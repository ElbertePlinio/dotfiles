#!/usr/bin/env python3
import sys
sys.dont_write_bytecode = True
import base64
import hashlib
import importlib.util
import json
import re
import shutil
import struct
import subprocess
import tempfile
import unittest
import zlib
from unittest import mock
from pathlib import Path

SOURCE = Path(__file__).resolve().parents[1] / "dot_agents/skills/device-pass/scripts/render_report.py"
spec = importlib.util.spec_from_file_location("render_report", SOURCE)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def png(width, height, rgb):
    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)
    rows = b"".join(b"\x00" + bytes(rgb) * width for _ in range(height))
    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b"")


# 16x16 baseline JPEG and lossy WebP from ImageMagick; both render in Chromium.
JPEG = base64.b64decode(
    "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAA0JCgsKCA0LCgsODg0PEyAVExISEyccHhcgLikxMC4pLSwzOko+MzZGNywtQFdBRkxOUlNSMj5aYVpQYEpRUk//"
    "2wBDAQ4ODhMREyYVFSZPNS01T09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT0//wAARCAAQABADASIAAhEBAxEB/8QAFQAB"
    "AQAAAAAAAAAAAAAAAAAAAAT/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFAEBAAAAAAAAAAAAAAAAAAAABv/EABQRAQAAAAAAAAAAAAAAAAAAAAD/2gAMAwEAAhED"
    "EQA/ALgBcqf/2Q==")
WEBP = base64.b64decode("UklGRjoAAABXRUJQVlA4IC4AAADwAQCdASoQABAAAoBCJaACdLoB+AAEyAAA/su3/9CT8TZ4mz4RX/kFpXLd2AAA")
# 21x11 lossless WebP and 5x3 Adam7-interlaced PNG from ImageMagick.
WEBP_LOSSLESS = base64.b64decode(
    "UklGRm4AAABXRUJQVlA4TGIAAAAvFIACEFcQaiJJUvzbu+wyvmcW8GoiSVKjZ4DvnjH77AUCicA5jx4fhg9fdNmUmpYabqnDPQRVsW1T915vfyqooIIKKqigg"
    "goqCLozRPQ/hRpoBxvgJvgFYUM8kC7kB+VDBQ==")
PNG_INTERLACED = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAUAAAADCAIAAAGjU2I5AAAAGUlEQVQI12P4z8DAAMWM/xmgAMpiQuHBAQDf2AYAOX4a5QAAAABJRU5ErkJggg==")

EVIL = '</script><script>alert(1)</script>"\'<img src=x onerror=alert(2)>'


def write_fixture(root):
    root.mkdir(parents=True, exist_ok=True)
    (root / "shots").mkdir()
    (root / "shots/desktop-home.png").write_bytes(png(320, 200, (40, 40, 48)))
    (root / "shots/desktop-form.png").write_bytes(png(320, 200, (255, 122, 26)))
    (root / "shots/mobile-menu.png").write_bytes(png(90, 190, (85, 201, 147)))
    (root / "shots/mobile-copy.png").write_bytes((root / "shots/mobile-menu.png").read_bytes())
    (root / "shots/error.webp").write_bytes(WEBP)
    (root / "shots/receipt.jpg").write_bytes(JPEG)
    (root / "shots/run.webm").write_bytes(b"\x1aE\xdf\xa3 fake video")
    manifest = {
        "title": "Checkout pass ✓ — café 日本語",
        "revision": "abc1234 (synthetic)",
        "target": "http://localhost:3000 · Chromium 140 · DPR 1 and 3, touch on mobile",
        "findings": ["Top-level finding: " + EVIL],
        "limitations": ["Safari and physical devices not tested", EVIL],
        "scenarios": [
            {"name": "Desktop checkout", "mode": "desktop", "browser": "Chromium 140", "viewport": "1440x1000",
             "status": "pass", "steps": ["Open home", "Submit form"],
             "screenshots": [{"file": "shots/desktop-home.png", "caption": "Home ünïcödé 🚀"},
                             {"file": "shots/desktop-form.png", "caption": EVIL},
                             {"file": "shots/desktop-home.png", "caption": "Home again, same file"}]},
            {"name": "Mobile menu", "mode": "mobile emulation", "browser": "Chromium 140", "viewport": "390x844",
             "status": "fail", "steps": ["Open menu"], "findings": ["Menu overlaps footer"],
             "screenshots": [{"file": "shots/mobile-menu.png", "caption": "Menu open"},
                             {"file": "shots/mobile-copy.png", "caption": "Identical bytes, other file"},
                             {"file": "shots/error.webp", "caption": "Error state (WebP)"},
                             {"file": "shots/receipt.jpg", "caption": "Receipt (JPEG)"}],
             "video": "shots/run.webm"},
            {"name": "Payment provider", "mode": "desktop", "browser": "Chromium 140", "viewport": "1440x1000",
             "status": "blocked", "steps": ["Sandbox credentials unavailable"], "screenshots": []},
        ],
    }
    (root / "pass.json").write_text(json.dumps(manifest, ensure_ascii=False), encoding="utf-8")
    return root / "pass.json"


