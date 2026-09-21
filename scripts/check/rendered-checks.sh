echo "== agent-config-sync checks =="
echo "source: $ROOT"

SHARED=(
  .chezmoitemplates/agents-shared.md
  .chezmoitemplates/codex-behavior-override.md
)
HARNESS=(
  'dot_codex/AGENTS.md.tmpl|# Codex|# Claude'
  'dot_grok/AGENTS.md.tmpl|# Grok|# Codex'
  'dot_pi/agent/AGENTS.md.tmpl|# Pi|# Codex'
  'dot_omp/agent/AGENTS.md.tmpl|# OMP|# Codex'
)
# Size ratchet: the shared policy shrank deliberately (2026-07); the budget stops
# it regrowing. Raise only with an explicit decision, never to make a check pass.
SHARED_MAX_BYTES=10000

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
      dot_config/QtProject.conf|\
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
check_retired_reference_scanner_regressions
check_active_target_completeness
check_sync_command_flow
check_pickforge_lanes_deployment
if python3 "$ROOT/scripts/test-lanes-hooks-config.py" >"$TMP/lanes-hooks-config.log" 2>&1; then
  pass "Lanes notification hooks track lifecycle and rearm with harness wake support"
else
  err "Lanes notification hook configuration tests failed"
fi
check_agent_hook_policy
check_managed_workflow_mode
check_doctor_sources
check_os_gating
check_portable_home_literals

for f in "${SHARED[@]}"; do need "$f"; done

shared_bytes="$(chezmoi "${SRC[@]}" execute-template '{{ template "agents-shared.md" . }}' | wc -c)"
if ((shared_bytes <= SHARED_MAX_BYTES)); then
  pass "shared policy size ${shared_bytes} bytes (budget ${SHARED_MAX_BYTES})"
else
  err "shared policy size ${shared_bytes} bytes exceeds ${SHARED_MAX_BYTES}-byte regression budget"
fi

if render .chezmoitemplates/agents-shared.md "$TMP/agents-shared.md"; then
  pass 'shared template renders'
else
  err 'shared template render failed'
fi

for routing_rule in \
  'Consider the whole eligible pool, not just the parent provider.' \
  'Sol and Fable are the preferred Pi and Claude Code orchestrators.' \
  'Reserve Astra primarily for independent final review, difficult correctness work' \
  'Treat the catalog'\''s Budget pressure score as a practical API or subscription resource prior' \
  'Fable is a selective first-class planner and advisor for consequential ambiguity, architecture, product intent, visual judgment, and nuanced review' \
  'When delegating read-only planning or investigation, use model-backed assessment attempts' \
  'Read-only Pi and Claude Code lanes lack shell access' \
  'including native agents and excluding diagnostics' \
  'Always use openai-codex/gpt-6-astra at low effort to execute device-pass and Picklab/Pickforge computer-use tasks.' \
  'The current model executes the work directly by default, whatever its size.' \
  'Discussion, investigation, and PR review get no automatic delegation and no review of the review.' \
  'Do not create a managed Pickforge Lanes task just to record a choice to execute directly.' \
  'Code being shipped gets one independent review by a model that did not author it.' \
  'A model, effort, or reviewer I explicitly request takes precedence over catalog selection.' \
  'it is not a per-edit, per-commit, per-review, or pre-review step'; do
  grep -Fq "$routing_rule" "$TMP/agents-shared.md" \
    || err "shared routing policy missing: $routing_rule"
done
for retired_rule in \
  'orchestrates rather than doing the substantive implementation' \
  'Create a planned Pickforge Lanes task before substantive implementation' \
  'Direct work by the lead is fine when it is tiny' \
  'defined sensitive work takes two' \
  'Use model-backed assessment attempts for read-only planning and investigation' \
  'Before committing code to publish'; do
  grep -Fq "$retired_rule" "$TMP/agents-shared.md" \
    && err "shared policy keeps retired delegation rule: $retired_rule"
done
if grep -Fq 'before completing every coding or code-review task' dot_agents/skills/complexity-gate/SKILL.md \
  || grep -Fq 'Stop hook' dot_agents/skills/complexity-gate/references/output.md \
  || ! grep -Fxq 'set -euo pipefail' dot_agents/skills/complexity-gate/SKILL.md \
  || ! grep -Fq 'git rev-parse --verify --quiet "$base^{commit}"' dot_agents/skills/complexity-gate/SKILL.md \
  || ! grep -Fq '"$base...HEAD" -- | xargs -0 -r complexity-gate check --' dot_agents/skills/complexity-gate/SKILL.md; then
  err 'complexity-gate skill requires automatic runs or lacks the fail-safe range command'
