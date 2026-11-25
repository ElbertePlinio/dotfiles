#!/usr/bin/env python3
"""Render a device-pass manifest as an HTML evidence page of comparison cards.

Usage: render_report.py <manifest.json> [--linked] [--cards]

Required: title, revision, target, cards. Each card has an id, a title, and
at least one pane among device, figma, and widget. A pane is a path or an
object with src and optional scale, cropTopPt, cropBottomPt, caption, and
label; a kind can hold a list of panes. Optional: intro, environment,
links, defaults, videos, journeys, findings, limitations. See
references/gallery.md for the schema.

By default the page is one self-contained HTML file with every image
embedded once. --linked links the files beside it instead. Videos are never
embedded; they play when the page sits in the evidence folder. --cards also
exports each card as cards/<nn>-<id>.png with headless Chrome or Chromium.
Artifact paths must be relative regular files inside the manifest folder,
with no symlinks, and images must be complete PNG, JPEG, or WebP files.
"""

import argparse
import base64
import hashlib
import html
import json
import os
import re
import shutil
import stat
import struct
import subprocess
import sys
import tempfile
import zlib
from pathlib import Path, PurePosixPath
from urllib.parse import quote

MAX_IMAGE_BYTES = 32 * 1024 * 1024
MAX_TOTAL_IMAGE_BYTES = 256 * 1024 * 1024
MAX_PNG_RAW_BYTES = 1024 * 1024 * 1024
STATUSES = ('pass', 'fail', 'blocked')
KINDS = ('device', 'figma', 'widget')
LABELS = {'device': 'Device', 'figma': 'Figma', 'widget': 'Widget'}
CARD_ID = re.compile(r'[a-z0-9][a-z0-9-]{0,79}')
VIDEO_TYPES = {'.mp4': 'video/mp4', '.webm': 'video/webm', '.mov': 'video/quicktime'}
EXPORT_WIDTH = 1600
CHROMES = (
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    '/Applications/Chromium.app/Contents/MacOS/Chromium',
    'google-chrome-stable', 'google-chrome', 'chromium', 'chromium-browser',
)


def text(value):
    return html.escape(str(value), quote=True)




def image_mime(data):
    if data.startswith(b'\x89PNG\r\n\x1a\n'):
        return 'image/png'
    if data.startswith(b'\xff\xd8\xff'):
        return 'image/jpeg'
    if len(data) >= 12 and data[:4] == b'RIFF' and data[8:12] == b'WEBP':
        return 'image/webp'
    return None


PNG_CHANNELS = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}
PNG_DEPTHS = {0: (1, 2, 4, 8, 16), 2: (8, 16), 3: (1, 2, 4, 8), 4: (8, 16), 6: (8, 16)}
ADAM7 = ((0, 0, 8, 8), (4, 0, 8, 8), (0, 4, 4, 8), (2, 0, 4, 4), (0, 2, 2, 4), (1, 0, 2, 2), (0, 1, 1, 2))


