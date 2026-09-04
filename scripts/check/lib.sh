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

managed_directory_unchanged() {
  local live="$1" file found=0
  [[ -d "$live" && ! -L "$live" ]] || return 1
  if [[ -n "$(find "$live" -mindepth 1 ! -type d ! -type f -print -quit)" ]]; then
    return 1
  fi
  while IFS= read -r -d '' file; do
    found=1
    managed_regular_file_unchanged "$file" || return 1
  done < <(find "$live" -type f -print0)
  [[ "$found" -eq 1 ]]
}

MANIFEST="$ROOT/dot_agents/skill-targets.json"
SKILL_LOCK="$ROOT/dot_agents/dot_skill-lock.json"
MCP_REGISTRY="$ROOT/dot_agents/mcp-targets.json"
OMP_MCP_SOURCE="$ROOT/dot_omp/agent/mcp.json.tmpl"
OMP_MCP="$(mktemp "${TMPDIR:-/tmp}/agent-config-sync-omp-mcp.XXXXXX")"
trap 'rm -f "$OMP_MCP"' EXIT
chezmoi "${SRC[@]}" execute-template --file "$OMP_MCP_SOURCE" >"$OMP_MCP"
PICKFORGE_LANES_WRAPPER="$ROOT/dot_local/bin/executable_pickforge-lanes-mcp"
PICKFORGE_LANES_CONFIGURE="$ROOT/run_onchange_after_configure_pickforge_lanes_mcp.sh"
CLAUDE_SETTINGS="$ROOT/dot_claude/settings.json.tmpl"

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
  private_dot_factory
  dot_config/opencode
  .chezmoitemplates/claude-restricted.md
  .chezmoitemplates/claude-personal-lite.md
  dot_agents/skills/model-runners
  dot_agents/skills/multi-model-lanes
  dot_agents/skills/context7-mcp
  dot_agents/skills/find-skills
  dot_agents/skills/audit-report
  dot_codex/skills/ship-pr
  dot_claude/skills/kickoff
  dot_claude/skills/pickgauge-usage
  dot_claude/hooks/executable_kickoff-delegation-gate.sh.tmpl
  .chezmoitemplates/kickoff-delegation-gate.sh
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
  find-skills
)

RETIRED_TARGET_PATHS=(
  .claude-personal
  .config/agent-profiles
  .config/rtk
  .local/bin/agent-profile-doctor
  .local/bin/claude-default
  .local/bin/claude-personal
  .local/bin/claude-profile
  .factory
  .claude/RTK.md
  Projects/Personal/.codex
  Projects/Personal/.agent-safety
  .agents/skills/superpowers
  .config/superpowers
  .codex/superpowers
  .codex/skills/ship-pr
  .agents/skills/caveman
  .agents/skills/caveman-commit
  .agents/skills/caveman-compress
  .agents/skills/caveman-help
  .agents/skills/caveman-review
  .agents/skills/caveman-stats
  .agents/skills/cavecrew
  .agents/skills/compress
  .agents/skills/model-runners
  .agents/skills/multi-model-lanes
  .agents/skills/context7-mcp
  .agents/skills/find-skills
  .agents/skills/audit-report
  .claude/skills/model-runners
  .claude/skills/multi-model-lanes
  .claude/skills/context7-mcp
  .claude/skills/find-skills
  .claude/skills/audit-report
  .claude/skills/kickoff
  .claude/skills/pickgauge-usage
  .claude/hooks/kickoff-delegation-gate.sh
  .pi/agent/skills/model-runners
  .pi/agent/skills/multi-model-lanes
  .pi/agent/skills/context7-mcp
  .pi/agent/skills/find-skills
  .pi/agent/skills/audit-report
  .omp/agent/skills/model-runners
  .omp/agent/skills/context7-mcp
  .omp/agent/skills/find-skills
  .omp/agent/skills/audit-report
  .grok/skills/model-runners
  .grok/skills/find-skills
  .hermes/skills/model-runners
  .hermes/skills/diagnosing-bugs
  .agents/skills/codebase-design
  .claude/skills/codebase-design
  .grok/skills/codebase-design
  .pi/agent/skills/codebase-design
  .omp/agent/skills/codebase-design
  .agents/skills/design-director
  .claude/skills/design-director
  .grok/skills/design-director
  .pi/agent/skills/design-director
  .omp/agent/skills/design-director
  .agents/skills/diagnosing-bugs
  .claude/skills/diagnosing-bugs
  .grok/skills/diagnosing-bugs
  .pi/agent/skills/diagnosing-bugs
  .omp/agent/skills/diagnosing-bugs
  .agents/skills/flutter-bloc
  .claude/skills/flutter-bloc
  .grok/skills/flutter-bloc
  .pi/agent/skills/flutter-bloc
  .omp/agent/skills/flutter-bloc
  .agents/skills/flutter-widget
  .claude/skills/flutter-widget
  .grok/skills/flutter-widget
  .pi/agent/skills/flutter-widget
  .omp/agent/skills/flutter-widget
  .agents/skills/gate-installer
  .claude/skills/gate-installer
  .grok/skills/gate-installer
  .pi/agent/skills/gate-installer
  .omp/agent/skills/gate-installer
  .agents/skills/improve
  .claude/skills/improve
  .grok/skills/improve
  .pi/agent/skills/improve
  .omp/agent/skills/improve
  .agents/skills/local-review
  .claude/skills/local-review
  .grok/skills/local-review
  .pi/agent/skills/local-review
  .omp/agent/skills/local-review
  .agents/skills/model-orchestration
  .claude/skills/model-orchestration
  .grok/skills/model-orchestration
  .pi/agent/skills/model-orchestration
  .omp/agent/skills/model-orchestration
  .agents/skills/plan-issue
  .claude/skills/plan-issue
  .grok/skills/plan-issue
  .pi/agent/skills/plan-issue
  .omp/agent/skills/plan-issue
  .agents/skills/ship-pr
  .claude/skills/ship-pr
  .grok/skills/ship-pr
  .pi/agent/skills/ship-pr
  .omp/agent/skills/ship-pr
  .agents/skills/stripe-best-practices
  .claude/skills/stripe-best-practices
  .grok/skills/stripe-best-practices
  .pi/agent/skills/stripe-best-practices
  .omp/agent/skills/stripe-best-practices
  .agents/skills/stripe-docs
  .claude/skills/stripe-docs
  .grok/skills/stripe-docs
  .pi/agent/skills/stripe-docs
  .omp/agent/skills/stripe-docs
  .agents/skills/upgrade-stripe
  .claude/skills/upgrade-stripe
  .grok/skills/upgrade-stripe
  .pi/agent/skills/upgrade-stripe
  .omp/agent/skills/upgrade-stripe
  .claude/rules
  .claude/hooks/decision-audit-gate.sh
  .claude/hooks/delegation-gate.sh
  .claude/hooks/orchestration-reminder.sh
  .pi/agent/extensions/decision-audit-gate.ts
  .pi/agent/extensions/delegation-gate.ts
  .omp/agent/extensions/decision-audit-gate.ts
)

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
