SYNC_CLI="$ROOT/dot_local/bin/executable_agent-config-sync"
SYNC_POLICY="$(mktemp "${TMPDIR:-/tmp}/agent-config-sync-policy.XXXXXX")"
SYNC_POLICY_ERR="$(mktemp "${TMPDIR:-/tmp}/agent-config-sync-policy-err.XXXXXX")"
SYNC_MANAGED_FILES="$(mktemp "${TMPDIR:-/tmp}/agent-config-sync-managed-files.XXXXXX")"
SYNC_MANAGED_DIRS="$(mktemp "${TMPDIR:-/tmp}/agent-config-sync-managed-dirs.XXXXXX")"
trap 'rm -rf "$TMP" "$DEST"; rm -f "$OMP_MCP" "$SYNC_POLICY" "$SYNC_POLICY_ERR" "$SYNC_MANAGED_FILES" "$SYNC_MANAGED_DIRS"' EXIT

need "$SYNC_CLI"

sync_active_targets=()
sync_excluded_targets=()
sync_excluded_reasons=()
sync_scope_roots=()

covered_by() {
  local target="$1" candidate
  shift
  for candidate in "$@"; do
    [[ "$target" == "$candidate" || "$target" == "$candidate"/* ]] && return 0
  done
  return 1
}

ancestor_of_any() {
  local target="$1" candidate
  shift
  for candidate in "$@"; do
    [[ "$candidate" == "$target"/* ]] && return 0
  done
  return 1
}

if ! CHEZMOI_SOURCE_DIR="$ROOT" bash "$SYNC_CLI" targets \
  >"$SYNC_POLICY" 2>"$SYNC_POLICY_ERR"; then
  err "agent-config-sync targets failed: $(tr '\n' ' ' <"$SYNC_POLICY_ERR")"
else
  pass 'agent-config-sync publishes its apply-path policy'
  while IFS=$'\t' read -r kind path reason; do
    case "$kind" in
      active) sync_active_targets+=("$path") ;;
      excluded)
        sync_excluded_targets+=("$path")
        sync_excluded_reasons+=("$reason")
        ;;
      scope) sync_scope_roots+=("$path") ;;
    esac
  done <"$SYNC_POLICY"

  if [[ "${#sync_active_targets[@]}" -gt 0 && "${#sync_scope_roots[@]}" -gt 0 ]]; then
    pass "apply-path policy declares ${#sync_active_targets[@]} active and ${#sync_excluded_targets[@]} excluded targets"
  else
    err 'apply-path policy is missing active targets or scope roots'
  fi

  # Every exclusion must carry a reason, must still be managed, and must not
  # also be active — so the list cannot rot into a silent second apply policy.
  for index in "${!sync_excluded_targets[@]}"; do
    excluded="${sync_excluded_targets[$index]}"
    if [[ -z "${sync_excluded_reasons[$index]}" ]]; then
      err "excluded target has no reason: $excluded"
    fi
    if covered_by "$excluded" "${sync_active_targets[@]}"; then
      err "target is both active and excluded: $excluded"
    fi
  done

  if ! chezmoi "${SRC[@]}" managed --include=files,symlinks --path-style=absolute \
    >"$SYNC_MANAGED_FILES" 2>"$SYNC_POLICY_ERR"; then
    err "managed file enumeration failed: $(tr '\n' ' ' <"$SYNC_POLICY_ERR")"
  elif ! chezmoi "${SRC[@]}" managed --include=dirs --path-style=absolute \
    >"$SYNC_MANAGED_DIRS" 2>"$SYNC_POLICY_ERR"; then
    err "managed directory enumeration failed: $(tr '\n' ' ' <"$SYNC_POLICY_ERR")"
  else
    uncovered=0
    while IFS= read -r managed; do
      [[ -n "$managed" ]] || continue
      covered_by "$managed" "${sync_scope_roots[@]}" || continue
      covered_by "$managed" "${sync_active_targets[@]}" && continue
      covered_by "$managed" "${sync_excluded_targets[@]}" && continue
      err "managed agent-config file is neither applied nor excluded: $managed"
      uncovered=$((uncovered + 1))
    done <"$SYNC_MANAGED_FILES"
    if [[ "$uncovered" -eq 0 ]]; then
      pass 'every managed agent-config file is on the apply path or explicitly excluded'
    fi

    # Managed directories may also be implicit: chezmoi creates them while
    # applying a covered child.
    uncovered=0
    while IFS= read -r managed; do
      [[ -n "$managed" ]] || continue
      covered_by "$managed" "${sync_scope_roots[@]}" || continue
      covered_by "$managed" "${sync_active_targets[@]}" && continue
      covered_by "$managed" "${sync_excluded_targets[@]}" && continue
      ancestor_of_any "$managed" "${sync_active_targets[@]}" && continue
      ancestor_of_any "$managed" "${sync_excluded_targets[@]}" && continue
      err "managed agent-config directory is unreachable from the apply path: $managed"
      uncovered=$((uncovered + 1))
    done <"$SYNC_MANAGED_DIRS"
    if [[ "$uncovered" -eq 0 ]]; then
      pass 'every managed agent-config directory is reachable from the apply path'
    fi

    stale=0
    for excluded in "${sync_excluded_targets[@]}"; do
      if grep -Fqx "$excluded" "$SYNC_MANAGED_FILES" \
        || grep -Fqx "$excluded" "$SYNC_MANAGED_DIRS" \
        || grep -Fq "$excluded/" "$SYNC_MANAGED_FILES" \
        || grep -Fq "$excluded/" "$SYNC_MANAGED_DIRS"; then
        continue
      fi
      err "stale apply-path exclusion, target is no longer managed: $excluded"
      stale=$((stale + 1))
    done
    if [[ "$stale" -eq 0 ]]; then
      pass 'no stale apply-path exclusions'
    fi
  fi
fi

# The apply path must stay derived from the published policy, not a second
# hand-maintained literal inside cmd_apply.
if grep -Fq 'local -a active_targets=("${AGENT_ACTIVE_TARGETS[@]}")' "$SYNC_CLI"; then
  pass 'cmd_apply derives its target list from the published policy'
else
  err 'cmd_apply no longer derives its target list from AGENT_ACTIVE_TARGETS'
fi
