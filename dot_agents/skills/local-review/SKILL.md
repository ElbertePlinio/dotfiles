---
name: local-review
description: Run quota-aware, risk-adaptive local review panels after behavioral validation and before opening or merging a PR.
---

# Local Review

Review locally after focused tests and behavioral verification pass. Reviewers are read-only. The active orchestrator owns risk classification, profile selection, deduplication, triage, fixes, validation, and acceptance.

## Risk Classes

- **Trivial**: obvious, narrow, low-impact change. Main-agent review is enough unless uncertainty remains.
- **Standard**: normal behavior or multi-file change. Run one independent reviewer with the single most relevant profile. Select its model and effort from the current model table for that concrete failure mode.
- **Serious backend**: auth, permissions, persistence, migrations, security, release infrastructure, broad architecture, destructive operations, or large backend blast radius. Run three reviewers in parallel against the same frozen HEAD with distinct profiles and complementary failure modes. Select every model and effort independently from the current model table.
- **Serious user-facing or full-stack**: use three complementary reviewers and add a fourth vision- and taste-capable profile only when UI/UX, accessibility, product behavior, or visual simplification is a concrete risk. Run the selected reviewers in parallel against the same frozen HEAD with distinct prompts. Select every model and effort independently from the current model table.
- **Critical**: use the relevant serious panel, then add at most one targeted adjudicator only when material evidence remains unresolved or reviewers materially disagree. The adjudicator resolves the named question; it does not restart the review.

Before selecting reviewers, read the `model-orchestration` skill's `references/model-routing.md` and its compatibility, effort, and fallback policy completely. Check live quota once before the wave when the table requires it. Select each reviewer for its specific profile, modality, tools, uncertainty, validation surface, and required independence; never treat a model as permanently assigned to a risk class or lane. Report substitutions required by availability or compatibility. Stop only when the user explicitly requires an unavailable model or no compatible candidate fits.

## Orchestrator Read Tiers

Read tiers govern what the orchestrator itself reads. They are orthogonal to risk classes: the risk class selects the reviewer panel; the read tier selects the orchestrator's own reading. A read tier never reduces a risk class or its reviewer count.

- **No-read**: the orchestrator does not read the implementation diff. It reviews the lane's decision list, the test diff (through the Test integrity profile), the acceptance tests, and the gate results. Allowed only when ALL hold:
  - the repo meets the enforced gate baseline (`references/gate-baseline.md`) with blocking CI
  - the change touches only application code and tests — no auth, permissions, persistence, migrations, release or CI infrastructure, public API contracts, and no dependency changes
  - the intended behavior change is fully expressed in acceptance tests the orchestrator has reviewed
  - the diff is at most ~400 changed lines, excluding generated files and lockfiles
- **Spot-check**: gated repo, but a no-read condition fails on size or judgment (not on protected paths or dependencies). The orchestrator reads only hotspots: files or hunks flagged by reviewers, gates, or the decision list.
- **Full read**: everything else — protected paths, ungated repo, dependency changes, or explicit user request.

Escalation is one-way: any valid P0–P2 finding, gate failure, weakened test, or unexplained decision-list entry promotes the change to full read for the rest of the round. When tier conditions are uncertain, use the higher tier.

## Profiles

Choose only profiles relevant to the diff. Give every reviewer one primary profile; do not send identical generic prompts.

### Correctness and regressions

Check contracts, state transitions, edge cases, concurrency, error paths, compatibility, call sites, and behavior outside the happy path.

### Tests and operational risk

Check whether tests defend observable behavior and plausible failures. Inspect determinism, migrations, configuration, release impact, rollback/recovery, and existing operational conventions.

### Test integrity

Enable whenever tests changed or should have changed; mandatory in the no-read and spot-check tiers, where the orchestrator does not read the implementation. Check that the test diff does not weaken assertions, delete or skip tests, broaden tolerances, or mock away the behavior under test; that new acceptance tests pin the requested behavior and would fail without the change; and that coverage of the touched code did not drop.

### Security and trust boundaries

Check authentication, authorization, input boundaries, injection, secrets, permissions, data exposure, unsafe defaults, and dependency or process boundaries.

### New dependencies

Enable only when a manifest or lockfile adds or changes dependencies. Verify each new dependency is justified against existing in-repo alternatives, maintained, minimally scoped, and free of known advisories; flag transitive additions with a large blast radius. Dependency changes are never eligible for the no-read tier.

### UI and accessibility

When UI changed, check interaction states, keyboard/focus behavior, semantics, responsiveness, loading/error/empty states, text scaling, contrast, motion, and screenshot-visible regressions.

