check_runtime_exclusions() {
  local path
  for path in "${RUNTIME_SOURCE_PATHS[@]}"; do
    compgen -G "$ROOT/$path" >/dev/null && err "runtime state still tracked: $path"
  done
  for path in "${RUNTIME_IGNORE_PATHS[@]}"; do
    grep -Fxq "$path" "$ROOT/.chezmoiignore" || err "runtime ignore missing: $path"
  done
  [[ "$fail" -eq 0 ]] && pass 'runtime state excluded from chezmoi source'
  return 0
}

check_retired_target_removals() {
  local removal_file="$ROOT/.chezmoiremove"
  local expected_file="$TMP/expected-chezmoiremove"
  local path count

  need "$removal_file"
  [[ -f "$removal_file" ]] || return
  printf '%s\n' "${RETIRED_TARGET_PATHS[@]}" >"$expected_file"

  for path in "${RETIRED_TARGET_PATHS[@]}"; do
    count="$(grep -Fxc -- "$path" "$removal_file" || true)"
    if [[ "$count" -eq 1 ]]; then
      pass "stable retirement entry present once: $path"
    else
      err "stable retirement entry count for $path: $count"
    fi
  done

  if cmp -s "$expected_file" "$removal_file"; then
    pass 'retirement list exactly matches stable target paths'
  else
    err 'retirement list differs from the exact stable target paths'
  fi

  if awk '
    ((index($0, "*") || index($0, "?") || index($0, "[")) \
      && $0 ~ /(^|\/)(plugins?|caches?)(\/|$)/) { found=1 }
    END { exit !found }
  ' "$removal_file"; then
    err 'retirement list contains a broad plugin/cache wildcard pattern'
  else
    pass 'retirement list rejects broad plugin/cache wildcard patterns'
  fi
}

