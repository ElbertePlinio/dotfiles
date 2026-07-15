---
name: codex
description: Run GPT-5.6 through native model-selected subagents when available, otherwise through `codex exec`. Choose the compatible model and effort per task from current routing policy. Never use Luna.
---

# Codex

Choose the GPT-5.6 model and reasoning effort for the actual task. Do not assign permanent model roles or reusable lane labels. Read the current model-routing owner before selecting a model; live compatibility, modality, uncertainty, reversibility, and quota headroom beat static aliases.

Never use GPT-5.6 Luna. Use another compatible GPT-5.6 model from the current managed pool.

## Runtime choice

Prefer the harness's native model-selected subagent when it can run the requested GPT-5.6 model with the needed tools. In OMP, use the native `agent()` bridge with an explicit model selector. Use the Codex CLI only when the harness lacks a compatible native route or a provider-native Codex feature is required.

## Direct CLI

`codex exec` is non-interactive. Defaults come from `~/.codex/config.toml`; still pass the selected model and effort explicitly when orchestration chose them.

```bash
codex exec \
  --sandbox <read-only|workspace-write> \
  --json \
  -m <gpt-5.6-model> \
  -c model_reasoning_effort="<effort>" \
  -o <scratchpad>/codex-<task>-last.md \
  "<self-contained prompt>" </dev/null
```

- Always pass `-o` and read that result file instead of the full transcript.
- Always end the command with `</dev/null`; Codex reads stdin when piped.
- Never use `--dangerously-bypass-approvals-and-sandbox`.
- Use `read-only` for investigation/review and `workspace-write` only for authorized edits.
- Include repository instructions, invariants, exact targets, acceptance criteria, and the narrow verification command in the prompt.
- Use `--skip-git-repo-check` only outside a Git repository.

For a native Codex review, scope flags and custom prompts are mutually exclusive:

```bash
codex exec review --uncommitted -m <gpt-5.6-model> -c model_reasoning_effort="<effort>" -o <out.md> </dev/null
codex exec review -m <gpt-5.6-model> -c model_reasoning_effort="<effort>" -o <out.md> "<review focus>" </dev/null
```

## Continue the same session

Capture the `thread_id` from the `thread.started` JSONL event. Send accepted findings back to that same session:

```bash
codex exec resume <thread_id> \
  -c sandbox_mode="workspace-write" \
  -o <out.md> \
  "<findings>" </dev/null
```

Persist thread IDs in the session scratchpad when a later fix round depends on them. Remove only exact session files named by that ledger; never delete by date, prefix, or loose glob.
