---
name: audit-report
description: Run a scoped, evidence-cited audit through parallel read-only research lenses, then optionally create a board or plan-issue follow-up.
---

# Audit Report

Use for investigations repeated across sessions where the deliverable is a decision-ready audit, not an implementation.

1. Define the audit question, in-scope paths/systems, exclusions, evidence standard, and decision the report must support. Inventory the scope before researching; do not broaden it silently.
2. Read `model-orchestration` and its current model table. Split only genuinely independent, read-only lenses (for example: architecture, behavior, history, security, DX). For every lens, explicitly select the compatible model and effort from the table, recording why it fits the modality, risk, uncertainty, and available evidence.
3. Dispatch the lenses in parallel with self-contained prompts: scope, exclusions, questions, required evidence, and a prohibition on edits, formatters, tests, git operations, and speculative findings.
4. Require each lens to return findings with severity, exact file/symbol or source citation, observed evidence, impact, confidence, and a concrete recommendation. Mark inferences explicitly.
5. Synthesize once: normalize terms, deduplicate shared root causes, reconcile conflicts against primary evidence, and rank only actionable findings. Do not promote a claim without a citation.
6. Deliver a compact report: scope and method; selected lenses/models/efforts; evidence-cited findings; grouped root causes; recommendations; unresolved questions; and explicit non-findings where useful.
7. Offer, but never auto-create, a standalone HTML board. If the user accepts, save it under `~/Projects/Boards/<project-slug>/` with the report's evidence and findings; otherwise keep the audit in its requested format.
8. Offer, but never auto-create, `plan-issue` follow-up for accepted findings. If accepted, create focused issues with evidence, expected behavior, risk, and next action; do not turn every observation into an issue.
9. Preserve the audit boundary: implementation, commits, and PRs require an explicit separate request.
