---
name: x-search
description: Search X (Twitter) for practitioner signal — model and tool reputations, launch and benchmark chatter, library sentiment, "what actually breaks in production" reports — and to read specific posts, threads, or X Articles that normal web fetching cannot reach. Use when a question needs what people say rather than what docs state, or when an x.com URL must be read.
---

# X search

x.com returns `402` to unauthenticated fetchers and X Articles are not indexed by
web search. Grok has native X access; route X work through it.

## Native first

If the current harness already has a live X search tool, call it directly. The
CLI path below is for harnesses without one.

## Grok CLI

```sh
grok --prompt-file <scratchpad>/x-<topic>.md --reasoning-effort high \
  --deny "Write(*)" --deny "Edit(*)" > <scratchpad>/x-<topic>-out.md 2>&1
```

- `--prompt-file <path>` takes the prompt; `-p` is `--single <PROMPT>` and requires
  an inline value, so `-p --prompt-file …` fails.
- Grok 4.5 runs at `high` effort.
- Run it in the background and read the output file — a research loop takes minutes.
- Deny `Write`/`Edit` for research; add `--json-schema` when a caller needs structure.

## Writing the prompt

Grok gets no session context, so restate everything it needs.

- Give the post URL **and** the numeric status ID — the ID survives when URL
  resolution fails.
- Require verbatim text in blockquotes, and require reconstructed or summarized
  passages to be labeled as such.
- Ask explicitly what it could **not** retrieve, and to say so plainly instead of
  filling the gap. Ask it to separate its own knowledge from the source.
- For an X Article, ask it to look for an official mirror — company blogs,
  crossposts. Mirrors are fetchable when the Article is not.
- Require account handles in reaction summaries so claims stay checkable.
- Ask for disagreement and correction, not just the supportive replies.

## Verify what you build on

Grok routes around the wall via mirrors, quote-posts, and other people's
summaries. Confirm load-bearing quotes against a fetchable source before acting
on them, and say which source you confirmed against.

## Cheaper paths worth trying first

- One post's text, no thread — no auth needed:
  `curl -s "https://cdn.syndication.twimg.com/tweet-result?id=<ID>&token=a"`
  returns JSON with `text`, `created_at`, `entities.urls`, and an `article` stub
  (title and preview only, not the body).
- Web search reaches posts older than roughly a day; same-day posts are not indexed.
