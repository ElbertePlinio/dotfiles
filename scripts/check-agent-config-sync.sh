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

pass() { printf 'OK  %s\n' "$*"; }
err()  { printf 'ERR %s\n' "$*" >&2; fail=1; }
need() { [[ -f "$1" ]] || err "missing: $1"; }

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
validate_omp_agent_override() {
  local role="$1" path="$2"

  if [[ ! -f "$path" ]]; then
    err "OMP ${role} override missing: $path"
    return
  fi

  if grep -Fq '  - openai-codex/gpt-5.6-terra' "$path"; then
    pass "OMP ${role} override uses GPT-5.6 Terra"
  else
    err "OMP ${role} override must use GPT-5.6 Terra"
  fi

  if grep -Eq '^[[:space:]]*thinkingLevel:[[:space:]]*medium[[:space:]]*$' "$path"; then
    pass "OMP ${role} override uses medium thinking"
  else
    err "OMP ${role} override must set thinkingLevel: medium"
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

    err "live OMP ${role} override differs from canonical source"
  done
}


MANIFEST="$ROOT/dot_agents/skill-targets.json"
MCP_REGISTRY="$ROOT/dot_agents/mcp-targets.json"
OMP_MCP="$ROOT/dot_omp/agent/mcp.json"
OMP_AGENT_OVERRIDES_DIR="$ROOT/dot_omp/agent/agents"
OMP_TASK_OVERRIDE="$OMP_AGENT_OVERRIDES_DIR/task.md"
OMP_REVIEWER_OVERRIDE="$OMP_AGENT_OVERRIDES_DIR/reviewer.md"

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

check_runtime_exclusions() {
  local path
  for path in "${RUNTIME_SOURCE_PATHS[@]}"; do
    compgen -G "$ROOT/$path" >/dev/null && err "runtime state still tracked: $path"
  done
  for path in "${RUNTIME_IGNORE_PATHS[@]}"; do
    grep -Fxq "$path" "$ROOT/.chezmoiignore" || err "runtime ignore missing: $path"
  done
  [[ "$fail" -eq 0 ]] && pass 'runtime state excluded from chezmoi source'
}

check_manifest_and_sources() {
  need "$MANIFEST"
  if ! jq -e . "$MANIFEST" >/dev/null 2>&1; then
    err "manifest is not valid JSON: $MANIFEST"
    return
  fi
  pass "manifest JSON valid"

  local skill harness src_root rel_prefix expected link_src
  local -a skills

  mapfile -t skills < <(jq -r '.skills | keys[]' "$MANIFEST")
  [[ "${#skills[@]}" -gt 0 ]] || err 'manifest has no skills'

  for skill in "${skills[@]}"; do
    local age="$ROOT/dot_agents/skills/${skill}/encrypted_SKILL.md.age"
    if [[ ! -f "$age" ]]; then
      err "canonical skill source missing: $age"
      continue
    fi
    pass "canonical source exists: $skill"
    local head name
    head="$(set +o pipefail; chezmoi "${SRC[@]}" decrypt "$age" 2>/dev/null | head -n 20)"
    if [[ -z "$head" ]]; then
      err "decrypt failed: $age"
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

  if [[ -e "$ROOT/dot_claude-personal/skills/context7-mcp" ]]; then
    err 'duplicate Claude context7 source still present (expected symlink only)'
  else
    pass 'no duplicate Claude context7 source directory'
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
      | $path] == [["mcpServers", "sentry", "env", "SENTRY_ACCESS_TOKEN"]])
    and .mcpServers.sentry.env.SENTRY_ACCESS_TOKEN == "!cat ~/.pickforge-keys/sentry-token"
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
      err "canonical skill missing for comparison: $canon"
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
    "${HOME}/.claude-personal/skills/codex-fable/SKILL.md"
    "${HOME}/.claude-personal/skills/codex-opus/SKILL.md"
    "${HOME}/.claude-personal/skills/kickoff/SKILL.md"
    "${HOME}/.codex/skills/model-orchestration/SKILL.md"
    "${HOME}/.codex/skills/model-orchestration/references/model-routing.md"
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
  else
    err 'live OMP MCP config differs from canonical source; refusing an implicit overwrite'
  fi
  check_live_omp_agent_overrides
  check_live_native_routing_files


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
  'dot_claude-personal/CLAUDE.md.tmpl|# Global Claude Rules|# Personal Codex Notes'
  'dot_codex/AGENTS.md.tmpl|# Personal Codex Notes|# Global Claude Rules'
  'dot_grok/AGENTS.md.tmpl|# Personal Grok Notes|# Personal Codex Notes'
  'dot_pi/agent/AGENTS.md.tmpl|# Personal Pi Notes|# Personal Codex Notes'
  'dot_omp/agent/AGENTS.md.tmpl|# Personal OMP Notes|# Personal Codex Notes'
  'private_dot_factory/AGENTS.md.tmpl|# Personal Droid Notes|# Personal Codex Notes'
)
SOUL=private_dot_hermes/SOUL.md.tmpl
OPENCODE=dot_config/opencode/AGENTS.md
SHARED_MAX_BYTES=12500
REQUIRED_SHARED_INVARIANTS=(
  'I like short, practical work. Read the repo, make the smallest clean change, and show proof before calling something done.'
  '- Be direct: no filler or ceremony. Fix root causes, not symptoms.'
  '- No hacks, monkey patches, fake fixes, temporary workarounds, or unrelated refactors.'
  'Dictation can corrupt names, model IDs, and technical terms. Confirm suspicious or contradictory wording instead of following it literally.'
  '- Never expose, print, commit, or send secrets or private production data.'
  '- Destructive filesystem, Git, account, or external-service actions require explicit confirmation.'
  '- Public actions (posts, replies, likes, follows, DMs, publishing) are drafts only; the user performs them.'
  '- Never use Anthropic Haiku, directly, indirectly, or as a fallback.'
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
  '- Use Context7 when library/API details matter and it is available.'
  '- For work that creates or materially changes user-facing UI or UX, use the `design-director` skill before implementation.'
  '- For "ship it", "open a PR", "usual PR flow", or requests to review and merge a branch, use `$ship-pr` when available.'
)

