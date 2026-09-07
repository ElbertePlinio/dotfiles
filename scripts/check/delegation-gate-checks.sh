check_delegation_gate() {
  local gate="$ROOT/dot_local/bin/executable_agent-delegation-gate"
  local runtime="$TMP/delegation-gate-runtime"
  local stdout="$TMP/delegation-gate.out"
  local stderr="$TMP/delegation-gate.err"
  local status session

  need "$gate"
  if [[ ! -f "$gate" ]] || ! bash -n "$gate"; then
    err 'delegation gate shell syntax invalid'
    return
  fi

  mkdir -p "$runtime"
  session="agent-config-check-$$"
  if XDG_RUNTIME_DIR="$runtime" bash "$gate" \
    <<<"{\"tool_name\":\"apply_patch\",\"session_id\":\"$session\"}" \
    >"$stdout" 2>"$stderr"; then
    status=0
  else
    status=$?
  fi
  if [[ "$status" -eq 2 && ! -s "$stdout" ]] \
    && grep -Fq 'decide whether delegation is useful' "$stderr" \
    && [[ "$(wc -l <"$stderr")" -eq 1 && "$(wc -c <"$stderr")" -le 400 ]]; then
    pass 'delegation gate blocks the first edit with bounded feedback'
  else
    err 'delegation gate first-edit contract failed'
  fi

  if XDG_RUNTIME_DIR="$runtime" bash "$gate" \
    <<<"{\"tool_name\":\"apply_patch\",\"session_id\":\"$session\"}" \
    >"$stdout" 2>"$stderr"; then
    status=0
  else
    status=$?
  fi
  if [[ "$status" -eq 0 && ! -s "$stdout" && ! -s "$stderr" ]]; then
    pass 'delegation gate allows the retry silently'
  else
    err 'delegation gate did not allow the retry'
  fi

  if XDG_RUNTIME_DIR="$runtime" bash "$gate" \
    <<<'{"tool_name":"Edit","session_id":"child-check","agent_id":"worker"}' \
    >"$stdout" 2>"$stderr"; then
    status=0
  else
    status=$?
  fi
  if [[ "$status" -eq 0 && ! -s "$stdout" && ! -s "$stderr" ]]; then
    pass 'delegation gate skips child agents'
  else
    err 'delegation gate blocked a child agent'
  fi

  XDG_RUNTIME_DIR="$runtime" bash "$gate" \
    <<<'{"toolName":"read_file","sessionId":"grok-check"}' \
    >"$stdout" 2>"$stderr" || true
  if XDG_RUNTIME_DIR="$runtime" bash "$gate" \
    <<<'{"toolName":"search_replace","sessionId":"grok-check"}' \
    >"$stdout" 2>"$stderr"; then
    status=0
  else
    status=$?
  fi
  if [[ "$status" -eq 2 ]] && grep -Fq 'decide whether delegation is useful' "$stderr"; then
    pass 'delegation gate supports Grok camelCase payloads without marking reads'
  else
    err 'delegation gate Grok payload contract failed'
  fi

  if cmp -s "$ROOT/dot_pi/agent/extensions/delegation-gate.ts" \
    "$ROOT/dot_omp/agent/extensions/delegation-gate.ts"; then
    pass 'Pi and OMP delegation extensions are identical'
  else
    err 'Pi and OMP delegation extensions drifted'
  fi

  local extension_test
  extension_test='
const module = await import(process.env.GATE_EXTENSION!);
let handler: ((event: { toolName: string }, context: unknown) => unknown) | undefined;
module.default({ on: (_event: string, value: typeof handler) => { handler = value; } });
if (!handler) throw new Error("tool_call handler missing");
let sessionId = "session-a";
const context = { sessionManager: { getSessionId: () => sessionId } };
if (handler({ toolName: "read" }, context) !== undefined) throw new Error("read blocked");
const first = handler({ toolName: "edit" }, context) as { block?: boolean; reason?: string };
if (!first?.block || !first.reason?.includes("lanes_models")) throw new Error("first edit allowed");
if (handler({ toolName: "write" }, context) !== undefined) throw new Error("retry blocked");
sessionId = "session-b";
const next = handler({ toolName: "apply_patch" }, context) as { block?: boolean };
if (!next?.block) throw new Error("new session allowed");
process.env.PIKIT_CHILD = "1";
sessionId = "session-c";
if (handler({ toolName: "edit" }, context) !== undefined) throw new Error("child blocked");
'
  local extension
  for extension in \
    "$ROOT/dot_pi/agent/extensions/delegation-gate.ts" \
    "$ROOT/dot_omp/agent/extensions/delegation-gate.ts"; do
    if GATE_EXTENSION="$extension" bun -e "$extension_test"; then
      pass "delegation extension behavior valid: ${extension#"$ROOT/"}"
    else
      err "delegation extension behavior invalid: ${extension#"$ROOT/"}"
    fi
  done

  local claude_settings="$TMP/delegation-claude-settings.json"
  local codex_hooks="$TMP/delegation-codex-hooks.json"
  if chezmoi "${SRC[@]}" execute-template --file "$ROOT/dot_claude/settings.json.tmpl" \
      >"$claude_settings" \
    && jq -e --arg command "$HOME/.local/bin/agent-delegation-gate" '
      any(.hooks.PreToolUse[];
        (.matcher | contains("Edit"))
        and (.hooks | any(.type == "command" and .command == $command)))
    ' "$claude_settings" >/dev/null; then
    pass 'Claude settings register the delegation gate'
  else
    err 'Claude settings do not register the delegation gate'
  fi
  if chezmoi "${SRC[@]}" execute-template --file "$ROOT/dot_codex/hooks.json.tmpl" \
      >"$codex_hooks" \
    && jq -e --arg command "$HOME/.local/bin/agent-delegation-gate" '
      any(.hooks.PreToolUse[];
        (.matcher | contains("apply_patch"))
        and (.hooks | any(.type == "command" and .command == $command)))
    ' "$codex_hooks" >/dev/null; then
    pass 'Codex hooks register the delegation gate'
  else
    err 'Codex hooks do not register the delegation gate'
  fi
  if awk '
    /^\[compat\.claude\]$/ { active=1; next }
    /^\[/ { active=0 }
    active && /^hooks[[:space:]]*=[[:space:]]*false$/ { disabled=1 }
    END { exit disabled ? 1 : 0 }
  ' "$ROOT/dot_grok/config.toml"; then
    pass 'Grok keeps Claude hook compatibility enabled'
  else
    err 'Grok disables the Claude delegation hook source'
  fi
}

check_live_delegation_gate() {
  local gate="$HOME/.local/bin/agent-delegation-gate"
  local -a targets=(
    "$gate"
    "$HOME/.claude/settings.json"
    "$HOME/.codex/hooks.json"
    "$HOME/.pi/agent/extensions/delegation-gate.ts"
    "$HOME/.omp/agent/extensions/delegation-gate.ts"
  )

  if chezmoi "${SRC[@]}" verify "${targets[@]}" >/dev/null 2>&1; then
    pass 'live delegation gates match managed state'
  else
    err 'live delegation gates differ from managed state'
  fi

  if grok inspect --json 2>/dev/null | jq -e --arg target "$gate" '
    [.hooks[] | select(
      .event == "pre_tool_use"
      and .target == $target
      and (.matcher | contains("search_replace"))
      and .vendor == "claude"
      and .compatibilityStatus == "enabled"
    )] | length == 1
  ' >/dev/null; then
    pass 'Grok loads one delegation gate through Claude compatibility'
  else
    err 'Grok delegation gate compatibility is missing or duplicated'
  fi
}
