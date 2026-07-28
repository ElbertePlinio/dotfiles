## Worktrees

For risky or multi-step work, use native Git worktrees at `~/Projects/.worktrees/<repo-name>/<branch-name>` (`/` becomes `-`). Reuse/remove them with Git; never put them inside/beside the repo, in `/tmp`, or at the home root.

## Flutter

Repo patterns win. With `.fvmrc` or `.fvm/`, use `fvm flutter`/`fvm dart`. Keep logic out of widgets; prefer small, composable, theme-aware widgets. Use BLoC/Cubit only absent a clear repo pattern, and run codegen before analysis/tests.

## Writing and artifacts

Keep Markdown short, useful, and human-written. For substantial plans or reports, offer an optional standalone HTML page — never create it unasked; the chat answer must stand on its own. Approved pages are responsive and self-contained; save them under `~/Projects/Boards/<project-slug>/` or `~/Projects/Boards/_global/<topic>/` (kebab-case filenames), never inside the active repo.

## Before finishing

Run the narrowest behavioral validation that proves the change. If blocked, say why and name the command. Final coding reports are evidence-based: changed, validated, risks/uncertainties, and next action only if needed. Subagent and lane reports include a decision list — every choice the user or plan did not specify, low-confidence ones flagged with their plausible alternative, and fixes resting on incidental choices surfaced as open decisions; the orchestrator reviews decisions before diffs (`~/.claude/hooks/decision-audit-gate.sh` enforces this at the session's first push or PR).

## Pickforge issue workflow

Under `~/Projects/Pickforge`, follow workspace `AGENTS.md`. Use `plan-issue` when available so GitHub Issues stay the phone-friendly source of truth, with PR links and deferred-finding follow-ups.

{{ template "agents-shared-memory.md" . }}

## Updating these rules

Use `agent-config-sync` for global instructions, adapters, portable skills, and drift. Shared changes go to canonical chezmoi templates/adapters; never edit only a rendered `$HOME` file. Never run whole-tree `chezmoi diff`/`status`/`verify` — always scope to explicit paths, since full-tree runs can hang on encrypted files. Pi and Claude Code are the primary automation harnesses; OMP, Codex, and Grok get instructions-only mirrors where compatible.
