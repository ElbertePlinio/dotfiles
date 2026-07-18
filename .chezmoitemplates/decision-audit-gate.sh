#!/usr/bin/env bash
# PreToolUse gate: before the first `git push` / `gh pr create` of a session,
# block once and ask for the decision audit (see "Decision audit" in the
# global instructions). Claude Code and Factory droid share this hook schema.
set -euo pipefail

input="$(cat)"
command="$(jq -r '.tool_input.command // empty' <<<"$input")"
session_id="$(jq -r '.session_id // "default"' <<<"$input")"

if ! grep -qE '\bgit\s+(-[cC][[:space:]]+[^[:space:]]+[[:space:]]+|--?[[:alnum:]-]+(=[^[:space:]]+)?[[:space:]]+)*push\b|\bgh pr create\b' <<<"$command"; then
  exit 0
fi

marker="${TMPDIR:-/tmp}/agent-decision-audit-${session_id}"
if [[ -f "$marker" ]]; then
  exit 0
fi
touch "$marker"

cat >&2 <<'EOF'
Decision audit gate: before pushing or opening a PR, run the decision audit from "Before finishing":
1) Would you stand behind this branch as-is? If not, say exactly why.
2) List every choice the user or plan did not explicitly specify; flag low-confidence ones and plausible alternatives.
3) Surface incidental fixes (magic constants, coincidental sizes, special cases) as open decisions, not successes.
Present the audit to the user, then retry this command (the gate passes on retry this session).
EOF
exit 2
