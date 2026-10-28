---
name: codex
description: Use to run an OpenAI model through the Codex CLI from Claude Code outside T3, such as a Sol review for sol-loop or the council's OpenAI seat.
---

Run every Codex task through `~/.claude/skills/codex/scripts/codex-run` with the brief on stdin, in the background with `run_in_background`, so the session wakes when it ends. The user's ChatGPT Plus limit is small, so run one Codex task at a time. `sol` is GPT-6.1 Sol, for reviews. Use `author` mode and `astra`, GPT-6 Astra, only when the user asks, because Opus writes the code and Astra costs about six times as much as Sol. Effort is low, medium, high, or xhigh; give a one-line reason for the model and effort.

`codex-run author --repo <worktree> --model sol --effort <e>` edits in that worktree, which must be one you own for the task, never the main checkout. `codex-run review --repo <repo> --rev <sha>` and `codex-run investigate --repo <repo> --rev <sha>` default to Sol. Both run with full access in a fresh detached worktree under `~/Projects/.worktrees/<repo>/`, so the model can run tests, builds, network, and Xvfb, and the worktree is removed afterwards even on failure. The script tells the model to stay read-only and adds the standing prohibitions on dispatch, release, publish, tag, push, and sudo. It also turns off the Lanes MCP, so Codex cannot delegate further.

Write briefs the same way you would for any worker: requirements, owned files or the exact diff (`git diff origin/main...<sha>`), validation evidence, and scope limits. Leave out the author's rationale and other reviewers' findings from a review brief, and ask for findings with file, line, severity, and a concrete failure scenario.

Output goes to `~/.pickforge/codex-runs/<repo>/<mode>-<sha>-<time>/` unless you pass `--out`. The script prints the session id, the exit status, and the path of `last-message.md`, which holds the result. `events.jsonl` and `stderr.log` hold the full run. A `stray-changes.txt` line means the model edited files during an assessment. The worktree is already gone, so report it and treat the run as suspect; nothing it changed is kept.

To send repairs or a recheck to the same Codex session, pass `--resume <session-id>` with the same mode and model, the new `--rev`, and a brief that lists only the findings and what changed. A resumed review runs in a fresh worktree at the new revision.

A nonzero exit or a `failed=` line is a run failure: read `stderr.log` and the error before retrying. Tell provider, auth, or quota errors apart from model defects, and do not switch models or raise effort because of them.
