# Delegation Contract

Use this when preparing implementation prompts, reviewer prompts, dissent prompts, or fan-out work.

## Roles

- Codex: orchestration, task trimming, contract definition, validation, synthesis, final report.
- Writer: exactly one model writes a given file/worktree by default; independent writers should run in parallel in isolated worktrees.
- Reviewers: read-only agents that report concrete findings.
- Dissenters: read-only agents that challenge assumptions and risk.
- GLM-5.2: text-only Ollama reviewer/dissenter. Give it text/code only; if visual evidence matters, include an orchestrator-written image description.

## Handoff Prompt

Include:

- Task lane and chosen model.
- Repo path, branch, and worktree.
- User goal and acceptance criteria.
- Relevant AGENTS rules.
- Files and directories in scope.
- Files and directories out of scope.
- Non-goals and refactors to avoid.
- Frozen contract for APIs, types, payloads, state, permissions, persistence, and migrations.
- Validation commands to run.
- Expected output: changed files, validation, risks, next action.
- For GLM-5.2: explicit note that image/video/diagram evidence is unavailable unless described in text.

## Writer Rules

- Use one active writer unless parallel worktrees are already prepared.
- Tell the writer to make the smallest clean change.
- Tell the writer to preserve repo style and avoid unrelated refactors.
- Give exact files or directories when possible.
- For correction passes, send only concrete, valid findings.

## Parallel Work

- Use isolated worktrees under `~/Projects/.worktrees/<repo-name>/<branch-name>`.
- Do not let two writers edit the same worktree.
- Parallelize whenever dependencies allow it: scouting, implementation units, reviews, validation commands, and PR preparation should overlap instead of waiting serially.
- Split independent issues/features into one branch/worktree per unit. For eligible shipping flows, use `$ship-pr` per completed branch and run multiple PRs in parallel when their scopes do not overlap.
- Keep a small active wave: enough parallelism to keep models busy, but not so much that review/triage becomes the bottleneck. A good default is 2-4 builders plus the review panel.
- Ask each writer for a patch or changed-file summary.
- Review patches before integrating.
- Serialize final integration, merge order, conflict resolution, and decisions that change architecture/contracts/security.

## Stop Conditions

Stop and report to the user when:

- The required CLI is missing or unauthenticated.
- A specifically requested model is unavailable and no user-approved fallback exists.
- A model lane cannot access the repo or allowed files.
- The decision changes architecture, persistence, auth, security, or scope and the user has not approved it.
- Validation cannot run and no narrower useful proof exists.
