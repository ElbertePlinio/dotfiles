#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
SRC=(--source "$ROOT")
fail=0
MODE=default
REQUIRE_PORTABLE_LINKS=0
STRICT_PREFLIGHT=0
for arg in "$@"; do
  case "$arg" in
    --check-live-migration) MODE=live ;;
    --require-portable-links) REQUIRE_PORTABLE_LINKS=1 ;;
    --strict-preflight) STRICT_PREFLIGHT=1 ;;
  esac
done

PROFILE_ROLE="$(chezmoi "${SRC[@]}" execute-template '{{ .agentProfile | default "restricted" }}')"
if [[ "$PROFILE_ROLE" != main && "$PROFILE_ROLE" != restricted ]]; then
  printf 'ERR invalid profile role: %s\n' "$PROFILE_ROLE" >&2
  exit 1
fi

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

known_legacy_model_skill() {
  local skill="$1" dir="$2" expected_hash actual_hash live
  local -a entries
  case "$skill" in
    codex) expected_hash='bcf38f2d2b463edaf6a7d5cf7374616318dfe24e133053ca45f42621eaedcb5c' ;;
    grok) expected_hash='fdd4ad1e3a40569ab80f0e1dc59fc5e197f39409b265b8bc01207cac82f39483' ;;
    *) return 1 ;;
  esac
  [[ -d "$dir" && ! -L "$dir" ]] || return 1
  live="$dir/SKILL.md"
  shopt -s nullglob dotglob
  entries=("$dir"/*)
  shopt -u nullglob dotglob
  [[ "${#entries[@]}" -eq 1 && "${entries[0]}" == "$live" && -f "$live" && ! -L "$live" ]] || return 1
  read -r actual_hash _ < <(sha256sum "$live")
  [[ "$actual_hash" == "$expected_hash" ]]
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
  Projects/Personal/private_dot_agent-safety/symlink_real-gh
  Projects/Personal/private_dot_agent-safety/private_use-isolated-gh
  Projects/Personal/private_dot_agent-safety/private_gh
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
  .claude-personal/.credentials.json
  .claude-personal/history.jsonl
  .claude-personal/plugins
  .claude-personal/projects
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
  Projects/Personal/.agent-safety/real-gh
  Projects/Personal/.agent-safety/use-isolated-gh
  Projects/Personal/.agent-safety/gh
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

  local claude_source
  for claude_source in dot_claude dot_claude-personal; do
    if [[ -e "$ROOT/${claude_source}/skills/context7-mcp" ]]; then
      err "duplicate Context7 skill source still present: $claude_source"
    else
      pass "no duplicate Context7 skill directory: $claude_source"
    fi
  done

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
    if [[ "$PROFILE_ROLE" == restricted && "$harness" == claude ]]; then
      continue
    fi
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
      if [[ "$REQUIRE_PORTABLE_LINKS" -eq 1 ]]; then
        err "live link missing: $link"
      else
        pass "live link not yet applied: $harness/$skill"
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

    if [[ "$REQUIRE_PORTABLE_LINKS" -eq 1 ]]; then
      err "live path is not a symlink: $link"
      continue
    fi

    if [[ ! -d "$canon" ]]; then
      if known_legacy_model_skill "$skill" "$link"; then
        pass "live legacy model skill is safely migratable: $harness/$skill"
      else
        err "canonical skill missing for comparison: $canon"
      fi
      continue
    fi
    if [[ -d "$link" ]] && dirs_identical "$link" "$canon"; then
      pass "live path identical to canonical (migratable): $harness/$skill"
    else
      err "live non-symlink path differs from canonical: $link"
    fi
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

check_live_native_routing_files() {
  local live rendered
  local -a files=(
    "${HOME}/.codex/skills/model-orchestration/SKILL.md"
    "${HOME}/.codex/skills/model-orchestration/references/model-routing.md"
  )
  if [[ "$PROFILE_ROLE" == main ]]; then
    files+=(
      "${HOME}/.claude/skills/kickoff/SKILL.md"
    )
  fi

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

check_live_split_profile_targets() {
  local -a targets=(
    "${HOME}/.config/agent-profiles/role"
    "${HOME}/.config/agent-profiles/personal-roots"
    "${HOME}/.local/bin/claude-profile"
    "${HOME}/.local/bin/claude-default"
    "${HOME}/.local/bin/claude-personal"
    "${HOME}/.local/bin/agent-profile-doctor"
    "${HOME}/.zshrc"
    "${HOME}/.bashrc"
    "${HOME}/.claude/CLAUDE.md"
    "${HOME}/.claude-personal"
    "${HOME}/Projects/Personal/.codex/config.toml"
    "${HOME}/Projects/Personal/.codex/AGENTS.md"
    "${HOME}/Projects/Personal/.codex/skills"
    "${HOME}/Projects/Personal/.agent-safety/bin/gh"
    "${HOME}/Projects/Personal/.agent-safety/bin/gh-credential"
    "${HOME}/Projects/Personal/.agent-safety/verify-personal-github"
    "${HOME}/Projects/Personal/.agent-safety/install-repo-hook"
    "${HOME}/Projects/Personal/.agent-safety/hooks/pre-push"
  )
  if [[ "$PROFILE_ROLE" == main ]]; then
    targets+=(
      "${HOME}/.claude/RTK.md"
      "${HOME}/.claude/rules"
      "${HOME}/.claude/settings.json"
      "${HOME}/.claude/skills"
    )
  fi

  if chezmoi "${SRC[@]}" verify "${targets[@]}" >/dev/null 2>&1; then
    pass 'live default and portable profiles match managed target state'
  else
    err 'live default or portable profile differs from managed target state'
  fi
}

check_live_portable_scope() {
  local path
  local -a forbidden=(
    "${HOME}/.claude-personal/codex-opus-workflow.html"
    "${HOME}/.claude-personal/skills/agent-config-sync"
    "${HOME}/.claude-personal/skills/codex-fable"
    "${HOME}/.claude-personal/skills/codex-opus"
    "${HOME}/.claude-personal/skills/kickoff"
    "${HOME}/.claude-personal/skills/local-review"
    "${HOME}/.claude-personal/skills/ship-pr"
  )
  for path in "${forbidden[@]}"; do
    if [[ -e "$path" || -L "$path" ]]; then
      if [[ "$STRICT_PREFLIGHT" -eq 1 ]]; then
        pass "portable full-profile path pending removal: $path"
      else
        err "portable profile still contains full-profile path: $path"
      fi
    fi
  done
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
  elif [[ "$REQUIRE_PORTABLE_LINKS" -eq 1 ]]; then
    err 'live OMP config differs from canonical source after apply'
  else
    pass 'live OMP config has managed runtime drift pending the authorized cutover'
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
  check_live_portable_scope


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
      if [[ "$REQUIRE_PORTABLE_LINKS" -eq 1 ]]; then
        err 'live OpenCode still auto-loads CODING_AGENT_RULES after apply'
      else
        pass 'live OpenCode is managed and pending the authorized memory cutover'
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

  if [[ "$STRICT_PREFLIGHT" -eq 0 ]]; then
    check_live_split_profile_targets
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
REQUIRED_SHARED_INVARIANTS=(
  'I like short, practical work. Read the repo, make the smallest clean change, and show proof before calling something done.'
  '- Be direct: no filler or ceremony. Fix root causes, not symptoms.'
  '- No hacks, monkey patches, fake fixes, temporary workarounds, or unrelated refactors.'
  'Dictation can corrupt names, model IDs, and technical terms. Confirm suspicious or contradictory wording instead of following it literally.'
  '- Never expose, print, commit, or send secrets or private production data.'
  '- Destructive filesystem, Git, account, or external-service actions require explicit confirmation.'
  '- Public actions (posts, replies, likes, follows, DMs, publishing) are drafts only; the user performs them.'
  '- Never use Anthropic Haiku — directly, via any tool, skill, subagent, fallback, or hidden route.'
  'verify-personal-github` to verify `ElbertePlinio`'
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
  'dot_claude-personal/CLAUDE.md.tmpl|500'
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
RESTRICTED_DEST="$(mktemp -d "${TMPDIR:-/tmp}/chezmoi-restricted.XXXXXX")"
trap 'rm -rf "$TMP" "$DEST" "$RESTRICTED_DEST"' EXIT
render() { chezmoi "${SRC[@]}" execute-template --file "$1" >"$2"; }
MAIN_PROFILE_DATA='{"agentProfile":"main"}'
RESTRICTED_PROFILE_DATA='{"agentProfile":"restricted"}'
MAIN_SRC=(--override-data "$MAIN_PROFILE_DATA" "${SRC[@]}" --persistent-state "$TMP/main-state.boltdb")
RESTRICTED_SRC=(--override-data "$RESTRICTED_PROFILE_DATA" "${SRC[@]}" --persistent-state "$TMP/restricted-state.boltdb")
render_profile() {
  local profile="$1" source_file="$2" destination_file="$3" data
  case "$profile" in
    main) data="$MAIN_PROFILE_DATA" ;;
    restricted) data="$RESTRICTED_PROFILE_DATA" ;;
    *) err "unknown render profile: $profile"; return 1 ;;
  esac
  chezmoi "${SRC[@]}" --override-data "$data" execute-template --file "$source_file" >"$destination_file"
}

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
  pass "shared source size ${shared_source_bytes} bytes (budget ${SHARED_MAX_BYTES})"
else
  err "shared source size ${shared_source_bytes} bytes exceeds ${SHARED_MAX_BYTES}-byte regression budget (recorded baseline: 11400)"
fi

if render .chezmoitemplates/agents-shared.md "$TMP/agents-shared.md"; then
  shared_output_bytes="$(wc -c <"$TMP/agents-shared.md")"
  if ((shared_output_bytes <= SHARED_MAX_BYTES)); then
    pass "shared rendered size ${shared_output_bytes} bytes (budget ${SHARED_MAX_BYTES})"
  else
    err "shared rendered size ${shared_output_bytes} bytes exceeds ${SHARED_MAX_BYTES}-byte regression budget"
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


if [[ -f .chezmoitemplates/zshrc-linux ]]; then
  linux_claude_codex="$(awk '
    /^claude-codex\(\) \{/ { in_function=1 }
    in_function { print }
    in_function && /^}/ { exit }
  ' .chezmoitemplates/zshrc-linux)"
  if grep -Fq 'CLAUDE_CONFIG_DIR="$HOME/.claude"' <<<"$linux_claude_codex" \
    && ! grep -Fq '.claude-personal' <<<"$linux_claude_codex"; then
    pass 'Linux claude-codex selects only the global Claude profile'
  else
    err 'Linux claude-codex does not select only the global Claude profile'
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

for path in dot_claude/CLAUDE.md.tmpl dot_claude-personal/CLAUDE.md.tmpl \
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
  if ! decrypted="$(chezmoi "${MAIN_SRC[@]}" cat "$target")"; then
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

MAIN_CLAUDE_OUT="$TMP/claude-main.md"
PORTABLE_CLAUDE_OUT="$TMP/claude-portable.md"
RESTRICTED_CLAUDE_OUT="$TMP/claude-restricted.md"

if render_profile main dot_claude/CLAUDE.md.tmpl "$MAIN_CLAUDE_OUT"; then
  grep -Fq '## Model orchestration' "$MAIN_CLAUDE_OUT" \
    && grep -Fq '/home/dev/AgentMemory' "$MAIN_CLAUDE_OUT" \
    && grep -Fq 'model-routing.md' "$MAIN_CLAUDE_OUT" \
    && pass 'main Claude profile renders full personal orchestration' \
    || err 'main Claude profile is missing full personal policy'
  grep -Fq '@RTK.md' "$MAIN_CLAUDE_OUT" \
    && err 'global Claude policy still loads retired RTK instructions' \
    || pass 'global Claude policy excludes retired RTK instructions'
else
  err 'main Claude profile render failed'
fi

if render dot_claude-personal/CLAUDE.md.tmpl "$PORTABLE_CLAUDE_OUT"; then
  grep -Fq '## Portable personal profile' "$PORTABLE_CLAUDE_OUT" \
    && grep -Fq 'Do not use Grok, GLM' "$PORTABLE_CLAUDE_OUT" \
    && ! grep -Fq '/home/dev/AgentMemory' "$PORTABLE_CLAUDE_OUT" \
    && ! grep -Fq 'model-routing.md' "$PORTABLE_CLAUDE_OUT" \
    && pass 'portable Claude profile renders personal policy without full orchestration' \
    || err 'portable Claude profile policy mismatch'
else
  err 'portable Claude profile render failed'
fi

PORTABLE_SETTINGS_OUT="$TMP/claude-portable-settings.json"
if chezmoi "${SRC[@]}" decrypt dot_claude-personal/encrypted_settings.json.age >"$PORTABLE_SETTINGS_OUT" \
  && jq -e '
    .permissions.defaultMode == "manual"
    and .permissions.allow == [
      "Read", "Glob", "Grep", "Edit", "Write", "mcp__codegraph__*"
    ]
    and ((.permissions.deny // []) | length == 0)
    and (((.mcpServers // {}) | has("agentmemory-vault")) | not)
    and ((.enabledPlugins["claude-mem@thedotmack"] // false) | not)
  ' "$PORTABLE_SETTINGS_OUT" >/dev/null; then
  pass 'portable Claude settings require prompts for shell and external actions'
else
  err 'portable Claude settings grant unsafe unattended permissions'
fi

if render_profile restricted dot_claude/CLAUDE.md.tmpl "$RESTRICTED_CLAUDE_OUT"; then
  grep -Fq '## Restricted profile' "$RESTRICTED_CLAUDE_OUT" \
    && grep -Fq 'require explicit user authorization for that exact action' "$RESTRICTED_CLAUDE_OUT" \
    && ! grep -Fq 'Pickforge' "$RESTRICTED_CLAUDE_OUT" \
    && ! grep -Fq 'model-routing.md' "$RESTRICTED_CLAUDE_OUT" \
    && ! grep -Fq '/home/dev/AgentMemory' "$RESTRICTED_CLAUDE_OUT" \
    && pass 'restricted Claude profile renders neutral explicit-authorization policy' \
    || err 'restricted Claude profile policy mismatch'
else
  err 'restricted Claude profile render failed'
fi

for public_profile_file in \
  .chezmoitemplates/claude-core.md \
  .chezmoitemplates/claude-adapter-common.md \
  .chezmoitemplates/claude-personal-lite.md \
  .chezmoitemplates/claude-restricted.md \
  dot_claude/CLAUDE.md.tmpl \
  dot_claude-personal/CLAUDE.md.tmpl; do
  grep -qiE '(^|[^[:alnum:]_])(company|contract|client|employer)([^[:alnum:]_]|$)' "$public_profile_file" \
    && err "profile source exposes private work-context vocabulary: $public_profile_file" \
    || pass "profile source uses generic public vocabulary: $public_profile_file"
done

render "$SOUL" "$TMP/SOUL.md" && pass 'rendered Hermes SOUL' || err 'Hermes SOUL render failed'

TARGETS=(
  "$DEST/.config/agent-profiles/role" "$DEST/.config/agent-profiles/personal-roots"
  "$DEST/.local/bin/claude-profile" "$DEST/.local/bin/claude-default"
  "$DEST/.local/bin/claude-personal" "$DEST/.local/bin/agent-profile-doctor"
  "$DEST/.zshrc" "$DEST/.bashrc"
  "$DEST/.claude/CLAUDE.md" "$DEST/.claude/RTK.md"
  "$DEST/.claude/rules/context7.md" "$DEST/.claude/settings.json"
  "$DEST/.claude/skills/audit-report"
  "$DEST/.claude/skills/kickoff/SKILL.md"
  "$DEST/.claude/skills/model-runners"
  "$DEST/.claude/skills/ship-pr/SKILL.md"
  "$DEST/.claude/skills/pickgauge-usage/SKILL.md"
  "$DEST/.claude/skills/plan-issue/SKILL.md"
  "$DEST/.claude/skills/x-research/SKILL.md"
  "$DEST/.claude-personal/CLAUDE.md" "$DEST/.claude-personal/RTK.md"
  "$DEST/.claude-personal/rules/context7.md" "$DEST/.claude-personal/settings.json"
  "$DEST/.claude-personal/skills/model-runners"
  "$DEST/.codex/AGENTS.md"
  "$DEST/Projects/Personal/.codex/config.toml"
  "$DEST/Projects/Personal/.codex/AGENTS.md"
  "$DEST/Projects/Personal/.codex/skills"
  "$DEST/Projects/Personal/.agent-safety/bin/gh"
  "$DEST/Projects/Personal/.agent-safety/bin/gh-credential"
  "$DEST/Projects/Personal/.agent-safety/verify-personal-github"
  "$DEST/Projects/Personal/.agent-safety/install-repo-hook"
  "$DEST/Projects/Personal/.agent-safety/hooks/pre-push"
  "$DEST/.grok/AGENTS.md" "$DEST/.pi/agent/AGENTS.md" "$DEST/.omp/agent/AGENTS.md"
  "$DEST/.omp/agent/config.yml" "$DEST/.omp/agent/mcp.json" "$DEST/.omp/agent/agents"
  "$DEST/.factory/AGENTS.md" "$DEST/.config/opencode/AGENTS.md" "$DEST/.hermes/SOUL.md"
)
EXPECTED=(
  dot_config/agent-profiles/role.tmpl dot_config/agent-profiles/personal-roots
  dot_local/bin/executable_claude-profile dot_local/bin/executable_claude-default
  dot_local/bin/executable_claude-personal dot_local/bin/executable_agent-profile-doctor
  dot_zshrc.tmpl dot_bashrc
  dot_claude/CLAUDE.md.tmpl dot_claude/private_RTK.md
  dot_claude/rules/context7.md dot_claude/encrypted_settings.json.age
  dot_claude/skills/symlink_audit-report
  dot_claude/skills/kickoff/encrypted_SKILL.md.age
  dot_claude/skills/symlink_model-runners
  dot_claude/skills/ship-pr/encrypted_SKILL.md.age
  dot_claude/skills/pickgauge-usage/encrypted_SKILL.md.age
  dot_claude/skills/plan-issue/encrypted_private_SKILL.md.age
  dot_claude/skills/x-research/encrypted_SKILL.md.age
  dot_claude-personal/CLAUDE.md.tmpl dot_claude-personal/private_RTK.md
  dot_claude-personal/rules/context7.md dot_claude-personal/encrypted_settings.json.age
  dot_claude-personal/skills/symlink_model-runners
  dot_codex/AGENTS.md.tmpl
  Projects/Personal/dot_codex/config.toml
  Projects/Personal/dot_codex/symlink_AGENTS.md
  Projects/Personal/dot_codex/symlink_skills
  Projects/Personal/private_dot_agent-safety/bin/executable_gh
  Projects/Personal/private_dot_agent-safety/bin/executable_gh-credential
  Projects/Personal/private_dot_agent-safety/executable_verify-personal-github
  Projects/Personal/private_dot_agent-safety/executable_install-repo-hook
  Projects/Personal/private_dot_agent-safety/hooks/executable_pre-push
  dot_grok/AGENTS.md.tmpl dot_pi/agent/AGENTS.md.tmpl dot_omp/agent/AGENTS.md.tmpl
  dot_omp/agent/config.yml dot_omp/agent/mcp.json dot_omp/agent/agents
  private_dot_factory/AGENTS.md.tmpl dot_config/opencode/AGENTS.md private_dot_hermes/SOUL.md.tmpl
)
if chezmoi "${MAIN_SRC[@]}" --destination "$DEST" source-path "${TARGETS[@]}" >"$TMP/sp.txt" 2>"$TMP/sp.err"; then
  for e in "${EXPECTED[@]}"; do
    grep -Fq "$e" "$TMP/sp.txt" && pass "source-path $e" || err "source-path missing $e"
  done
else
  err "source-path failed: $(tr '\n' ' ' <"$TMP/sp.err")"
fi
chezmoi "${MAIN_SRC[@]}" --destination "$DEST" --dry-run status >/dev/null 2>"$TMP/st.err" \
  && pass 'dry-run status (temp dest)' || err "dry-run status failed: $(tr '\n' ' ' <"$TMP/st.err")"

mkdir -p "$DEST/.grok" "$DEST/.hermes" "$DEST/.config/opencode" \
  "$DEST/.config/agent-profiles" "$DEST/.local/bin" \
  "$DEST/.claude/rules" \
  "$DEST/.claude/skills/codex-fable" \
  "$DEST/.claude/skills/codex-opus" \
  "$DEST/.claude/skills/kickoff" \
  "$DEST/.claude/skills/ship-pr" \
  "$DEST/.claude/skills/pickgauge-usage" \
  "$DEST/.claude/skills/plan-issue" \
  "$DEST/.claude/skills/x-research" \
  "$DEST/.claude-personal/rules" \
  "$DEST/.claude-personal/skills" \
  "$DEST/.codex/skills/model-orchestration/references" \
  "$DEST/.codex/skills/ship-pr" \
  "$DEST/.grok/skills/model-orchestration" \
  "$DEST/.pi/agent/skills" "$DEST/.omp/agent/skills" \
  "$DEST/.factory/skills" "$DEST/.hermes/skills" "$DEST/.agents/skills" \
  "$DEST/Projects/Personal/.codex" "$DEST/Projects/Personal/.agent-safety/bin" \
  "$DEST/Projects/Personal/.agent-safety/hooks"
ln -s ../.codex/AGENTS.md "$DEST/.grok/AGENTS.md"
printf '%s\n' 'You are Hermes Agent, an intelligent AI assistant created by Nous Research.' >"$DEST/.hermes/SOUL.md"

if ! chezmoi "${MAIN_SRC[@]}" --destination "$DEST" apply "$DEST/.agents/skills" "${TARGETS[@]}"; then
  err 'temp seed apply (canonical skills / adapters) failed'
else
  grep -Fq 'git rev-parse --path-format=absolute --git-common-dir' "$DEST/.zshrc" \
    && pass 'temp zsh profile detects Personal worktrees' \
    || err 'temp zsh profile missing Personal worktree detection'
  grep -Fq 'Projects/Personal/.agent-safety/bin:$PATH' "$DEST/.zshrc" \
    && pass 'temp zsh profile enables Personal GitHub guard' \
    || err 'temp zsh profile missing Personal GitHub guard PATH'
  grep -Fq '"$HOME/.local/bin/claude-default"' "$DEST/.zshrc" \
    && pass 'temp zsh profile routes default Claude through managed launcher' \
    || err 'temp zsh profile missing managed default Claude launcher'
  grep -Fxq main "$DEST/.config/agent-profiles/role" \
    && pass 'temp main role marker applied' \
    || err 'temp main role marker mismatch'
  grep -Fq '## Model orchestration' "$DEST/.claude/CLAUDE.md" \
    && pass 'temp main Claude profile applied' \
    || err 'temp main Claude profile missing full orchestration'
  grep -Fq '## Portable personal profile' "$DEST/.claude-personal/CLAUDE.md" \
    && ! grep -Fq 'model-routing.md' "$DEST/.claude-personal/CLAUDE.md" \
    && pass 'temp portable Claude profile stays lightweight' \
    || err 'temp portable Claude profile scope mismatch'
  for script in \
    "$DEST/.local/bin/claude-profile" \
    "$DEST/.local/bin/claude-default" \
    "$DEST/.local/bin/claude-personal" \
    "$DEST/.local/bin/agent-profile-doctor"; do
    if [[ -x "$script" ]] && sh -n "$script"; then
      pass "temp profile launcher applied: ${script#"$DEST/"}"
    else
      err "temp profile launcher invalid: ${script#"$DEST/"}"
    fi
  done
  if [[ -L "$DEST/Projects/Personal/.codex/AGENTS.md" ]] \
    && [[ "$(readlink "$DEST/Projects/Personal/.codex/AGENTS.md")" == '../../../.codex/AGENTS.md' ]]; then
    pass 'temp Personal Codex AGENTS link applied'
  else
    err 'temp Personal Codex AGENTS link mismatch'
  fi
  if [[ -L "$DEST/Projects/Personal/.codex/skills" ]] \
    && [[ "$(readlink "$DEST/Projects/Personal/.codex/skills")" == '../../../.codex/skills' ]]; then
    pass 'temp Personal Codex skills link applied'
  else
    err 'temp Personal Codex skills link mismatch'
  fi
  for script in \
    "$DEST/Projects/Personal/.agent-safety/bin/gh" \
    "$DEST/Projects/Personal/.agent-safety/bin/gh-credential" \
    "$DEST/Projects/Personal/.agent-safety/verify-personal-github" \
    "$DEST/Projects/Personal/.agent-safety/install-repo-hook" \
    "$DEST/Projects/Personal/.agent-safety/hooks/pre-push"; do
    if [[ -x "$script" ]] && sh -n "$script"; then
      pass "temp Personal safety script applied: ${script#"$DEST/"}"
    else
      err "temp Personal safety script invalid: ${script#"$DEST/"}"
    fi
  done
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
fi

RESTRICTED_TARGETS=(
  "$RESTRICTED_DEST/.config/agent-profiles/role"
  "$RESTRICTED_DEST/.config/agent-profiles/personal-roots"
  "$RESTRICTED_DEST/.local/bin/claude-profile"
  "$RESTRICTED_DEST/.local/bin/claude-default"
  "$RESTRICTED_DEST/.local/bin/claude-personal"
  "$RESTRICTED_DEST/.local/bin/agent-profile-doctor"
  "$RESTRICTED_DEST/.claude/CLAUDE.md"
)
mkdir -p "$RESTRICTED_DEST/.config/agent-profiles" "$RESTRICTED_DEST/.local/bin" "$RESTRICTED_DEST/.claude"
if chezmoi "${RESTRICTED_SRC[@]}" --destination "$RESTRICTED_DEST" apply "${RESTRICTED_TARGETS[@]}"; then
  grep -Fxq restricted "$RESTRICTED_DEST/.config/agent-profiles/role" \
    && grep -Fq '## Restricted profile' "$RESTRICTED_DEST/.claude/CLAUDE.md" \
    && ! grep -Fq 'Pickforge' "$RESTRICTED_DEST/.claude/CLAUDE.md" \
    && [[ ! -e "$RESTRICTED_DEST/.claude/settings.json" ]] \
    && [[ ! -e "$RESTRICTED_DEST/.claude/skills" ]] \
    && pass 'restricted destination applies only neutral default-profile policy' \
    || err 'restricted destination profile scope mismatch'
else
  err 'restricted destination apply failed'
fi
if chezmoi "${RESTRICTED_SRC[@]}" --destination "$RESTRICTED_DEST" \
  source-path "$RESTRICTED_DEST/.claude/settings.json" >/dev/null 2>&1; then
  err 'restricted profile still exposes full default settings as a managed target'
else
  pass 'restricted profile ignores full default settings'
fi

if [[ -d "$DEST/.agents/skills/context7-mcp" ]]; then
  for claude_skills_root in "$DEST/.claude/skills" "$DEST/.claude-personal/skills"; do
    rm -rf "$claude_skills_root/context7-mcp"
    cp -a "$DEST/.agents/skills/context7-mcp" "$claude_skills_root/context7-mcp"
    if dirs_identical "$claude_skills_root/context7-mcp" "$DEST/.agents/skills/context7-mcp"; then
      pass "seeded identical Context7 directory: ${claude_skills_root#"$DEST/"}"
    else
      err "failed to seed Context7 directory: ${claude_skills_root#"$DEST/"}"
    fi
  done
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
  if chezmoi "${MAIN_SRC[@]}" --destination "$DEST" apply "${PORTABLE_TARGETS[@]}"; then
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

TRANSITION_HOME="$TMP/profile-transition-home"
TRANSITION_CONFIG="$TRANSITION_HOME/.config/chezmoi/chezmoi.toml"
TRANSITION_AGE_IDENTITY="$(chezmoi dump-config | jq -r '.age.identity')"
TRANSITION_AGE_RECIPIENT="$(chezmoi dump-config | jq -r '.age.recipient')"
mkdir -p \
  "$TRANSITION_HOME/.config/chezmoi" \
  "$TRANSITION_HOME/.config/agent-profiles" \
  "$TRANSITION_HOME/.claude/rules" \
  "$TRANSITION_HOME/.claude/skills/kickoff"
cat >"$TRANSITION_CONFIG" <<EOF
encryption = "age"
[age]
  identity = "$TRANSITION_AGE_IDENTITY"
  recipient = "$TRANSITION_AGE_RECIPIENT"
[data]
  agentProfile = "restricted"
EOF
printf '%s\n' main >"$TRANSITION_HOME/.config/agent-profiles/role"
chezmoi "${MAIN_SRC[@]}" --destination "$TRANSITION_HOME" \
  cat "$TRANSITION_HOME/.claude/settings.json" >"$TRANSITION_HOME/.claude/settings.json"
cp "$ROOT/dot_claude/private_RTK.md" "$TRANSITION_HOME/.claude/RTK.md"
cp "$ROOT/dot_claude/rules/context7.md" "$TRANSITION_HOME/.claude/rules/context7.md"
chezmoi "${SRC[@]}" decrypt \
  dot_claude/skills/kickoff/encrypted_SKILL.md.age \
  >"$TRANSITION_HOME/.claude/skills/kickoff/SKILL.md"
ln -s ../../.agents/skills/model-runners "$TRANSITION_HOME/.claude/skills/model-runners"

if HOME="$TRANSITION_HOME" CHEZMOI_SOURCE_DIR="$ROOT" \
  bash -c 'source "$1"; remove_main_profile_paths' _ \
  "$ROOT/dot_local/bin/executable_agent-config-sync"; then
  transition_stale=0
  for path in \
    "$TRANSITION_HOME/.claude/settings.json" \
    "$TRANSITION_HOME/.claude/RTK.md" \
    "$TRANSITION_HOME/.claude/rules/context7.md" \
    "$TRANSITION_HOME/.claude/skills/kickoff" \
    "$TRANSITION_HOME/.claude/skills/model-runners"; do
    [[ ! -e "$path" && ! -L "$path" ]] || transition_stale=1
  done
  [[ "$transition_stale" -eq 0 ]] \
    && pass 'main-to-restricted cleanup removes unchanged full-profile state' \
    || err 'main-to-restricted cleanup left full-profile state'
else
  err 'main-to-restricted cleanup failed'
fi

mkdir -p "$TRANSITION_HOME/.claude"
chezmoi "${MAIN_SRC[@]}" --destination "$TRANSITION_HOME" \
  cat "$TRANSITION_HOME/.claude/settings.json" >"$TRANSITION_HOME/.claude/settings.json"
printf '\n' >>"$TRANSITION_HOME/.claude/settings.json"
if HOME="$TRANSITION_HOME" CHEZMOI_SOURCE_DIR="$ROOT" \
  bash -c 'source "$1"; remove_main_profile_paths' _ \
  "$ROOT/dot_local/bin/executable_agent-config-sync" >/dev/null 2>&1; then
  err 'main-to-restricted cleanup removed divergent full-profile state'
elif [[ -f "$TRANSITION_HOME/.claude/settings.json" ]]; then
  pass 'main-to-restricted cleanup preserves divergent full-profile state'
else
  err 'main-to-restricted cleanup lost divergent full-profile state'
fi

mkdir -p "$TRANSITION_HOME/.claude/rules" "$TRANSITION_HOME/.claude/skills/kickoff"
chezmoi "${MAIN_SRC[@]}" --destination "$TRANSITION_HOME" \
  cat "$TRANSITION_HOME/.claude/settings.json" >"$TRANSITION_HOME/.claude/settings.json"
cp "$ROOT/dot_claude/private_RTK.md" "$TRANSITION_HOME/.claude/RTK.md"
cp "$ROOT/dot_claude/rules/context7.md" "$TRANSITION_HOME/.claude/rules/context7.md"
chezmoi "${SRC[@]}" decrypt \
  dot_claude/skills/kickoff/encrypted_SKILL.md.age \
  >"$TRANSITION_HOME/.claude/skills/kickoff/SKILL.md"
printf '\n' >>"$TRANSITION_HOME/.claude/skills/kickoff/SKILL.md"
if HOME="$TRANSITION_HOME" CHEZMOI_SOURCE_DIR="$ROOT" \
  bash -c 'source "$1"; remove_main_profile_paths' _ \
  "$ROOT/dot_local/bin/executable_agent-config-sync" >/dev/null 2>&1; then
  err 'main-to-restricted cleanup accepted late divergent skill'
elif [[ -f "$TRANSITION_HOME/.claude/settings.json" \
  && -f "$TRANSITION_HOME/.claude/RTK.md" \
  && -f "$TRANSITION_HOME/.claude/rules/context7.md" ]]; then
  pass 'main-to-restricted cleanup preflights before deleting state'
else
  err 'main-to-restricted cleanup partially deleted state before failure'
fi

REAPPLY_HOME="$TMP/profile-reapply-home"
mkdir -p \
  "$REAPPLY_HOME/.agents/skills/codex" \
  "$REAPPLY_HOME/.agents/skills/grok" \
  "$REAPPLY_HOME/.config/chezmoi" \
  "$REAPPLY_HOME/.claude/skills" \
  "$REAPPLY_HOME/.claude-personal/skills"
cp "$TRANSITION_CONFIG" "$REAPPLY_HOME/.config/chezmoi/chezmoi.toml"
ln -s ../../.agents/skills/codex "$REAPPLY_HOME/.claude/skills/codex"
ln -s ../../.agents/skills/grok "$REAPPLY_HOME/.claude/skills/grok"
ln -s ../../.agents/skills/codex "$REAPPLY_HOME/.claude-personal/skills/codex"
if HOME="$REAPPLY_HOME" CHEZMOI_SOURCE_DIR="$ROOT" \
  bash -c 'source "$1"; remove_obsolete_portable_paths' _ \
  "$ROOT/dot_local/bin/executable_agent-config-sync"; then
  if [[ -L "$REAPPLY_HOME/.claude/skills/codex" \
    && -L "$REAPPLY_HOME/.claude/skills/grok" \
    && -L "$REAPPLY_HOME/.claude-personal/skills/codex" ]]; then
    pass 'portable skill cleanup preserves canonical links on reapply'
  else
    err 'portable skill cleanup removed canonical links on reapply'
  fi
else
  err 'portable skill cleanup failed on canonical links'
fi

PROFILE_HOME="$TMP/profile-home"
FAKE_CLAUDE="$TMP/fake-claude"
mkdir -p "$PROFILE_HOME/.config/agent-profiles" "$PROFILE_HOME/Projects/Personal/demo" "$TMP/outside"
printf '%s\n' restricted >"$PROFILE_HOME/.config/agent-profiles/role"
printf '%s\n' '~/Projects/Personal' >"$PROFILE_HOME/.config/agent-profiles/personal-roots"
cat >"$FAKE_CLAUDE" <<'EOF'
#!/bin/sh
printf 'config=%s\n' "${CLAUDE_CONFIG_DIR:-default}"
printf 'bedrock=%s\n' "${CLAUDE_CODE_USE_BEDROCK:-unset}"
printf 'aws_profile=%s\n' "${AWS_PROFILE:-unset}"
printf 'mantle=%s\n' "${CLAUDE_CODE_USE_MANTLE:-unset}"
printf 'bedrock_bearer=%s\n' "${AWS_BEARER_TOKEN_BEDROCK:-unset}"
printf 'bedrock_skip_auth=%s\n' "${CLAUDE_CODE_SKIP_BEDROCK_AUTH:-unset}"
printf 'anthropic_aws=%s\n' "${ANTHROPIC_AWS_API_KEY:-unset}"
printf 'foundry_token=%s\n' "${ANTHROPIC_FOUNDRY_AUTH_TOKEN:-unset}"
printf 'vertex_base=%s\n' "${ANTHROPIC_VERTEX_BASE_URL:-unset}"
if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
  printf 'anthropic=set\n'
else
  printf 'anthropic=unset\n'
fi
printf 'codex_home=%s\n' "${CODEX_HOME:-default}"
for argument in "$@"; do
  printf 'arg=%s\n' "$argument"
done
EOF
chmod +x "$FAKE_CLAUDE"

restricted_run="$(
  HOME="$PROFILE_HOME" CLAUDE_REAL_BIN="$FAKE_CLAUDE" \
    CLAUDE_CONFIG_DIR="$PROFILE_HOME/.claude-personal" \
    "$ROOT/dot_local/bin/executable_claude-profile" default --print probe
)"
grep -Fq 'arg=--permission-mode' <<<"$restricted_run" \
  && grep -Fq 'arg=manual' <<<"$restricted_run" \
  && ! grep -Fq 'arg=--dangerously-skip-permissions' <<<"$restricted_run" \
  && grep -Fq "config=$PROFILE_HOME/.claude" <<<"$restricted_run" \
  && pass 'restricted launcher forces manual permissions' \
  || err 'restricted launcher permission enforcement failed'

if HOME="$PROFILE_HOME" CLAUDE_REAL_BIN="$FAKE_CLAUDE" \
  "$ROOT/dot_local/bin/executable_claude-profile" default --dangerously-skip-permissions >/dev/null 2>&1; then
  err 'restricted launcher accepted permission bypass'
else
  pass 'restricted launcher rejects permission bypass'
fi

if (
  cd "$TMP/outside"
  HOME="$PROFILE_HOME" CLAUDE_REAL_BIN="$FAKE_CLAUDE" \
    "$ROOT/dot_local/bin/executable_claude-profile" personal --print probe
) >/dev/null 2>&1; then
  err 'portable launcher accepted a path outside configured personal roots'
else
  pass 'portable launcher rejects paths outside configured personal roots'
fi

portable_run="$(
  cd "$PROFILE_HOME/Projects/Personal/demo"
  HOME="$PROFILE_HOME" CLAUDE_REAL_BIN="$FAKE_CLAUDE" \
    CLAUDE_CODE_USE_BEDROCK=1 CLAUDE_CODE_USE_MANTLE=1 \
    CLAUDE_CODE_SKIP_BEDROCK_AUTH=1 AWS_BEARER_TOKEN_BEDROCK=restricted \
    AWS_PROFILE=restricted ANTHROPIC_AWS_API_KEY=restricted \
    ANTHROPIC_FOUNDRY_AUTH_TOKEN=restricted ANTHROPIC_VERTEX_BASE_URL=restricted \
    ANTHROPIC_API_KEY=restricted OPENAI_API_KEY=restricted \
    "$ROOT/dot_local/bin/executable_claude-profile" personal --print probe
)"
grep -Fq "config=$PROFILE_HOME/.claude-personal" <<<"$portable_run" \
  && grep -Fq "codex_home=$PROFILE_HOME/Projects/Personal/.codex" <<<"$portable_run" \
  && grep -Fq 'bedrock=unset' <<<"$portable_run" \
  && grep -Fq 'mantle=unset' <<<"$portable_run" \
  && grep -Fq 'bedrock_bearer=unset' <<<"$portable_run" \
  && grep -Fq 'bedrock_skip_auth=unset' <<<"$portable_run" \
  && grep -Fq 'anthropic_aws=unset' <<<"$portable_run" \
  && grep -Fq 'foundry_token=unset' <<<"$portable_run" \
  && grep -Fq 'vertex_base=unset' <<<"$portable_run" \
  && grep -Fq 'aws_profile=unset' <<<"$portable_run" \
  && grep -Fq 'anthropic=unset' <<<"$portable_run" \
  && grep -Fq 'arg=--permission-mode' <<<"$portable_run" \
  && grep -Fq 'arg=manual' <<<"$portable_run" \
  && ! grep -Fq 'arg=--dangerously-skip-permissions' <<<"$portable_run" \
  && pass 'portable launcher isolates config, providers, and permissions' \
  || err 'portable launcher isolation failed'
if (
  cd "$PROFILE_HOME/Projects/Personal/demo"
  HOME="$PROFILE_HOME" CLAUDE_REAL_BIN="$FAKE_CLAUDE" \
    "$ROOT/dot_local/bin/executable_claude-profile" personal --dangerously-skip-permissions
) >/dev/null 2>&1; then
  err 'portable launcher accepted permission bypass'
else
  pass 'portable launcher rejects permission bypass'
fi

printf '%s\n' main >"$PROFILE_HOME/.config/agent-profiles/role"
main_run="$(
  HOME="$PROFILE_HOME" CLAUDE_REAL_BIN="$FAKE_CLAUDE" \
    "$ROOT/dot_local/bin/executable_claude-profile" default --print probe
)"
grep -Fq 'arg=--dangerously-skip-permissions' <<<"$main_run" \
  && ! grep -Fq 'arg=manual' <<<"$main_run" \
  && pass 'main launcher retains autonomous permissions' \
  || err 'main launcher permission mode mismatch'

bash -n "$ROOT/scripts/check-agent-config-sync.sh" && pass 'bash -n' || err 'bash -n failed'
if [[ -f "$ROOT/dot_local/bin/executable_agent-config-sync" ]]; then
  bash -n "$ROOT/dot_local/bin/executable_agent-config-sync" && pass 'bash -n agent-config-sync' \
    || err 'bash -n agent-config-sync failed'
  grep -Fq 'bootstrap_real_gh' "$ROOT/dot_local/bin/executable_agent-config-sync" \
    && pass 'agent-config-sync bootstraps Personal real-gh' \
    || err 'agent-config-sync missing Personal real-gh bootstrap'
  grep -Fq 'preflight_unmanaged_targets' "$ROOT/dot_local/bin/executable_agent-config-sync" \
    && pass 'agent-config-sync protects unmanaged first-apply targets' \
    || err 'agent-config-sync missing unmanaged-target preflight'
  grep -Fq 'apply --force --no-tty "${targets[@]}"' "$ROOT/dot_local/bin/executable_agent-config-sync" \
    && pass 'agent-config-sync permits preflighted type migrations' \
    || err 'agent-config-sync missing forced preflighted apply'
fi

echo
[[ "$fail" -eq 0 ]] && { echo "PASSED: agent-config-sync checks"; exit 0; }
echo "FAILED: agent-config-sync checks"; exit 1
