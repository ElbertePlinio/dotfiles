# Dispatch mechanics

How to launch a selected worker. Pass self-contained prompts: repo rules, scope,
contracts, file ownership, non-goals, and the validation command. External workers are
leaves and must not start another orchestration layer.

## Harnesses with native subagents

Prefer the harness's own model-selected subagent whenever it can run the selected model
with the tools the task needs. Use the CLI wrappers below only when there is no
compatible native route, or when a provider-native feature is required.

In Grok sessions:

- `spawn_subagent` from the main session.
- `capability_mode: read-only` for scouts, reviewers, and dissenters.
- `isolation: worktree` for parallel writers.
- Background subagents only when the parent has useful independent work to continue.
- `resume_from` for correction passes where preserving worker context helps.
- Never invoke the `grok` CLI from inside Grok — that recursively launches the same
  harness.

## Wrapper scripts

These live in the canonical skill directory, so the paths below resolve from every
harness the skill is installed in:

```bash
node ~/.agents/skills/model-orchestration/scripts/codex-delegate.mjs \
  --model <selected-model> \
  --mode <scout|implement|review> \
  --cwd "$PWD" \
  --prompt-file <prompt.md>
```

`claude-delegate.mjs` and `ollama-delegate.mjs` take the same flags; use
`--model glm-5.2:cloud` for the Ollama wrapper. `fanout-review.mjs` drives multiple
reviewers in one wave — give each a distinct prompt.

For per-CLI invocation detail (Codex `codex exec`, the `grok` CLI), see the
`model-runners` skill.
