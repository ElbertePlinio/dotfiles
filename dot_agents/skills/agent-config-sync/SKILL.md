---
name: agent-config-sync
description: Use when updating or syncing global agent instructions, portable skills, or harness configuration through chezmoi.
---

Resolve the source with `chezmoi source-path`. Edit that source, never only rendered files under `$HOME`. Inspect relevant source status and preserve unrelated work. Scope chezmoi diff, status, and verify to explicit paths; whole-tree runs can hang on encrypted files.

Shared rules belong in `.chezmoitemplates/agents-shared*.md` and applicable adapters. Harness-only changes stay in that harness. Repo rules stay repo-local unless a global change was requested. Portable skills belong in `dot_agents/skills/`, with capability-aware distribution in `dot_agents/skill-targets.json` and declared links. Harness-native skills stay native.

Read [operations](references/operations.md) for commands, bootstrap, harness ownership, and scoped apply. An authorized implementation includes relevant validation and apply within the requested scope unless the user limits it. Do not ask again for the same authorization. Assessment requests do not authorize edits; changes to architecture, persistence, auth, security, or scope still need approval.

For an authorized full agent apply, use `agent-config-sync apply`: it performs source validation, strict live preflight, scoped apply, and live validation. Do not repeat those checks on the same revision. For source-only work, run `agent-config-sync check`; for live assessment, use `check-live`. Follow the operations reference for harness-only work rather than running full apply.

Keep credentials encrypted and never print secret values. Do not sync sessions, histories, caches, locks, counters, or generated runtime state. Never overwrite a divergent live skill directory; strict preflight must block it for review.

Read [skill authoring](references/authoring.md) when creating or materially rewriting skills, and [behavior audits](references/behavior-audits.md) only for behavior-driven policy work. Report changed source paths, actual validation, any applied scope, and unresolved drift or risks.
