check_pickforge_lanes_deployment() {
  local skill settings_file
  local fake_home="$TMP/pickforge-lanes-home"
  local fake_bin="$TMP/pickforge-lanes-bin"
  local fake_log="$TMP/pickforge-lanes-claude.log"
  local run_log="$TMP/pickforge-lanes-run.log"
  local wrapper_log="$TMP/pickforge-lanes-wrapper.log"
  local descendant_pid_file="$TMP/pickforge-lanes-descendant.pid"
  local fake_private_root="$TMP/pickforge-lanes-private"
  local mode status started elapsed descendant_pid

  need "$PICKFORGE_LANES_WRAPPER"
  need "$PICKFORGE_LANES_CONFIGURE"
  need "$PICKFORGE_LANES_SKILL"
  need "$CLAUDE_SETTINGS"

  if [[ -f "$PICKFORGE_LANES_WRAPPER" ]] \
    && sh -n "$PICKFORGE_LANES_WRAPPER" \
    && grep -Fq '$HOME/Projects/Personal/pi-kit/mcp/server.ts' "$PICKFORGE_LANES_WRAPPER" \
    && grep -Fq 'command -v bun' "$PICKFORGE_LANES_WRAPPER" \
    && grep -Fq 'exec bun "$server" "$@"' "$PICKFORGE_LANES_WRAPPER"; then
    pass 'pickforge lanes wrapper has canonical server, bun/file guards, and exec'
  else
    err 'pickforge lanes wrapper contract invalid'
  fi

  rm -rf "$fake_home" "$fake_bin"
  mkdir -p "$fake_home/Projects/Personal/pi-kit/mcp" "$fake_bin"
  printf '%s\n' probe >"$fake_home/Projects/Personal/pi-kit/mcp/server.ts"
  cat >"$fake_bin/bun" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >"$PICKFORGE_WRAPPER_LOG"
EOF
  chmod 0755 "$fake_bin/bun"
  if HOME="$fake_home" PATH="$fake_bin:/usr/bin:/bin" PICKFORGE_WRAPPER_LOG="$wrapper_log" \
    "$PICKFORGE_LANES_WRAPPER" alpha beta >/dev/null 2>&1 \
    && grep -Fq "$fake_home/Projects/Personal/pi-kit/mcp/server.ts alpha beta" "$wrapper_log"; then
    pass 'pickforge lanes wrapper invokes bun with canonical server and forwarded arguments'
  else
    err 'pickforge lanes wrapper invocation probe failed'
  fi
  rm -f "$fake_home/Projects/Personal/pi-kit/mcp/server.ts"
  if HOME="$fake_home" PATH="$fake_bin:/usr/bin:/bin" PICKFORGE_WRAPPER_LOG="$wrapper_log" \
    "$PICKFORGE_LANES_WRAPPER" >/dev/null 2>&1; then
    err 'pickforge lanes wrapper accepted a missing server file'
  else
    pass 'pickforge lanes wrapper rejects a missing server file'
  fi
  printf '%s\n' probe >"$fake_home/Projects/Personal/pi-kit/mcp/server.ts"
  mkdir -p "$TMP/empty-bin"
  if HOME="$fake_home" PATH="$TMP/empty-bin" "$PICKFORGE_LANES_WRAPPER" >/dev/null 2>&1; then
    err 'pickforge lanes wrapper accepted a missing bun runtime'
  else
    pass 'pickforge lanes wrapper rejects a missing bun runtime'
  fi

  if [[ -f "$PICKFORGE_LANES_CONFIGURE" ]] \
    && sh -n "$PICKFORGE_LANES_CONFIGURE" \
    && grep -Fq 'umask 077' "$PICKFORGE_LANES_CONFIGURE" \
    && grep -Fq 'command -v python3' "$PICKFORGE_LANES_CONFIGURE" \
    && grep -Fq 'start_new_session=True' "$PICKFORGE_LANES_CONFIGURE" \
    && grep -Fq 'os.open(output_path, flags, 0o600)' "$PICKFORGE_LANES_CONFIGURE" \
    && grep -Fq 'os.killpg(process.pid, signal.SIGTERM)' "$PICKFORGE_LANES_CONFIGURE" \
    && grep -Fq 'os.killpg(process.pid, signal.SIGKILL)' "$PICKFORGE_LANES_CONFIGURE" \
    && grep -Fq 'claude mcp get pickforge-lanes' "$PICKFORGE_LANES_CONFIGURE" \
    && grep -Fq 'claude mcp remove --scope user pickforge-lanes' "$PICKFORGE_LANES_CONFIGURE" \
    && grep -Fq 'claude mcp add --scope user pickforge-lanes -- pickforge-lanes-mcp' "$PICKFORGE_LANES_CONFIGURE" \
    && ! grep -Fqi 'context7' "$PICKFORGE_LANES_CONFIGURE"; then
    pass 'pickforge lanes configure uses the required private Python process-group boundary'
  else
    err 'pickforge lanes configure source contract invalid'
  fi

  cat >"$fake_bin/claude" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$PICKFORGE_CLAUDE_LOG"
if [ "$1 $2 $3" = 'mcp get pickforge-lanes' ]; then
  case "$PICKFORGE_CLAUDE_MODE" in
    matching)
      printf '%s\n' 'pickforge-lanes:' '  Scope: User config (available in all your projects)' '  Type: stdio' '  Command: pickforge-lanes-mcp' '  Args:'
      ;;
    mismatch|remove_failure)
      printf '%s\n' 'pickforge-lanes:' '  Scope: User config (available in all your projects)' '  Type: stdio' '  Command: wrong-command' '  Args:' 'secret-probe-value'
      ;;
    extra_args)
      printf '%s\n' 'pickforge-lanes:' '  Scope: User config (available in all your projects)' '  Type: stdio' '  Command: pickforge-lanes-mcp' '  Args: --unexpected'
      ;;
    missing|add_failure)
      printf '%s\n' 'No MCP server named pickforge-lanes. Configured servers: context7' >&2
      exit 1
      ;;
    generic_get_error)
      printf '%s\n' 'transport unavailable' >&2
      exit 1
      ;;
    private_get_error)
      printf '%s\n' 'Authorization: Bearer secret-header-probe' 'token=secret-token-probe' >&2
      exit 1
      ;;
    timeout_descendant)
      printf '%s\n' 'Authorization: Bearer secret-timeout-probe'
      (
        trap '' TERM
        while :; do sleep 1; done
      ) &
      printf '%s\n' "$!" >"$PICKFORGE_DESCENDANT_PID_FILE"
      trap '' TERM
      wait
      ;;
  esac
