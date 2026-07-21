# OpenCode

Global OpenCode setup with a 3-level company hierarchy: CTO orchestrates, Senior DEV handles complex work, Mid DEV implements.

## Files

- `opencode.json`
  - main config
  - default agent: `cto`
  - custom commands
  - MCP server definitions
- `AGENTS.md`
  - global communication rules in ultra-terse mode
  - company structure overview
- `agents/`
  - `cto.md` — primary agent, GPT 5.5, strategic orchestration
  - `senior-dev.md` — subagent, GPT 5.5, architecture/review/complex refactors
  - `mid-dev.md` — subagent, DeepSeek V4 Pro (Ollama Cloud), hands-on implementation
- `tools/workflow-route.ts`
  - deterministic task router for CTO (routes to self, senior-dev, or mid-dev)
- `WORKFLOW_DIAGRAM.md`
  - Mermaid workflow diagram
- `package.json`
  - `@opencode-ai/plugin` dependency

## Company Hierarchy

| Role | Model | Responsibilities |
|------|-------|-----------------|
| **CTO** | GPT 5.5 | Strategic orchestration, planning, delegation, final approval |
| **Senior DEV** | GPT 5.5 | Architecture decisions, code review, complex refactors, delegates to Mid DEV |
| **Mid DEV** | DeepSeek V4 Pro (Ollama Cloud) | Hands-on implementation, testing, git operations, PRs |

Flow: `User → CTO → Senior DEV (complex) or Mid DEV (routine) → back to CTO → final answer`

- **CTO** never edits files or runs commands. Routes everything to Senior or Mid.
- **Senior DEV** handles complex/ambiguous work, delegates routine implementation to Mid DEV.
- **Mid DEV** does bulk coding, testing, and operations.

## Configured MCP Servers

- `context7`

## Installation

This repository stores the OpenCode configuration, not the OpenCode binary itself.

### Prerequisites

- OpenCode installed on the machine
- provider authentication already configured (`opencode providers`)
- `bun` or `npm` available to install the local plugin dependency

### Install On macOS/Linux

Create the target directory:

```bash
mkdir -p ~/.config/opencode
```

Copy the contents of this folder into the OpenCode config directory:

```bash
rsync -a opencode/ ~/.config/opencode/
```

Install the local dependency used by the custom tool/plugin setup:

```bash
cd ~/.config/opencode && bun install
```

If you do not use Bun:

```bash
cd ~/.config/opencode && npm install
```

### Verify The Setup

Run:

```bash
opencode debug config
opencode agent list
```

Expected result:

- default agent is `cto`
- CTO model is `openai/gpt-5.5`
- Senior DEV model is `openai/gpt-5.5`
- Mid DEV model is `ollama-cloud/deepseek-v4-pro`
- the `context7` MCP server appears in the resolved config

### MCP Authentication Notes

Context7 is configured here as a remote MCP server.

Set `CONTEXT7_API_KEY` in the shell environment before starting OpenCode.

## Daily Usage

For normal day-to-day work, talk to `cto`.

- Ask questions to `cto`
- Ask for implementation through `cto`
- Let `cto` decide when to call Senior DEV or Mid DEV

### Custom Commands

- `/ship`
  - end-to-end implementation through CTO orchestration
- `/code`
  - direct implementation by Mid DEV for routine coding
- `/senior`
  - code review, architecture, or complex decisions by Senior DEV
- `/plan`
  - get a plan from CTO without implementing

## Agents

### `cto`

Primary agent. Strategic orchestration, not hands-on execution.

Responsibilities:
- understand user intent
- break tasks into subtasks
- delegate to Senior DEV (complex) or Mid DEV (routine)
- integrate results
- final approval

### `senior-dev`

Subagent for complex technical work.

Responsibilities:
- architecture and design decisions
- code review
- complex refactors
- hard bugs and investigation
- delegates routine implementation to Mid DEV

### `mid-dev`

Subagent for hands-on execution.

Responsibilities:
- implementing features, fixes, refactors
- running tests
- git operations (commits, pushes, PRs)
- benchmarks, evals, CI checks

## `workflow-route` Tool

Custom tool for deterministic routing of non-trivial tasks by the CTO.

Possible routes:

- `self` — CTO handles directly
- `senior-dev` — complex, architecture, review
- `mid-dev` — routine implementation, tests, ops

## Mental Model Of The Setup

1. Talk to `cto`
2. `cto` decides whether to answer directly or delegate
3. `cto` routes to Senior DEV (complex) or Mid DEV (routine)
4. Senior DEV may delegate implementation to Mid DEV
5. Results flow back to `cto` for integration and final answer

Goal: clear chain of command, expensive models used only for high-value work, bulk implementation on cheaper model.
