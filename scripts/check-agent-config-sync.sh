#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
SRC=(--source "$ROOT")
fail=0
MODE=default
STRICT_PREFLIGHT=0
for arg in "$@"; do
  case "$arg" in
    --check-live-migration) MODE=live ;;
    --strict-preflight) STRICT_PREFLIGHT=1 ;;
  esac
done

pass() { printf 'OK  %s\n' "$*"; }
err()  { printf 'ERR %s\n' "$*" >&2; fail=1; }
need() { [[ -f "$1" ]] || err "missing: $1"; }

source_absent() {
  local path="$1"
  if [[ -e "$ROOT/$path" || -L "$ROOT/$path" ]]; then
    err "retired source remains: $path"
  else
    pass "retired source absent: $path"
  fi
}

expand_home() {
  local p="$1"
  if [[ "$p" == "~/"* ]]; then
    printf '%s\n' "${HOME}/${p#"~/"}"
  elif [[ "$p" == "~" ]]; then
    printf '%s\n' "$HOME"
  else
    printf '%s\n' "$p"
  fi
}

dirs_identical() {
  local a="$1" b="$2"
  [[ -d "$a" && -d "$b" ]] || return 1
  diff -rq "$a" "$b" >/dev/null 2>&1
}

managed_regular_file_unchanged() {
  local live="$1"
  local state expected actual
  [[ -f "$live" && ! -L "$live" ]] || return 1
  state="$(chezmoi state get --bucket=entryState --key="$live" 2>/dev/null || true)"
  expected="$(jq -r '.contentsSHA256 // empty' <<<"$state" 2>/dev/null || true)"
  [[ -n "$expected" ]] || return 1
  read -r actual _ < <(sha256sum "$live")
  [[ "$actual" == "$expected" ]]
}

validate_omp_agent_override() {
  local role="$1" path="$2"

  if [[ ! -f "$path" ]]; then
    err "OMP ${role} override missing: $path"
    return
  fi

  if grep -Eq '^(model|thinkingLevel):' "$path"; then
    err "OMP ${role} override fixes a model or effort instead of deferring selection"
  else
    pass "OMP ${role} override defers model and effort selection"
  fi

  if [[ "$role" == reviewer ]]; then
    if grep -Fq 'output:' "$path" \
      && grep -Fq 'overall_correctness:' "$path" \
      && grep -Fq 'findings:' "$path"; then
      pass 'OMP reviewer override retains structured output'
    else
      err 'OMP reviewer override missing structured output schema'
    fi
    if grep -Fq 'Bash is read-only:' "$path" \
      && grep -Fq 'You NEVER make file edits or trigger builds.' "$path" \
      && grep -Fq 'Every finding MUST be patch-anchored and evidence-backed.' "$path"; then
      pass 'OMP reviewer override retains read-only review contract'
    else
      err 'OMP reviewer override missing read-only review contract'
    fi
  fi
}

check_omp_agent_override_sources() {
  validate_omp_agent_override task "$OMP_TASK_OVERRIDE"
  validate_omp_agent_override reviewer "$OMP_REVIEWER_OVERRIDE"
}

check_live_omp_agent_overrides() {
  local live_dir="${HOME}/.omp/agent/agents"
  local role live_override canonical_override

  if [[ ! -e "$live_dir" ]]; then
    if [[ "$STRICT_PREFLIGHT" -eq 1 ]]; then
      pass "live OMP agent overrides not yet applied: $live_dir"
    else
      err "live OMP agent overrides missing: $live_dir"
    fi
    return
  fi
  if [[ ! -d "$live_dir" || -L "$live_dir" ]]; then
    err "live OMP agent overrides must be a managed regular directory: $live_dir"
    return
  fi

  for role in task reviewer; do
    live_override="$live_dir/${role}.md"
    canonical_override="$OMP_AGENT_OVERRIDES_DIR/${role}.md"

    if [[ -L "$live_override" ]]; then
      err "live OMP ${role} override must be a managed regular file: $live_override"
      continue
    fi
    if [[ ! -f "$live_override" ]]; then
      err "live OMP ${role} override missing or not a regular file: $live_override"
      continue
    fi
    if [[ ! -f "$canonical_override" ]]; then
      err "canonical OMP ${role} override missing: $canonical_override"
      continue
    fi

    if cmp -s "$live_override" "$canonical_override"; then
      validate_omp_agent_override "$role" "$live_override"
      pass "live OMP ${role} override matches canonical source"
      continue
    fi

    if [[ "$STRICT_PREFLIGHT" -eq 1 ]] && managed_regular_file_unchanged "$live_override"; then
      pass "live OMP ${role} override has managed pending drift"
      continue
    fi
    err "live OMP ${role} override differs from canonical source"
  done
}


MANIFEST="$ROOT/dot_agents/skill-targets.json"
SKILL_LOCK="$ROOT/dot_agents/dot_skill-lock.json"
MCP_REGISTRY="$ROOT/dot_agents/mcp-targets.json"
OMP_MCP="$ROOT/dot_omp/agent/mcp.json"
PICKFORGE_LANES_WRAPPER="$ROOT/dot_local/bin/executable_pickforge-lanes-mcp"
PICKFORGE_LANES_CONFIGURE="$ROOT/run_onchange_after_configure_pickforge_lanes_mcp.sh"
PICKFORGE_LANES_SKILL="$ROOT/dot_agents/skills/multi-model-lanes/encrypted_SKILL.md.age"
CLAUDE_SETTINGS="$ROOT/dot_claude/encrypted_settings.json.age"
OMP_AGENT_OVERRIDES_DIR="$ROOT/dot_omp/agent/agents"
OMP_TASK_OVERRIDE="$OMP_AGENT_OVERRIDES_DIR/task.md"
OMP_REVIEWER_OVERRIDE="$OMP_AGENT_OVERRIDES_DIR/reviewer.md"

RETIRED_SOURCE_PATHS=(
  dot_claude-personal
  dot_config/agent-profiles
  dot_config/rtk
  Projects/Personal/dot_codex
  Projects/Personal/private_dot_agent-safety
  dot_local/bin/executable_claude-profile
  dot_local/bin/executable_claude-default
  dot_local/bin/executable_claude-personal
  dot_local/bin/executable_agent-profile-doctor
  dot_claude/private_RTK.md
  private_dot_factory/bin/executable_frun
  .chezmoitemplates/claude-restricted.md
  .chezmoitemplates/claude-personal-lite.md
)

RETIRED_SKILL_LOCK_ENTRIES=(
  caveman
  caveman-commit
  caveman-compress
  caveman-help
  caveman-review
  caveman-stats
  cavecrew
  compress
)

RETIRED_TARGET_PATHS=(
  .claude-personal
  .config/agent-profiles
  .config/rtk
  .local/bin/agent-profile-doctor
  .local/bin/claude-default
  .local/bin/claude-personal
  .local/bin/claude-profile
  .factory/bin/frun
  .claude/RTK.md
  Projects/Personal/.codex
  Projects/Personal/.agent-safety
  .agents/skills/superpowers
  .config/superpowers
  .codex/superpowers
  .agents/skills/caveman
  .agents/skills/caveman-commit
  .agents/skills/caveman-compress
  .agents/skills/caveman-help
  .agents/skills/caveman-review
  .agents/skills/caveman-stats
  .agents/skills/cavecrew
  .agents/skills/compress
)

RUNTIME_SOURCE_PATHS=(
  private_dot_hermes/private_skills/dot_curator_backups
  private_dot_hermes/private_skills/encrypted_empty_dot_usage.json.lock.age
  private_dot_hermes/private_skills/encrypted_private_dot_bundled_manifest.age
  private_dot_hermes/private_skills/encrypted_private_dot_curator_state.age
  private_dot_hermes/private_skills/encrypted_private_dot_usage.json.age
  private_dot_hermes/private_skills/dot_hub/encrypted_private_lock.json.age
  dot_pi/agent/sessions
  dot_pi/agent/encrypted_run-history.jsonl.age
  dot_pi/agent/encrypted_mcp-cache.json.age
  dot_pi/agent/encrypted_mcp-npx-cache.json.age
  dot_pi/agent/encrypted_mcp-onboarding.json.age
  dot_pi/agent/pi-hermes-memory/encrypted_dot_skills-migrated-to-extension-storage.age
  dot_codex/encrypted_private_auth.json.age
  dot_codex/encrypted_private_config.toml.age
  dot_codex/rules
  dot_codex/version.json
  dot_codex/archived_sessions
  dot_codex/cache
  dot_codex/history.jsonl
  dot_codex/log
  dot_codex/memories
  dot_codex/sessions
  dot_codex/shell_snapshots
  dot_codex/sqlite
  dot_codex/tmp
  'dot_codex/*.sqlite*'
  dot_omp/agent/sessions
  dot_omp/agent/terminal-sessions
  dot_omp/agent/blobs
  dot_omp/agent/cache
  dot_omp/agent/last-changelog-version
  dot_omp/autoqa.db
  dot_omp/autoqa.db-wal
  dot_omp/autoqa.db-shm
  dot_omp/agent/agent.db
  dot_omp/agent/history.db
  dot_omp/agent/models.db
  dot_omp/logs
  dot_omp/puppeteer
  private_dot_factory/private_background-processes.json
  private_dot_factory/private_background-tasks.json
  private_dot_factory/certs/system-certs-cache.json
  private_dot_factory/cli-hints.json
  private_dot_factory/private_host.json
  private_dot_factory/bin/dot_rg-version
)

