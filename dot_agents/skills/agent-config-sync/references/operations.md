# Agent configuration operations

Use this reference for first-machine setup and requests scoped to one harness. The
canonical repository is `~/.local/share/chezmoi`; rendered files under `$HOME`
are never the source of truth.

## First machine bootstrap

The skill cannot bootstrap itself. Before an agent can use it:

1. Install `chezmoi`, `age`, `git`, and the system GitHub CLI (`gh`),
   which `agent-config-sync apply` requires for its Personal GitHub safety link.
2. Restore `~/.config/chezmoi/key.txt` and recreate the age configuration.
3. Verify `ssh -T git@github.com` succeeds before apply. A managed `run_after_`
   script clones `pickforge-platform`, which provides the local Pi `pi-kit`.
4. Run `chezmoi init git@github.com:ElbertePlinio/dotfiles.git`.
5. Review the diff, then run `chezmoi apply --interactive`.
6. Start a new shell and reload/restart the harness.
7. Run `agent-config-sync check-live`.

The first apply installs both `~/.local/bin/agent-config-sync` and the canonical
skill at `~/.agents/skills/agent-config-sync`. Harness links become available
after apply. Authentication, credentials, sessions, and caches are separate and
must not be copied from the repository.

## Scope semantics

`agent-config-sync` currently accepts only `check`, `check-live`, and `apply`.
It has no harness argument. Never run `agent-config-sync apply pi` or similar:
extra arguments are not a scope contract and full apply may touch other
harnesses.

Interpret requests as follows:

- **Sync only `<harness>`:** change only that harness adapter/native source and
  its declared skill links. Preserve shared templates and every other harness.
  Use scoped `chezmoi diff` and `chezmoi apply` targets.
- **Sync a shared/global rule:** update the shared templates and all applicable
  adapters, then use the full `agent-config-sync apply` workflow.
- **Sync a portable skill:** edit the canonical skill, update
  `dot_agents/skill-targets.json`, and update only compatible declared links.
- **Sync a harness-native skill or extension:** keep it under that harness; do
  not promote it to the portable registry without an explicit portability
  decision.

Always run the full read-only `agent-config-sync check` before and after edits.
For a harness-only request, use `check-live` plus scoped target validation after
the scoped apply. Run full `apply` only when its preflight is clean and touching
all registered targets matches the requested scope.

## Harness map

| Harness | Adapter source | Rendered adapter | Native/config source |
|---|---|---|---|
| Claude | `dot_claude/CLAUDE.md.tmpl` | `~/.claude/CLAUDE.md` | `dot_claude/` |
| Codex | `dot_codex/AGENTS.md.tmpl` | `~/.codex/AGENTS.md` | `dot_codex/` |
| Grok | `dot_grok/AGENTS.md.tmpl` | `~/.grok/AGENTS.md` | `dot_grok/` |
| Pi | `dot_pi/agent/AGENTS.md.tmpl` | `~/.pi/agent/AGENTS.md` | `dot_pi/agent/` |
| OMP | `dot_omp/agent/AGENTS.md.tmpl` | `~/.omp/agent/AGENTS.md` | `dot_omp/agent/` |
| Hermes | `private_dot_hermes/SOUL.md.tmpl` | `~/.hermes/SOUL.md` | `private_dot_hermes/` |

Shared behavior is composed from `.chezmoitemplates/agents-shared*.md`. Do not
edit a harness adapter for a genuinely shared rule merely to avoid updating the
other applicable adapters.

### Pi-only boundary

Typical Pi targets are:

- `dot_pi/agent/AGENTS.md.tmpl`
- `dot_pi/agent/encrypted_settings.json.age`
- `dot_pi/agent/encrypted_models.json.age`
- `dot_pi/agent/encrypted_mcp.json.age`
- `dot_pi/agent/extensions/`
- `dot_pi/agent/skills/`
- Pi-specific shell/bootstrap helpers explicitly required by those resources

Render or diff only the corresponding paths under `~/.pi/agent` and any named
helper path. Do not include OMP just because both harnesses share agent concepts.

### OMP-only boundary

Typical OMP targets are:

- `dot_omp/agent/AGENTS.md.tmpl`
- `dot_omp/agent/config.yml`
- `dot_omp/agent/mcp.json`
- `dot_omp/agent/agents/`
- `dot_omp/agent/extensions/`
- `dot_omp/agent/skills/`

Render or diff only the corresponding paths under `~/.omp/agent`.

## Portable skills

Canonical skill content lives under `dot_agents/skills/` and renders to
`~/.agents/skills/`. `dot_agents/skill-targets.json` is the distribution source
of truth:

- `canonical` means the harness reads `~/.agents/skills` directly.
- `symlink` means the harness source contains a managed relative link.
- Absence from a skill's target list means do not distribute it there.

A harness-only request may repair that harness's existing declared links. It
must not silently add the harness to a portable skill's target list.

## Never sync

Do not manage credentials, OAuth tokens, sessions, histories, caches, databases,
locks, usage counters, generated package installs, or transient extension
state. Follow `.chezmoiignore` and the runtime exclusions enforced by
`scripts/check-agent-config-sync.sh`.

## Completion evidence

A scoped sync is done only when:

1. Source and live paths are named explicitly.
2. Unrelated dirty and untracked files remain untouched.
3. `agent-config-sync check` has no new failure.
4. Scoped `chezmoi diff` is reviewed and the scoped apply succeeds.
5. `agent-config-sync check-live` passes or any unrelated pre-existing failure
   is reported precisely.
6. The narrowest harness-specific behavioral validation passes.
