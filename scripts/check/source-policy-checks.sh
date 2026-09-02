[[ -L dot_grok/AGENTS.md.tmpl || -L dot_grok/AGENTS.md ]] && err 'Grok AGENTS must not be a symlink'
need dot_grok/AGENTS.md.tmpl
if [[ -f dot_grok/AGENTS.md.tmpl ]]; then
  grep -qE 'codex/AGENTS|\.\./\.codex|Personal Codex Notes' dot_grok/AGENTS.md.tmpl \
    && err 'Grok adapter links to or reuses Codex' || pass 'Grok adapter not Codex-linked'
fi

if grep -Fxq '  - xai-oauth/grok-4.6' dot_omp/agent/config.yml \
  && ! grep -Fq 'grok-4.5' dot_omp/agent/config.yml; then
  pass 'OMP source selects Grok 4.6 and retires Grok 4.5'
else
  err 'OMP source does not cleanly replace Grok 4.5 with Grok 4.6'
fi

if grep -Fxq 'default = "grok-4.6"' dot_grok/config.toml \
  && ! grep -Fq 'grok-4.5' dot_grok/config.toml; then
  pass 'Grok source defaults to Grok 4.6'
else
  err 'Grok source default or effort is stale'
fi

if grep -Fq 'template "codex-behavior-override.md"' dot_codex/AGENTS.md.tmpl \
  && grep -Fq 'template "codex-behavior-override.md"' dot_agents/codex-lane-override.md.tmpl; then
  pass 'Codex adapters consume the canonical behavior override'
else
  err 'Codex behavior override include missing from an adapter'
fi

for path in "${STALE_PI_FLOW_PATHS[@]}"; do
  [[ ! -e "$path" ]] \
    && pass "stale Pi flow source absent: $path" \
    || err "stale Pi flow source remains: $path"
done

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

compaction_extension='dot_pi/agent/extensions/model-compaction-threshold.ts'
if [[ -f "$compaction_extension" ]] \
  && grep -Fq 'provider: "openai-codex"' "$compaction_extension" \
  && grep -Fq 'id: "gpt-5.6-sol"' "$compaction_extension" \
  && grep -Fq 'COMPACTION_THRESHOLD_TOKENS = 240_000' "$compaction_extension"; then
  pass 'Pi model-specific compaction threshold targets GPT-5.6 Sol at 240k tokens'
else
  err 'Pi model-specific compaction threshold has the wrong model or token limit'
fi
unset compaction_extension

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
    jq -e '(.enabledModels | any(. == "xai/grok-4.6"))
      and (.enabledModels | all(. != "xai/grok-4.5"))
      and (.enabledModels | any(. == "opencode-go/kimi-k3"))
      and (.enabledModels | any(. == "opencode-go/glm-5.3-flash"))
      and (.enabledModels | all(. != "opencode-go/ox-alpha-free"))
      and (.enabledModels | all(. != "ollama/kimi-k3:cloud"))' >/dev/null <<<"$pi_settings" \
      && pass 'Pi enabled models select Grok 4.6 and OpenCode Go Kimi/GLM Flash, and retire Ox Alpha' \
      || err 'Pi enabled models missing OpenCode Go pool, still list retired Ox Alpha, or still pin Ollama Kimi'
    jq -e '.defaultProvider == "openai-codex" and .defaultModel == "gpt-5.6-sol"' >/dev/null <<<"$pi_settings" \
      && pass 'Pi canonical bootstrap defaults to GPT-5.6 Sol' \
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
    jq -e '.providers["openai-codex"].models
      | any(.id == "gpt-5.6-sol" and .contextWindow == 272000)' >/dev/null <<<"$pi_models" \
      && pass 'Pi GPT-5.6 Sol uses a 272k context window' \
      || err 'Pi GPT-5.6 Sol context window is not 272k'
    jq -e '(.providers.ollama.models // []) | any(.id == "kimi-k3:cloud")' >/dev/null <<<"$pi_models" \
      && err 'Pi models still pin Ollama Kimi K3 Cloud; use OpenCode Go' \
      || pass 'Pi models no longer pin Ollama Kimi K3'
    jq -e '.providers["deepseek-official"]
      | .apiKey == "!sed -n '\''s/^DEEPSEEK_API_KEY=//p'\'' \"$HOME/.agents/deepseek.env\""
      and any(.models[]; .id == "deepseek-v4-flash")' >/dev/null <<<"$pi_models" \
      && pass 'Pi models include DeepSeek V4 Flash with encrypted credential indirection' \
      || err 'Pi models missing DeepSeek V4 Flash or safe credential indirection'
  else
    err 'Pi models JSON invalid'
  fi
else
  err 'could not read Pi models for runtime checks'
fi
unset pi_models

for public_profile_file in \
  .chezmoitemplates/agents-shared.md \
  dot_claude/CLAUDE.md.tmpl; do
  grep -qiE '(^|[^[:alnum:]_])(company|contract|client|employer)([^[:alnum:]_]|$)' "$public_profile_file" \
    && err "profile source exposes private work-context vocabulary: $public_profile_file" \
    || pass "profile source uses generic public vocabulary: $public_profile_file"
done
