#!/usr/bin/env python3
"""Read live windows and perform explicit, validated Hyprland actions."""
import json
import re
import subprocess
import sys


def hypr(*args):
    result = subprocess.run(["hyprctl", *args], capture_output=True, text=True, timeout=5, check=True)
    return result.stdout.strip()


def windows():
    return [c for c in json.loads(hypr("clients", "-j")) if c.get("mapped", True) and not c.get("hidden", False)]


def snapshot():
    clients = windows()
    active = json.loads(hypr("activewindow", "-j"))
    monitors = json.loads(hypr("monitors", "-j"))
    screen = next((m["name"] for m in monitors if m.get("focused")), "")
    keys = ("address", "title", "class", "workspace", "fullscreen")
    return {"windows": [{k: c.get(k) for k in keys} for c in clients], "active": active.get("address", ""), "screen": screen}


def action(name, address, workspace=None):
    if name not in ("fullscreen", "windowed", "focus", "move", "close"):
        raise ValueError("Unknown action")
    if not re.fullmatch(r"0x[0-9a-fA-F]+", address):
        raise ValueError("Invalid window address")
    if name == "move" and (workspace is None or not re.fullmatch(r"[1-9]|10", workspace)):
        raise ValueError("Choose workspace 1 through 10")
    if not any(c["address"] == address for c in windows()):
        raise ValueError("That window has closed. Refresh the window list.")
    target = json.dumps("address:" + address)
    commands = [f"hl.dispatch(hl.dsp.focus({{ window = {target} }}))"]
    if name in ("fullscreen", "windowed"):
        state = 2 if name == "fullscreen" else 0
        commands.append(f"hl.dispatch(hl.dsp.window.fullscreen_state({{ internal = {state}, client = {state} }}))")
    if name == "move":
        commands.append(f"hl.dispatch(hl.dsp.window.move({{ workspace = {json.dumps(workspace)}, follow = true }}))")
    if name == "close":
        commands.append(f"hl.dispatch(hl.dsp.window.close({{ window = {target} }}))")
    result = hypr("eval", "; ".join(commands))
    if result != "ok":
        raise RuntimeError(result)
    return {"ok": True}


def main():
    args = sys.argv[1:]
    if args == ["snapshot"]:
        result = snapshot()
    elif len(args) in (2, 3):
        result = action(*args)
    else:
        raise ValueError("Usage: control.py snapshot | fullscreen|windowed|focus|close ADDRESS | move ADDRESS WORKSPACE")
    print(json.dumps(result))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
