[[ -L dot_grok/AGENTS.md.tmpl || -L dot_grok/AGENTS.md ]] && err 'Grok AGENTS must not be a symlink'
need dot_grok/AGENTS.md.tmpl
if [[ -f dot_grok/AGENTS.md.tmpl ]]; then
  grep -qE 'codex/AGENTS|\.\./\.codex|Personal Codex Notes' dot_grok/AGENTS.md.tmpl \
    && err 'Grok adapter links to or reuses Codex' || pass 'Grok adapter not Codex-linked'
fi

if grep -Fq 'template "codex-behavior-override.md"' dot_codex/AGENTS.md.tmpl \
  && grep -Fq 'template "codex-behavior-override.md"' dot_agents/codex-lane-override.md.tmpl; then
  pass 'Codex adapters consume the canonical behavior override'
else
  err 'Codex behavior override include missing from an adapter'
fi

# Leaf adapters (Codex, Grok) stay table-free and reach the pool through the
# model-orchestration routing reference; orchestrating harnesses inline it.
for path in dot_codex/AGENTS.md.tmpl dot_grok/AGENTS.md.tmpl; do
  grep -qiE '^\|.*cost.*intelligence.*taste.*vision.*\|$' "$path" \
    && err "leaf adapter embeds a full model scoring table: $path" \
    || pass "leaf adapter has no full model scoring table: $path"
done
for path in dot_claude/CLAUDE.md.tmpl dot_pi/agent/AGENTS.md.tmpl dot_omp/agent/AGENTS.md.tmpl; do
  grep -Fq 'template "model-table.md"' "$path" \
    && pass "orchestrating adapter inlines the shared model table: $path" \
    || err "orchestrating adapter missing shared model table include: $path"
done

TABLE_ROW_GROK='^\| Grok 4\.5 \| .*grok-4\.5.* \| high \|.*\| yes \|$'
TABLE_ROW_KIMI='^\| Kimi K3 \| `ollama/kimi-k3:cloud` \| provider default \|.*\| yes \|$'
TABLE_ROW_OPUS='^\| Opus 5 \| `anthropic/claude-opus-5` \| medium \|.*\| yes \|$'
OPUS_EFFORT_RULE='Opus 5 defaults to `medium` and may use only `low` or `medium`; `high` and above are prohibited.'
for entry in \
  'dot_pi/agent/AGENTS.md.tmpl|Pi' \
  'dot_omp/agent/AGENTS.md.tmpl|OMP' \
  'dot_claude/CLAUDE.md.tmpl|Claude'; do
  IFS='|' read -r path harness <<<"$entry"
  out="$TMP/table-$(echo "$path" | tr '/' '_')"
  if render "$path" "$out" \
    && grep -Eq "$TABLE_ROW_GROK" "$out" \
    && grep -Eq "$TABLE_ROW_KIMI" "$out" \
    && grep -Eq "$TABLE_ROW_OPUS" "$out" \
    && grep -Fq "$OPUS_EFFORT_RULE" "$out"; then
    pass "rendered $harness routing table and Opus effort policy are current"
  else
    err "rendered $harness routing table or Opus effort policy is stale"
  fi
done

for entry in \
  'dot_codex/AGENTS.md.tmpl|Codex' \
  'dot_grok/AGENTS.md.tmpl|Grok'; do
  IFS='|' read -r path harness <<<"$entry"
  out="$TMP/opus-policy-$(echo "$path" | tr '/' '_')"
  if render "$path" "$out" && grep -Fq "$OPUS_EFFORT_RULE" "$out"; then
    pass "rendered $harness instructions include the Opus effort policy"
  else
    err "rendered $harness instructions are missing the Opus effort policy"
  fi
done

for path in "${STALE_PI_FLOW_PATHS[@]}"; do
  [[ ! -e "$path" ]] \
    && pass "stale Pi flow source absent: $path" \
    || err "stale Pi flow source remains: $path"
done

if grep -Fq '`max` reasoning level is allowed' dot_pi/agent/AGENTS.md.tmpl \
  && grep -Fq 'shared `xhigh` ceiling still applies to' dot_pi/agent/AGENTS.md.tmpl; then
  pass 'Pi adapter allows main-session Max while preserving the lane ceiling'
else
  err 'Pi adapter Max exception is missing or overbroad'
fi

fast_extension='dot_pi/agent/extensions/fast-mode.ts'
if [[ -f "$fast_extension" ]] \
  && grep -Fq 'registerCommand("fast"' "$fast_extension" \
  && grep -Fq 'service_tier: "priority"' "$fast_extension" \
  && grep -Fq 'model?.provider === "openai-codex"' "$fast_extension"; then
  pass 'Pi Fast mode extension maps supported Codex requests to priority tier'
else
  err 'Pi Fast mode extension is missing its command, provider guard, or priority mapping'
fi
unset fast_extension

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
    jq -e '.providers.ollama.models | any(.id == "kimi-k3:cloud")' >/dev/null <<<"$pi_models" \
      && pass 'Pi models include Ollama Kimi K3 Cloud' \
      || err 'Pi models missing Ollama Kimi K3 Cloud'
  else
    err 'Pi models JSON invalid'
  fi
else
  err 'could not read Pi models for runtime checks'
fi
unset pi_models

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

# Behavioral: the model bans live in dispatch code, not prose. Prove they throw.
if command -v node >/dev/null 2>&1; then
  if node --input-type=module -e "
    import { assertModelPermitted } from '$ROOT/dot_agents/skills/model-orchestration/scripts/lane-policy.mjs';
    for (const bad of ['gpt-5.6-terra', 'gpt-5.6-luna', 'claude-haiku-4-5']) {
      let threw = false;
      try { assertModelPermitted(bad); } catch { threw = true; }
      if (!threw) { console.error('allowed banned model: ' + bad); process.exit(1); }
    }
    assertModelPermitted('gpt-5.6-sol');
    assertModelPermitted('claude-fable-5');
    assertModelPermitted('kimi-k3:cloud');
  " 2>/dev/null; then
    pass 'lane-policy bans Haiku/Luna/Terra and admits the managed pool'
  else
    err 'lane-policy ban enforcement failed its behavioral probe'
  fi
else
  err 'node unavailable for lane-policy behavioral probe'
fi

GLOBAL_CLAUDE_OUT="$TMP/claude-global.md"
if render dot_claude/CLAUDE.md.tmpl "$GLOBAL_CLAUDE_OUT"; then
  grep -Fq '## Claude model orchestration' "$GLOBAL_CLAUDE_OUT" \
    && grep -Fq 'AgentMemory' "$GLOBAL_CLAUDE_OUT" \
    && pass 'global Claude profile renders orchestration and memory policy' \
    || err 'global Claude profile is missing orchestration or memory policy'
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
