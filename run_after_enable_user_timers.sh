#!/bin/sh
# Keep Codegraph indexes fresh between agent sessions, check daily whether
# first-party tools on this machine have fallen behind, and let agents yield the
# CPU while a game runs.
command -v systemctl >/dev/null 2>&1 || exit 0
systemctl --user daemon-reload >/dev/null 2>&1 || exit 0
for timer in codegraph-sync.timer dev-freshness.timer modo-jogo.service; do
  if ! systemctl --user enable --now "$timer" >/dev/null 2>&1; then
    printf 'warning: could not enable %s\n' "$timer" >&2
  fi
done
exit 0
