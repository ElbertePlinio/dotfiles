#!/bin/sh
set -eu

# Register the read-only Sentry MCP at Claude user scope.
# Claude Code ignores mcpServers in settings.json, so register through the CLI.
if ! command -v claude >/dev/null 2>&1; then
  printf '%s\n' 'warning: Claude CLI is unavailable; Sentry MCP registration skipped' >&2
  exit 0
fi

if claude mcp get sentry >/dev/null 2>&1; then
  exit 0
fi

claude mcp add --scope user sentry -- "$HOME/.local/bin/sentry-mcp" >/dev/null
