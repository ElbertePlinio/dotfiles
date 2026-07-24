## Worktrees

For risky or multi-step work, use native Git worktrees at `~/Projects/.worktrees/<repo-name>/<branch-name>` (`/` becomes `-`). Reuse/remove them with Git; never put them inside/beside the repo, in `/tmp`, or at the home root.

## Flutter

Repo patterns win. With `.fvmrc` or `.fvm/`, use `fvm flutter`/`fvm dart`. Keep logic out of widgets; prefer small, composable, theme-aware widgets. Use BLoC/Cubit only absent a clear repo pattern, and run codegen before analysis/tests.

## Writing

Keep Markdown short, useful, and human-written unless the user asks for more or clarity requires it.

## HTML readability artifacts

For substantial plans, diagrams, comparisons, or reports, offer an optional standalone HTML page — never create it unasked; an explicit request is approval. The chat answer must stand on its own. Approved pages are responsive, self-contained, and free of remote dependencies or telemetry unless requested. Save presentation artifacts under `~/Projects/Boards/<project-slug>/` or `~/Projects/Boards/_global/<topic>/` (kebab-case filenames), never inside the active repo; HTML that is real application source stays in its repo.

## Before finishing

Run the narrowest behavioral validation that proves the change. If blocked, say why and name the command. Final coding reports are evidence-based: changed, validated, risks/uncertainties, and next action only if needed.

### Decision audit

Subagent and lane reports must include a decision list: every choice the user or plan did not specify, low-confidence ones flagged with their plausible alternative, and any fix resting on an incidental choice (magic constant, coincidental size, special-cased path) surfaced as an open decision rather than a success. The orchestrator reviews decisions before diffs. `~/.claude/hooks/decision-audit-gate.sh` blocks the first push or PR of a session and prints the full checklist.

## Pickforge issue workflow

Under `~/Projects/Pickforge`, follow workspace `AGENTS.md`. Use `plan-issue` when available; otherwise keep the same phone-friendly Issue checklist, PR links, and deferred-finding follow-ups.

{{ template "agents-shared-memory.md" . }}

## Updating these rules

Use `agent-config-sync` for global instructions, adapters, portable skills, and drift. Shared changes go to canonical chezmoi templates/adapters; never edit only a rendered `$HOME` file. Never run whole-tree `chezmoi diff`/`status`/`verify` — always scope to explicit paths, since full-tree runs can hang on encrypted files. Harness changes stay in that adapter; repo rules stay local unless made global. Target only compatible harnesses; use documented native fallbacks elsewhere.
