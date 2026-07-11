## Worktrees

Use worktrees for risky or multi-step implementation. Create them in the centralized location, outside the repo:

```text
~/Projects/.worktrees/<repo-name>/<branch-name>
```

- Sanitize branch names for the directory: replace `/` with `-` (e.g. `feat/login` -> `feat-login`).
- Discover existing worktrees with `git worktree list`.
- Clean up with `git worktree remove` and `git worktree prune` when done.
- Do not create worktrees inside the repo, as siblings of it, in `/tmp`, or in the home directory root.

## Flutter

- Repo patterns win.
- If `.fvmrc` or `.fvm/` exists, use `fvm flutter` and `fvm dart`.
- Keep business logic out of widgets.
- Prefer small, composable, theme-aware widgets.
- BLoC/Cubit is my default only when the repo does not already have a clear different pattern.
- When codegen is involved, run codegen before analyze/tests.

## Writing Markdown

When creating `.md` files, keep them short, concise, and human-written. Make them feel like useful notes, not machine policy. Only write more when I ask or when clarity would suffer.

## Before finishing

Run the narrowest useful validation. If you cannot run it, say why and name the command I should run.

Final coding reports should be compact:

1. Changed
2. Validated
3. Risks/uncertainties
4. Next action, only if needed

## Pickforge GitHub Issues as source of truth

When working in any repo under `~/Projects/Pickforge`, prefer the workspace policy in `~/Projects/Pickforge/AGENTS.md`. Use the `plan-issue` skill when available; otherwise keep a phone-friendly GitHub Issue checklist, link PRs to issues, and file follow-ups for deferred review/CI findings.

## Context7 usage

Use Context7 MCP to fetch current documentation whenever the user asks about a library, framework, SDK, API, CLI tool, or cloud service -- even well-known ones. Use even when you think you know the answer -- your training data may not reflect recent changes. Prefer this over web search for library docs. Do not use for refactoring, writing scripts from scratch, debugging business logic, code review, or general programming concepts.

1. Start with `resolve-library-id` using the library name and the user's question, unless given an exact `/org/project` ID.
2. Pick the best match by name, relevance, snippet count, reputation, and benchmark score. Use version-specific IDs when a version is mentioned.
3. `query-docs` with the selected library ID and the user's full question.
4. Answer using the fetched docs.

## Shared Agent Memory

Before user-specific work, read relevant files from `/home/dev/AgentMemory`:

- Always: `CORE_PROFILE.md`, `WRITING_STYLE.md`, `BOUNDARIES.md`
- Coding: `CODING_AGENT_RULES.md`, `WORK_AND_PROJECTS.md`
- Social/media: `SOCIAL_MEDIA.md`
- Project-specific: `projects/*.md`

Do not read or import `/home/dev/AgentMemory/archive_raw/` unless explicitly scoped. Do not store secrets in memory.

## Updating these rules

- Use the `agent-config-sync` skill for global agent instructions, harness adapters, portable skills, and chezmoi agent-config drift. Run `agent-config-sync check` before editing and `agent-config-sync apply` after validation.
- Global or shared agent-rule and portable-skill requests update the canonical chezmoi source under `/home/dev/.local/share/chezmoi` (`.chezmoitemplates/agents-shared*.md` and applicable adapters) — never only a rendered file under `$HOME`.
- Harness-specific requests change only that harness adapter.
- Repo instruction requests stay repo-local unless the user explicitly asks for a global change.
- Apply a skill only on harnesses that support it; other harnesses use the documented direct fallback.

<!-- CODEGRAPH_START -->

## CodeGraph

In repositories indexed by CodeGraph (a `.codegraph/` directory exists at the repo root), reach for it BEFORE grep/find or reading files when you need to understand or locate code:

- **MCP tool** (when available): `codegraph_explore` answers most code questions in one call — the relevant symbols' verbatim source plus the call paths between them, including dynamic-dispatch hops grep can't follow. Name a file or symbol in the query to read its current line-numbered source. If it's listed but deferred, load it by name via tool search.
- **Shell** (always works): `codegraph explore "<symbol names or question>"` prints the same output.

If there is no `.codegraph/` directory, skip CodeGraph entirely — indexing is the user's decision.
<!-- CODEGRAPH_END -->