RUNTIME_IGNORE_PATHS=(
  .hermes/skills/.bundled_manifest
  .hermes/skills/.curator_backups
  .hermes/skills/.curator_state
  .hermes/skills/.usage.json
  .hermes/skills/.usage.json.lock
  .hermes/skills/.hub/lock.json
  .pi/agent/sessions
  .pi/agent/run-history.jsonl
  .pi/agent/mcp-cache.json
  .pi/agent/mcp-npx-cache.json
  .pi/agent/mcp-onboarding.json
  .pi/agent/pi-hermes-memory/.skills-migrated-to-extension-storage
  .claude/.credentials.json
  .claude/history.jsonl
  .claude/plugins
  .claude/projects
  .codex/auth.json
  .codex/config.toml
  .codex/rules
  .codex/version.json
  .codex/archived_sessions
  .codex/cache
  .codex/history.jsonl
  .codex/log
  .codex/memories
  .codex/sessions
  .codex/shell_snapshots
  .codex/sqlite
  .codex/tmp
  '.codex/*.sqlite*'
  .omp/agent/sessions
  .omp/agent/terminal-sessions
  .omp/agent/blobs
  .omp/agent/cache
  .omp/agent/last-changelog-version
  .omp/autoqa.db
  .omp/autoqa.db-wal
  .omp/autoqa.db-shm
  .omp/agent/*.db
  .omp/logs
  .omp/cache
  .omp/install-id
  .omp/gpu_cache.json
  .omp/puppeteer
  .factory/background-processes.json
  .factory/background-tasks.json
  .factory/certs/system-certs-cache.json
  .factory/cli-hints.json
  .factory/host.json
  .factory/bin/.rg-version
)

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
    && grep -Fq '$HOME/Projects/Pickforge/pickforge-platform/packages/pi-kit/mcp/server.ts' "$PICKFORGE_LANES_WRAPPER" \
    && grep -Fq 'command -v bun' "$PICKFORGE_LANES_WRAPPER" \
    && grep -Fq 'exec bun "$server" "$@"' "$PICKFORGE_LANES_WRAPPER"; then
    pass 'pickforge lanes wrapper has canonical server, bun/file guards, and exec'
  else
    err 'pickforge lanes wrapper contract invalid'
  fi

  rm -rf "$fake_home" "$fake_bin"
  mkdir -p "$fake_home/Projects/Pickforge/pickforge-platform/packages/pi-kit/mcp" "$fake_bin"
  printf '%s\n' probe >"$fake_home/Projects/Pickforge/pickforge-platform/packages/pi-kit/mcp/server.ts"
  cat >"$fake_bin/bun" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >"$PICKFORGE_WRAPPER_LOG"
EOF
  chmod 0755 "$fake_bin/bun"
  if HOME="$fake_home" PATH="$fake_bin:/usr/bin:/bin" PICKFORGE_WRAPPER_LOG="$wrapper_log" \
    "$PICKFORGE_LANES_WRAPPER" alpha beta >/dev/null 2>&1 \
    && grep -Fq "$fake_home/Projects/Pickforge/pickforge-platform/packages/pi-kit/mcp/server.ts alpha beta" "$wrapper_log"; then
    pass 'pickforge lanes wrapper invokes bun with canonical server and forwarded arguments'
  else
    err 'pickforge lanes wrapper invocation probe failed'
  fi
  rm -f "$fake_home/Projects/Pickforge/pickforge-platform/packages/pi-kit/mcp/server.ts"
  if HOME="$fake_home" PATH="$fake_bin:/usr/bin:/bin" PICKFORGE_WRAPPER_LOG="$wrapper_log" \
    "$PICKFORGE_LANES_WRAPPER" >/dev/null 2>&1; then
    err 'pickforge lanes wrapper accepted a missing server file'
  else
    pass 'pickforge lanes wrapper rejects a missing server file'
  fi
  printf '%s\n' probe >"$fake_home/Projects/Pickforge/pickforge-platform/packages/pi-kit/mcp/server.ts"
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
assert not any("/home/dev/.claude/hooks/decision-audit-gate.sh" in value for value in all_strings)
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

check_runtime_exclusions() {
  local path
  for path in "${RUNTIME_SOURCE_PATHS[@]}"; do
    compgen -G "$ROOT/$path" >/dev/null && err "runtime state still tracked: $path"
  done
  for path in "${RUNTIME_IGNORE_PATHS[@]}"; do
    grep -Fxq "$path" "$ROOT/.chezmoiignore" || err "runtime ignore missing: $path"
  done
  [[ "$fail" -eq 0 ]] && pass 'runtime state excluded from chezmoi source'
  return 0
}

check_retired_target_removals() {
  local removal_file="$ROOT/.chezmoiremove"
  local expected_file="$TMP/expected-chezmoiremove"
  local path count

  need "$removal_file"
  [[ -f "$removal_file" ]] || return
  printf '%s\n' "${RETIRED_TARGET_PATHS[@]}" >"$expected_file"

  for path in "${RETIRED_TARGET_PATHS[@]}"; do
    count="$(grep -Fxc -- "$path" "$removal_file" || true)"
    if [[ "$count" -eq 1 ]]; then
      pass "stable retirement entry present once: $path"
    else
      err "stable retirement entry count for $path: $count"
    fi
  done

  if cmp -s "$expected_file" "$removal_file"; then
    pass 'retirement list exactly matches stable target paths'
  else
    err 'retirement list differs from the exact stable target paths'
  fi

  if awk '
    ((index($0, "*") || index($0, "?") || index($0, "[")) \
      && $0 ~ /(^|\/)(plugins?|caches?)(\/|$)/) { found=1 }
    END { exit !found }
  ' "$removal_file"; then
    err 'retirement list contains a broad plugin/cache wildcard pattern'
  else
    pass 'retirement list rejects broad plugin/cache wildcard patterns'
  fi
}

check_retired_target_apply() {
  local DEST="$TMP/retirement-dest"
  local removal_source="$TMP/retirement-source"
  local path sentinel
  local preview_log="$TMP/retirement-preview.log"
  local apply_log="$TMP/retirement-apply.log"

  mkdir -p "$DEST" "$removal_source"
  cp "$ROOT/.chezmoiremove" "$removal_source/.chezmoiremove"
  for path in "${RETIRED_TARGET_PATHS[@]}"; do
    case "$path" in
      .local/bin/*|.factory/bin/frun|.claude/RTK.md)
        mkdir -p "$DEST/${path%/*}"
        printf 'retired\n' >"$DEST/$path"
        ;;
      *)
        mkdir -p "$DEST/$path"
        printf 'retired\n' >"$DEST/$path/sentinel"
        ;;
    esac
  done
  mkdir -p "$DEST/.claude/plugins/cache" "$DEST/.codex/cache"
  printf 'keep\n' >"$DEST/.claude/global-sentinel"
  printf 'keep\n' >"$DEST/.claude/plugins/cache/sentinel"
  printf 'keep\n' >"$DEST/.codex/global-sentinel"
  printf 'keep\n' >"$DEST/.codex/cache/sentinel"

  if (
    cd "$removal_source"
    chezmoi -S "$PWD" --persistent-state "$TMP/retirement-state.boltdb" -D "$DEST" apply --dry-run --verbose
  ) >"$preview_log" 2>&1; then
    pass 'retirement apply preview succeeds in temporary destination'
  else
    err "retirement apply preview failed: $(tr '\n' ' ' <"$preview_log")"
    return
  fi
  if (
    cd "$removal_source"
    chezmoi -S "$PWD" --persistent-state "$TMP/retirement-state.boltdb" -D "$DEST" apply --force --no-tty
  ) >"$apply_log" 2>&1; then
    pass 'retirement apply succeeds in temporary destination'
  else
    err "retirement apply failed: $(tr '\n' ' ' <"$apply_log")"
    return
  fi

  for path in "${RETIRED_TARGET_PATHS[@]}"; do
    if [[ ! -e "$DEST/$path" && ! -L "$DEST/$path" ]]; then
      pass "retired target removed from temporary destination: $path"
    else
      err "retired target remains in temporary destination: $path"
    fi
  done
  for sentinel in \
    .claude/global-sentinel \
    .claude/plugins/cache/sentinel \
    .codex/global-sentinel \
    .codex/cache/sentinel; do
    if [[ -f "$DEST/$sentinel" ]]; then
      pass "unrelated temporary sentinel preserved: $sentinel"
    else
      err "unrelated temporary sentinel removed: $sentinel"
    fi
  done
}

check_live_retired_targets() {
  local path live
  for path in "${RETIRED_TARGET_PATHS[@]}"; do
    live="$HOME/$path"
    if [[ ! -e "$live" && ! -L "$live" ]]; then
      pass "live retired target absent: $live"
    elif [[ "$STRICT_PREFLIGHT" -eq 1 ]]; then
      pass "live retired target pending removal: $live"
    else
      err "live retired target remains: $live"
    fi
  done
}

check_live_retired_target_regressions() {
  local seeded_home="$TMP/live-retirement-home"
  local seeded_path="${RETIRED_TARGET_PATHS[0]}"
  mkdir -p "$seeded_home/$seeded_path"
  printf '%s\n' retired >"$seeded_home/$seeded_path/sentinel"

  if (HOME="$seeded_home"; STRICT_PREFLIGHT=1; fail=0; \
    check_live_retired_targets >/dev/null 2>&1; [[ "$fail" -eq 0 ]]); then
    pass 'strict live preflight permits seeded pending retirement'
  else
    err 'strict live preflight rejected seeded pending retirement'
  fi
  if (HOME="$seeded_home"; STRICT_PREFLIGHT=0; fail=0; \
    check_live_retired_targets >/dev/null 2>&1; [[ "$fail" -ne 0 ]]); then
    pass 'normal live check rejects seeded stable retired target'
  else
    err 'normal live check accepted seeded stable retired target'
  fi
}

check_active_retired_references() {
  local matches
  if matches="$(rg -n -i --hidden \
    --glob '!.git' \
    --glob '!.git/**' \
    --glob '!docs/specs/**' \
    --glob '!docs/plans/**' \
    --glob '!.chezmoiremove' \
    --glob '!scripts/check-agent-config-sync.sh' \
    'claude-personal|claude-default|claude-profile|agentProfile|agent-profiles|Projects/Personal/\.codex|\.agent-safety|superpowers|\brtk\b|RTK\.md|\bfrun\b|caveman|cavecrew' \
    .)"; then
    err 'active source contains retired profile/tooling references'
    printf '%s\n' "$matches" >&2
  else
    pass 'active source excludes retired profile/tooling references'
  fi
}

check_active_target_completeness() {
  local sync_command="$ROOT/dot_local/bin/executable_agent-config-sync"
  local source_path target command hook_name hook_source entry
  local -a metadata_targets=(
    'dot_agents/dot_skill-lock.json|.agents/.skill-lock.json'
    'dot_agents/skill-targets.json|.agents/skill-targets.json'
    'dot_agents/mcp-targets.json|.agents/mcp-targets.json'
    'dot_local/bin/executable_pickforge-lanes-mcp|.local/bin/pickforge-lanes-mcp'
  )
  local -a opencode_targets=(
    'dot_config/opencode/AGENTS.md|.config/opencode/AGENTS.md'
    'dot_config/opencode/README.md|.config/opencode/README.md'
  )

  need "$sync_command"
  [[ -f "$sync_command" ]] || return

  for source_path in "$ROOT"/dot_agents/*.md; do
    [[ -f "$source_path" ]] || continue
    target=".agents/${source_path##*/}"
    if grep -Fq '"${HOME}/'"$target"'"' "$sync_command"; then
      pass "active target includes top-level agent policy: $target"
    else
      err "active target missing top-level agent policy: $target"
    fi
  done

  for entry in "${metadata_targets[@]}"; do
    source_path="${entry%%|*}"
    target="${entry#*|}"
    need "$ROOT/$source_path"
    if [[ -f "$ROOT/$source_path" ]] \
      && grep -Fq '"${HOME}/'"$target"'"' "$sync_command"; then
      pass "active target includes agent metadata registry: $target"
    else
      err "active target missing agent metadata registry: $target"
    fi
  done

  for entry in "${opencode_targets[@]}"; do
    source_path="${entry%%|*}"
    target="${entry#*|}"
    need "$ROOT/$source_path"
    if [[ -f "$ROOT/$source_path" ]] \
      && grep -Fq '"${HOME}/'"$target"'"' "$sync_command"; then
      pass "active target includes OpenCode policy/doc: $target"
    else
      err "active target missing OpenCode policy/doc: $target"
    fi
  done

  need "$ROOT/private_dot_factory/hooks.json"
  [[ -f "$ROOT/private_dot_factory/hooks.json" ]] || return
  if ! jq -e . "$ROOT/private_dot_factory/hooks.json" >/dev/null 2>&1; then
    err 'Factory hooks.json is not valid JSON'
    return
  fi
  pass 'Factory hooks JSON valid'
  if ! grep -Fq '"${HOME}/.factory/hooks.json"' "$sync_command"; then
    err 'active target missing Factory hooks.json'
    return
  fi

  while IFS= read -r command; do
    case "$command" in
      */.factory/hooks/*.sh) ;;
      *) continue ;;
    esac
    hook_name="${command##*/}"
    hook_source="$ROOT/private_dot_factory/hooks/executable_${hook_name}"
    [[ -f "$hook_source" || -f "$hook_source.tmpl" ]] || continue
    target=".factory/hooks/$hook_name"
    if grep -Fq '"${HOME}/'"$target"'"' "$sync_command"; then
      pass "active target includes managed Factory hook: $target"
    else
      err "active target missing managed Factory hook: $target"
    fi
  done < <(jq -r '.. | objects | .command? // empty | select(type == "string")' \
    "$ROOT/private_dot_factory/hooks.json" | sort -u)
}

check_sync_command_flow() {
  local flow_source="$TMP/sync-flow-source"
  local flow_home="$TMP/sync-flow-home"
  local divergent_home="$TMP/sync-flow-divergent-home"
  local malformed_home="$TMP/sync-flow-malformed-home"
  local flow_log="$TMP/sync-flow.log"
  local flow_error="$TMP/sync-flow.err"
  local all_absent_log="$TMP/sync-flow-all-absent.log"
  local all_absent_error="$TMP/sync-flow-all-absent.err"
  local divergent_log="$TMP/sync-flow-divergent.log"
  local malformed_log="$TMP/sync-flow-malformed.log"
  local malformed_error="$TMP/sync-flow-malformed.err"
  local script_marker="$TMP/sync-flow-script-marker"
  local configure_log="$TMP/sync-flow-configure.log"
  local expected_log="$TMP/sync-flow-expected.log"
  local source_path
  local -a active_source_files=(
    dot_zshrc
    dot_bashrc
    dot_claude/CLAUDE.md
    dot_claude/rules/context7.md
    dot_claude/settings.json
    dot_claude/hooks/executable_decision-audit-gate.sh
    dot_claude/skills/kickoff/SKILL.md
    dot_claude/skills/ship-pr/SKILL.md
    dot_claude/skills/audit-report/SKILL.md
    dot_claude/skills/pickgauge-usage/SKILL.md
    dot_claude/skills/plan-issue/SKILL.md
    dot_claude/skills/x-research/SKILL.md
    dot_claude/skills/model-runners/SKILL.md
    dot_codex/AGENTS.md
    dot_codex/skills/model-orchestration/SKILL.md
    dot_codex/skills/ship-pr/SKILL.md
    dot_grok/AGENTS.md
    dot_grok/skills/model-orchestration/SKILL.md
    dot_pi/agent/AGENTS.md
    dot_pi/agent/extensions/decision-audit-gate.ts
    dot_pi/agent/skills/symlink_probe
    dot_omp/agent/AGENTS.md
    dot_omp/agent/config.yml
    dot_omp/agent/agents/task.md
    dot_omp/agent/mcp.json
    dot_omp/agent/extensions/decision-audit-gate.ts
    dot_factory/AGENTS.md
    dot_factory/hooks/model-flow-reminder.sh
    dot_factory/hooks/decision-audit-gate.sh
    dot_factory/hooks/executable_kde-notify.sh
    dot_factory/hooks.json
    dot_config/opencode/AGENTS.md
    dot_config/opencode/README.md
    dot_agents/dot_skill-lock.json
    dot_agents/mcp-targets.json
    dot_agents/skill-targets.json
    dot_agents/desktop-capture.md
    dot_agents/browser-use.md
    dot_agents/codex-lane-override.md
    dot_hermes/SOUL.md
    dot_agents/skills/probe/SKILL.md
    dot_local/bin/executable_sudo-askpass
    dot_local/bin/executable_pickforge-lanes-mcp
    dot_config/environment.d/50-sudo-askpass.conf
    dot_config/environment.d/60-omp.conf
  )

  mkdir -p "$flow_source/scripts" \
    "$flow_home/.local/bin" "$flow_home/.agents" "$flow_home/.config/opencode" \
    "$flow_home/.retired-agent-config-probe" \
    "$divergent_home/.local/bin" "$divergent_home/.retired-agent-config-probe" \
    "$divergent_home/.agents" "$malformed_home/.local/bin"
  cat >"$flow_source/scripts/check-agent-config-sync.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
live=0
strict=0
for arg in "$@"; do
  case "$arg" in
    --check-live-migration) live=1 ;;
    --strict-preflight) strict=1 ;;
    *) exit 64 ;;
  esac
