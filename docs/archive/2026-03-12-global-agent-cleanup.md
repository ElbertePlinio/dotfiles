# Global Agent Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the split agent profiles with one unrestricted global Claude/Codex setup and retire Superpowers, RTK, Caveman, Personal Codex, and Personal GitHub safety tooling from dotfiles and this Mac.

**Architecture:** Keep one canonical `~/.claude` and `~/.codex`, with direct unrestricted shell wrappers. Remove retired source trees and use `.chezmoiremove` for stable cross-machine cleanup; remove generated caches and the Homebrew RTK package only after source validation. Simplify `agent-config-sync` and its regression suite to describe only the remaining architecture.

**Tech Stack:** chezmoi, Bash 3.2-compatible shell, zsh, jq, age-encrypted JSON, Git, Homebrew.

**Spec:** `docs/specs/2026-03-12-single-global-agent-profile-design.md`

---

### Task 1: Restore a green portable preflight baseline

**Files:**
- Modify: `scripts/check-agent-config-sync.sh`
- Modify: `dot_local/bin/executable_agent-config-sync`

- [ ] **Step 1: Reproduce the two origin failures**

Run:

```bash
cd /Users/elberte/Projects/.worktrees/dotfiles/remove-split-claude-profile
bash scripts/check-agent-config-sync.sh
```

Expected: FAIL on the 12,500-byte shared-source/rendered budgets and macOS Bash missing `mapfile`.

- [ ] **Step 2: Replace `mapfile` with Bash 3.2-compatible collection**

Replace:

```bash
local skill harness src_root rel_prefix expected link_src
local -a skills

mapfile -t skills < <(jq -r '.skills | keys[]' "$MANIFEST")
```

with:

```bash
local skill harness src_root rel_prefix expected link_src
local -a skills=()

while IFS= read -r skill; do
  skills+=("$skill")
done < <(jq -r '.skills | keys[]' "$MANIFEST")
```

Search the rest of the script for additional `mapfile` calls and convert each to the same `while IFS= read -r` pattern without process-substitution subshell mutation.

Also replace the installed sync command's NUL-delimited preflight collection:

```bash
mapfile -d '' -t managed_targets < <(chezmoi ... --nul-path-separator ...)
```

with a Bash 3.2-compatible loop that preserves NUL delimiters:

```bash
local -a managed_targets=()
while IFS= read -r -d '' target; do
  managed_targets+=("$target")
done < <(
  chezmoi "${SRC[@]}" managed \
    --include=files,symlinks \
    --path-style=absolute \
    --nul-path-separator \
    "$@"
)
```

Do not convert NUL-delimited paths to newline parsing.

- [ ] **Step 3: Recalibrate the stale shared-size guard**

Keep the regression guard, but raise its hard ceiling from 12,500 to 15,000 bytes. After Tasks 3–8, update the recorded baseline to the exact final rendered byte count while retaining 15,000 as the explicit ceiling. Do not weaken adapter-specific budgets.

- [ ] **Step 4: Run the baseline check**

Run:

```bash
bash scripts/check-agent-config-sync.sh
```

Expected: PASS before architecture assertions are changed.

- [ ] **Step 5: Commit**

```bash
git add scripts/check-agent-config-sync.sh dot_local/bin/executable_agent-config-sync
git commit -m "fix(agent-config): support macOS preflight"
```

### Task 2: Add failing regression contracts for the retired architecture

**Files:**
- Modify: `scripts/check-agent-config-sync.sh`

- [ ] **Step 1: Add source-absence assertions**

Add a single helper-driven check covering these retired source roots/files:

```text
dot_claude-personal
dot_config/agent-profiles
dot_config/rtk
Projects/Personal/dot_codex
Projects/Personal/private_dot_agent-safety
dot_local/bin/executable_claude-profile
dot_local/bin/executable_claude-default
dot_local/bin/executable_claude-personal
dot_local/bin/executable_agent-profile-doctor
dot_claude/private_RTK.md
private_dot_factory/bin/executable_frun
.chezmoitemplates/claude-restricted.md
.chezmoitemplates/claude-personal-lite.md
```

Add JSON assertions that `skill-targets.json` has no `claude-portable` harness/targets and `dot_skill-lock.json` lacks `caveman`, `caveman-commit`, `caveman-compress`, `caveman-help`, `caveman-review`, `caveman-stats`, `cavecrew`, and `compress`.