ADAPTER_BUDGETS=(
  'dot_claude-personal/CLAUDE.md.tmpl|3000'
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
  "$HOME/.claude-personal/skills/codex-fable/SKILL.md"
  "$HOME/.claude-personal/skills/codex-opus/SKILL.md"
  "$HOME/.claude-personal/skills/kickoff/SKILL.md"
  "$HOME/.codex/skills/model-orchestration/SKILL.md"
  "$HOME/.codex/skills/model-orchestration/references/model-routing.md"
)

TMP="$(mktemp -d "${TMPDIR:-/tmp}/agent-config-sync.XXXXXX")"
DEST="$(mktemp -d "${TMPDIR:-/tmp}/chezmoi-dest.XXXXXX")"
trap 'rm -rf "$TMP" "$DEST"' EXIT
render() { chezmoi "${SRC[@]}" execute-template --file "$1" >"$2"; }

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
fi

if grep -Fq 'CODING_AGENT_RULES.md' "$TMP/agents-shared.md"; then
  err 'shared global harness loader must not auto-load CODING_AGENT_RULES'
else
  pass 'shared global harness loader excludes CODING_AGENT_RULES'
fi

need "$OPENCODE"
for invariant in CORE_PROFILE.md WRITING_STYLE.md BOUNDARIES.md WORK_AND_PROJECTS.md 'projects/*.md'; do
  grep -Fq "$invariant" "$OPENCODE" \
    && pass "OpenCode memory invariant: $invariant" \
    || err "OpenCode memory invariant missing: $invariant"
done
grep -Fq 'CODING_AGENT_RULES.md' "$OPENCODE" \
  && err 'OpenCode global harness loader must not auto-load CODING_AGENT_RULES' \
  || pass 'OpenCode global harness loader excludes CODING_AGENT_RULES'


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

for path in dot_claude-personal/CLAUDE.md.tmpl dot_codex/AGENTS.md.tmpl \
  dot_grok/AGENTS.md.tmpl private_dot_factory/AGENTS.md.tmpl; do
  grep -qiE '^\|.*cost.*intelligence.*taste.*vision.*\|$' "$path" \
    && err "adapter embeds a full model scoring table: $path" \
    || pass "adapter has no full model scoring table: $path"
done

