---
name: model-orchestration
description: Adaptively route substantial, risky, multi-file, multi-model, review, or fan-out work from a Grok main session across Grok native subagents, Codex GPT-5.6, Claude models, and Ollama GLM. Use when delegation or independent review materially improves the result.
---

# Adaptive Model Orchestration

Keep the current Grok session as orchestrator. It owns scope, contracts, routing, synthesis, validation, and final acceptance.

## Routing

1. Read `~/.codex/skills/model-orchestration/references/model-routing.md` completely before choosing models.
2. Treat its table as comparative context, never as permanent role assignments.
3. Reconsider the full table for every task using risk, uncertainty, context size, tools and modalities, validation options, output quality, and pool headroom.
4. Use the lightest sufficient mode:
   - `simple`: the current session completes and validates the task.
   - `standard`: one implementation lane, then `$local-review`.
   - `serious`: risk-targeted orchestration, then `$local-review`.
   - `fanout`: isolated worktrees only for genuinely independent scopes.
5. Before a multi-task wave, use `$pickgauge-usage` to check pool headroom.

Do not map any model permanently to scouting, architecture, UI, implementation, review, dissent, or another task class. Scores, examples, and previous successful routes are evidence, not assignments.

## Execution

Use Grok native subagents when the selected worker is Grok:

- Use `spawn_subagent` from the main session.
- Use `capability_mode: read-only` for scouts and reviewers.
- Use `isolation: worktree` for parallel writers.
- Use background subagents only when the parent can continue useful independent work.
- Use `resume_from` for correction passes when preserving the worker context helps.
- Never invoke the `grok` CLI from inside Grok; that recursively launches the same harness.

Use the shared wrappers when another pool is selected:

```bash
node ~/.codex/skills/model-orchestration/scripts/codex-delegate.mjs \
  --model <selected-model> \
  --mode <scout|implement|review> \
  --cwd "$PWD" \
  --prompt-file <prompt.md>
```

```bash
node ~/.codex/skills/model-orchestration/scripts/claude-delegate.mjs \
  --model <selected-model> \
  --mode <scout|implement|review> \
  --cwd "$PWD" \
  --prompt-file <prompt.md>
```

```bash
node ~/.codex/skills/model-orchestration/scripts/ollama-delegate.mjs \
  --model glm-5.2:cloud \
  --mode <scout|implement|review> \
  --cwd "$PWD" \
  --prompt-file <prompt.md>
```

Pass self-contained prompts with repo rules, scope, contracts, file ownership, non-goals, and validation commands. External workers are leaves and must not start another orchestration layer.

## Hard Rules

- Keep one active writer per file/worktree.
- Put parallel writers in isolated worktrees and review their patches before integration.
- Keep scouts, reviewers, and dissenters read-only.
- GLM is text-only. Convert visual evidence to text before routing it there.
- Do not route secrets, credentials, or private production data to external model prompts.
- Report every substitution. If Fable 5 is unavailable, use Opus 4.8 at xhigh, then Grok 4.5 at high. If GPT-5.6 Sol is unavailable, use GPT-5.6 Terra at xhigh. For other unavailable models, use the closest compatible substitute. Stop when the user explicitly requires the unavailable model or no substitute fits.
- If this Grok session was launched as a leaf by another orchestrator, do the assigned task directly and do not re-delegate.
- After behavioral validation, follow `$local-review`; it owns review models, profiles, provider diversity, critical adjudication, overengineering, findings, and rounds.

Synthesize every worker result in the main session. Reject weak or contradictory output, run the narrowest useful validation, and report changes, proof, and residual risk.
