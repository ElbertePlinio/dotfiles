# Model Routing

This is comparative pool metadata, not a role-assignment table. Scores are relative user defaults; cost reflects effective pool cost (1 = cheapest), not vendor list price. Select every call independently.

| model | selector | start | cost | intelligence | taste | calibration | vision | compatibility notes |
|---|---|---:|---:|---:|---:|---:|---|---|
| GPT-5.6 Sol | `openai-codex/gpt-5.6-sol` | medium | 4 | 9 | 6 | 8 | yes | candidate when context, tools, quota, and validation fit |
| Fable 5 | `anthropic/claude-fable-5` | high | 6 | 9 | 9 | 9 | yes | candidate when context, tools, quota, and validation fit |
| Opus 5 | `anthropic/claude-opus-5` | high | 5 | 9 | 8 | 9 | yes | candidate when context, tools, quota, and validation fit |
| Grok 4.5 | `xai/grok-4.5` (Pi, pickforge-lanes MCP) / `xai-oauth/grok-4.5` (OMP) | high | 3 | 7 | 5 | 3 | yes | provider prefix is harness-scoped; always high |
| GLM-5.2 | `ollama/glm-5.2:cloud` | provider default | 2 | 7 | 6 | 4 | no | text-only; never receive visual inputs |
| Kimi K3 | none yet — verify before first use | provider default | 3 | 7 | 8 | 5 | yes | **not selectable**; open weights due 2026-07-27 |

GPT-5.6 Luna and Anthropic Haiku are prohibited. Do not use Codex `ultra`; its internal delegation duplicates this workflow.

Kimi K3 is listed for planning only and must not be dispatched until its weights ship and a selector is confirmed working in the target harness. Treat a Kimi K3 selection before then as an unavailable model and substitute per the fallback policy. Its taste score is weighted toward greenfield visual work, where it ranks first on blind frontend comparisons; it drops materially on structural code quality and on changes inside a large existing codebase, so score the task, not the headline.

## The Three Score Axes

The axes are independent and a model can be strong on one and weak on another. Read the axis the task actually depends on, not the highest number.

- **Intelligence** — can it solve the problem and complete the task.
- **Taste** — is the artifact one a senior engineer keeps: restraint, idiom, respect for existing conventions and design systems, sound visual judgment.
- **Calibration** — does it know which of its own claims are true. This governs review verdicts, severity ranking, and any judgment where being confidently wrong is expensive.

A high intelligence score with a low taste score describes a model that reaches the goal and leaves an artifact you would rewrite. A high intelligence score with a low calibration score describes a model that surfaces real signal and then misjudges which parts matter.

## Selection Policy

Select every call independently from:

1. **Risk and irreversibility:** user impact, rollback cost, architecture/security/data consequences, and blast radius.
2. **Modality and tool compatibility:** vision, terminal, coding, browsing, long-context, or text-only constraints.
3. **Uncertainty and context complexity:** unknowns, ambiguity, competing hypotheses, and context volume.
4. **Validation strength:** narrow tests, reproducible defects, independent evidence, or lack of proof.
5. **Live quota headroom:** before a multi-agent wave, check `pickgauge-usage` once; weigh credits, rate limits, authentication, tool availability, and scarce capacity. The `pickgauge` binary is not installed on every machine — if it is missing, note it and continue rather than blocking.
6. **Observed output quality:** whether the chosen result withstands the validation and review it was asked to support.

Start at the table's documented effort. Grok 4.5 always uses high. For other models, raise effort only for concrete failed validation, unresolved evidence, irreversible risk, or an explicit user request; return to the table prior after that question is resolved.

Small, precisely specified mechanical tasks run executor lanes at low effort by default — measured on Claude executors, higher effort buys edge-case hunting and validation depth, not better core code. A low-effort dispatch requires the contract to enumerate edge cases and input-validation expectations; if they cannot be enumerated, the spec is not ready or effort goes up.

Choose the lightest sufficient compatible candidate. Rank the axes by what the task depends on rather than applying one fixed order:

- **Solving a defined problem** — intelligence > taste > cost.
- **Producing an artifact that must survive review** — taste > intelligence > cost.
- **Issuing a verdict, severity, or judgment call** — calibration > intelligence > cost.

Never create permanent model-to-role bindings, named model lanes, fixed provider sequences, or automatic task-class defaults. A prior successful choice is evidence, not entitlement.

## Executors With a Taste Deficit

When a selected executor's taste score is materially below its intelligence score, it receives a written contract, never a bare goal.

A contract names the files in scope, the interfaces, the acceptance criteria, and what must not change. If the contract cannot be written, the task is not ready to dispatch — resolve the design first, and prefer the highest-taste compatible candidate to resolve it.

Such an executor's output is reviewed before it is accepted. Never self-review, and never review a lane's work with the same model that produced it.

## Finding Versus Adjudicating

Review is two separate jobs and the pool splits on calibration.

- **Finding** — surfacing candidate issues, optimized for recall. Any compatible candidate may find, including low-calibration ones. Cheap high-recall passes are a good use of a low-cost lane.
- **Adjudicating** — deciding which candidates are real, ranking severity, and issuing the verdict. This requires calibration 8 or above.

A model below that threshold may contribute findings but never issues the verdict on its own findings or anyone else's. Route its output to an adjudicator. Cheap-and-confident is the failure this rule exists to prevent: an uncalibrated lane reports real patterns and false alarms with identical confidence, and the cost of believing it exceeds what the cheap pass saved.

Calibration 8 is the floor for every adjudicator, never traded away for another axis. Some profiles add a second requirement on top of it: over-engineering, DRY, KISS, simplification, and design-system fidelity additionally require taste 8 or above, because recognizing that an abstraction was not earned is a taste judgment; visual work additionally requires vision.

## Bounded Review and Escalation

- **Trivial:** main-session review unless uncertainty remains.
- **Standard:** one independent reviewer with the most relevant failure-mode profile.
- **Serious backend:** three independent reviewers with distinct relevant profiles against the same frozen HEAD.
- **Serious user-facing or full-stack:** four independent reviewers covering correctness, operational/security risk, product/UI concerns, and simplification as applicable.
- **Critical:** use the relevant serious set, then add at most one targeted adjudicator only for unresolved material evidence or reviewer disagreement.

`$local-review` owns profile selection and counts. Select every reviewer independently from this table for its assigned failure mode; provider diversity is useful only when it adds genuinely different evidence. Use distinct prompts, deduplicate centrally, and run one targeted fix-verification reviewer instead of repeating a panel.

## Compatibility and Fallback

- GLM-5.2 is text-only. When visual context matters, select a vision-capable candidate or provide a faithful text summary before a GLM call.
- Preserve each candidate's tool, modality, privacy, and context constraints. Never send secrets, credentials, or private production data to cloud prompts.
- If a selected model is unavailable or incompatible, reselect the closest compatible candidate from this table and report the substitution. Stop only when the user required that exact model or no candidate fits.
- Parallelize only genuinely independent scopes with enough headroom to justify coordination. Keep one writer per file/worktree; use isolated worktrees and patch review for parallel writers.

## Anti-overengineering Gate

Use `$local-review`'s overengineering and simplification profile; do not redefine its verdicts here.
