## Worktrees

For risky or multi-step work, use native Git worktrees at `~/Projects/.worktrees/<repo-name>/<branch-name>` (`/` becomes `-`). Reuse/remove them with Git; never put them inside/beside the repo, in `/tmp`, or at the home root.

## Flutter

Repo patterns win. With `.fvmrc` or `.fvm/`, use `fvm flutter`/`fvm dart`. Keep logic out of widgets; prefer small, composable, theme-aware widgets. Use BLoC/Cubit only absent a clear repo pattern, and run codegen before analysis/tests.

## Writing

Keep Markdown short, useful, and human-written unless the user asks for more or clarity requires it.

## Validation and reporting

Run the narrowest behavioral validation that proves the change. If blocked, say why and name the command. Final coding reports are evidence-based: changed, validated, risks/uncertainties, and next action only if needed.

## Pickforge issue workflow

Under `~/Projects/Pickforge`, follow workspace `AGENTS.md`. Use `plan-issue` when available; otherwise keep the same phone-friendly Issue checklist, PR links, and deferred-finding follow-ups.

## Shared Agent Memory

Before user-specific work, read relevant `/home/dev/AgentMemory`: always `CORE_PROFILE.md`, `WRITING_STYLE.md`, `BOUNDARIES.md`; coding adds `WORK_AND_PROJECTS.md`; social/media adds `SOCIAL_MEDIA.md`; also relevant `projects/*.md`. Never import `archive_raw/` unless scoped. Never store secrets in memory.

## Updating these rules

Use `agent-config-sync` for global instructions, adapters, portable skills, and drift. Shared changes go to canonical chezmoi templates/adapters; never edit only a rendered `$HOME` file. Harness changes stay in that adapter; repo rules stay local unless made global. Target only compatible harnesses; use documented native fallbacks elsewhere.
