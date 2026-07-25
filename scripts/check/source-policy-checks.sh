need "$SOUL"
for include in agents-shared-memory.md agents-shared-public-actions.md agents-shared-destructive-actions.md; do
  grep -Fq "template \"$include\"" "$SOUL" \
    || err "Hermes SOUL missing shared include: $include"
done
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

need .chezmoitemplates/codex-behavior-override.md
if grep -Fq 'template "codex-behavior-override.md"' dot_codex/AGENTS.md.tmpl \
  && grep -Fq 'template "codex-behavior-override.md"' dot_agents/codex-lane-override.md.tmpl; then
  pass 'Codex adapters consume the canonical behavior override'
else
  err 'Codex behavior override include missing from an adapter'
fi
if grep -Fq '~/.codex/skills/model-orchestration/references/model-routing.md' dot_claude/CLAUDE.md.tmpl; then
  err 'Claude adapter hardcodes the Codex routing reference path'
elif grep -Fq 'references/model-routing.md' dot_claude/CLAUDE.md.tmpl; then
  pass 'Claude adapter uses a skill-relative routing reference'
else
  err 'Claude adapter missing skill-relative routing reference'
fi

for path in dot_claude/CLAUDE.md.tmpl \
  dot_codex/AGENTS.md.tmpl dot_grok/AGENTS.md.tmpl; do
  grep -qiE '^\|.*cost.*intelligence.*taste.*vision.*\|$' "$path" \
    && err "adapter embeds a full model scoring table: $path" \
    || pass "adapter has no full model scoring table: $path"
done

ADAPTER_OWNER_POINTERS=(
  'dot_claude/CLAUDE.md.tmpl|model-routing.md|Claude'
  'dot_codex/AGENTS.md.tmpl|model-orchestration|Codex'
  'dot_grok/AGENTS.md.tmpl|model-orchestration|Grok'
  'dot_pi/agent/AGENTS.md.tmpl|Available managed pool|Pi'
  'dot_omp/agent/AGENTS.md.tmpl|Available managed pool|OMP'
)
for entry in "${ADAPTER_OWNER_POINTERS[@]}"; do
  IFS='|' read -r path pointer harness <<<"$entry"
  grep -Fq "$pointer" "$path" \
    && pass "$harness adapter points to its routing owner" \
    || err "$harness adapter missing routing owner pointer: $pointer"
done

need .chezmoitemplates/model-table.md
if grep -Fq 'template "model-table.md"' dot_pi/agent/AGENTS.md.tmpl \
  && grep -Fq '"grokSelector" "xai/grok-4.5"' dot_pi/agent/AGENTS.md.tmpl \
  && grep -Fq '"glmStart" "medium"' dot_pi/agent/AGENTS.md.tmpl; then
  pass 'Pi adapter consumes shared model table with native parameters'
else
  err 'Pi adapter shared model table include or parameters mismatch'
fi
if grep -Fq 'template "model-table.md"' dot_omp/agent/AGENTS.md.tmpl \
  && grep -Fq '"grokSelector" "xai-oauth/grok-4.5"' dot_omp/agent/AGENTS.md.tmpl \
  && grep -Fq '"glmStart" "provider default"' dot_omp/agent/AGENTS.md.tmpl; then
  pass 'OMP adapter consumes shared model table with native parameters'
else
  err 'OMP adapter shared model table include or parameters mismatch'
fi
PI_TABLE_OUT="$TMP/pi-model-table.md"
OMP_TABLE_OUT="$TMP/omp-model-table.md"
if render dot_pi/agent/AGENTS.md.tmpl "$PI_TABLE_OUT" \
  && grep -Eq '^\| Grok 4\.5 \| `xai/grok-4\.5` \| high \|' "$PI_TABLE_OUT" \
  && grep -Eq '^\| GLM-5\.2 \| `ollama/glm-5\.2:cloud` \| medium \|' "$PI_TABLE_OUT"; then
  pass 'rendered Pi routing table includes native Grok 4.5 selector and GLM start'
else
  err 'rendered Pi routing table missing native Grok 4.5 selector or GLM start'
fi
if render dot_omp/agent/AGENTS.md.tmpl "$OMP_TABLE_OUT" \
  && grep -Eq '^\| Grok 4\.5 \| `xai-oauth/grok-4\.5` \| high \|' "$OMP_TABLE_OUT" \
  && grep -Eq '^\| GLM-5\.2 \| `ollama/glm-5\.2:cloud` \| provider default \|' "$OMP_TABLE_OUT"; then
  pass 'rendered OMP routing table includes OAuth Grok 4.5 selector and GLM start'
else
  err 'rendered OMP routing table missing OAuth Grok 4.5 selector or GLM start'
fi

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
    jq -e '.defaultProvider == "openai-codex" and .defaultModel == "gpt-5.6-sol" and .defaultThinkingLevel == "high"' >/dev/null <<<"$pi_settings" \
      && pass 'Pi canonical bootstrap defaults to GPT-5.6 Sol at high effort' \
      || err 'Pi canonical GPT-5.6 Sol bootstrap default is missing or misconfigured'
  else
    err 'Pi settings JSON invalid'
  fi
