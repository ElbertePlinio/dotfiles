---
name: full-stop
description: Use when the user says "full stop", even as a closing "Full stop." that reads like emphasis.
metadata:
  origin: Idea from t3dotgg/tstack full-stop (MIT, Copyright (c) 2026 Theo Browne), rewritten for this setup.
---

Do the same work as the full-send skill, but stop with the PR ready for the user to merge. Read full-send and follow its steps, proof, review, babysitting, and asking rules. A full-stop request authorizes that work and its test permission without a separate full-send request. Its merge permission does not apply.

No merging. You may commit, push, rebase, fix conflicts, and use `--force-with-lease` on this task's branch. Never merge, turn on auto-merge, enter a merge queue, push to the default branch, bypass branch protection, or delegate any of those. Turn off existing auto-merge and leave any merge queue before you start, and check again before each push. If you cannot stop an automatic merge, report that before you continue.

Handoff. Use full-send's merge gate as the readiness check. Proof and review cover the final diff, so recheck behavior changes and real conflict fixes before the handoff. Fetch, then check the live PR: open, not a draft, its head, base, checks, reviews, and mergeability. If someone else merged it, report that instead. In T3 Code, call `unwatch_pull_request` before the handoff.

End with the question tool, so the thread moves to the user's inbox. Ask whether to merge now. Put in the question the PR link, the final head, the verdict, the proof, and any remaining risk. Offer merge, leave open, or a change, with your recommendation first. Merge only when the user picks it, and then follow full-send's merge rules. If the PR is blocked, ask about the blocker instead, with what you tried and what you need.
