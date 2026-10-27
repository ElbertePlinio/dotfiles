---
name: takeover
description: Use when the user asks to take over a PR, branch, or agent thread.
metadata:
  origin: Idea from t3dotgg/tstack takeover (MIT, Copyright (c) 2026 Theo Browne), rewritten for this setup.
---

Finish the original goal of someone else's work, and keep the original contributors' credit. Do not defend an implementation only because another agent built it.

Read the source PR, branch, or thread, with its review findings and the user's later corrections. Resolve it to the real code at the current head, and account for uncommitted work. The handoff is context, not proof.

Run the intent, context, and disposition steps of the modernize skill first, without its rebase or push. They decide whether the goal still matters and whether the code is a starting point or only a reference. Do all rework on your replacement branch. Rework what the same goal needs and nothing more. Simplify, but keep every intended behavior.

For a replacement PR, bring the original commits onto a new branch and add your fixes as separate commits, so authorship survives. Continue in place or stacked only when the user asks for it. Never change the original PR, or overwrite work on it, without permission. Credit the original contributors in the PR description and link their PR. Model attribution does not replace contributor credit.

Verify the original failure and the real user journeys yourself, as full-send's proof paragraph describes, and say what stays unverified. Then use sol-loop, file-pr, and babysit-pr. Merge only under full-send or kickoff. Leave the original PR open. Draft a closing comment that credits the author and links the replacement, and put it in the report for the user to post.

Report what you inherited, what you changed, how you verified it, how you kept the credit, and any decision left.
