---
name: agent-config-sync
description: Use when updating or syncing global agent instructions, portable skills, or harness configuration through chezmoi.
---

Resolve the source with `chezmoi source-path`. Edit that source, never only rendered files under `$HOME`. Inspect relevant source status and preserve unrelated work. Scope `chezmoi diff` to explicit paths, because whole-tree diffs open a pager and expose rendered credentials.

Shared rules belong in `.chezmoitemplates/agents-shared*.md` and applicable adapters. Harness-only changes stay in that harness. Repo rules stay repo-local unless a global change was requested. Portable skills belong in `dot_agents/skills/`. A harness receives a skill through a `symlink_<skill>` file in its skills source directory, and those links are the only distribution registry. Harness-native skills stay native.

Read [operations](references/operations.md) for commands, bootstrap, harness ownership, and harness-only apply. An authorized implementation includes relevant validation and apply within the requested scope unless the user limits it. Do not ask again for the same authorization. Assessment requests do not authorize edits; changes to architecture, persistence, auth, security, or scope still need approval.

For an authorized apply, use `agent-config-sync apply`: it validates the source, runs a full chezmoi apply behind the apply guard, and validates live state. Do not repeat those checks on the same revision. For source-only work, run `agent-config-sync check`; for live assessment, use `check-live`. Follow the operations reference for harness-only work rather than running full apply.

Keep credentials encrypted and never print secret values. Do not sync sessions, histories, caches, locks, counters, or generated runtime state. Never overwrite a divergent live skill directory. A full apply runs the apply guard, which blocks it for review. Before a scoped apply, run the guard yourself as the operations reference describes.

Read [skill authoring](references/authoring.md) when creating or materially rewriting skills, and [behavior audits](references/behavior-audits.md) only for behavior-driven policy work. Report changed source paths, actual validation, any applied scope, and unresolved drift or risks.
