---
name: sol-loop
description: Use when the user says "sol loop", or when full-send, full-stop, kickoff, or takeover needs its review step.
metadata:
  origin: Idea from t3dotgg/tstack sol-loop (MIT, Copyright (c) 2026 Theo Browne), rewritten for this setup.
---

You own the change, and Sol reviews it in a loop until you both agree or the budget ends. Fix what is right and push back on what is wrong. Keep the smallest change that meets the intent. Review makes a change correct, not bigger.

Reviewer. Sol is the default reviewer. It scores within a point of Astra on independent tests at about a sixth of the cost, and the user's ChatGPT Plus limit is small. Use Astra only when the user asks for it. If Sol wrote the code, Fable reviews in its place through the native `final-reviewer-high` agent, or Opus when Fable is unavailable, because a model never reviews its own code. Use high effort, because this review is the main bug gate before an unattended merge. Use xhigh when the change touches security, auth, permissions, money, migrations, persistence, concurrency, or data loss.

Route. Send each round to the chosen reviewer. A Fable or Opus reviewer runs as a native subagent with the same brief. For an OpenAI reviewer in T3 Code, resolve its latest model through `orchestrator_capabilities`. Start every round with `delegate_task`: role `review`, mode `async`, the Codex provider, and `reasoningEffort` in `target.options`. Use a new `clientRequestId` per round and keep each `taskId`. The `childThreadId` is storage, never the target of the next round. Outside T3, commit the change's paths first, because codex-run reviews a commit and never sees uncommitted or untracked work. Then run `codex-run review --repo <repo> --model sol --effort <high|xhigh> --rev <sha>` through the codex skill in the background, and send later rounds with `--resume`. A local commit is not a push. If no route runs the reviewer, report the blocker. Never substitute another model without saying so.

Budget. Run three rounds at most. Round one reviews the whole change; later rounds check only changed code and open findings. Allow five rounds only for the risk areas above, while a blocker or should stays open with evidence. Stop early when a round returns only nits. Run one reviewer at a time.

Scope. Run `git status --short` first. Never stash, discard, or include unrelated changes. Fetch, then take the base from `git merge-base HEAD origin/<base>`. The change runs from the base to the working tree and includes untracked files. Use the same diff command in every round. Run the covering checks before round one and put their results in the brief. Do not edit scoped files while a round runs. A timeout, an error, or no reply is not approval.

Brief. A delegated child has no history, so every brief stands alone:

```
Review only. Do not edit, commit, push, comment, or start subagents.
Repo: <path>  Base: <sha>  Intent: <one or two sentences>  Out of scope: <items>
Checks: <commands and results>
Diff: git diff <base> [<sha>] [-- <paths>], plus untracked files from git status --short.
Read callers and surrounding code. Find bugs, broken callers, and gaps against the intent.
Ignore style unless it hides a bug. Flag code, tests, or guards the intent does not need.
blocker: the intended case is wrong, or any path can lose data, money, or access.
should: a real bug callers hit within the intent.
nit: everything else, such as rare low-impact paths, small costs, or extra compatibility.
Reply with VERDICT: APPROVE or CHANGES, then one line per finding:
S1 [blocker|should|nit] <file>:<line> <claim> Fix: <suggestion>
Keep ids stable across rounds.
```

Answers. Check every finding and its severity yourself, and judge severity by consequence. A rare path with small impact is a nit whatever its label. A rare path that can lose data, money, or access is not a nit. When you agree, make the smallest fix. Prefer deleting or narrowing code over a new lock, cache, helper, or option. Add one focused test that fails without the fix when the intent needs it. When you disagree, give evidence: file and line, a test, or output. Decline nits and out-of-scope items in one line and list them as follow-ups. Keep a ledger of id, severity, and outcome. After fixes, rerun the checks and `git diff --shortstat <base>`. If review grew the diff, cut it back. Never agree only to end the loop.

Next round. Start one only while budget remains and a blocker or should is open, or behavior code changed after an approval. Send the round-one brief again with the ledger (fixed, disputed, declined, with evidence), the same base diff, and the change since the last round. Ask the reviewer to check only open ids and changed code, and to mark each old id resolved or still open with a reason.

Stop. Agreement is APPROVE on the current behavior diff, with no open blocker or should and no concern of your own. When an item stays disputed after two replies, or the budget ends, write both sides in two or three lines each. Under full-send or kickoff, settle it yourself when the evidence is clear, and ask the user only when the answer changes the product. The end of the budget is not approval.

Do not push during the loop. When you file or update the PR in a project where your global instructions allow model names, add this line to the description with the true verdict: `Reviewed with sol-loop: <N> rounds with <model>. Sol verdict: <approved | not approved, see below>`. Report the rounds, the model, what review changed, the diff size before and after, the fixed and declined findings with reasons, and whether you pushed.
