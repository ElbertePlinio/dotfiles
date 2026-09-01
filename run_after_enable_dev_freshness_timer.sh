#!/bin/sh
# Check daily whether first-party tools on this machine have fallen behind.
command -v systemctl >/dev/null 2>&1 || exit 0
systemctl --user daemon-reload >/dev/null 2>&1 || exit 0
if ! systemctl --user enable --now dev-freshness.timer >/dev/null 2>&1; then
  printf 'warning: could not enable dev-freshness.timer\n' >&2
fi
exit 0
