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

MANIFEST="$ROOT/dot_agents/skill-targets.json"
MCP_REGISTRY="$ROOT/dot_agents/mcp-targets.json"
OMP_MCP="$ROOT/dot_omp/agent/mcp.json"

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
  dot_omp/agent/sessions
  dot_omp/agent/terminal-sessions
  dot_omp/agent/agent.db
  dot_omp/agent/history.db
  dot_omp/agent/models.db
  dot_omp/logs
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
  .omp/agent/sessions
  .omp/agent/terminal-sessions
  .omp/agent/*.db
  .omp/logs
  .omp/cache
  .omp/install-id
  .omp/gpu_cache.json
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
    [[ ! -e "$ROOT/$path" ]] || err "runtime state still tracked: $path"
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

  if [[ -e "$ROOT/dot_claude/skills/context7-mcp" ]]; then
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

if [[ "$MODE" == live ]]; then
  if [[ "$STRICT_PREFLIGHT" -eq 1 ]]; then
    echo "== agent-config-sync strict live preflight (read-only) =="
  else
    echo "== agent-config-sync live migration (read-only) =="
  fi
  GROK_LIVE="${HOME}/.grok/AGENTS.md"
  SOUL_LIVE="${HOME}/.hermes/SOUL.md"
  NOUS_DEFAULT='You are Hermes Agent, an intelligent AI assistant created by Nous Research.'

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

  if [[ ! -f "$SOUL_LIVE" ]]; then
    err "live Hermes SOUL missing: $SOUL_LIVE"
  elif grep -q '^# Hermes' "$SOUL_LIVE" && grep -q '/home/dev/AgentMemory' "$SOUL_LIVE"; then
    pass 'live Hermes SOUL already rendered (managed identity)'
  elif grep -Fq "$NOUS_DEFAULT" "$SOUL_LIVE" && ! grep -q '## How to work' "$SOUL_LIVE"; then
    pass 'live Hermes SOUL is known Nous default one-line identity'
  else
    err 'live Hermes SOUL is neither Nous default nor rendered managed SOUL'
  fi

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
  'dot_claude/CLAUDE.md.tmpl|# Global Claude Rules|# Personal Codex Notes'
  'dot_codex/AGENTS.md.tmpl|# Personal Codex Notes|# Global Claude Rules'
  'dot_grok/AGENTS.md.tmpl|# Personal Grok Notes|# Personal Codex Notes'
  'dot_pi/agent/AGENTS.md.tmpl|# Personal Pi Notes|# Personal Codex Notes'
  'dot_omp/agent/AGENTS.md.tmpl|# Personal OMP Notes|# Personal Codex Notes'
  'private_dot_factory/AGENTS.md.tmpl|# Personal Droid Notes|# Personal Codex Notes'
)
SOUL=private_dot_hermes/SOUL.md.tmpl
MARKERS=(
  '## How to work' '## Dictated prompts (PickScribe)' '## Tools' '## Git'
  '### Pull requests' '## Worktrees' '## Flutter' '## Writing Markdown'
  '## Before finishing' '## Shared Agent Memory' '## CodeGraph' '## Context7 usage'
  '## Updating these rules' '## UI and UX' 'design-director'
  '/home/dev/AgentMemory' 'when available'
)

for f in "${SHARED[@]}"; do need "$f"; done
[[ -f .chezmoitemplates/agents-shared.md ]] && \
  grep -q 'agents-shared-before-worktrees.md' .chezmoitemplates/agents-shared.md && \
  grep -q 'agents-shared-after-git.md' .chezmoitemplates/agents-shared.md && \
  pass 'agents-shared.md composes parts' || err 'agents-shared.md must include before/after parts'

shared_blob="$(cat .chezmoitemplates/agents-shared-before-worktrees.md .chezmoitemplates/agents-shared-after-git.md)"
for m in "${MARKERS[@]}"; do
  grep -Fq "$m" <<<"$shared_blob" && pass "shared has: $m" || err "shared missing: $m"
done

need "$SOUL"
grep -q '/home/dev/AgentMemory' "$SOUL" || err 'Hermes SOUL missing AgentMemory'
grep -qi 'public' "$SOUL" || err 'Hermes SOUL missing public-action boundary'
grep -qi 'memory' "$SOUL" || err 'Hermes SOUL missing memory boundary'
grep -qE '## How to work|## Worktrees' "$SOUL" && err 'Hermes SOUL must not dump full coding policy' || pass 'Hermes SOUL identity-oriented'

[[ -L dot_grok/AGENTS.md.tmpl || -L dot_grok/AGENTS.md ]] && err 'Grok AGENTS must not be a symlink'
need dot_grok/AGENTS.md.tmpl
if [[ -f dot_grok/AGENTS.md.tmpl ]]; then
  grep -qE 'codex/AGENTS|\.\./\.codex|Personal Codex Notes' dot_grok/AGENTS.md.tmpl \
    && err 'Grok adapter links to or reuses Codex' || pass 'Grok adapter not Codex-linked'
  grep -q 'gpt-5.6-luna' dot_grok/AGENTS.md.tmpl \
    && err 'Grok adapter still embeds full model table' || pass 'Grok has no full model table'
  grep -q 'model-orchestration' dot_grok/AGENTS.md.tmpl \
    && pass 'Grok references model-orchestration skill' || err 'Grok missing model-orchestration reference'
fi

check_manifest_and_sources
check_mcp_registry_and_config
check_runtime_exclusions

TMP="$(mktemp -d "${TMPDIR:-/tmp}/agent-config-sync.XXXXXX")"
DEST="$(mktemp -d "${TMPDIR:-/tmp}/chezmoi-dest.XXXXXX")"
trap 'rm -rf "$TMP" "$DEST"' EXIT
render() { chezmoi "${SRC[@]}" execute-template --file "$1" >"$2"; }

for entry in "${HARNESS[@]}"; do
  IFS='|' read -r path want forbid <<<"$entry"
  if [[ ! -f "$path" ]]; then err "missing: $path"; continue; fi
  grep -Eq 'template "(agents-shared\.md|agents-shared-before-worktrees\.md)"' "$path" \
    || err "missing shared include: $path"
  for bad in '## How to work' '## Dictated prompts (PickScribe)' '## Shared Agent Memory'; do
    grep -Fq "$bad" "$path" && err "duplicate shared block in $path: $bad"
  done
  out="$TMP/$(echo "$path" | tr '/' '_')"
  if ! render "$path" "$out"; then err "render failed: $path"; continue; fi
  pass "rendered $path"
  grep -Fq "$want" "$out" || err "missing heading in $path: $want"
  grep -Fq "$forbid" "$out" && err "forbidden heading in $path: $forbid"
  [[ "$(grep -c 'I like short, practical work' "$out" || true)" -eq 1 ]] || err "shared intro count != 1 in $path"
  grep -q PickScribe "$out" || err "missing PickScribe in $path"
  grep -q '/home/dev/AgentMemory' "$out" || err "missing AgentMemory in $path"
done

render "$SOUL" "$TMP/SOUL.md" && pass 'rendered Hermes SOUL' || err 'Hermes SOUL render failed'

TARGETS=(
  "$DEST/.claude/CLAUDE.md" "$DEST/.codex/AGENTS.md" "$DEST/.grok/AGENTS.md"
  "$DEST/.pi/agent/AGENTS.md" "$DEST/.omp/agent/AGENTS.md" "$DEST/.omp/agent/mcp.json"
  "$DEST/.factory/AGENTS.md" "$DEST/.hermes/SOUL.md"
)
EXPECTED=(
  dot_claude/CLAUDE.md.tmpl dot_codex/AGENTS.md.tmpl dot_grok/AGENTS.md.tmpl
  dot_pi/agent/AGENTS.md.tmpl dot_omp/agent/AGENTS.md.tmpl dot_omp/agent/mcp.json
  private_dot_factory/AGENTS.md.tmpl private_dot_hermes/SOUL.md.tmpl
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

mkdir -p "$DEST/.grok" "$DEST/.hermes" \
  "$DEST/.claude/skills" "$DEST/.pi/agent/skills" "$DEST/.omp/agent/skills" \
  "$DEST/.factory/skills" "$DEST/.grok/skills" "$DEST/.hermes/skills" "$DEST/.agents/skills"
ln -s ../.codex/AGENTS.md "$DEST/.grok/AGENTS.md"
printf '%s\n' 'You are Hermes Agent, an intelligent AI assistant created by Nous Research.' >"$DEST/.hermes/SOUL.md"

if ! chezmoi "${SRC[@]}" --destination "$DEST" apply "$DEST/.agents/skills" \
  "$DEST/.omp/agent/mcp.json" "$DEST/.grok/AGENTS.md" "$DEST/.hermes/SOUL.md"; then
  err 'temp seed apply (canonical skills / adapters) failed'
else
  [[ ! -L "$DEST/.grok/AGENTS.md" ]] && grep -q '^# Personal Grok Notes' "$DEST/.grok/AGENTS.md" \
    && pass 'temp migration replaces Grok symlink safely' || err 'temp Grok symlink migration failed'
  grep -q '^# Hermes' "$DEST/.hermes/SOUL.md" && grep -q '/home/dev/AgentMemory' "$DEST/.hermes/SOUL.md" \
    && pass 'temp migration replaces default Hermes SOUL safely' || err 'temp Hermes SOUL migration failed'
  cmp -s "$DEST/.omp/agent/mcp.json" "$OMP_MCP" \
    && pass 'temp OMP MCP config applied' || err 'temp OMP MCP config apply mismatch'
fi

if [[ -d "$DEST/.agents/skills/context7-mcp" ]]; then
  rm -rf "$DEST/.claude/skills/context7-mcp"
  cp -a "$DEST/.agents/skills/context7-mcp" "$DEST/.claude/skills/context7-mcp"
  if dirs_identical "$DEST/.claude/skills/context7-mcp" "$DEST/.agents/skills/context7-mcp"; then
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
