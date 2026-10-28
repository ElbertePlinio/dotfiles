#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
SRC=(--source "$ROOT")
fail=0
MODE=default
for arg in "$@"; do
  case "$arg" in
    --check-live-migration) MODE=live ;;
  esac
done
if [[ "$MODE" == default ]]; then
  export AGENT_CONFIG_SYNC_SOURCE_CHECK=1
fi


python3 "$ROOT/scripts/check-hermes-policy.py"

CHECK_MODULE_DIR="$ROOT/scripts/check"
for module in \
  lib.sh \
  agent-hook-policy-checks.sh \
  lanes-mcp-checks.sh \
  retirement-checks.sh \
  sync-flow-fixture.sh \
  source-checks.sh \
  mcp-live-checks.sh \
  live-checks.sh \
  rendered-checks.sh \
  ai-memory-capture-checks.sh \
  source-policy-checks.sh \
  encryption-policy-checks.sh \
  hermetic-target-checks.sh; do
  # shellcheck source=/dev/null
  source "$CHECK_MODULE_DIR/$module"
done
