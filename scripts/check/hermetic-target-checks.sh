TARGETS=(
  "$DEST/.zshrc" "$DEST/.bashrc"
  "$DEST/.claude/CLAUDE.md"
  "$DEST/.claude/agents/final-reviewer.md"
  "$DEST/.claude/agents/final-reviewer-high.md"
  "$DEST/.claude/settings.json"
  "$DEST/.codex/AGENTS.md"
  "$DEST/.grok/AGENTS.md" "$DEST/.pi/agent/AGENTS.md" "$DEST/.omp/agent/AGENTS.md"
  "$DEST/.omp/agent/config.yml" "$DEST/.omp/agent/mcp.json"
  "$DEST/.local/bin/agent-config-sync"
  "$DEST/.local/bin/agent-harness-preflight"
  "$DEST/.local/bin/pickforge-lanes-mcp"
  "$DEST/.config/agent-config-sync/doctor.json"
  "$DEST/.agents/.skill-lock.json"
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
  ! grep -Fq 'Projects/Personal/.agent-safety/bin:$PATH' "$DEST/.zshrc" \
    && pass 'temp zsh profile excludes retired Personal GitHub guard PATH' \
    || err 'temp zsh profile still enables Personal GitHub guard PATH'
  ! grep -Fq 'claude-default' "$DEST/.zshrc" \
    && ! grep -Fq 'claude-personal' "$DEST/.zshrc" \
    && pass 'temp zsh profile uses unrestricted global claude wrapper' \
    || err 'temp zsh profile still routes through split-profile launchers'
  grep -Fq 'Never expose, commit, or send secrets or private production data.' "$DEST/.claude/CLAUDE.md" \
    && pass 'temp global Claude profile applied' \
    || err 'temp global Claude profile missing hard limits'
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
  cmp -s "$DEST/.agents/.skill-lock.json" "$SKILL_LOCK" \
    && pass 'temp skill lock applied' \
    || err 'temp skill lock apply mismatch'
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

PENDING_DIR="$TMP/managed-pending-directory"
mkdir -p "$PENDING_DIR"
printf '%s\n' managed >"$PENDING_DIR/SKILL.md"
if managed_directory_unchanged "$PENDING_DIR"; then
  pass 'managed pending directory accepts unchanged prior target'
else
  err 'managed pending directory rejected unchanged prior target'
fi
printf '%s\n' divergent >>"$PENDING_DIR/SKILL.md"
if managed_directory_unchanged "$PENDING_DIR"; then
  err 'managed pending directory accepted divergent target'
else
  pass 'managed pending directory rejects divergent target'
fi
printf '%s\n' managed >"$PENDING_DIR/SKILL.md"
ln -s "$PENDING_FILE" "$PENDING_DIR/unmanaged-link"
if managed_directory_unchanged "$PENDING_DIR"; then
  err 'managed pending directory accepted unmanaged symlink'
else
  pass 'managed pending directory rejects unmanaged symlink'
fi

PENDING_PI_HOME="$TMP/managed-pending-pi-home"
mkdir -p "$PENDING_PI_HOME/.pi/agent"
printf '%s\n' '{"enabledModels":["xai/grok-4.5"]}' >"$PENDING_PI_HOME/.pi/agent/settings.json"
read -r PENDING_HASH _ < <(sha256sum "$PENDING_PI_HOME/.pi/agent/settings.json")
if (HOME="$PENDING_PI_HOME"; STRICT_PREFLIGHT=1; fail=0; \
  check_live_pi_enabled_models >/dev/null 2>&1; [[ "$fail" -eq 0 ]]); then
  pass 'strict live preflight accepts unchanged managed Pi model migration drift'
else
  err 'strict live preflight rejected unchanged managed Pi model migration drift'
fi
if (HOME="$PENDING_PI_HOME"; STRICT_PREFLIGHT=0; fail=0; \
  check_live_pi_enabled_models >/dev/null 2>&1; [[ "$fail" -ne 0 ]]); then
  pass 'normal live check rejects stale Pi model routing'
else
  err 'normal live check accepted stale Pi model routing'
fi
printf '%s\n' divergent >>"$PENDING_PI_HOME/.pi/agent/settings.json"
if (HOME="$PENDING_PI_HOME"; STRICT_PREFLIGHT=1; fail=0; \
  check_live_pi_enabled_models >/dev/null 2>&1; [[ "$fail" -ne 0 ]]); then
  pass 'strict live preflight rejects unmanaged Pi model drift'
else
  err 'strict live preflight accepted unmanaged Pi model drift'
fi

jq '.defaultThinkingLevel = "high"
  | .enabledModels = [
      "anthropic/claude-fable-5",
      "anthropic/claude-opus-4-8",
      "anthropic/claude-sonnet-5",
      "ollama/glm-5.2:cloud",
      "openai-codex/gpt-6-astra",
      "xai/grok-4.5"
    ]' "$ROOT/dot_pi/agent/settings.json" >"$PENDING_PI_HOME/.pi/agent/settings.json"
cp "$PENDING_PI_HOME/.pi/agent/settings.json" "$PENDING_PI_HOME/settings-exact-migration.json"
PENDING_HASH='0000000000000000000000000000000000000000000000000000000000000000'
if (HOME="$PENDING_PI_HOME"; STRICT_PREFLIGHT=1; fail=0; \
  check_live_pi_enabled_models >/dev/null 2>&1; [[ "$fail" -eq 0 ]]); then
  pass 'strict live preflight accepts the exact legacy Pi settings cutover'
else
  err 'strict live preflight rejected the exact legacy Pi settings cutover'
fi
jq '.enabledModels += ["unexpected/provider-model"]' \
  "$PENDING_PI_HOME/.pi/agent/settings.json" >"$PENDING_PI_HOME/settings-divergent.json"
mv "$PENDING_PI_HOME/settings-divergent.json" "$PENDING_PI_HOME/.pi/agent/settings.json"
if (HOME="$PENDING_PI_HOME"; STRICT_PREFLIGHT=1; fail=0; \
  check_live_pi_enabled_models >/dev/null 2>&1; [[ "$fail" -ne 0 ]]); then
  pass 'strict live preflight rejects extra Pi model drift during cutover'
else
  err 'strict live preflight accepted extra Pi model drift during cutover'
fi

jq '.theme = "unexpected"' "$ROOT/dot_pi/agent/settings.json" \
  >"$PENDING_PI_HOME/.pi/agent/settings.json"
if (HOME="$PENDING_PI_HOME"; STRICT_PREFLIGHT=1; fail=0; \
  check_live_pi_enabled_models >/dev/null 2>&1; [[ "$fail" -ne 0 ]]); then
  pass 'strict live preflight rejects unrelated drift after Grok 4.6 is selected'
else
  err 'strict live preflight accepted unrelated drift after Grok 4.6 was selected'
fi

cat "$PENDING_PI_HOME/settings-exact-migration.json" \
  "$PENDING_PI_HOME/settings-exact-migration.json" \
  >"$PENDING_PI_HOME/.pi/agent/settings.json"
if (HOME="$PENDING_PI_HOME"; STRICT_PREFLIGHT=1; fail=0; \
  check_live_pi_enabled_models >/dev/null 2>&1; [[ "$fail" -ne 0 ]]); then
  pass 'strict live preflight rejects concatenated Pi settings documents'
else
  err 'strict live preflight accepted concatenated Pi settings documents'
fi
unset -f chezmoi

# OpenCode drift guard against real chezmoi applied state. Apply is gated on the
# strict preflight exactly as agent-config-sync orders it.
OPENCODE_ROOT="$TMP/opencode-source"
OPENCODE_HOME="$TMP/opencode-home"
OPENCODE_STATE="$TMP/opencode-state.boltdb"
OPENCODE_SOURCE="$OPENCODE_ROOT/dot_config/opencode/private_opencode.jsonc"
OPENCODE_LIVE="$OPENCODE_HOME/.config/opencode/opencode.jsonc"
mkdir -p "${OPENCODE_SOURCE%/*}" "${OPENCODE_LIVE%/*}"
cp "$ROOT/dot_config/opencode/private_opencode.jsonc" "$OPENCODE_SOURCE"

opencode_gated_apply() {
  (
    HOME="$OPENCODE_HOME"; ROOT="$OPENCODE_ROOT"; STRICT_PREFLIGHT=1; fail=0
    chezmoi() { command chezmoi --persistent-state "$OPENCODE_STATE" "$@"; }
    check_live_opencode_config >/dev/null 2>&1
    [[ "$fail" -eq 0 ]] || exit 1
    chezmoi -S "$OPENCODE_ROOT" -D "$OPENCODE_HOME" apply --force --no-tty -- "$OPENCODE_LIVE" \
      >/dev/null 2>&1 || exit 2
  )
}

opencode_blocks_without_write() {
  local label="$1" before after status=0
  read -r before _ < <(sha256sum "$OPENCODE_LIVE")
  opencode_gated_apply || status=$?
  if [[ "$status" -ne 1 ]]; then
    err "OpenCode preflight did not block $label (status $status)"
  else
    read -r after _ < <(sha256sum "$OPENCODE_LIVE")
    [[ "$before" == "$after" ]] \
      && pass "OpenCode preflight blocks $label without writing" \
      || err "OpenCode preflight wrote over $label"
  fi
}

opencode_gated_apply && cmp -s "$OPENCODE_LIVE" "$OPENCODE_SOURCE" \
  && pass 'OpenCode first apply into an absent target succeeds' \
  || err 'OpenCode first apply into an absent target failed'

jq '.mcp.fixture = {type: "remote", url: "http://127.0.0.1:1/mcp", enabled: false}' \
  "$ROOT/dot_config/opencode/private_opencode.jsonc" >"$OPENCODE_SOURCE"
opencode_gated_apply && cmp -s "$OPENCODE_LIVE" "$OPENCODE_SOURCE" \
  && pass 'OpenCode source update applies over the unchanged applied config' \
  || err 'OpenCode source update was blocked over the unchanged applied config'

jq '.mcp.user = {type: "local", command: ["user-mcp"], enabled: true}' "$OPENCODE_LIVE" \
  >"$OPENCODE_LIVE.new" && mv "$OPENCODE_LIVE.new" "$OPENCODE_LIVE"
opencode_blocks_without_write 'a later live MCP addition'
cp "$OPENCODE_SOURCE" "$OPENCODE_LIVE"
jq '.plugin = ["user-plugin"]' "$OPENCODE_LIVE" >"$OPENCODE_LIVE.new" \
  && mv "$OPENCODE_LIVE.new" "$OPENCODE_LIVE"
jq '.mcp.fixture.enabled = true' "$ROOT/dot_config/opencode/private_opencode.jsonc" >"$OPENCODE_SOURCE"
opencode_blocks_without_write 'a later live plugin addition during a source update'

rm -f "$OPENCODE_STATE"
opencode_blocks_without_write 'an unmanaged target without applied state'
printf 'not-a-bolt-database\n' >"$OPENCODE_STATE"
opencode_blocks_without_write 'a target with unreadable applied state'

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
