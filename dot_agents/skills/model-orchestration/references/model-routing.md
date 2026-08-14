# Model Routing

Comparative pool metadata, not a role-assignment table. Scores are relative user
defaults; cost reflects effective pool cost (1 = cheapest), not vendor list price.
Selection policy — axis ranking, quota asymmetry, effort rules, model bans — lives in
the shared global rules; this file carries the pool for harnesses without an inline
table.

| model | selector | start | cost | intelligence | taste | calibration | vision | compatibility notes |
|---|---|---:|---:|---:|---:|---:|---|---|
| GPT-5.6 Sol | `openai-codex/gpt-5.6-sol` | medium | 4 | 9 | 6 | 8 | yes | candidate when context, tools, quota, and validation fit |
| Fable 5 | `anthropic/claude-fable-5` | medium | 6 | 9 | 9 | 9 | yes | candidate when context, tools, quota, and validation fit |
| Opus 5 | `anthropic/claude-opus-5` | medium | 5 | 9 | 8 | 9 | yes | only low or medium effort; high and above are prohibited |
| Grok 4.6 | `xai/grok-4.6` (Pi, pickforge-lanes MCP) / `xai-oauth/grok-4.6` (OMP) | high | 3 | 9 | 7 | 6 | yes | provider prefix is harness-scoped; always high |
| Kimi K3 | `ollama/kimi-k3:cloud` | provider default | 4 | 8 | 8 | 4 | yes | slow (~30 tok/s, hour-scale agentic tasks); Ollama bills it as extra usage, not plan quota |

GPT-5.6 Luna/Terra and Anthropic Haiku are prohibited; `scripts/lane-policy.mjs`
enforces the bans in the dispatch wrappers. Do not use Codex `ultra`; its internal
delegation duplicates this workflow.

Kimi K3's taste score is weighted toward greenfield visual work, where it ranks first
on blind frontend comparisons; it drops materially on structural code quality and on
changes inside a large existing codebase, so score the task, not the headline. Its
calibration is measured, not guessed: review precision 0.684 vs 0.84–0.91 for peers
(Semgrep, 2026-07) and a hallucination rate that regressed generation-over-generation
— use it as a high-recall finder, never an adjudicator. Its cost score reflects
effective cost: cheap list price, but slow and token-hungry enough that cost per
successful task measures above Opus-class.

## Compatibility and fallback

- Preserve each candidate's tool, modality, privacy, and context constraints. Never
  send secrets, credentials, or private production data to cloud prompts.
- If a selected model is unavailable or incompatible, reselect the closest compatible
  candidate from this table and report the substitution. Stop only when the user
  required that exact model or no candidate fits.
- Parallelize only genuinely independent scopes; keep one writer per file/worktree,
  with isolated worktrees and patch review for parallel writers.
