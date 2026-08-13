check_sync_command_flow() {
  local flow_source="$TMP/sync-flow-source"
  local flow_home="$TMP/sync-flow home"
  local divergent_home="$TMP/sync-flow-divergent-home"
  local malformed_home="$TMP/sync-flow-malformed-home"
  local failure_home="$TMP/sync-flow-failure-home"
  local flow_log="$TMP/sync-flow.log"
  local flow_stdout="$TMP/sync-flow.out"
  local flow_error="$TMP/sync-flow.err"
  local all_absent_log="$TMP/sync-flow-all-absent.log"
  local all_absent_error="$TMP/sync-flow-all-absent.err"
  local divergent_log="$TMP/sync-flow-divergent.log"
  local malformed_log="$TMP/sync-flow-malformed.log"
  local malformed_error="$TMP/sync-flow-malformed.err"
  local self_update_log="$TMP/sync-flow-self-update.log"
  local self_update_output="$TMP/sync-flow-self-update.out"
  local self_update_error="$TMP/sync-flow-self-update.err"
  local failure_log="$TMP/sync-flow-failure.log"
  local failure_output="$TMP/sync-flow-failure.out"
  local failure_error="$TMP/sync-flow-failure.err"
  local script_marker="$TMP/sync-flow-script-marker"
  local configure_log="$TMP/sync-flow-configure.log"
  local expected_log="$TMP/sync-flow-expected.log"
  local source_path self_update_status second_run_status failure_status
  local dotfiles_origin="$TMP/sync-flow-dotfiles-origin.git"
  local dotfiles_updater="$TMP/sync-flow-dotfiles-updater"
  local memory_origin="$TMP/sync-flow-memory-origin.git"
  local sync_output="$TMP/sync-command.out"
  local sync_error="$TMP/sync-command.err"
  local sync_status before_sync_head after_sync_head origin_head memory_head
  local -a active_source_files=(
    dot_zshrc
    dot_bashrc
    dot_claude/CLAUDE.md
    dot_claude/rules/context7.md
    dot_claude/settings.json
    dot_claude/hooks/executable_decision-audit-gate.sh
    dot_claude/hooks/executable_delegation-gate.sh
    dot_claude/hooks/executable_orchestration-reminder.sh
    dot_agents/skills/model-orchestration/SKILL.md
    dot_codex/AGENTS.md
    dot_codex/agents/architecture-reviewer.toml
    dot_codex/model.json
    dot_codex/ollama-launch.config.toml
    dot_grok/AGENTS.md
    dot_grok/config.toml
    dot_pi/agent/AGENTS.md
    dot_pi/agent/settings.json
    dot_pi/agent/mcp.json
    dot_pi/agent/models.json
    dot_pi/agent/extensions/btw.ts
    dot_pi/agent/extensions/fast-mode.ts
    dot_pi/agent/extensions/model-compaction-threshold.ts
    dot_pi/agent/extensions/decision-audit-gate.ts
    dot_pi/agent/extensions/delegation-gate.ts
    dot_pi/agent/skills/symlink_probe
    dot_omp/agent/AGENTS.md
    dot_omp/agent/config.yml
    dot_omp/agent/mcp.json.tmpl
    dot_omp/agent/extensions/decision-audit-gate.ts
    dot_agents/dot_skill-lock.json
    dot_agents/mcp-targets.json
    dot_agents/skill-targets.json
    dot_agents/doctor-targets.json
    dot_agents/desktop-capture.md
    dot_agents/browser-use.md
    dot_agents/codex-lane-override.md
    dot_agents/private_stripe.env
    dot_agents/skills/probe/SKILL.md
    dot_local/bin/executable_sudo-askpass
    dot_local/bin/executable_pickforge-lanes-mcp
    dot_config/environment.d/50-sudo-askpass.conf.tmpl
    dot_config/environment.d/60-omp.conf
    dot_config/environment.d/70-pi-caffeinate.conf
  )

  mkdir -p "$flow_source/scripts" \
    "$flow_home/.local/bin" "$flow_home/.agents" \
    "$flow_home/.retired-agent-config-probe" \
    "$divergent_home/.local/bin" "$divergent_home/.retired-agent-config-probe" \
    "$divergent_home/.agents" "$malformed_home/.local/bin" \
    "$failure_home/.local/bin"
  cat >"$flow_source/scripts/check-agent-config-sync.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
live=0
strict=0
for arg in "$@"; do
  case "$arg" in
    --check-live-migration) live=1 ;;
    --strict-preflight) strict=1 ;;
    *) exit 64 ;;
  esac
