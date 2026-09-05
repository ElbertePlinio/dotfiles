#!/usr/bin/env python3
"""Register Codex lanes without replacing unrelated or customized MCP entries."""
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tomllib


def configure():
    executable = shutil.which("codex")
    if not executable:
        print("warning: Codex CLI unavailable; lanes registration skipped", file=sys.stderr)
        return 0
    config = Path(os.environ.get("CODEX_HOME", str(Path.home() / ".codex"))) / "config.toml"
    data = tomllib.loads(config.read_text()) if config.exists() else {}
    current = data.get("mcp_servers", {}).get("pickforge-lanes")
    if current is not None:
        if current.get("command") == "pickforge-lanes-mcp" and current.get("args") == ["--origin", "codex"] and current.get("enabled", True):
            return 0
        print("error: existing Codex pickforge-lanes entry differs; preserved for review", file=sys.stderr)
        return 1
    command = [executable, "mcp", "add", "pickforge-lanes", "--", "pickforge-lanes-mcp", "--origin", "codex"]
    with subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True) as process:
        try:
            status = process.wait(timeout=15)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
            print("error: Codex lanes registration timed out", file=sys.stderr)
            return 1
    if status:
        print("error: Codex lanes registration failed; command output withheld", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    try:
        sys.exit(configure())
    except (OSError, ValueError):
        print("error: cannot inspect Codex configuration safely", file=sys.stderr)
        sys.exit(1)
