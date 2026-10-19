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
  [[ -f "$removal_file" ]] || return 0
  if awk '
    /^#/ { next }
    ((index($0, "*") || index($0, "?") || index($0, "[")) \
      && $0 ~ /(^|\/)(plugins?|caches?)(\/|$)/) { found=1 }
    END { exit !found }
  ' "$removal_file"; then
    err 'retirement list contains a broad plugin/cache wildcard pattern'
  else
    pass 'retirement list rejects broad plugin/cache wildcard patterns'
  fi
}

check_active_retired_references() {
  local matches status
  if matches="$(rg --pcre2 -n -i --hidden \
    --glob '!.git' \
    --glob '!.git/**' \
    --glob '!docs/**' \
    --glob '!.chezmoiremove' \
    --glob '!scripts/check-agent-config-sync.sh' \
    --glob '!scripts/check/**' \
    --glob '!dot_config/opencode/private_opencode.jsonc' \
    'claude-personal|claude-default|claude-profile|agentProfile|agent-profiles|Projects/Personal/\.codex|\.agent-safety|superpowers|\brtk\b|RTK\.md|\bfrun\b|caveman|cavecrew|\bfactory\b|\bdroid\b|(?<![\w-])(?<!\.config/opencode/)(?!opencode/opencode\.jsonc)opencode(?!-[Gg]o)(?![\w-])' \
    .)"; then
    err 'active source contains retired harness/profile/tooling references'
    printf '%s\n' "$matches" >&2
  else
    status=$?
    if [[ "$status" -eq 1 ]]; then
      pass 'active source excludes retired harness/profile/tooling references'
    else
      err "retired-reference scan failed (ripgrep exit $status)"
    fi
  fi
}

check_retired_reference_scanner_regressions() {
  local fixture="$TMP/retired-reference-scanner"
  mkdir -p "$fixture"
  printf '%s\n' 'opencode-go/kimi-k3' >"$fixture/instructions.md"
  printf '%s\n' '"${HOME}/.config/opencode/opencode.jsonc"' >>"$fixture/instructions.md"
  if (cd "$fixture"; fail=0; check_active_retired_references >/dev/null; [[ "$fail" -eq 0 ]]); then
    pass 'retired-reference scanner accepts the active provider route and the hook-removal OpenCode config target'
  else
    err 'retired-reference scanner rejected the active provider route'
  fi
  printf '%s\n' 'use opencode' >>"$fixture/instructions.md"
  if (cd "$fixture"; fail=0; check_active_retired_references >/dev/null 2>&1; [[ "$fail" -ne 0 ]]); then
    pass 'retired-reference scanner detects a retired harness'
  else
    err 'retired-reference scanner missed a retired harness'
  fi
  if (rg() { return 2; }; fail=0; check_active_retired_references >/dev/null 2>&1; [[ "$fail" -ne 0 ]]); then
    pass 'retired-reference scanner distinguishes execution errors from no matches'
  else
    err 'retired-reference scanner treated an execution error as clean'
  fi
}
