check_ai_memory_capture() {
  local harness="$ROOT/scripts/test-ai-memory-capture.ts"
  local expected="$ROOT/scripts/test-ai-memory-capture.expected.jsonl"
  local -A pids=()
  local entry extension agent log status

  need "$harness"
  need "$expected"
  if ! command -v bun >/dev/null 2>&1; then
    err 'ai-memory capture behavior checks require bun'
    return
  fi

  # Pi and OMP share capture-policy-v1, so both must reproduce one fixture.
  # The harness prints only fixture values and redacted request shapes.
  for entry in dot_pi/agent/extensions/ai-memory-pi.ts:pi dot_omp/agent/extensions/ai-memory-omp.ts:omp; do
    extension="${entry%%:*}"
    agent="${entry##*:}"
    log="$TMP/ai-memory-capture-$agent"
    AI_MEMORY_EXTENSION="$ROOT/$extension" AI_MEMORY_EXPECTED_AGENT="$agent" \
      bun "$harness" >"$log.jsonl" 2>"$log.err" &
    pids[$entry]=$!
  done

  for entry in "${!pids[@]}"; do
    extension="${entry%%:*}"
    log="$TMP/ai-memory-capture-${entry##*:}"
    if wait "${pids[$entry]}"; then
      status=0
    else
      status=$?
    fi
    if [[ "$status" -eq 0 ]] && cmp -s "$expected" "$log.jsonl"; then
      pass "ai-memory capture behavior matches fixture: $extension"
    else
      grep '^FAIL ' "$log.err" | head -20 >&2 || true
      err "ai-memory capture behavior diverged (exit $status): $extension"
    fi
  done
}

check_ai_memory_capture
