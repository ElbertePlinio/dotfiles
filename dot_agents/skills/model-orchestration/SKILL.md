---
name: model-orchestration
description: Select compatible models and effort per call for substantial or risky work, using the current model table, validation evidence, and bounded complementary review. Use when explicit model selection, delegation, independent review, dissent, or fan-out materially improves the result.
---

# Model orchestration

The current session is the orchestrator: it owns scope, contracts, routing, synthesis,
validation, and final acceptance. Workers are leaves unless it explicitly authorizes
fan-out.

## Read what the task needs

- `references/model-routing.md` — before selecting any model or effort.
- `references/delegation-contract.md` — before delegating implementation, creating
  fan-out reviewers, or using parallel worktrees.
- `references/review-schemas.md` — when asking reviewers for structured findings.
- `references/dispatch.md` — how to actually launch a worker from this harness.

## Provider boundary

Check this before selecting anything. The boundary is the repository's git remote,
never its directory — a worktree carries its repository's remote, so a client
worktree parked outside the client tree is still client code.

- Remotes under `github.com/ElbertePlinio` or `github.com/pickforge` may use the
  whole table.
- Every other remote, a repository with no remote, and a directory that is not a
  repository are restricted to the Anthropic and OpenAI lanes. Grok and Kimi are
  not selectable there. `kimi-k3` dispatches as `kimi-k3:cloud` and leaves the
  machine, so it is restricted like any other external provider.
- Unsure means restricted. Do not infer ownership from a directory name.

`scripts/lane-policy.mjs` enforces this in `fanout-review.mjs` and
`ollama-delegate.mjs`, so a restricted dispatch fails rather than leaking. Treat
that as a backstop, not permission to skip the check when planning.

## Per-call selection

1. Classify the call: risk and irreversibility, modality and tool compatibility,
   uncertainty and context size, validation strength.
2. Exclude incompatible or unavailable options, then take the lightest sufficient
   candidate from the table and start at its documented effort.
3. Never assign permanent roles, named lanes, fixed provider sequences, or
   task-class defaults. Scores and past successful routes are evidence, not
   assignments — select builders, reviewers, researchers, and adjudicators
   independently from the same table.
4. Grok 4.5 always uses high. Raise any other effort only when a lower-effort result
   fails targeted validation, material evidence stays unresolved or contradictory, or
   an irreversible decision lacks adequate proof. Record the trigger and its
   resolution; elevated effort ends when its question resolves.
5. The session cannot silently upgrade its own turn — dispatch an explicit second
   opinion or escalation call instead.

## Mode

Use the lightest that fits: the session completes and validates the task; one
implementation lane then `local-review`; risk-targeted orchestration then
`local-review`; isolated worktrees only for genuinely independent scopes.

## Bounds

- `local-review` owns risk classes, profile selection, and review counts. Pick each
  reviewer for its concrete failure mode, with distinct prompts against the same
  frozen HEAD. Do not repeat reviewers against a generic prompt. It also owns the
  overengineering and simplification verdicts.
- Add an adjudicator only for unresolved material evidence or reviewer disagreement;
  it answers the named question rather than restarting review.
- One writer per file or worktree. Keep scouts, reviewers, and dissenters read-only.
  Review parallel writers' patches before integration.
- Prefer a two-level tree: workers propose further splits to the orchestrator rather
  than delegating recursively.
- Reuse a healthy builder for follow-up fixes. Abandon stuck, failed, or interrupted
  runs instead of rescuing them: capture the short cause, cancel owned work, and
  redispatch fresh. Never spawn a new agent per verification step, and never repeat a
  full review panel after fixes.
- Keep one accountable owner for taste-heavy work; provider identity does not define
  ownership.
- Synthesize every worker result yourself. Reject weak or contradictory output,
  validate with the narrowest useful proof, and report changes, evidence,
  substitutions, and residual risk.

## Hard constraints

- Never route secrets, credentials, or private production data into a model prompt.
- Report every substitution. If a selected model is unavailable or incompatible, take
  the closest compatible candidate from the table; stop only when the user required
  that exact model or nothing compatible fits.
- Running non-interactively as a leaf under another orchestrator: do the assigned
  task directly and do not re-delegate.
