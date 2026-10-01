#!/usr/bin/env python3
"""Render a device-pass manifest as an HTML evidence gallery.

Required: title, revision, target, scenarios.
Each scenario: name, mode, browser, viewport, status (pass/fail/blocked),
steps (strings), screenshots ({file, caption}); optional video (file) and
findings (strings). Optional top-level findings and limitations are lists of
strings. Artifact paths must be relative regular files inside the manifest
directory, with no symlinks. Screenshots must be structurally complete PNG,
JPEG, or WebP images.

By default the report is a single self-contained HTML file with every
screenshot embedded once. Use --linked for the older report that links to
the evidence files beside it. Video is never embedded.
"""

import argparse
import base64
import hashlib
import html
import json
import os
import re
import stat
import struct
import sys
import zlib
from pathlib import Path, PurePosixPath
from urllib.parse import quote

MAX_IMAGE_BYTES = 32 * 1024 * 1024
MAX_TOTAL_IMAGE_BYTES = 256 * 1024 * 1024
STATUSES = ('pass', 'fail', 'blocked')
DEFAULT_SUBTITLE = 'A visual record of the tested journeys. Open any capture for a closer look.'


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
    return total


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
        fd, relative = open_artifact(self.root, filename)
        data = read_artifact(fd, filename)
        mime = validate_image(data, filename)
        if not self.standalone:
            return quote(relative.as_posix(), safe='/')
        digest = hashlib.sha256(data).hexdigest()
        if digest not in self.payloads:
            self.total += len(data)
            if self.total > MAX_TOTAL_IMAGE_BYTES:
                raise ValueError(
                    f"Embedded screenshots exceed the {MAX_TOTAL_IMAGE_BYTES // (1024 * 1024)} MiB total limit "
                    f"at {filename}. Use --linked or split the pass; images are never downscaled or dropped.")
            self.payloads[digest] = {'mime': mime, 'data': base64.b64encode(data).decode('ascii')}
        return digest

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


def screenshot_html(images, screenshot, index):
    ref = images.add(screenshot['file'])
    caption = text(screenshot['caption'])
    if images.standalone:
        link, image = '#', f'<img data-img="{ref}" alt="{caption}">'
    else:
        link, image = ref, f'<img src="{ref}" alt="{caption}">'
    return f'<figure class="shot"><a href="{link}" aria-label="Open {caption}"><div class="image-stage">{image}</div><figcaption><span class="shot-number">{index:02d}</span><span>{caption}</span></figcaption></a></figure>'


def scenario_html(images, scenario, omitted):
    status = scenario['status']
    if status not in STATUSES:
        raise ValueError(f"Invalid scenario status: {status}")
    screenshots = scenario.get('screenshots', [])
    if status == 'pass' and not screenshots:
        raise ValueError(f"Passing scenario needs screenshots: {scenario['name']}")
    details = ' · '.join(text(scenario[key]) for key in ('mode', 'browser', 'viewport'))
    steps = ''.join(f'<li>{text(step)}</li>' for step in scenario['steps'])
    shots = ''.join(screenshot_html(images, shot, i + 1) for i, shot in enumerate(screenshots))
    findings = ''.join(f'<li>{text(item)}</li>' for item in string_list(scenario.get('findings'), f"Findings for {scenario['name']}"))
    findings = f'<div class="findings"><p class="eyebrow">Findings</p><ul>{findings}</ul></div>' if findings else ''
    video = ''
    if scenario.get('video'):
        relative = check_artifact(images.root, scenario['video'])
        if images.standalone:
            omitted.append(f"video {relative.as_posix()}")
            video = f'<p class="video-note">Video not included in this portable file: {text(relative.as_posix())}</p>'
        else:
            video = f'<video controls preload="metadata" src="{quote(relative.as_posix(), safe="/")}"></video>'
    mode = 'mobile' if 'mobile' in scenario['mode'].lower() else 'desktop'
    return f'<section class="scenario {mode}" data-mode="{mode}"><div class="scenario-head"><div><h3>{text(scenario["name"])}</h3><p class="scenario-meta">{details}</p></div><span class="badge {status}">{status}</span></div><details class="steps"><summary>Journey · {len(scenario["steps"])} recorded steps</summary><ol>{steps}</ol></details>{findings}<div class="images">{shots}</div>{video}</section>'


def outcome_summary(scenarios):
    counts = {status: sum(item['status'] == status for item in scenarios) for status in STATUSES}
    return ' · '.join(f'{counts[status]} {status}' for status in STATUSES)


