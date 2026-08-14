#!/usr/bin/env bash
set -u

ROOT="$(mktemp -d "${TMPDIR:-/tmp}/agent-harness-preflight-test.XXXXXX")" || exit 1
trap 'rm -rf "$ROOT"' EXIT HUP INT TERM
SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/dot_local/bin/executable_agent-harness-preflight"
HOME_DIR="$ROOT/home"
LOG="$ROOT/calls.log"
mkdir -p "$HOME_DIR/.local/bin"

cat >"$HOME_DIR/.local/bin/agent-config-sync" <<'SH'
#!/usr/bin/env bash
harness=''
while [[ $# -gt 0 ]]; do
  if [[ "$1" == --only ]]; then harness="$2"; shift 2; else shift; fi
done
printf '%s\n' "$harness" >>"$PREFLIGHT_TEST_LOG"
if [[ "${PREFLIGHT_FAIL:-}" == "$harness" ]]; then
  printf '%s\n' '{"checks":[{"required":true,"status":"fail","message":"authentication expired"},{"required":false,"status":"pass","message":"SECRET_SENTINEL"}]}'
  exit 1
fi
printf '%s\n' '{"checks":[{"required":true,"status":"pass","message":"ready"}]}'
SH
chmod +x "$HOME_DIR/.local/bin/agent-config-sync"

failures=0
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1"; failures=$((failures + 1)); }

: >"$LOG"
if HOME="$HOME_DIR" PREFLIGHT_TEST_LOG="$LOG" "$SCRIPT" pi >"$ROOT/pi.out" 2>&1 \
  && [[ "$(tr '\n' ' ' <"$LOG")" == 'pi claude ' ]] \
  && grep -Fq 'Pi routes and Claude lane authentication are ready' "$ROOT/pi.out"; then
  pass 'Pi launch checks Pi plus Claude lane authentication'
else
  fail 'Pi launch dependency preflight'
fi

: >"$LOG"
if HOME="$HOME_DIR" PREFLIGHT_TEST_LOG="$LOG" "$SCRIPT" omp >"$ROOT/omp.out" 2>&1 \
  && [[ "$(tr '\n' ' ' <"$LOG")" == 'omp ' ]]; then
  pass 'non-Pi launch checks only its harness'
else
  fail 'targeted harness preflight'
fi

: >"$LOG"
if HOME="$HOME_DIR" PREFLIGHT_TEST_LOG="$LOG" PREFLIGHT_FAIL=claude \
  "$SCRIPT" pi >"$ROOT/fail.out" 2>&1; then
  fail 'failed dependency blocks launch'
elif grep -Fq 'claude is not ready' "$ROOT/fail.out" \
  && grep -Fq 'authentication expired' "$ROOT/fail.out" \
  && ! grep -Fq 'SECRET_SENTINEL' "$ROOT/fail.out"; then
  pass 'failure is actionable and secret-safe'
else
  fail 'failure output contract'
fi

set +e
HOME="$HOME_DIR" PREFLIGHT_TEST_LOG="$LOG" "$SCRIPT" unknown >/dev/null 2>&1
rc=$?
set -e
if [[ "$rc" -eq 64 ]]; then pass 'unknown harness is rejected'; else fail 'unknown harness usage status'; fi

[[ "$failures" -eq 0 ]]
