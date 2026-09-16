# Complexity checks and delegation decisions are not automatic. complexity-gate
# stays a manual pre-publication check and the delegation gate is retired, so no
# managed harness may register either on edit, tool, or stop events. Unrelated
# hooks must survive the removal.
AGENT_HOOK_FORBIDDEN_PATTERN='complexity-gate|agent-delegation-gate|delegation-gate\.ts'

# Prints every hook command string in a rendered JSON hook document.
hook_commands() {
  jq -r '[.. | objects | .command? | strings] | .[]' "$1"
}

check_hook_document_policy() {
  local label="$1" rendered="$2"
  shift 2
  local commands required

  if ! commands="$(hook_commands "$rendered")"; then
    err "$label hooks are not valid JSON"
    return
  fi
  if grep -Eq "$AGENT_HOOK_FORBIDDEN_PATTERN" <<<"$commands"; then
    err "$label registers an automatic complexity or delegation hook"
  else
    pass "$label has no automatic complexity or delegation hook"
  fi
  for required in "$@"; do
    if grep -Fq -- "$required" <<<"$commands"; then
      pass "$label keeps unrelated hook: $required"
    else
      err "$label lost unrelated hook: $required"
    fi
  done
}

check_agent_hook_policy() {
  local claude="$TMP/hook-policy-claude.json"
  local codex="$TMP/hook-policy-codex.json"
  local cursor="$TMP/hook-policy-cursor.json"
  local grok="$TMP/hook-policy-grok.json"
  local pi_settings="$ROOT/dot_pi/agent/settings.json"
  local extension

  if chezmoi "${SRC[@]}" execute-template --file "$ROOT/dot_claude/settings.json.tmpl" >"$claude"; then
    check_hook_document_policy 'Claude settings' "$claude" \
      'pickforge-lanes hook claude' 'ai-attribution-gate.sh' 'codegraph prompt-hook' \
      '--event stop --agent claude-code' 'herdr-agent-state.sh'
  else
    err 'Claude settings render failed'
  fi
  if chezmoi "${SRC[@]}" execute-template --file "$ROOT/dot_codex/hooks.json.tmpl" >"$codex"; then
    check_hook_document_policy 'Codex hooks' "$codex" \
      'pickforge-lanes hook codex' '--event stop --agent codex' 'herdr-agent-state.sh'
  else
    err 'Codex hooks render failed'
  fi
  if chezmoi "${SRC[@]}" execute-template --file "$ROOT/dot_cursor/hooks.json.tmpl" >"$cursor"; then
    check_hook_document_policy 'Cursor hooks' "$cursor" \
      '--event stop --agent cursor' '--event session-start --agent cursor'
  else
    err 'Cursor hooks render failed'
  fi
  if chezmoi "${SRC[@]}" execute-template --file "$ROOT/dot_grok/hooks/ai-memory.json.tmpl" >"$grok"; then
    check_hook_document_policy 'Grok hooks' "$grok" '--event session-start --agent grok'
  else
    err 'Grok hooks render failed'
  fi

  if jq -e '.packages | any(contains("pi-kit")) and all(contains("complexity-gate") | not)' \
    "$pi_settings" >/dev/null 2>&1; then
    pass 'Pi packages keep pi-kit without the complexity-gate extension'
  else
    err 'Pi packages load the complexity-gate extension or lost pi-kit'
  fi

  if extension="$(grep -ElR "$AGENT_HOOK_FORBIDDEN_PATTERN" \
    "$ROOT/dot_pi/agent/extensions" "$ROOT/dot_omp/agent/extensions")"; then
    err "managed extensions run an automatic complexity or delegation hook: ${extension//"$ROOT/"/}"
  else
    pass 'managed Pi and OMP extensions have no complexity or delegation hook'
  fi

  check_opencode_hook_policy "$ROOT/dot_config/opencode/private_opencode.jsonc" 'OpenCode config'
  if [[ "$(find "$ROOT/dot_config/opencode" -mindepth 1 -printf '%P\n')" == private_opencode.jsonc ]]; then
    pass 'OpenCode source manages only its global config file'
  else
    err 'OpenCode source manages more than its global config file'
  fi

  if grep -Eq "$AGENT_HOOK_FORBIDDEN_PATTERN" "$ROOT/dot_config/git/hooks/executable_hook-dispatch"; then
    err 'global Git hook dispatcher runs complexity-gate in every repository'
  else
    pass 'global Git hook dispatcher leaves complexity-gate to repository-local hooks'
  fi

  if awk '
    /^\[compat\.claude\]$/ { active=1; next }
    /^\[/ { active=0 }
    active && /^hooks[[:space:]]*=[[:space:]]*false$/ { disabled=1 }
    END { exit disabled ? 1 : 0 }
  ' "$ROOT/dot_grok/config.toml"; then
    pass 'Grok keeps Claude hook compatibility enabled'
  else
    err 'Grok disables the Claude hook source'
  fi

  check_hook_policy_detection
}

# OpenCode loads complexity-gate as a plugin package rather than a hook command.
# Only that plugin is removed; the ai-memory MCP server must survive.
check_opencode_hook_policy() {
  local config="$1" label="$2"
  if ! jq -e . "$config" >/dev/null 2>&1; then
    err "$label is missing or not strict JSON: $config"
  elif jq -e '.plugin // [] | any(contains("complexity-gate"))' "$config" >/dev/null; then
    err "$label loads the complexity-gate plugin"
  else
    pass "$label does not load the complexity-gate plugin"
  fi
  if jq -e '.mcp["ai-memory"] == {type: "remote", url: "http://127.0.0.1:49374/mcp", enabled: true}' \
    "$config" >/dev/null 2>&1; then
    pass "$label keeps the ai-memory MCP server"
  else
    err "$label lost the ai-memory MCP server"
  fi
}

# A checker that never fails proves nothing: seed each forbidden hook and require
# rejection.
check_hook_policy_detection() {
  local fixture="$TMP/hook-policy-fixture.json" command
  for command in 'complexity-gate hook claude' "$HOME/.local/bin/agent-delegation-gate"; do
    jq -n --arg command "$command" \
      '{hooks: {Stop: [{hooks: [{type: "command", command: $command}]}]}}' >"$fixture"
    if (fail=0; check_hook_document_policy fixture "$fixture" >/dev/null 2>&1; [[ "$fail" -ne 0 ]]); then
      pass "hook policy rejects seeded hook: ${command##*/}"
    else
      err "hook policy accepted seeded hook: ${command##*/}"
    fi
  done
  jq '.plugin = ["@pickforge/complexity-gate"] | del(.mcp)' \
    "$ROOT/dot_config/opencode/private_opencode.jsonc" >"$fixture"
  if (fail=0; check_opencode_hook_policy "$fixture" fixture >/dev/null 2>&1; [[ "$fail" -ne 0 ]]) \
    && [[ "$(check_opencode_hook_policy "$fixture" fixture 2>&1 | grep -c '^ERR')" -eq 2 ]]; then
    pass 'OpenCode policy rejects a seeded complexity plugin and a lost MCP server'
  else
    err 'OpenCode policy accepted a seeded complexity plugin or lost MCP server'
  fi
}

# The managed enforce file is the source of the mode the hook worker resolves.
check_managed_workflow_mode() {
  local managed="$ROOT/dot_config/pickforge-lanes/workflow.json"
  local claude_settings="$TMP/workflow-claude-settings.json"
  local codex_hooks="$TMP/workflow-codex-hooks.json"

  need "$managed"
  if [[ -f "$managed" ]] && jq -e '.mode == "enforce"' "$managed" >/dev/null 2>&1; then
    pass 'managed Pickforge Lanes workflow selects enforce mode'
  else
    err 'managed Pickforge Lanes workflow mode is missing or not enforce'
  fi

  if chezmoi "${SRC[@]}" execute-template --file "$ROOT/dot_claude/settings.json.tmpl" \
      >"$claude_settings" \
    && jq -e '
      any(.hooks.PreToolUse[];
        (.matcher | contains("Edit") and contains("Write"))
        and (.hooks | any(.type == "command" and .command == "pickforge-lanes hook claude")))
    ' "$claude_settings" >/dev/null; then
    pass 'Claude settings register the workflow mutation gate on PreToolUse'
  else
    err 'Claude settings do not register the workflow mutation gate on PreToolUse'
  fi

  if chezmoi "${SRC[@]}" execute-template --file "$ROOT/dot_codex/hooks.json.tmpl" \
      >"$codex_hooks" \
    && jq -e '
      any(.hooks.PreToolUse[];
        (.matcher | contains("apply_patch"))
        and (.hooks | any(.type == "command" and .command == "pickforge-lanes hook codex")))
    ' "$codex_hooks" >/dev/null; then
    pass 'Codex hooks register the workflow mutation gate on PreToolUse'
  else
    err 'Codex hooks do not register the workflow mutation gate on PreToolUse'
  fi
}

check_live_agent_hook_policy() {
  local live commands

  for live in "$HOME/.claude/settings.json" "$HOME/.codex/hooks.json" "$HOME/.cursor/hooks.json"; do
    [[ -f "$live" ]] || continue
    if ! commands="$(hook_commands "$live" 2>/dev/null)"; then
      err "live hooks are not valid JSON: $live"
    elif grep -Eq "$AGENT_HOOK_FORBIDDEN_PATTERN" <<<"$commands"; then
      err "live hooks still run complexity or delegation automatically: $live"
    else
      pass "live hooks have no automatic complexity or delegation hook: $live"
    fi
  done

  if [[ -f "$HOME/.pi/agent/settings.json" ]] \
    && jq -e '.packages // [] | any(contains("complexity-gate"))' "$HOME/.pi/agent/settings.json" >/dev/null 2>&1; then
    err 'live Pi settings still load the complexity-gate extension'
  else
    pass 'live Pi settings do not load the complexity-gate extension'
  fi

  check_opencode_hook_policy "$HOME/.config/opencode/opencode.jsonc" 'live OpenCode config'

  if grok inspect --json 2>/dev/null | jq -e --arg pattern "$AGENT_HOOK_FORBIDDEN_PATTERN" '
    [.hooks[] | select((.target // "") + " " + (.command // "") | test($pattern))] | length == 0
  ' >/dev/null; then
    pass 'Grok loads no complexity or delegation hook'
  else
    err 'Grok loads a complexity or delegation hook, or inspection failed'
  fi
}
