---
name: modernize
description: Use when the user asks to modernize an old PR, or to rebase or update one against its base.
metadata:
  origin: Idea from t3dotgg/tstack modernize (MIT, Copyright (c) 2026 Theo Browne), rewritten for this setup.
---

Update the idea, not only the branch. A clean rebase does not prove the PR still belongs in the product.

Limits. Fetch the PR head, its base, and related branches first. Treat changes in an existing worktree as the user's, and work in a separate worktree under `~/Projects/.worktrees/<repo>/`. This skill lets you rebase and update the PR branch. It does not let you merge, close, change the base, or widen the scope. Push a rebase only with `--force-with-lease=<branch>:<head seen before the rebase>`.

Intent. Record the PR URL, state, base, head, author, checks, and review state. Read the title, body, linked issues, commits, review threads, and the whole diff. State the smallest goal the PR was trying to reach before you judge the code.

Context. Read what landed on the base since the PR diverged. Search merged and open PRs for a replacement or a rival. Ask whether the same problem is already solved, whether APIs, types, schemas, or boundaries changed, whether the touched code moved or was deleted, and whether the PR would bring back an old behavior or add a second way to do the same thing. Ask whether the benefit still pays for the upkeep. No Git conflicts does not mean current.

Disposition. Choose one before you push. MODERNIZE: the goal and the shape still fit, so rebase, resolve, test, and push. REWORK: the goal fits but the shape is wrong, so describe the smallest rewrite and stop, unless the user also asked for the rework. CLOSE: the PR is obsolete, replaced, or no longer worth its cost, so give the evidence and stop. Never close a PR without permission. Age is not evidence, and sunk effort is not a reason to keep a PR.

Rebase. For MODERNIZE:

1. Make a safe branch at the recorded PR head in the separate worktree.
2. Rebase it onto the freshly fetched base.
3. Resolve each conflict by the PR's intent and the base's newer rules. If a conflict shows a product or design disagreement, stop and reconsider the disposition.
4. Compare the commit series before and after with `git range-diff`. Confirm no intended behavior disappeared and no landed behavior came back.
5. Run the focused checks for the touched area, and tell real failures apart from old or infrastructure failures.
6. Push with the lease. If the lease fails, fetch and reassess instead of overwriting.

Report. Lead with MODERNIZE, REWORK, or CLOSE and the reason. Then give the meaningful base changes, the design conflicts or their absence, the push result, the checks and their results, and the decision left, with the PR link. Separate facts from judgment, and say what you could not verify.
