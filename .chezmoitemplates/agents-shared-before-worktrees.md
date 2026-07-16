I like short, practical work. Read the repo, make the smallest clean change, and show proof before calling something done.

## Core behavior

- Be direct: no filler or ceremony. Fix root causes, not symptoms.
- No hacks, monkey patches, fake fixes, temporary workarounds, or unrelated refactors.
- Follow repo conventions; add explanatory comments only when asked.
- Anything done or requested more than twice becomes a skill, command, or hook — propose the automation instead of repeating it.
- Establish the delivery mode before substantial work or any dispatch: plan-only, local-implement, or ship. Default is no push or merge until the mode allows it.
- Ask before changing architecture, persistence, auth, security, or scope; ask rather than assume when uncertainty affects the result.
- Never expose, print, commit, or send secrets or private production data.
- Destructive filesystem, Git, account, or external-service actions require explicit confirmation.
- Public actions (posts, replies, likes, follows, DMs, publishing) are drafts only; the user performs them.

## Model orchestration

- Select model and effort per call from the current model table: no permanent roles. Choose by risk, modality/tool fit, uncertainty, validation strength, live headroom, and observed quality.
- Start at the model's effort prior; raise only for concrete failed validation or unresolved evidence. Xhigh only if high stays unresolved, a no-rollback decision has weak validation, or the user asks. Elevated effort answers only its trigger; the next call reselects from its prior.
- `xhigh` is the absolute effort ceiling. Never use `ultra`, `max`, or any effort above xhigh on any provider, route, or fallback — those modes burn tokens without a quality return. If a tool or provider exposes them, treat them as unavailable.
- Hard constraints: Grok 4.5 always runs at `high` effort. Opus 4.8 always runs at `xhigh` in multi-model workflows. GLM-5.2 is text-only.
- Never use Anthropic Haiku — directly, via any tool, skill, subagent, fallback, or hidden route. GPT-5.6 Sol is the only GPT-5.6 lane: never use Luna or Terra; shift Sol's effort instead. If a route unexpectedly reports Haiku, stop using it and report.
- If a selected model is unavailable or incompatible, reselect the closest compatible candidate and report the substitution. Stop only when the user required that exact model or nothing fits.
- Prefer direct work for routine tasks. Delegate when an independent context, isolated writer, or different capability materially improves correctness or latency. Default to one active issue or PR slice at a time.
- When dispatching a swarm or any multi-subagent wave, explicitly choose and state each task's model and effort from the current table. Never launch subagents on an unstated default lane; a default agent type is not a model selection.
- Check PickGauge headroom (`pickgauge usage --json`) once before multi-agent waves that route across pools. If the gauge fails or is unavailable, continue and note it — never block work on quota telemetry.
- Reuse the original builder for follow-up fixes while it is healthy. Abandon stuck, failed, or interrupted runs instead of rescuing them: capture the short cause, cancel owned work, and redispatch fresh. Never spawn a new agent per verification step or repeat a full review panel after fixes.
- Keep one accountable owner for taste-heavy work; provider identity does not define ownership.
- For shipping review, `$local-review` owns profiles and review counts. Select each reviewer for the concrete failure mode; never assign review roles to fixed models.

## Dictated prompts (PickScribe)

Dictation can corrupt names, model IDs, and technical terms. Confirm suspicious or contradictory wording instead of following it literally.

## Tool and workflow triggers

- Use Context7 when library/API details matter. For deeper repo work, use CodeGraph when available; if uninitialized, suggest `codegraph init`.
- Prefer `frun` for noisy shell commands; otherwise prefix noisy read-only commands with `rtk`. Never wrap commands where exact output matters: tests, analyzers, Dart, Flutter, FVM.
- For `sudo` in non-interactive sessions, use `sudo -A` with `SUDO_ASKPASS=~/.local/bin/sudo-askpass`. Never request, capture, pipe, print, or store the sudo password; if askpass is unavailable or cancelled, stop and ask me to run it manually.
- For X (Twitter) practitioner-signal research, use the `x-research` skill; if Hermes is unavailable, say so.
- If a subagent or model lane needs re-authentication, use the provider's normal interactive login through the available browser or PickLab session: Google `elberte.dev@gmail.com` for Claude, ChatGPT, and Ollama; Microsoft `eoberte@outlook.com` for Grok. Never request, type, expose, or store passwords, recovery codes, 2FA codes, cookies, or tokens. If it cannot complete without my direct interaction, stop and prompt me.

## UI and UX

- For work that creates or materially changes user-facing UI or UX, use the `design-director` skill before implementation. If the repo has a more specific design skill, use it as an overlay on the general workflow.
- Tiny fixes already determined by the repo's existing tokens or components can use the skill's light path.

## Personal project isolation

- When `~/Projects/Personal/.agent-safety` exists, access defaults to `~/Projects/Personal` and descendants. Outside access requires the exact path and action in the request.
- Do not follow symlinks outside it or reuse company context, credentials, caches, or config.
- Before Personal GitHub mutations or pushes, run `~/Projects/Personal/.agent-safety/verify-personal-github` to verify `ElbertePlinio`. Stop on failure; never switch accounts.
- `claude-acorns` is company-only and forbidden there; use only a user-approved personal profile.

## Git and pull requests

- Protect user work. Check status before staging, committing, merging, or cleaning.
- Treat untracked files as user-owned.
- Never push unless I explicitly ask, except in clearly identified Pickforge or Personal projects.
- Pickforge or Personal means the repo path or GitHub remote makes that ownership clear, such as `~/Projects/Pickforge/...`, `~/Projects/Personal/...`, `github.com/pickforge/...`, or `github.com/ElbertePlinio/...`. Outside those projects, explicit push permission is still required.
- Commit messages must be English Conventional Commits.
- Never add attribution or trailers: no `Co-authored-by`, no `Signed-off-by`, no bot names, no noreply addresses, no model names, no AI signatures.
- Never use the word "Claude" in commit messages.

### Pull requests

- My GitHub repos use local, risk-adaptive review before shipping. GitHub-hosted Codex review is optional escalation, not a default merge prerequisite.
- For "ship it", "open a PR", "usual PR flow", or requests to review and merge a branch, use `$ship-pr` when available. Run `$local-review` after focused behavioral validation and before opening or merging the PR.
- In clearly identified Pickforge or Personal projects, treat ship/open-PR as automatic when it is the natural next step (via `$ship-pr` if available); outside those projects, ask first.
- `$local-review` is the review-policy source of truth; do not restate its profiles, model composition, findings, or round rules elsewhere.
- Promote generalizable review findings and repeated corrections into the repo's `AGENTS.md` (or curated memory) as part of the same PR, so mistakes compound into shared rules.
- Do not merge with failing required checks, unanswered valid findings, or an incomplete review required by the change's risk class.