Add rendered-policy assertions that:

- `~/.claude/CLAUDE.md` has no `@RTK.md`.
- `.agent-safety` instructions are absent.
- Pickforge/Personal push and ship permission text remains.
- Linux `claude-codex` selects global `~/.claude`, not `~/.claude-personal`.

- [ ] **Step 2: Run checks and confirm contract failure**

Run:

```bash
bash scripts/check-agent-config-sync.sh
```

Expected: FAIL only on newly asserted retired paths/references.

- [ ] **Step 3: Commit the failing contract**

```bash
git add scripts/check-agent-config-sync.sh
git commit -m "test(agent-config): define single-profile contract"
```

### Task 3: Collapse Claude and Codex to global shell profiles

**Files:**
- Modify: `dot_claude/CLAUDE.md.tmpl`
- Modify: `.chezmoitemplates/zshrc-common`
- Modify: `.chezmoitemplates/zshrc-linux`
- Modify: `dot_bashrc`
- Modify: `.chezmoitemplates/agents-shared-before-worktrees.md`
- Delete: `.chezmoitemplates/claude-restricted.md`
- Delete: `.chezmoitemplates/claude-personal-lite.md`
- Delete: `.chezmoitemplates/claude-core.md`
- Delete: `dot_config/agent-profiles/`
- Delete: `dot_local/bin/executable_claude-profile`
- Delete: `dot_local/bin/executable_claude-default`
- Delete: `dot_local/bin/executable_claude-personal`
- Delete: `dot_local/bin/executable_agent-profile-doctor`

- [ ] **Step 1: Make the Claude adapter unconditional**

Render only the existing main branch:

```gotemplate
# Global Claude Rules

{{ template "agents-shared.md" . }}

{{ template "claude-adapter-common.md" . }}

## Claude model orchestration

- For substantial or risky multi-model work, use the `model-orchestration` skill; pool metadata, compatibility constraints, selection axes, and escalation policy live in `~/.codex/skills/model-orchestration/references/model-routing.md`.
- Claude subagents use the Agent or Workflow model parameter. Workers and reviewers are leaves unless the main session explicitly authorizes fan-out.
- When Claude is invoked non-interactively as a worker under another orchestrator, do the assigned work directly and do not re-delegate.
```

Do not retain `agentProfile`, restricted-profile templates, or `@RTK.md`.

- [ ] **Step 2: Simplify zsh global wrappers**

Remove the Personal safety PATH and `_agent_personal_context`. Keep:

```zsh
claude() {
  command claude --dangerously-skip-permissions "$@"
}

codex() {
  command codex --yolo "$@"
}
```

Preserve unrelated aliases/work shell loading.

- [ ] **Step 3: Simplify bash Claude wrapper**

Replace launcher delegation with:

```bash
claude() {
  command claude --dangerously-skip-permissions "$@"
}
```

- [ ] **Step 4: Preserve Linux proxy/model wrappers against global Claude**

In `.chezmoitemplates/zshrc-linux`, change only:

```zsh
CLAUDE_CONFIG_DIR="$HOME/.claude-personal"
```

to:

```zsh
CLAUDE_CONFIG_DIR="$HOME/.claude"
```

Keep proxy URLs, token environment, model selection, and permission mode unchanged.

- [ ] **Step 5: Remove only Personal safety instructions**

Delete the `Personal project isolation` section and `verify-personal-github` requirement. Preserve Pickforge/Personal ownership, push, and ship permission rules under Git/PR policy. Delete the now-orphaned `claude-core.md` template rather than retaining restricted-profile prose.

- [ ] **Step 6: Delete profile launchers/config/templates and run focused checks**

Run:

```bash
rg -n 'agentProfile|claude-personal|claude-default|claude-profile|agent-profiles' \
  dot_claude .chezmoitemplates dot_bashrc dot_config dot_local README.md scripts/check-agent-config-sync.sh
```

