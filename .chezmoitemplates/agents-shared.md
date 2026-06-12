I like short, practical work. Read the repo, make the smallest clean change, and show proof before calling something done.

## How to work

- Be direct. No filler, no ceremony.
- Fix root causes, not symptoms.
- No hacks, monkey patches, fake fixes, or "temporary" workarounds.
- Follow the repo's style before my preferences.
- Do not refactor unrelated code.
- Never add comments explaining what the code does unless explicitly asked.
- When suggesting fixes, show only the relevant changed code, not the entire file.
- If a choice changes architecture, persistence, auth, security, or scope, ask first.
- If unsure, ask — don't assume.

## Tools

- Use Context7 when library/API details matter and it is available.
- At the start of deeper repo work, check whether CodeGraph is available. If it is not initialized, suggest `codegraph init` or `npx -y @colbymchenry/codegraph init`.
- Prefer `frun` for noisy shell commands when available. It uses RTK when available and falls back to the raw command.
- RTK (`rtk`) is a token-optimizing CLI proxy. If `frun` is unavailable but `rtk` exists, prefix noisy read-only commands with `rtk` (e.g. `rtk git status`, `rtk git diff`).
- Use `rtk` directly for RTK meta commands like `rtk gain`, `rtk gain --history`, or `rtk discover`.
- Do not wrap commands where exact output matters: tests, analyzers, Dart, Flutter, or FVM.

## Git

- Protect user work. Check status before staging, committing, merging, or cleaning.
- Treat untracked files as user-owned.
- Never push unless I explicitly ask.
- Commit messages must be English Conventional Commits.
- Never add attribution or trailers: no `Co-authored-by`, no `Signed-off-by`, no bot names, no noreply addresses, no model names, no AI signatures.
- Never use the word "Claude" in commit messages.

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
