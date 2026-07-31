#!/usr/bin/env bash
# PreToolUse gate: before the first Edit/Write inside a git repository, block
# once and require a delegation plan, so lanes and parallel subagents are
# considered before solo implementation begins. The orchestration-reminder
# UserPromptSubmit hook re-arms this gate after 30 idle minutes so long
# sessions keep the pressure. Claude Code hook schema.
set -euo pipefail

input="$(cat)"
file_path="$(jq -r '.tool_input.file_path // empty' <<<"$input")"
session_id="$(jq -r '.session_id // "default"' <<<"$input")"

[[ -n "$file_path" ]] || exit 0
dir="$(dirname "$file_path")"
[[ -d "$dir" ]] || dir="$PWD"
git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

marker="${TMPDIR:-/tmp}/agent-delegation-gate-${session_id}"
if [[ -f "$marker" ]]; then
  exit 0
fi
touch "$marker"

cat >&2 <<'EOF'
Delegation gate: first edit since the gate was (re-)armed. Before implementing by hand, state the delegation plan:
1) Split the task: which self-contained chunks dispatch to lanes or subagents — model and effort for each, from the harness's model table — and which of them run in parallel.
2) The session's own model is the scarce pool, whichever model that is; route brute work outward to compatible lanes that are not the session's model. Spec-ready implementation goes to the cheapest capable lane at low effort under a written contract.
3) Say what stays in this session and why: taste-heavy ownership, synthesis, or a genuinely trivial change.
Load the model-orchestration skill for dispatch mechanics, present the plan, then retry the edit (the gate passes on retry and re-arms after 30 idle minutes).
EOF
exit 2
