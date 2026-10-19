#!/bin/sh
# Stop a full apply that would overwrite content chezmoi did not write.
exec bash "$CHEZMOI_SOURCE_DIR/scripts/apply-guard.sh"