Expected: only migration/removal assertions remain until later cleanup tasks.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "refactor(claude): use one global profile"
```

### Task 4: Remove portable Claude, Personal Codex, and Personal safety source

**Files:**
- Delete: `dot_claude-personal/`
- Delete: `Projects/Personal/dot_codex/`
- Delete: `Projects/Personal/private_dot_agent-safety/`
- Modify: `dot_agents/skill-targets.json`
- Modify: `.chezmoiignore`
- Modify: `.gitignore`

- [ ] **Step 1: Remove the retired source trees**

Use `git rm -r` for the three tracked roots. Do not inspect or print encrypted retired settings.

- [ ] **Step 2: Remove the `claude-portable` skill harness**

Delete `harnesses["claude-portable"]` and remove `claude-portable` from every skill target array. Validate with:

```bash
jq -e '
  (.harnesses | has("claude-portable") | not) and
  ([.skills[][]] | all(. != "claude-portable"))
' dot_agents/skill-targets.json
```

- [ ] **Step 3: Remove obsolete ignore entries**

Delete ignore rules that exist only for `.claude-personal`, Personal `.codex`, Personal `.agent-safety`, and `agentProfile` conditionals. Preserve unrelated runtime exclusions.

- [ ] **Step 4: Run manifest/source checks**

```bash
bash scripts/check-agent-config-sync.sh
```

Expected: remaining failures are confined to `agent-config-sync`, RTK, Caveman, docs, and removal migration.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor(agents): remove portable profile sources"
```

### Task 5: Retire RTK and frun

**Files:**
- Delete: `dot_claude/private_RTK.md`
- Delete: `dot_config/rtk/config.toml`
- Delete: `private_dot_factory/bin/executable_frun`
- Modify: `.chezmoitemplates/agents-shared-before-worktrees.md`
- Modify: `dot_config/opencode/README.md`
- Modify: `.chezmoiignore`

- [ ] **Step 1: Remove managed RTK/frun files**

Use `git rm` for the three tracked files/directories.

- [ ] **Step 2: Remove RTK/frun instructions**

Delete recommendations to run `frun`, prefix commands with `rtk`, or import `RTK.md`. Remove the stale OpenCode RTK plugin section and index entry. Do not replace command rewriting.

- [ ] **Step 3: Prove no active source references remain**

```bash
rg -n -i --hidden --glob '!docs/specs/**' --glob '!docs/plans/**' --glob '!.git/**' \
  '\brtk\b|RTK\.md|\bfrun\b' .
```

Expected at this stage: `.chezmoiremove`/regression assertions plus stale RTK handling in `dot_local/bin/executable_agent-config-sync` and `scripts/check-agent-config-sync.sh`, which Task 8 removes. No other active runtime/docs references may remain.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "refactor(agents): retire rtk tooling"
```

### Task 6: Retire Caveman and Superpowers

**Files:**
- Modify: `dot_agents/dot_skill-lock.json`
- Modify encrypted source: `dot_claude/encrypted_settings.json.age`
- Modify: `dot_config/opencode/AGENTS.md`

- [ ] **Step 1: Remove Caveman-family lock entries**

Use jq to delete exactly:

```jq
del(
  .skills.caveman,
  .skills["caveman-commit"],
  .skills["caveman-compress"],
  .skills["caveman-help"],
  .skills["caveman-review"],
  .skills["caveman-stats"],
  .skills.cavecrew,
  .skills.compress
)
```

Preserve all unrelated lock metadata.

- [ ] **Step 2: Safely edit encrypted Claude settings**

From the worktree, run `chezmoi -S "$PWD" edit ~/.claude/settings.json` with a local editor and remove only:

```text
enabledPlugins["caveman@caveman"]
extraKnownMarketplaces.caveman
```

Never print the decrypted file. Render to a `0600` temporary file only for structural validation, then delete it:

```bash
umask 077
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
chezmoi -S "$PWD" cat ~/.claude/settings.json >"$tmp"
jq -e '
  (.enabledPlugins | has("caveman@caveman") | not) and
  (.extraKnownMarketplaces | has("caveman") | not)
