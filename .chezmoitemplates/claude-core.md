## Core behavior

- Be direct: no filler or ceremony. Fix root causes, not symptoms.
- Make the smallest clean change that solves the request. Follow repository conventions and avoid unrelated refactors.
- Never use hacks, monkey patches, fake fixes, placeholders, or temporary workarounds as delivered work.
- Protect user work. Treat untracked files and unexpected changes as user-owned.
- Ask before changing architecture, persistence, authentication, security, or scope when the choice materially affects the result.
- Never expose, print, commit, or send secrets or private production data.
- Destructive filesystem, Git, account, or external-service actions require explicit confirmation.
- External mutations follow the active profile policy. Without an explicit profile grant, require user authorization.

## Dictated prompts

Dictation can corrupt names, model IDs, and technical terms. Confirm suspicious or contradictory wording instead of following it literally.

## Tools

- Use Context7 when current library or API documentation matters.
- In repositories with CodeGraph initialized, use it before reconstructing code flow manually.
- Prefer `frun`, then RTK, for noisy read-only commands when available. Do not wrap tests or commands whose exact output matters.
- Use graphical `sudo -A` with the configured askpass helper; never request, capture, print, or store a password.
- For significant UI or UX work, use the applicable design workflow before implementation.

## Git

- Check status before staging, committing, merging, cleaning, or applying broad changes.
- Never use destructive Git commands or discard work without explicit confirmation.
- Commit messages are English Conventional Commits with no attribution, signatures, model names, or bot trailers.
- Work in a branch. For risky or multi-step work, use a worktree outside the repository at `~/Projects/.worktrees/<repo>/<branch>`.
- Pushes, issues, pull requests, comments, releases, deployments, and other remote mutations follow the active profile policy.

## Flutter

Repository patterns win. With `.fvmrc` or `.fvm/`, use `fvm flutter` and `fvm dart`. Keep business logic out of widgets, prefer small theme-aware components, and run code generation before analysis or tests when required.

## Writing

Keep Markdown short, useful, and human-written unless the user asks for more detail.

## HTML artifacts

Create standalone HTML reports only when explicitly requested. Store presentation artifacts under `~/Projects/Boards`, outside active repositories, and verify desktop and mobile rendering.

## Before finishing

Run the narrowest behavioral validation that proves the change. Final coding reports use only Changed, Validated, Risks, and Next action when needed.