else
  pass 'complexity-gate skill is a manual pre-publication check'
fi
unset retired_rule
if grep -Fq 'Always execute this pass with `openai-codex/gpt-6-astra` at `low` effort.' dot_agents/skills/device-pass/SKILL.md \
  && grep -Fq 'Confirm the worker has the required browser/device tools before spawning' dot_agents/skills/device-pass/SKILL.md \
  && grep -Fq 'Pi lanes disable extensions and do not inherit browser/MCP tools' dot_agents/skills/device-pass/SKILL.md; then
  pass 'device-pass pins Astra low and checks worker tool access'
else
  err 'device-pass is missing its fixed model/effort or worker tool check'
fi
for routing_adapter in dot_claude/CLAUDE.md.tmpl dot_codex/AGENTS.md.tmpl dot_pi/agent/AGENTS.md.tmpl dot_grok/AGENTS.md.tmpl dot_omp/agent/AGENTS.md.tmpl; do
  routing_render="$TMP/routing-$(basename "$(dirname "$routing_adapter")")-$(basename "$routing_adapter")"
  if render "$routing_adapter" "$routing_render" \
    && grep -Fq 'Consider the whole eligible pool, not just the parent provider.' "$routing_render" \
    && grep -Fq 'Always use openai-codex/gpt-6-astra at low effort to execute device-pass and Picklab/Pickforge computer-use tasks.' "$routing_render"; then
    pass "shared routing policy reaches $routing_adapter"
  else
    err "shared routing policy missing from $routing_adapter"
  fi
done
unset routing_rule routing_adapter routing_render

for path in "${RETIRED_SOURCE_PATHS[@]}"; do
  source_absent "$path"
done
check_manifest_and_sources
check_legacy_model_skill_absence
check_skill_lock_retirements
check_mcp_registry_and_config
check_runtime_exclusions

for entry in "${HARNESS[@]}"; do
  IFS='|' read -r path want forbid <<<"$entry"
  if [[ ! -f "$path" ]]; then err "missing: $path"; continue; fi
  grep -Fq 'template "agents-shared.md"' "$path" \
    || err "missing shared include: $path"
  for bad in 'Make the smallest clean change that solves the requested problem.' 'names, model IDs, and technical terms' 'AgentMemory'; do
    grep -Fq "$bad" "$path" && err "duplicate shared policy in $path: $bad"
  done
  out="$TMP/$(echo "$path" | tr '/' '_')"
  if ! render "$path" "$out"; then err "render failed: $path"; continue; fi
  pass "rendered $path"
  grep -Fq "$want" "$out" || err "missing heading in $path: $want"
  grep -Fq "$forbid" "$out" && err "forbidden heading in $path: $forbid"
  [[ "$(grep -c 'Make the smallest clean change that solves the requested problem.' "$out" || true)" -eq 1 ]] || err "shared intro count != 1 in $path"
  grep -Fq 'AgentMemory' "$out" || err "missing AgentMemory in $path"
done

for entry in "${ADAPTER_BUDGETS[@]}"; do
  IFS='|' read -r path budget <<<"$entry"
  bytes="$(wc -c <"$path")"
  if ((bytes <= budget)); then
    pass "adapter source size ${path}: ${bytes} bytes (budget ${budget})"
  else
    err "adapter source size ${path}: ${bytes} bytes exceeds ${budget}-byte regression budget"
  fi
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

launch_preflight_ok=1
for shell_source in .chezmoitemplates/zshrc-common dot_bashrc; do
  grep -Fq '"$HOME/.local/bin/agent-harness-preflight" "$harness"' "$shell_source" \
    || launch_preflight_ok=0
  for harness in claude codex grok pi omp; do
    grep -Fq "_agent_harness_preflight $harness \"\${1:-}\" || return" "$shell_source" \
      || launch_preflight_ok=0
  done
done
if [[ "$launch_preflight_ok" -eq 1 ]]; then
  pass 'zsh and bash agent-session wrappers gate every managed harness on preflight'
else
  err 'a managed harness agent-session wrapper bypasses preflight'
fi
unset launch_preflight_ok shell_source harness

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
    && grep -Fq 'ANTHROPIC_SMALL_FAST_MODEL="gpt-6-astra"' <<<"$linux_claude_codex" \
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