def snapshot(root):
    return {str(p): (p.read_bytes(), p.stat().st_mtime_ns) for p in sorted(root.rglob("*")) if p.is_file()}


def embedded(report):
    match = re.search(r'<script type="application/json" id="images">(.*?)</script>', report, re.S)
    return json.loads(match[1])


class DevicePassReportTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.root = self.base / "evidence"
        self.manifest = write_fixture(self.root)

    def edit(self, change):
        data = json.loads(self.manifest.read_text(encoding="utf-8"))
        change(data)
        self.manifest.write_text(json.dumps(data), encoding="utf-8")

    def set_first_file(self, name):
        self.edit(lambda data: data["scenarios"][0]["screenshots"][0].update(file=name))

    def assert_rejected(self, name, message):
        self.set_first_file(name)
        for standalone in (True, False):
            with self.assertRaisesRegex(ValueError, message):
                module.render(self.manifest, standalone=standalone)

    def test_statuses_unicode_and_context_render(self):
        report, _ = module.render(self.manifest)
        for status in ("pass", "fail", "blocked"):
            self.assertIn(f'<span class="badge {status}">{status}</span>', report)
        self.assertIn("Home ünïcödé 🚀", report)
        self.assertIn("café 日本語", report)
        self.assertIn("Outcomes: 1 pass · 1 fail · 1 blocked", report)
        self.assertIn("Menu overlaps footer", report)
        self.assertIn("Safari and physical devices not tested", report)
        self.assertIn("390x844", report)
        self.assertIn('<details class="context" open>', report)
        self.assertIn("Self-contained file", report)
        self.assertIn("<span>Self-contained evidence file</span></header>", report)
        self.assertNotIn("Local evidence workspace", report)

    def test_both_modes_keep_steps_collapsed(self):
        for standalone in (True, False):
            report, _ = module.render(self.manifest, standalone=standalone)
            self.assertEqual(report.count('<details class="steps">'), 3)
            self.assertNotIn('<details class="steps" open', report)

    def test_malicious_text_is_inert(self):
        report, _ = module.render(self.manifest)
        self.assertNotIn(EVIL, report)
        self.assertNotIn("<img src=x", report)
        self.assertIn("&lt;/script&gt;&lt;script&gt;alert(1)", report)
        self.assertEqual(len(re.findall(r"<script\b", report)), 2)
        self.assertEqual(report.count("</script>"), 2)

    def test_unsafe_paths_are_rejected(self):
        outside = self.base / "outside.png"
        outside.write_bytes(png(2, 2, (1, 2, 3)))
        (self.root / "link-out.png").symlink_to(outside)
        (self.root / "link-in.png").symlink_to(self.root / "shots/desktop-home.png")
        (self.root / "dirlink").symlink_to(self.root / "shots")
        self.assert_rejected("../outside.png", "inside the evidence folder")
        self.assert_rejected(str(outside), "inside the evidence folder")
        self.assert_rejected("link-out.png", "symlink")
        self.assert_rejected("link-in.png", "symlink")
        self.assert_rejected("dirlink/desktop-home.png", "symlink")
        self.assert_rejected("shots", "regular file")
        self.assert_rejected(".", "inside the evidence folder")
        self.assert_rejected("./", "inside the evidence folder")

    def test_directory_swapped_for_symlink_cannot_redirect_the_read(self):
        outside = self.base / "outside"
        outside.mkdir()
        evil = png(4, 4, (9, 9, 9))
        (outside / "desktop-home.png").write_bytes(evil)
        original = (self.root / "shots/desktop-home.png").read_bytes()
        self.edit(lambda data: data.update(scenarios=[{**data["scenarios"][0], "screenshots": [data["scenarios"][0]["screenshots"][0]]}]))
        real_open = module.os.open

        def run(trigger):
            fired = []

            def swap_then_open(path, *args, **kwargs):
                if not fired and Path(module.os.fspath(path)).name == trigger:
                    fired.append(True)
                    (self.root / "shots").rename(self.root / "shots-real")
                    (self.root / "shots").symlink_to(outside, target_is_directory=True)
                return real_open(path, *args, **kwargs)

            try:
                with mock.patch.object(module.os, "open", swap_then_open):
                    return module.render(self.manifest)[0]
            finally:
                self.assertTrue(fired)
                (self.root / "shots").unlink()
                (self.root / "shots-real").rename(self.root / "shots")

        report = run("desktop-home.png")
        self.assertFalse(base64.b64encode(evil).decode() in report, "an image outside the evidence folder was embedded")
        self.assertEqual([base64.b64decode(item["data"]) for item in embedded(report).values()], [original])
        with self.assertRaisesRegex(ValueError, "changed while rendering"):
            run("shots")

    def test_missing_and_unsupported_files_are_rejected(self):
        (self.root / "notes.png").write_text("not an image")
        self.assert_rejected("shots/nope.png", "Missing evidence artifact")
        self.assert_rejected("notes.png", "Unsupported screenshot type")
        self.set_first_file("shots/desktop-home.png")
        self.edit(lambda data: data["scenarios"][1].update(video="../outside.webm"))
        with self.assertRaisesRegex(ValueError, "inside the evidence folder"):
            module.render(self.manifest)

    def test_incomplete_images_are_rejected(self):
        sample = png(8, 8, (1, 2, 3))
        tampered = bytearray(sample)
        tampered[-20] ^= 0xFF
        no_idat = sample[:33] + sample[-12:]
        cases = {
            "PNG": [sample[:8], sample[:-12], sample[:len(sample) // 2], bytes(tampered), no_idat, sample + b"extra"],
            "JPEG": [JPEG[:3], JPEG[:-2], JPEG[:len(JPEG) // 2], JPEG[:2] + JPEG[-2:]],
            "WebP": [WEBP[:12], WEBP[:-4], WEBP[:len(WEBP) // 2], WEBP[:12] + b"ABCD" + WEBP[16:]],
        }
        for label, samples in cases.items():
            for index, data in enumerate(samples):
                with self.subTest(label=label, index=index):
                    (self.root / f"bad-{index}.img").write_bytes(data)
                    self.assert_rejected(f"bad-{index}.img", f"not a complete {label} image")
        self.set_first_file("bad-0.img")
        result = subprocess.run([sys.executable, str(SOURCE), str(self.manifest)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertTrue(result.stderr.startswith("error: Screenshot is not a complete WebP image"), result.stderr)
        self.assertFalse((self.root / "pass.html").exists())

    def test_crafted_headers_that_cannot_decode_are_rejected(self):
        def png_chunk(kind, body):
            return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)
        header = struct.pack(">IIBBBBB", 8, 8, 8, 2, 0, 0, 0)
        truncated_zlib = zlib.compress(b"\x00" + b"\x01\x02\x03" * 8 * 8)[:-6]
        corrupt_start = bytearray(WEBP)
        corrupt_start[23] ^= 0xFF
        cases = {
            "JPEG": b"\xff\xd8\xff\xc0\x00\x02\xff\xda\x00\x02\xff\xd9",
            "WebP": [b"RIFF\x0c\x00\x00\x00WEBPVP8 \x00\x00\x00\x00", bytes(corrupt_start)],
            "PNG": b"\x89PNG\r\n\x1a\n" + png_chunk(b"IHDR", header) + png_chunk(b"IDAT", truncated_zlib) + png_chunk(b"IEND", b""),
        }
        samples = [(label, data) for label, value in cases.items() for data in (value if isinstance(value, list) else [value])]
        self.assertEqual(len(samples[0][1]), 12)
        self.assertEqual(len(samples[1][1]), 20)
        for index, (label, data) in enumerate(samples):
            with self.subTest(label=label, index=index):
                (self.root / f"crafted-{index}.img").write_bytes(data)
                self.assert_rejected(f"crafted-{index}.img", f"not a complete {label} image")

    def test_trailing_data_is_named_in_the_error(self):
        with self.assertRaisesRegex(ValueError, r"truncated, corrupt, or has data after the image end"):
            module.validate_image(JPEG + b"tail", "x")

    def test_valid_images_of_each_type_pass_validation(self):
        valid = ((png(3, 2, (1, 2, 3)), "image/png"), (PNG_INTERLACED, "image/png"), (JPEG, "image/jpeg"),
                 (WEBP, "image/webp"), (WEBP_LOSSLESS, "image/webp"))
        for data, mime in valid:
            self.assertEqual(module.validate_image(data, "x"), mime)

    def test_size_caps_fail_clearly(self):
        original = module.MAX_IMAGE_BYTES, module.MAX_TOTAL_IMAGE_BYTES
        self.addCleanup(lambda: (setattr(module, "MAX_IMAGE_BYTES", original[0]), setattr(module, "MAX_TOTAL_IMAGE_BYTES", original[1])))
        module.MAX_IMAGE_BYTES = 100
        for standalone in (True, False):
            with self.assertRaisesRegex(ValueError, "exceeds the 0 MiB per-image limit: shots/desktop-home.png"):
                module.render(self.manifest, standalone=standalone)
        module.MAX_IMAGE_BYTES = original[0]
        module.MAX_TOTAL_IMAGE_BYTES = 700
        with self.assertRaisesRegex(ValueError, "total limit"):
            module.render(self.manifest)

    def test_each_payload_is_embedded_once_with_original_bytes(self):
        report, images = module.render(self.manifest)
        payloads = embedded(report)
        files = ["desktop-home.png", "desktop-form.png", "mobile-menu.png", "error.webp", "receipt.jpg"]
        originals = {hashlib.sha256((self.root / "shots" / f).read_bytes()).hexdigest(): (self.root / "shots" / f).read_bytes() for f in files}
        self.assertEqual(set(payloads), set(originals))
        self.assertEqual(len(payloads), 5)
        for digest, item in payloads.items():
            self.assertEqual(base64.b64decode(item["data"]), originals[digest])
            self.assertEqual(report.count(item["data"]), 1)
        self.assertEqual(payloads[next(d for d, b in originals.items() if b.startswith(b"RIFF"))]["mime"], "image/webp")
        self.assertEqual(images.total, sum(len(b) for b in originals.values()))
        self.assertEqual(len(re.findall(r'<img data-img="[0-9a-f]{64}"', report)), 7)

    def test_standalone_has_no_external_or_relative_references(self):
        report, _ = module.render(self.manifest)
        markup = re.sub(r'<script type="application/json" id="images">.*?</script>', "", report, flags=re.S)
        self.assertIsNone(re.search(r"https?:|//[a-z]", markup.replace("http://localhost:3000", ""), re.I))
        for attr, value in re.findall(r'\b(src|href)="([^"]*)"', report):
            self.assertTrue(value.startswith("#"), f"{attr}={value}")
        self.assertNotIn("<video", report)
        self.assertIn("Video not included in this portable file: shots/run.webm", report)
        self.assertIn("Not included: video shots/run.webm", report)
        self.assertIn("<noscript>", report)

    def test_csp_hash_matches_inline_script(self):
        report, _ = module.render(self.manifest)
        csp = re.search(r'<meta http-equiv="Content-Security-Policy" content="([^"]*)">', report)[1].replace("&#x27;", "'")
        scripts = re.findall(r"<script>(.*?)</script>", report, re.S)
        self.assertEqual(len(scripts), 1)
        digest = base64.b64encode(hashlib.sha256(scripts[0].encode()).digest()).decode()
        self.assertIn(f"script-src 'sha256-{digest}'", csp)
        self.assertNotIn("data:", csp)
        for directive in ("default-src 'none'", "img-src blob:", "style-src 'unsafe-inline'", "base-uri 'none'", "form-action 'none'"):
            self.assertIn(directive, csp)

    def test_cli_writes_only_report_and_keeps_evidence_unchanged(self):
        before = snapshot(self.root)
        result = subprocess.run([sys.executable, str(SOURCE), str(self.manifest)], capture_output=True, text=True, check=True)
        output = self.root / "pass.html"
        self.assertEqual(snapshot(self.root), {**before, str(output): (output.read_bytes(), output.stat().st_mtime_ns)})
        self.assertIn(str(output), result.stdout)
        self.assertIn("size:", result.stdout)
        self.assertIn("embedded images: 5 unique", result.stdout)
        elsewhere = self.base / "unrelated"
        elsewhere.mkdir()
        shutil.copy(output, elsewhere / "report.html")
        copied = (elsewhere / "report.html").read_text(encoding="utf-8")
        self.assertNotIn("shots/desktop", re.sub(r'<script type="application/json".*?</script>', "", copied, flags=re.S).replace("shots/run.webm", ""))
        self.assertEqual(len(embedded(copied)), 5)

    def test_cli_reports_errors_without_writing(self):
        self.set_first_file("../x.png")
        result = subprocess.run([sys.executable, str(SOURCE), str(self.manifest)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn("inside the evidence folder", result.stderr)
        self.assertFalse((self.root / "pass.html").exists())

    def test_cli_reports_unreadable_folder_without_traceback(self):
        self.root.chmod(0o300)
        self.addCleanup(self.root.chmod, 0o755)
        for flags in ([], ["--linked"]):
            result = subprocess.run([sys.executable, str(SOURCE), str(self.manifest), *flags], capture_output=True, text=True)
            self.assertEqual(result.returncode, 1)
            self.assertTrue(result.stderr.startswith("error: ") and "Permission denied" in result.stderr, result.stderr)
            self.assertNotIn("Traceback", result.stderr)
            self.assertFalse((self.root / "pass.html").exists())

    def test_linked_mode_keeps_relative_links(self):
        report, _ = module.render(self.manifest, standalone=False)
        self.assertIn('<img src="shots/desktop-home.png"', report)
        self.assertIn('<a href="shots/desktop-form.png"', report)
        self.assertIn('<video controls preload="metadata" src="shots/run.webm">', report)
        self.assertNotIn('id="images"', report)
        self.assertNotIn("Content-Security-Policy", report)
        self.assertIn("Saved evidence, outside the application repository", report)
        self.assertIn("<span>Local evidence workspace</span></header>", report)


if __name__ == "__main__":
    unittest.main()