check_retired_target_apply() {
  local DEST="$TMP/retirement-dest"
  local removal_source="$TMP/retirement-source"
  local path sentinel
  local preview_log="$TMP/retirement-preview.log"
  local apply_log="$TMP/retirement-apply.log"

  mkdir -p "$DEST" "$removal_source"
  cp "$ROOT/.chezmoiremove" "$removal_source/.chezmoiremove"
  for path in "${RETIRED_TARGET_PATHS[@]}"; do
    case "$path" in
      .local/bin/*|.claude/RTK.md)
        mkdir -p "$DEST/${path%/*}"
        printf 'retired\n' >"$DEST/$path"
        ;;
      *)
        mkdir -p "$DEST/$path"
        printf 'retired\n' >"$DEST/$path/sentinel"
        ;;
    esac
  done
  mkdir -p "$DEST/.claude/plugins/cache" "$DEST/.codex/cache"
  printf 'keep\n' >"$DEST/.claude/global-sentinel"
  printf 'keep\n' >"$DEST/.claude/plugins/cache/sentinel"
  printf 'keep\n' >"$DEST/.codex/global-sentinel"
  printf 'keep\n' >"$DEST/.codex/cache/sentinel"

  if (
    cd "$removal_source"
    chezmoi -S "$PWD" --persistent-state "$TMP/retirement-state.boltdb" -D "$DEST" apply --dry-run --verbose
  ) >"$preview_log" 2>&1; then
    pass 'retirement apply preview succeeds in temporary destination'
  else
    err "retirement apply preview failed: $(tr '\n' ' ' <"$preview_log")"
    return
  fi
  if (
    cd "$removal_source"
    chezmoi -S "$PWD" --persistent-state "$TMP/retirement-state.boltdb" -D "$DEST" apply --force --no-tty
  ) >"$apply_log" 2>&1; then
    pass 'retirement apply succeeds in temporary destination'
  else
    err "retirement apply failed: $(tr '\n' ' ' <"$apply_log")"
    return
  fi

  for path in "${RETIRED_TARGET_PATHS[@]}"; do
    if [[ ! -e "$DEST/$path" && ! -L "$DEST/$path" ]]; then
      pass "retired target removed from temporary destination: $path"
    else
      err "retired target remains in temporary destination: $path"
    fi
  done
  for sentinel in \
    .claude/global-sentinel \
    .claude/plugins/cache/sentinel \
    .codex/global-sentinel \
    .codex/cache/sentinel; do
    if [[ -f "$DEST/$sentinel" ]]; then
      pass "unrelated temporary sentinel preserved: $sentinel"
    else
      err "unrelated temporary sentinel removed: $sentinel"
    fi
  done
}

check_live_retired_targets() {
  local path live
  for path in "${RETIRED_TARGET_PATHS[@]}"; do
    live="$HOME/$path"
    if [[ ! -e "$live" && ! -L "$live" ]]; then
      pass "live retired target absent: $live"
    elif [[ "$STRICT_PREFLIGHT" -eq 1 ]]; then
      pass "live retired target pending removal: $live"
    else
      err "live retired target remains: $live"
    fi
  done
}

check_live_retired_target_regressions() {
  local seeded_home="$TMP/live-retirement-home"
  local seeded_path="${RETIRED_TARGET_PATHS[0]}"
  mkdir -p "$seeded_home/$seeded_path"
  printf '%s\n' retired >"$seeded_home/$seeded_path/sentinel"

  if (HOME="$seeded_home"; STRICT_PREFLIGHT=1; fail=0; \
    check_live_retired_targets >/dev/null 2>&1; [[ "$fail" -eq 0 ]]); then
    pass 'strict live preflight permits seeded pending retirement'
  else
    err 'strict live preflight rejected seeded pending retirement'
  fi
  if (HOME="$seeded_home"; STRICT_PREFLIGHT=0; fail=0; \
    check_live_retired_targets >/dev/null 2>&1; [[ "$fail" -ne 0 ]]); then
    pass 'normal live check rejects seeded stable retired target'
  else
    err 'normal live check accepted seeded stable retired target'
  fi
}

check_active_retired_references() {
  local matches
  if matches="$(rg -n -i --hidden \
    --glob '!.git' \
    --glob '!.git/**' \
    --glob '!docs/**' \
    --glob '!.chezmoiremove' \
    --glob '!scripts/check-agent-config-sync.sh' \
    --glob '!scripts/check/**' \
    'claude-personal|claude-default|claude-profile|agentProfile|agent-profiles|Projects/Personal/\.codex|\.agent-safety|superpowers|\brtk\b|RTK\.md|\bfrun\b|caveman|cavecrew|\bfactory\b|\bdroid\b|\bopencode\b' \
    .)"; then
    err 'active source contains retired harness/profile/tooling references'
    printf '%s\n' "$matches" >&2
  else
    pass 'active source excludes retired harness/profile/tooling references'
  fi
}

check_active_target_completeness() {
  local sync_command="$ROOT/dot_local/bin/executable_agent-config-sync"
  local source_path target entry
  local -a metadata_targets=(
    'dot_agents/dot_skill-lock.json|.agents/.skill-lock.json'
    'dot_agents/skill-targets.json|.agents/skill-targets.json'
    'dot_agents/mcp-targets.json|.agents/mcp-targets.json'
    'dot_local/bin/executable_pickforge-lanes-mcp|.local/bin/pickforge-lanes-mcp'
    'dot_pi/agent/encrypted_settings.json.age|.pi/agent/settings.json'
    'dot_pi/agent/extensions/btw.ts|.pi/agent/extensions/btw.ts'
  )

  need "$sync_command"
  [[ -f "$sync_command" ]] || return

  for source_path in "$ROOT"/dot_agents/*.md "$ROOT"/dot_agents/*.md.tmpl; do
    [[ -f "$source_path" ]] || continue
    target=".agents/${source_path##*/}"
    target="${target%.tmpl}"
    if grep -Fq '"${HOME}/'"$target"'"' "$sync_command"; then
      pass "active target includes top-level agent policy: $target"
    else
      err "active target missing top-level agent policy: $target"
    fi
  done

  for entry in "${metadata_targets[@]}"; do
    source_path="${entry%%|*}"
    target="${entry#*|}"
    need "$ROOT/$source_path"
    if [[ -f "$ROOT/$source_path" ]] \
      && grep -Fq '"${HOME}/'"$target"'"' "$sync_command"; then
      pass "active target includes agent metadata registry: $target"
    else
      err "active target missing agent metadata registry: $target"
    fi
  done

}

