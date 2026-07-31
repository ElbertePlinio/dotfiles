---
name: agent-config-sync
description: Synchronize Elberte's global agent instructions and portable skills through chezmoi across Claude Code, Codex, Grok, Pi, OMP, and Hermes. Use when asked to update shared or harness-specific AGENTS.md, CLAUDE.md, Hermes SOUL.md, portable skills, skill distribution targets, or to check/apply agent configuration drift.
---

# Agent Config Sync

Resolve the source of truth with `chezmoi source-path` (usually `~/.local/share/chezmoi`). Never update only a rendered file under `$HOME`.

For first-machine setup or a harness-only request such as "sync only Pi", read [Agent configuration operations](references/operations.md) before selecting paths. The CLI has no harness scope argument.

## Scope

- Global/shared rule: update `.chezmoitemplates/agents-shared*.md` and every applicable adapter.
- Harness-specific rule: update only that harness adapter.
- Repo instruction: keep it repo-local unless the user explicitly asks for a global change.
- Portable skill: keep canonical content under `~/.agents/skills`, then update `dot_agents/skill-targets.json` and compatible harness symlinks.
- Harness-native skill: keep it under that harness only.

## Workflow

1. Read relevant AgentMemory and inspect chezmoi/git status. Preserve unrelated and untracked work.
2. Run `agent-config-sync check` before editing.
3. Edit the chezmoi source. For an encrypted canonical skill, use `chezmoi edit ~/.agents/skills/<name>/SKILL.md`; for a new skill, create it under `~/.agents/skills` and add it with `chezmoi add --encrypt`.
4. Keep portable-skill targets capability-aware. Do not distribute a skill to a harness that lacks its required tools.
5. Before adding or materially rewriting a skill, run the quality gate below.
6. Run `agent-config-sync check` and `agent-config-sync check-live`.
7. For shared/full scope, run `agent-config-sync apply`. For harness-only scope, use the reference's scoped `chezmoi apply` targets; never pass a harness name to the CLI.
8. Confirm `agent-config-sync check-live` passes and report source changes, validation, and unresolved risks.

## Behavior-driven policy updates

When updating policy from agent behavior:

1. Inspect only representative, relevant local sessions; categorize recurring or expensive failures.
2. For each category, ask why that path was chosen and whether current instructions contributed.
3. Record only anonymized categories and counts; never promote secrets or private/proprietary content.
4. Add permanent prose only for a demonstrated failure. Prefer machine gates for repeated corrections, and remove or narrow stale rules.
5. Report the sessions sampled, anonymized category counts, instruction contribution, and resulting prose/gate/removal decision.

## Skill quality gate

Apply when creating or materially rewriting any skill:

- **Description earns its trigger.** The frontmatter description states concretely when to use the skill; a model that has never seen the body can decide from the description alone.
- **Observable completion criteria.** The skill defines what "done" looks like in checkable terms, not vibes.
- **Progressive disclosure.** The SKILL.md body stays lean; deep material lives in `references/` and is linked, not inlined.
- **No duplication.** Check existing skills first; extend or improve one instead of adding an overlapping sibling.
- **No no-ops or sediment.** Remove steps that no harness can execute, references to retired skills/tools, and rules that restate global AGENTS.md policy.
- **Capability-aware targets.** Distribute only to harnesses that have the tools the skill requires (subagents, vision, MCP, gh, etc.).
- **Origin recorded.** Adapted third-party skills carry license and origin in frontmatter metadata.

## Boundaries

- Do not sync sessions, histories, caches, usage counters, locks, generated state, cron output, or background-process state.
- Keep credentials encrypted and never print secret values.
- Do not replace a divergent live skill directory; strict preflight must block it for review.
- Do not change architecture, persistence, auth, security, or scope without user approval.
- Do not stage, commit, or push unrelated dirty changes.
