---
name: model-orchestration
description: Dispatch work to other models — native subagents, provider CLIs, cross-provider lanes — with per-call model and effort selection from the current table. Use when delegating implementation, review, research, or any multi-model work, or when quota headroom must be checked before a dispatch wave.
---

# Model orchestration

The current session is the orchestrator: it owns scope, contracts, routing, synthesis,
validation, and final acceptance. Workers are leaves unless it explicitly authorizes
fan-out. Selection policy — axis ranking, quota asymmetry, effort ceilings, model bans —
lives in the shared global rules; this skill owns the mechanics.

## Read what the task needs

- `references/dispatch.md` — how to launch a worker: native subagents, provider CLIs,
  pickforge-lanes MCP lifecycle.
- `references/model-routing.md` — pool table, harness-scoped selectors, compatibility
  notes, for harnesses without an inline table.
- `references/delegation-contract.md` — before delegating implementation, creating
  fan-out reviewers, or using parallel worktrees.
- `references/review-schemas.md` — when asking reviewers for structured findings.

## Provider boundary

The boundary is the repository's git remote, never its directory — a worktree carries
its repository's remote. Full table under `github.com/ElbertePlinio` or
`github.com/pickforge` remotes; every other remote, a repository with no remote, a
non-repository directory, or any doubt restricts to the Anthropic and OpenAI lanes.
`scripts/lane-policy.mjs` enforces this in the dispatch wrappers, so a restricted
dispatch fails rather than leaking. Treat that as a backstop, not permission to skip
the check when planning.

## Provider re-authentication

Use each provider's normal interactive login: Google `elberte.dev@gmail.com` for Claude, ChatGPT, and Ollama; Microsoft `eoberte@outlook.com` for Grok. Never handle passwords, recovery codes, 2FA codes, cookies, or tokens. If login cannot complete without the user, stop and prompt them.

## Quota headroom

Before a multi-task dispatch wave, check pool headroom once (not before every call):

```sh
pickgauge usage --json || ~/.local/bin/pickgauge usage --json
```

Read `services`: `remainingPercent` and `windows.fiveHour`/`windows.week` are the
gauges; `source`, `confidence`, and `staleSeconds` say how much to trust a reading.
Route by available headroom, not sticker price — a cheap lane near its cap loses to a
pricier lane with room. `remainingPercent: null` means no gauge: treat the pool as
unknown, never as empty. If the binary is missing on this machine, note it and
continue rather than blocking.

## Bounds

- `local-review` owns risk classes, profile selection, and review counts. Pick each
  reviewer for its concrete failure mode, with distinct prompts against the same
  frozen HEAD. It also owns the overengineering and simplification verdicts.
- Use the lightest mode that fits: the session completes and validates the task; one
  implementation lane then `local-review`; risk-targeted orchestration; isolated
  worktrees only for genuinely independent scopes.
- Add an adjudicator only for unresolved material evidence or reviewer disagreement;
  it answers the named question rather than restarting review.
- One writer per file or worktree. Keep scouts, reviewers, and dissenters read-only.
  Prefer a two-level tree: workers propose further splits instead of delegating
  recursively.
- Reuse a healthy builder for follow-up fixes. Abandon stuck, failed, or interrupted
  runs: capture the short cause, cancel owned work, redispatch fresh. Never spawn a
  new agent per verification step, and never repeat a full review panel after fixes.
- The session cannot silently upgrade its own turn — dispatch an explicit second
  opinion or escalation call instead.
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