elif [ "$PICKFORGE_CLAUDE_MODE" = add_failure ] \
  && [ "$1 $2 $3 $4 $5 $6 $7" = 'mcp add --scope user pickforge-lanes -- pickforge-lanes-mcp' ]; then
  printf '%s\n' 'X-Api-Key: secret-add-probe' >&2
  exit 1
elif [ "$PICKFORGE_CLAUDE_MODE" = remove_failure ] \
  && [ "$1 $2 $3 $4 $5" = 'mcp remove --scope user pickforge-lanes' ]; then
  printf '%s\n' 'Authorization: Bearer secret-remove-probe' >&2
  exit 1
fi
EOF
  chmod 0755 "$fake_bin/claude"

  mkdir -p "$fake_private_root"
  for mode in matching mismatch extra_args missing generic_get_error private_get_error \
    add_failure remove_failure timeout_descendant; do
    : >"$fake_log"
    : >"$run_log"
    rm -f "$descendant_pid_file"
    started="$(python3 -c 'import time; print(time.monotonic())')"
    if HOME="$fake_home" PATH="$fake_bin:/usr/bin:/bin" TMPDIR="$fake_private_root" \
      PICKFORGE_CLAUDE_LOG="$fake_log" PICKFORGE_CLAUDE_MODE="$mode" \
      PICKFORGE_DESCENDANT_PID_FILE="$descendant_pid_file" PICKFORGE_LANES_MCP_TIMEOUT=1 \
      "$PICKFORGE_LANES_CONFIGURE" >"$run_log" 2>&1; then
      status=0
    else
      status=$?
    fi
    elapsed="$(python3 -c 'import sys, time; print(time.monotonic() - float(sys.argv[1]))' "$started")"
    case "$mode" in
      add_failure|remove_failure)
        [[ "$status" -ne 0 ]] \
          && pass "pickforge lanes configure reports mutation failure: $mode" \
          || err "pickforge lanes configure hid mutation failure: $mode"
        ;;
      *)
        [[ "$status" -eq 0 ]] \
          || err "pickforge lanes fake-Claude probe failed: $mode (status $status)"
        ;;
    esac
    if grep -Eiq 'secret-|authorization:|x-api-key:|token=' "$run_log"; then
      err "pickforge lanes configure leaked private output: $mode"
    else
      pass "pickforge lanes configure keeps command output private: $mode"
    fi
    if find "$fake_private_root" -mindepth 1 -print -quit | grep -q .; then
      err "pickforge lanes configure retained plaintext output: $mode"
    else
      pass "pickforge lanes configure removes private output: $mode"
    fi
    if grep -Fqi context7 "$fake_log"; then
      err "pickforge lanes configure touched Context7: $mode"
    else
      pass "pickforge lanes configure leaves Context7 untouched: $mode"
    fi
    case "$mode" in
      matching)
        if [[ "$(wc -l <"$fake_log" | tr -d ' ')" == 1 ]] \
          && grep -Fxq 'mcp get pickforge-lanes' "$fake_log"; then
          pass 'pickforge lanes configure is idempotent for canonical registration'
        else
          err 'pickforge lanes configure changed canonical registration'
        fi
        ;;
      mismatch|extra_args)
        if grep -Fxq 'mcp remove --scope user pickforge-lanes' "$fake_log" \
          && grep -Fxq 'mcp add --scope user pickforge-lanes -- pickforge-lanes-mcp' "$fake_log" \
          && [[ "$(wc -l <"$fake_log" | tr -d ' ')" == 3 ]]; then
          pass "pickforge lanes configure replaces mismatched user registration: $mode"
        else
          err "pickforge lanes configure mismatch repair contract failed: $mode"
        fi
        ;;
      missing)
        if grep -Fxq 'mcp add --scope user pickforge-lanes -- pickforge-lanes-mcp' "$fake_log" \
          && ! grep -Fq 'mcp remove' "$fake_log"; then
          pass 'pickforge lanes configure adds genuinely missing registration'
        else
          err 'pickforge lanes configure missing-registration contract failed'
        fi
        ;;
      generic_get_error|private_get_error)
        if grep -Fxq 'mcp get pickforge-lanes' "$fake_log" \
          && ! grep -Eq 'mcp (add|remove)' "$fake_log"; then
          pass "pickforge lanes configure leaves registration unchanged after ambiguous get error: $mode"
        else
          err "pickforge lanes configure mutated registration after ambiguous get error: $mode"
        fi
        ;;
      add_failure)
        if grep -Fxq 'mcp add --scope user pickforge-lanes -- pickforge-lanes-mcp' "$fake_log" \
          && ! grep -Fq 'mcp remove' "$fake_log"; then
          pass 'pickforge lanes configure propagates add failure without removal'
        else
          err 'pickforge lanes configure add-failure contract failed'
        fi
        ;;
      remove_failure)
        if grep -Fxq 'mcp remove --scope user pickforge-lanes' "$fake_log" \
          && ! grep -Fq 'mcp add' "$fake_log"; then
          pass 'pickforge lanes configure propagates user-scoped removal failure without add'
        else
          err 'pickforge lanes configure removal-failure contract failed'
        fi
        ;;
      timeout_descendant)
        if grep -Fxq 'mcp get pickforge-lanes' "$fake_log" \
          && ! grep -Eq 'mcp (add|remove)' "$fake_log" \
          && python3 -c 'import sys; raise SystemExit(float(sys.argv[1]) > 4)' "$elapsed"; then
          pass 'pickforge lanes configure bounds timeout and avoids mutation'
        else
          err "pickforge lanes configure timeout contract failed after ${elapsed}s"
        fi
        if [[ -s "$descendant_pid_file" ]]; then
          descendant_pid="$(<"$descendant_pid_file")"
          if kill -0 "$descendant_pid" 2>/dev/null; then
            err 'pickforge lanes configure left a timeout descendant running'
            kill -KILL "$descendant_pid" 2>/dev/null || true
          else
            pass 'pickforge lanes configure reaps timeout descendants'
          fi
        else
          err 'pickforge lanes timeout probe did not record its descendant'
        fi
        ;;
    esac
  done

  if jq -e '.skills["multi-model-lanes"] == ["claude", "pi"]' "$MANIFEST" >/dev/null 2>&1 \
    && [[ "$(tr -d '\n' <"$ROOT/dot_claude/skills/symlink_multi-model-lanes" 2>/dev/null)" == '../../.agents/skills/multi-model-lanes' ]] \
    && [[ "$(tr -d '\n' <"$ROOT/dot_pi/agent/skills/symlink_multi-model-lanes" 2>/dev/null)" == '../../../.agents/skills/multi-model-lanes' ]] \
    && [[ ! -e "$ROOT/dot_agents/skills/multi-model-lanes/SKILL.md" ]]; then
    pass 'multi-model lanes canonical source is encrypted with Claude/Pi relative symlinks only'
  else
    err 'multi-model lanes manifest, encryption, or symlink matrix invalid'
  fi

  if skill="$(chezmoi "${SRC[@]}" decrypt "$PICKFORGE_LANES_SKILL" 2>/dev/null)"; then
    if grep -Fq 'global model policy' <<<"$skill" \
      && grep -Fq 'Pi native lanes' <<<"$skill" \
      && grep -Fq 'Claude-to-Claude' <<<"$skill" \
      && grep -Fq 'MCP' <<<"$skill" \
      && grep -Fq 'model, effort, mode, cwd, and rationale' <<<"$skill" \
      && grep -Fq 'mcp__pickforge-lanes__lanes_spawn' <<<"$skill" \
      && grep -Fq 'mcp__pickforge-lanes__lanes_status' <<<"$skill" \
      && grep -Fq 'mcp__pickforge-lanes__lanes_wait' <<<"$skill" \
      && grep -Fq 'mcp__pickforge-lanes__lanes_abandon' <<<"$skill" \
      && grep -Fq 'Do not poll' <<<"$skill" \
      && grep -Fq 'Never use a foreground or synchronous provider CLI as fallback' <<<"$skill"; then
      pass 'multi-model lanes skill enforces native/background routing and lifecycle invariants'
    else
      err 'multi-model lanes skill missing required routing or background-only invariants'
    fi
  else
    err 'multi-model lanes encrypted canonical skill is unreadable'
  fi
  unset skill

  settings_file="$(mktemp "$TMP/claude-settings.XXXXXX")"
  chmod 0600 "$settings_file"
  if chezmoi "${SRC[@]}" cat "$HOME/.claude/settings.json" >"$settings_file" 2>/dev/null \
    && python3 - "$settings_file" <<'PY'
