#!/usr/bin/env python3
"""Replay a flow on a phone at a human pace and record it as evidence.

Usage:
  record_flow.py (--udid <udid> | --serial <serial>) [--dry-run] [--seed N] [--no-taps] <evidence>/raw/video/<name>.flow.json
  record_flow.py --sheet <video.mp4>

--udid drives an iOS Simulator (xcrun simctl, idb). --serial drives an Android device or emulator (adb).
The flow file is a JSON list of steps, one key each (plus options). A label is the iOS AXLabel, or the
Android content-desc (Flutter semantics label) or text of a node in `uiautomator dump`.
  {"open": "scheme://path"}                         open a deep link
  {"wait": "Label", "timeout": 20}                  wait until an element shows (default 15 s)
  {"tap": "Label"}                                  tap the element whose label is exactly Label
  {"tap": "Part", "contains": true, "index": 1}     substring match; index picks the nth match
  {"tapAt": [x, y]}                                 tap a point (iOS pt, Android px), for icon-only buttons
  {"type": "Ella"}                                  type into the focused field, one key at a time (ASCII)
  {"scroll": "down", "distance": 300}               swipe so the page moves down (or "up"), in pt or px
  {"pause": 1.5}                                    hold still, in seconds
  {"textSize": "largest"}                           live text size change: smallest, default, largest

A recording writes raw/video/<name>.raw.<ext>, <name>.events.json, <name>-sheet.png and
<evidence>/videos/<name>.mp4. A dry run plays the steps fast, records nothing and stops at the first
step that fails. --sheet only writes a frame sheet beside any video, such as a browser recording.
"""
import argparse
import json
import math
import os
import random
import uuid
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
import xml.etree.ElementTree as ET
from pathlib import Path

MAX_WIDTH = 720
SHEET_FRAMES = 24
GITHUB_LIMIT_MB = 100


class StepFailed(Exception):
    pass


def run(*cmd, check=True):
    return subprocess.run(cmd, check=check, capture_output=True, text=True)


class IOS:
    """iOS Simulator through simctl and idb. Coordinates are in points."""

    TEXT_SIZES = {"smallest": "extra-small", "default": "large", "largest": "accessibility-extra-extra-extra-large"}
    raw_suffix = ".mov"
    dot_pt = 44

    def __init__(self, udid):
        self.udid = udid
        self.screen = None

    def elements(self):
        out = run("idb", "ui", "describe-all", "--udid", self.udid).stdout
        nodes = json.loads(out)
        if self.screen is None:
            frame = next(e["frame"] for e in nodes if e.get("type") == "Application")
            self.screen = {"width": frame["width"], "height": frame["height"]}
        found = []
        for e in nodes:
            f = e.get("frame") or {}
            if not (f.get("width") and f.get("height") and e.get("AXLabel")):
                continue
            cx, cy = f.get("x", 0) + f["width"] / 2, f.get("y", 0) + f["height"] / 2
            if 0 <= cx <= self.screen["width"] and 0 <= cy <= self.screen["height"]:
                found.append((e["AXLabel"], (cx, cy)))
        return found

    def open(self, url):
        run("xcrun", "simctl", "openurl", self.udid, url)

    def tap(self, x, y):
        run("idb", "ui", "tap", "--udid", self.udid, str(round(x)), str(round(y)))

    def key(self, ch):
        run("idb", "ui", "text", "--udid", self.udid, ch)

    def swipe(self, x, y1, y2):
        run("idb", "ui", "swipe", "--udid", self.udid, "--duration", "0.4", "--delta", "12",
            str(round(x)), str(round(y1)), str(round(x)), str(round(y2)))

    def text_size(self, size, recording):
        run("xcrun", "simctl", "ui", self.udid, "content_size", self.TEXT_SIZES[size])

    def save_text_size(self):
        value = run("xcrun", "simctl", "ui", self.udid, "content_size", check=False).stdout.strip()
        return value if re.fullmatch(r"[a-z-]+", value) else None

    def restore_text_size(self, saved):
        run("xcrun", "simctl", "ui", self.udid, "content_size", saved)

    def clean_status_bar(self, on):
        if on:
            run("xcrun", "simctl", "status_bar", self.udid, "override", "--time", "9:41",
                "--dataNetwork", "wifi", "--wifiMode", "active", "--wifiBars", "3",
                "--cellularMode", "active", "--cellularBars", "4",
                "--batteryState", "charged", "--batteryLevel", "100")
        else:
            run("xcrun", "simctl", "status_bar", self.udid, "clear", check=False)

    def start_recording(self, raw):
        self.proc = subprocess.Popen(
            ["xcrun", "simctl", "io", self.udid, "recordVideo", "--codec=h264", "--force", str(raw)],
            stderr=subprocess.PIPE, text=True)
        started = threading.Event()

        def watch():
            for line in self.proc.stderr:
                if "Recording started" in line:
                    started.set()

        threading.Thread(target=watch, daemon=True).start()
        if not started.wait(20):
            self.proc.send_signal(signal.SIGINT)
            raise SystemExit("simctl recordVideo did not start within 20 s")

    def stop_recording(self, raw):
        """Stop the recorder; return True when it had already stopped on its own."""
        early = self.proc.poll() is not None
        if not early:
            self.proc.send_signal(signal.SIGINT)
        self.proc.wait(timeout=60)
        return early

    early_stop = "simctl recordVideo stopped before the flow ended"

    def labels_hint(self):
        return "AXLabel from `idb ui describe-all`"