' "$tmp"
rm -f "$tmp"
trap - EXIT
```

- [ ] **Step 3: Remove Caveman mode prose**

Delete the Caveman communication-mode block from `dot_config/opencode/AGENTS.md`; preserve unrelated OpenCode policy.

- [ ] **Step 4: Prove registries/settings are clean**

```bash
jq -e '[.skills | keys[] | select(test("caveman|cavecrew|^compress$"; "i"))] | length == 0' dot_agents/dot_skill-lock.json
```

Run the encrypted structural validation from Step 2 again.

- [ ] **Step 5: Commit**

```bash
git add dot_agents/dot_skill-lock.json dot_claude/encrypted_settings.json.age dot_config/opencode/AGENTS.md
git commit -m "refactor(agents): retire caveman tooling"
```

### Task 7: Add deterministic cross-machine removals

**Files:**
- Create: `.chezmoiremove`
- Modify: `scripts/check-agent-config-sync.sh`

- [ ] **Step 1: Declare stable retired targets**

Create `.chezmoiremove` with exact paths, one per line:

```text
.claude-personal
.config/agent-profiles
.config/rtk
.local/bin/agent-profile-doctor
.local/bin/claude-default
.local/bin/claude-personal
.local/bin/claude-profile
.factory/bin/frun
.claude/RTK.md
Projects/Personal/.codex
Projects/Personal/.agent-safety
.agents/skills/superpowers
.config/superpowers
.codex/superpowers
.agents/skills/caveman
.agents/skills/caveman-commit
.agents/skills/caveman-compress
.agents/skills/caveman-help
.agents/skills/caveman-review
.agents/skills/caveman-stats
.agents/skills/cavecrew
.agents/skills/compress
```

Do not add broad cache wildcards.

- [ ] **Step 2: Validate the removal contract in a temporary destination**

Seed sentinel files beneath representative retired directories and unrelated global Claude/Codex directories. Run a dry-run first, then `chezmoi -S "$PWD" -D "$DEST" apply --force --no-tty`. Assert retired sentinels are gone and unrelated/global targets remain.

- [ ] **Step 3: Update regression assertions**

Require every stable retired target in `.chezmoiremove` and reject broad plugin/cache wildcard patterns.

- [ ] **Step 4: Commit**

```bash
git add .chezmoiremove scripts/check-agent-config-sync.sh
git commit -m "feat(agent-config): remove retired agent state"
```

### Task 8: Simplify agent-config-sync and documentation

**Files:**
- Modify: `dot_local/bin/executable_agent-config-sync`
- Modify: `scripts/check-agent-config-sync.sh`
- Modify: `README.md`
- Modify: `.gitignore`
- Modify: `.chezmoiignore`

- [ ] **Step 1: Remove split-profile orchestration from the installed sync command**

Delete:

- `LIVE_PROFILE_ROLE`/`PROFILE_ROLE` validation.
- Personal safety link/preflight logic.
- restricted-to-main migration functions.
- portable skill cleanup/link logic and the `--require-portable-links` post-apply flag.
- split-profile target arrays and checks.
- RTK target validation/removal.

Replace the old scoped split-profile target array with one full managed-source apply after strict preflight:

```bash
chezmoi "${SRC[@]}" apply --force --no-tty
```

This is required so `.chezmoiremove` entries execute. Keep credential/runtime exclusions and all unrelated strict preflight behavior.

- [ ] **Step 2: Remove obsolete test fixtures and migrations**

Delete tests for restricted rendering, portable launchers, portable environment stripping, Personal Codex symlinks, Personal GitHub wrappers, legacy portable skill reapply, and RTK transition. Replace with single-profile rendering, wrapper, policy-preservation, `.chezmoiremove`, and clean-up assertions from Tasks 2/7.

- [ ] **Step 3: Update README and ignore rules**

Document only global `claude`/`codex`, active harnesses, and remaining skills. Remove split profile, Superpowers, RTK, Caveman, Personal Codex/safety references. Keep runtime ignore entries that protect active credentials/sessions.

- [ ] **Step 4: Run complete source validation**

```bash
bash scripts/check-agent-config-sync.sh
agent-config-sync check-live
```

Expected: the source check passes. For live-flow validation before local apply, render the new `~/.local/bin/agent-config-sync` and managed targets into a temporary HOME/destination and run its `check-live` there; do not invoke the stale installed command as evidence for the new workflow.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor(agent-config): remove split-profile workflow"
```

### Task 9: Behavioral validation and local review

**Files:**
- Test only; fix only scoped defects found.

- [ ] **Step 1: Run static absence checks**

```bash
rg -n -i --hidden --glob '!.git/**' --glob '!docs/specs/**' --glob '!docs/plans/**' \
  'claude-personal|claude-default|claude-profile|agentProfile|agent-profiles|Projects/Personal/\.codex|\.agent-safety|superpowers|\brtk\b|RTK\.md|\bfrun\b|caveman|cavecrew' .
```

Expected: only explicit `.chezmoiremove` and regression-assertion references.

