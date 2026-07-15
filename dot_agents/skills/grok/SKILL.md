---
name: grok
description: Run Grok 4.5 through a native model-selected subagent when available, otherwise through the `grok` CLI. Choose it per task from current routing policy; always use high reasoning effort.
---

# Grok

Choose Grok for the actual task based on current routing policy, tool fit, modality, uncertainty, and quota headroom. Do not assign permanent model roles or reusable lane labels.

Grok 4.5 always runs at high reasoning effort.

## Runtime choice

Prefer the harness's native model-selected subagent when it can run Grok 4.5 with the needed tools. In OMP, use the native `agent()` bridge with `xai-oauth/grok-4.5:high`. Use the Grok CLI only when the harness lacks a compatible native route or a provider-native Grok feature is required.

## Direct CLI

`grok -p` runs a headless agentic loop in the target working directory and prints the final response to stdout.

```bash
grok -p "<self-contained prompt>" \
  --reasoning-effort high \
  --cwd <repo> \
  > <scratchpad>/grok-<task>-last.md 2>&1
```

- Use `--prompt-file <path>` for long prompts.
- Include repository instructions, invariants, exact targets, acceptance criteria, and the narrow verification command.
- Use `--json-schema '<schema>'` when the result needs a machine-readable contract.
- Read the output file after completion instead of streaming a large transcript.

For read-only work, deny edits and Git mutations explicitly:

```bash
grok -p "<prompt>" \
  --reasoning-effort high \
  --deny "Write(*)" \
  --deny "Edit(*)" \
  --deny "Bash(git commit*)" \
  --cwd <repo> > <out.md> 2>&1
```

For authorized edits, use an isolated worktree and a session ID so fixes return to the same builder:

```bash
SID=$(uuidgen)
grok -p "<task spec>" -s "$SID" \
  --permission-mode acceptEdits \
  --reasoning-effort high \
  --cwd <worktree> > <out.md> 2>&1

grok -p "<accepted findings>" -r "$SID" \
  --reasoning-effort high \
  --cwd <worktree> > <out.md> 2>&1
```

Never use `bypassPermissions`. A `--sandbox` name is safe only when that profile exists in `~/.grok/sandbox.toml`; unknown names can run unsandboxed. Grok 4.5 can inspect screenshots directly.
