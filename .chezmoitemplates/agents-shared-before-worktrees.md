I like short, practical work. Read the repo, make the smallest clean change, and show proof before calling something done.

## Core behavior

- Be direct: no filler or ceremony. Fix root causes, not symptoms.
- No hacks, monkey patches, fake fixes, temporary workarounds, or unrelated refactors.
- Follow repo conventions; add explanatory comments only when asked.
- Ask before changing architecture, persistence, auth, security, or scope; ask rather than assume when uncertainty affects the result.
- Never expose, print, commit, or send secrets or private production data.
- Destructive filesystem, Git, account, or external-service actions require explicit confirmation.
- Public actions (posts, replies, likes, follows, DMs, publishing) are drafts only; the user performs them.
- Never use Anthropic Haiku, directly, indirectly, or as a fallback.

## Dictated prompts (PickScribe)

Dictation can corrupt names, model IDs, and technical terms. Confirm suspicious or contradictory wording instead of following it literally.

## Tool and workflow triggers

- Use `context7-mcp` or native Context7 when current library/API docs matter.
- In repos with `.codegraph/`, use native CodeGraph before text search or file reads for code discovery; otherwise skip it.
- Prefer `frun` for noisy commands, or `rtk` for noisy read-only/meta commands. Never wrap tests, analyzers, Dart, Flutter, FVM, or exact-output commands.
- Use `x-research` for X/Twitter signal; otherwise use its Hermes workflow or report Hermes unavailable.
- Use `design-director` for material UI/UX work, plus any repo-specific design skill. Tiny token/component-determined fixes may use its light path.

## Personal project isolation

- When `~/Projects/Personal/.agent-safety` exists, access defaults to `~/Projects/Personal` and descendants. Outside access requires the exact path and action in the request.
- Do not follow symlinks outside it or reuse company context, credentials, caches, or config.
- Before Personal GitHub mutations or pushes, run `~/Projects/Personal/.agent-safety/verify-personal-github` to verify `ElbertePlinio`. Stop on failure; never switch accounts.
- `claude-work` is company-only and forbidden there; use only a user-approved personal profile.

## Git and pull requests

- Protect user work: check status before staging, committing, merging, or cleaning; untracked files are user-owned.
- Push only when asked, except in clearly identified Pickforge or Personal repos (path or `pickforge`/`ElbertePlinio` remote). Elsewhere explicit permission remains required.
- Use English Conventional Commits. No attribution, trailers, bot/noreply/model names, AI signatures, or `Claude`.
- For ship/open-PR/review-and-merge requests, use `ship-pr` where available; otherwise perform its focused validation, local review, PR, CI, and finding loop.
- Pickforge and Personal repos may open/ship a PR when it is the natural next step; elsewhere ask first.
- `$local-review` is the shipping review source. GitHub-hosted Codex review is optional escalation, not a default prerequisite; triage any findings.
- Never merge with failing or in-flight required checks, unanswered valid findings, or an unreviewed current HEAD.
