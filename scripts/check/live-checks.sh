pi_settings_have_expected_pending_migration() {
  local settings="$1"
  jq -s -e --slurpfile target "$ROOT/dot_pi/agent/settings.json" '
    (length == 1) and ($target | length == 1) and
    (.[0] as $live | $target[0] as $desired |
      $live.defaultThinkingLevel == "high" and
      $live.enabledModels == [
        "anthropic/claude-fable-5",
        "anthropic/claude-opus-4-8",
        "anthropic/claude-sonnet-5",
        "ollama/glm-5.2:cloud",
        "openai-codex/gpt-6-astra",
        "xai/grok-4.5"
      ] and
      (($live
        | .defaultThinkingLevel = $desired.defaultThinkingLevel
        | .enabledModels = $desired.enabledModels) == $desired))
  ' "$settings" >/dev/null 2>&1
}

check_live_pi_enabled_models() {
  local settings="$HOME/.pi/agent/settings.json"
  if [[ "$STRICT_PREFLIGHT" -eq 1 ]]; then
    if cmp -s "$settings" "$ROOT/dot_pi/agent/settings.json"; then
      pass 'live Pi settings match canonical source'
    elif managed_regular_file_unchanged "$settings" || pi_settings_have_expected_pending_migration "$settings"; then
      pass 'live Pi settings have managed model migration drift pending the authorized cutover'
    else
      err 'live Pi settings contain unmanaged drift'
    fi
  elif jq -e '(.enabledModels | any(. == "xai/grok-4.6"))
    and (.enabledModels | all(. != "xai/grok-4.5"))' "$settings" >/dev/null 2>&1; then
    pass 'live Pi enabled models select Grok 4.6 and retire Grok 4.5'
  else
    err 'live Pi enabled models do not cleanly replace Grok 4.5 with Grok 4.6'
  fi
}

if [[ "$MODE" == live ]]; then
  if [[ "$STRICT_PREFLIGHT" -eq 1 ]]; then
    echo "== agent-config-sync strict live preflight (read-only) =="
  else
    echo "== agent-config-sync live migration (read-only) =="
  fi
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
  elif [[ "$STRICT_PREFLIGHT" -eq 1 ]] && managed_regular_file_unchanged "$GROK_CONFIG_LIVE"; then
    pass 'live Grok config has managed pending drift'
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
  elif [[ "$STRICT_PREFLIGHT" -eq 1 ]]; then
    pass 'live OMP config has managed runtime drift pending the authorized cutover'
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
  elif [[ "$STRICT_PREFLIGHT" -eq 1 ]] && managed_regular_file_unchanged "$OMP_MCP_LIVE"; then
    pass 'live OMP MCP config has managed pending drift'
  else
    err 'live OMP MCP config differs from canonical source; refusing an implicit overwrite'
  fi
  if [[ "$STRICT_PREFLIGHT" -eq 0 ]]; then
    check_live_primary_global_targets
    check_live_delegation_gate
  fi

  check_mcp_registry_and_config

  if [[ -f "$MANIFEST" ]]; then
    check_live_portable_links
  else
    err "manifest missing for live portable checks: $MANIFEST"
  fi

  check_live_pi_enabled_models

  echo
  [[ "$fail" -eq 0 ]] && { echo "PASSED: live migration checks"; exit 0; }
  echo "FAILED: live migration checks"; exit 1
fi
