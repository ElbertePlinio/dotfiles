#!/bin/sh
set -eu

# Register the PickScribe dictionary MCP for Claude Code and Codex, so agents can record
# dictation corrections the user confirms. It only edits ~/.config/pickscribe/dictionary.txt.
pickscribe="$HOME/.local/bin/pickscribe"
if [ ! -x "$pickscribe" ]; then
  printf '%s\n' 'warning: PickScribe is not installed; dictionary MCP registration skipped' >&2
  exit 0
fi

if command -v claude >/dev/null 2>&1 && ! claude mcp get pickscribe >/dev/null 2>&1; then
  claude mcp add --scope user pickscribe -- "$pickscribe" mcp >/dev/null
fi

if command -v codex >/dev/null 2>&1 && ! codex mcp get pickscribe >/dev/null 2>&1; then
  timeout 15 codex mcp add pickscribe -- "$pickscribe" mcp >/dev/null
fi
