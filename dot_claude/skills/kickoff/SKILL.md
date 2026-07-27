---
name: kickoff
description: Start a substantial task with the full delivery flow — model-orchestrated workers, GitHub Issue planning for Pickforge repos, branch/worktree discipline, and ship-pr to merge. Use at the start of any feature, refactor, or multi-file change, or whenever the user runs /kickoff.
---

# Kickoff

Set up the standard delivery flow for the task in $ARGUMENTS, then execute it. This skill is the answer to "which workflow?" — don't ask, route:

1. **Delegation** — invoke the `model-orchestration` skill (Skill tool) first, before repo exploration or any edit; its routing reference is `references/model-routing.md`. State the delegation decision in one sentence before the first Edit/Write. Solo implementation is allowed only after that sentence says why delegation overhead exceeds its value. Do not force a model chain. A PreToolUse gate blocks edits in kickoff sessions until model-orchestration is loaded.
2. **Planning** — substantial work in a repo under `~/Projects/Pickforge` gets a GitHub Issue via `plan-issue` before building. For features, apply the feature-flag decision rule from the workspace `AGENTS.md` ("Feature flags") and record flag-or-no-flag (and the flag name) in the issue.
3. **Shipping** — work on a branch; use a worktree (`~/Projects/.worktrees/<repo>/<branch>`) for risky or multi-step changes. When a unit is behaviorally validated, run `local-review`, then `ship-pr` to open the PR, watch CI, and merge. Independent units → parallel branches and PRs.

Pick delivery depth based on the task. If it is genuinely trivial, load model-orchestration, say so in the delegation decision, and just do it. Re-evaluate when scope grows.

If $ARGUMENTS is empty, ask what the task is before routing.
