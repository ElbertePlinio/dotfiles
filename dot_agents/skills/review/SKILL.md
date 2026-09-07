---
name: review
description: Use when asked to review a diff, branch, or PR before it ships.
---

Read the diff and surrounding code. Check correctness, security, regressions, needless abstractions, duplication, and unjustified changes or tests. Use relevant existing validation evidence tied to the reviewed revision. Have a separate writable worker run missing checks; reviewers stay read-only and do not run tests.

Every final reviewer runs in a separate lane or subagent from the author. Use lanes_models or pickforge-lanes models for reviewer selection: default to a counter-opinion from the other model, allow task-fit overrides, and use both independently for sensitive work. Base the choice on the code author, not the lead. Use one reviewer for ordinary work, medium effort for routine reviews and high for substantive ones. In Claude Code, route Astra through Lanes and selected Fable reviewers through native subagents.

Give each reviewer requirements, the diff, and validation evidence before sharing the author rationale or other reviewers' findings. The lead verifies disagreements through code or focused tests, not votes; dual review is not a mandatory two-approval gate.

Record the reviewed revision, including any uncommitted diff, and recheck only affected areas after fixes against the resulting revision. Report supported findings by severity with file and line, impact, and a concrete fix. Include useful simplifications as findings, not a required empty section. State missing evidence or review limits. If there are no findings, say so briefly. Do not restate the diff or add praise.
