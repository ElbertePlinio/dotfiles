echo "== agent-config-sync checks =="
echo "source: $ROOT"

SHARED=(
  .chezmoitemplates/agents-shared.md
  .chezmoitemplates/agents-shared-before-worktrees.md
  .chezmoitemplates/agents-shared-after-git.md
  .chezmoitemplates/agents-shared-destructive-actions.md
  .chezmoitemplates/agents-shared-public-actions.md
  .chezmoitemplates/agents-shared-memory.md
)
HARNESS=(
  'dot_codex/AGENTS.md.tmpl|# Personal Codex Notes|# Global Claude Rules'
  'dot_grok/AGENTS.md.tmpl|# Personal Grok Notes|# Personal Codex Notes'
  'dot_pi/agent/AGENTS.md.tmpl|# Personal Pi Notes|# Personal Codex Notes'
  'dot_omp/agent/AGENTS.md.tmpl|# Personal OMP Notes|# Personal Codex Notes'
)
SOUL=private_dot_hermes/SOUL.md.tmpl
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
  '- Never use Anthropic Haiku or GPT-5.6 Luna/Terra; Sol is the only GPT-5.6 lane'
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
  "$HOME/AgentMemory"
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
  "$HOME/.grok/skills/model-orchestration/references/model-routing.md"
)

TMP="$(mktemp -d "${TMPDIR:-/tmp}/agent-config-sync.XXXXXX")"
DEST="$(mktemp -d "${TMPDIR:-/tmp}/chezmoi-dest.XXXXXX")"
trap 'rm -rf "$TMP" "$DEST"; rm -f "$OMP_MCP"' EXIT
render() { chezmoi "${SRC[@]}" execute-template --file "$1" >"$2"; }

check_os_gating() {
  local darwin_ignore="$TMP/chezmoiignore-darwin" linux_ignore="$TMP/chezmoiignore-linux"
  local target
  if chezmoi "${SRC[@]}" --override-data '{"chezmoi":{"os":"darwin"}}' \
      execute-template --file .chezmoiignore >"$darwin_ignore" \
    && chezmoi "${SRC[@]}" --override-data '{"chezmoi":{"os":"linux"}}' \
      execute-template --file .chezmoiignore >"$linux_ignore"; then
    for target in .p10k.zsh .config/kdeglobals '.config/environment.d/**' '.config/fish/**'; do
      grep -Fxq "$target" "$darwin_ignore" \
        || err "Darwin ignore render missing Linux target: $target"
      if grep -Fxq "$target" "$linux_ignore"; then
        err "Linux ignore render excludes Linux target: $target"
      fi
    done
    pass 'OS-simulated ignore renders gate Linux desktop targets on Darwin only'
  else
    err 'OS-simulated .chezmoiignore render failed'
  fi

  local darwin_managed="$TMP/managed-darwin" linux_managed="$TMP/managed-linux"
  if chezmoi "${SRC[@]}" --override-data '{"chezmoi":{"os":"darwin"}}' \
      managed --path-style=relative >"$darwin_managed" \
    && chezmoi "${SRC[@]}" --override-data '{"chezmoi":{"os":"linux"}}' \
      managed --path-style=relative >"$linux_managed"; then
    if ! grep -Fxq '.config/environment.d/50-sudo-askpass.conf' "$darwin_managed" \
      && grep -Fxq '.config/environment.d/50-sudo-askpass.conf' "$linux_managed" \
      && ! grep -Fxq '.config/kdeglobals' "$darwin_managed" \
      && grep -Fxq '.config/kdeglobals' "$linux_managed"; then
      pass 'OS-simulated managed sets exclude Linux-gated targets on Darwin only'
    else
      err 'OS-simulated managed sets do not reflect dual-OS gating'
    fi
  else
    err 'OS-simulated managed enumeration failed'
  fi
}

check_portable_home_literals() {
  local needle='/home/'dev path unexpected=0
  while IFS= read -r path; do
    case "$path" in
      .chezmoitemplates/zshrc-linux|dot_config/QtProject.conf|\
      dot_config/plasma-org.kde.plasma.desktop-appletsrc|\
      dot_config/private_katerc|dot_config/private_spectaclerc) ;;
      *) err "literal Linux home remains outside an OS-gated source: $path"; unexpected=1 ;;
    esac
  done < <(rg -l --hidden --glob '!.git/**' --glob '!*.age' "$needle" . | sed 's#^\./##')
  [[ "$unexpected" -eq 0 ]] && pass 'literal Linux homes remain only in OS-gated sources'
}

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
check_os_gating
check_portable_home_literals

for f in "${SHARED[@]}"; do need "$f"; done
[[ -f .chezmoitemplates/agents-shared.md ]] && \
  grep -q 'agents-shared-before-worktrees.md' .chezmoitemplates/agents-shared.md && \
  grep -q 'agents-shared-after-git.md' .chezmoitemplates/agents-shared.md && \
  pass 'agents-shared.md composes parts' || err 'agents-shared.md must include before/after parts'

shared_source_bytes=$((
  $(wc -c <.chezmoitemplates/agents-shared-before-worktrees.md) +
  $(wc -c <.chezmoitemplates/agents-shared-after-git.md) +
  $(wc -c <.chezmoitemplates/agents-shared-destructive-actions.md) +
  $(wc -c <.chezmoitemplates/agents-shared-public-actions.md) +
  $(wc -c <.chezmoitemplates/agents-shared-memory.md)
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