- [ ] **Step 2: Render and verify active targets in a temporary HOME**

Run `chezmoi apply` against a temporary destination, then verify:

- Global Claude policy/settings render.
- Global Codex stays intact.
- zsh/bash wrappers invoke unrestricted global commands.
- Linux proxy wrappers use `~/.claude`.
- Retired targets are absent.
- Remaining skill symlinks resolve.

- [ ] **Step 3: Run full checks**

```bash
bash scripts/check-agent-config-sync.sh
bash -n scripts/check-agent-config-sync.sh
bash -n dot_local/bin/executable_agent-config-sync
zsh -n .chezmoitemplates/zshrc-common
rendered_zsh=$(mktemp)
trap 'rm -f "$rendered_zsh"' EXIT
chezmoi -S "$PWD" execute-template <.chezmoitemplates/zshrc-linux >"$rendered_zsh"
zsh -n "$rendered_zsh"
rm -f "$rendered_zsh"
trap - EXIT
bash -n dot_bashrc
git diff --check
```

Expected: all PASS.

- [ ] **Step 4: Run `$local-review`**

Review the focused branch after behavioral validation. Resolve every valid finding and rerun the narrow affected checks; reuse the original implementation owner for fixes.

- [ ] **Step 5: Decision audit**

Record all implementation choices not fixed by the spec, especially any changed removal path, budget value, generated cache scope, or preserved policy text. Do not ship with unresolved low-confidence choices.

### Task 10: Ship, apply locally, and remove generated state

**Files:**
- Source unchanged unless final validation finds a scoped defect.
- Local destructive migration paths explicitly approved by the user.

- [ ] **Step 1: Verify Personal GitHub identity before removing the guard**

```bash
~/Projects/Personal/.agent-safety/verify-personal-github
```

Expected: confirms `ElbertePlinio`; stop on failure.

- [ ] **Step 2: Push/open PR using the normal ship workflow**

Use Conventional Commits already present, required checks, and local review evidence. Merge only when checks/review are complete.

- [ ] **Step 3: Pull merged origin into canonical chezmoi source**

```bash
git -C ~/.local/share/chezmoi pull --ff-only origin main
```

- [ ] **Step 4: Preview the local migration**

```bash
chezmoi apply --dry-run --verbose
```

Review every removal. Stop if any unrelated path would change.

- [ ] **Step 5: Bootstrap the new sync command, then apply managed changes**

The installed command is still the old split-profile version after pulling source. Apply only its replacement first:

```bash
chezmoi apply --force --no-tty -- ~/.local/bin/agent-config-sync
agent-config-sync apply
```

The new `agent-config-sync apply` runs strict preflight and then a full managed-source `chezmoi apply`, so `.chezmoiremove` entries execute. Expected: bootstrap, strict preflight, full apply, and live check pass.

- [ ] **Step 6: Remove generated local remnants**

Delete only confirmed Superpowers/Caveman generated state under:

```text
~/.claude/plugins/cache/*superpowers*
~/.claude/plugins/data/*superpowers*
~/.claude/plugins/cache/caveman
~/.claude/plugins/data/caveman-caveman
~/.claude/plugins/marketplaces/caveman
~/.codex/.tmp/plugins/plugins/superpowers
~/.grok/marketplace-cache/* paths proven to belong to Caveman
```

Inspect ownership/name before deletion; do not delete whole unrelated cache roots.

- [ ] **Step 7: Uninstall RTK from this Mac**

Identify its Homebrew owner without guessing:

```bash
brew list --formula | grep -Fx rtk
```

If exactly `rtk` is returned:

```bash
brew uninstall rtk
```

If ownership differs, stop and report instead of deleting `/opt/homebrew/bin/rtk` manually.

- [ ] **Step 8: Final live proof**

```bash
agent-config-sync check
agent-config-sync check-live
chezmoi verify -- ~/.agents ~/.claude ~/.codex ~/.grok ~/.pi/agent ~/.omp/agent ~/.factory ~/.hermes ~/.config/opencode
command -v rtk && exit 1 || true
find ~/.agents ~/.claude ~/.codex ~/.grok ~/.config -maxdepth 5 \
  \( -iname '*superpower*' -o -iname '*rtk*' -o -iname '*caveman*' \) -print
```

Expected: checks pass, RTK is absent, and the final `find` has no retired live paths except unrelated historical text explicitly reviewed and accepted.
