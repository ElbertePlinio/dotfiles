# Behavior fixtures for scripts/apply-guard.sh and the agent-config-sync CLI.
# Each chezmoi run gets a scratch HOME and scratch XDG directories. HOME alone
# is not enough: chezmoi follows XDG_CONFIG_HOME to its config and state file.

fixture_env() {
  local home="$1"
  shift
  HOME="$home" XDG_CONFIG_HOME="$home/.config" XDG_CACHE_HOME="$home/.cache" \
    XDG_DATA_HOME="$home/.local/share" XDG_STATE_HOME="$home/.local/state" "$@"
}

new_fixture_source() {
  local src="$1"
  mkdir -p "$src/scripts"
  cp "$ROOT/scripts/apply-guard.sh" "$src/scripts/apply-guard.sh"
  cp "$ROOT/run_before_00-apply-guard.sh" "$src/run_before_00-apply-guard.sh"
  printf '%s\n' scripts >"$src/.chezmoiignore"
}

check_apply_guard() {
  local src="$TMP/guard-source" home="$TMP/guard home" log="$TMP/guard.log"
  local -a cz=(chezmoi --source "$src" --destination "$home")

  new_fixture_source "$src"
  mkdir -p "$src/dot_skills" "$src/private_dot_box" "$home"
  printf '%s\n' one >"$src/dot_edited"
  printf '%s\n' one >"$src/dot_other"
  printf '%s\n' '../.agents/kick' >"$src/dot_skills/symlink_kick"

  if fixture_env "$home" "${cz[@]}" apply --force --no-tty >"$log" 2>&1 \
    && grep -Fxq one "$home/.edited" && [[ -L "$home/.skills/kick" ]]; then
    pass 'apply guard allows a first apply into an empty home'
  else
    err "apply guard blocked a first apply: $(tr '\n' ' ' <"$log")"
    return
  fi

  printf '%s\n' local >"$home/.edited"
  printf '%s\n' two >"$src/dot_edited"
  printf '%s\n' two >"$src/dot_other"
  if ! fixture_env "$home" "${cz[@]}" apply --force --no-tty >"$log" 2>&1 \
    && grep -Fq "edited since the last apply: $home/.edited" "$log" \
    && grep -Fxq local "$home/.edited" && grep -Fxq one "$home/.other"; then
    pass 'apply guard blocks a live edit before any target is written'
  else
    err "apply guard missed a live edit: $(tr '\n' ' ' <"$log")"
  fi

  if fixture_env "$home" "${cz[@]}" apply --force --no-tty "$home/.edited" >"$log" 2>&1 \
    && grep -Fxq two "$home/.edited" \
    && fixture_env "$home" "${cz[@]}" apply --force --no-tty >"$log" 2>&1 \
    && grep -Fxq two "$home/.other"; then
    pass 'a scoped apply resolves a blocked path and the next full apply proceeds'
  else
    err "scoped resolution or the following full apply failed: $(tr '\n' ' ' <"$log")"
  fi

  printf '%s\n' three >"$src/dot_edited"
  printf '%s\n' three >"$home/.edited"
  if fixture_env "$home" "${cz[@]}" apply --force --no-tty >"$log" 2>&1; then
    pass 'apply guard allows a live edit that already matches the source'
  else
    err "apply guard blocked a converged live edit: $(tr '\n' ' ' <"$log")"
  fi

  printf '%s\n' source >"$src/dot_unowned"
  printf '%s\n' mine >"$home/.unowned"
  if ! fixture_env "$home" "${cz[@]}" apply --force --no-tty >"$log" 2>&1 \
    && grep -Fq "existed before chezmoi managed it: $home/.unowned" "$log" \
    && grep -Fxq mine "$home/.unowned"; then
    pass 'apply guard blocks a pre-existing file that chezmoi never wrote'
  else
    err "apply guard missed a pre-existing file: $(tr '\n' ' ' <"$log")"
  fi
  rm -f "$src/dot_unowned" "$home/.unowned"

  printf '%s\n' '../.agents/new' >"$src/dot_skills/symlink_new"
  mkdir -p "$home/.skills/new"
  printf '%s\n' keep >"$home/.skills/new/SKILL.md"
  if ! fixture_env "$home" "${cz[@]}" apply --force --no-tty >"$log" 2>&1 \
    && grep -Fq "live directory would be replaced: $home/.skills/new" "$log" \
    && grep -Fxq keep "$home/.skills/new/SKILL.md"; then
    pass 'apply guard blocks a live skill directory where the source declares a link'
  else
    err "apply guard missed a live skill directory: $(tr '\n' ' ' <"$log")"
  fi
  rm -rf "$src/dot_skills/symlink_new" "$home/.skills/new"

  mkdir -p "$src/dot_skills/owned"
  printf '%s\n' one >"$src/dot_skills/owned/SKILL.md"
  fixture_env "$home" "${cz[@]}" apply --force --no-tty >"$log" 2>&1 || true
  printf '%s\n' keep >"$home/.skills/owned/notes"
  rm -rf "$src/dot_skills/owned"
  printf '%s\n' '../.agents/owned' >"$src/dot_skills/symlink_owned"
  if ! fixture_env "$home" "${cz[@]}" apply --force --no-tty >"$log" 2>&1 \
    && grep -Fq "live directory would be replaced: $home/.skills/owned" "$log" \
    && grep -Fxq keep "$home/.skills/owned/notes"; then
    pass 'apply guard blocks a link that would replace a directory chezmoi wrote'
  else
    err "apply guard let a link replace a directory: $(tr '\n' ' ' <"$log")"
  fi
  rm -rf "$src/dot_skills/symlink_owned" "$home/.skills/owned"

  rm -f "$home/.other"
  if fixture_env "$home" "${cz[@]}" apply --force --no-tty >"$log" 2>&1 \
    && grep -Fxq two "$home/.other"; then
    pass 'apply guard lets apply recreate a deleted target'
  else
    err "apply guard blocked a deleted target: $(tr '\n' ' ' <"$log")"
  fi

  # Without the default state, only the named state file shows .other as owned.
  mv "$home/.config/chezmoi/chezmoistate.boltdb" "$TMP/guard-state.boltdb"
  printf '%s\n' four >"$src/dot_other"
  if (cd "$TMP" && fixture_env "$home" "${cz[@]}" --persistent-state guard-state.boltdb \
    apply --force --no-tty) >"$log" 2>&1; then
    err 'apply guard accepted a relative --persistent-state path'
  elif grep -Fq 'cannot read the state file' "$log" && grep -Fxq two "$home/.other"; then
    pass 'apply guard rejects a relative --persistent-state path'
  else
    err "apply guard failed a relative state path oddly: $(tr '\n' ' ' <"$log")"
  fi
  if fixture_env "$home" "${cz[@]}" --persistent-state "$TMP/guard-state.boltdb" \
    apply --force --no-tty >"$log" 2>&1 \
    && grep -Fxq four "$home/.other"; then
    pass 'apply guard reads the state file named by --persistent-state'
  else
    err "apply guard ignored --persistent-state: $(tr '\n' ' ' <"$log")"
  fi
  mv "$TMP/guard-state.boltdb" "$home/.config/chezmoi/chezmoistate.boltdb"
  fixture_env "$home" "${cz[@]}" apply --force --no-tty "$home/.other" >"$log" 2>&1 || true

  printf '%s\n' x >"$src/dot_new"$'\n'"line"
  if ! fixture_env "$home" "${cz[@]}" apply --force --no-tty >"$log" 2>&1 \
    && grep -Fq 'a source path contains a newline' "$log"; then
    pass 'apply guard rejects a source name with a newline'
  else
    err "apply guard accepted a source name with a newline: $(tr '\n' ' ' <"$log")"
  fi
  rm -f "$src/dot_new"$'\n'"line"

  chmod 0755 "$home/.box"
  if fixture_env "$home" "${cz[@]}" apply --force --no-tty >"$log" 2>&1 \
    && [[ "$(ls -ld "$home/.box")" == drwx------* ]]; then
    pass 'apply guard lets a managed directory change only its mode'
  else
    err "apply guard blocked a directory mode change: $(tr '\n' ' ' <"$log")"
  fi

  printf '%s\n' retired >"$home/.retired"
  printf '%s\n' .retired >"$src/.chezmoiremove"
  if fixture_env "$home" "${cz[@]}" apply --force --no-tty >"$log" 2>&1 \
    && [[ ! -e "$home/.retired" ]]; then
    pass 'apply guard lets .chezmoiremove delete a retired target'
  else
    err "apply guard blocked a retirement: $(tr '\n' ' ' <"$log")"
  fi

  mkdir -p "$home/.retired-dir"
  printf '%s\n' tool >"$home/.retired-dir/kept.json"
  printf '%s\n' .retired-dir/kept.json >"$home/.config/chezmoi/ignore.local"
  printf '%s\n' .retired-dir >"$src/.chezmoiremove"
  if ! fixture_env "$home" "${cz[@]}" apply --force --no-tty >"$log" 2>&1 \
    && grep -Fq "removal would delete a path in $home/.config/chezmoi/ignore.local: $home/.retired-dir" "$log" \
    && grep -Fxq tool "$home/.retired-dir/kept.json"; then
    pass 'apply guard blocks a removal that would delete a locally ignored path'
  else
    err "apply guard let a removal delete a locally ignored path: $(tr '\n' ' ' <"$log")"
  fi
  rm -rf "$home/.retired-dir" "$home/.config/chezmoi/ignore.local"

  # The removal leaves a remove entry in the state. A file recreated at that
  # path later is still not content chezmoi wrote.
  : >"$src/.chezmoiremove"
  printf '%s\n' mine >"$home/.retired"
  printf '%s\n' source >"$src/dot_retired"
  if ! fixture_env "$home" "${cz[@]}" apply --force --no-tty >"$log" 2>&1 \
    && grep -Fq "$home/.retired" "$log" && grep -Fxq mine "$home/.retired"; then
    pass 'apply guard blocks a file recreated at a removed path'
  else
    err "apply guard missed a file recreated at a removed path: $(tr '\n' ' ' <"$log")"
  fi
}

