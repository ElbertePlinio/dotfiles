#!/bin/sh
# Keep Codegraph indexes fresh between agent sessions, and check daily whether
# first-party tools on this machine have fallen behind.
command -v systemctl >/dev/null 2>&1 || exit 0
systemctl --user daemon-reload >/dev/null 2>&1 || exit 0
for timer in codegraph-sync.timer dev-freshness.timer; do
  if ! systemctl --user enable --now "$timer" >/dev/null 2>&1; then
    printf 'warning: could not enable %s\n' "$timer" >&2
  fi
done
exit 0
