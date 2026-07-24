# Model Routing

This is comparative pool metadata, not a role-assignment table. Scores are relative user defaults; cost reflects effective pool cost (1 = cheapest), not vendor list price. Select every call independently.

| model | selector | start | cost | intelligence | taste | vision | compatibility notes |
|---|---|---:|---:|---:|---:|---|---|
| GPT-5.6 Sol | `openai-codex/gpt-5.6-sol` | medium | 4 | 9 | 6 | yes | candidate when context, tools, quota, and validation fit |
| Fable 5 | `anthropic/claude-fable-5` | high | 5 | 9 | 9 | yes | candidate when context, tools, quota, and validation fit |
| Opus 5 | `anthropic/claude-opus-5` | high | 5 | 8 | 8 | yes | candidate when context, tools, quota, and validation fit |
| Sonnet 5 | `anthropic/claude-sonnet-5` | medium | 5 | 5 | 7 | yes | candidate when context, tools, quota, and validation fit |
| Grok 4.5 | `xai/grok-4.5` (Pi, pickforge-lanes MCP) / `xai-oauth/grok-4.5` (OMP) | high | 3 | 7 | 6 | yes | provider prefix is harness-scoped; always high |
| GLM-5.2 | `ollama/glm-5.2:cloud` | provider default | 2 | 6 | 7 | no | text-only; never receive visual inputs |

GPT-5.6 Luna and Anthropic Haiku are prohibited. Do not use Codex `ultra`; its internal delegation duplicates this workflow.

## Selection Policy

Select every call independently from:

1. **Risk and irreversibility:** user impact, rollback cost, architecture/security/data consequences, and blast radius.
2. **Modality and tool compatibility:** vision, terminal, coding, browsing, long-context, or text-only constraints.
3. **Uncertainty and context complexity:** unknowns, ambiguity, competing hypotheses, and context volume.
4. **Validation strength:** narrow tests, reproducible defects, independent evidence, or lack of proof.
5. **Live quota headroom:** before a multi-agent wave, check `pickgauge-usage` once; weigh credits, rate limits, authentication, tool availability, and scarce capacity. The `pickgauge` binary is not installed on every machine — if it is missing, note it and continue rather than blocking.
6. **Observed output quality:** whether the chosen result withstands the validation and review it was asked to support.

Start at the table's documented effort. Grok 4.5 always uses high. For other models, raise effort only for concrete failed validation, unresolved evidence, irreversible risk, or an explicit user request; return to the table prior after that question is resolved.

Choose the lightest sufficient compatible candidate. When compatible options remain, prefer intelligence > taste > cost while respecting modality, risk, validation, and live headroom. Never create permanent model-to-role bindings, named model lanes, fixed provider sequences, or automatic task-class defaults. A prior successful choice is evidence, not entitlement.

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
