---
name: ship-pr
description: Ship the current branch as a GitHub PR through focused validation, risk-adaptive local review, CI, issue tracking, and merge. Use when the user asks to open a PR, ship it, run the usual PR flow, or get a branch reviewed and merged.
---

# Ship a PR

Invoking this skill authorizes pushing the current branch, opening the PR, and merging it once the gates below are clean. Global git rules still apply: protect user work, use Conventional Commits, and never add AI attribution or bot trailers.

## Before Opening

1. Batch everything intended to ship. Do not open a half-finished PR.
2. Run the build, focused tests, and the narrowest real behavioral verification for the change.
3. Run `$local-review` against the branch diff. Select the risk class and independent failure-mode profiles from the actual change.
4. Batch valid review fixes, re-run focused validation, and review each changed HEAD until clean or blocked. GitHub-hosted Codex review is optional escalation only.
5. Promote durable findings: if review, validation, or this session surfaced a generalizable, recurring correction (not a one-off bug), add it to the repo's `AGENTS.md` (or the workspace root `AGENTS.md` if cross-repo) in the same PR. Review findings must compound into shared memory.
6. Check release tracking:
   - If `docs/releases/UNRELEASED.md` exists, update it for release-relevant changes, validation, unverified areas, and known blockers.
   - If this is a releasable Pickforge product app and the file is missing, create it.
   - If the change is not release-note-worthy, leave it unchanged and say so in the PR body.
7. Check `git status --short` before staging, committing, pushing, or merging.

## Issue and PR Contract

- Keep the PR body compact: what changed, what was tested, what was not tested, known risks, and the local-review risk class.
- In `~/Projects/Pickforge`, link the tracking issue. Use `Closes #n` only when the PR fully resolves it; otherwise use `Refs #n`.
- If the parent issue defines multiple PR slices, state which slice this PR completes, what remains, and any dependency.
- Update the parent issue when the PR opens, becomes review-clean, gains a follow-up, and merges.
- If substantial Pickforge work has no issue, create one before opening the PR.

## Open and Check

1. Push the branch and open the PR against `main`.
2. Confirm the PR diff and HEAD match the locally reviewed commit.
3. Watch required CI:

```bash
gh pr checks <number> --watch
```

4. Triage every GitHub discussion or CI finding. Fix valid findings and reply briefly with evidence when dismissing a false positive.
5. If a fix changes HEAD, re-run focused validation and `$local-review` before merging. Do not request repeated review of an unchanged diff.
6. If review, CI, discussion, or the agent reveals valid work intentionally deferred, create or update a follow-up issue. Link the source PR and include risk, expected behavior, evidence, and next action.

## Merge Gate

Merge only when:

- focused validation passes
- the current HEAD completed the review required by its risk class
- no valid P0–P2 finding remains
- P3 findings are fixed or explicitly dismissed/deferred with rationale
- required CI is green
- no review or CI run is in flight
- release tracking and the parent issue match the final diff

Merge with squash and delete the branch:

```bash
gh pr merge <number> --squash --delete-branch
```

Clean up any worktree used for the branch:

```bash
git worktree remove <path>
git worktree prune
```

## Optional External Review

Use GitHub Codex review on demand only when it adds a genuinely independent perspective or adjudicates disagreement. Its absence is not a blocker when the local review gate is satisfied. If requested, triage its findings under the same evidence standard as local findings.
