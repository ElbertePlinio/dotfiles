I like short, practical work. Read the repo, make the smallest clean change, and show proof before calling something done.

## How to work

- Be direct. No filler, no ceremony.
- Fix root causes, not symptoms.
- No hacks, monkey patches, fake fixes, or "temporary" workarounds.
- Follow the repo's style before my preferences.
- Do not refactor unrelated code.
- Never add comments explaining what the code does unless explicitly asked.
- When suggesting fixes, show only the relevant changed code, not the entire file.
- If a choice changes architecture, persistence, auth, security, or scope, ask first.
- If unsure, ask — don't assume.

## Dictated prompts (PickScribe)

I often dictate prompts with PickScribe. Words can come out wrong — especially names, model IDs, and technical terms. If a request hinges on a word that looks off or contradicts what you know, ask me to confirm what I meant instead of running with the literal transcription.

## Tools

- Use Context7 when library/API details matter and it is available.
- At the start of deeper repo work, check whether CodeGraph is available. If it is not initialized, suggest `codegraph init` or `npx -y @colbymchenry/codegraph init`.
- Prefer `frun` for noisy shell commands when available. It uses RTK when available and falls back to the raw command.
- RTK (`rtk`) is a token-optimizing CLI proxy. If `frun` is unavailable but `rtk` exists, prefix noisy read-only commands with `rtk` (e.g. `rtk git status`, `rtk git diff`).
- Use `rtk` directly for RTK meta commands like `rtk gain`, `rtk gain --history`, or `rtk discover`.
- Do not wrap commands where exact output matters: tests, analyzers, Dart, Flutter, or FVM.
- For X (Twitter) research — model reputations, AI tooling chatter, practitioner sentiment — use the `x-research` skill when available; otherwise run its Hermes Agent CLI workflow directly. If Hermes is unavailable, say so.

## UI and UX

- For work that creates or materially changes user-facing UI or UX, use the `design-director` skill before implementation. If the repo has a more specific design skill, use it as an overlay on the general workflow.
- Tiny fixes already determined by the repo's existing tokens or components can use the skill's light path.

## Git

- Protect user work. Check status before staging, committing, merging, or cleaning.
- Treat untracked files as user-owned.
- Never push unless I explicitly ask, except in clearly identified Pickforge or Personal projects.
- Pickforge or Personal means the repo path or GitHub remote makes that ownership clear, such as `~/Projects/Pickforge/...`, `~/Projects/Personal/...`, `github.com/pickforge/...`, or `github.com/ElbertePlinio/...`. Outside those projects, explicit push permission is still required.
- Commit messages must be English Conventional Commits.
- Never add attribution or trailers: no `Co-authored-by`, no `Signed-off-by`, no bot names, no noreply addresses, no model names, no AI signatures.
- Never use the word "Claude" in commit messages.

### Pull requests

- My GitHub repos use an automated Codex PR review (`chatgpt-codex-connector[bot]`).
- For "ship it", "open a PR", "usual PR flow", or requests to review and merge a branch, use `$ship-pr` when that skill is available; otherwise open/update the PR yourself and run the same Codex review loop manually.
- In clearly identified Pickforge or Personal projects, treat ship/open-PR as automatic when it is the natural next step (via `$ship-pr` if available); outside those projects, ask first.
- Triage every review finding: fix valid findings; reply briefly with rationale for false positives.
- React on each Codex finding as model feedback: 👍 when it is correct and useful; 👎 when it is incorrect or not useful. React on the finding itself, not the `@codex review` trigger; reactions do not replace replies or fixes.
- Let the automatic review on PR open run first; use `@codex review` only after fixes or when the opening trigger fails.
- Normally cap review at 3 distinct HEADs. Use round 4 only to verify a fix for a new valid P1/P2 found in round 3. Do not run a fifth round.
- Do not merge with a review round in flight, failing required checks, unanswered findings, or a HEAD that Codex has not reviewed.
