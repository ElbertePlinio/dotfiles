---
name: x-search
description: Use to read X posts, threads, or Articles, or research practitioner reactions on X.
---

Use a live native X search tool when available. For one public post's text, try `curl -s "https://cdn.syndication.twimg.com/tweet-result?id=<ID>&token=a"`; an Article stub contains only a title and preview, not its body. Web search or an official mirror may suffice for indexed posts. Neither indexing nor unauthenticated retrieval is guaranteed.

For threads, reactions, Articles, or failed direct retrieval without a native tool, use Grok:

```sh
grok --prompt-file <scratchpad>/x-<topic>.md --model grok-4.6 --reasoning-effort high \
  --deny "Write(*)" --deny "Edit(*)" > <scratchpad>/x-<topic>-out.md 2>&1
```

`--prompt-file` is single-turn mode; do not add `-p`, which needs an inline prompt. Research can take minutes; run in the background and read the output file when ready. Deny writes and edits for research. Use `--json-schema` if structured output is needed.

Grok has no session context. Give it the question, relevant context, post URL and numeric status ID. Ask for verbatim quotes distinguished from summaries or reconstruction, account handles and source links, retrieval gaps, and disagreement or corrections. For Articles, ask for an official mirror when the body cannot be retrieved. Require its own knowledge to be separated from retrieved material.

Attribute claims to their sources and label uncertainty. Never present reconstructed text as a quote. Verify consequential quotes and reconstructed claims against a fetchable original or official mirror before relying on them, and name that source. If verification is unavailable, report the limit rather than filling the gap or treating reactions as established fact.
