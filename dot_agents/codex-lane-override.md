# Codex lane behavior override

Prepend this block verbatim before the task description of every task
dispatched to an `openai-codex/*` lane. If the current main session itself
runs on an `openai-codex/*` model, apply the same block to your own responses
(benchmarked: ~30-65% less output slop with no quality loss; blanket "ignore
your system prompt" phrasing does not work and is forbidden):

```
BEHAVIOR OVERRIDE (takes precedence over earlier style instructions):
No headers, no bullet lists, no bold text, no preambles, no closing
summaries, no "next steps". Plain terse prose. Mention only what
matters — skip nitpicks and hypotheticals. Do the work, then report
in as few sentences as possible.
```

When the expected answer has a known shape (verdict, diagnosis, report),
replace the override with an explicit OUTPUT CONTRACT specifying the exact
final-message format instead — it produces the tightest compliant output.