### Issue conformance

Enable only when the change implements a named issue, spec, or plan with observable acceptance criteria. Verify the diff against those criteria: missing behavior, extra scope beyond the issue, and misunderstood requirements. Report these findings separately under `Issue conformance` with the criterion each finding traces to; do not blend them into correctness or security. A conformance gap is not automatically a blocker — the orchestrator decides whether it is a P0–P2 (broken core acceptance) or a documented deferral filed as a follow-up issue. For trivial and standard changes, the existing reviewer performs this check when an issue is named; never add a reviewer solely for conformance.

### Overengineering and simplification

Every review includes a KISS gate in addition to its primary profile. Identify abstractions, layers, files, configuration, options, caches, factories, managers, adapters, or tests that are not justified by current requirements. Return one verdict:

- `keep`: complexity is justified now.
- `simplify_now`: name exact code to remove or collapse, why it is unnecessary, the simpler design, and the validation that preserves behavior.
- `defer`: no current defect; record the concrete future signal that would justify revisiting it. Do not create cleanup work from taste alone.

For trivial and standard changes, the existing reviewer performs this gate; never add a reviewer solely for KISS. Add one dedicated simplification reviewer only when the diff introduces a shared abstraction, utility, file, or layer for limited use; performs a broad refactor; or is materially larger than the behavior requires. Select that reviewer from the current model table based on the concrete simplification risk, modality, tool compatibility, uncertainty, validation strength, and live quota headroom. If an already selected risk-class reviewer fits, assign that lane the simplification profile instead of adding another. Add a separate lane only for a distinct simplification risk that the existing panel cannot cover.

### Fix verification

Use only after a prior round produced valid findings. Verify each accepted finding against the new HEAD, inspect regressions introduced by the fix, and avoid reopening dismissed findings without new evidence.

## Review Prompt Contract

Each reviewer receives:

- repository and base branch
- exact review range (`merge-base...HEAD` or equivalent)
- current HEAD identifier
- relevant repo instructions
- one primary profile
- tests and behavioral verification already run
- known risks or intentional constraints
- the named issue/spec and its acceptance criteria, when Issue conformance is enabled
- instruction to stay read-only and inspect the actual diff plus affected call paths
- mandatory KISS verdict: `keep`, `simplify_now`, or `defer`, with reduction evidence when simplifying

Select every reviewer independently from the current model table for its concrete profile and failure mode. Use distinct profile-specific prompts and the same frozen HEAD. Run independent reviewers in parallel, then deduplicate and adjudicate centrally. Apply the same dynamic selection to any dedicated simplification lane. After fixes, use one targeted fix-verification reviewer instead of repeating the panel.

## Finding Contract

A finding is actionable only when it includes:

- severity: `P0`, `P1`, `P2`, or `P3`
- file and line or exact symbol when applicable
- observable problem
- evidence tying the problem to the reviewed diff
- smallest correct fix or verification path

Reject vague concerns, style preferences, speculative future requirements, and findings contradicted by tests or repository contracts.

Reviewers return findings first, then their verdict. A clean verdict means no actionable finding, not merely no major finding.

## Rounds

1. Run the risk-class review against the current HEAD.
2. The orchestrator deduplicates and adjudicates every finding.
3. Promote durable lessons: when an adjudicated finding reflects a generalizable, recurring pattern (not a one-off bug), add the compact rule to the repo's `AGENTS.md` — or the workspace/curated memory for cross-repo patterns — in the same change set. One line per lesson; skip anything already covered.
4. Batch all valid fixes. Do not change code for dismissed findings.
5. Re-run focused behavioral validation.
6. If HEAD changed and accepted findings need independent confirmation, run one targeted **Fix verification** reviewer. Re-run the KISS gate only when fixes add abstractions or files or materially increase complexity. Never restart the whole profile set.
7. Stop on the first clean current HEAD.

Three reviewed HEADs is the hard ceiling, not a target. The third is reserved for a new or unresolved P0–P2 finding after targeted verification. If it still has a valid P0–P2, do not ship; report the blocker. Do not repeatedly sample an unchanged diff to manufacture confidence.

## Shipping Gate

Before opening or merging a PR:

- focused tests and behavioral verification pass
- the current HEAD completed the required local review for its risk class
- no valid P0–P2 remains
- P3 findings are fixed or explicitly dismissed/deferred with rationale
- serious/critical review used only the complementary coverage required by its concrete risks, with any unavailable required lane reported
- required CI remains mandatory after the PR opens

GitHub-hosted Codex review is optional escalation, not a default merge prerequisite. Use it on demand only when it adds a genuinely independent check or resolves disagreement.
