# dotfiles

Personal CachyOS / Linux dotfiles, managed with [chezmoi](https://www.chezmoi.io/).

Covers shell, terminal emulators, editors, git, KDE theming, and AI tooling config. A small set of API credentials lives in the repo too, **age-encrypted** via chezmoi — see [Secrets (age encryption)](#secrets-age-encryption). Browser profiles, SSH/GPG keys, and stateful blobs stay out of scope — they need manual backup before reinstalling the OS. See [Manual backup](#manual-backup-not-managed-by-chezmoi).

## Quickstart

On a fresh machine:

```bash
# 1. Install bootstrap dependencies
sudo pacman -S chezmoi age git github-cli

# 2. Restore your chezmoi age identity (see "Secrets" section)
#    Store it off-machine; you need it before `chezmoi apply`.
mkdir -p ~/.config/chezmoi
# ...copy your saved key.txt to ~/.config/chezmoi/key.txt...
chmod 0600 ~/.config/chezmoi/key.txt

# 3. Authenticate GitHub SSH before apply (the Pi bootstrap clones
#    pickforge-platform, which provides pi-kit)
ssh -T git@github.com

# 4. Initialize from this repo
chezmoi init git@github.com:ElbertePlinio/dotfiles.git

# 5. Preview every target before applying
chezmoi diff

# 6. Apply interactively on a clean machine
chezmoi apply --interactive

# 7. Start a new shell, then validate managed agent configuration
exec zsh
agent-config-sync check-live
```

The first apply installs `agent-config-sync`, the canonical skill under
`~/.agents/skills/agent-config-sync`, and each declared harness link. The skill
cannot guide the initial apply because it does not exist locally yet; use this
Quickstart as the bootstrap boundary. Tailscale is optional during bootstrap:
a later `chezmoi apply` configures the Plannotator tailnet URL after Tailscale is
installed and connected.

Daily use:

```bash
chezmoi edit ~/.zshrc               # edit the source copy
chezmoi diff                         # review target drift
chezmoi apply ~/.zshrc               # apply only the reviewed target
agent-config-sync apply              # validated agent-config cutover
chezmoi cd                           # open the source repository
git pull --ff-only                   # update source without applying blindly
```

## What's managed

- **Shell**: `.zshrc`, `.zshenv`, `.p10k.zsh`, `.bashrc`, `.bash_profile`
- **Git**: `.gitconfig`, `~/.config/git/`
- **Terminals**: `~/.config/alacritty/`, `~/.config/ghostty/`, `~/.config/fish/`
- **Editors**: `~/.config/Code/User/{settings,keybindings,mcp,snippets}.json`, `~/.config/kate/`, `~/.config/katerc`, `~/.config/katevirc`, `~/.config/kwriterc`, `~/.config/micro/`, `~/.config/nvim/` (LazyVim)
- **KDE / Plasma**: `kdeglobals`, `kwinrc`, `kglobalshortcutsrc`, `konsolerc`, `dolphinrc`, `baloofilerc`, `kxkbrc`, `kcminputrc`, `kded5rc`, `kdedefaults/`, `kiorc`, `kactivitymanagerdrc`, `ksmserverrc`, `plasmashellrc`, `plasma-localerc`, `plasmanotifyrc`, `plasma-org.kde.plasma.desktop-appletsrc` (panel layout), `powermanagementprofilesrc`, `systemmonitorrc`, `gwenviewrc`, `spectaclerc`, `arkrc`, `bluedevilglobalrc`
- **GTK / Qt**: `~/.config/gtk-3.0/`, `~/.config/gtk-4.0/`, `.gtkrc-2.0`, `Trolltech.conf`, `QtProject.conf`
- **Defaults / environment**: `mimeapps.list`, `user-dirs.dirs`, `user-dirs.locale`, `trashrc`, `autostart/`, `environment.d/`, `cachyos/`, `cachyos-hello.json`, `libinput-gestures.conf`
- **Fonts / input**: `~/.config/fontconfig/`, `.XCompose`
- **AI tooling**:
  - Shared policy: `.chezmoitemplates/agents-shared*.md`
  - Global Claude adapter: `~/.claude/CLAUDE.md` (unrestricted `claude` shell wrapper)
  - Global Codex adapter: `~/.codex/AGENTS.md` (unrestricted `codex` shell wrapper)
  - Other harness adapters: Grok, Pi, OMP, Factory, Hermes, OpenCode
  - Portable skills: `~/.agents/skills` (canonical). Distribution matrix: `dot_agents/skill-targets.json`
  - Sync CLI: `agent-config-sync` (`check` | `check-live` | `apply`)
  - Encrypted stable configuration: selected Claude settings and harness-native skills
  - Runtime state: credentials, sessions, histories, caches, plugins, and usage state remain machine-owned

## Agent configuration

One unrestricted global Claude and Codex setup. Shell wrappers:

```bash
claude   # command claude --dangerously-skip-permissions
codex    # command codex --yolo
```

Daily sync workflow:

```bash
agent-config-sync check       # source templates + portable skill matrix
agent-config-sync check-live  # read-only live validation against $HOME
agent-config-sync apply       # source check, strict preflight, scoped agent apply, live check
```

`apply` targets only the managed agent configuration and the stable paths listed in `.chezmoiremove`; it does not apply unrelated dotfiles or root run scripts. Do not sync credentials, sessions, histories, caches, or other machine-owned runtime state.

## Secrets (age encryption)

Chezmoi encrypts sensitive files with [age](https://github.com/FiloSottile/age) before committing. The repo only ever contains ciphertext (`encrypted_*.age`); the decrypt key lives at `~/.config/chezmoi/key.txt` on each machine and must never leave it in plaintext form.

### First-time setup (new key)

```bash
mkdir -p ~/.config/chezmoi
age-keygen -o ~/.config/chezmoi/key.txt
chmod 0600 ~/.config/chezmoi/key.txt

PUBKEY=$(age-keygen -y ~/.config/chezmoi/key.txt)
cat > ~/.config/chezmoi/chezmoi.toml <<EOF
encryption = "age"

[age]
  identity = "~/.config/chezmoi/key.txt"
  recipient = "$PUBKEY"
EOF
```

**Store `~/.config/chezmoi/key.txt` off-machine** — password manager attachment, printed QR on paper, offline USB. Without the identity file, encrypted entries cannot be decrypted on a new machine and you would have to rotate every credential.

### New machine (restore identity)

```bash
mkdir -p ~/.config/chezmoi
# Paste or copy the saved key.txt into place
chmod 0600 ~/.config/chezmoi/key.txt
# chezmoi.toml is NOT in the repo; recreate it with the public recipient line
cat > ~/.config/chezmoi/chezmoi.toml <<EOF
encryption = "age"

[age]
  identity = "~/.config/chezmoi/key.txt"
  recipient = "$(age-keygen -y ~/.config/chezmoi/key.txt)"
EOF
```

### Adding a new secret

```bash
chezmoi add --encrypt ~/.some/secret-file
```

The source file will land as `encrypted_<name>.age`. Commit and push as usual.

### Rotating the age key

If the identity file leaks: generate a new pair, re-encrypt every `encrypted_*.age` against the new recipient, force-push. Treat every credential inside the repo as leaked in the meantime — rotate them too.

## Manual backup (not managed by chezmoi)

Chezmoi is built for small, hand-edited text files. The items below are either too large, too sensitive, or too stateful for git and must be snapshotted manually **before** reformatting.

### Browser profiles — Zen, Firefox, Chrome

A full profile contains cookies, history, saved logins, extensions, and open tabs. To carry an exact session across a reinstall, tar the profile dirs while browsers are **closed**:

```bash
# Close all browsers first.
mkdir -p ~/browser-backup

tar --zstd -cf ~/browser-backup/zen.tar.zst     -C ~        .zen
tar --zstd -cf ~/browser-backup/firefox.tar.zst -C ~        .mozilla
tar --zstd -cf ~/browser-backup/chrome.tar.zst  -C ~/.config google-chrome
```

Restore on the new install (again, browsers closed):

```bash
tar --zstd -xf ~/browser-backup/zen.tar.zst     -C ~
tar --zstd -xf ~/browser-backup/firefox.tar.zst -C ~
tar --zstd -xf ~/browser-backup/chrome.tar.zst  -C ~/.config
```

**Lighter alternative — built-in sync:** Firefox Sync, Zen Sync (Firefox-based), Chrome Sync. Handles bookmarks, history, logins, tabs, extensions automatically, no tarballs.

**Security note:** these tarballs contain live session cookies. Keep them off shared drives; prefer encrypting (see [Secrets](#secrets--ssh-gpg-api-tokens) below for the `age` pattern).

### Secrets — SSH, GPG, API tokens

Private keys and tokens. **Never** commit to git, even inside this repo. Encrypt with [age](https://github.com/FiloSottile/age) before moving off the machine.

One-time key setup:

```bash
age-keygen -o ~/age-identity.txt
age-keygen -y ~/age-identity.txt > ~/age-recipients.txt
chmod 0600 ~/age-identity.txt
```

**Store `age-identity.txt` off the backup drive** — password manager attachment, printed QR, separate offline USB. Lose the identity = backup is unrecoverable.

Backup:

```bash
tar -cf - -C ~ .ssh .gnupg | \
  age -R ~/age-recipients.txt -o ~/secrets.tar.age
sha256sum ~/secrets.tar.age > ~/secrets.tar.age.sha256
```

Restore:

```bash
sha256sum -c ~/secrets.tar.age.sha256
age -d -i /path/to/age-identity.txt ~/secrets.tar.age | tar -xf - -C ~
chmod 700 ~/.ssh ~/.gnupg
ssh-add -l               # confirm keys load
gpg --list-secret-keys   # confirm GPG
```

**Filesystem warning:** exFAT/NTFS external drives strip Unix permissions. SSH refuses to load world-readable keys. Stage on a local ext4/btrfs filesystem and only move the opaque `.age` file to the external drive.

### Shell history

Personal log, small, optional:

```bash
mkdir -p ~/history-backup
cp ~/.zsh_history ~/.bash_history ~/history-backup/ 2>/dev/null || true
```

### Package lists

So a fresh install gets the same stack back:

```bash
pacman -Qqen > ~/packages-explicit.txt                          # official repos
pacman -Qqem > ~/packages-aur.txt                               # AUR
flatpak list --app --columns=application > ~/flatpaks.txt
```

Restore:

```bash
xargs -r -a packages-explicit.txt sudo pacman -S --needed
xargs -r -a packages-aur.txt      paru -S --needed              # or yay
xargs -r -a flatpaks.txt          flatpak install -y flathub
```

### AI tool state (optional)

Credentials for Codex and Context7 live in the repo, age-encrypted (see [Secrets](#secrets-age-encryption)). Everything else is stateful runtime data — snapshot separately if you want it back:

| Path               | Contents                                  |
|--------------------|-------------------------------------------|
| `~/.claude.json`   | Claude Code auth / session                |
| `~/.claude-mem/`   | Claude memory DB                          |
| `~/.hermes/`       | Hermes data                               |
| `~/.codex/sessions`, `logs_*.sqlite*`, `memories/` | Codex runtime state |
| `~/.copilot/`      | GitHub Copilot token                      |

```bash
tar --zstd -cf - -C ~ \
  .claude.json .claude-mem .hermes .copilot \
  | age -R ~/age-recipients.txt -o ~/ai-state.tar.zst.age
```

Encrypt with age — these files contain session tokens.

### System files

Outside `$HOME` but handy to keep:

```bash
mkdir -p ~/system-snapshot
sudo cp /etc/fstab /etc/hostname /etc/hosts ~/system-snapshot/
```

### What to deliberately skip

Regenerable — don't back up, reinstall fresh:

- `~/.cache/`, `~/.local/share/Trash/`
- Toolchain caches: `.nvm/`, `.bun/`, `.pub-cache/`, `.gradle/`, `.java/`, `.dotnet/`, `.dartServer/`, `.dart-tool/`, `.npm/`, `~/fvm/`, `~/go/`, `~/.android/avd/`
- `.steam/`, `.ollama/` — reinstall, let apps re-download
- Source repos in `Development/`, `Projects/`, `Documents/`, `Android/`, `ProgramsDev/` — these live on git remotes

## Reformat checklist

1. **Backup** → browser tarballs, `secrets.tar.age`, shell history, package lists, AI state, system files.
2. **Push** any pending chezmoi changes: `chezmoi cd && git push`.
3. **Reinstall** the OS.
4. **Packages** → pacman, AUR helper, flatpaks from the `.txt` lists.
5. **Age identity** → restore `~/.config/chezmoi/key.txt` (0600) and recreate `~/.config/chezmoi/chezmoi.toml` — see [Secrets](#secrets-age-encryption).
6. **Dotfiles** → initialize the repo, review `chezmoi diff`, apply interactively, then run `agent-config-sync apply`.
7. **SSH/GPG** → decrypt `secrets.tar.age` into `$HOME`.
8. **Browsers** → extract tarballs (browsers closed).
9. **AI state** → decrypt and extract if kept.
10. **Verify** → `ssh-add -l`, `gpg --list-secret-keys`, re-login to pick up shell config, open each browser.

## License

[MIT](LICENSE).
