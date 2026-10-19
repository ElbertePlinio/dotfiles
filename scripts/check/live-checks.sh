check_live_pi_enabled_models() {
  local settings="$HOME/.pi/agent/settings.json"
  if jq -e '(.enabledModels | all(. != "openai-codex/gpt-5.6-luna"))
    and (.enabledModels | any(. == "openai-codex/gpt-6.1-sol"))
    and (.enabledModels | any(. == "xai/grok-4.7"))
    and (.enabledModels | all(. != "xai/grok-4.5" and . != "xai/grok-4.6"))' "$settings" >/dev/null 2>&1; then
    pass 'live Pi enabled models include Sol and Grok 4.7 and exclude Luna, Grok 4.5 and Grok 4.6'
  else
    err 'live Pi enabled models must include Sol and Grok 4.7 and exclude Luna, Grok 4.5 and Grok 4.6'
  fi
}

check_live_opencode_config() {
  local config="$HOME/.config/opencode/opencode.jsonc"
  if [[ ! -e "$config" && ! -L "$config" ]]; then
    pass "live OpenCode config not yet applied: $config"
  elif [[ -L "$config" || ! -f "$config" ]]; then
    err "live OpenCode config must be a managed regular file: $config"
  elif cmp -s "$config" "$ROOT/dot_config/opencode/private_opencode.jsonc"; then
    pass 'live OpenCode config matches canonical source'
  else
    err 'live OpenCode config differs from canonical source'
  fi
}

if [[ "$MODE" == live ]]; then
  echo "== agent-config-sync live checks (read-only) =="
  GROK_LIVE="${HOME}/.grok/AGENTS.md"
  GROK_CONFIG_LIVE="${HOME}/.grok/config.toml"
  OMP_AGENTS_LIVE="${HOME}/.omp/agent/AGENTS.md"
  OMP_CONFIG_LIVE="${HOME}/.omp/agent/config.yml"
  OMP_MCP_LIVE="${HOME}/.omp/agent/mcp.json"
  check_live_retired_targets

  if [[ ! -e "$GROK_LIVE" ]]; then
    err "live Grok AGENTS missing: $GROK_LIVE"
  elif [[ -L "$GROK_LIVE" ]]; then
    target="$(readlink "$GROK_LIVE")"
    if [[ "$target" == *'/.codex/AGENTS.md' || "$target" == '../.codex/AGENTS.md' || "$target" == *'codex/AGENTS.md' ]]; then
      pass "live Grok AGENTS is expected Codex symlink ($target)"
    else
      err "live Grok AGENTS symlink is unexpected: $target"
    fi
  elif [[ -f "$GROK_LIVE" ]]; then
    pass 'live Grok AGENTS is a managed adapter'
  else
    err 'live Grok AGENTS is neither Codex symlink nor rendered Grok adapter'
  fi

  if [[ ! -e "$GROK_CONFIG_LIVE" ]]; then
    err "live Grok config missing: $GROK_CONFIG_LIVE"
  elif grep -Fxq 'default = "grok-4.6"' "$GROK_CONFIG_LIVE" \
    && ! grep -Fq 'grok-4.5' "$GROK_CONFIG_LIVE"; then
    pass 'live Grok config defaults to Grok 4.6'
  else
    err 'live Grok config default or effort is stale'
  fi

  if [[ ! -e "$OMP_AGENTS_LIVE" ]]; then
    pass "live OMP AGENTS not yet applied: $OMP_AGENTS_LIVE"
  elif [[ -L "$OMP_AGENTS_LIVE" ]]; then
    err "live OMP AGENTS must be a managed regular file: $OMP_AGENTS_LIVE"
  elif [[ -f "$OMP_AGENTS_LIVE" ]]; then
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
  else
    err 'live OMP config differs from canonical source'
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
    err 'live OMP MCP config differs from canonical source'
  fi
  check_live_primary_global_targets
  check_live_agent_hook_policy

  check_mcp_registry_and_config

  if [[ -f "$MANIFEST" ]]; then
    check_live_portable_links
  else
    err "manifest missing for live portable checks: $MANIFEST"
  fi

  check_live_pi_enabled_models
  check_live_opencode_config

  echo
  [[ "$fail" -eq 0 ]] && { echo "PASSED: live checks"; exit 0; }
  echo "FAILED: live checks"; exit 1
fi
