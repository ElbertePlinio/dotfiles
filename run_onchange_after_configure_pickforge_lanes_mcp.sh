#!/bin/sh
set -eu
umask 077

timeout_seconds=${PICKFORGE_LANES_MCP_TIMEOUT:-15}
case "$timeout_seconds" in
  ''|*[!0-9]*) timeout_seconds=15 ;;
esac
if [ "$timeout_seconds" -lt 1 ] || [ "$timeout_seconds" -gt 300 ]; then
  timeout_seconds=15
fi

if ! command -v python3 >/dev/null 2>&1; then
  printf '%s\n' 'error: python3 is required to configure the pickforge-lanes MCP safely' >&2
  exit 1
fi
if ! command -v claude >/dev/null 2>&1; then
  printf '%s\n' 'warning: Claude CLI is unavailable; pickforge-lanes MCP was not configured' >&2
  exit 0
fi

private_dir=$(mktemp -d "${TMPDIR:-/tmp}/pickforge-lanes-mcp.XXXXXX") || exit 1
trap 'rm -rf "$private_dir"' EXIT HUP INT TERM
details="$private_dir/get"

run_capture() {
  output=$1
  shift
  python3 - "$timeout_seconds" "$output" "$@" <<'PY'
import os
import signal
import subprocess
import sys
import time

timeout = int(sys.argv[1])
output_path = sys.argv[2]
command = sys.argv[3:]
flags = os.O_WRONLY | os.O_CREAT | os.O_TRUNC
fd = os.open(output_path, flags, 0o600)
try:
    try:
        process = subprocess.Popen(
            command,
            stdout=fd,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
    except OSError:
        raise SystemExit(125)
finally:
    os.close(fd)

try:
    status = process.wait(timeout=timeout)
except subprocess.TimeoutExpired:
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass

    deadline = time.monotonic() + 1.0
    while process.poll() is None and time.monotonic() < deadline:
        time.sleep(0.05)

    try:
        os.killpg(process.pid, 0)
    except ProcessLookupError:
        pass
    else:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass

    try:
        process.wait(timeout=1.0)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait(timeout=1.0)
    raise SystemExit(124)

raise SystemExit(status if status >= 0 else 128 - status)
PY
}

if run_capture "$details" claude mcp get pickforge-lanes; then
  if grep -Eq '^[[:space:]]*Scope:[[:space:]]*User config([[:space:]]+\([^[:cntrl:]]*\))?[[:space:]]*$' "$details" \
    && grep -Eq '^[[:space:]]*Type:[[:space:]]*stdio[[:space:]]*$' "$details" \
    && grep -Eq '^[[:space:]]*Command:[[:space:]]*pickforge-lanes-mcp[[:space:]]*$' "$details" \
    && grep -Eq '^[[:space:]]*Args:[[:space:]]*$' "$details"; then
    exit 0
  fi
  if ! run_capture "$private_dir/remove" claude mcp remove --scope user pickforge-lanes; then
    printf '%s\n' 'error: mismatched user-scoped pickforge-lanes MCP could not be removed' >&2
    exit 1
  fi
else
  get_status=$?
  if [ "$get_status" -eq 124 ]; then
    printf '%s\n' 'warning: pickforge-lanes MCP inspection timed out; configuration was not changed' >&2
    exit 0
  fi
  if ! grep -Eiq "^[[:space:]]*(No MCP server found with name:[[:space:]]*pickforge-lanes|No MCP server named[[:space:]]+['\"]?pickforge-lanes['\"]?|MCP server[[:space:]]+['\"]?pickforge-lanes['\"]?[[:space:]]+(was[[:space:]]+)?(not found|does not exist))([[:space:].]|$)" "$details"; then
    printf '%s\n' 'warning: pickforge-lanes MCP inspection failed; configuration was not changed' >&2
    exit 0
  fi
fi

if ! run_capture "$private_dir/add" claude mcp add --scope user pickforge-lanes -- pickforge-lanes-mcp; then
  printf '%s\n' 'error: pickforge-lanes MCP could not be configured' >&2
  exit 1
fi
