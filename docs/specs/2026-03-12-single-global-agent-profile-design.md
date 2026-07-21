# Single Global Agent Profile and Retired Tooling Design

## Goal

Use one unrestricted personal agent configuration on every synced machine and permanently retire the split Claude profile, Personal Codex routing, Personal GitHub safety layer, Superpowers, RTK, and the Caveman family.

`claude` uses `~/.claude`; `codex` uses `~/.codex`. Retired source and live state disappear on the next dotfiles apply.

## Scope

### Split profile

Remove:

- `~/.claude-personal` and its source adapter, settings, rules, sessions, and skill links.
- `claude-default`, `claude-personal`, `claude-profile`, and `agent-profile-doctor` launchers.
- `~/.config/agent-profiles`, the `agentProfile` main/restricted rendering split, and orphaned `claude-restricted.md`/`claude-personal-lite.md` templates.
- `~/Projects/Personal/.codex`, Personal `CODEX_HOME` routing, and related shell branches.
- `~/Projects/Personal/.agent-safety`, its PATH injection, GitHub identity guard, hooks, and shared instructions.
- Portable-profile registry entries, documentation, ignore rules, migrations, and validation.

### Superpowers

Remove the unmanaged canonical/live installations and harness copies, including:

- `~/.agents/skills/superpowers`.
- `~/.config/superpowers`.
- `~/.codex/superpowers` and transient Codex plugin copies.
- Installed Claude plugin cache/data for Superpowers where present.

Superpowers is not represented by an active canonical skill in the dotfiles source. Design and plan documents move to neutral `docs/specs` and `docs/plans` directories so the retired product name is not retained as workflow architecture.

### RTK

Remove:

- `dot_claude/private_RTK.md`, rendered `~/.claude/RTK.md`, and every `@RTK.md` import.
- `dot_config/rtk` and rendered `~/.config/rtk`.
- RTK recommendations in shared/Claude instructions and OpenCode documentation.
- RTK validation and migration logic in `agent-config-sync`.
- The `frun` wrapper because its only behavior is invoking RTK or transparently executing the original command.
- The Homebrew RTK package from this Mac after source validation.

No command-rewriting replacement is introduced.

### Caveman

Remove:

- Caveman-family entries from `dot_agents/dot_skill-lock.json`: `caveman`, `caveman-commit`, `caveman-compress`, `caveman-help`, `caveman-review`, `caveman-stats`, `cavecrew`, and the Caveman-sourced `compress` entry.
- Corresponding live directories under `~/.agents/skills`.
- The Caveman Claude plugin and marketplace declarations from the encrypted canonical Claude settings, edited without exposing credentials or unrelated values.
- Installed Claude plugin cache/data/marketplace state and Grok marketplace cache entries where present locally.
- Caveman communication-mode rules from OpenCode instructions and any harness documentation or validation references.

No replacement compression or terse-output skill is introduced.

### Keep

- The vendor `claude` executable and a minimal shell wrapper that calls it directly with `--dangerously-skip-permissions`.
- The global `~/.claude` main policy, settings, rules, hooks, remaining plugins, and remaining skills.
- The global `~/.codex` configuration, remaining skills, and unrestricted `--yolo` invocation.
- `agent-config-sync` and all unrelated portable skills/harness integrations.
- Existing protections unrelated to the retired Personal safety layer, including explicit confirmation for destructive operations.
- Existing Pickforge/Personal push and ship permission policy. Only the `.agent-safety` access/identity mechanism is removed; general repository ownership and delivery permissions remain unchanged.

## Architecture

There is one canonical Claude adapter. `dot_claude/CLAUDE.md.tmpl` always renders the current main/shared rules and Claude orchestration adapter without an `agentProfile` branch.

Shell configuration keeps direct unrestricted wrappers in both `.chezmoitemplates/zshrc-common` and `dot_bashrc`: `claude` invokes the vendor executable with `--dangerously-skip-permissions`; `codex` invokes the global executable with `--yolo`. Neither wrapper selects an alternate config directory or delegates through profile launchers.

Linux-only `claude-codex`, `claude-sol`, and `claudex` proxy/model wrappers remain available. They stop selecting `~/.claude-personal` and use the global `~/.claude` configuration while preserving their existing proxy URLs, model selection, environment overrides, and unrestricted permission mode.

