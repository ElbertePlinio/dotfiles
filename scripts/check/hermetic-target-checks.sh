TARGETS=(
  "$DEST/.zshrc" "$DEST/.bashrc"
  "$DEST/.claude/CLAUDE.md"
  "$DEST/.claude/agents/final-reviewer.md"
  "$DEST/.claude/agents/final-reviewer-high.md"
  "$DEST/.claude/agents/final-reviewer-xhigh.md"
  "$DEST/.claude/skills/kickoff"
  "$DEST/.claude/skills/codex"
  "$DEST/.claude/settings.json"
  "$DEST/.codex/AGENTS.md"
  "$DEST/.grok/AGENTS.md" "$DEST/.pi/agent/AGENTS.md" "$DEST/.omp/agent/AGENTS.md"
  "$DEST/.omp/agent/config.yml" "$DEST/.omp/agent/mcp.json"
  "$DEST/.local/bin/agent-config-sync"
  "$DEST/.local/bin/agent-harness-preflight"
  "$DEST/.local/bin/pickforge-lanes-mcp"
  "$DEST/.config/agent-config-sync/doctor.json"
  "$DEST/.agents/skill-targets.json"
  "$DEST/.agents/mcp-targets.json"
)
EXPECTED=(
  dot_zshrc.tmpl dot_bashrc
  dot_claude/CLAUDE.md.tmpl
  dot_claude/settings.json.tmpl
  dot_codex/AGENTS.md.tmpl
  dot_grok/AGENTS.md.tmpl dot_pi/agent/AGENTS.md.tmpl dot_omp/agent/AGENTS.md.tmpl
  dot_omp/agent/config.yml dot_omp/agent/mcp.json.tmpl
  dot_local/bin/executable_agent-config-sync
  dot_local/bin/executable_agent-harness-preflight
  dot_local/bin/executable_pickforge-lanes-mcp
  dot_config/agent-config-sync/doctor.json
  dot_agents/skill-targets.json.tmpl
  dot_agents/mcp-targets.json
)
if chezmoi "${TMP_SRC[@]}" --destination "$DEST" source-path "${TARGETS[@]}" >"$TMP/sp.txt" 2>"$TMP/sp.err"; then
  for e in "${EXPECTED[@]}"; do
    grep -Fq "$e" "$TMP/sp.txt" && pass "source-path $e" || err "source-path missing $e"
  done
else
  err "source-path failed: $(tr '\n' ' ' <"$TMP/sp.err")"
fi
chezmoi "${TMP_SRC[@]}" --destination "$DEST" --dry-run status >/dev/null 2>"$TMP/st.err" \
  && pass 'dry-run status (temp dest)' || err "dry-run status failed: $(tr '\n' ' ' <"$TMP/st.err")"

mkdir -p "$DEST/.grok" "$DEST/.codex" \
  "$DEST/.local/bin" "$DEST/.config/agent-config-sync" \
  "$DEST/.claude/rules" "$DEST/.claude/skills" "$DEST/.claude/agents" \
  "$DEST/.grok/skills" \
  "$DEST/.pi/agent/skills" "$DEST/.omp/agent/skills" \
  "$DEST/.pi/agent/extensions" "$DEST/.omp/agent/extensions" \
  "$DEST/.agents/skills"
ln -s ../.codex/AGENTS.md "$DEST/.grok/AGENTS.md"

if ! chezmoi "${TMP_SRC[@]}" --destination "$DEST" apply "$DEST/.agents/skills" "${TARGETS[@]}"; then
  err 'temp seed apply (canonical skills / adapters) failed'
