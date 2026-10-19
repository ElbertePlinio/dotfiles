# dotfiles

Personal dotfiles for macOS and Omarchy Linux, managed with [chezmoi](https://www.chezmoi.io/). Shell, editor, git, terminal, and AI tooling configuration is shared. Linux-only settings are applied only on Linux. Omarchy owns the Hyprland desktop, so this repo does not manage it. A small set of API credentials lives in the repo too, **age-encrypted** via chezmoi — see [Secrets (age encryption)](#secrets-age-encryption). Browser profiles, SSH/GPG keys, and stateful blobs stay out of scope — they need manual backup before reinstalling the OS. See [Manual backup](#manual-backup-not-managed-by-chezmoi).

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
#    the standalone pi-kit repository)
ssh -T git@github.com

# 4. Initialize from this repo. The template creates the age config.
chezmoi init git@github.com:ElbertePlinio/dotfiles.git

# 5. Review source templates and target status. Diffs can expose keys.
chezmoi status

# 6. Apply. The apply guard lists each existing file that chezmoi would
#    replace. Merge it with `chezmoi merge <path>`, or take the source
#    version with `chezmoi apply --force <path>`. Then apply again.
chezmoi apply

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
chezmoi apply                        # full apply, behind the apply guard
agent-config-sync apply              # source check, full apply, live check
agent-config-sync sync               # fast-forward dotfiles and AgentMemory, then apply
chezmoi cd                           # open the source repository
```

## What's managed

- **Shell**: `.zshrc`, `.zshenv`, `.bashrc`, `.bash_profile`; `.p10k.zsh` (Linux only)
- **Git**: `.gitconfig`, `~/.config/git/`
- **Terminals**: `~/.config/ghostty/`; Linux only: `~/.config/alacritty/`
- **Editors**: `~/.config/Code/User/{settings,keybindings,mcp,snippets}.json`, `~/.config/micro/`, `~/.config/nvim/` (LazyVim). VS Code `settings.json` is a modify template that keeps the theme line Omarchy writes.
- **Defaults / environment** (Linux only): `mimeapps.list`, `user-dirs.dirs`, `user-dirs.locale`, `environment.d/`, `systemd/user/`, `omarchy/plugins/`
- **Fonts / input**: `~/.config/fontconfig/`; `.XCompose` (Linux only)
- **AI tooling**:
  - Shared policy: `.chezmoitemplates/agents-shared*.md`
  - Global Claude adapter: `~/.claude/CLAUDE.md` (unrestricted `claude` shell wrapper)
  - Global Codex adapter: `~/.codex/AGENTS.md` (unrestricted `codex` shell wrapper)
  - Other harness adapters: Grok, Pi, OMP
  - Portable skills: `~/.agents/skills` (canonical). Each harness gets a skill through a `symlink_<skill>` file in its skills directory; `dot_agents/skill-targets.json.tmpl` derives the registry from those links
  - Sync CLI: `agent-config-sync` (`check` | `check-live` | `apply` | `sync` | `doctor`)
  - Skills, prompts, and harness configuration are plaintext and meant to be read. See [Secrets](#secrets-age-encryption) for the encrypted key bundle.
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
agent-config-sync apply       # source check, guarded full apply, live check
agent-config-sync sync        # fast-forward dotfiles and AgentMemory, then run apply
```

Every full apply runs `scripts/apply-guard.sh` first, through `run_before_00-apply-guard.sh`. That covers `chezmoi apply`, `chezmoi update`, and `agent-config-sync apply`. The guard stops the apply when a target holds a live edit made since the last apply, a file that existed before chezmoi managed it, or a live directory that a file or link would replace. A scoped `chezmoi apply <path>` runs no scripts, so it skips the guard. Use it to resolve a path that the guard reported. Do not give a full apply `--keep-going`, or an `--include` or `--exclude` that leaves out scripts: the first ignores the guard's failure, and the others skip the guard. Do not sync credentials, sessions, histories, caches, or other machine-owned runtime state.

### Agent doctor

Each computer declares only the harnesses, Pi providers, MCP servers, and
standalone pi-kit lane routes it requires in the deliberately unmanaged
`~/.config/agent-config-sync/doctor.json`. The example below reflects the
current pi-kit setup: `openai-codex` selectors dispatch
through Pi's native route, while the Anthropic Fable/Opus selectors
dispatch through genuine Claude Code child processes — Anthropic is the
Claude Code route, never a Pi provider. Core Pi has no MCP of its own, so only
`pickforge-lanes` under `mcp.claude` is required here:

```json
{
  "version": 1,
  "harnesses": ["claude", "codex", "pi", "ollama"],
  "providers": {"pi": ["openai-codex"]},
  "mcp": {"claude": ["pickforge-lanes"]},
  "lanes": {
    "pi": ["openai-codex/gpt-6-astra", "openai-codex/gpt-6.1-sol"],
    "claude-code": ["anthropic/claude-fable-5-1", "anthropic/claude-opus-5-5"]
  }
}
```

Unlisted tools are ignored. `lanes` is optional and backward compatible: a
machine that omits it (or any prior requirements file written before lanes
existed) gets no lane checks at all. When `lanes.pi` is nonempty, `pi` must be
in `harnesses`; when `lanes["claude-code"]` is nonempty, `claude` must be in
`harnesses` too — the doctor rejects an inconsistent requirements file before
running any checks.

For each required lane selector the doctor statically reads and parses the
pi-kit runtime's `MODEL_TABLE` as text — via a local, no-network
`bun --no-install` invocation of a doctor-owned parser that only does
`readFile`/regex/brace-depth scanning and never imports, requires, or
evaluates the runtime file — and confirms the selector exists, is declared on
the expected route, and carries the `pi` origin — every `lanes.pi` and
`lanes["claude-code"]` selector is a Pi native lane, so a route match with a
missing or different origin still fails. The table contents are never
printed, only pass/fail per selector, and a malformed table (missing
declaration, unbalanced braces, unquoted/duplicate fields) is reported as a
required failure rather than silently accepted. It
also checks that the runtime package directory, `package.json`, and each
catalog-declared required runtime file (the lane extension, the Pi and Claude
Code adapters, the model table, and the MCP server entry point) are present,
that `package.json`'s `.pi.extensions` actually declares the lane extension,
and that `~/.pi/agent/settings.json` loads the pi-kit package. Each required
Pi lane selector's provider is derived directly from the selector itself —
the substring before its first `/` — with no separate catalog-side mapping to
keep in sync; a selector with no `/` or with an `anthropic` prefix (Anthropic
is routed through Claude Code, never through `providers.pi`) is rejected
outright, and any other derived provider must be present in `providers.pi`.
For `claude-code` selectors it independently finds at least one eligible
Claude Code executable on `PATH` — rejecting wrapper scripts whose shebang'd
body contains the known literal bypass flags `--dangerously-skip-permissions`
or `--permission-mode=bypassPermissions` (or the space-separated form), the
same way the runtime adapter does — and checks that its version is at least
`2.1.216`. This is a known-bypass-wrapper check, not an exhaustive safety
guarantee: it does not detect every possible way a wrapper could grant
bypass permissions. None of this is a login check: use `agent-config-sync
doctor --online` for that.

```bash
agent-config-sync doctor                 # local installation, configuration, and lane wiring
agent-config-sync doctor --online        # add noninteractive login-status probes
agent-config-sync doctor --deep          # add safe HTTP MCP reachability checks
agent-config-sync doctor --only pi       # one required harness (and its lane checks, if any)
agent-config-sync doctor --json          # stable machine-readable results
agent-config-sync doctor --ascii         # ASCII symbols for limited terminals
```

Human output uses symbols and automatic terminal colors. `NO_COLOR` and
`--color=never` disable color. The doctor never logs in, installs packages,
starts MCP OAuth, executes stdio MCP servers or configured credential commands,
dispatches a real Pi or Claude Code lane, prints credential values, wrapper
contents, or child process output, or claims that locally detected
credentials are remotely valid. Requiring `pickforge-lanes` under
`mcp.claude` reuses the existing generic MCP static check: it verifies the
server is registered and its command is executable, nothing more — `--deep`
still refuses to execute stdio MCP transports. Live lane dispatch (actually
running a Pi or Claude Code lane end to end) is a separate manual
verification, not something the doctor runs by default. Run the full
hermetic validation explicitly with `bash scripts/check-agent-doctor.sh`.

## Secrets (age encryption)

Exactly one file holds ciphertext: `.secrets.json.age` at the source root. It stores static API keys as an age-encrypted JSON object. Dot-prefixed source files are not managed targets. The age identity stays at `~/.config/chezmoi/key.txt` with mode 0600.

The readable templates are `dot_pi/agent/private_mcp.json.tmpl`, `dot_agents/private_deepseek.env.tmpl`, and `dot_agents/private_stripe.env.tmpl`. Each uses `.chezmoitemplates/secret` to read a named value from the bundle. The Stripe MCP header reuses `stripe_restricted_key`. All three targets have mode 0600. Never print their rendered contents or include them in a diff.

Pi provider auth, Pi MCP OAuth tokens, and Context7 OAuth credentials stay machine-owned. The source omits `.pi/agent/auth.json`, `.pi/agent/mcp-oauth`, and `.context7/credentials.json`. `.chezmoiignore` protects those paths. Log in again on a new machine.

Skills, prompts, rules, hooks, and harness configuration remain readable. `scripts/check/encryption-policy-checks.sh` checks both policy directions. It rejects ciphertext without a declared reason and plaintext credential files. It also renders all three secret templates without printing values.

For a new machine, restore the saved identity before initialization:

```bash
mkdir -p ~/.config/chezmoi
# Copy the saved identity to ~/.config/chezmoi/key.txt securely.
chmod 0600 ~/.config/chezmoi/key.txt
chezmoi init git@github.com:ElbertePlinio/dotfiles.git
```

`.chezmoi.toml.tmpl` creates the age config during init. It sets encryption, the identity path, and the public recipient. Keep an encrypted backup of the identity off-machine. A new identity cannot decrypt the existing bundle.

Edit the readable template when changing configuration or comments. Edit the bundle when adding or changing a static key. Use stable snake_case key names and reuse existing credentials. Keep plaintext only in a 0600 temporary file, then remove it:

```bash
(
  set -eu
  umask 077
  source_dir="$(chezmoi source-path)"
  secret_tmp="$(mktemp "${TMPDIR:-/tmp}/chezmoi-secrets.XXXXXX")"
  trap 'rm -f "$secret_tmp"' EXIT
  chezmoi decrypt "$source_dir/.secrets.json.age" >"$secret_tmp"
  # Use an editor that disables swap files, backups, and history.
  vim -n -i NONE -u NONE -c 'set nobackup nowritebackup' "$secret_tmp"
  chezmoi encrypt "$secret_tmp" --output "$source_dir/.secrets.json.age"
)
```

The trap removes the temporary file on exit. Do not copy plaintext into the source or print it during validation. Confirm that each template still renders with `chezmoi execute-template --file <source-template> >/dev/null`.

If the identity leaks, treat every key in the bundle as leaked. Rotate each key with its provider, create a new identity, update the recipient in `.chezmoi.toml.tmpl`, and encrypt the bundle again.

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

Static API keys live in the encrypted bundle (see [Secrets](#secrets-age-encryption)). Codex, Pi, and Context7 login state stays machine-owned. Back up runtime data separately if needed:

| Path               | Contents                                  |
|--------------------|-------------------------------------------|
| `~/.claude.json`   | Claude Code auth / session                |
| `~/.hermes/`       | Hermes data (unmanaged; single source of truth lives on this machine) |
| `~/.codex/sessions`, `logs_*.sqlite*`, `memories/` | Codex runtime state |
| `~/.copilot/`      | GitHub Copilot token                      |

```bash
tar --zstd -cf - -C ~ \
  .claude.json .hermes .copilot \
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
5. **Age identity** → restore `~/.config/chezmoi/key.txt` (0600) before `chezmoi init` creates the config. See [Secrets](#secrets-age-encryption).
6. **Dotfiles** → initialize the repo, review source and `chezmoi status`, apply interactively, then run `agent-config-sync apply`.
7. **SSH/GPG** → decrypt `secrets.tar.age` into `$HOME`.
8. **Browsers** → extract tarballs (browsers closed).
9. **AI state** → decrypt and extract if kept.
10. **Verify** → `ssh-add -l`, `gpg --list-secret-keys`, re-login to pick up shell config, open each browser.

## License

[MIT](LICENSE).
