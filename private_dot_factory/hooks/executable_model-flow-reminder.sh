#!/bin/sh
# Inject the adaptive review reminder on every user prompt.
# Must never fail: a non-zero exit would block and erase the prompt.

cat << 'EOF'
{
  "suppressOutput": true,
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "Workflow reminder: use the lightest sufficient path and delegate only when independent execution or review materially improves the result. The main model owns scope, synthesis, validation, and acceptance. After focused behavioral validation, run $local-review before shipping."
  }
}
EOF
exit 0
