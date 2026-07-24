TARGETS=(
  "$DEST/.zshrc" "$DEST/.bashrc"
  "$DEST/.claude/CLAUDE.md"
  "$DEST/.claude/rules/context7.md" "$DEST/.claude/settings.json"
  "$DEST/.claude/skills/audit-report"
  "$DEST/.claude/skills/kickoff/SKILL.md"
  "$DEST/.claude/skills/model-runners"
  "$DEST/.claude/skills/ship-pr/SKILL.md"
  "$DEST/.claude/skills/pickgauge-usage/SKILL.md"
  "$DEST/.claude/skills/plan-issue/SKILL.md"
  "$DEST/.codex/AGENTS.md"
  "$DEST/.grok/AGENTS.md" "$DEST/.pi/agent/AGENTS.md" "$DEST/.omp/agent/AGENTS.md"
  "$DEST/.omp/agent/config.yml" "$DEST/.omp/agent/mcp.json" "$DEST/.omp/agent/agents"
  "$DEST/.hermes/SOUL.md"
  "$DEST/.local/bin/agent-config-sync"
  "$DEST/.local/bin/pickforge-lanes-mcp"
  "$DEST/.claude/skills/multi-model-lanes"
  "$DEST/.pi/agent/skills/multi-model-lanes"
  "$DEST/.agents/.skill-lock.json"
  "$DEST/.agents/skill-targets.json"
  "$DEST/.agents/mcp-targets.json"
)
EXPECTED=(
  dot_zshrc.tmpl dot_bashrc
  dot_claude/CLAUDE.md.tmpl
  dot_claude/rules/context7.md dot_claude/settings.json.tmpl
  dot_claude/skills/symlink_audit-report
  dot_claude/skills/kickoff/SKILL.md
  dot_claude/skills/symlink_model-runners
  dot_claude/skills/ship-pr/SKILL.md
  dot_claude/skills/pickgauge-usage/SKILL.md
  dot_claude/skills/plan-issue/private_SKILL.md
  dot_codex/AGENTS.md.tmpl
  dot_grok/AGENTS.md.tmpl dot_pi/agent/AGENTS.md.tmpl dot_omp/agent/AGENTS.md.tmpl
  dot_omp/agent/config.yml dot_omp/agent/mcp.json.tmpl dot_omp/agent/agents
  private_dot_hermes/SOUL.md.tmpl
  dot_local/bin/executable_agent-config-sync
  dot_local/bin/executable_pickforge-lanes-mcp
  dot_claude/skills/symlink_multi-model-lanes
  dot_pi/agent/skills/symlink_multi-model-lanes
  dot_agents/dot_skill-lock.json
  dot_agents/skill-targets.json
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

mkdir -p "$DEST/.grok" "$DEST/.hermes" \
  "$DEST/.local/bin" \
  "$DEST/.claude/rules" \
  "$DEST/.claude/skills/kickoff" \
  "$DEST/.claude/skills/ship-pr" \
  "$DEST/.claude/skills/pickgauge-usage" \
  "$DEST/.claude/skills/plan-issue" \
  "$DEST/.codex/skills/ship-pr" \
  "$DEST/.grok/skills" \
  "$DEST/.pi/agent/skills" "$DEST/.omp/agent/skills" \
  "$DEST/.hermes/skills" "$DEST/.agents/skills"
ln -s ../.codex/AGENTS.md "$DEST/.grok/AGENTS.md"
printf '%s\n' 'You are Hermes Agent, an intelligent AI assistant created by Nous Research.' >"$DEST/.hermes/SOUL.md"

if ! chezmoi "${TMP_SRC[@]}" --destination "$DEST" apply "$DEST/.agents/skills" "${TARGETS[@]}"; then
  err 'temp seed apply (canonical skills / adapters) failed'
else
  ! grep -Fq 'Projects/Personal/.agent-safety/bin:$PATH' "$DEST/.zshrc" \
    && pass 'temp zsh profile excludes retired Personal GitHub guard PATH' \
    || err 'temp zsh profile still enables Personal GitHub guard PATH'
  ! grep -Fq 'claude-default' "$DEST/.zshrc" \
    && ! grep -Fq 'claude-personal' "$DEST/.zshrc" \
    && pass 'temp zsh profile uses unrestricted global claude wrapper' \
    || err 'temp zsh profile still routes through split-profile launchers'
  grep -Fq '## Claude model orchestration' "$DEST/.claude/CLAUDE.md" \
    && pass 'temp global Claude profile applied' \
    || err 'temp global Claude profile missing full orchestration'
  [[ ! -e "$DEST/.claude-personal" ]] \
    && pass 'temp destination has no portable Claude profile tree' \
    || err 'temp destination still creates portable Claude profile tree'
  [[ ! -e "$DEST/.config/agent-profiles" ]] \
    && pass 'temp destination has no agent-profiles role tree' \
    || err 'temp destination still creates agent-profiles role tree'
  [[ ! -e "$DEST/Projects/Personal/.codex" && ! -e "$DEST/Projects/Personal/.agent-safety" ]] \
    && pass 'temp destination has no Personal Codex or agent-safety trees' \
    || err 'temp destination still creates Personal Codex or agent-safety trees'
  [[ -x "$DEST/.local/bin/agent-config-sync" ]] \
    && bash -n "$DEST/.local/bin/agent-config-sync" \
    && pass 'temp agent-config-sync applied' \
    || err 'temp agent-config-sync invalid'
  [[ ! -L "$DEST/.grok/AGENTS.md" ]] && grep -q '^# Personal Grok Notes' "$DEST/.grok/AGENTS.md" \
    && pass 'temp migration replaces Grok symlink safely' || err 'temp Grok symlink migration failed'
  grep -q '^# Hermes' "$DEST/.hermes/SOUL.md" && grep -Fq "$HOME/AgentMemory" "$DEST/.hermes/SOUL.md" \
    && pass 'temp migration replaces default Hermes SOUL safely' || err 'temp Hermes SOUL migration failed'
  grep -q '^# Personal OMP Notes' "$DEST/.omp/agent/AGENTS.md" \
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
  if [[ -d "$DEST/.omp/agent/agents" && ! -L "$DEST/.omp/agent/agents" ]]; then
    pass 'temp OMP agent override directory applied'
  else
    err 'temp OMP agent override directory apply mismatch'
  fi
  for role in task reviewer; do
    validate_omp_agent_override "$role" "$DEST/.omp/agent/agents/${role}.md"
    if [[ -f "$DEST/.omp/agent/agents/${role}.md" ]] \
      && cmp -s "$DEST/.omp/agent/agents/${role}.md" "$OMP_AGENT_OVERRIDES_DIR/${role}.md"; then
      pass "temp OMP ${role} override matches canonical source"
    else
      err "temp OMP ${role} override apply mismatch"
    fi
  done
  cmp -s "$DEST/.agents/.skill-lock.json" "$SKILL_LOCK" \
    && pass 'temp skill lock applied' \
    || err 'temp skill lock apply mismatch'
fi

if [[ -d "$DEST/.agents/skills/context7-mcp" ]]; then
  mkdir -p "$DEST/.claude/skills"
  rm -rf "$DEST/.claude/skills/context7-mcp"
  cp -a "$DEST/.agents/skills/context7-mcp" "$DEST/.claude/skills/context7-mcp"
  if dirs_identical "$DEST/.claude/skills/context7-mcp" "$DEST/.agents/skills/context7-mcp"; then
    pass 'seeded identical Context7 directory: .claude/skills'
  else
    err 'failed to seed Context7 directory: .claude/skills'
  fi
else
  err 'canonical context7-mcp missing after seed apply'
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

PENDING_FILE="$TMP/managed-pending-drift"
printf '%s\n' managed >"$PENDING_FILE"
read -r PENDING_HASH _ < <(sha256sum "$PENDING_FILE")
chezmoi() {
  if [[ "$1" == state && "$2" == get ]]; then
    printf '{"contentsSHA256":"%s"}\n' "$PENDING_HASH"
  else
    command chezmoi "$@"
  fi
}
if managed_regular_file_unchanged "$PENDING_FILE"; then
  pass 'managed pending drift accepts unchanged prior target'
else
  err 'managed pending drift rejected unchanged prior target'
fi
printf '%s\n' divergent >>"$PENDING_FILE"
if managed_regular_file_unchanged "$PENDING_FILE"; then
  err 'managed pending drift accepted divergent target'
else
  pass 'managed pending drift rejects divergent target'
fi
unset -f chezmoi

bash -n "$ROOT/scripts/check-agent-config-sync.sh" "$ROOT"/scripts/check/*.sh \
  && pass 'bash -n' || err 'bash -n failed'
if [[ -f "$ROOT/dot_local/bin/executable_agent-config-sync" ]]; then
  bash -n "$ROOT/dot_local/bin/executable_agent-config-sync" && pass 'bash -n agent-config-sync' \
    || err 'bash -n agent-config-sync failed'
  grep -Fq 'preflight_unmanaged_targets' "$ROOT/dot_local/bin/executable_agent-config-sync" \
    && pass 'agent-config-sync protects unmanaged first-apply targets' \
    || err 'agent-config-sync missing unmanaged-target preflight'
  grep -Fq 'filter_ignored_targets "${active_targets[@]}"' "$ROOT/dot_local/bin/executable_agent-config-sync" \
    && grep -Fq 'chezmoi "${SRC[@]}" apply --verbose --force --no-tty -- "${apply_targets[@]}"' \
      "$ROOT/dot_local/bin/executable_agent-config-sync" \
    && pass 'agent-config-sync applies only scoped active and retirement targets' \
    || err 'agent-config-sync missing scoped active/retirement apply'
  ! grep -Eq '^known_legacy_model_skill\(\)' "$ROOT/dot_local/bin/executable_agent-config-sync" \
    && ! grep -REq '^known_legacy_model_skill\(\)' \
      "$ROOT/scripts/check-agent-config-sync.sh" "$ROOT/scripts/check" \
    && pass 'obsolete legacy model skill hash helpers removed' \
    || err 'obsolete legacy model skill hash helper remains'
  ! grep -Eq 'LIVE_PROFILE_ROLE|PROFILE_ROLE|agentProfile|require-portable-links|bootstrap_real_gh|remove_main_profile_paths|claude-personal' \
    "$ROOT/dot_local/bin/executable_agent-config-sync" \
    && pass 'agent-config-sync excludes split-profile orchestration' \
    || err 'agent-config-sync still contains split-profile orchestration'
fi

echo
[[ "$fail" -eq 0 ]] && { echo "PASSED: agent-config-sync checks"; exit 0; }
echo "FAILED: agent-config-sync checks"; exit 1
