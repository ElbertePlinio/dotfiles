#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
SRC=(--source "$ROOT")
fail=0
MODE=default
STRICT_PREFLIGHT=0
for arg in "$@"; do
  case "$arg" in
    --check-live-migration) MODE=live ;;
    --strict-preflight) STRICT_PREFLIGHT=1 ;;
  esac
done


CHECK_MODULE_DIR="$ROOT/scripts/check"
for module in \
  lib.sh \
  lanes-mcp-checks.sh \
  retirement-checks.sh \
  sync-flow-fixture.sh \
  source-checks.sh \
  mcp-live-checks.sh \
  live-checks.sh \
  rendered-checks.sh \
  source-policy-checks.sh \
  sync-coverage-checks.sh \
  encryption-policy-checks.sh \
  hermetic-target-checks.sh; do
  # shellcheck source=/dev/null
  source "$CHECK_MODULE_DIR/$module"
done