else
  grep -Fq 'Never expose, commit, or send secrets or private production data.' "$DEST/.claude/CLAUDE.md" \
    && pass 'temp global Claude profile applied' \
    || err 'temp global Claude profile missing hard limits'
  [[ -x "$DEST/.local/bin/agent-config-sync" ]] \
    && bash -n "$DEST/.local/bin/agent-config-sync" \
    && pass 'temp agent-config-sync applied' \
    || err 'temp agent-config-sync invalid'
  [[ ! -L "$DEST/.grok/AGENTS.md" ]] && grep -q '^# Grok' "$DEST/.grok/AGENTS.md" \
    && pass 'temp migration replaces Grok symlink safely' || err 'temp Grok symlink migration failed'
  grep -q '^# OMP' "$DEST/.omp/agent/AGENTS.md" \
    && ! grep -Fq 'CODING_AGENT_RULES.md' "$DEST/.omp/agent/AGENTS.md" \
    && pass 'temp OMP adapter applied without global CODING_AGENT_RULES load' \
    || err 'temp OMP adapter apply mismatch'
  cmp -s "$DEST/.omp/agent/config.yml" "$ROOT/dot_omp/agent/config.yml" \
    && pass 'temp OMP runtime config applied' || err 'temp OMP runtime config apply mismatch'
  jq -e --arg home "$HOME" '
    .mcpServers["agentmemory-vault"].args == [($home + "/AgentMemory/scripts/agent_memory_mcp.py")]
    and .mcpServers["cua-driver"].command == ($home + "/.local/bin/cua-driver")
  ' "$DEST/.omp/agent/mcp.json" >/dev/null \
    && pass 'temp OMP MCP config applied with rendered home paths' \
    || err 'temp OMP MCP config apply mismatch'
fi

PORTABLE_TARGETS=()
while IFS= read -r target; do
  PORTABLE_TARGETS+=("$target")
done < <(jq -r --arg dest "$DEST" '
  . as $root
  | .skills | to_entries[]
  | .key as $skill
  | .value[] as $harness
  | $root.harnesses[$harness] as $h
  | select($h.discovery == "symlink")
  | ($h.skills_root | sub("^~"; $dest)) + "/" + $skill
' "$MANIFEST")

if ((${#PORTABLE_TARGETS[@]})); then
  for target in "${PORTABLE_TARGETS[@]}"; do
    mkdir -p "$(dirname "$target")"
  done
  if chezmoi "${TMP_SRC[@]}" --destination "$DEST" apply "${PORTABLE_TARGETS[@]}"; then
    pass "temp applied ${#PORTABLE_TARGETS[@]} portable skill links"
  else
    err 'temp portable skill apply failed'
  fi
fi

while IFS=$'\t' read -r skill harness; do
  discovery="$(jq -r --arg h "$harness" '.harnesses[$h].discovery' "$MANIFEST")"
  [[ "$discovery" == "symlink" ]] || continue
  root="$(jq -r --arg h "$harness" --arg dest "$DEST" \
    '.harnesses[$h].skills_root | sub("^~"; $dest)' "$MANIFEST")"
  expected_prefix="$(jq -r --arg h "$harness" '.harnesses[$h].relative_prefix' "$MANIFEST")"
  link="${root}/${skill}"
  want="${expected_prefix}/${skill}"
  if [[ ! -L "$link" ]]; then
    err "temp portable link missing or not symlink: $harness/$skill ($link)"
    continue
  fi
  got="$(readlink "$link")"
  if [[ "$got" != "$want" ]]; then
    err "temp readlink $harness/$skill expected '$want' got '$got'"
    continue
  fi
  if [[ ! -e "$link/SKILL.md" ]]; then
    err "temp resolved SKILL.md missing: $harness/$skill"
    continue
  fi
  if ! cmp -s "$link/SKILL.md" "$DEST/.agents/skills/${skill}/SKILL.md"; then
    err "temp SKILL.md mismatch vs canonical: $harness/$skill"
    continue
  fi
  pass "temp portable ok: $harness/$skill"
done < <(jq -r '.skills | to_entries[] | .key as $s | .value[] | "\($s)\t\(.)"' "$MANIFEST")

check_primary_global_live_regressions

bash -n "$ROOT/scripts/check-agent-config-sync.sh" "$ROOT"/scripts/check/*.sh \
  "$ROOT/scripts/apply-guard.sh" "$ROOT/run_before_00-apply-guard.sh" \
  && pass 'bash -n' || err 'bash -n failed'
if [[ -f "$ROOT/dot_local/bin/executable_agent-config-sync" ]]; then
  bash -n "$ROOT/dot_local/bin/executable_agent-config-sync" && pass 'bash -n agent-config-sync' \
    || err 'bash -n agent-config-sync failed'
fi

echo
[[ "$fail" -eq 0 ]] && { echo "PASSED: agent-config-sync checks"; exit 0; }
echo "FAILED: agent-config-sync checks"; exit 1
