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
| Grok 4.6 | `xai/grok-4.6` (Pi, pickforge-lanes MCP) / `xai-oauth/grok-4.6` (OMP) | high | 3 | 9 | 7 | 6 | yes | provider prefix is harness-scoped |
| Kimi K3 | `opencode-go/kimi-k3` | medium | 5 | 8 | 8 | 4 | yes | OpenCode Go; burns the $60 cap fast (~110 req / 5h) |
| GLM-5.3 | `opencode-go/glm-5.3` | medium | 3 | 8 | 7 | 6 | no | OpenCode Go; text-only; daily agent/terminal lane |
| Ox Alpha | `opencode-go/ox-alpha-free` | medium | 1 | 7 | 7 | 3 | yes | OpenCode Go promo, stealth lab; never adjudicate |

GPT-5.6 Luna/Terra and Anthropic Haiku are prohibited; `scripts/lane-policy.mjs`
enforces the bans in the dispatch wrappers. Do not use Codex `ultra`; its internal
delegation duplicates this workflow.

Kimi K3's taste score is weighted toward greenfield visual work (LMArena Frontend
Code Arena #1); it drops on structural edits inside a large repo. Calibration is
measured: Semgrep review precision 0.684 vs 0.84–0.91 for peers (2026-07) and
AA-Omniscience hallucination 51% (up from 39% on K2.6) — high-recall finder,
never an adjudicator. Cost 5 is Go quota burn ($3/$15 per 1M, ~490 req/month),
not Ollama list price.

GLM-5.3 matches K3 on Artificial Analysis Intelligence Index 60 (Unite.AI,
2026-08-18) and leads open-weight Terminal-Bench / long-horizon agent numbers
on Z.ai's table. Taste is agent/terminal, not UI. Vision is not in this launch.
Calibration 6 is a gap, not praise: no Semgrep-class honesty study; treat cyber
claims as vendor-reported.

Ox Alpha is a stealth OpenRouter/Go model (image+video, 1M context, $0 while
the promo lasts). Public “80% DeepSWE” figures are tiny unofficial slices, not
the 113-task set. Intelligence/taste 7 are provisional practitioner reads;
calibration 3 means it cannot close a verdict.

## Compatibility and fallback

- Preserve each candidate's tool, modality, privacy, and context constraints. Never
  send secrets, credentials, or private production data to cloud prompts.
- If a selected model is unavailable or incompatible, reselect the closest compatible
  candidate from this table and report the substitution. Stop only when the user
  required that exact model or no candidate fits.
- Parallelize only genuinely independent scopes; keep one writer per file/worktree,
  with isolated worktrees and patch review for parallel writers.
