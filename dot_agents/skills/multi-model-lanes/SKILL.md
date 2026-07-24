---
name: multi-model-lanes
description: Dispatch and supervise parallel or cross-provider model lanes in Pi or Claude when work should run asynchronously with an explicit model, effort, mode, cwd, and rationale.
---

# Multi-model lanes

Use the global model policy to select each lane. Keep scope, selection, synthesis, and final judgment in the main session.

## Choose the mechanism

- In Pi, use Pi native lanes through pi-kit.
- In Claude, use native Claude-to-Claude agents for Claude models.
- For cross-provider work from Claude, use the pickforge-lanes MCP tools.

Never use a foreground or synchronous provider CLI as fallback. If the native or MCP lane is unavailable, report the block and reselect only through an approved asynchronous mechanism.

## Dispatch contract

Before spawning, state the selected model, effort, mode, cwd, and rationale. Give the lane a bounded task, relevant constraints, required validation, and a report contract. Parallelize only independent work.

Use `mcp__pickforge-lanes__lanes_spawn` to start cross-provider MCP work. Use `mcp__pickforge-lanes__lanes_status` for a deliberate state check, `mcp__pickforge-lanes__lanes_wait` once when results are needed, and `mcp__pickforge-lanes__lanes_abandon` for stuck, failed, interrupted, or no-longer-needed work. The corresponding Pi lifecycle is spawn, status, wait, and abandon.

Do not poll. Continue independent work after spawn, then wait only at the dependency boundary. Review lane decisions and evidence before accepting results.

Done means every owned lane has produced a reviewed report or has been explicitly abandoned, and no lane remains unaccounted for.
