---
name: model-runners
description: Run external models — GPT-5.6 Sol via native subagents or `codex exec`, Grok 4.5 via native subagents or the `grok` CLI. Choose model and effort per task from current routing policy. Never use Luna or Terra; Sol is the only GPT-5.6 lane.
---

# Model Runners

Choose the model and reasoning effort for the actual task from the current routing policy. Do not assign permanent model roles or reusable lane labels; live compatibility, modality, uncertainty, reversibility, and quota headroom beat static aliases.

Hard constraints: GPT-5.6 Sol is the only GPT-5.6 lane — never Luna or Terra; shift Sol's effort (low/medium/high) instead of switching models. Grok 4.5 always runs at high reasoning effort.

## Runtime choice

Prefer the harness's native model-selected subagent when it can run the model with the needed tools. In OMP, use the native `agent()` bridge with an explicit selector (`openai-codex/gpt-5.6-sol:<effort>`, `xai-oauth/grok-4.5:high`). Use the CLIs below only when the harness lacks a compatible native route or a provider-native feature is required.

## Codex CLI (GPT-5.6 Sol)

`codex exec` is non-interactive. Defaults come from `~/.codex/config.toml`; still pass model and effort explicitly when orchestration chose them.

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
- Include repository instructions, invariants, exact targets, acceptance criteria, and the narrow verification command in the prompt.
- `--skip-git-repo-check` only outside a Git repository.

Native review (scope flags and custom prompts are mutually exclusive):

```bash
codex exec review --uncommitted -m gpt-5.6-sol -c model_reasoning_effort="<effort>" -o <out.md> </dev/null
codex exec review -m gpt-5.6-sol -c model_reasoning_effort="<effort>" -o <out.md> "<review focus>" </dev/null
```

Continue a session: capture `thread_id` from the `thread.started` JSONL event, then `codex exec resume <thread_id> -c sandbox_mode="workspace-write" -o <out.md> "<findings>" </dev/null`. Persist thread IDs in the session scratchpad when a later fix round depends on them; remove only exact session files named by that ledger.

## Grok CLI (Grok 4.5)

Headless single-turn: `-p "<inline prompt>"` OR `--prompt-file <path>` — never both — runs a headless agentic loop in the target working directory and prints the final response to stdout.

```bash
grok -p "<self-contained prompt>" \
  --reasoning-effort high \
  --cwd <repo> \
  > <scratchpad>/grok-<task>-last.md 2>&1
```

- Use `--prompt-file <path>` in place of `-p` for long prompts; `--json-schema '<schema>'` for machine-readable contracts.
- Read the output file after completion instead of streaming a large transcript.
- Read-only work: `--deny "Write(*)" --deny "Edit(*)" --deny "Bash(git commit*)"`.
- Authorized edits: isolated worktree plus a session ID so fixes return to the same builder — `grok -p "<task spec>" -s "$SID" --permission-mode acceptEdits ...`, later `grok -p "<accepted findings>" -r "$SID" ...`.
- Never use `bypassPermissions`. A `--sandbox` name is safe only when that profile exists in `~/.grok/sandbox.toml`; unknown names can run unsandboxed. Grok 4.5 can inspect screenshots directly.