Chezmoi source deletion only stops management, so `.chezmoiremove` declares stable retired targets such as profile directories, Personal Codex/safety directories, RTK state, and canonical Superpowers/Caveman skill directories. Transient cache paths whose names are generated are removed during the explicitly approved local migration rather than represented as broad permanent wildcards that might delete unrelated plugins.

Authentication, provider credentials, and active global histories remain outside source control. This migration intentionally deletes state beneath the retired profile/tool directories.

## Sync and Migration

`agent-config-sync` becomes single-profile and unaware of retired tooling:

- Remove role detection, restricted-profile preflight, portable-link maintenance, and split-profile checks.
- Remove RTK validation, transition, and target handling.
- Validate only active global Claude/Codex targets and portable skills declared for active harnesses.
- Add regression checks proving retired source paths, launchers, registry entries, and active textual references are absent except in `.chezmoiremove` and migration assertions.
- Preserve general Pickforge/Personal push and ship policy while removing only `.agent-safety`-specific access and identity checks.
- Fix the macOS Bash 3.2 `mapfile` incompatibility and shared-size regression budget as required migration prerequisites so preflight can complete before apply.
- Keep full apply safety checks and live verification for all remaining harnesses.

Upgrade path from an existing installation:

1. Pull origin.
2. Run `chezmoi apply --dry-run --verbose` and review intended removals.
3. Apply the updated source.
4. Remove generated local plugin/cache remnants and uninstall RTK on this Mac.
5. Run `agent-config-sync check`, `check-live`, and scoped `chezmoi verify`.

The update must not require bootstrapping a removed launcher or manually editing credentials.

## Security Consequences

The company machine no longer isolates personal Claude from ambient Bedrock/AWS variables or the active GitHub account. It receives the same unrestricted personal policy as other machines. Company isolation is explicitly deferred as a separate machine-local design.

Removing the Personal GitHub guard means mutations use the active `gh` identity without an automatic `ElbertePlinio` assertion. No replacement identity gate is included.

Removing Superpowers eliminates its mandatory planning/review workflow. Normal repository and global instructions remain authoritative.

## Validation

1. Static checks find no active references to split profiles, Personal Codex/safety routing, Superpowers, RTK, or Caveman, excluding explicit removal declarations and migration regression assertions.
2. Rendered `~/.claude/CLAUDE.md` contains the main shared policy and orchestration section without `@RTK.md`.
3. Decrypted canonical Claude settings contain neither the Caveman plugin nor marketplace while preserving all unrelated settings.
4. A temporary destination seeded with representative retired paths loses them after apply while global Claude/Codex targets remain.
5. Shell tests cover zsh and bash: `claude` and `codex` retain unrestricted modes with no profile launcher, Personal PATH, Personal `CODEX_HOME`, `frun`, or RTK routing; Linux proxy wrappers retain model/proxy behavior while using global `~/.claude`.
6. Shared policy tests prove `.agent-safety` instructions are absent while Pickforge/Personal push and ship permissions remain.
7. Skill-lock and live skill inventories contain no Caveman-family or Superpowers entries.
8. `command -v rtk` fails on this Mac after the approved Homebrew uninstall.
9. `agent-config-sync check` and `check-live` pass; macOS Bash portability and size-budget corrections are required, not optional.
10. Scoped `chezmoi verify` passes for every remaining managed harness target.

## Decisions

- Remove the split globally rather than add a per-host exception.
- Delete Personal Codex and GitHub safety tooling with the portable Claude profile.
- Remove Superpowers, RTK, and the complete Caveman family globally without replacements.
- Use `.chezmoiremove` for stable cross-machine cleanup and targeted local deletion for generated caches.
- Preserve unrestricted `claude` and `codex` modes with small direct wrappers; retain Linux proxy wrappers against global `~/.claude`.
- Preserve Pickforge/Personal push and ship permissions while removing their retired identity/access guard implementation.
- Uninstall RTK only from this Mac during this delivery; other machines stop receiving/configuring it and may remove independently installed binaries during their own migration.
- Keep unrelated credentials, histories, plugins, skills, and harness configuration unchanged.
