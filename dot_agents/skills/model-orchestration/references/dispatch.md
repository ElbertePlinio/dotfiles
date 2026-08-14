# Dispatch mechanics

How to launch a selected worker. Selection comes from the global model policy. Pass
self-contained prompts: repo rules, scope, contracts, file ownership, non-goals, and
the validation command. External workers are leaves and must not start another
orchestration layer.

## Native subagents first

Prefer the harness's own model-selected subagent whenever it can run the selected
model with the tools the task needs. Use the CLI wrappers or MCP lanes below only
when there is no compatible native route, or when a provider-native feature is
required.

- In Claude, use native Claude-to-Claude agents (the Agent/Workflow `model`
  parameter) for Claude models; the pickforge-lanes MCP rejects Anthropic selectors
  by design.
- In Pi, use Pi native lanes through pi-kit with an explicit full selector and effort
  per call.
- In OMP, use the native `agent()` bridge with an explicit selector
  (`openai-codex/gpt-5.6-sol:<effort>`, `xai-oauth/grok-4.6:high`).
- In Grok sessions: `spawn_subagent` from the main session;
  `capability_mode: read-only` for scouts, reviewers, and dissenters;
  `isolation: worktree` for parallel writers; `resume_from` for correction passes.
  Never invoke the `grok` CLI from inside Grok — that recursively launches the same
  harness.

## Cross-provider lanes (pickforge-lanes MCP)

Cross-provider work from Claude (Sol, Grok, Kimi) dispatches through the
pickforge-lanes MCP tools. Before spawning, state the selected model, effort, mode, cwd, and rationale.
Give the lane a bounded task, relevant constraints, required validation, and a report
contract. Parallelize only independent work.

- `mcp__pickforge-lanes__lanes_spawn` starts work.
- `mcp__pickforge-lanes__lanes_status` is a deliberate state check.
- `mcp__pickforge-lanes__lanes_wait` once, when results are needed.
- `mcp__pickforge-lanes__lanes_abandon` for stuck, failed, interrupted, or
  no-longer-needed work.
- The corresponding Pi lifecycle is spawn, status, wait, and abandon.

Do not poll. Continue independent work after spawn, then wait only at the dependency
boundary. Review lane decisions and evidence before accepting results.

Never use a foreground or synchronous provider CLI as fallback. If the native or MCP
lane is unavailable, report the block and reselect only through an approved
asynchronous mechanism.

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
`--model kimi-k3:cloud` for the Ollama wrapper. `fanout-review.mjs` drives multiple
reviewers in one wave — give each a distinct prompt.

## Codex CLI (GPT-5.6 Sol)

`codex exec` is non-interactive. Defaults come from `~/.codex/config.toml`; still
pass model and effort explicitly when orchestration chose them.

```bash
codex exec \
  --sandbox <read-only|workspace-write> \
  --json \
  -m gpt-5.6-sol \
  -c model_reasoning_effort="<effort>" \
  -o <scratchpad>/codex-<task>-last.md \
  "<self-contained prompt>" </dev/null
```

- Always pass `-o` and read that result file; always end with `</dev/null`.
- Never use `--dangerously-bypass-approvals-and-sandbox`.
- `read-only` for investigation/review; `workspace-write` only for authorized edits.
- Include repository instructions, invariants, exact targets, acceptance criteria,
  and the narrow verification command in the prompt.
- `--skip-git-repo-check` only outside a Git repository.

Native review (scope flags and custom prompts are mutually exclusive):

```bash
codex exec review --uncommitted -m gpt-5.6-sol -c model_reasoning_effort="<effort>" -o <out.md> </dev/null
codex exec review -m gpt-5.6-sol -c model_reasoning_effort="<effort>" -o <out.md> "<review focus>" </dev/null
```

Continue a session: capture `thread_id` from the `thread.started` JSONL event, then
`codex exec resume <thread_id> -c sandbox_mode="workspace-write" -o <out.md>
"<findings>" </dev/null`. Persist thread IDs in the session scratchpad when a later
fix round depends on them.

## Grok CLI (Grok 4.6)

Pi lanes use the authenticated `xai/grok-4.6` route first. After a reported Pi route failure, the Grok CLI is the explicit fallback; always pass `--model grok-4.6` so the fallback cannot drift to a retired default.

Headless single-turn: `-p "<inline prompt>"` OR `--prompt-file <path>` — never both —
runs a headless agentic loop in the target working directory and prints the final
response to stdout.

```bash
grok -p "<self-contained prompt>" \
  --model grok-4.6 \
  --reasoning-effort high \
  --cwd <repo> \
  > <scratchpad>/grok-<task>-last.md 2>&1
```

- Use `--prompt-file <path>` for long prompts; `--json-schema '<schema>'` for
  machine-readable contracts.
- Read the output file after completion instead of streaming a large transcript.
- Read-only work: `--deny "Write(*)" --deny "Edit(*)" --deny "Bash(git commit*)"`.
- Authorized edits: isolated worktree plus a session ID so fixes return to the same
  builder — `grok -p "<task spec>" -s "$SID" --permission-mode acceptEdits ...`,
  later `grok -p "<accepted findings>" -r "$SID" ...`.
- Never use `bypassPermissions`. A `--sandbox` name is safe only when that profile
  exists in `~/.grok/sandbox.toml`; unknown names can run unsandboxed. Grok 4.6 can
  inspect screenshots directly.
