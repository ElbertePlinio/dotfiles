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


EVIL = '</script><script>alert(1)</script>"\'<img src=x onerror=alert(2)>'


def write_fixture(root):
    root.mkdir(parents=True, exist_ok=True)
    (root / "shots").mkdir()
    (root / "shots/desktop-home.png").write_bytes(png(320, 200, (40, 40, 48)))
    (root / "shots/desktop-form.png").write_bytes(png(320, 200, (255, 122, 26)))
    (root / "shots/mobile-menu.png").write_bytes(png(90, 190, (85, 201, 147)))
    (root / "shots/mobile-copy.png").write_bytes((root / "shots/mobile-menu.png").read_bytes())
    (root / "shots/error.webp").write_bytes(b"RIFF\x1a\x00\x00\x00WEBPVP8L\x0d\x00\x00\x00\x2f\x00\x00\x00\x00\x07\x10\x11\x11\x88\x88\xfe\x07\x00")
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
                             {"file": "shots/error.webp", "caption": "Error state (WebP)"}],
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

    def test_missing_and_unsupported_files_are_rejected(self):
        (self.root / "notes.png").write_text("not an image")
        self.assert_rejected("shots/nope.png", "Missing evidence artifact")
        self.assert_rejected("notes.png", "Unsupported screenshot type")
        self.set_first_file("shots/desktop-home.png")
        self.edit(lambda data: data["scenarios"][1].update(video="../outside.webm"))
        with self.assertRaisesRegex(ValueError, "inside the evidence folder"):
            module.render(self.manifest)

    def test_size_caps_fail_clearly(self):
        original = module.MAX_IMAGE_BYTES, module.MAX_TOTAL_IMAGE_BYTES
        self.addCleanup(lambda: (setattr(module, "MAX_IMAGE_BYTES", original[0]), setattr(module, "MAX_TOTAL_IMAGE_BYTES", original[1])))
        module.MAX_IMAGE_BYTES = 100
        with self.assertRaisesRegex(ValueError, "per-image limit"):
            module.render(self.manifest)
        module.MAX_IMAGE_BYTES = original[0]
        module.MAX_TOTAL_IMAGE_BYTES = 700
        with self.assertRaisesRegex(ValueError, "total limit"):
            module.render(self.manifest)

    def test_each_payload_is_embedded_once_with_original_bytes(self):
        report, images = module.render(self.manifest)
        payloads = embedded(report)
        files = ["desktop-home.png", "desktop-form.png", "mobile-menu.png", "error.webp"]
        originals = {hashlib.sha256((self.root / "shots" / f).read_bytes()).hexdigest(): (self.root / "shots" / f).read_bytes() for f in files}
        self.assertEqual(set(payloads), set(originals))
        self.assertEqual(len(payloads), 4)
        for digest, item in payloads.items():
            self.assertEqual(base64.b64decode(item["data"]), originals[digest])
            self.assertEqual(report.count(item["data"]), 1)
        self.assertEqual(payloads[next(d for d, b in originals.items() if b.startswith(b"RIFF"))]["mime"], "image/webp")
        self.assertEqual(images.total, sum(len(b) for b in originals.values()))
        self.assertEqual(len(re.findall(r'<img data-img="[0-9a-f]{64}"', report)), 6)

    def test_standalone_has_no_external_or_relative_references(self):
        report, _ = module.render(self.manifest)
        self.assertIsNone(re.search(r"https?:|//[a-z]", report.replace("http://localhost:3000", ""), re.I))
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
        for directive in ("default-src 'none'", "img-src data:", "style-src 'unsafe-inline'", "base-uri 'none'", "form-action 'none'"):
            self.assertIn(directive, csp)

    def test_cli_writes_only_report_and_keeps_evidence_unchanged(self):
        before = snapshot(self.root)
        result = subprocess.run([sys.executable, str(SOURCE), str(self.manifest)], capture_output=True, text=True, check=True)
        output = self.root / "pass.html"
        self.assertEqual(snapshot(self.root), {**before, str(output): (output.read_bytes(), output.stat().st_mtime_ns)})
        self.assertIn(str(output), result.stdout)
        self.assertIn("size:", result.stdout)
        self.assertIn("embedded images: 4 unique", result.stdout)
        elsewhere = self.base / "unrelated"
        elsewhere.mkdir()
        shutil.copy(output, elsewhere / "report.html")
        copied = (elsewhere / "report.html").read_text(encoding="utf-8")
        self.assertNotIn("shots/desktop", re.sub(r'<script type="application/json".*?</script>', "", copied, flags=re.S).replace("shots/run.webm", ""))
        self.assertEqual(len(embedded(copied)), 4)

    def test_cli_reports_errors_without_writing(self):
        self.set_first_file("../x.png")
        result = subprocess.run([sys.executable, str(SOURCE), str(self.manifest)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn("inside the evidence folder", result.stderr)
        self.assertFalse((self.root / "pass.html").exists())

    def test_linked_mode_keeps_relative_links(self):
        report, _ = module.render(self.manifest, standalone=False)
        self.assertIn('<img src="shots/desktop-home.png"', report)
        self.assertIn('<a href="shots/desktop-form.png"', report)
        self.assertIn('<video controls preload="metadata" src="shots/run.webm">', report)
        self.assertNotIn('id="images"', report)
        self.assertNotIn("Content-Security-Policy", report)
        self.assertIn("Saved evidence, outside the application repository", report)


if __name__ == "__main__":
    unittest.main()
