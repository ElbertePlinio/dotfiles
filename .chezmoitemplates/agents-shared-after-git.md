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