done
if [[ $# -eq 0 ]]; then
  printf '%s\n' source
elif [[ $# -eq 1 && "$live" -eq 1 ]]; then
  printf '%s\n' live
elif [[ $# -eq 2 && "$live" -eq 1 && "$strict" -eq 1 ]]; then
  printf '%s\n' strict
else
  exit 64
fi >>"$SYNC_FLOW_LOG"
EOF
  printf '%s\n' scripts '.config/environment.d/**' >"$flow_source/.chezmoiignore"
  printf '%s\n' \
    .retired-agent-config-probe \
    .absent-retired-agent-config-probe \
    >"$flow_source/.chezmoiremove"
  for source_path in "${active_source_files[@]}"; do
    if [[ "$source_path" == */* ]]; then
      mkdir -p "$flow_source/${source_path%/*}"
    fi
    printf '%s\n' managed >"$flow_source/$source_path"
  done
  printf '%s\n' '../../../.agents/skills/probe' \
    >"$flow_source/dot_pi/agent/skills/symlink_probe"
  printf '%s\n' '{"canonical_root":"~/.agents/skills","harnesses":{"pi":{"skills_root":"~/.pi/agent/skills","source_root":"dot_pi/agent/skills","discovery":"symlink","relative_prefix":"../../../.agents/skills"}},"skills":{"probe":["pi"]}}' \
    >"$flow_source/dot_agents/skill-targets.json"
  printf '%s\n' intended-agent-probe >"$flow_source/dot_agents/mcp-targets.json"
  printf '%s\n' original-unrelated >"$flow_source/dot_unrelated-agent-config-probe"
  install -m 0755 "$ROOT/dot_local/bin/executable_agent-config-sync" \
    "$flow_source/dot_local/bin/executable_agent-config-sync"
  printf '%s\n' '{"state":"original"}' >"$flow_source/dot_agents/dot_skill-lock.json"
  HOME="$flow_home" chezmoi --source "$flow_source" apply --force --no-tty \
    "$flow_home/.unrelated-agent-config-probe" \
    "$flow_home/.agents/.skill-lock.json"
  printf '%s\n' '{"state":"intended"}' >"$flow_source/dot_agents/dot_skill-lock.json"
  cat >"$flow_source/run_after_agent_config_probe.sh" <<'EOF'
#!/usr/bin/env bash
: >"$SYNC_SCRIPT_MARKER"
EOF
  chmod 0755 "$flow_source/run_after_agent_config_probe.sh"
  cat >"$flow_source/run_onchange_after_configure_pickforge_lanes_mcp.sh" <<'EOF'
#!/bin/sh
set -eu
[ -x "$HOME/.local/bin/pickforge-lanes-mcp" ]
printf '%s\n' configured >>"$SYNC_CONFIGURE_LOG"
EOF
  chmod 0755 "$flow_source/run_onchange_after_configure_pickforge_lanes_mcp.sh"
  printf '%s\n' changed-unrelated >"$flow_source/dot_unrelated-agent-config-probe"
  printf '%s\n' retired >"$flow_home/.retired-agent-config-probe/sentinel"
  printf '%s\n' retired >"$divergent_home/.retired-agent-config-probe/sentinel"
  printf '%s\n' divergent >"$divergent_home/.agents/mcp-targets.json"
  for target_home in "$flow_home" "$divergent_home" "$malformed_home" "$failure_home"; do
    install -m 0755 "$ROOT/dot_local/bin/executable_agent-config-sync" \
      "$target_home/.local/bin/agent-config-sync"
  done

  : >"$configure_log"
  if HOME="$flow_home" CHEZMOI_SOURCE_DIR="$flow_source" SYNC_FLOW_LOG="$flow_log" \
    SYNC_SCRIPT_MARKER="$script_marker" SYNC_CONFIGURE_LOG="$configure_log" \
    "$flow_home/.local/bin/agent-config-sync" apply >"$flow_stdout" 2>"$flow_error" \
    && HOME="$flow_home" CHEZMOI_SOURCE_DIR="$flow_source" SYNC_FLOW_LOG="$flow_log" \
      "$flow_home/.local/bin/agent-config-sync" check-live >/dev/null 2>&1; then
    printf '%s\n' source strict live live >"$expected_log"
    if grep -Fxq intended-agent-probe "$flow_home/.agents/mcp-targets.json" \
      && grep -Fxq '{"state":"intended"}' "$flow_home/.agents/.skill-lock.json" \
      && grep -Fxq managed "$flow_home/.agents/browser-use.md" \
      && grep -Fxq managed "$flow_home/.pi/agent/settings.json" \
      && grep -Fxq managed "$flow_home/.pi/agent/extensions/btw.ts" \
      && grep -Fxq managed "$flow_home/.pi/agent/extensions/fast-mode.ts" \
      && grep -Fxq managed "$flow_home/.pi/agent/extensions/model-compaction-threshold.ts" \
      && [[ -L "$flow_home/.pi/agent/skills/probe" ]] \
      && [[ "$(readlink "$flow_home/.pi/agent/skills/probe")" == '../../../.agents/skills/probe' ]] \
      && [[ ! -e "$flow_home/.retired-agent-config-probe" \
        && ! -L "$flow_home/.retired-agent-config-probe" ]] \
      && [[ ! -e "$flow_home/.absent-retired-agent-config-probe" \
        && ! -L "$flow_home/.absent-retired-agent-config-probe" ]] \
      && grep -Fxq original-unrelated "$flow_home/.unrelated-agent-config-probe" \
      && [[ ! -e "$script_marker" ]] \
      && [[ "$(grep -Fxc configured "$configure_log")" -eq 1 ]] \
      && cmp -s "$expected_log" "$flow_log"; then
      pass 'temporary scoped sync updates skill-lock metadata target from source'
      pass 'temporary scoped sync applies browser-use policy target'
      pass 'temporary scoped sync applies curated Pi settings and extension targets'
      pass 'temporary scoped sync removes present retirement and skips absent retirement'
      pass 'temporary sync applies only agent targets and retirements without implicit run scripts'
      pass 'temporary sync invokes managed pickforge-lanes registration once after target apply'
    else
      err 'temporary scoped sync changed an unrelated target, ran a script, or missed agent cleanup'
    fi
    if grep -Eq '^applied: [1-9][0-9]* targets$' "$flow_stdout" \
      && grep -Fq "applied: $flow_home/.agents/mcp-targets.json" "$flow_stdout" \
      && ! grep -Fq 'PASSED:' "$flow_stdout"; then
      pass 'temporary sync reports the nonzero applied target count and written target paths'
    else
      err 'temporary sync apply observability output is missing or misleading'
    fi
    # Only OS-gated targets may be skipped. Naming the unexpected ones turns a
    # policy/fixture drift into a diagnostic instead of a bare count mismatch.
    local unexpected_skips
    unexpected_skips="$(grep -F 'skipping target not managed on this machine' "$flow_error" \
      | grep -Fv '/.config/environment.d/' || true)"
    if [[ ! -e "$flow_home/.config/environment.d/50-sudo-askpass.conf" ]] \
      && [[ "$(grep -Fc '/.config/environment.d/' <<<"$(grep -F 'skipping target not managed on this machine' "$flow_error")")" -eq 3 ]] \
      && [[ -z "$unexpected_skips" ]]; then
      pass 'temporary sync skips chezmoiignore-gated targets instead of aborting apply'
    elif [[ -n "$unexpected_skips" ]]; then
      err "temporary sync skipped non-OS-gated targets absent from the flow fixture: $(sed -E 's/.*machine: //' <<<"$unexpected_skips" | tr '\n' ' ')"
    else
      err 'temporary sync applied or aborted on chezmoiignore-gated environment.d targets'
    fi
  else
    err "temporary scoped sync command apply/check-live flow failed: $(tr '\n' ' ' <"$flow_error")"
  fi

  printf '%s\n' intended-agent-probe-all-retirements-absent \
    >"$flow_source/dot_agents/mcp-targets.json"
  : >"$configure_log"
  if HOME="$flow_home" CHEZMOI_SOURCE_DIR="$flow_source" SYNC_FLOW_LOG="$all_absent_log" \
    SYNC_SCRIPT_MARKER="$script_marker" SYNC_CONFIGURE_LOG="$configure_log" \
    "$flow_home/.local/bin/agent-config-sync" apply >/dev/null 2>"$all_absent_error" \
    && HOME="$flow_home" CHEZMOI_SOURCE_DIR="$flow_source" SYNC_FLOW_LOG="$all_absent_log" \
      "$flow_home/.local/bin/agent-config-sync" check-live >/dev/null 2>&1; then
    printf '%s\n' source strict live live >"$expected_log"
    if grep -Fxq intended-agent-probe-all-retirements-absent \
      "$flow_home/.agents/mcp-targets.json" \
      && [[ ! -e "$flow_home/.retired-agent-config-probe" \
        && ! -L "$flow_home/.retired-agent-config-probe" ]] \
      && [[ ! -e "$flow_home/.absent-retired-agent-config-probe" \
        && ! -L "$flow_home/.absent-retired-agent-config-probe" ]] \
      && [[ ! -e "$script_marker" ]] \
      && [[ "$(grep -Fxc configured "$configure_log")" -eq 1 ]] \
      && cmp -s "$expected_log" "$all_absent_log"; then
      pass 'temporary scoped sync applies active targets when all retirements are absent'
      pass 'temporary scoped sync live check succeeds when all retirements are absent'
    else
      err 'temporary scoped sync missed active apply or live check with all retirements absent'
    fi
  else
    err "temporary scoped sync all-absent retirement flow failed: $(tr '\n' ' ' <"$all_absent_error")"
  fi

  cp "$flow_source/dot_local/bin/executable_agent-config-sync" \
    "$TMP/sync-flow-cli-source.backup"
  printf '\n# fixture self-update marker\n' \
    >>"$flow_source/dot_local/bin/executable_agent-config-sync"
  : >"$configure_log"
  if HOME="$flow_home" CHEZMOI_SOURCE_DIR="$flow_source" SYNC_FLOW_LOG="$self_update_log" \
    SYNC_SCRIPT_MARKER="$script_marker" SYNC_CONFIGURE_LOG="$configure_log" \
    "$flow_home/.local/bin/agent-config-sync" apply \
    >"$self_update_output" 2>"$self_update_error"; then
    self_update_status=0
  else
    self_update_status=$?
  fi
  if [[ "$self_update_status" -eq 75 ]] \
    && grep -Fq 'agent-config-sync updated; re-run apply' "$self_update_error" \
    && [[ ! -s "$self_update_log" ]] \
    && [[ ! -s "$configure_log" ]]; then
    pass 'temporary sync self-updates first and exits 75 before stale code continues'
  else
    err 'temporary sync did not stop after updating its running CLI'
  fi
  : >"$configure_log"
  if HOME="$flow_home" CHEZMOI_SOURCE_DIR="$flow_source" SYNC_FLOW_LOG="$self_update_log" \
    SYNC_SCRIPT_MARKER="$script_marker" SYNC_CONFIGURE_LOG="$configure_log" \
    "$flow_home/.local/bin/agent-config-sync" apply \
    >"$self_update_output" 2>"$self_update_error"; then
    second_run_status=0
  else
    second_run_status=$?
  fi
  if [[ "$second_run_status" -eq 0 ]] \
    && grep -Fxq 'applied: 0 targets' "$self_update_output" \
    && ! grep -Fq 'agent-config-sync updated; re-run apply' "$self_update_error" \
    && [[ "$(grep -Fxc configured "$configure_log")" -eq 1 ]]; then
    pass 'temporary sync second run proceeds and reports a silent no-op explicitly'
  else
    err "temporary sync second run after self-update did not proceed cleanly (status $second_run_status)"
  fi
  cp "$TMP/sync-flow-cli-source.backup" \
    "$flow_source/dot_local/bin/executable_agent-config-sync"

  mv "$flow_source/dot_pi/agent/settings.json" \
    "$flow_source/dot_pi/agent/settings.json.fixture-backup"
  printf '{{ invalid template\n' >"$flow_source/dot_pi/agent/settings.json.tmpl"
  : >"$configure_log"
  if HOME="$failure_home" CHEZMOI_SOURCE_DIR="$flow_source" SYNC_FLOW_LOG="$failure_log" \
    SYNC_SCRIPT_MARKER="$script_marker" SYNC_CONFIGURE_LOG="$configure_log" \
    "$failure_home/.local/bin/agent-config-sync" apply \
    >"$failure_output" 2>"$failure_error"; then
    failure_status=0
  else
    failure_status=$?
  fi
  rm -f "$flow_source/dot_pi/agent/settings.json.tmpl"
  mv "$flow_source/dot_pi/agent/settings.json.fixture-backup" \
    "$flow_source/dot_pi/agent/settings.json"
  if [[ "$failure_status" -eq 74 ]] \
    && grep -Fq 'agent-config-sync: batched chezmoi apply failed' "$failure_error" \
    && ! grep -Fq 'PASSED:' "$failure_output" \
    && ! grep -Fq 'PASSED:' "$failure_error" \
    && [[ ! -s "$configure_log" ]] \
    && [[ "$(tr '\n' ' ' <"$failure_log")" == 'source strict ' ]]; then
    pass 'temporary sync propagates batched apply failure as exit 74 without a false PASSED'
  else
    err "temporary sync masked or misreported a batched apply failure (status $failure_status)"
  fi

  : >"$configure_log"
  if HOME="$divergent_home" CHEZMOI_SOURCE_DIR="$flow_source" SYNC_FLOW_LOG="$divergent_log" \
    SYNC_SCRIPT_MARKER="$script_marker" SYNC_CONFIGURE_LOG="$configure_log" \
    "$divergent_home/.local/bin/agent-config-sync" apply >/dev/null 2>&1; then
    err 'temporary scoped sync overwrote an unmanaged active target'
  elif grep -Fxq divergent "$divergent_home/.agents/mcp-targets.json" \
    && [[ -e "$divergent_home/.retired-agent-config-probe" ]] \
    && [[ ! -e "$script_marker" ]] \
    && [[ ! -s "$configure_log" ]] \
    && [[ "$(tr '\n' ' ' <"$divergent_log")" == 'source strict ' ]]; then
    pass 'temporary scoped sync blocks unmanaged active targets before retirement apply'
  else
    err 'temporary scoped sync unmanaged-target preflight was not atomic'
  fi

  for malformed in '' '/absolute-retirement'; do
    printf '%s\n' "$malformed" >"$flow_source/.chezmoiremove"
    rm -f "$malformed_log" "$malformed_error" "$script_marker"
    : >"$configure_log"
    if HOME="$malformed_home" CHEZMOI_SOURCE_DIR="$flow_source" \
      SYNC_FLOW_LOG="$malformed_log" SYNC_SCRIPT_MARKER="$script_marker" \
      SYNC_CONFIGURE_LOG="$configure_log" \
      "$malformed_home/.local/bin/agent-config-sync" apply \
      >/dev/null 2>"$malformed_error"; then
      err "temporary scoped sync accepted malformed retirement entry: ${malformed:-empty}"
    elif [[ ! -e "$script_marker" ]] \
      && [[ ! -s "$configure_log" ]] \
      && [[ "$(tr '\n' ' ' <"$malformed_log")" == 'source strict ' ]] \
      && grep -Fq 'retirement list' "$malformed_error"; then
      pass "temporary scoped sync rejects malformed retirement entry: ${malformed:-empty}"
    else
      err "temporary scoped sync did not fail closed on malformed retirement entry: ${malformed:-empty}"
    fi
  done
  printf '%s\n' \
    .retired-agent-config-probe \
    .absent-retired-agent-config-probe \
    >"$flow_source/.chezmoiremove"

  git -C "$flow_source" init -b main >/dev/null
  git -C "$flow_source" config user.name 'Fixture User'
  git -C "$flow_source" config user.email fixture@example.invalid
  git -C "$flow_source" add .
  git -C "$flow_source" commit -m 'chore: initialize sync fixture' >/dev/null
  git init --bare "$dotfiles_origin" >/dev/null
  git -C "$flow_source" remote add origin "$dotfiles_origin"
  git -C "$flow_source" push -u origin main >/dev/null
  git -C "$dotfiles_origin" symbolic-ref HEAD refs/heads/main
  install -m 0755 "$flow_source/dot_local/bin/executable_agent-config-sync" \
    "$flow_home/.local/bin/agent-config-sync"
  git clone "$dotfiles_origin" "$dotfiles_updater" >/dev/null 2>&1
  git -C "$dotfiles_updater" config user.name 'Fixture User'
  git -C "$dotfiles_updater" config user.email fixture@example.invalid

  mkdir -p "$flow_home/AgentMemory"
  git -C "$flow_home/AgentMemory" init -b main >/dev/null
  git -C "$flow_home/AgentMemory" config user.name 'Fixture User'
  git -C "$flow_home/AgentMemory" config user.email fixture@example.invalid
  printf '%s\n' memory >"$flow_home/AgentMemory/memory.txt"
  git -C "$flow_home/AgentMemory" add memory.txt
  git -C "$flow_home/AgentMemory" commit -m 'chore: initialize memory fixture' >/dev/null
  git init --bare "$memory_origin" >/dev/null
  git -C "$flow_home/AgentMemory" remote add origin "$memory_origin"
  git -C "$flow_home/AgentMemory" push -u origin main >/dev/null
  git -C "$memory_origin" symbolic-ref HEAD refs/heads/main

  before_sync_head="$(git -C "$flow_source" rev-parse HEAD)"
  printf '%s\n' upstream >"$dotfiles_updater/sync-origin-marker"
  git -C "$dotfiles_updater" add sync-origin-marker
  git -C "$dotfiles_updater" commit -m 'test: advance sync origin' >/dev/null
  git -C "$dotfiles_updater" push origin main >/dev/null
  origin_head="$(git -C "$dotfiles_origin" rev-parse refs/heads/main)"
  : >"$flow_log"
  : >"$configure_log"
  if HOME="$flow_home" CHEZMOI_SOURCE_DIR="$flow_source" SYNC_FLOW_LOG="$flow_log" \
    SYNC_SCRIPT_MARKER="$script_marker" SYNC_CONFIGURE_LOG="$configure_log" \
    "$flow_home/.local/bin/agent-config-sync" sync >"$sync_output" 2>"$sync_error"; then
    sync_status=0
  else
    sync_status=$?
  fi
  after_sync_head="$(git -C "$flow_source" rev-parse HEAD)"
  memory_head="$(git -C "$flow_home/AgentMemory" rev-parse --short HEAD)"
  if [[ "$sync_status" -eq 0 && "$before_sync_head" != "$after_sync_head" \
    && "$after_sync_head" == "$origin_head" \
    && -f "$flow_source/sync-origin-marker" ]]; then
    pass 'sync fast-forwards the dotfiles source to a new origin commit'
  else
    err "sync did not fast-forward the dotfiles source (status $sync_status)"
  fi
  if [[ "$(tr '\n' ' ' <"$flow_log")" == 'source strict live ' \
    && "$(grep -Fxc configured "$configure_log")" -eq 1 ]] \
    && grep -Fq "sync: dotfiles=$(git -C "$flow_source" rev-parse --short HEAD) AgentMemory=$memory_head apply=ok" "$sync_output"; then
    pass 'sync runs apply and reports pulled commits with a successful result'
  else
    err 'sync did not run apply or emit its commit/result summary'
  fi

  printf '%s\n' dirty >>"$flow_home/AgentMemory/memory.txt"
  memory_head="$(git -C "$flow_home/AgentMemory" rev-parse HEAD)"
  : >"$flow_log"
  : >"$configure_log"
  if HOME="$flow_home" CHEZMOI_SOURCE_DIR="$flow_source" SYNC_FLOW_LOG="$flow_log" \
    SYNC_SCRIPT_MARKER="$script_marker" SYNC_CONFIGURE_LOG="$configure_log" \
    "$flow_home/.local/bin/agent-config-sync" sync >"$sync_output" 2>"$sync_error"; then
    sync_status=0
  else
    sync_status=$?
  fi
  if [[ "$sync_status" -eq 0 \
    && "$(git -C "$flow_home/AgentMemory" rev-parse HEAD)" == "$memory_head" \
    && -n "$(git -C "$flow_home/AgentMemory" status --porcelain)" \
    && "$(tr '\n' ' ' <"$flow_log")" == 'source strict live ' \
    && "$(grep -Fxc configured "$configure_log")" -eq 1 ]] \
    && grep -Fq 'AgentMemory has local changes; skipping pull' "$sync_error" \
    && grep -Fq 'AgentMemory=dirty apply=ok' "$sync_output"; then
    pass 'sync preserves dirty AgentMemory, warns, and still applies successfully'
  else
    err "sync mishandled dirty AgentMemory (status $sync_status)"
  fi

  printf '%s\n' second-upstream >"$dotfiles_updater/sync-origin-marker-2"
  git -C "$dotfiles_updater" add sync-origin-marker-2
  git -C "$dotfiles_updater" commit -m 'test: advance origin past dirty source' >/dev/null
  git -C "$dotfiles_updater" push origin main >/dev/null
  origin_head="$(git -C "$dotfiles_origin" rev-parse refs/heads/main)"
  before_sync_head="$(git -C "$flow_source" rev-parse HEAD)"
  printf '%s\n' local-dirty >>"$flow_source/dot_unrelated-agent-config-probe"
  : >"$flow_log"
  : >"$configure_log"
  if HOME="$flow_home" CHEZMOI_SOURCE_DIR="$flow_source" SYNC_FLOW_LOG="$flow_log" \
    SYNC_SCRIPT_MARKER="$script_marker" SYNC_CONFIGURE_LOG="$configure_log" \
    "$flow_home/.local/bin/agent-config-sync" sync >"$sync_output" 2>"$sync_error"; then
    sync_status=0
  else
    sync_status=$?
  fi
  after_sync_head="$(git -C "$flow_source" rev-parse HEAD)"
  if [[ "$sync_status" -eq 76 && "$after_sync_head" == "$before_sync_head" \
    && "$after_sync_head" != "$origin_head" \
    && ! -s "$flow_log" && ! -s "$configure_log" ]] \
    && grep -Fq 'dotfiles source has local changes' "$sync_error"; then
    pass 'sync rejects dirty dotfiles with exit 76 before pull or apply'
  else
    err "sync did not fail closed on dirty dotfiles (status $sync_status)"
  fi
}

check_primary_global_live_regressions() {
  local target log log_name
  local -a drift_targets=(
    "$DEST/.claude/CLAUDE.md"
    "$DEST/.claude/settings.json"
    "$DEST/.claude/rules/context7.md"
    "$DEST/.zshrc"
    "$DEST/.bashrc"
  )

  if (fail=0; check_live_primary_global_targets "$DEST" >/dev/null; [[ "$fail" -eq 0 ]]); then
    pass 'temporary primary global live targets include Claude rules and skills'
  else
    err 'temporary primary global live baseline was rejected'
    return
  fi

  for target in "${drift_targets[@]}"; do
    printf '\nmanaged-live-drift\n' >>"$target"
    log_name="${target#"$DEST/"}"
    log_name="${log_name//\//_}"
    log="$TMP/primary-global-live-${log_name}.log"
    if (fail=0; check_live_primary_global_targets "$DEST"; [[ "$fail" -ne 0 ]]) \
      >"$log" 2>&1; then
      pass "temporary primary global live drift rejected: ${target#"$DEST/"}"
    else
      err "temporary primary global live drift accepted: ${target#"$DEST/"}"
    fi
    if ! chezmoi "${TMP_SRC[@]}" --destination "$DEST" apply --force --no-tty "$target"; then
      err "temporary primary global target restore failed: ${target#"$DEST/"}"
      return
    fi
  done
}

