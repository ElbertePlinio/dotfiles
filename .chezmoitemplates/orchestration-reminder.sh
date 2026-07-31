#!/usr/bin/env bash
# UserPromptSubmit hook: on every user message, inject a short orchestration
# reminder into context, and re-arm the delegation gate once its last firing
# is more than 30 minutes old, so long sessions keep routing work to lanes
# instead of drifting back to solo implementation. Claude Code hook schema.
set -euo pipefail

input="$(cat)"
session_id="$(jq -r '.session_id // "default"' <<<"$input")"

marker="${TMPDIR:-/tmp}/agent-delegation-gate-${session_id}"
if [[ -f "$marker" && -n "$(find "$marker" -mmin +30 2>/dev/null)" ]]; then
  rm -f "$marker"
fi

cat <<'EOF'
Orchestration reminder: the session's own model is the scarce pool. Route brute, mechanical, or spec-ready work to lanes/subagents per the harness model table (the model-orchestration skill owns dispatch mechanics); keep scope, routing, synthesis, and taste in-session. Before the first edit of any multi-step task, state the delegation plan.
EOF
