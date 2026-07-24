---
name: plan-issue
description: Use GitHub Issues as the planning and progress source of truth for Pickforge work. Create/read/update issues, maintain phone-friendly checklists, link PRs, and file follow-up issues for deferred findings.
---

# Plan Issue

Use this skill for substantial work in any repo under `~/Projects/Pickforge`, or whenever the user asks to plan/track work through GitHub Issues.

Goal: GitHub Issues are the canonical plan/progress tracker. Local todos are only a mirror for the current agent session.

## When to use

Use for non-trivial work: multi-step implementation, refactors, user-visible changes, bugs, release work, risky changes, work likely to become a PR, or anything the user may want to track from phone.

Skip for tiny one-shot edits or quick investigations, but say no issue was needed if reporting back.

## Setup checks

From the repo root:

```bash
git remote get-url origin
gh auth status
gh issue list --state open --limit 20
```

If `gh` is unavailable or unauthenticated, do not pretend progress was updated. Report the blocker and continue with local planning only if useful.

## Workflow

1. **Find issue context**
   - Check the user request for `#123` or a GitHub URL.
   - Check branch name and PR body for an issue number.
   - Search related issues:
     ```bash
     gh issue list --state open --search "<keywords>" --limit 10
     ```

2. **Select or create the tracking issue**
   - If the user named an issue, use it.
   - If an existing issue clearly matches, use it.
   - If substantial work has no issue, create one:
     ```bash
     gh issue create --title "<short outcome>" --body-file /tmp/issue-body.md
     ```
   - Ask only if ambiguity would change scope, ownership, title, or acceptance criteria.

3. **Read the issue before planning**
   ```bash
   gh issue view <number> --comments
   ```
   Treat the issue as source of truth for scope, acceptance criteria, prior decisions, and blockers.

4. **Post or update the plan**
   Prefer one compact progress comment if editing the issue body is not obviously safe.

   Template:

   ```md
   ## Agent plan

   Goal: <one sentence>

   Checklist:
   - [ ] <step 1>
   - [ ] <step 2>
   - [ ] <validation>
   - [ ] PR/review

   Validation:
   - <commands planned>

   Current status: Planned / In progress / Blocked / In review / Done
   Next action: <short>
   ```

5. **Update at meaningful checkpoints only**
   Update the issue when:
   - plan is posted;
   - implementation starts;
   - major checklist item completes;
   - blocked;
   - PR opens;
   - review/follow-up is filed;
   - merged/done.

   Avoid comment spam. Batch small progress into one update.

6. **Link PRs**
   Use:
   - `Closes #n` / `Fixes #n` only when the PR fully resolves the issue.
   - `Refs #n` when the PR is partial or the issue tracks broader work.

7. **Follow-up issues for deferred problems**
   If Codex review, CI, PR discussion, QA, or the agent itself finds a real issue that will not be fixed in the current PR:
   - create or update a GitHub issue before merge;
   - link the source PR and review/comment if available;
   - include expected vs actual behavior, severity/risk, why deferred, reproduction/validation notes, and suggested next action;
   - link the follow-up issue back in the PR.

   Do not merge if the unresolved finding is severe: security, data loss, crash, corrupt state, or a broken core user path.


## Flagged features

Apply the feature-flag decision rule from the workspace `AGENTS.md`
(`~/Projects/Pickforge/AGENTS.md`, "Feature flags") when planning. If the
feature goes behind a flag:

- record the flag name in the issue body;
- add the `flagged` label;
- include the lifecycle in the checklist:

```md
- [ ] merged behind flag `<name>`
- [ ] tested on main (flag on)
- [ ] enabled in vX.Y.Z
- [ ] flag removed
```

Remove the `flagged` label when the flag is removed.

## Splitting one issue into multiple PRs

One GitHub Issue can be the parent plan for multiple PRs. The agent should choose this when it will make review faster, enable safe parallel work, or reduce risk.

### Split decision

Prefer multiple PRs when:

- work touches independent areas;
- there are natural phases such as scaffold → behavior → polish;
- the task mixes refactor/migration with user-visible behavior;
- validation can be done independently per slice;
- a single PR would be large, noisy, or slow for Codex to review;
- independent slices can run safely in separate branches/worktrees.

Keep one PR when:

- the change is tiny;
- slices would be tightly coupled;
- intermediate states cannot be validated or merged safely;
- splitting adds more overhead than review value.

### Parent issue PR plan template

Add this to the issue plan when splitting:

```md
## PR plan

- [ ] PR 1 — <small outcome>
  - Depends on: none
  - Touches: <files/areas>
  - Validation: <commands/checks>
  - Link: pending
- [ ] PR 2 — <small outcome>
  - Depends on: PR 1 / none
  - Touches: <files/areas>
  - Validation: <commands/checks>
  - Link: pending
- [ ] Final integration/release note pass
```

### Traceability

When an issue has explicit acceptance criteria and is split into multiple PRs, add one traceability block to the parent issue so every criterion maps to a slice and a validation:

```md
## Traceability

| Acceptance criterion | PR/slice | Validation | Status |
|---|---|---|---|
| <criterion 1> | PR 1 | <command/check> | pending |
| <criterion 2> | PR 2 | <command/check> | pending |
```

- Every acceptance criterion must map to at least one PR/slice and one concrete validation; a criterion with no slice is unplanned scope, a slice with no criterion is scope creep — name it and resolve it before implementation.
- Each slice must be independently verifiable; if it is not, either merge it into the slice it depends on or name the real blocker in `Depends on`.
- Only the final closing PR may mark the parent `Closes #n`; it must confirm every traceability row is done.
- Keep the block updated at the same checkpoints as the PR plan. Skip the block entirely for single-PR issues — the checklist already covers it.

### Rules

- Each PR must have one clear outcome and its own validation plan.
- Prefer independent PRs over stacked PRs. If stacked PRs are unavoidable, record the order/dependency in the parent issue.
- Use `Refs #n` for partial PRs. Use `Closes #n` only on the final PR that fully resolves the parent issue.
- Update the parent issue when each PR opens, gets review-clean, merges, or spawns a follow-up.
- If a PR slice grows too large during implementation, pause and split it before requesting review.
- Parallelize only independent slices. Use separate branches/worktrees and avoid concurrent edits to the same files unless the orchestrator explicitly serializes the merge order.

## Phone-friendly style

Keep comments short and scannable:

```md
Progress update:
- [x] Reproduced
- [x] Added regression test
- [ ] Fix implementation
- [ ] Run validation

PR: <url or pending>
Blocked: none
Next: fix implementation
```

## Commands reference

```bash
gh issue view <n> --comments
gh issue comment <n> --body-file /tmp/progress.md
gh issue edit <n> --body-file /tmp/body.md
gh issue create --title "<title>" --body-file /tmp/issue.md
gh pr view --json number,url,body,headRefName
gh pr edit <n> --body-file /tmp/pr-body.md
```