done
if [[ $# -eq 0 ]]; then
  printf '%s\n' source
elif [[ $# -eq 1 && "$live" -eq 1 ]]; then
  printf '%s\n' live
elif [[ $# -eq 2 && "$live" -eq 1 && "$strict" -eq 1 ]]; then
  printf '%s\n' strict
else
  exit 64
fi >>"$SYNC_FLOW_LOG"
EOF
  printf '%s\n' scripts >"$flow_source/.chezmoiignore"
  printf '%s\n' \
    .retired-agent-config-probe \
    .absent-retired-agent-config-probe \
    >"$flow_source/.chezmoiremove"
  for source_path in "${active_source_files[@]}"; do
    if [[ "$source_path" == */* ]]; then
      mkdir -p "$flow_source/${source_path%/*}"
    fi
    printf '%s\n' managed >"$flow_source/$source_path"
  done
  printf '%s\n' '../../../.agents/skills/probe' \
    >"$flow_source/dot_pi/agent/skills/symlink_probe"
  printf '%s\n' '{"canonical_root":"~/.agents/skills","harnesses":{"pi":{"skills_root":"~/.pi/agent/skills","source_root":"dot_pi/agent/skills","discovery":"symlink","relative_prefix":"../../../.agents/skills"}},"skills":{"probe":["pi"]}}' \
    >"$flow_source/dot_agents/skill-targets.json"
  printf '%s\n' intended-agent-probe >"$flow_source/dot_agents/mcp-targets.json"
  printf '%s\n' original-unrelated >"$flow_source/dot_unrelated-agent-config-probe"
  install -m 0755 "$ROOT/dot_local/bin/executable_agent-config-sync" \
    "$flow_source/dot_local/bin/executable_agent-config-sync"
  printf '%s\n' '{"state":"original"}' >"$flow_source/dot_agents/dot_skill-lock.json"
  printf '%s\n' original-opencode-readme >"$flow_source/dot_config/opencode/README.md"
  HOME="$flow_home" chezmoi --source "$flow_source" apply --force --no-tty \
    "$flow_home/.unrelated-agent-config-probe" \
    "$flow_home/.agents/.skill-lock.json" \
    "$flow_home/.config/opencode/README.md"
  printf '%s\n' '{"state":"intended"}' >"$flow_source/dot_agents/dot_skill-lock.json"
  printf '%s\n' intended-opencode-readme >"$flow_source/dot_config/opencode/README.md"
  cat >"$flow_source/run_after_agent_config_probe.sh" <<'EOF'
#!/usr/bin/env bash
: >"$SYNC_SCRIPT_MARKER"
EOF
  chmod 0755 "$flow_source/run_after_agent_config_probe.sh"
  cat >"$flow_source/run_onchange_after_configure_pickforge_lanes_mcp.sh" <<'EOF'
#!/bin/sh
set -eu
[ -x "$HOME/.local/bin/pickforge-lanes-mcp" ]
printf '%s\n' configured >>"$SYNC_CONFIGURE_LOG"
EOF
  chmod 0755 "$flow_source/run_onchange_after_configure_pickforge_lanes_mcp.sh"
  printf '%s\n' changed-unrelated >"$flow_source/dot_unrelated-agent-config-probe"
  printf '%s\n' retired >"$flow_home/.retired-agent-config-probe/sentinel"
  printf '%s\n' retired >"$divergent_home/.retired-agent-config-probe/sentinel"
  printf '%s\n' divergent >"$divergent_home/.agents/mcp-targets.json"
  for target_home in "$flow_home" "$divergent_home" "$malformed_home"; do
    install -m 0755 "$ROOT/dot_local/bin/executable_agent-config-sync" \
      "$target_home/.local/bin/agent-config-sync"
  done

  : >"$configure_log"
  if HOME="$flow_home" CHEZMOI_SOURCE_DIR="$flow_source" SYNC_FLOW_LOG="$flow_log" \
    SYNC_SCRIPT_MARKER="$script_marker" SYNC_CONFIGURE_LOG="$configure_log" \
    "$flow_home/.local/bin/agent-config-sync" apply >/dev/null 2>"$flow_error" \
    && HOME="$flow_home" CHEZMOI_SOURCE_DIR="$flow_source" SYNC_FLOW_LOG="$flow_log" \
      "$flow_home/.local/bin/agent-config-sync" check-live >/dev/null 2>&1; then
    printf '%s\n' source strict live live >"$expected_log"
    if grep -Fxq intended-agent-probe "$flow_home/.agents/mcp-targets.json" \
      && grep -Fxq '{"state":"intended"}' "$flow_home/.agents/.skill-lock.json" \
      && grep -Fxq intended-opencode-readme "$flow_home/.config/opencode/README.md" \
      && grep -Fxq managed "$flow_home/.agents/browser-use.md" \
      && [[ -x "$flow_home/.factory/hooks/kde-notify.sh" ]] \
      && grep -Fxq managed "$flow_home/.factory/hooks/kde-notify.sh" \
      && [[ -L "$flow_home/.pi/agent/skills/probe" ]] \
      && [[ "$(readlink "$flow_home/.pi/agent/skills/probe")" == '../../../.agents/skills/probe' ]] \
      && [[ ! -e "$flow_home/.retired-agent-config-probe" \
        && ! -L "$flow_home/.retired-agent-config-probe" ]] \
      && [[ ! -e "$flow_home/.absent-retired-agent-config-probe" \
        && ! -L "$flow_home/.absent-retired-agent-config-probe" ]] \
      && grep -Fxq original-unrelated "$flow_home/.unrelated-agent-config-probe" \
      && [[ ! -e "$script_marker" ]] \
      && [[ "$(grep -Fxc configured "$configure_log")" -eq 1 ]] \
      && cmp -s "$expected_log" "$flow_log"; then
      pass 'temporary scoped sync updates skill-lock metadata target from source'
      pass 'temporary scoped sync updates OpenCode README target from source'
      pass 'temporary scoped sync applies browser-use policy target'
      pass 'temporary scoped sync applies Factory kde-notify hook target'
      pass 'temporary scoped sync removes present retirement and skips absent retirement'
      pass 'temporary sync applies only agent targets and retirements without implicit run scripts'
      pass 'temporary sync invokes managed pickforge-lanes registration once after target apply'
    else
      err 'temporary scoped sync changed an unrelated target, ran a script, or missed agent cleanup'
    fi
  else
    err "temporary scoped sync command apply/check-live flow failed: $(tr '\n' ' ' <"$flow_error")"
  fi

  printf '%s\n' intended-agent-probe-all-retirements-absent \
    >"$flow_source/dot_agents/mcp-targets.json"
  : >"$configure_log"
  if HOME="$flow_home" CHEZMOI_SOURCE_DIR="$flow_source" SYNC_FLOW_LOG="$all_absent_log" \
    SYNC_SCRIPT_MARKER="$script_marker" SYNC_CONFIGURE_LOG="$configure_log" \
    "$flow_home/.local/bin/agent-config-sync" apply >/dev/null 2>"$all_absent_error" \
    && HOME="$flow_home" CHEZMOI_SOURCE_DIR="$flow_source" SYNC_FLOW_LOG="$all_absent_log" \
      "$flow_home/.local/bin/agent-config-sync" check-live >/dev/null 2>&1; then
    printf '%s\n' source strict live live >"$expected_log"
    if grep -Fxq intended-agent-probe-all-retirements-absent \
      "$flow_home/.agents/mcp-targets.json" \
      && [[ ! -e "$flow_home/.retired-agent-config-probe" \
        && ! -L "$flow_home/.retired-agent-config-probe" ]] \
      && [[ ! -e "$flow_home/.absent-retired-agent-config-probe" \
        && ! -L "$flow_home/.absent-retired-agent-config-probe" ]] \
      && [[ ! -e "$script_marker" ]] \
      && [[ "$(grep -Fxc configured "$configure_log")" -eq 1 ]] \
      && cmp -s "$expected_log" "$all_absent_log"; then
      pass 'temporary scoped sync applies active targets when all retirements are absent'
      pass 'temporary scoped sync live check succeeds when all retirements are absent'
    else
      err 'temporary scoped sync missed active apply or live check with all retirements absent'
    fi
  else
    err "temporary scoped sync all-absent retirement flow failed: $(tr '\n' ' ' <"$all_absent_error")"
  fi

  : >"$configure_log"
  if HOME="$divergent_home" CHEZMOI_SOURCE_DIR="$flow_source" SYNC_FLOW_LOG="$divergent_log" \
    SYNC_SCRIPT_MARKER="$script_marker" SYNC_CONFIGURE_LOG="$configure_log" \
    "$divergent_home/.local/bin/agent-config-sync" apply >/dev/null 2>&1; then
    err 'temporary scoped sync overwrote an unmanaged active target'
  elif grep -Fxq divergent "$divergent_home/.agents/mcp-targets.json" \
    && [[ -e "$divergent_home/.retired-agent-config-probe" ]] \
    && [[ ! -e "$script_marker" ]] \
    && [[ ! -s "$configure_log" ]] \
    && [[ "$(tr '\n' ' ' <"$divergent_log")" == 'source strict ' ]]; then
    pass 'temporary scoped sync blocks unmanaged active targets before retirement apply'
  else
    err 'temporary scoped sync unmanaged-target preflight was not atomic'
  fi

  for malformed in '' '/absolute-retirement'; do
    printf '%s\n' "$malformed" >"$flow_source/.chezmoiremove"
    rm -f "$malformed_log" "$malformed_error" "$script_marker"
    : >"$configure_log"
    if HOME="$malformed_home" CHEZMOI_SOURCE_DIR="$flow_source" \
      SYNC_FLOW_LOG="$malformed_log" SYNC_SCRIPT_MARKER="$script_marker" \
      SYNC_CONFIGURE_LOG="$configure_log" \
      "$malformed_home/.local/bin/agent-config-sync" apply \
      >/dev/null 2>"$malformed_error"; then
      err "temporary scoped sync accepted malformed retirement entry: ${malformed:-empty}"
    elif [[ ! -e "$script_marker" ]] \
      && [[ ! -s "$configure_log" ]] \
      && [[ "$(tr '\n' ' ' <"$malformed_log")" == 'source strict ' ]] \
      && grep -Fq 'retirement list' "$malformed_error"; then
      pass "temporary scoped sync rejects malformed retirement entry: ${malformed:-empty}"
    else
      err "temporary scoped sync did not fail closed on malformed retirement entry: ${malformed:-empty}"
    fi
  done
  printf '%s\n' \
    .retired-agent-config-probe \
    .absent-retired-agent-config-probe \
    >"$flow_source/.chezmoiremove"
}

check_primary_global_live_regressions() {
  local target log log_name
  local -a drift_targets=(
    "$DEST/.claude/CLAUDE.md"
    "$DEST/.claude/settings.json"
    "$DEST/.claude/rules/context7.md"
    "$DEST/.claude/skills/kickoff/SKILL.md"
    "$DEST/.zshrc"
    "$DEST/.bashrc"
  )

  if (fail=0; check_live_primary_global_targets "$DEST" >/dev/null; [[ "$fail" -eq 0 ]]); then
    pass 'temporary primary global live targets include Claude rules and skills'
  else
    err 'temporary primary global live baseline was rejected'
    return
  fi

  for target in "${drift_targets[@]}"; do
    printf '\nmanaged-live-drift\n' >>"$target"
    log_name="${target#"$DEST/"}"
    log_name="${log_name//\//_}"
    log="$TMP/primary-global-live-${log_name}.log"
    if (fail=0; check_live_primary_global_targets "$DEST"; [[ "$fail" -ne 0 ]]) \
      >"$log" 2>&1; then
      pass "temporary primary global live drift rejected: ${target#"$DEST/"}"
    else
      err "temporary primary global live drift accepted: ${target#"$DEST/"}"
    fi
    if ! chezmoi "${TMP_SRC[@]}" --destination "$DEST" apply --force --no-tty "$target"; then
      err "temporary primary global target restore failed: ${target#"$DEST/"}"
      return
    fi
  done
}

check_doctor_sources() {
  local doctor="$ROOT/scripts/agent-doctor.sh"
  local doctor_tests="$ROOT/scripts/check-agent-doctor.sh"
  local catalog="$ROOT/dot_agents/doctor-targets.json"

  need "$doctor"
  need "$doctor_tests"
  need "$catalog"
  if [[ -f "$catalog" ]] && jq -e '
    .version == 1
    and (.bootstrap | type == "array")
    and (.harnesses | type == "object" and length > 0)
    and all(.harnesses[];
      (.displayName | type == "string" and length > 0)
      and (.binary | type == "string" and length > 0)
      and (.versionArgs | type == "array")
      and (.configPaths | type == "array"))
  ' "$catalog" >/dev/null 2>&1; then
    pass 'doctor catalog JSON and source invariants valid'
  else
    err 'doctor catalog JSON or source invariants invalid'
  fi
  if [[ -f "$doctor" ]] && bash -n "$doctor" \
    && [[ -f "$doctor_tests" ]] && bash -n "$doctor_tests"; then
    pass 'doctor scripts have valid Bash syntax'
  else
    err 'doctor script Bash syntax invalid'
  fi
  if [[ -f "$doctor_tests" ]] && bash "$doctor_tests"; then
    pass 'hermetic doctor suite passes'
  else
    err 'hermetic doctor suite failed'
  fi
}

check_manifest_and_sources() {
  need "$MANIFEST"
  if ! jq -e . "$MANIFEST" >/dev/null 2>&1; then
    err "manifest is not valid JSON: $MANIFEST"
    return
  fi
  pass "manifest JSON valid"

  if jq -e '.harnesses | has("claude-portable") | not' "$MANIFEST" >/dev/null; then
    pass 'manifest has no retired claude-portable harness'
  else
    err 'manifest still defines retired claude-portable harness'
  fi
  if jq -e '.skills | all(.[]; all(.[]; . != "claude-portable"))' "$MANIFEST" >/dev/null; then
    pass 'manifest skill targets exclude retired claude-portable harness'
  else
    err 'manifest skill targets still contain retired claude-portable harness'
  fi

  local skill harness src_root rel_prefix expected link_src
  local -a skills

  skills=()
  while IFS= read -r skill; do
    skills+=("$skill")
  done < <(jq -r '.skills | keys[]' "$MANIFEST")
  [[ "${#skills[@]}" -gt 0 ]] || err 'manifest has no skills'

  for skill in "${skills[@]}"; do
    local age="$ROOT/dot_agents/skills/${skill}/encrypted_SKILL.md.age"
    local plain="$ROOT/dot_agents/skills/${skill}/SKILL.md"
    local head name
    if [[ -f "$age" && -f "$plain" ]]; then
      err "duplicate canonical skill sources: $skill"
      continue
    elif [[ -f "$age" ]]; then
      head="$(set +o pipefail; chezmoi "${SRC[@]}" decrypt "$age" 2>/dev/null | head -n 20)"
    elif [[ -f "$plain" ]]; then
      head="$(head -n 20 "$plain")"
    else
      err "canonical skill source missing: $skill"
      continue
    fi
    pass "canonical source exists: $skill"
    if [[ -z "$head" ]]; then
      err "canonical source unreadable: $skill"
      continue
    fi
    if [[ "$head" != ---$'\n'* ]]; then
      err "frontmatter missing for $skill"
      continue
    fi
    name="$(awk 'BEGIN{fm=0} /^---$/{fm++; next} fm==1 && /^name:/{sub(/^name:[[:space:]]*/,""); print; exit}' <<<"$head")"
    if [[ "$name" == "$skill" ]]; then
      pass "frontmatter name=$skill"
    else
      err "frontmatter name mismatch for $skill (got: ${name:-empty})"
    fi
  done

  if [[ -e "$ROOT/dot_claude/skills/context7-mcp" ]]; then
    err 'duplicate Context7 skill source still present: dot_claude'
  else
    pass 'no duplicate Context7 skill directory: dot_claude'
  fi

  while IFS=$'\t' read -r skill harness; do
    [[ -n "$skill" && -n "$harness" ]] || continue
    local discovery
    discovery="$(jq -r --arg h "$harness" '.harnesses[$h].discovery' "$MANIFEST")"
    if [[ "$discovery" == "canonical" ]]; then
      pass "codex/canonical uses $skill without harness symlink"
      continue
    fi
    src_root="$(jq -r --arg h "$harness" '.harnesses[$h].source_root' "$MANIFEST")"
    rel_prefix="$(jq -r --arg h "$harness" '.harnesses[$h].relative_prefix' "$MANIFEST")"
    expected="${rel_prefix}/${skill}"
    link_src="$ROOT/${src_root}/symlink_${skill}"
    if [[ ! -f "$link_src" ]]; then
      err "missing symlink source: $link_src"
      continue
    fi
    local got
    got="$(tr -d '\n' <"$link_src")"
    if [[ "$got" == "$expected" ]]; then
      pass "symlink source $harness/$skill -> $expected"
    else
      err "symlink source $link_src expected '$expected' got '$got'"
    fi
  done < <(jq -r '.skills | to_entries[] | .key as $s | .value[] | "\($s)\t\(.)"' "$MANIFEST")
}

check_legacy_model_skill_absence() {
  local managed_log="$TMP/managed-legacy-model-skills.log"
  if jq -e '.skills | (has("codex") | not) and (has("grok") | not)' \
    "$MANIFEST" >/dev/null 2>&1; then
    pass 'manifest has no legacy codex/grok skill entries'
  else
    err 'manifest still contains a legacy codex/grok skill entry'
  fi

  if chezmoi "${SRC[@]}" managed --include=files,symlinks --path-style=absolute \
    >"$managed_log" \
    && ! grep -Eq '/\.claude/skills/(codex|grok)(/|$)' "$managed_log"; then
    pass 'managed targets have no legacy Claude codex/grok skill paths'
  else
    err 'managed targets contain or could not check legacy Claude codex/grok skill paths'
  fi
}

check_skill_lock_retirements() {
  need "$SKILL_LOCK"
  [[ -f "$SKILL_LOCK" ]] || return 0
  if ! jq -e . "$SKILL_LOCK" >/dev/null 2>&1; then
    err "skill lock is not valid JSON: $SKILL_LOCK"
    return
  fi
  pass 'skill lock JSON valid'

  local retired_json present
  retired_json="$(printf '%s\n' "${RETIRED_SKILL_LOCK_ENTRIES[@]}" | jq -R . | jq -s .)"
  if jq -e --argjson retired "$retired_json" '
    .skills as $skills
    | all($retired[]; . as $skill | $skills | has($skill) | not)
  ' "$SKILL_LOCK" >/dev/null; then
    pass 'skill lock excludes retired caveman entries'
  else
    present="$(jq -r --argjson retired "$retired_json" '
      .skills as $skills
      | $retired
      | map(select(. as $skill | $skills | has($skill)))
      | join(", ")
    ' "$SKILL_LOCK")"
    err "skill lock still contains retired entries: $present"
  fi

  if chezmoi "${SRC[@]}" cat "$HOME/.claude/settings.json" \
    | jq -e '
      ((.enabledPlugins // {}) | has("caveman@caveman") | not)
      and ((.extraKnownMarketplaces // {}) | has("caveman") | not)
    ' >/dev/null; then
    pass 'Claude settings exclude retired Caveman plugin and marketplace'
  else
    err 'Claude settings still contain retired Caveman plugin or marketplace'
  fi
}

validate_omp_mcp_credentials() {
  local config="$1"
  jq -e '
    def credential_key:
      ascii_downcase
      | test("(^|[_-])(token|secret|api[_-]?key|access[_-]?key)($|[_-])");
    ([.. | objects | to_entries[]
      | select(
          (.key | credential_key)
          and (.value | type == "string")
          and (.value | length > 0)
          and ((.value | startswith("!")) | not)
        )]
      | length == 0)
    and
    ([paths(strings) as $path
      | select(getpath($path) | startswith("!"))
      | $path] as $commands
      | ($commands == [])
        or (
          $commands == [["mcpServers", "sentry", "env", "SENTRY_ACCESS_TOKEN"]]
          and .mcpServers.sentry.env.SENTRY_ACCESS_TOKEN == "!cat ~/.pickforge-keys/sentry-token"
        ))
    and
    ([.. | strings
      | select(test(
          "^(bearer[[:space:]]+|sk_(live|test)_|sk-(proj-)?|gh[pousr]_|xox[baprs]-|eyJ[A-Za-z0-9_-]+\\\\.)";
          "i"
        ))]
      | length == 0)
  ' "$config" >/dev/null
}
check_mcp_registry_and_config() {
  need "$MCP_REGISTRY"
  need "$OMP_MCP"
  [[ -f "$MCP_REGISTRY" && -f "$OMP_MCP" ]] || return

  if jq -e . "$MCP_REGISTRY" >/dev/null 2>&1; then
    pass 'MCP target registry JSON valid'
  else
    err "MCP target registry is not valid JSON: $MCP_REGISTRY"
    return
  fi
  if jq -e . "$OMP_MCP" >/dev/null 2>&1; then
    pass 'OMP MCP config JSON valid'
  else
    err "OMP MCP config is not valid JSON: $OMP_MCP"
    return
  fi

  if jq -e '
    def unique_nonempty_strings:
      type == "array"
      and all(.[]; type == "string" and length > 0)
      and (length == (unique | length));

    type == "object"
    and keys == ["omp", "version"]
    and .version == 1
    and (.omp
      | type == "object"
      and keys == ["externallyImported", "native", "pluginRetained", "suppressed"]
      and all(
        .native,
        .externallyImported,
        .pluginRetained,
        .suppressed;
        unique_nonempty_strings)
      and all(.native[], .externallyImported[]; contains(":") | not))
  ' "$MCP_REGISTRY" >/dev/null; then
    pass 'MCP target registry shape valid'
  else
    err 'MCP target registry shape invalid'
  fi

  if jq -e '
    def optional_type($key; $kind):
      (has($key) | not) or (getpath([$key]) | type == $kind);
    def string_map:
      type == "object" and all(to_entries[]; .value | type == "string");
    def string_array:
      type == "array" and all(.[]; type == "string");
    def unique_nonempty_strings:
      string_array
      and all(.[]; length > 0)
      and (length == (unique | length));
    def allowed_keys($allowed):
      ((keys - $allowed) | length == 0);
    def shared_fields:
      optional_type("enabled"; "boolean")
      and ((has("timeout") | not) or (.timeout | type == "number" and . >= 0));
    def stdio_server:
      type == "object"
      and allowed_keys(["args", "command", "cwd", "enabled", "env", "timeout", "type"])
      and ((has("type") | not) or .type == "stdio")
      and (.command | type == "string" and length > 0)
      and (has("url") | not)
      and ((has("args") | not) or (.args | string_array))
      and ((has("env") | not) or (.env | string_map))
      and optional_type("cwd"; "string")
      and shared_fields;
    def remote_server:
      type == "object"
      and allowed_keys(["enabled", "headers", "oauth", "timeout", "type", "url"])
      and (.type == "http" or .type == "sse")
      and (.url | type == "string" and length > 0)
      and (has("command") | not)
      and ((has("headers") | not) or (.headers | string_map))
      and shared_fields;
    def valid_server:
      stdio_server or remote_server;
    def optional_unique_names($key):
      (has($key) | not) or (getpath([$key]) | unique_nonempty_strings);

    type == "object"
    and ((keys - ["$schema", "disabledServers", "enabledServers", "mcpServers"]) | length == 0)
    and optional_type("$schema"; "string")
    and (.mcpServers | type == "object")
    and all(.mcpServers | keys[]; test("^[a-zA-Z0-9_.-]{1,100}$"))
    and all(.mcpServers[]; valid_server)
    and optional_unique_names("disabledServers")
    and optional_unique_names("enabledServers")
  ' "$OMP_MCP" >/dev/null; then
    pass 'OMP MCP documented schema subset valid'
  else
    err 'OMP MCP has an invalid top-level key or transport shape'
  fi

  if jq -e '
    [.. | objects | to_entries[]
      | select((.key | ascii_downcase) == "auth")]
    | length == 0
  ' "$OMP_MCP" >/dev/null; then
    pass 'OMP MCP has no auth blocks'
  else
    err 'OMP MCP must not contain auth blocks'
  fi

  if jq -e '
    ([paths as $path
      | select(
          ($path | length) > 0
          and ($path[-1] | type) == "string"
          and ($path[-1] | ascii_downcase) == "oauth"
        )
      | $path] == [["mcpServers", "stripe", "oauth"]])
    and (.mcpServers.stripe.oauth
      | type == "object"
      and keys == ["callbackPath", "callbackPort", "clientId", "redirectUri"]
      and .clientId == "oacli_UsBlZ6jiucaNw9"
      and (.clientId | test("^oacli_[A-Za-z0-9]+$"))
      and .redirectUri == "http://127.0.0.1:3000/callback"
      and .callbackPort == 3000
      and .callbackPath == "/callback")
  ' "$OMP_MCP" >/dev/null; then
    pass 'OMP MCP OAuth is restricted to the approved Stripe public client'
  else
    err 'OMP MCP OAuth must be exactly the approved Stripe public client configuration'
  fi

  if jq -e '
    [.. | objects | to_entries[]
      | select((.key | ascii_downcase) == "clientsecret")]
    | length == 0
  ' "$OMP_MCP" >/dev/null; then
    pass 'OMP MCP has no clientSecret fields'
  else
    err 'OMP MCP must not contain clientSecret fields'
  fi

  if jq -e '
    [.. | objects | to_entries[]
      | select((.key | ascii_downcase) == "authorization")]
    | length == 0
  ' "$OMP_MCP" >/dev/null; then
    pass 'OMP MCP has no literal Authorization header'
  else
    err 'OMP MCP must not contain a literal Authorization header'
  fi

  if validate_omp_mcp_credentials "$OMP_MCP"; then
    pass 'OMP MCP has no suspicious literals and only the approved Sentry credential command'
  else
    err 'OMP MCP contains a suspicious literal or unapproved credential command'
  fi

  local credential_probe
  credential_probe="$(mktemp "${TMPDIR:-/tmp}/agent-config-sync-mcp-probe.XXXXXX")"
  if jq '.mcpServers.sentry.env.SENTRY_ACCESS_TOKEN = "!cat /tmp/unapproved-token"' \
    "$OMP_MCP" >"$credential_probe"; then
    if validate_omp_mcp_credentials "$credential_probe"; then
      err 'OMP MCP negative probe accepted an unapproved credential command'
    else
      pass 'OMP MCP credential validator rejects a mutated unapproved command'
    fi
  else
    err 'OMP MCP negative probe could not create the mutated config'
  fi
  rm -f "$credential_probe"

  if jq -e '
    def credential_key:
      ascii_downcase
      | test("(^|[_-])(token|secret|api[_-]?key|access[_-]?key)($|[_-])");
    ([.. | objects | to_entries[]
      | select(
          (.key | credential_key)
          and (.value | type == "string")
          and (.value | length > 0)
          and ((.value | startswith("!")) | not)
        )]
      | length == 0)
    and
    ([.. | strings
      | select(test(
          "^(bearer[[:space:]]+|sk_(live|test)_|sk-(proj-)?|gh[pousr]_|xox[baprs]-|eyJ[A-Za-z0-9_-]+\\\\.)";
          "i"
        ))]
      | length == 0)
  ' "$OMP_MCP" >/dev/null; then
    pass 'OMP MCP has no suspicious literal credential values'
  else
    err 'OMP MCP contains a suspicious literal token, secret, or key value'
  fi
  if jq -e -n --slurpfile registry "$MCP_REGISTRY" --slurpfile config "$OMP_MCP" '
    ($registry[0].omp.native | sort)
    ==
    ($config[0].mcpServers | keys | sort)
  ' >/dev/null; then
    pass 'registry native OMP names match mcpServers'
  else
    err 'registry native OMP names do not match mcpServers'
  fi

  if jq -e -n --slurpfile registry "$MCP_REGISTRY" --slurpfile config "$OMP_MCP" '
    ($registry[0].omp.suppressed | sort)
    ==
    ($config[0].disabledServers | sort)
  ' >/dev/null; then
    pass 'registry suppressed names match disabledServers'
  else
    err 'registry suppressed names do not match disabledServers'
  fi
}

check_live_portable_links() {
  local skill harness root link target expected_prefix canon
  canon_root="$(expand_home "$(jq -r '.canonical_root' "$MANIFEST")")"
  while IFS=$'\t' read -r skill harness; do
    local discovery
    discovery="$(jq -r --arg h "$harness" '.harnesses[$h].discovery' "$MANIFEST")"
    if [[ "$discovery" == "canonical" ]]; then
      continue
    fi
    root="$(expand_home "$(jq -r --arg h "$harness" '.harnesses[$h].skills_root' "$MANIFEST")")"
    expected_prefix="$(jq -r --arg h "$harness" '.harnesses[$h].relative_prefix' "$MANIFEST")"
    link="${root}/${skill}"
    canon="${canon_root}/${skill}"

    if [[ ! -e "$link" && ! -L "$link" ]]; then
      if [[ "$STRICT_PREFLIGHT" -eq 1 ]]; then
        pass "live link not yet applied: $harness/$skill"
      else
        err "live link missing: $link"
      fi
      continue
    fi

    if [[ -L "$link" ]]; then
      target="$(readlink "$link")"
      if [[ "$target" != "${expected_prefix}/${skill}" ]]; then
        err "live link $link expected '${expected_prefix}/${skill}' got '$target'"
        continue
      fi
      if [[ ! -e "$link" ]]; then
        err "live link broken: $link -> $target"
        continue
      fi
      pass "live link ok: $harness/$skill"
      continue
    fi

    if [[ "$STRICT_PREFLIGHT" -eq 1 ]]; then
      if [[ -d "$canon" && -d "$link" ]] && dirs_identical "$link" "$canon"; then
        pass "live path identical to canonical (migratable): $harness/$skill"
      else
        err "live non-symlink path differs from canonical: $link"
      fi
      continue
    fi

    err "live path is not a symlink: $link"
  done < <(jq -r '.skills | to_entries[] | .key as $s | .value[] | "\($s)\t\(.)"' "$MANIFEST")
}

check_live_native_routing_ancestors() {
  local live="$1" relative ancestor component
  local -a components

  relative="${live#"${HOME}/"}"
  if [[ "$relative" == "$live" ]]; then
    err "live native routing file is not beneath HOME: $live"
    return 1
  fi

  ancestor="$HOME"
  IFS='/' read -r -a components <<<"${relative%/*}"
  for component in "${components[@]}"; do
    [[ -n "$component" ]] || continue
    ancestor="${ancestor}/${component}"
    if [[ -L "$ancestor" ]]; then
      err "live native routing ancestor must not be a symlink: $ancestor"
      return 1
    elif [[ -e "$ancestor" && ! -d "$ancestor" ]]; then
      err "live native routing ancestor is not a directory: $ancestor"
      return 1
    elif [[ ! -e "$ancestor" ]]; then
      return 0
    fi
  done
}

check_live_primary_global_targets() {
  local target_root="${1:-$HOME}"
  local -a targets=(
    "${target_root}/.claude/CLAUDE.md"
    "${target_root}/.claude/settings.json"
    "${target_root}/.claude/rules"
    "${target_root}/.claude/skills"
    "${target_root}/.zshrc"
    "${target_root}/.bashrc"
  )

  if chezmoi "${SRC[@]}" --destination "$target_root" verify "${targets[@]}" >/dev/null 2>&1; then
    pass 'live global Claude policy, settings, rules, skills, and shell targets match managed state'
  else
    err 'live global Claude policy, settings, rules, skills, or shell target differs from managed state'
  fi
}

check_live_native_routing_files() {
  local live rendered
  local -a files=(
    "${HOME}/.codex/skills/model-orchestration/SKILL.md"
    "${HOME}/.codex/skills/model-orchestration/references/model-routing.md"
    "${HOME}/.claude/skills/kickoff/SKILL.md"
  )

  rendered="$(mktemp "${TMPDIR:-/tmp}/agent-config-sync-native-routing.XXXXXX")"
  for live in "${files[@]}"; do
    if ! check_live_native_routing_ancestors "$live"; then
      continue
    fi
    if ! chezmoi "${SRC[@]}" cat "$live" >"$rendered"; then
      err "native routing source cannot be rendered: $live"
      continue
    fi
    if [[ -L "$live" ]]; then
      err "live native routing file must be a managed regular file: $live"
    elif [[ ! -e "$live" ]]; then
      if [[ "$STRICT_PREFLIGHT" -eq 1 ]]; then
        pass "live native routing file not yet applied: $live"
      else
        err "live native routing file missing: $live"
      fi
    elif [[ ! -f "$live" ]]; then
      err "live native routing path is not a regular file: $live"
    elif cmp -s "$rendered" "$live"; then
      pass "live native routing file matches rendered source: $live"
    elif [[ "$STRICT_PREFLIGHT" -eq 1 ]]; then
      pass "live native routing file has managed pending drift: $live"
    else
      err "live native routing file differs from rendered source: $live"
    fi
  done
  rm -f "$rendered"
}



if [[ "$MODE" == live ]]; then
  if [[ "$STRICT_PREFLIGHT" -eq 1 ]]; then
    echo "== agent-config-sync strict live preflight (read-only) =="
  else
    echo "== agent-config-sync live migration (read-only) =="
  fi
  GROK_LIVE="${HOME}/.grok/AGENTS.md"
  OMP_AGENTS_LIVE="${HOME}/.omp/agent/AGENTS.md"
  OMP_CONFIG_LIVE="${HOME}/.omp/agent/config.yml"
  OMP_MCP_LIVE="${HOME}/.omp/agent/mcp.json"
  OPENCODE_LIVE="${HOME}/.config/opencode/AGENTS.md"
  SOUL_LIVE="${HOME}/.hermes/SOUL.md"
  NOUS_DEFAULT='You are Hermes Agent, an intelligent AI assistant created by Nous Research.'
  check_omp_agent_override_sources
  check_live_retired_targets

  if [[ ! -e "$GROK_LIVE" ]]; then
    err "live Grok AGENTS missing: $GROK_LIVE"
  elif [[ -L "$GROK_LIVE" ]]; then
    target="$(readlink "$GROK_LIVE")"
    if [[ "$target" == *'/.codex/AGENTS.md' || "$target" == '../.codex/AGENTS.md' || "$target" == *'codex/AGENTS.md' ]]; then
      pass "live Grok AGENTS is expected Codex symlink ($target)"
    else
      err "live Grok AGENTS symlink is unexpected: $target"
    fi
  elif grep -q '^# Personal Grok Notes' "$GROK_LIVE"; then
    pass 'live Grok AGENTS already rendered (Personal Grok Notes)'
  else
    err 'live Grok AGENTS is neither Codex symlink nor rendered Grok adapter'
  fi

  if [[ ! -e "$OMP_AGENTS_LIVE" ]]; then
    pass "live OMP AGENTS not yet applied: $OMP_AGENTS_LIVE"
  elif [[ -L "$OMP_AGENTS_LIVE" ]]; then
    err "live OMP AGENTS must be a managed regular file: $OMP_AGENTS_LIVE"
  elif grep -q '^# Personal OMP Notes' "$OMP_AGENTS_LIVE"; then
    pass 'live OMP AGENTS is a managed adapter'
  else
    err 'live OMP AGENTS is not a recognized managed adapter'
  fi

  if [[ ! -e "$OMP_CONFIG_LIVE" ]]; then
    pass "live OMP config not yet applied: $OMP_CONFIG_LIVE"
  elif [[ -L "$OMP_CONFIG_LIVE" ]]; then
    err "live OMP config must be a managed regular file: $OMP_CONFIG_LIVE"
  elif cmp -s "$OMP_CONFIG_LIVE" "$ROOT/dot_omp/agent/config.yml"; then
    pass 'live OMP config matches canonical source'
  elif ! grep -q '^providers:' "$OMP_CONFIG_LIVE" || ! grep -q '^modelRoles:' "$OMP_CONFIG_LIVE"; then
    err 'live OMP config is not a recognized managed file'
  elif [[ "$STRICT_PREFLIGHT" -eq 1 ]]; then
    pass 'live OMP config has managed runtime drift pending the authorized cutover'
  else
    err 'live OMP config differs from canonical source'
  fi

  if [[ ! -e "$OMP_MCP_LIVE" ]]; then
    pass "live OMP MCP config not yet applied: $OMP_MCP_LIVE"
  elif [[ -L "$OMP_MCP_LIVE" ]]; then
    err "live OMP MCP config must be a managed regular file: $OMP_MCP_LIVE"
  elif ! jq -e . "$OMP_MCP_LIVE" >/dev/null 2>&1; then
    err 'live OMP MCP config is not valid JSON'
  elif cmp -s "$OMP_MCP_LIVE" "$OMP_MCP"; then
    pass 'live OMP MCP config matches canonical source'
  elif [[ "$STRICT_PREFLIGHT" -eq 1 ]] && managed_regular_file_unchanged "$OMP_MCP_LIVE"; then
    pass 'live OMP MCP config has managed pending drift'
  else
    err 'live OMP MCP config differs from canonical source; refusing an implicit overwrite'
  fi
  check_live_omp_agent_overrides
  check_live_native_routing_files
  if [[ "$STRICT_PREFLIGHT" -eq 0 ]]; then
    check_live_primary_global_targets
  fi

  if [[ ! -e "$OPENCODE_LIVE" ]]; then
    pass "live OpenCode AGENTS not yet applied: $OPENCODE_LIVE"
  elif [[ -L "$OPENCODE_LIVE" ]]; then
    err "live OpenCode AGENTS must be a managed regular file: $OPENCODE_LIVE"
  elif ! grep -Fq '## Shared Agent Memory' "$OPENCODE_LIVE"; then
    err 'live OpenCode AGENTS is not a recognized managed file'
  else
    for invariant in CORE_PROFILE.md WRITING_STYLE.md BOUNDARIES.md WORK_AND_PROJECTS.md 'projects/*.md'; do
      grep -Fq "$invariant" "$OPENCODE_LIVE" \
        || err "live OpenCode memory invariant missing: $invariant"
    done
    if grep -Fq 'CODING_AGENT_RULES.md' "$OPENCODE_LIVE"; then
      if [[ "$STRICT_PREFLIGHT" -eq 1 ]]; then
        pass 'live OpenCode is managed and pending the authorized memory cutover'
      else
        err 'live OpenCode still auto-loads CODING_AGENT_RULES'
      fi
    else
      pass 'live OpenCode excludes CODING_AGENT_RULES'
    fi
  fi

  if [[ ! -f "$SOUL_LIVE" ]]; then
    err "live Hermes SOUL missing: $SOUL_LIVE"
  elif grep -q '^# Hermes' "$SOUL_LIVE" && grep -q '/home/dev/AgentMemory' "$SOUL_LIVE"; then
    pass 'live Hermes SOUL already rendered (managed identity)'
  elif grep -Fq "$NOUS_DEFAULT" "$SOUL_LIVE" && ! grep -Fq 'I like short, practical work' "$SOUL_LIVE"; then
    pass 'live Hermes SOUL is known Nous default one-line identity'
  else
    err 'live Hermes SOUL is neither Nous default nor rendered managed SOUL'
  fi

  check_mcp_registry_and_config

  if [[ -f "$MANIFEST" ]]; then
    check_live_portable_links
  else
    err "manifest missing for live portable checks: $MANIFEST"
  fi

  if jq -e '.enabledModels | any(. == "xai/grok-4.5")' "$HOME/.pi/agent/settings.json" >/dev/null 2>&1; then
    pass 'live Pi enabled models include native Grok 4.5'
  else
    err 'live Pi enabled models missing native Grok 4.5'
  fi

  echo
  [[ "$fail" -eq 0 ]] && { echo "PASSED: live migration checks"; exit 0; }
  echo "FAILED: live migration checks"; exit 1
fi

echo "== agent-config-sync checks =="
echo "source: $ROOT"

SHARED=(
  .chezmoitemplates/agents-shared.md
  .chezmoitemplates/agents-shared-before-worktrees.md
  .chezmoitemplates/agents-shared-after-git.md
)
HARNESS=(
  'dot_codex/AGENTS.md.tmpl|# Personal Codex Notes|# Global Claude Rules'
  'dot_grok/AGENTS.md.tmpl|# Personal Grok Notes|# Personal Codex Notes'
  'dot_pi/agent/AGENTS.md.tmpl|# Personal Pi Notes|# Personal Codex Notes'
  'dot_omp/agent/AGENTS.md.tmpl|# Personal OMP Notes|# Personal Codex Notes'
  'private_dot_factory/AGENTS.md.tmpl|# Personal Droid Notes|# Personal Codex Notes'
)
SOUL=private_dot_hermes/SOUL.md.tmpl
OPENCODE=dot_config/opencode/AGENTS.md
SHARED_MAX_BYTES=15000
SHARED_SOURCE_BASELINE=13851
SHARED_RENDERED_BASELINE=13853
REQUIRED_SHARED_INVARIANTS=(
  'I like short, practical work. Read the repo, make the smallest clean change, and show proof before calling something done.'
  '- Be direct: no filler or ceremony. Fix root causes, not symptoms.'
  '- No hacks, monkey patches, fake fixes, temporary workarounds, or unrelated refactors.'
  'Dictation can corrupt names, model IDs, and technical terms. Confirm suspicious or contradictory wording instead of following it literally.'
  '- Never expose, print, commit, or send secrets or private production data.'
  '- Destructive filesystem, Git, account, or external-service actions require explicit confirmation.'
  '- Public actions (posts, replies, likes, follows, DMs, publishing) are drafts only; the user performs them.'
  '- Never use Anthropic Haiku — directly, via any tool, skill, subagent, fallback, or hidden route.'
  'github.com/ElbertePlinio/'
  '- Protect user work. Check status before staging, committing, merging, or cleaning.'
  '- Treat untracked files as user-owned.'
  '- Never push unless I explicitly ask, except in clearly identified Pickforge or Personal projects.'
  '- Commit messages must be English Conventional Commits.'
  '- Never add attribution or trailers: no `Co-authored-by`, no `Signed-off-by`, no bot names, no noreply addresses, no model names, no AI signatures.'
  '- `$local-review` is the review-policy source of truth; do not restate its profiles, model composition, findings, or round rules elsewhere.'
  '- Do not merge with failing required checks, unanswered valid findings, or an incomplete review required by the change'
  '~/Projects/.worktrees/<repo-name>/<branch-name>'
  'Run the narrowest behavioral validation that proves the change.'
  '/home/dev/AgentMemory'
  'CORE_PROFILE.md'
  'WRITING_STYLE.md'
  'BOUNDARIES.md'
  'WORK_AND_PROJECTS.md'
  'projects/*.md'
  'Never store secrets in memory.'
  'never edit only a rendered `$HOME` file'
  '- Use Context7 when library/API details matter.'
  '- When dispatching a swarm or any multi-subagent wave, explicitly choose and state each task'"'"'s model and effort from the current table.'
  '- Anything done or requested more than twice becomes a skill, command, or hook'
  '- `xhigh` is the absolute effort ceiling. Never use `ultra`, `max`, or any effort above xhigh'
  '- Establish the delivery mode before substantial work or any dispatch: plan-only, local-implement, or ship.'
  '- For work that creates or materially changes user-facing UI or UX, use the `design-director` skill before implementation.'
  '- For "ship it", "open a PR", "usual PR flow", or requests to review and merge a branch, use `$ship-pr` when available.'
)

ADAPTER_BUDGETS=(
  'dot_claude/CLAUDE.md.tmpl|2400'
  'dot_codex/AGENTS.md.tmpl|2000'
  'dot_grok/AGENTS.md.tmpl|700'
  'dot_pi/agent/AGENTS.md.tmpl|1800'
  'dot_omp/agent/AGENTS.md.tmpl|2800'
  'private_dot_factory/AGENTS.md.tmpl|1000'
)

STALE_PI_FLOW_PATHS=(
  dot_pi/agent/extensions/model-flow.ts
  dot_pi/agent/agents/encrypted_coder.md.age
  dot_pi/agent/agents/encrypted_git.md.age
  dot_pi/agent/agents/encrypted_planner.md.age
  dot_pi/agent/agents/encrypted_reviewer.md.age
)

ROUTING_SKILL_TARGETS=(
  "$HOME/.claude/skills/kickoff/SKILL.md"
  "$HOME/.codex/skills/model-orchestration/SKILL.md"
  "$HOME/.codex/skills/model-orchestration/references/model-routing.md"
)

TMP="$(mktemp -d "${TMPDIR:-/tmp}/agent-config-sync.XXXXXX")"
DEST="$(mktemp -d "${TMPDIR:-/tmp}/chezmoi-dest.XXXXXX")"
trap 'rm -rf "$TMP" "$DEST"' EXIT
render() { chezmoi "${SRC[@]}" execute-template --file "$1" >"$2"; }
# Persistent state for isolated temp destination applies (not live HOME).
TMP_SRC=("${SRC[@]}" --persistent-state "$TMP/temp-state.boltdb")

check_retired_target_removals
check_retired_target_apply
check_live_retired_target_regressions
check_active_retired_references
check_active_target_completeness
check_sync_command_flow
check_pickforge_lanes_deployment
check_doctor_sources

for f in "${SHARED[@]}"; do need "$f"; done
[[ -f .chezmoitemplates/agents-shared.md ]] && \
  grep -q 'agents-shared-before-worktrees.md' .chezmoitemplates/agents-shared.md && \
  grep -q 'agents-shared-after-git.md' .chezmoitemplates/agents-shared.md && \
  pass 'agents-shared.md composes parts' || err 'agents-shared.md must include before/after parts'

shared_source_bytes=$((
  $(wc -c <.chezmoitemplates/agents-shared-before-worktrees.md) +
  $(wc -c <.chezmoitemplates/agents-shared-after-git.md)
))
if ((shared_source_bytes <= SHARED_MAX_BYTES)); then
  pass "shared source size ${shared_source_bytes} bytes (recorded baseline ${SHARED_SOURCE_BASELINE}; budget ${SHARED_MAX_BYTES})"
else
  err "shared source size ${shared_source_bytes} bytes exceeds ${SHARED_MAX_BYTES}-byte regression budget (recorded source baseline: ${SHARED_SOURCE_BASELINE})"
fi

if render .chezmoitemplates/agents-shared.md "$TMP/agents-shared.md"; then
  shared_output_bytes="$(wc -c <"$TMP/agents-shared.md")"
  if ((shared_output_bytes <= SHARED_MAX_BYTES)); then
    pass "shared rendered size ${shared_output_bytes} bytes (recorded baseline ${SHARED_RENDERED_BASELINE}; budget ${SHARED_MAX_BYTES})"
  else
    err "shared rendered size ${shared_output_bytes} bytes exceeds ${SHARED_MAX_BYTES}-byte regression budget (recorded rendered baseline: ${SHARED_RENDERED_BASELINE})"
  fi
  for invariant in "${REQUIRED_SHARED_INVARIANTS[@]}"; do
    grep -Fq -- "$invariant" "$TMP/agents-shared.md" \
      && pass "shared output invariant: $invariant" || err "shared output invariant missing: $invariant"
  done
else
  err 'shared template render failed'
  rm -f "$TMP/agents-shared.md"
fi

if grep -Fq 'CODING_AGENT_RULES.md' "$TMP/agents-shared.md"; then
  err 'shared global harness loader must not auto-load CODING_AGENT_RULES'
else
  pass 'shared global harness loader excludes CODING_AGENT_RULES'
fi

if [[ -f "$TMP/agents-shared.md" ]]; then
  if grep -Fq '.agent-safety' "$TMP/agents-shared.md"; then
    err 'shared policy still contains retired .agent-safety instructions'
  else
    pass 'shared policy excludes retired .agent-safety instructions'
  fi
fi
for invariant in \
  '- Never push unless I explicitly ask, except in clearly identified Pickforge or Personal projects.' \
  '- Pickforge or Personal means the repo path or GitHub remote makes that ownership clear' \
  '- In clearly identified Pickforge or Personal projects, treat ship/open-PR as automatic'; do
  grep -Fq -- "$invariant" "$TMP/agents-shared.md" \
    && pass "shared policy retains permission: $invariant" \
    || err "shared policy permission missing: $invariant"
done

need "$OPENCODE"
for invariant in CORE_PROFILE.md WRITING_STYLE.md BOUNDARIES.md WORK_AND_PROJECTS.md 'projects/*.md'; do
  grep -Fq "$invariant" "$OPENCODE" \
    && pass "OpenCode memory invariant: $invariant" \
    || err "OpenCode memory invariant missing: $invariant"
done
grep -Fq 'CODING_AGENT_RULES.md' "$OPENCODE" \
  && err 'OpenCode global harness loader must not auto-load CODING_AGENT_RULES' \
  || pass 'OpenCode global harness loader excludes CODING_AGENT_RULES'


zsh_claude_wrapper="$(awk '
  /^claude\(\) \{/ { in_function=1 }
  in_function { print }
  in_function && /^}/ { exit }
' .chezmoitemplates/zshrc-common)"
zsh_codex_wrapper="$(awk '
  /^codex\(\) \{/ { in_function=1 }
  in_function { print }
  in_function && /^}/ { exit }
' .chezmoitemplates/zshrc-common)"
bash_claude_wrapper="$(awk '
  /^claude\(\) \{/ { in_function=1 }
  in_function { print }
  in_function && /^}/ { exit }
' dot_bashrc)"
if grep -Fq 'command claude --dangerously-skip-permissions "$@"' <<<"$zsh_claude_wrapper" \
  && grep -Fq 'command codex --yolo "$@"' <<<"$zsh_codex_wrapper" \
  && grep -Fq 'command claude --dangerously-skip-permissions "$@"' <<<"$bash_claude_wrapper"; then
  pass 'zsh and bash wrappers use unrestricted global Claude/Codex commands'
else
  err 'zsh or bash global wrapper contract mismatch'
fi
unset zsh_claude_wrapper zsh_codex_wrapper bash_claude_wrapper

if [[ -f .chezmoitemplates/zshrc-linux ]]; then
  linux_claude_codex="$(awk '
    /^claude-codex\(\) \{/ { in_function=1 }
    in_function { print }
    in_function && /^}/ { exit }
  ' .chezmoitemplates/zshrc-linux)"
  if grep -Fq 'CLAUDE_CONFIG_DIR="$HOME/.claude"' <<<"$linux_claude_codex" \
    && grep -Fq 'ANTHROPIC_BASE_URL="http://127.0.0.1:8317"' <<<"$linux_claude_codex" \
    && grep -Fq 'ANTHROPIC_AUTH_TOKEN="$CLIPROXY_API_KEY"' <<<"$linux_claude_codex" \
    && grep -Fq 'ANTHROPIC_MODEL="$model"' <<<"$linux_claude_codex" \
    && grep -Fq 'ANTHROPIC_SMALL_FAST_MODEL="gpt-5.6-sol"' <<<"$linux_claude_codex" \
    && grep -Fq '"$HOME/.local/bin/claude" --dangerously-skip-permissions "$@"' <<<"$linux_claude_codex" \
    && ! grep -Fq '.claude-personal' <<<"$linux_claude_codex"; then
    pass 'Linux claude-codex preserves proxy/model behavior on the global Claude profile'
  else
    err 'Linux claude-codex proxy/model or global-profile contract mismatch'
  fi
  if render .chezmoitemplates/zshrc-linux "$TMP/zshrc-linux" \
    && zsh -n "$TMP/zshrc-linux"; then
    pass 'temporary Linux zsh template renders with valid syntax'
  else
    err 'temporary Linux zsh template render or syntax check failed'
  fi
  unset linux_claude_codex
else
  err 'missing: .chezmoitemplates/zshrc-linux'
fi

need "$SOUL"
grep -q '/home/dev/AgentMemory' "$SOUL" || err 'Hermes SOUL missing AgentMemory'
grep -qi 'public' "$SOUL" || err 'Hermes SOUL missing public-action boundary'
grep -qi 'memory' "$SOUL" || err 'Hermes SOUL missing memory boundary'
grep -qE 'I like short, practical work|Fix root causes, not symptoms' "$SOUL" \
  && err 'Hermes SOUL must not dump full coding policy' || pass 'Hermes SOUL identity-oriented'
grep -Fq 'CODING_AGENT_RULES.md' "$SOUL" \
  && pass 'Hermes remains the explicit standalone CODING_AGENT_RULES exception' \
  || err 'Hermes standalone memory exception missing CODING_AGENT_RULES'

[[ -L dot_grok/AGENTS.md.tmpl || -L dot_grok/AGENTS.md ]] && err 'Grok AGENTS must not be a symlink'
need dot_grok/AGENTS.md.tmpl
if [[ -f dot_grok/AGENTS.md.tmpl ]]; then
  grep -qE 'codex/AGENTS|\.\./\.codex|Personal Codex Notes' dot_grok/AGENTS.md.tmpl \
    && err 'Grok adapter links to or reuses Codex' || pass 'Grok adapter not Codex-linked'
fi

for entry in "${ADAPTER_BUDGETS[@]}"; do
  IFS='|' read -r path budget <<<"$entry"
  bytes="$(wc -c <"$path")"
  if ((bytes <= budget)); then
    pass "adapter source size ${path}: ${bytes} bytes (budget ${budget})"
  else
    err "adapter source size ${path}: ${bytes} bytes exceeds ${budget}-byte regression budget"
  fi
done

for path in dot_claude/CLAUDE.md.tmpl \
  dot_codex/AGENTS.md.tmpl dot_grok/AGENTS.md.tmpl private_dot_factory/AGENTS.md.tmpl; do
  grep -qiE '^\|.*cost.*intelligence.*taste.*vision.*\|$' "$path" \
    && err "adapter embeds a full model scoring table: $path" \
    || pass "adapter has no full model scoring table: $path"
done

ADAPTER_OWNER_POINTERS=(
  'dot_claude/CLAUDE.md.tmpl|model-routing.md|Claude'
  'dot_codex/AGENTS.md.tmpl|$model-orchestration|Codex'
  'dot_grok/AGENTS.md.tmpl|model-orchestration|Grok'
  'dot_pi/agent/AGENTS.md.tmpl|Available managed pool|Pi'
  'dot_omp/agent/AGENTS.md.tmpl|Available managed pool|OMP'
  'private_dot_factory/AGENTS.md.tmpl|runtime model pool|Factory'
)
for entry in "${ADAPTER_OWNER_POINTERS[@]}"; do
  IFS='|' read -r path pointer harness <<<"$entry"
  grep -Fq "$pointer" "$path" \
    && pass "$harness adapter points to its routing owner" \
    || err "$harness adapter missing routing owner pointer: $pointer"
done

grep -Fq '| Grok 4.5 | `xai/grok-4.5` | high | 3 | 7 | 6 | yes |' dot_pi/agent/AGENTS.md.tmpl \
  && pass 'Pi routing table includes calibrated native Grok 4.5' \
  || err 'Pi routing table missing calibrated native Grok 4.5'
grep -Fq '| Grok 4.5 | `xai-oauth/grok-4.5` | high | 3 | 7 | 6 | yes |' dot_omp/agent/AGENTS.md.tmpl \
  && pass 'OMP routing table includes calibrated Grok 4.5' \
  || err 'OMP routing table missing calibrated Grok 4.5'

if grep -Fq 'await agent(prompt' dot_omp/agent/AGENTS.md.tmpl \
  && grep -Fq '`parallel()`' dot_omp/agent/AGENTS.md.tmpl \
  && grep -Fq 'The main model owns scope' dot_omp/agent/AGENTS.md.tmpl; then
  pass 'OMP adapter uses native agent/parallel mechanics and main-session ownership'
else
  err 'OMP adapter missing native agent/parallel mechanics or main-session ownership'
fi

for path in "${STALE_PI_FLOW_PATHS[@]}"; do
  [[ ! -e "$path" ]] \
    && pass "stale Pi flow source absent: $path" \
    || err "stale Pi flow source remains: $path"
done

pi_settings=''
if pi_settings="$(chezmoi "${SRC[@]}" cat "$HOME/.pi/agent/settings.json")"; then
  if jq -e . >/dev/null 2>&1 <<<"$pi_settings"; then
    pass 'Pi settings JSON valid'
    jq -e 'any(.. | strings; contains("pi-kit") or contains("pi-subagents"))' >/dev/null <<<"$pi_settings" \
      && pass 'Pi runtime enables native subagents (pi-kit)' \
      || err 'Pi runtime missing native subagents'
    jq -e 'any(.. | strings; ascii_downcase | contains("haiku"))' >/dev/null <<<"$pi_settings" \
      && err 'Pi settings contain a forbidden Haiku selector' \
      || pass 'Pi settings contain no Haiku selector'
    jq -e '.enabledModels | any(. == "xai/grok-4.5")' >/dev/null <<<"$pi_settings" \
      && pass 'Pi enabled models include native Grok 4.5' \
      || err 'Pi enabled models missing native Grok 4.5'
    jq -e '.defaultProvider == "xai" and .defaultModel == "grok-4.5" and .defaultThinkingLevel == "high"' >/dev/null <<<"$pi_settings" \
      && pass 'Pi canonical bootstrap defaults to native Grok 4.5 at high effort' \
      || err 'Pi canonical native Grok 4.5 bootstrap default is missing or misconfigured'
  else
    err 'Pi settings JSON invalid'
  fi
else
  err 'could not decrypt Pi settings for runtime checks'
fi
unset pi_settings

pi_models=''
if pi_models="$(chezmoi "${SRC[@]}" cat "$HOME/.pi/agent/models.json")"; then
  if jq -e . >/dev/null 2>&1 <<<"$pi_models"; then
    pass 'Pi models JSON valid'
    jq -e '.providers.ollama.models | any(.id == "glm-5.2:cloud")' >/dev/null <<<"$pi_models" \
      && pass 'Pi models include Ollama GLM-5.2 Cloud' \
      || err 'Pi models missing Ollama GLM-5.2 Cloud'
    jq -e '(.providers | has("local-llama")) or any(.. | strings; ascii_downcase | contains("local-llama"))' >/dev/null <<<"$pi_models" \
      && err 'Pi models still contain removed local-llama provider or model' \
      || pass 'Pi models omit removed local-llama provider and model'
  else
    err 'Pi models JSON invalid'
  fi
else
  err 'could not decrypt Pi models for runtime checks'
fi
unset pi_models

FACTORY_FLOW_HOOK=private_dot_factory/hooks/executable_model-flow-reminder.sh
need "$FACTORY_FLOW_HOOK"
grep -Fq 'lightest sufficient path' "$FACTORY_FLOW_HOOK" \
  && grep -Fq '$local-review' "$FACTORY_FLOW_HOOK" \
  && pass 'Factory runtime injects adaptive local-review reminder' \
  || err 'Factory runtime missing adaptive local-review reminder'
grep -qiE '(planner|coder|reviewer|git) droid|plan -> code -> review' "$FACTORY_FLOW_HOOK" \
  && err 'Factory runtime still injects named model flow' \
  || pass 'Factory runtime avoids named model flow'

for target in "${ROUTING_SKILL_TARGETS[@]}"; do
  decrypted=''
  if ! decrypted="$(chezmoi "${SRC[@]}" cat "$target")"; then
    err "could not decrypt routing skill for checks: $target"
    continue
  fi

  grep -qiE 'CLAUDE\.md([^[:alnum:]]+model)?[^[:alnum:]]+table' <<<"$decrypted" \
    && err "routing skill contains stale CLAUDE.md table reference: $target" \
    || pass "routing skill avoids stale CLAUDE.md table reference: $target"

  case "$target" in
    */codex-fable/SKILL.md|*/codex-opus/SKILL.md)
      grep -Fq 'Before selecting any worker or reviewer, read `~/.codex/skills/model-orchestration/references/model-routing.md` completely.' <<<"$decrypted" \
        && pass 'Claude workflow requires the model-routing owner before routing' \
        || err 'Claude workflow missing required pre-routing model-routing read'
      ;;
    */references/model-routing.md)
      grep -Fq '$pickgauge-usage' <<<"$decrypted" \
        && grep -Fq 'intelligence > taste > cost' <<<"$decrypted" \
        && pass 'model-routing owns wave headroom and shipping preference' \
        || err 'model-routing missing wave headroom or shipping preference'
      ;;
    */kickoff/SKILL.md)
      grep -Fq 'model-routing.md' <<<"$decrypted" \
        && pass 'kickoff fallback routing points to model-routing owner' \
        || err 'kickoff fallback routing missing model-routing owner'
      ;;
  esac
done
unset decrypted

local_review=''
if local_review="$(chezmoi "${SRC[@]}" decrypt \
  "$ROOT/dot_agents/skills/local-review/encrypted_SKILL.md.age")"; then
  grep -Fq 'Every review includes a KISS gate' <<<"$local_review" \
    && grep -Fq 'mandatory KISS verdict' <<<"$local_review" \
    && pass 'local-review requires a scoped KISS gate' \
    || err 'local-review missing required KISS gate'
  grep -Fq '~/.codex/skills/model-orchestration/references/model-routing.md' <<<"$local_review" \
    && grep -Fq 'never treat a model as permanently assigned' <<<"$local_review" \
    && pass 'local-review delegates model selection to the current table' \
    || err 'local-review missing dynamic model selection'
  grep -Eq 'Grok 4\.5|GPT-5\.6|Fable 5|Opus 4\.8|GLM-5\.2' <<<"$local_review" \
    && err 'local-review contains fixed model lane assignments' \
    || pass 'local-review contains no fixed model lane assignments'
else
  err 'could not decrypt local-review skill for checks'
fi
unset local_review

for path in "${RETIRED_SOURCE_PATHS[@]}"; do
  source_absent "$path"
done
check_manifest_and_sources
check_legacy_model_skill_absence
check_skill_lock_retirements
check_omp_agent_override_sources
check_mcp_registry_and_config
check_runtime_exclusions


for entry in "${HARNESS[@]}"; do
  IFS='|' read -r path want forbid <<<"$entry"
  if [[ ! -f "$path" ]]; then err "missing: $path"; continue; fi
  grep -Eq 'template "(agents-shared\.md|agents-shared-before-worktrees\.md)"' "$path" \
    || err "missing shared include: $path"
  for bad in 'I like short, practical work' 'names, model IDs, and technical terms' '/home/dev/AgentMemory'; do
    grep -Fq "$bad" "$path" && err "duplicate shared policy in $path: $bad"
  done
  out="$TMP/$(echo "$path" | tr '/' '_')"
  if ! render "$path" "$out"; then err "render failed: $path"; continue; fi
  pass "rendered $path"
  grep -Fq "$want" "$out" || err "missing heading in $path: $want"
  grep -Fq "$forbid" "$out" && err "forbidden heading in $path: $forbid"
  [[ "$(grep -c 'I like short, practical work' "$out" || true)" -eq 1 ]] || err "shared intro count != 1 in $path"
  grep -q PickScribe "$out" || err "missing PickScribe in $path"
  grep -q '/home/dev/AgentMemory' "$out" || err "missing AgentMemory in $path"
  grep -Fq 'CODING_AGENT_RULES.md' "$out" \
    && err "global harness auto-loads CODING_AGENT_RULES: $path" \
    || pass "global harness excludes CODING_AGENT_RULES: $path"
done

GLOBAL_CLAUDE_OUT="$TMP/claude-global.md"

if render dot_claude/CLAUDE.md.tmpl "$GLOBAL_CLAUDE_OUT"; then
  grep -Fq '## Claude model orchestration' "$GLOBAL_CLAUDE_OUT" \
    && grep -Fq '/home/dev/AgentMemory' "$GLOBAL_CLAUDE_OUT" \
    && grep -Fq 'model-routing.md' "$GLOBAL_CLAUDE_OUT" \
    && pass 'global Claude profile renders full personal orchestration' \
    || err 'global Claude profile is missing full personal policy'
  grep -Fq '@RTK.md' "$GLOBAL_CLAUDE_OUT" \
    && err 'global Claude policy still loads retired RTK instructions' \
    || pass 'global Claude policy excludes retired RTK instructions'
  grep -Fq '## Restricted profile' "$GLOBAL_CLAUDE_OUT" \
    && err 'global Claude still renders restricted profile policy' \
    || pass 'global Claude has no restricted profile policy'
  grep -Fq '## Portable personal profile' "$GLOBAL_CLAUDE_OUT" \
    && err 'global Claude still renders portable personal profile policy' \
    || pass 'global Claude has no portable personal profile policy'
else
  err 'global Claude profile render failed'
fi

for public_profile_file in \
  .chezmoitemplates/claude-adapter-common.md \
  dot_claude/CLAUDE.md.tmpl; do
  grep -qiE '(^|[^[:alnum:]_])(company|contract|client|employer)([^[:alnum:]_]|$)' "$public_profile_file" \
    && err "profile source exposes private work-context vocabulary: $public_profile_file" \
    || pass "profile source uses generic public vocabulary: $public_profile_file"
done

render "$SOUL" "$TMP/SOUL.md" && pass 'rendered Hermes SOUL' || err 'Hermes SOUL render failed'

TARGETS=(
  "$DEST/.zshrc" "$DEST/.bashrc"
  "$DEST/.claude/CLAUDE.md"
  "$DEST/.claude/rules/context7.md" "$DEST/.claude/settings.json"
  "$DEST/.claude/skills/audit-report"
  "$DEST/.claude/skills/kickoff/SKILL.md"
  "$DEST/.claude/skills/model-runners"
  "$DEST/.claude/skills/ship-pr/SKILL.md"
  "$DEST/.claude/skills/pickgauge-usage/SKILL.md"
  "$DEST/.claude/skills/plan-issue/SKILL.md"
  "$DEST/.claude/skills/x-research/SKILL.md"
  "$DEST/.codex/AGENTS.md"
  "$DEST/.grok/AGENTS.md" "$DEST/.pi/agent/AGENTS.md" "$DEST/.omp/agent/AGENTS.md"
  "$DEST/.omp/agent/config.yml" "$DEST/.omp/agent/mcp.json" "$DEST/.omp/agent/agents"
  "$DEST/.factory/AGENTS.md"
  "$DEST/.config/opencode/AGENTS.md" "$DEST/.config/opencode/README.md"
  "$DEST/.hermes/SOUL.md"
  "$DEST/.local/bin/agent-config-sync"
  "$DEST/.local/bin/pickforge-lanes-mcp"
  "$DEST/.claude/skills/multi-model-lanes"
  "$DEST/.pi/agent/skills/multi-model-lanes"
  "$DEST/.agents/.skill-lock.json"
  "$DEST/.agents/skill-targets.json"
  "$DEST/.agents/mcp-targets.json"
)
EXPECTED=(
  dot_zshrc.tmpl dot_bashrc
  dot_claude/CLAUDE.md.tmpl
  dot_claude/rules/context7.md dot_claude/encrypted_settings.json.age
  dot_claude/skills/symlink_audit-report
  dot_claude/skills/kickoff/encrypted_SKILL.md.age
  dot_claude/skills/symlink_model-runners
  dot_claude/skills/ship-pr/encrypted_SKILL.md.age
  dot_claude/skills/pickgauge-usage/encrypted_SKILL.md.age
  dot_claude/skills/plan-issue/encrypted_private_SKILL.md.age
  dot_claude/skills/x-research/encrypted_SKILL.md.age
  dot_codex/AGENTS.md.tmpl
  dot_grok/AGENTS.md.tmpl dot_pi/agent/AGENTS.md.tmpl dot_omp/agent/AGENTS.md.tmpl
  dot_omp/agent/config.yml dot_omp/agent/mcp.json dot_omp/agent/agents
  private_dot_factory/AGENTS.md.tmpl
  dot_config/opencode/AGENTS.md dot_config/opencode/README.md
  private_dot_hermes/SOUL.md.tmpl
  dot_local/bin/executable_agent-config-sync
  dot_local/bin/executable_pickforge-lanes-mcp
  dot_claude/skills/symlink_multi-model-lanes
  dot_pi/agent/skills/symlink_multi-model-lanes
  dot_agents/dot_skill-lock.json
  dot_agents/skill-targets.json
  dot_agents/mcp-targets.json
)
if chezmoi "${TMP_SRC[@]}" --destination "$DEST" source-path "${TARGETS[@]}" >"$TMP/sp.txt" 2>"$TMP/sp.err"; then
  for e in "${EXPECTED[@]}"; do
    grep -Fq "$e" "$TMP/sp.txt" && pass "source-path $e" || err "source-path missing $e"
  done
else
  err "source-path failed: $(tr '\n' ' ' <"$TMP/sp.err")"
fi
chezmoi "${TMP_SRC[@]}" --destination "$DEST" --dry-run status >/dev/null 2>"$TMP/st.err" \
  && pass 'dry-run status (temp dest)' || err "dry-run status failed: $(tr '\n' ' ' <"$TMP/st.err")"

mkdir -p "$DEST/.grok" "$DEST/.hermes" "$DEST/.config/opencode" \
  "$DEST/.local/bin" \
  "$DEST/.claude/rules" \
  "$DEST/.claude/skills/kickoff" \
  "$DEST/.claude/skills/ship-pr" \
  "$DEST/.claude/skills/pickgauge-usage" \
  "$DEST/.claude/skills/plan-issue" \
  "$DEST/.claude/skills/x-research" \
  "$DEST/.codex/skills/model-orchestration/references" \
  "$DEST/.codex/skills/ship-pr" \
  "$DEST/.grok/skills/model-orchestration" \
  "$DEST/.pi/agent/skills" "$DEST/.omp/agent/skills" \
  "$DEST/.factory/skills" "$DEST/.hermes/skills" "$DEST/.agents/skills"
ln -s ../.codex/AGENTS.md "$DEST/.grok/AGENTS.md"
printf '%s\n' 'You are Hermes Agent, an intelligent AI assistant created by Nous Research.' >"$DEST/.hermes/SOUL.md"

if ! chezmoi "${TMP_SRC[@]}" --destination "$DEST" apply "$DEST/.agents/skills" "${TARGETS[@]}"; then
  err 'temp seed apply (canonical skills / adapters) failed'
else
  ! grep -Fq 'Projects/Personal/.agent-safety/bin:$PATH' "$DEST/.zshrc" \
    && pass 'temp zsh profile excludes retired Personal GitHub guard PATH' \
    || err 'temp zsh profile still enables Personal GitHub guard PATH'
  ! grep -Fq 'claude-default' "$DEST/.zshrc" \
    && ! grep -Fq 'claude-personal' "$DEST/.zshrc" \
    && pass 'temp zsh profile uses unrestricted global claude wrapper' \
    || err 'temp zsh profile still routes through split-profile launchers'
  grep -Fq '## Claude model orchestration' "$DEST/.claude/CLAUDE.md" \
    && pass 'temp global Claude profile applied' \
    || err 'temp global Claude profile missing full orchestration'
  [[ ! -e "$DEST/.claude-personal" ]] \
    && pass 'temp destination has no portable Claude profile tree' \
    || err 'temp destination still creates portable Claude profile tree'
  [[ ! -e "$DEST/.config/agent-profiles" ]] \
    && pass 'temp destination has no agent-profiles role tree' \
    || err 'temp destination still creates agent-profiles role tree'
  [[ ! -e "$DEST/Projects/Personal/.codex" && ! -e "$DEST/Projects/Personal/.agent-safety" ]] \
    && pass 'temp destination has no Personal Codex or agent-safety trees' \
    || err 'temp destination still creates Personal Codex or agent-safety trees'
  [[ -x "$DEST/.local/bin/agent-config-sync" ]] \
    && bash -n "$DEST/.local/bin/agent-config-sync" \
    && pass 'temp agent-config-sync applied' \
    || err 'temp agent-config-sync invalid'
  [[ ! -L "$DEST/.grok/AGENTS.md" ]] && grep -q '^# Personal Grok Notes' "$DEST/.grok/AGENTS.md" \
    && pass 'temp migration replaces Grok symlink safely' || err 'temp Grok symlink migration failed'
  grep -q '^# Hermes' "$DEST/.hermes/SOUL.md" && grep -q '/home/dev/AgentMemory' "$DEST/.hermes/SOUL.md" \
    && pass 'temp migration replaces default Hermes SOUL safely' || err 'temp Hermes SOUL migration failed'
  grep -q '^# Personal OMP Notes' "$DEST/.omp/agent/AGENTS.md" \
    && ! grep -Fq 'CODING_AGENT_RULES.md' "$DEST/.omp/agent/AGENTS.md" \
    && pass 'temp OMP adapter applied without global CODING_AGENT_RULES load' \
    || err 'temp OMP adapter apply mismatch'
  cmp -s "$DEST/.omp/agent/config.yml" "$ROOT/dot_omp/agent/config.yml" \
    && pass 'temp OMP runtime config applied' || err 'temp OMP runtime config apply mismatch'
  cmp -s "$DEST/.omp/agent/mcp.json" "$OMP_MCP" \
    && pass 'temp OMP MCP config applied' || err 'temp OMP MCP config apply mismatch'
  if [[ -d "$DEST/.omp/agent/agents" && ! -L "$DEST/.omp/agent/agents" ]]; then
    pass 'temp OMP agent override directory applied'
  else
    err 'temp OMP agent override directory apply mismatch'
  fi
  for role in task reviewer; do
    validate_omp_agent_override "$role" "$DEST/.omp/agent/agents/${role}.md"
    if [[ -f "$DEST/.omp/agent/agents/${role}.md" ]] \
      && cmp -s "$DEST/.omp/agent/agents/${role}.md" "$OMP_AGENT_OVERRIDES_DIR/${role}.md"; then
      pass "temp OMP ${role} override matches canonical source"
    else
      err "temp OMP ${role} override apply mismatch"
    fi
  done
  cmp -s "$DEST/.config/opencode/AGENTS.md" "$ROOT/dot_config/opencode/AGENTS.md" \
    && ! grep -Fq 'CODING_AGENT_RULES.md' "$DEST/.config/opencode/AGENTS.md" \
    && pass 'temp OpenCode memory cutover applied' \
    || err 'temp OpenCode memory cutover apply mismatch'
  cmp -s "$DEST/.config/opencode/README.md" "$ROOT/dot_config/opencode/README.md" \
    && pass 'temp OpenCode README applied' \
    || err 'temp OpenCode README apply mismatch'
  cmp -s "$DEST/.agents/.skill-lock.json" "$SKILL_LOCK" \
    && pass 'temp skill lock applied' \
    || err 'temp skill lock apply mismatch'
fi

if [[ -d "$DEST/.agents/skills/context7-mcp" ]]; then
  mkdir -p "$DEST/.claude/skills"
  rm -rf "$DEST/.claude/skills/context7-mcp"
  cp -a "$DEST/.agents/skills/context7-mcp" "$DEST/.claude/skills/context7-mcp"
  if dirs_identical "$DEST/.claude/skills/context7-mcp" "$DEST/.agents/skills/context7-mcp"; then
    pass 'seeded identical Context7 directory: .claude/skills'
  else
    err 'failed to seed Context7 directory: .claude/skills'
  fi
else
  err 'canonical context7-mcp missing after seed apply'
fi

PORTABLE_TARGETS=()
while IFS= read -r target; do
  PORTABLE_TARGETS+=("$target")
done < <(jq -r --arg dest "$DEST" '
  . as $root
  | .skills | to_entries[]
  | .key as $skill
  | .value[] as $harness
  | $root.harnesses[$harness] as $h
  | select($h.discovery == "symlink")
  | ($h.skills_root | sub("^~"; $dest)) + "/" + $skill
' "$MANIFEST")

if ((${#PORTABLE_TARGETS[@]})); then
  if chezmoi "${TMP_SRC[@]}" --destination "$DEST" apply "${PORTABLE_TARGETS[@]}"; then
    pass "temp applied ${#PORTABLE_TARGETS[@]} portable skill links"
  else
    err 'temp portable skill apply failed'
  fi
fi

while IFS=$'\t' read -r skill harness; do
  discovery="$(jq -r --arg h "$harness" '.harnesses[$h].discovery' "$MANIFEST")"
  [[ "$discovery" == "symlink" ]] || continue
  root="$(jq -r --arg h "$harness" --arg dest "$DEST" \
    '.harnesses[$h].skills_root | sub("^~"; $dest)' "$MANIFEST")"
  expected_prefix="$(jq -r --arg h "$harness" '.harnesses[$h].relative_prefix' "$MANIFEST")"
  link="${root}/${skill}"
  want="${expected_prefix}/${skill}"
  if [[ ! -L "$link" ]]; then
    err "temp portable link missing or not symlink: $harness/$skill ($link)"
    continue
  fi
  got="$(readlink "$link")"
  if [[ "$got" != "$want" ]]; then
    err "temp readlink $harness/$skill expected '$want' got '$got'"
    continue
  fi
  if [[ ! -e "$link/SKILL.md" ]]; then
    err "temp resolved SKILL.md missing: $harness/$skill"
    continue
  fi
  if ! cmp -s "$link/SKILL.md" "$DEST/.agents/skills/${skill}/SKILL.md"; then
    err "temp SKILL.md mismatch vs canonical: $harness/$skill"
    continue
  fi
  pass "temp portable ok: $harness/$skill"
done < <(jq -r '.skills | to_entries[] | .key as $s | .value[] | "\($s)\t\(.)"' "$MANIFEST")

check_primary_global_live_regressions

PENDING_FILE="$TMP/managed-pending-drift"
printf '%s\n' managed >"$PENDING_FILE"
read -r PENDING_HASH _ < <(sha256sum "$PENDING_FILE")
chezmoi() {
  if [[ "$1" == state && "$2" == get ]]; then
    printf '{"contentsSHA256":"%s"}\n' "$PENDING_HASH"
  else
    command chezmoi "$@"
  fi
}
if managed_regular_file_unchanged "$PENDING_FILE"; then
  pass 'managed pending drift accepts unchanged prior target'
else
  err 'managed pending drift rejected unchanged prior target'
fi
printf '%s\n' divergent >>"$PENDING_FILE"
if managed_regular_file_unchanged "$PENDING_FILE"; then
  err 'managed pending drift accepted divergent target'
else
  pass 'managed pending drift rejects divergent target'
fi
unset -f chezmoi

bash -n "$ROOT/scripts/check-agent-config-sync.sh" && pass 'bash -n' || err 'bash -n failed'
if [[ -f "$ROOT/dot_local/bin/executable_agent-config-sync" ]]; then
  bash -n "$ROOT/dot_local/bin/executable_agent-config-sync" && pass 'bash -n agent-config-sync' \
    || err 'bash -n agent-config-sync failed'
  grep -Fq 'preflight_unmanaged_targets' "$ROOT/dot_local/bin/executable_agent-config-sync" \
    && pass 'agent-config-sync protects unmanaged first-apply targets' \
    || err 'agent-config-sync missing unmanaged-target preflight'
  grep -Fq 'apply_targets=("${active_targets[@]}")' "$ROOT/dot_local/bin/executable_agent-config-sync" \
    && grep -Fq 'chezmoi "${SRC[@]}" apply --force --no-tty -- "${apply_targets[@]}"' \
      "$ROOT/dot_local/bin/executable_agent-config-sync" \
    && pass 'agent-config-sync applies only scoped active and retirement targets' \
    || err 'agent-config-sync missing scoped active/retirement apply'
  ! grep -Eq '^known_legacy_model_skill\(\)' "$ROOT/dot_local/bin/executable_agent-config-sync" \
    && ! grep -Eq '^known_legacy_model_skill\(\)' "$ROOT/scripts/check-agent-config-sync.sh" \
    && pass 'obsolete legacy model skill hash helpers removed' \
    || err 'obsolete legacy model skill hash helper remains'
  ! grep -Eq 'LIVE_PROFILE_ROLE|PROFILE_ROLE|agentProfile|require-portable-links|bootstrap_real_gh|remove_main_profile_paths|claude-personal' \
    "$ROOT/dot_local/bin/executable_agent-config-sync" \
    && pass 'agent-config-sync excludes split-profile orchestration' \
    || err 'agent-config-sync still contains split-profile orchestration'
fi

echo
[[ "$fail" -eq 0 ]] && { echo "PASSED: agent-config-sync checks"; exit 0; }
echo "FAILED: agent-config-sync checks"; exit 1
