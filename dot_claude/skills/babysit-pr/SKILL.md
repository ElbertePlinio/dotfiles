---
name: babysit-pr
description: Use when the user asks to watch, monitor, or babysit a PR, or when full-send, full-stop, kickoff, or takeover reaches its babysitting step.
metadata:
  origin: Idea from t3dotgg/tstack babysit-pr (MIT, Copyright (c) 2026 Theo Browne), rewritten for this setup.
---

Waiting. Never write your own polling or sleep loop, and run one watcher per PR. In T3 Code, handle the current checks and comments first, then call `watch_pull_request` and end your turn. T3 wakes you when a check fails, the required checks pass, someone comments or reviews, or the branch conflicts. Only the thread that owns the PR watches it; a delegated child never does. A wake is news, not a merge decision. Call `unwatch_pull_request` before you hand off or ask the user a question, and call `watch_pull_request` again after the answer. If T3 says it stopped watching, check `gh api rate_limit --jq .resources.graphql`, and when it is near zero, wait for the reset with one background command. Outside T3, run `gh pr checks <n> --watch --required` in the background so its exit wakes you, then read the reviews and comments. If a gating bot has not reviewed the head yet, wait once with one background `sleep 600` and read again. If it still has not, report it as the blocker. Start the watch again after each push. When an event needs no action, end your turn without a message.

Checks. Tell real failures apart from infrastructure flakes. Rerun a flaky job once with `gh run rerun <run-id> --failed`, and never merge while any check fails or is pending. When GitHub Actions is down for billing or usage limits, run the jobs locally on the PR head merged with its base. When GraphQL is used up, read the PR through REST with `gh api repos/<owner>/<repo>/pulls/<n>` and checks with `.../commits/<sha>/check-runs`.

Reviews. Assess every unresolved thread and every comment since the latest push against the current source, and skip what you already answered. Check every bot finding against the source before you change code. Fix real findings. If the repo has `.macroscope/check-run-agents/*.md`, read those rules before you answer Macroscope. Greptile and Macroscope gate the merge when the repo uses them. CodeRabbit is advisory, so never wait for it or hold a merge for it. Keep the PR at the size the goal needs. Decline unneeded tests, guards for edge cases that do not matter, extra compatibility, and small performance costs, and list them as follow-ups. Prefer the fix that deletes or narrows code.

Replies. Answer review bots on the PR and resolve their threads after the reply posts. Replies to people stay drafts in your report for the user to send. Start every reply with this note, using the verified model name or, without one, the harness name:

```md
> [!NOTE]
> 🤖 <model> responding on behalf of <user>

Reply text starts here.
```

Lead with the conclusion, cite the code, check, or reproduction, and keep it short. Check the reply for secrets and private details before you post it.

Base branch. Keep the branch current. `watch_pull_request` reports conflicts only, so check `gh pr view <n> --json mergeStateStatus` for BEHIND before you call the PR ready. Right before a merge, fetch and check the PR again. Never merge when it is BEHIND or DIRTY, or when base commits after the last green run touch this PR's files: rebase, push, and wait for green again. If an overlapping PR makes this one obsolete, stop and ask before you close anything. Merge only when the user or a skill such as full-send authorized it; otherwise report that the PR is ready.
