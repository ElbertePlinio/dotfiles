#!/bin/sh
# Keep Codegraph indexes incrementally fresh between agent sessions.
command -v systemctl >/dev/null 2>&1 || exit 0
systemctl --user daemon-reload >/dev/null 2>&1 || exit 0
if ! systemctl --user enable --now codegraph-sync.timer >/dev/null 2>&1; then
  printf 'warning: could not enable codegraph-sync.timer\n' >&2
fi
exit 0