ADAPTER_OWNER_POINTERS=(
  'dot_claude-personal/CLAUDE.md.tmpl|model-routing.md|Claude'
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
    jq -e 'any(.. | strings; contains("pi-subagents"))' >/dev/null <<<"$pi_settings" \
      && pass 'Pi runtime enables native subagents' \
      || err 'Pi runtime missing native subagents'
    jq -e 'any(.. | strings; ascii_downcase | contains("haiku"))' >/dev/null <<<"$pi_settings" \
      && err 'Pi settings contain a forbidden Haiku selector' \
      || pass 'Pi settings contain no Haiku selector'
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

check_manifest_and_sources
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

render "$SOUL" "$TMP/SOUL.md" && pass 'rendered Hermes SOUL' || err 'Hermes SOUL render failed'

TARGETS=(
  "$DEST/.claude-personal/CLAUDE.md" "$DEST/.codex/AGENTS.md" "$DEST/.grok/AGENTS.md"
  "$DEST/.pi/agent/AGENTS.md" "$DEST/.omp/agent/AGENTS.md"
  "$DEST/.omp/agent/config.yml" "$DEST/.omp/agent/mcp.json"
  "$DEST/.omp/agent/agents"
  "$DEST/.factory/AGENTS.md" "$DEST/.config/opencode/AGENTS.md" "$DEST/.hermes/SOUL.md"
)
EXPECTED=(
  dot_claude-personal/CLAUDE.md.tmpl dot_codex/AGENTS.md.tmpl dot_grok/AGENTS.md.tmpl
  dot_pi/agent/AGENTS.md.tmpl dot_omp/agent/AGENTS.md.tmpl
  dot_omp/agent/agents
  dot_omp/agent/config.yml dot_omp/agent/mcp.json
  private_dot_factory/AGENTS.md.tmpl dot_config/opencode/AGENTS.md private_dot_hermes/SOUL.md.tmpl
)
if chezmoi "${SRC[@]}" --destination "$DEST" source-path "${TARGETS[@]}" >"$TMP/sp.txt" 2>"$TMP/sp.err"; then
  for e in "${EXPECTED[@]}"; do
    grep -Fq "$e" "$TMP/sp.txt" && pass "source-path $e" || err "source-path missing $e"
  done
else
  err "source-path failed: $(tr '\n' ' ' <"$TMP/sp.err")"
fi
chezmoi "${SRC[@]}" --destination "$DEST" --dry-run status >/dev/null 2>"$TMP/st.err" \
  && pass 'dry-run status (temp dest)' || err "dry-run status failed: $(tr '\n' ' ' <"$TMP/st.err")"

mkdir -p "$DEST/.grok" "$DEST/.hermes" "$DEST/.config/opencode" \
  "$DEST/.claude-personal/skills" "$DEST/.pi/agent/skills" "$DEST/.omp/agent/skills" \
  "$DEST/.factory/skills" "$DEST/.grok/skills" "$DEST/.hermes/skills" "$DEST/.agents/skills"
ln -s ../.codex/AGENTS.md "$DEST/.grok/AGENTS.md"
printf '%s\n' 'You are Hermes Agent, an intelligent AI assistant created by Nous Research.' >"$DEST/.hermes/SOUL.md"

if ! chezmoi "${SRC[@]}" --destination "$DEST" apply "$DEST/.agents/skills" \
  "$DEST/.omp/agent/AGENTS.md" "$DEST/.omp/agent/config.yml" "$DEST/.omp/agent/mcp.json" \
  "$DEST/.omp/agent/agents" "$DEST/.config/opencode/AGENTS.md" "$DEST/.grok/AGENTS.md" \
  "$DEST/.hermes/SOUL.md"; then
  err 'temp seed apply (canonical skills / adapters) failed'
else
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

if [[ -d "$DEST/.agents/skills/context7-mcp" ]]; then
  rm -rf "$DEST/.claude-personal/skills/context7-mcp"
  cp -a "$DEST/.agents/skills/context7-mcp" "$DEST/.claude-personal/skills/context7-mcp"
  if dirs_identical "$DEST/.claude-personal/skills/context7-mcp" "$DEST/.agents/skills/context7-mcp"; then
    pass 'seeded Claude context7 as identical regular directory'
  else
    err 'failed to seed identical Claude context7 directory'
  fi
else
  err 'canonical context7-mcp missing after seed apply'
fi

mapfile -t PORTABLE_TARGETS < <(jq -r --arg dest "$DEST" '
  . as $root
  | .skills | to_entries[]
  | .key as $skill
  | .value[] as $harness
  | $root.harnesses[$harness] as $h
  | select($h.discovery == "symlink")
  | ($h.skills_root | sub("^~"; $dest)) + "/" + $skill
' "$MANIFEST")

if ((${#PORTABLE_TARGETS[@]})); then
  if chezmoi "${SRC[@]}" --destination "$DEST" apply "${PORTABLE_TARGETS[@]}"; then
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

bash -n "$ROOT/scripts/check-agent-config-sync.sh" && pass 'bash -n' || err 'bash -n failed'
if [[ -f "$ROOT/dot_local/bin/executable_agent-config-sync" ]]; then
  bash -n "$ROOT/dot_local/bin/executable_agent-config-sync" && pass 'bash -n agent-config-sync' \
    || err 'bash -n agent-config-sync failed'
fi

echo
[[ "$fail" -eq 0 ]] && { echo "PASSED: agent-config-sync checks"; exit 0; }
echo "FAILED: agent-config-sync checks"; exit 1
