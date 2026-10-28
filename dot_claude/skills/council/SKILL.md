---
name: council
description: Use when the user says "council", when kickoff or full-send meets a high-risk change, or for a design choice with lasting cost.
metadata:
  origin: Idea from t3dotgg/tstack council (MIT, Copyright (c) 2026 Theo Browne), rewritten for this setup.
---

Bring in three delegates from three providers, so different training finds different problems. A council costs about three reviews, so use it only when the user asks, for security, auth, permissions, money, migration, persistence, concurrency, or data-loss risk, or for a design choice with lasting cost. Members the user names take precedence.

Members. The OpenAI seat is the latest Sol at high effort; it finds the most bugs per cost. When Sol wrote the code, the OpenAI seat does not run, and the record says `not run`. Use Astra only when the user asks for it, because the user's ChatGPT Plus limit is small. The Anthropic seat is Fable 5.1 at high effort, or Opus 5.5 when Fable wrote the code or is unavailable. The third seat is Kimi K3.1 Pro from the opencode-go models at the high variant, the strongest third provider on independent indexes. Its opencode-go quota is small, so it reviews round one only. It returns in a later round only to recheck its own open blocker or should; otherwise its latest result stands. When it reports a usage limit or cannot run, use Gemini 4 Argon, then MiMo-V2.6-Pro, both from opencode-go. Do not seat Grok for code; it scores well below these on independent coding tests. Seat only providers that the repo's `AGENTS.md` allows, and record any other seat as `not allowed`. A model never reviews its own code.

Route. In T3 Code, resolve the IDs with `orchestrator_capabilities` and start the seats that run with `delegate_task` in parallel: role `review` or `design`, mode `async`, and the effort option the model advertises in `target.options`, such as `reasoningEffort`, `effort`, or `variant`. Outside T3, run Sol through the codex skill and the Anthropic seat as the native `final-reviewer-high` agent. The opencode-go seat needs T3, so outside T3 the council runs with two seats and records the missing one. If a seat that should run fails along with its fallbacks, ask the user with the question tool whether to continue with fewer seats, and name the failure, such as an expired key.

Brief. Give each delegate the request, the requirements, the exact diff or design, and the validation evidence. Do not give the author's rationale or another delegate's answer. Keep their work read-only, and tell them not to start subagents. For a code review, ask for findings with file, line, severity, and a failure scenario, plus a score out of 10. For a design question, ask for a recommendation with its trade-offs and the main risk.

Decide. Verify each finding through code or a focused test; a vote is not evidence. Fix what is valid with the smallest change. Fight scope creep: decline nits and out-of-scope ideas, and list them as follow-ups. After fixes, start a fresh round with the earlier findings and your answers. Stop when every seat approves or has only nits, or after three rounds, and report what stays disputed. For a product decision, ask the user with the question tool and put each seat's view in the options.

Record. When the work ends in a PR, edit its description and add this block at the end. Write `no score` where a delegate gave none, `not run` where a seat skipped the round, and never invent one. Record a fallback's scores under the model that gave them.

```markdown
Council review, <N> rounds:

| Delegate | Round 1 | Round 2 |
| --- | --- | --- |
| GPT-6.1 Sol | 7/10 | 9/10 |
```

Without a PR, put the same table in the final reply.
