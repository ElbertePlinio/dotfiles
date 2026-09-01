# Model Routing

Comparative pool metadata, not a role-assignment table. Scores are relative user
defaults; cost reflects effective pool cost (1 = cheapest), not vendor list price.
Selection policy — axis ranking, quota asymmetry, effort rules, model bans — lives in
the shared global rules; this file carries the pool for harnesses without an inline
table.

| model | selector | start | cost | intelligence | taste | calibration | vision | compatibility notes |
|---|---|---:|---:|---:|---:|---:|---|---|
| GPT-5.6 Sol | `openai-codex/gpt-5.6-sol` | medium | 4 | 9 | 6 | 8 | yes | candidate when context, tools, quota, and validation fit |
| Fable 5.1 | `anthropic/claude-fable-5-1` | medium | 6 | 9 | 9 | 9 | yes | candidate when context, tools, quota, and validation fit |
| Opus 5 | `anthropic/claude-opus-5` | medium | 5 | 9 | 8 | 9 | yes | only low or medium effort; high and above are prohibited |
| Grok 4.6 | `xai/grok-4.6` (Pi, pickforge-lanes MCP) / `xai-oauth/grok-4.6` (OMP) | high | 3 | 9 | 7 | 6 | yes | provider prefix is harness-scoped |
| Kimi K3 | `opencode-go/kimi-k3` | medium | 5 | 8 | 8 | 4 | yes | OpenCode Go; burns the $60 cap fast (~110 req / 5h) |
| GLM-5.3 Flash | `opencode-go/glm-5.3-flash` | medium | 1 | 7 | 7 | 6 | yes | OpenCode Go; image+video in; cheapest lane; not the long-horizon tail |

GPT-5.6 Luna/Terra and Anthropic Haiku are prohibited; `scripts/lane-policy.mjs`
enforces the bans in the dispatch wrappers. Do not use Codex `ultra`; its internal
delegation duplicates this workflow.

Kimi K3's taste score is weighted toward greenfield visual work (LMArena Frontend
Code Arena #1); it drops on structural edits inside a large repo. Calibration is
measured: Semgrep review precision 0.684 vs 0.84–0.91 for peers (2026-07) and
AA-Omniscience hallucination 51% (up from 39% on K2.6) — high-recall finder,
never an adjudicator. Cost 5 is Go quota burn ($3/$15 per 1M, ~490 req/month),
not Ollama list price.

GLM-5.3 Flash is the cheap, multimodal sibling of GLM-5.3, not a faster one:
it is a 320B MoE with 18B active that cuts attention compute 3.01x and KV cache
4.44x, buying cost rather than throughput. It generates ~49.8 output tok/s
against the flagship's 66.5 and wins only on time-to-first-token (1.51s vs
1.62s). Cost 1 reflects $0.15/$0.50 per 1M against the flagship's $1.40/$4.40.

Intelligence 7 is measured, not inherited: Artificial Analysis Intelligence
Index 57 vs 60, and llm-stats coding 37.8 vs 45.4 — a 17% coding gap, the
widest of any sub-score. On DeepSWE v1.1, the only benchmark both models were
actually run on, the gap narrows to 63.4 vs 66.9; most Flash-favourable
comparisons are not like-for-like, so treat Terminal-Bench 2.1 84.3 and
"ahead of Claude Opus 4.8" as vendor-reported and unmatched.

Vision is the real differentiator and the reason this lane is vision-capable at
all: Flash takes image and video input, which the flagship cannot. It is built
for vision-driven UI coding, screenshot debugging, and UI verification. Route
high-volume, spec-ready, and visual work here; send long-horizon or hard
engineering to Sol or Opus instead. Calibration 6 is a gap, not praise: no
Semgrep-class honesty study exists for Flash specifically.

Operational cautions, from practitioner reports the week of its 2026-08-26
unmasking (it is the model that ran as the Ox Alpha stealth preview):

- Reasoning is always on and cannot be disabled. Reports exist of it spending an
  entire token budget thinking before emitting a single edit, and of subagents
  returning 400 on their first turn when a parent's effort setting is dropped.
  Always pass an explicit effort when dispatching this lane.
- Hosted throughput is commonly 20-40 tok/s and has been measured slower than
  the hosted flagship on the same endpoint. Local FP8/NVFP4 serving inverts
  this; the penalty is an endpoint property, not a model one.
- Z.ai acknowledged a configuration degradation on 2026-08-26/27 and rolled it
  back; some same-task traces still report the stealth build outperforming the
  released one. Treat unattended agent loops on this lane as unproven.
- On the OpenCode Go plan it has been reported as metered against a smaller
  monthly allowance than the other cheap lanes, so Cost 1 tracks per-token
  price and may understate quota burn.

Where it does win on evidence: a same-task security review (VulnPR-100) scored
Flash 34/100 at $4.21 against the flagship's 32/100 at $82 — better and ~19x
cheaper — and Flash ships MIT weights where the flagship does not.



## Compatibility and fallback

- Preserve each candidate's tool, modality, privacy, and context constraints. Never
  send secrets, credentials, or private production data to cloud prompts.
- If a selected model is unavailable or incompatible, reselect the closest compatible
  candidate from this table and report the substitution. Stop only when the user
  required that exact model or no candidate fits.
- Parallelize only genuinely independent scopes; keep one writer per file/worktree,
  with isolated worktrees and patch review for parallel writers.