class Android:
    """Android device or emulator through adb. Coordinates are in pixels."""

    FONT_SCALES = {"smallest": "0.85", "default": "1.0", "largest": "2.0"}
    BOUNDS = re.compile(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]")
    raw_suffix = ".mp4"

    def __init__(self, serial):
        self.serial = serial
        self.screen = None

    @property
    def dot_pt(self):
        # 48 px on a 1080 px wide screen, scaled to other widths.
        return 48 * self.screen["width"] / 1080

    def adb(self, *args, check=True):
        return run("adb", "-s", self.serial, *args, check=check)

    def shell(self, *args, check=True):
        return self.adb("shell", *args, check=check)

    def dump(self):
        for _ in range(5):
            out = self.adb("exec-out", "uiautomator", "dump", "/dev/tty", check=False).stdout
            start, end = out.find("<?xml"), out.rfind("</hierarchy>")
            if start >= 0 and end > start:
                return ET.fromstring(out[start:end + len("</hierarchy>")])
            time.sleep(0.5)  # uiautomator fails while the screen animates
        raise StepFailed("uiautomator dump returned no hierarchy; is the screen unlocked?")

    def elements(self):
        found = []
        for node in self.dump().iter("node"):
            m = self.BOUNDS.fullmatch(node.get("bounds", ""))
            if not m:
                continue
            x1, y1, x2, y2 = map(int, m.groups())
            if self.screen is None:
                self.screen = {"width": x2, "height": y2}
            cx, cy = (x1 + x2) / 2, (y1 + y2) / 2
            on_screen = 0 <= cx <= self.screen["width"] and 0 <= cy <= self.screen["height"]
            if x2 > x1 and y2 > y1 and on_screen:
                found += [(label, (cx, cy)) for label in {node.get("content-desc") or "", node.get("text") or ""} - {""}]
        return found

    def open(self, url):
        self.shell("am", "start", "-a", "android.intent.action.VIEW", "-d", "'" + url.replace("'", "'\\''") + "'")

    def tap(self, x, y):
        self.shell("input", "tap", str(round(x)), str(round(y)))

    def key(self, ch):
        self.shell("input", "text", "%s" if ch == " " else "'" + ch.replace("'", "'\\''") + "'")

    def swipe(self, x, y1, y2):
        self.shell("input", "swipe", str(round(x)), str(round(y1)), str(round(x)), str(round(y2)), "400")

    def text_size(self, size, recording):
        self.shell("settings", "put", "system", "font_scale", self.FONT_SCALES[size])
        if recording:
            time.sleep(0.5)  # a font change reloads the status bar and drops demo mode
            self.clean_status_bar(True)

    def save_text_size(self):
        value = self.shell("settings", "get", "system", "font_scale", check=False).stdout.strip()
        if value == "null":
            return "unset"
        return value if re.fullmatch(r"\d+(\.\d+)?", value) else None

    def restore_text_size(self, saved):
        if saved == "unset":
            self.shell("settings", "delete", "system", "font_scale")
        else:
            self.shell("settings", "put", "system", "font_scale", saved)

    def clean_status_bar(self, on):
        """Demo mode: 9:41, full battery, full wifi, no mobile icon, no notifications."""
        def demo(command, *extras):
            self.shell("am", "broadcast", "-a", "com.android.systemui.demo", "-e", "command", command, *extras,
                       check=False)

        if not on:
            demo("exit")
            self.restore_demo_flag()
            return
        if not hasattr(self, "demo_flag"):
            read = self.shell("settings", "get", "global", "sysui_demo_allowed", check=False)
            if read.returncode or not read.stdout.strip():
                raise SystemExit("could not read sysui_demo_allowed, so demo mode could not be undone")
            self.demo_flag = read.stdout.strip()
        self.shell("settings", "put", "global", "sysui_demo_allowed", "1", check=False)
        for command, *extras in (("enter",), ("clock", "-e", "hhmm", "0941"),
                                 ("battery", "-e", "level", "100", "-e", "plugged", "false"),
                                 ("network", "-e", "fully", "true"), ("network", "-e", "wifi", "show", "-e", "level", "4"),
                                 ("network", "-e", "mobile", "hide"), ("notifications", "-e", "visible", "false")):
            demo(command, *extras)

    def restore_demo_flag(self):
        flag = getattr(self, "demo_flag", "1")
        if flag == "1":
            return
        command = ("delete", "global", "sysui_demo_allowed") if flag == "null" else ("put", "global", "sysui_demo_allowed", flag)
        if self.shell("settings", *command, check=False).returncode:
            print(f"warning: could not restore sysui_demo_allowed to {flag}; set it by hand", file=sys.stderr)

    def alive(self):
        """True while the recorder runs and False once it exited. Stops the run when adb cannot tell."""
        out = self.shell(f"kill -0 {self.pid} 2>/dev/null && echo running || echo exited", check=False).stdout.split()
        if out[-1:] == ["running"]:
            return True
        if out[-1:] == ["exited"]:
            return False
        raise SystemExit(f"adb could not check the recorder; its file is still on the device: {self.device_file}")

    def start_recording(self, raw):
        # A file and a process of this run only, so another capture on the device is never touched.
        self.device_file = f"/sdcard/device-pass-{uuid.uuid4().hex}.mp4"
        self.proc = subprocess.Popen(
            ["adb", "-s", self.serial, "shell",
             f"screenrecord --bit-rate 8000000 --time-limit 180 {self.device_file} & echo $!; wait"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.pid = (self.proc.stdout.readline() or "").strip()
        if not self.pid.isdigit():
            self.proc.kill()
            raise SystemExit(f"screenrecord did not start: {self.proc.stderr.read().strip()}")
        time.sleep(0.5)
        if not self.alive():
            raise SystemExit(f"screenrecord stopped at once: {self.proc.stderr.read().strip()}")

    def stop_recording(self, raw):
        """Stop the recorder; return True when it had already stopped, such as at the 180 s limit."""
        early = not self.alive()
        if not early:
            self.shell("kill", "-INT", self.pid, check=False)
        # screenrecord writes the mp4 trailer after SIGINT; pull only once it has exited on the device.
        deadline = time.monotonic() + 30
        while self.alive():
            if time.monotonic() > deadline:
                raise SystemExit(f"screenrecord did not finish within 30 s; its file is still on the device: {self.device_file}")
            time.sleep(0.3)
        try:
            self.proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            self.proc.kill()
        self.adb("pull", self.device_file, str(raw))
        try:
            probe(raw)
        except (subprocess.CalledProcessError, KeyError, IndexError, ValueError):
            raise SystemExit(f"the pulled recording is not readable; the device keeps {self.device_file}") from None
        self.shell("rm", "-f", self.device_file, check=False)
        return early

    early_stop = "screenrecord stopped before the flow ended; it records at most 180 s"

    def labels_hint(self):
        return "content-desc or text from `adb exec-out uiautomator dump /dev/tty`"


class Flow:
    def __init__(self, device, dry_run, seed):
        self.device = device
        self.dry = dry_run
        self.rng = random.Random(seed)
        self.t0 = None
        self.last_action = time.monotonic()
        self.events = []

    def find(self, step, key):
        label = step[key]
        timeout = step.get("timeout", 15)
        deadline = time.monotonic() + timeout
        while True:
            try:
                elements = self.device.elements()
            except StepFailed:
                elements = []  # the tree is briefly unreadable while a screen animates
            hits = [xy for text, xy in elements if (label in text if step.get("contains") else text == label)]
            if len(hits) > step.get("index", 0):
                return hits[step.get("index", 0)]
            if time.monotonic() > deadline:
                raise StepFailed(f'no element "{label}" after {timeout} s')
            time.sleep(0.25)

    def dwell(self, low, high, floor=0.0):
        """Sleep so the next action lands a human pause after the last one."""
        if self.dry:
            return
        target = self.rng.uniform(low, high)
        time.sleep(max(floor, target - (time.monotonic() - self.last_action)))

    def stamp(self, action, x=None, y=None):
        self.last_action = time.monotonic()
        if self.t0 is not None:
            self.events.append({"t": round(self.last_action - self.t0, 3), "action": action, "x": x, "y": y})

    def tap(self, x, y):
        self.device.tap(x, y)
        self.stamp("tap", x, y)

    def step(self, step):
        for key, action in (("open", self.do_open), ("wait", self.do_wait), ("tap", self.do_tap),
                            ("tapAt", self.do_tap_at), ("type", self.do_type), ("scroll", self.do_scroll),
                            ("pause", self.do_pause), ("textSize", self.do_text_size)):
            if key in step:
                return action(step)
        raise StepFailed(f"unknown step {step}")

    def do_open(self, step):
        self.device.open(step["open"])
        self.stamp("open")

    def do_wait(self, step):
        self.find(step, "wait")

    def do_tap(self, step):
        x, y = self.find(step, "tap")
        self.dwell(0.8, 1.3, floor=0.5)
        self.tap(x, y)

    def do_tap_at(self, step):
        self.dwell(0.8, 1.3)
        self.tap(*step["tapAt"])

    def do_type(self, step):
        text = step["type"]
        if not text.isascii():
            raise StepFailed("typing supports ASCII only")
        self.dwell(0.5, 0.8)
        for ch in text:
            self.device.key(ch)
            self.stamp("key")
            self.dwell(0.06, 0.16)

    def do_scroll(self, step):
        d = self.device
        if d.screen is None:
            d.elements()
        w, h = d.screen["width"], d.screen["height"]
        dist = min(step.get("distance", h * 0.4), h * 0.7)
        y1 = h * 0.65 if step["scroll"] == "down" else h * 0.35
        y2 = y1 - dist if step["scroll"] == "down" else y1 + dist
        self.dwell(0.8, 1.3)
        d.swipe(w / 2, y1, y2)
        self.stamp("scroll")

    def do_pause(self, step):
        if not self.dry:
            time.sleep(step["pause"])

    def do_text_size(self, step):
        if step["textSize"] not in ("smallest", "default", "largest"):
            raise StepFailed("textSize is smallest, default or largest")
        self.dwell(0.8, 1.2)
        self.device.text_size(step["textSize"], recording=self.t0 is not None)
        self.stamp("textSize")


def probe(path):
    out = run("ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height",
              "-show_entries", "format=duration", "-of", "json", str(path)).stdout
    data = json.loads(out)
    s = data["streams"][0]
    # A recording of a still screen can hold one frame and no duration.
    return s["width"], s["height"], float(data["format"].get("duration", 0))


def duration(path):
    """The video stream's duration, else the end of its last packet, else the container's duration.

    The container's duration comes last because a longer audio track can stretch it past the video.
    """
    out = run("ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=duration",
              "-of", "csv=p=0", str(path)).stdout.strip()
    if re.fullmatch(r"\d+(\.\d+)?", out) and float(out) > 0:
        return float(out)
    out = run("ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "packet=pts_time,duration_time",
              "-of", "csv=p=0", str(path)).stdout
    ends = [sum(float(x) for x in line.split(",") if re.fullmatch(r"-?\d+(\.\d+)?", x)) for line in out.splitlines()]
    return max(ends, default=0) or probe(path)[2]


def encode(raw, mp4, taps, end, device):
    """Encode the raw capture to mp4, padded to the real end, with a dot on each tap in taps."""
    with tempfile.TemporaryDirectory() as tmp:
        if raw.suffix == ".mov":
            # simctl can write bad decode timestamps at the end of the .mov, and ffmpeg then runs the screens
            # ahead of the tap log. A stream copy into .mkv keeps the real frame times.
            remux = Path(tmp) / "raw.mkv"
            run("ffmpeg", "-v", "error", "-y", "-i", str(raw), "-c", "copy", str(remux))
            raw = remux
        encode_video(raw, mp4, taps, end, device, Path(tmp) / "tap.png")


def encode_video(raw, mp4, taps, end, device, tap_png):
    vw, _, raw_duration = probe(raw)
    scale = vw / device.screen["width"]
    # A still screen gives one frame with no duration, which filters drop unless the input has a rate.
    inputs = ["-r", "30", "-i", str(raw)] if raw_duration == 0 else ["-i", str(raw)]
    # Both recorders write a frame only when the screen changes, so pad the still tail back to the real end.
    graph = [f"[0:v]tpad=stop_mode=clone:stop_duration={max(0, end - raw_duration):.3f},fps=30[v0]"]
    if taps:
        # Neither platform draws a touch for injected taps, so draw a grey dot from the tap log.
        d = round(device.dot_pt * scale)
        r = d / 2
        run("ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", f"color=black@0:s={d}x{d},format=rgba",
            "-vf", f"geq=r=90:g=90:b=90:a='if(lt(hypot(X-{r},Y-{r}),{r * 0.85}),110,"
                   f"if(lt(hypot(X-{r},Y-{r}),{r}),200,0))'",
            "-frames:v", "1", str(tap_png))
        inputs += ["-i", str(tap_png)]
        graph.append(f"[1:v]split={len(taps)}" + "".join(f"[d{i}]" for i in range(len(taps))))
        for i, e in enumerate(taps):
            # The tap command returns just after the touch, so the dot starts a little before the stamp.
            a, b = max(0, e["t"] - 0.1), e["t"] + 0.4
            x, y = round(e["x"] * scale - r), round(e["y"] * scale - r)
            graph.append(f"[v{i}][d{i}]overlay={x}:{y}:enable='between(t,{a:.3f},{b:.3f})'[v{i + 1}]")
    graph.append(f"[v{len(taps)}]scale='min({MAX_WIDTH},iw)':-2,format=yuv420p[out]")
    run("ffmpeg", "-v", "error", "-y", *inputs, "-filter_complex", ";".join(graph), "-map", "[out]",
        "-c:v", "libx264", "-preset", "slow", "-crf", "26", "-movflags", "+faststart", "-an", str(mp4))


def contact_sheet(video, sheet):
    """Write up to 24 evenly spaced frames as one image; the old sheet stays until the new one exists."""
    seconds = duration(video)
    if seconds <= 0:
        raise SystemExit(f"video has no duration: {video}")
    frames = min(SHEET_FRAMES, max(1, math.ceil(seconds)))
    cols = min(6, frames)
    rows = math.ceil(frames / cols)
    with tempfile.TemporaryDirectory() as tmp:
        new = Path(tmp) / "sheet.png"
        run("ffmpeg", "-v", "error", "-y", "-i", str(video), "-vf",
            f"fps={cols * rows / seconds:.4f},scale=240:-2,tile={cols}x{rows}:padding=4", "-frames:v", "1", str(new))
        if not new.is_file():
            raise SystemExit(f"ffmpeg wrote no frame sheet for {video}")
        shutil.move(new, sheet)


def report(mp4, sheet):
    w, h, duration = probe(mp4)
    size_mb = mp4.stat().st_size / 1e6
    print(f"wrote {mp4} ({w}x{h}, {duration:.1f} s, {size_mb:.1f} MB)")
    print(f"look at {sheet} before you report the video")
    if size_mb > GITHUB_LIMIT_MB:
        print(f"warning: GitHub rejects attachments over {GITHUB_LIMIT_MB} MB; lower the quality, do not split",
              file=sys.stderr)


def play(flow, steps):
    """Run the steps; return the first failure, printed at once, or None."""
    for i, step in enumerate(steps, 1):
        print(f"{i:>3} {json.dumps(step)}", flush=True)
        try:
            flow.step(step)
        except (StepFailed, subprocess.CalledProcessError) as err:
            detail = err.stderr.strip() if isinstance(err, subprocess.CalledProcessError) else err
            failed = f"step {i} failed: {detail}"
            print(failed, file=sys.stderr, flush=True)
            return failed
    return None


def record(flow, steps, partial, saved_size):
    """Record the steps when not a dry run. Return (failure, seconds recorded) and always undo device changes."""
    device = flow.device
    recording = False
    failed = None
    end = 0
    try:
        if not flow.dry:
            device.clean_status_bar(True)
            device.start_recording(partial)
            recording = True
            flow.t0 = flow.last_action = time.monotonic()
        failed = play(flow, steps)
        if recording and not failed:
            time.sleep(1.5)
    finally:
        try:
            if recording:
                end = time.monotonic() - flow.t0
                if device.stop_recording(partial) and not failed:
                    failed = device.early_stop
                    print(failed, file=sys.stderr)
        finally:
            restore(flow, saved_size)
    return failed, end


def restore(flow, saved_size):
    if not flow.dry:
        flow.device.clean_status_bar(False)
    if saved_size:
        try:
            flow.device.restore_text_size(saved_size)
        except subprocess.CalledProcessError:
            print(f"warning: could not restore the text size to {saved_size}; set it by hand", file=sys.stderr)


def show_labels(device):
    try:
        labels = sorted({text for text, _ in device.elements()})
    except (StepFailed, subprocess.CalledProcessError):
        return
    print(f"labels on screen ({device.labels_hint()}): " + " | ".join(l.replace("\n", " ") for l in labels[:40]),
          file=sys.stderr)


def finish(flow, partial, name, end, draw_taps):
    """Encode the take, then replace the last raw capture, so a bad take never replaces a good one."""
    video_dir = partial.parent
    mp4 = video_dir.parent.parent / "videos" / f"{name}.mp4"
    mp4.parent.mkdir(exist_ok=True)
    taps = [e for e in flow.events if e["action"] == "tap"] if draw_taps else []
    encode(partial, mp4, taps, end, flow.device)
    os.replace(partial, video_dir / f"{name}.raw{flow.device.raw_suffix}")
    (video_dir / f"{name}.events.json").write_text(json.dumps(flow.events, indent=1))
    sheet = video_dir / f"{name}-sheet.png"
    contact_sheet(mp4, sheet)
    report(mp4, sheet)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("flow", type=Path, nargs="?")
    target = ap.add_mutually_exclusive_group()
    target.add_argument("--udid", help="iOS Simulator you own, never another session's")
    target.add_argument("--serial", help="adb serial; pin it, a stale wireless entry can coexist")
    target.add_argument("--sheet", type=Path, help="only write <video>-sheet.png for an existing video")
    ap.add_argument("--dry-run", action="store_true", help="play the steps fast with no recording")
    ap.add_argument("--seed", type=int, default=1, help="seed for the human pauses")
    ap.add_argument("--no-taps", action="store_true", help="do not draw tap dots")
    args = ap.parse_args()

    if args.sheet:
        video = args.sheet.expanduser().resolve()
        sheet = video.with_name(video.stem + "-sheet.png")
        contact_sheet(video, sheet)
        print(f"wrote {sheet}")
        return
    if not args.flow or not (args.udid or args.serial):
        ap.error("give a flow file and --udid or --serial, or --sheet <video>")

    flow_path = args.flow.expanduser().resolve()
    steps = json.loads(flow_path.read_text())
    name = flow_path.name.removesuffix(".flow.json")
    device = IOS(args.udid) if args.udid else Android(args.serial)
    # Record to a partial file, so a failed take never replaces the last good raw capture.
    partial = flow_path.parent / f"{name}.raw.partial{device.raw_suffix}"
    flow = Flow(device, args.dry_run, args.seed)
    device.elements()
    saved_size = None
    if any("textSize" in s for s in steps):
        saved_size = device.save_text_size()
        if not saved_size:
            sys.exit("could not read the current text size, so it could not be restored; textSize steps refused")
    try:
        failed, end = record(flow, steps, partial, saved_size)
    except subprocess.CalledProcessError as err:
        sys.exit(f"{' '.join(map(str, err.cmd[:4]))} failed: {(err.stderr or '').strip()}")
    if failed:
        if not args.dry_run:
            print(f"raw video kept for a look: {partial}", file=sys.stderr)
        show_labels(device)
        sys.exit(1)
    if args.dry_run:
        print("dry run passed; put the app back at the first screen, then record")
        return
    try:
        finish(flow, partial, name, end, not args.no_taps)
    except subprocess.CalledProcessError as err:
        sys.exit(f"could not encode the take, kept at {partial}: {(err.stderr or '').strip()}")


if __name__ == "__main__":
    main()
