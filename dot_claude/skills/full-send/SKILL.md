---
name: full-send
description: Use when the user says "full send". They are not watching and want the work taken to a merged PR.
metadata:
  origin: Idea from t3dotgg/tstack full-send (MIT, Copyright (c) 2026 Theo Browne), rewritten for this setup.
---

The user said "full send" because they are not watching this thread. They read your messages long after you stop. You own the work from its current state to a merged PR. Without a clear full-send request, do not assume this autonomy.

Grant. A full-send request lets you merge the PR when the merge gate passes, and force-push this task's own branch with `--force-with-lease` after a rebase. It also lets you use any test method that proof needs without asking first, such as browser automation, simulators, running the app, or screenshots. That replaces ask-first test rules in project files for this task. Rules about how to test still apply, and a harness approval prompt still applies.

Steps.

1. Finish the change with the smallest change that works. Fix the case that happened, not every case that could. On the default branch, branch first in `~/Projects/.worktrees/<repo>/<branch>`.
2. Prove it, as the proof paragraph describes.
3. Review it with the sol-loop skill. While a Sol round runs, run the repo's checks and PickCheck, because they do not edit files.
4. File the PR with the file-pr skill, after a rebase on the latest default branch.
5. Babysit it with the babysit-pr skill. Fix real findings and CI failures, and prove each fix before you push.
6. Merge when the merge gate passes.
7. Report the PR link, the merge commit, your proof, the review verdict, and each decision you made for the user.

Stay active from step 1 to step 7. If you end your turn while checks or bots are pending, nothing wakes you, unless a watcher from babysit-pr runs. If you stop before the merge, unwatch first.

Proof. Proof is evidence you saw yourself in this session, such as command output, a reproduction, or a screenshot. Reproduce the original failure, apply the fix, and watch the same reproduction pass. Run the checks the repo's CI runs. Add one focused test that fails without the fix when the behavior has none and the repo has tests. For UI and runtime behavior, run the app and look; use the device-pass skill for user journeys. Green mocked tests do not prove the user experience. For a migration, run it against staging or a copy of the data, keep it compatible with the running code, and prove the rollback or a verified backup. For Stripe, use test mode or a sandbox, and drive webhooks with the Stripe CLI. Write the rollback path in the PR. Without proof you do not have full confidence, so ask.

Merge gate. Merge only when all of these hold on the latest commit. Your proof covers every change in the diff. Every required check is green, with none pending or failing, including flaky ones. PickCheck passes. Sol approved, or each open dispute is settled with evidence and written in the PR. Review bots have finished, and each finding is fixed or answered with a reason. No person still requests changes. The branch is up to date with the default branch, and GitHub reports it mergeable. Merge with the repo's usual method and never with `--admin` or another bypass. With a merge queue or auto-merge, stay until GitHub reports the PR merged.

Asking. A question in a normal message goes unseen, and the thread looks done. Use the question tool, `AskUserQuestion` in Claude Code, so the thread shows it waits. Put all the context in the question: the PR link, what blocks you, and the options with your recommendation first. Ask only when you cannot continue alone: you cannot prove the change, the gate cannot pass and you cannot fix it, the goal is ambiguous in a way that changes the result, another PR makes this one obsolete, or the next step is one of the hard stops in your global instructions, such as real money or production data without a backup. Decide everything else with sensible defaults, and list those decisions in the report. If the question tool is missing or returns no answer, take the safe path: leave the PR open and unmerged, and start the final message with the question.
