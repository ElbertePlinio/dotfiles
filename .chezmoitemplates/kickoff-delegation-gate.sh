#!/usr/bin/env bash
# PreToolUse gate: in a session where the kickoff skill was loaded, block
# Edit/Write until the model-orchestration skill has also been loaded, so
# routing happens before solo implementation (see kickoff step 1). This hook
# uses the Claude Code hook schema.
set -euo pipefail

input="$(cat)"
transcript="$(jq -r '.transcript_path // empty' <<<"$input")"

[[ -n "$transcript" && -f "$transcript" ]] || exit 0

kickoff_marker="Base directory for this skill: $HOME/.claude/skills/kickoff"
routing_marker="Base directory for this skill: $HOME/.claude/skills/model-orchestration"

grep -qF "$kickoff_marker" "$transcript" || exit 0
grep -qF "$routing_marker" "$transcript" && exit 0

cat >&2 <<'EOF'
Kickoff delegation gate: this session loaded the kickoff skill but not
model-orchestration. Before editing any file:
1) Invoke the model-orchestration skill (Skill tool) and read its routing reference.
2) State the delegation decision in one sentence: who implements, at which model
   and effort — or why solo is right for this task.
Then retry the edit; the gate passes once model-orchestration is loaded.
EOF
exit 2