def png_raw_size(header):
    """Expected decompressed IDAT size from IHDR, or None if IHDR is invalid."""
    if len(header) != 13:
        return None
    width, height, depth, color, compression, filtering, interlace = struct.unpack('>IIBBBBB', header)
    if 0 in (width, height) or (compression, filtering) != (0, 0):
        return None
    if depth not in PNG_DEPTHS.get(color, ()) or interlace > 1:
        return None
    bits = depth * PNG_CHANNELS[color]
    passes = ADAM7 if interlace else ((0, 0, 1, 1),)
    total = 0
    for x, y, dx, dy in passes:
        columns, rows = (width - x + dx - 1) // dx, (height - y + dy - 1) // dy
        if columns and rows:
            total += rows * (1 + (columns * bits + 7) // 8)
    return total if total <= MAX_PNG_RAW_BYTES else None


def png_stream_complete(compressed, expected):
    """True if the IDAT data is one complete zlib stream of exactly the expected size."""
    stream, produced = zlib.decompressobj(), 0
    try:
        while True:
            out = stream.decompress(compressed, 1 << 20)
            produced += len(out)
            compressed = stream.unconsumed_tail
            if produced > expected or stream.eof or not (out or compressed):
                break
    except zlib.error:
        return False
    return stream.eof and not stream.unused_data and produced == expected


def png_chunks(data):
    """Yield (kind, body) for each CRC-checked chunk through IEND, then (None, None) if anything is malformed or follows."""
    pos = 8
    while pos + 12 <= len(data):
        length, kind = struct.unpack('>I4s', data[pos:pos + 8])
        end = pos + 12 + length
        body = data[pos + 8:end - 4]
        if end > len(data) or zlib.crc32(kind + body) != struct.unpack('>I', data[end - 4:end])[0]:
            break
        yield kind, body
        pos = end
        if kind == b'IEND':
            break
    if pos != len(data):
        yield None, None


def png_is_valid(data):
    """IHDR first, every chunk CRC intact, IEND last, and IDAT data that inflates fully."""
    chunks = list(png_chunks(data))
    if not chunks or chunks[0][0] != b'IHDR' or chunks[-1][0] != b'IEND':
        return False
    expected = png_raw_size(chunks[0][1])
    idat = b''.join(body for kind, body in chunks if kind == b'IDAT')
    return expected is not None and bool(idat) and png_stream_complete(idat, expected)


JPEG_FRAMES = set(range(0xC0, 0xD0)) - {0xC4, 0xC8, 0xCC}


def jpeg_segment(data, pos):
    """Return the marker at pos and the next position, or (None, None) if malformed."""
    if data[pos] != 0xFF:
        return None, None
    marker = data[pos + 1]
    if marker == 0xFF:
        return marker, pos + 1
    if 0xD0 <= marker <= 0xD7 or marker == 0x01:
        return marker, pos + 2
    length = int.from_bytes(data[pos + 2:pos + 4], 'big')
    if length < 2 or pos + 2 + length > len(data) - 2:
        return None, None
    return marker, pos + 2 + length


def jpeg_frame_is_valid(segment):
    """SOF: precision 8 or 12, nonzero size, 1 to 4 components, and room for each."""
    if len(segment) < 6:
        return False
    precision, height, width, components = struct.unpack('>BHHB', segment[:6])
    return precision in (8, 12) and 0 not in (height, width) and components in range(1, 5) and len(segment) >= 6 + 3 * components


def jpeg_scan_is_valid(segment):
    """SOS: 1 to 4 components and a length of exactly 6 + 2 per component."""
    return len(segment) >= 1 and 1 <= segment[0] <= 4 and len(segment) == 4 + 2 * segment[0]


def jpeg_is_valid(data):
    """SOI, a valid frame header, a valid scan header with entropy data, and EOI at the end."""
    if len(data) < 4 or data[:2] != b'\xff\xd8' or data[-2:] != b'\xff\xd9':
        return False
    pos, frame = 2, False
    while pos + 4 <= len(data) - 2:
        start = pos
        marker, pos = jpeg_segment(data, pos)
        if marker is None or marker in (0xD8, 0xD9):
            return False
        segment = data[start + 4:pos]
        if marker == 0xDA:
            return frame and jpeg_scan_is_valid(segment) and pos < len(data) - 2
        if marker in JPEG_FRAMES:
            if not jpeg_frame_is_valid(segment):
                return False
            frame = True
    return False


def riff_chunks(data, pos, end):
    """Yield (fourcc, payload) for each chunk that fits; stop at the first that does not."""
    while pos + 8 <= end:
        size = int.from_bytes(data[pos + 4:pos + 8], 'little')
        if pos + 8 + size > end:
            yield None, None
            return
        yield data[pos:pos + 4], data[pos + 8:pos + 8 + size]
        pos += 8 + size + (size & 1)


def webp_bitstream_is_valid(kind, payload):
    """VP8 needs its frame start code and a nonzero size; VP8L needs its signature."""
    if kind == b'VP8 ':
        if len(payload) < 10 or payload[3:6] != b'\x9d\x01\x2a':
            return False
        width, height = struct.unpack('<HH', payload[6:10])
        return bool(width & 0x3FFF and height & 0x3FFF)
    return kind == b'VP8L' and len(payload) >= 5 and payload[0] == 0x2F


def webp_frame_is_valid(data, pos, end, animated):
    """The first image chunk after VP8X is a valid VP8, VP8L, or animation frame."""
    for kind, payload in riff_chunks(data, pos, end):
        if kind in (b'VP8 ', b'VP8L'):
            return webp_bitstream_is_valid(kind, payload)
        if kind == b'ANMF' and animated:
            return len(payload) >= 16 and webp_frame_is_valid(payload, 16, len(payload), False)
        if kind is None:
            return False
    return False


def webp_is_valid(data):
    """RIFF size matches the file, and the image chunks carry a plausible bitstream header."""
    if len(data) < 20 or int.from_bytes(data[4:8], 'little') + 8 != len(data):
        return False
    kind, payload = next(riff_chunks(data, 12, len(data)), (None, None))
    if kind in (b'VP8 ', b'VP8L'):
        return webp_bitstream_is_valid(kind, payload)
    if kind != b'VP8X' or len(payload) != 10:
        return False
    return webp_frame_is_valid(data, 30, len(data), bool(payload[0] & 0x02))


def jpeg_size(data):
    pos = 2
    while pos + 4 <= len(data) - 2:
        start = pos
        marker, pos = jpeg_segment(data, pos)
        if marker in JPEG_FRAMES:
            height, width = struct.unpack('>HH', data[start + 5:start + 9])
            return width, height
    raise ValueError('JPEG has no frame header')


def webp_size(data):
    kind, payload = next(riff_chunks(data, 12, len(data)))
    if kind == b'VP8 ':
        width, height = struct.unpack('<HH', payload[6:10])
        return width & 0x3FFF, height & 0x3FFF
    if kind == b'VP8L':
        bits = int.from_bytes(payload[1:5], 'little')
        return (bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1
    return int.from_bytes(payload[4:7], 'little') + 1, int.from_bytes(payload[7:10], 'little') + 1


def image_size(data, mime):
    """Pixel width and height of an image that already passed validation."""
    if mime == 'image/png':
        return struct.unpack('>II', data[16:24])
    if mime == 'image/jpeg':
        return jpeg_size(data)
    return webp_size(data)


IMAGE_CHECKS = {'image/png': ('PNG', png_is_valid), 'image/jpeg': ('JPEG', jpeg_is_valid), 'image/webp': ('WebP', webp_is_valid)}


def validate_image(data, filename):
    """Return the MIME type of a structurally complete PNG, JPEG, or WebP."""
    mime = image_mime(data)
    if not mime:
        raise ValueError(f"Unsupported screenshot type (use PNG, JPEG, or WebP): {filename}")
    label, check = IMAGE_CHECKS[mime]
    if not check(data):
        raise ValueError(f"Screenshot is not a complete {label} image (truncated, corrupt, or has data after the image end): {filename}")
    return mime


def has_unsafe_parts(name, path):
    return '\\' in name or not path.parts or '..' in path.parts


def artifact_name(filename):
    """Return the relative path if it is a plain path inside the evidence folder."""
    name = str(filename)
    path = PurePosixPath(name)
    if path.is_absolute() or has_unsafe_parts(name, path):
        raise ValueError(f"Artifact must stay inside the evidence folder: {filename}")
    return path


def check_component(info, last, filename):
    """Reject symlinks, a non-regular final file, and non-directory parents."""
    if stat.S_ISLNK(info.st_mode):
        raise ValueError(f"Artifact must not be a symlink: {filename}")
    if last:
        if not stat.S_ISREG(info.st_mode):
            raise ValueError(f"Artifact must be a regular file: {filename}")
    elif not stat.S_ISDIR(info.st_mode):
        raise ValueError(f"Missing evidence artifact: {filename}")


def open_artifact(root, filename):
    """Open a regular file inside root, walking pinned directory descriptors.

    Every component is opened relative to its parent's descriptor with
    O_NOFOLLOW, so swapping any directory for a symlink after it was checked
    cannot redirect the read outside the evidence folder.
    """
    path = artifact_name(filename)
    fd = os.open(root, os.O_RDONLY | os.O_DIRECTORY)
    try:
        for index, part in enumerate(path.parts):
            last = index == len(path.parts) - 1
            try:
                info = os.stat(part, dir_fd=fd, follow_symlinks=False)
            except FileNotFoundError:
                raise ValueError(f"Missing evidence artifact: {filename}") from None
            check_component(info, last, filename)
            flags = os.O_RDONLY | os.O_NOFOLLOW | (os.O_NONBLOCK if last else os.O_DIRECTORY)
            try:
                child = os.open(part, flags, dir_fd=fd)
            except OSError:
                raise ValueError(f"Evidence artifact changed while rendering: {filename}") from None
            os.close(fd)
            fd = child
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            raise ValueError(f"Artifact must be a regular file: {filename}")
    except BaseException:
        os.close(fd)
        raise
    return fd, path


def check_artifact(root, filename):
    fd, path = open_artifact(root, filename)
    os.close(fd)
    return path


def read_artifact(fd, filename):
    with os.fdopen(fd, 'rb') as handle:
        data = handle.read(MAX_IMAGE_BYTES + 1)
    if len(data) > MAX_IMAGE_BYTES:
        raise ValueError(
            f"Screenshot exceeds the {MAX_IMAGE_BYTES // (1024 * 1024)} MiB per-image limit: {filename}. "
            "Images are never downscaled; split or recapture it.")
    return data


class Images:
    """Embedded screenshot payloads, stored once per unique content hash."""

    def __init__(self, root, standalone):
        self.root = root
        self.standalone = standalone
        self.payloads = {}
        self.total = 0

    def add(self, filename):
        """Return (reference, width, height) for a validated image."""
        fd, relative = open_artifact(self.root, filename)
        data = read_artifact(fd, filename)
        mime = validate_image(data, filename)
        width, height = image_size(data, mime)
        if not self.standalone:
            return quote(relative.as_posix(), safe='/'), width, height
        digest = hashlib.sha256(data).hexdigest()
        if digest not in self.payloads:
            self.total += len(data)
            if self.total > MAX_TOTAL_IMAGE_BYTES:
                raise ValueError(
                    f"Embedded screenshots exceed the {MAX_TOTAL_IMAGE_BYTES // (1024 * 1024)} MiB total limit "
                    f"at {filename}. Use --linked or split the pass; images are never downscaled or dropped.")
            self.payloads[digest] = {'mime': mime, 'data': base64.b64encode(data).decode('ascii')}
        return digest, width, height

    def data_block(self):
        if not self.standalone:
            return ''
        payload = json.dumps(self.payloads, separators=(',', ':'))
        payload = payload.replace('<', '\\u003c').replace('>', '\\u003e').replace('&', '\\u0026')
        return f'<script type="application/json" id="images">{payload}</script>'


def string_list(value, label):
    if value is None:
        return []
    if not isinstance(value, list) or not all(isinstance(item, str) for item in value):
        raise ValueError(f"{label} must be a list of strings")
    return value


def number(value, label, minimum):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or value < minimum:
        raise ValueError(f"{label} must be a number of at least {minimum}")
    return value


def fmt(value):
    return f'{value:.1f}'.rstrip('0').rstrip('.')


def pane_specs(card, kind, defaults):
    """Yield merged pane settings for one kind of a card."""
    specs = card.get(kind)
    if not specs:
        return
    for spec in specs if isinstance(specs, list) else [specs]:
        if isinstance(spec, str):
            spec = {'src': spec}
        if not isinstance(spec, dict) or not isinstance(spec.get('src'), str):
            raise ValueError(f"Card {card['id']}: each {kind} pane needs a src path")
        yield {**defaults.get(kind, {}), **spec}


def pane(images, card, kind, spec):
    ref, width, height = images.add(spec['src'])
    label = f"Card {card['id']} {kind}"
    scale = number(spec.get('scale', 1), f'{label} scale', 0.1)
    top = number(spec.get('cropTopPt', 0), f'{label} cropTopPt', 0)
    bottom = number(spec.get('cropBottomPt', 0), f'{label} cropBottomPt', 0)
    w, h = width / scale, height / scale - top - bottom
    if h <= 0:
        raise ValueError(f"{label}: the crop removes the whole image ({spec['src']})")
    return {'kind': kind, 'ref': ref, 'w': w, 'h': h, 'top': top, 'label': spec.get('label', LABELS[kind]),
            'caption': spec.get('caption', '')}


def frame_html(images, p, alt, extra=''):
    if images.standalone:
        source = f'data-img="{p["ref"]}"'
    else:
        source = f'src="{text(p["ref"])}"'
    style = f'--w:{fmt(p["w"])};--h:{fmt(p["h"])};--top:{fmt(p["top"])}'
    return f'<div class="frame{extra}" style="{style}"><img {source} alt="{text(alt)}"></div>'


def card_html(images, card, defaults):
    if not isinstance(card.get('id'), str) or not CARD_ID.fullmatch(card['id']):
        raise ValueError(f"Card id must be lowercase letters, digits and dashes: {card.get('id')!r}")
    if not isinstance(card.get('title'), str):
        raise ValueError(f"Card {card['id']} needs a title")
    panes = [pane(images, card, kind, spec) for kind in KINDS for spec in pane_specs(card, kind, defaults)]
    if not panes:
        raise ValueError(f"Card {card['id']} needs a device, figma, or widget pane")
    figures = []
    for p in panes:
        caption = f'<span class="cap">{text(p["caption"])}</span>' if p['caption'] else ''
        alt = f'{p["label"]}: {card["title"]}'
        figures.append(
            f'<figure class="pane" data-kind="{p["kind"]}" style="--w:{fmt(p["w"])}"><figcaption><b>{text(p["label"])}</b>'
            f'<span class="dim">{fmt(p["w"])} × {fmt(p["h"])} pt</span>{caption}</figcaption>'
            f'<button class="open" type="button" aria-label="Open {text(alt)}">{frame_html(images, p, alt)}</button></figure>')
    overlay = ''
    first = {}
    for p in panes:
        first.setdefault(p['kind'], p)
    if 'device' in first and 'figma' in first:
        d, f = first['device'], first['figma']
        overlay = (
            f'<details class="overlay"><summary>Overlay {text(d["label"])} on {text(f["label"])}</summary>'
            f'<label>{text(d["label"])} opacity <input type="range" min="0" max="100" value="50"></label>'
            f'<div class="stack">{frame_html(images, f, "")}{frame_html(images, d, "", " top")}</div></details>')
    desc = f'<p class="desc">{text(card["desc"])}</p>' if card.get('desc') else ''
    note = f'<p class="note">{text(card["note"])}</p>' if card.get('note') else ''
    return (f'<section class="card" id="{card["id"]}"><h2>{text(card["title"])}</h2>{desc}'
            f'<div class="panes">{"".join(figures)}</div>{overlay}{note}</section>')


def video_html(images, video, omitted):
    if not isinstance(video, dict) or not isinstance(video.get('src'), str):
        raise ValueError('Each video needs a src path')
    relative = check_artifact(images.root, video['src'])
    kind = VIDEO_TYPES.get(relative.suffix.lower())
    if not kind:
        raise ValueError(f"Video must be MP4, WebM, or MOV: {video['src']}")
    src = quote(relative.as_posix(), safe='/')
    if images.standalone:
        omitted.append(relative.as_posix())
    title = text(video.get('title', relative.name))
    desc = f'<p class="desc">{text(video["desc"])}</p>' if video.get('desc') else ''
    return (f'<section class="video"><h2>{title}</h2>{desc}<video controls muted playsinline preload="metadata">'
            f'<source src="{src}" type="{kind}"></video><p class="file mono">{text(relative.as_posix())}</p></section>')


def journey_html(journey):
    for key in ('name', 'mode', 'browser', 'viewport', 'status'):
        if not isinstance(journey.get(key), str):
            raise ValueError(f"Each journey needs {key}")
    if journey['status'] not in STATUSES:
        raise ValueError(f"Invalid journey status: {journey['status']}")
    steps = ''.join(f'<li>{text(step)}</li>' for step in string_list(journey.get('steps'), f"Steps for {journey['name']}"))
    findings = ''.join(f'<li>{text(item)}</li>' for item in string_list(journey.get('findings'), f"Findings for {journey['name']}"))
    meta = ' · '.join(text(journey[key]) for key in ('mode', 'browser', 'viewport'))
    body = f'<ol>{steps}</ol>' if steps else ''
    body += f'<ul class="findings">{findings}</ul>' if findings else ''
    return (f'<details class="journey"><summary><span class="status {journey["status"]}">{journey["status"]}</span>'
            f'<b>{text(journey["name"])}</b><span class="dim">{meta}</span></summary>{body}</details>')


def summary_html(data, omitted):
    rows = [('Revision', data['revision']), ('Target', data['target'])]
    rows += [('Environment', item) for item in string_list(data.get('environment'), 'environment')]
    facts = ''.join(f'<dt>{label}</dt><dd>{text(value)}</dd>' for label, value in rows)
    journeys = data.get('journeys') or []
    if not isinstance(journeys, list):
        raise ValueError('journeys must be a list')
    blocks = ''.join(journey_html(item) for item in journeys)
    for title, key in (('Findings', 'findings'), ('Limitations', 'limitations')):
        items = string_list(data.get(key), key)
        if items:
            blocks += f'<h3>{title}</h3><ul>' + ''.join(f'<li>{text(item)}</li>' for item in items) + '</ul>'
    if omitted:
        blocks += '<h3>Kept beside this file</h3><ul>' + ''.join(
            f'<li class="mono">{text(item)}</li>' for item in omitted) + '</ul>'
    intro = f'<p class="intro">{text(data["intro"])}</p>' if data.get('intro') else ''
    return f'<section class="summary">{intro}<dl>{facts}</dl>{blocks}</section>'


def links_html(links):
    if not isinstance(links, list):
        raise ValueError('links must be a list')
    out = []
    for link in links:
        url = str(link.get('url', '')) if isinstance(link, dict) else ''
        if not re.match(r'https?://', url):
            raise ValueError(f'Links need an http or https url: {link!r}')
        out.append(f'<a href="{text(url)}" target="_blank" rel="noopener">{text(link.get("label", url))}</a>')
    return ''.join(out)


def script_hash(script):
    digest = hashlib.sha256(script.encode('utf-8')).digest()
    return 'sha256-' + base64.b64encode(digest).decode('ascii')


def load(manifest):
    data = json.loads(Path(manifest).read_text(encoding='utf-8'))
    for key in ('title', 'revision', 'target'):
        if not isinstance(data.get(key), str) or not data[key].strip():
            raise ValueError(f"Manifest needs {key}")
    cards = data.get('cards')
    if not isinstance(cards, list) or not cards:
        raise ValueError('Manifest needs at least one card')
    ids = [card.get('id') for card in cards if isinstance(card, dict)]
    if len(ids) != len(cards):
        raise ValueError('Each card must be an object')
    if len(set(ids)) != len(ids):
        raise ValueError('Card ids must be unique')
    defaults = data.get('defaults', {})
    if not isinstance(defaults, dict) or not all(isinstance(v, dict) for v in defaults.values()):
        raise ValueError('defaults must map a pane kind to its settings')
    return data


def render(manifest, standalone=True, only=None):
    """Return (html, images) for a manifest; never writes any file.

    only=<card id> renders that card alone, linked and without page chrome, for the PNG export.
    """
    manifest = Path(manifest)
    data = load(manifest)
    root = manifest.parent.resolve()
    images = Images(root, standalone and only is None)
    assets = Path(__file__).parent
    css = (assets / 'report.css').read_text(encoding='utf-8')
    cards = [card for card in data['cards'] if only is None or card['id'] == only]
    cards_html = ''.join(card_html(images, card, data.get('defaults', {})) for card in cards)
    if only is not None:
        base = text(root.as_uri() + '/')
        return (f'<!doctype html><html lang="en" class="export"><head><meta charset="utf-8"><base href="{base}">'
                f'<style>{css}</style></head><body><main>{cards_html}</main></body></html>'), images
    omitted = []
    videos = ''.join(video_html(images, video, omitted) for video in data.get('videos') or [])
    script = (assets / 'report.js').read_text(encoding='utf-8')
    if '</script' in script.lower():
        raise ValueError('report.js must not contain a closing script tag')
    head = ''
    if images.standalone:
        policy = (f"default-src 'none'; img-src blob:; media-src 'self' file:; style-src 'unsafe-inline'; "
                  f"script-src '{script_hash(script)}'; base-uri 'none'; form-action 'none'")
        head = f'<meta http-equiv="Content-Security-Policy" content="{text(policy)}">'
    values = {
        'HEAD': head, 'TITLE': text(data['title']), 'LINKS': links_html(data.get('links') or []),
        'SUMMARY': summary_html(data, omitted), 'VIDEOS': videos, 'CARDS': cards_html,
        'IMAGES': images.data_block(), 'CSS': css, 'JS': script,
    }
    template = (assets / 'report.html').read_text(encoding='utf-8')
    return re.sub(r'\{\{([A-Z]+)\}\}', lambda match: values[match[1]], template), images


def find_chrome():
    configured = os.environ.get('CHROME')
    for candidate in ([configured] if configured else []) + list(CHROMES):
        path = candidate if os.path.isabs(candidate) else shutil.which(candidate)
        if path and os.access(path, os.X_OK):
            return path
    raise ValueError('Card export needs Chrome or Chromium; set CHROME to its path')


def chrome(binary, page, *args):
    command = [binary, '--headless=new', '--disable-gpu', '--hide-scrollbars', '--no-first-run',
               '--allow-file-access-from-files', '--virtual-time-budget=4000', *args, page.as_uri()]
    return subprocess.run(command, check=True, capture_output=True, text=True, timeout=120).stdout


MEASURE = ("<script>addEventListener('load',()=>{const r=document.querySelector('.card').getBoundingClientRect();"
           "document.body.dataset.size=Math.ceil(r.right+24)+'x'+Math.ceil(r.bottom+24)})</script></body>")


def export_cards(manifest):
    """Write cards/<nn>-<id>.png beside the manifest: one dark PNG per card, at 2x, cropped to the card."""
    manifest = Path(manifest)
    data = load(manifest)
    binary = find_chrome()
    out = manifest.parent / 'cards'
    out.mkdir(exist_ok=True)
    for old in out.glob('*.png'):
        old.unlink()
    written = []
    with tempfile.TemporaryDirectory() as tmp:
        for n, card in enumerate(data['cards'], 1):
            page_html, _ = render(manifest, only=card['id'])
            page = Path(tmp) / f"{card['id']}.html"
            page.write_text(page_html.replace('</body>', MEASURE), encoding='utf-8')
            found = re.search(r'data-size="(\d+)x(\d+)"', chrome(binary, page, f'--window-size={EXPORT_WIDTH},8000', '--dump-dom'))
            if not found:
                raise ValueError(f"Could not measure card {card['id']}")
            png = out / f"{n:02d}-{card['id']}.png"
            page.write_text(page_html, encoding='utf-8')
            chrome(binary, page, f'--window-size={found[1]},{found[2]}', '--force-device-scale-factor=2',
                   f'--screenshot={png}')
            written.append(png)
    return written


def size(count):
    for unit in ('B', 'KiB', 'MiB'):
        if count < 1024 or unit == 'MiB':
            return f'{count} B' if unit == 'B' else f'{count:.1f} {unit}'
        count /= 1024


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('manifest', type=Path)
    parser.add_argument('--linked', action='store_true', help='link images and videos beside the page instead of embedding images')
    parser.add_argument('--cards', action='store_true', help='also export one PNG per card to cards/ for a PR')
    args = parser.parse_args()
    try:
        report, images = render(args.manifest, standalone=not args.linked)
        output = args.manifest.with_suffix('.html')
        output.write_text(report, encoding='utf-8')
        print(output)
        print(f'size: {size(output.stat().st_size)}')
        if args.linked:
            print('mode: linked; keep the images and videos beside the page when sharing')
        else:
            print(f'embedded images: {len(images.payloads)} unique, {size(images.total)} of original bytes')
        if args.cards:
            for png in export_cards(args.manifest):
                print(png)
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        print(f'error: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
