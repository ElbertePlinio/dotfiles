---
name: review
description: Use when asked to review a diff, branch, or PR before it ships.
---

Read the diff and surrounding code. Check correctness, security, regressions, needless abstractions, duplication, and unjustified changes or tests. Use relevant existing validation evidence tied to the reviewed revision. A reviewer running in a read-only lane or subagent stays read-only and asks for missing checks to run in a separate writable worker.

When asked to review a PR or diff, review it yourself. Do not delegate it automatically or add a review of the review. Code being shipped from your own task gets independent review in a separate lane or subagent from the author. When the user requests a specific reviewer model, use it. Otherwise use lanes_models or pickforge-lanes models: Astra reviews every change it did not write, and Fable adds a separate review for visual, architecture or product-intent work and for sensitive risks, at medium effort for routine reviews and high only for difficult failure paths, interacting invariants or security boundaries. In Claude Code, route Astra through Lanes and selected Fable reviewers through native subagents.

Give each reviewer requirements, the diff, and validation evidence before sharing the author rationale or other reviewers' findings. The lead verifies disagreements through code or focused tests, not votes; two reviews are not a mandatory two-approval gate.

Record the reviewed revision, including any uncommitted diff, and recheck only affected areas after fixes against the resulting revision. Report supported findings by severity with file and line, impact, and a concrete fix. Include useful simplifications as findings, not a required empty section. State missing evidence or review limits. If there are no findings, say so briefly. Do not restate the diff or add praise.