else
  err 'could not read Pi settings for runtime checks'
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
  err 'could not read Pi models for runtime checks'
fi
unset pi_models


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
    */references/model-routing.md)
      if grep -Fq 'pickgauge-usage' <<<"$decrypted" \
        && grep -Fq 'intelligence > taste > cost' <<<"$decrypted" \
        && grep -Fq '`xai/grok-4.5` (Pi, pickforge-lanes MCP)' <<<"$decrypted" \
        && grep -Fq '`xai-oauth/grok-4.5` (OMP)' <<<"$decrypted"; then
        pass 'model-routing owns selection policy and harness-scoped Grok selectors'
      else
        err 'model-routing selection policy or harness-scoped Grok selectors missing'
      fi
      ;;
    */kickoff/SKILL.md)
      grep -Fq 'model-routing.md' <<<"$decrypted" \
        && pass 'kickoff fallback routing points to model-routing owner' \
        || err 'kickoff fallback routing missing model-routing owner'
      ;;
  esac
done
unset decrypted

for reference in delegation-contract.md dispatch.md model-routing.md review-schemas.md; do
  canonical_reference=''
  if canonical_reference="$(chezmoi "${SRC[@]}" cat \
    "$HOME/.agents/skills/model-orchestration/references/$reference")" \
    && [[ -n "$canonical_reference" ]]; then
    pass "canonical routing reference present: $reference"
  else
    err "canonical routing reference missing or empty: $reference"
  fi
done
unset canonical_reference

# model-orchestration is canonical under dot_agents/skills and reaches every
# harness by symlink. Harness-native forks reintroduce the drift that previously
# let a stale model pin survive in one copy but not the other.
if [[ -e "$ROOT/dot_codex/skills/model-orchestration" \
  || -e "$ROOT/dot_grok/skills/model-orchestration" ]]; then
  err 'harness-native model-orchestration copy reintroduced; keep it canonical'
else
  pass 'model-orchestration has no harness-native duplicate'
fi

local_review=''
if local_review="$(cat \
  "$ROOT/dot_agents/skills/local-review/SKILL.md")"; then
  grep -Fq 'Every review includes a KISS gate' <<<"$local_review" \
    && grep -Fq 'mandatory KISS verdict' <<<"$local_review" \
    && pass 'local-review requires a scoped KISS gate' \
    || err 'local-review missing required KISS gate'
  grep -Fq 'references/model-routing.md' <<<"$local_review" \
    && grep -Fq 'never treat a model as permanently assigned' <<<"$local_review" \
    && pass 'local-review delegates model selection to the current table' \
    || err 'local-review missing dynamic model selection'
  grep -Eq 'Grok 4\.5|GPT-5\.6|Fable 5|Opus 5|Opus 4\.8|Sonnet 5|GLM-5\.2' <<<"$local_review" \
    && err 'local-review contains fixed model lane assignments' \
    || pass 'local-review contains no fixed model lane assignments'
else
  err 'could not read local-review skill for checks'
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
  for bad in 'I like short, practical work' 'names, model IDs, and technical terms' 'AgentMemory'; do
    grep -Fq "$bad" "$path" && err "duplicate shared policy in $path: $bad"
  done
  out="$TMP/$(echo "$path" | tr '/' '_')"
  if ! render "$path" "$out"; then err "render failed: $path"; continue; fi
  pass "rendered $path"
  grep -Fq "$want" "$out" || err "missing heading in $path: $want"
  grep -Fq "$forbid" "$out" && err "forbidden heading in $path: $forbid"
  [[ "$(grep -c 'I like short, practical work' "$out" || true)" -eq 1 ]] || err "shared intro count != 1 in $path"
  grep -q PickScribe "$out" || err "missing PickScribe in $path"
  grep -Fq "$HOME/AgentMemory" "$out" || err "missing AgentMemory in $path"
  grep -Fq 'CODING_AGENT_RULES.md' "$out" \
    && err "global harness auto-loads CODING_AGENT_RULES: $path" \
    || pass "global harness excludes CODING_AGENT_RULES: $path"
done

GLOBAL_CLAUDE_OUT="$TMP/claude-global.md"

if render dot_claude/CLAUDE.md.tmpl "$GLOBAL_CLAUDE_OUT"; then
  grep -Fq '## Claude model orchestration' "$GLOBAL_CLAUDE_OUT" \
    && grep -Fq "$HOME/AgentMemory" "$GLOBAL_CLAUDE_OUT" \
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

if render "$SOUL" "$TMP/SOUL.md" \
  && grep -Fq -- '- Public actions (posts, replies, likes, follows, DMs, publishing) are drafts only; the user performs them.' "$TMP/SOUL.md" \
  && grep -Fq -- '- Destructive filesystem, Git, account, or external-service actions require explicit confirmation.' "$TMP/SOUL.md" \
  && grep -Fq 'CODING_AGENT_RULES.md' "$TMP/SOUL.md"; then
  pass 'rendered Hermes SOUL includes shared boundaries and standalone coding memory'
else
  err 'Hermes SOUL render or shared-boundary composition failed'
fi

