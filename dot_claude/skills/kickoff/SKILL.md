---
name: kickoff
description: Start a substantial task with the full delivery flow — model-orchestrated workers, GitHub Issue planning for Pickforge repos, branch/worktree discipline, and ship-pr to merge. Use at the start of any feature, refactor, or multi-file change, or whenever the user runs /kickoff.
---

# Kickoff

Set up the standard delivery flow for the task in $ARGUMENTS, then execute it. This skill is the answer to "which workflow?" — don't ask, route:

1. **Delegation** — select workers per the `model-orchestration` skill; its routing reference is `references/model-routing.md`. Do not force a model chain or delegate work whose overhead exceeds its value.
2. **Planning** — substantial work in a repo under `~/Projects/Pickforge` gets a GitHub Issue via `plan-issue` before building. For features, apply the feature-flag decision rule from the workspace `AGENTS.md` ("Feature flags") and record flag-or-no-flag (and the flag name) in the issue.
3. **Shipping** — work on a branch; use a worktree (`~/Projects/.worktrees/<repo>/<branch>`) for risky or multi-step changes. When a unit is behaviorally validated, run `local-review`, then `ship-pr` to open the PR, watch CI, and merge. Independent units → parallel branches and PRs.

Pick delivery depth based on the task. If it is genuinely trivial, just do it. Re-evaluate when scope grows.

If $ARGUMENTS is empty, ask what the task is before routing.