check_sync_command_flow() {
  local src="$TMP/flow-source" home="$TMP/flow home" log="$TMP/flow.log"
  local out="$TMP/flow.out" errs="$TMP/flow.err" fail_flag="$TMP/flow-fail-source"
  local origin="$TMP/flow-origin.git" updater="$TMP/flow-updater"
  local memory="$TMP/flow home/AgentMemory" memory_origin="$TMP/flow-memory.git"
  local status before after origin_head memory_head

  run_cli() {
    : >"$log"
    if fixture_env "$home" env CHEZMOI_SOURCE_DIR="$src" FLOW_LOG="$log" \
      FLOW_FAIL_SOURCE="$fail_flag" \
      bash "$ROOT/dot_local/bin/executable_agent-config-sync" "$@" >"$out" 2>"$errs"; then
      status=0
    else
      status=$?
    fi
  }
  git_fixture() {
    git -c user.name='Fixture User' -c user.email=fixture@example.invalid \
      -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@"
  }

  new_fixture_source "$src"
  cat >"$src/scripts/check-agent-config-sync.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  '') printf '%s\n' source >>"$FLOW_LOG"; [[ ! -e "$FLOW_FAIL_SOURCE" ]] ;;
  --check-live-migration) printf '%s\n' live >>"$FLOW_LOG" ;;
  *) exit 64 ;;
