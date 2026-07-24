# Browser use and web automation

Procedures for agent browser work on this machine. Read before driving a
browser or scraping/automating any website.

## Prefer HTTP over browser driving

Driving a browser (navigate/click/screenshot loops) is the most expensive way
to interact with a website. Escalate through these tiers and stop at the
first one that works:

1. **Official API or docs** — check for a public API first.
2. **Derived HTTP client (HAR trick)** — see below. One browser session to
   capture traffic, then plain `curl`/scripted requests forever after.
3. **Headless DOM via the harness's browser MCP** — extract data with page
   text or JS in the page instead of screenshot-reading it. On Claude that is
   `claude-in-chrome`'s `get_page_text` / `javascript_tool`.
4. **Full visual browser driving** — last resort, only for pages that
   genuinely need interaction/vision (canvas apps, anti-bot walls, visual
   verification). Follow `~/.agents/desktop-capture.md` rules for any
   screenshots (downscale before reading into context).

## The HAR trick (derive a client for any website)

When a site has no API but you'll need it more than once:

1. **Record**: perform the target flow (login, search, order, etc.) once in a
   browser while capturing network traffic:
   - DevTools MCP session: use CDP `Network.*` events, or
   - Manual: user does the flow with DevTools open → Network tab → right
     click → "Save all as HAR with content" → hand the file to the agent, or
   - Scripted: launch Chrome with `--remote-debugging-port` and dump
     requests via CDP.
2. **Store** the HAR under the project (e.g. `har/<site>-<flow>.har`).
   HARs contain cookies and auth tokens — **never commit them**; add
   `*.har` to `.gitignore`.
3. **Derive**: read the HAR and extract only what matters:
   - the handful of XHR/fetch endpoints for the flow (ignore assets,
     analytics, telemetry),
   - required headers (auth, csrf, user-agent, content-type),
   - cookie/session bootstrap,
   - request/response payload shapes.
4. **Build** a minimal client (script or small module) that replays the flow
   with plain HTTP. Parameterize secrets/tokens via env vars, not literals.
5. **Verify** the client against the live site once, then use it instead of
   the browser for all subsequent runs.

HAR files are huge — never read one whole into context. Filter first, e.g.:

```
jq '[.log.entries[] | select(.response.content.mimeType | test("json"))
     | {url: .request.url, method: .request.method, status: .response.status}]' file.har
```

Then pull full request/response bodies only for the specific entries needed.

## When browser driving is unavoidable

- Use the harness's browser MCP (navigate, page text, evaluate, screenshot);
  don't spawn ad-hoc browsers unless those tools can't reach the target.
- Prefer page text or `evaluate` (DOM queries, `fetch` from page context to
  reuse the session) over screenshots for reading state.
- If the browser MCP reports no extension or browser connected, say so and
  stop — don't fall back to scraping walled pages by other means.
- Screenshots are for visual verification only; downscale per
  `~/.agents/desktop-capture.md` before reading into context.
- Delegate long interactive click/type/verify sessions to a vision-capable
  sub-agent per the global CLAUDE.md rules; the orchestrator reads the
  report, not the pixels.

## Etiquette and safety

- Respect auth boundaries: only automate accounts/sessions the user owns and
  has explicitly provided.
- Keep request rates human-like; no scraping loops without the user asking.
- Treat captured tokens/cookies as secrets: keep them out of logs, commits,
  and model context beyond what's needed to build the client.