def report_context(data, standalone, omitted):
    def block(title, items):
        if not items:
            return ''
        return f'<p class="eyebrow">{title}</p><ul>' + ''.join(f'<li>{text(item)}</li>' for item in items) + '</ul>'

    limitations = string_list(data.get('limitations'), 'limitations')
    findings = string_list(data.get('findings'), 'findings')
    body = f'<p class="revision mono">{text(data["revision"])}</p><p>{text(data["target"])}</p><p>Outcomes: {outcome_summary(data["scenarios"])}</p>'
    body += block('Findings', findings) + block('Limitations', limitations)
    if standalone:
        body += block('Not included in this file', omitted)
        return f'<details class="context" open><summary>Test environment, revision, findings & limitations</summary><div class="context-body">{body}</div></details>'
    return f'<details class="context"><summary>Test environment, revision & limitations</summary><div class="context-body">{body}</div></details>'


def report_stats(data, standalone):
    scenarios = data['scenarios']
    passed = sum(item['status'] == 'pass' for item in scenarios)
    captures = sum(len(item.get('screenshots', [])) for item in scenarios)
    source = '<strong>Embedded</strong><span>Self-contained file</span>' if standalone else '<strong>Local</strong><span>Evidence source</span>'
    return f'<div class="stats"><div class="stat"><strong>{passed}/{len(scenarios)}</strong><span>Journeys passed</span></div><div class="stat"><strong>{captures:02d}</strong><span>Saved captures</span></div><div class="stat">{source}</div></div>'


def footer(standalone, omitted):
    if not standalone:
        return 'Pickforge · Device pass · Saved evidence, outside the application repository'
    missing = f" Not included: {text(', '.join(omitted))}." if omitted else ' Nothing was left out.'
    return f'Pickforge · Device pass · Self-contained file with every screenshot embedded.{missing}'


def script_hash(script):
    digest = hashlib.sha256(script.encode('utf-8')).digest()
    return 'sha256-' + base64.b64encode(digest).decode('ascii')


def render(manifest, standalone=True):
    """Return (html, images) for a manifest; never writes any file."""
    manifest = Path(manifest)
    data = json.loads(manifest.read_text(encoding='utf-8'))
    root = manifest.parent.resolve()
    images = Images(root, standalone)
    omitted = []
    scenarios = ''.join(scenario_html(images, item, omitted) for item in data['scenarios'])
    assets = Path(__file__).parent
    template = (assets / 'report.html').read_text(encoding='utf-8')
    script = (assets / 'report.js').read_text(encoding='utf-8')
    if '</script' in script.lower():
        raise ValueError('report.js must not contain a closing script tag')
    head = ''
    noscript = ''
    if standalone:
        policy = f"default-src 'none'; img-src blob:; style-src 'unsafe-inline'; script-src '{script_hash(script)}'; base-uri 'none'; form-action 'none'"
        head = f'<meta http-equiv="Content-Security-Policy" content="{text(policy)}">'
        noscript = '<noscript><p class="empty">Screenshots in this file need JavaScript to display. Allow scripts for this local file, or ask for the linked evidence folder.</p></noscript>'
    values = {
        'HEAD': head, 'WORKSPACE': 'Self-contained evidence file' if standalone else 'Local evidence workspace', 'TITLE': text(data['title']), 'STATS': report_stats(data, standalone),
        'SUBTITLE': text(data.get('subtitle', DEFAULT_SUBTITLE)),
        'CONTEXT': report_context(data, standalone, omitted), 'SCENARIOS': scenarios,
        'NOSCRIPT': noscript, 'FOOTER': footer(standalone, omitted),
        'IMAGES': images.data_block(), 'CSS': (assets / 'report.css').read_text(encoding='utf-8'), 'JS': script,
        'CAPTURES': str(sum(len(item.get('screenshots', [])) for item in data['scenarios'])),
    }
    return re.sub(r'\{\{([A-Z]+)\}\}', lambda match: values[match[1]], template), images


def size(count):
    for unit in ('B', 'KiB', 'MiB'):
        if count < 1024 or unit == 'MiB':
            return f'{count} B' if unit == 'B' else f'{count:.1f} {unit}'
        count /= 1024


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('manifest', type=Path)
    parser.add_argument('--linked', action='store_true', help='link screenshots and video as files beside the report instead of embedding them')
    args = parser.parse_args()
    try:
        report, images = render(args.manifest, standalone=not args.linked)
    except (ValueError, OSError) as error:
        print(f'error: {error}', file=sys.stderr)
        return 1
    output = args.manifest.with_suffix('.html')
    output.write_text(report, encoding='utf-8')
    print(output)
    print(f'size: {size(output.stat().st_size)}')
    if args.linked:
        print('mode: linked; keep the screenshots and video beside the report when sharing')
    else:
        print(f'embedded images: {len(images.payloads)} unique, {size(images.total)} of original bytes')
    return 0


if __name__ == '__main__':
    sys.exit(main())
