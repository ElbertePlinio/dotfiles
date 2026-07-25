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

## Hard constraints

These are properties of the implementation, not preferences. Violating one produces a tool error or silently drops information.

- **Only `task` reaches the lane.** `rationale` is journaled for audit and never delivered to the child process. Every constraint the worker must honour — scope, interfaces, acceptance criteria, out-of-scope, validation commands — goes inside `task` itself. A contract written anywhere else is discarded. Its required contents are defined by `model-orchestration`'s `references/delegation-contract.md`; do not restate them elsewhere.
- **One active run at a time.** A second spawn is rejected while a run is active. Parallelism comes from putting many lanes in a *single* spawn, never from repeated spawns, so parallel stages of a workflow must not each spawn. Batch the whole wave, then wait.
- **Waiting does not block.** The wait call reports current state and returns; it is a state check, not a join. Finish the parent turn and check back rather than expecting it to park until lanes settle.
- **Automatic continuation on settle is Pi-only.** From Claude there is no equivalent, so a Claude session must check back on its own.

Native Claude subagents and cross-provider lanes are independent substrates and run concurrently. Spawning a lane wave does not block the session from running its own agents or workflows meanwhile — dispatch the wave first, then keep working.
