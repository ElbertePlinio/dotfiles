if [[ "$MODE" == live ]]; then
  if [[ "$STRICT_PREFLIGHT" -eq 1 ]]; then
    echo "== agent-config-sync strict live preflight (read-only) =="
  else
    echo "== agent-config-sync live migration (read-only) =="
  fi
  GROK_LIVE="${HOME}/.grok/AGENTS.md"
  OMP_AGENTS_LIVE="${HOME}/.omp/agent/AGENTS.md"
  OMP_CONFIG_LIVE="${HOME}/.omp/agent/config.yml"
  OMP_MCP_LIVE="${HOME}/.omp/agent/mcp.json"
  SOUL_LIVE="${HOME}/.hermes/SOUL.md"
  NOUS_DEFAULT='You are Hermes Agent, an intelligent AI assistant created by Nous Research.'
  check_omp_agent_override_sources
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
  elif grep -q '^# Personal Grok Notes' "$GROK_LIVE"; then
    pass 'live Grok AGENTS already rendered (Personal Grok Notes)'
  else
    err 'live Grok AGENTS is neither Codex symlink nor rendered Grok adapter'
  fi

  if [[ ! -e "$OMP_AGENTS_LIVE" ]]; then
    pass "live OMP AGENTS not yet applied: $OMP_AGENTS_LIVE"
  elif [[ -L "$OMP_AGENTS_LIVE" ]]; then
    err "live OMP AGENTS must be a managed regular file: $OMP_AGENTS_LIVE"
  elif grep -q '^# Personal OMP Notes' "$OMP_AGENTS_LIVE"; then
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
  check_live_omp_agent_overrides
  check_live_native_routing_files
  if [[ "$STRICT_PREFLIGHT" -eq 0 ]]; then
    check_live_primary_global_targets
  fi

  if [[ ! -f "$SOUL_LIVE" ]]; then
    err "live Hermes SOUL missing: $SOUL_LIVE"
  elif grep -q '^# Hermes' "$SOUL_LIVE" && grep -Fq "$HOME/AgentMemory" "$SOUL_LIVE"; then
    pass 'live Hermes SOUL already rendered (managed identity)'
  elif grep -Fq "$NOUS_DEFAULT" "$SOUL_LIVE" && ! grep -Fq 'I like short, practical work' "$SOUL_LIVE"; then
    pass 'live Hermes SOUL is known Nous default one-line identity'
  else
    err 'live Hermes SOUL is neither Nous default nor rendered managed SOUL'
  fi

  check_mcp_registry_and_config

  if [[ -f "$MANIFEST" ]]; then
    check_live_portable_links
  else
    err "manifest missing for live portable checks: $MANIFEST"
  fi

  if jq -e '.enabledModels | any(. == "xai/grok-4.5")' "$HOME/.pi/agent/settings.json" >/dev/null 2>&1; then
    pass 'live Pi enabled models include native Grok 4.5'
  else
    err 'live Pi enabled models missing native Grok 4.5'
  fi

  echo
  [[ "$fail" -eq 0 ]] && { echo "PASSED: live migration checks"; exit 0; }
  echo "FAILED: live migration checks"; exit 1
fi

