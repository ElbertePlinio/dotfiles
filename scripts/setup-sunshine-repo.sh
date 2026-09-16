#!/usr/bin/env bash
set -euo pipefail
if (( EUID != 0 )) || [[ -z ${SUDO_USER:-} || ${SUDO_USER} == root ]]; then
  echo 'Run this script with sudo bash from your normal Termius login.' >&2
  exit 1
fi
python3 - <<'PYCONFIG'
from pathlib import Path
import shutil
import time
p = Path('/etc/pacman.conf')
s = p.read_text()
repo = '[lizardbyte]\nSigLevel = Optional\nServer = https://github.com/LizardByte/pacman-repo/releases/latest/download\n\n'
if s.count('[omarchy]') != 1:
    raise SystemExit('Expected one Omarchy repository. No changes made.')
if '[lizardbyte]' in s:
    if repo not in s or s.index('[lizardbyte]') > s.index('[omarchy]'):
        raise SystemExit('Existing LizardByte configuration differs. Stopping for inspection.')
else:
    backup = p.with_name(f'pacman.conf.before-lizardbyte-{time.time_ns()}')
    shutil.copy2(p, backup)
    p.write_text(s.replace('[omarchy]', repo + '[omarchy]', 1))
    print(f'Backup: {backup}')
PYCONFIG
# Full upgrade avoids unsupported partial upgrades on Arch.
pacman -Syu lizardbyte/sunshine
uid=$(id -u "$SUDO_USER")
user_systemctl() {
  runuser -u "$SUDO_USER" -- env XDG_RUNTIME_DIR="/run/user/$uid" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" systemctl --user "$@"
}
user_systemctl daemon-reload
user_systemctl restart sunshine
pacman -Q sunshine
user_systemctl is-active sunshine