import json
import os
import stat
import sys

assert stat.S_IMODE(os.stat(sys.argv[1]).st_mode) == 0o600
with open(sys.argv[1], encoding="utf-8") as source:
    settings = json.load(source)
assert isinstance(settings, dict)
assert isinstance(settings.get("permissions"), dict)
allow = settings["permissions"].get("allow")
assert isinstance(allow, list)
expected = {
    "mcp__pickforge-lanes__lanes_spawn",
    "mcp__pickforge-lanes__lanes_status",
    "mcp__pickforge-lanes__lanes_wait",
    "mcp__pickforge-lanes__lanes_abandon",
}
pickforge_permissions = [
    permission
    for permission in allow
    if isinstance(permission, str)
    and permission.startswith("mcp__pickforge-lanes__")
]
assert set(pickforge_permissions) == expected
assert len(pickforge_permissions) == len(expected)
assert any(isinstance(value, str) and value.startswith("Bash") for value in allow)
assert any(isinstance(value, str) and value.startswith("Bash") and "git" in value.lower() for value in allow)

def strings(value):
    if isinstance(value, str):
        yield value
    elif isinstance(value, list):
        for item in value:
            yield from strings(item)
    elif isinstance(value, dict):
        for item in value.values():
            yield from strings(item)

all_strings = list(strings(settings))
assert not any(("/home/" + "dev/.claude/hooks/decision-audit-gate.sh") in value for value in all_strings)
assert any("$HOME/.claude/hooks/decision-audit-gate.sh" in value for value in all_strings)
assert not any("rtk hook claude" in value for value in all_strings)
PY
  then
    pass 'Claude settings retain Bash/Git shape and exact pickforge-lanes permissions'
    pass 'Claude settings use portable decision hook and exclude retired RTK hook'
  else
    err 'Claude settings structural invariants failed'
  fi
  rm -f "$settings_file"
}

