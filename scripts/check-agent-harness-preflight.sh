#!/usr/bin/env bash
set -u

ROOT="$(mktemp -d "${TMPDIR:-/tmp}/agent-harness-preflight-test.XXXXXX")" || exit 1
trap 'rm -rf "$ROOT"' EXIT HUP INT TERM
SOURCE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$SOURCE_ROOT/dot_local/bin/executable_agent-harness-preflight"
BASHRC="$SOURCE_ROOT/dot_bashrc"
ZSH_COMMON="$SOURCE_ROOT/.chezmoitemplates/zshrc-common"
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
if [[ "${PREFLIGHT_UNKNOWN:-}" == "$harness" ]]; then
  printf '%s\n' '{"checks":[{"required":true,"status":"unknown","message":"authentication status unavailable"},{"required":false,"status":"pass","message":"SECRET_SENTINEL"}]}'
  exit 0
fi
printf '%s\n' '{"checks":[{"required":true,"status":"pass","message":"ready"}]}'
SH
chmod +x "$HOME_DIR/.local/bin/agent-config-sync"
ln -s "$SCRIPT" "$HOME_DIR/.local/bin/agent-harness-preflight"

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

: >"$LOG"
if HOME="$HOME_DIR" PREFLIGHT_TEST_LOG="$LOG" PREFLIGHT_UNKNOWN=omp \
  "$SCRIPT" omp >"$ROOT/unknown-status.out" 2>&1; then
  fail 'required unknown status blocks launch'
elif grep -Fq 'authentication status unavailable' "$ROOT/unknown-status.out" \
  && ! grep -Fq 'SECRET_SENTINEL' "$ROOT/unknown-status.out"; then
  pass 'required unknown status fails closed without leaking unrelated output'
else
  fail 'required unknown status output contract'
fi

mkdir -p "$ROOT/bin"
cat >"$ROOT/bin/codex" <<'SH'
#!/usr/bin/env bash
printf 'codex %s\n' "$*" >>"$HARNESS_CALL_LOG"
SH
cat >"$ROOT/bin/pi" <<'SH'
#!/usr/bin/env bash
printf 'pi %s\n' "$*" >>"$HARNESS_CALL_LOG"
SH
chmod +x "$ROOT/bin/codex" "$ROOT/bin/pi"

: >"$LOG"
: >"$ROOT/bash-harness.log"
set +e
HOME="$HOME_DIR" PATH="$ROOT/bin:$PATH" PREFLIGHT_TEST_LOG="$LOG" PREFLIGHT_FAIL=codex \
  HARNESS_CALL_LOG="$ROOT/bash-harness.log" \
  bash --noprofile --norc -ic "source '$BASHRC'; codex login; codex" >"$ROOT/bash-wrapper.out" 2>&1
bash_rc=$?
set -e
if [[ "$bash_rc" -ne 0 ]] \
  && [[ "$(cat "$ROOT/bash-harness.log")" == 'codex --yolo login' ]] \
  && [[ "$(cat "$LOG")" == 'codex' ]]; then
  pass 'Bash wrapper permits Codex login recovery while blocking agent launch'
else
  fail 'Bash wrapper authentication recovery behavior'
fi

: >"$LOG"
: >"$ROOT/zsh-harness.log"
set +e
HOME="$HOME_DIR" PATH="$ROOT/bin:$PATH" PREFLIGHT_TEST_LOG="$LOG" PREFLIGHT_FAIL=pi \
  HARNESS_CALL_LOG="$ROOT/zsh-harness.log" \
  zsh -dfc "source '$ZSH_COMMON'; pi auth check --provider xai; pi" >"$ROOT/zsh-wrapper.out" 2>&1
zsh_rc=$?
set -e
if [[ "$zsh_rc" -ne 0 ]] \
  && [[ "$(cat "$ROOT/zsh-harness.log")" == 'pi auth check --provider xai' ]] \
  && [[ "$(cat "$LOG")" == 'pi' ]]; then
  pass 'Zsh wrapper permits Pi auth recovery while blocking agent launch'
else
  fail 'Zsh wrapper authentication recovery behavior'
fi

set +e
HOME="$HOME_DIR" PREFLIGHT_TEST_LOG="$LOG" "$SCRIPT" unknown >/dev/null 2>&1
rc=$?
set -e
if [[ "$rc" -eq 64 ]]; then pass 'unknown harness is rejected'; else fail 'unknown harness usage status'; fi

[[ "$failures" -eq 0 ]]
