pass() { printf 'OK  %s\n' "$*"; }
err()  { printf 'ERR %s\n' "$*" >&2; fail=1; }
need() { [[ -f "$1" ]] || err "missing: $1"; }

# macOS before 14 has shasum but no sha256sum.
command -v sha256sum >/dev/null 2>&1 || sha256sum() { shasum -a 256 "$@"; }

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

# The skill links are the registry; the manifest is rendered from them.
MANIFEST="$(mktemp "${TMPDIR:-/tmp}/agent-config-sync-manifest.XXXXXX")"
chezmoi "${SRC[@]}" execute-template --file "$ROOT/dot_agents/skill-targets.json.tmpl" >"$MANIFEST"
MCP_REGISTRY="$ROOT/dot_agents/mcp-targets.json"
OMP_MCP_SOURCE="$ROOT/dot_omp/agent/mcp.json.tmpl"
OMP_MCP="$(mktemp "${TMPDIR:-/tmp}/agent-config-sync-omp-mcp.XXXXXX")"
trap 'rm -f "$OMP_MCP" "$MANIFEST"' EXIT
chezmoi "${SRC[@]}" execute-template --file "$OMP_MCP_SOURCE" >"$OMP_MCP"
PICKFORGE_LANES_WRAPPER="$ROOT/dot_local/bin/executable_pickforge-lanes-mcp"
PICKFORGE_LANES_REMOVE="$ROOT/run_onchange_after_remove_claude_pickforge_lanes_mcp.sh"
CLAUDE_SETTINGS="$ROOT/dot_claude/settings.json.tmpl"

RUNTIME_SOURCE_PATHS=(
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
)

RUNTIME_IGNORE_PATHS=(
  .pi/agent/auth.json
  .pi/agent/mcp-oauth
  .context7/credentials.json
  .agents/.skill-lock.json
  .pi/agent/npm
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
)