esac
EOF
  cat >"$src/run_after_flow-probe.sh" <<'EOF'
#!/bin/sh
printf '%s\n' script >>"$FLOW_LOG"
EOF
  printf '%s\n' agent >"$src/dot_agent-probe"
  printf '%s\n' desktop >"$src/dot_desktop-probe"
  printf '%s\n' .retired-probe >"$src/.chezmoiremove"
  mkdir -p "$home/.retired-probe"
  printf '%s\n' retired >"$home/.retired-probe/sentinel"

  run_cli apply
  if [[ "$status" -eq 0 && "$(tr '\n' ' ' <"$log")" == 'source script live ' ]] \
    && grep -Fxq agent "$home/.agent-probe" \
    && grep -Fxq desktop "$home/.desktop-probe" \
    && [[ ! -e "$home/.retired-probe" ]] \
    && grep -Fxq 'applied: 3 targets' "$out" \
    && grep -Fxq "applied: $home/.desktop-probe" "$out"; then
    pass 'apply checks the source, applies every target and script, then checks live state'
  else
    err "apply flow is wrong (status $status): $(tr '\n' ' ' <"$log") $(tr '\n' ' ' <"$errs")"
  fi

  touch "$fail_flag"
  printf '%s\n' agent-2 >"$src/dot_agent-probe"
  run_cli apply
  if [[ "$status" -ne 0 && "$(tr '\n' ' ' <"$log")" == 'source ' ]] \
    && grep -Fxq agent "$home/.agent-probe" \
    && grep -Fq 'source check failed' "$errs"; then
    pass 'apply stops before writing when the source check fails'
  else
    err "apply continued after a failed source check (status $status)"
  fi
  rm -f "$fail_flag"

  printf '%s\n' local >"$home/.agent-probe"
  run_cli apply
  if [[ "$status" -ne 0 && "$(tr '\n' ' ' <"$log")" == 'source ' ]] \
    && grep -Fxq local "$home/.agent-probe" \
    && grep -Fq "edited since the last apply: $home/.agent-probe" "$errs"; then
    pass 'apply stops before writing when the guard finds a live edit'
  else
    err "apply overwrote a live edit or misreported it (status $status)"
  fi
  printf '%s\n' agent-2 >"$home/.agent-probe"

  git_fixture -C "$src" init -q -b main
  git_fixture -C "$src" add -A
  git_fixture -C "$src" commit -q -m 'chore: initialize sync fixture'
  git_fixture init -q --bare "$origin"
  git_fixture -C "$src" remote add origin "$origin"
  git_fixture -C "$src" push -q -u origin main
  git_fixture -C "$origin" symbolic-ref HEAD refs/heads/main
  git_fixture clone -q "$origin" "$updater"
  mkdir -p "$memory"
  git_fixture -C "$memory" init -q -b main
  printf '%s\n' memory >"$memory/memory.txt"
  git_fixture -C "$memory" add memory.txt
  git_fixture -C "$memory" commit -q -m 'chore: initialize memory fixture'
  git_fixture init -q --bare "$memory_origin"
  git_fixture -C "$memory" remote add origin "$memory_origin"
  git_fixture -C "$memory" push -q -u origin main

  before="$(git -C "$src" rev-parse HEAD)"
  printf '%s\n' upstream >"$updater/dot_upstream-probe"
  git_fixture -C "$updater" add dot_upstream-probe
  git_fixture -C "$updater" commit -q -m 'test: advance sync origin'
  git_fixture -C "$updater" push -q origin main
  origin_head="$(git -C "$origin" rev-parse refs/heads/main)"
  run_cli sync
  after="$(git -C "$src" rev-parse HEAD)"
  memory_head="$(git -C "$memory" rev-parse --short HEAD)"
  if [[ "$status" -eq 0 && "$before" != "$after" && "$after" == "$origin_head" \
    && "$(tr '\n' ' ' <"$log")" == 'source script live ' ]] \
    && grep -Fxq upstream "$home/.upstream-probe" \
    && grep -Fq "sync: dotfiles=$(git -C "$src" rev-parse --short HEAD) AgentMemory=$memory_head apply=ok" "$out"; then
    pass 'sync fast-forwards the source, applies it, and reports both commits'
  else
    err "sync did not fast-forward and apply (status $status): $(tr '\n' ' ' <"$errs")"
  fi

  printf '%s\n' dirty >>"$memory/memory.txt"
  memory_head="$(git -C "$memory" rev-parse HEAD)"
  run_cli sync
  if [[ "$status" -eq 0 && "$(git -C "$memory" rev-parse HEAD)" == "$memory_head" \
    && -n "$(git -C "$memory" status --porcelain)" ]] \
    && grep -Fq 'AgentMemory has local changes; skipping pull' "$errs" \
    && grep -Fq 'AgentMemory=dirty apply=ok' "$out"; then
    pass 'sync keeps a dirty AgentMemory, warns, and still applies'
  else
    err "sync mishandled a dirty AgentMemory (status $status)"
  fi

  printf '%s\n' second-upstream >"$updater/dot_upstream-probe"
  git_fixture -C "$updater" commit -q -am 'test: advance origin past dirty source'
  git_fixture -C "$updater" push -q origin main
  before="$(git -C "$src" rev-parse HEAD)"
  printf '%s\n' local-dirty >>"$src/dot_desktop-probe"
  run_cli sync
  if [[ "$status" -eq 76 && "$(git -C "$src" rev-parse HEAD)" == "$before" && ! -s "$log" ]] \
    && grep -Fq 'dotfiles source has local changes' "$errs"; then
    pass 'sync rejects a dirty dotfiles source with exit 76 before pull or apply'
  else
    err "sync did not fail closed on a dirty dotfiles source (status $status)"
  fi
}

check_primary_global_live_regressions() {
  local target log log_name
  local -a drift_targets=(
    "$DEST/.claude/CLAUDE.md"
    "$DEST/.claude/settings.json"
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
