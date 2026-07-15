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

## Adaptive model orchestration

- Each call may choose any enabled compatible non-Haiku model: no permanent roles; ratings are priors, aliases fallbacks.
- Choose by risk/irreversibility, modality/tool fit, uncertainty/context complexity, validation strength, live quota, and observed quality; reset model and effort each call.
- Start each selected model at its documented/configured effort prior for that call (including Grok 4.5 at high, cost 3); a prior is a baseline, not an evidence escalation.
- Raise above that prior only for concrete failed validation or unresolved evidence. Xhigh only if high remains unresolved/contradictory, a no-rollback critical decision has weak validation, or the user asks.
- Elevated effort answers only its trigger; the next call reselects the model and starts from its prior. No self-upgrade: explicitly dispatch a provider/model/effort second opinion or escalation call.

## Dictated prompts (PickScribe)

Dictation can corrupt names, model IDs, and technical terms. Confirm suspicious or contradictory wording instead of following it literally.

## Tool and workflow triggers

- Use Context7 when library/API details matter and it is available.
- At the start of deeper repo work, check whether CodeGraph is available. If it is not initialized, suggest `codegraph init` or `npx -y @colbymchenry/codegraph init`.
- Prefer `frun` for noisy shell commands when available. It uses RTK when available and falls back to the raw command.
- RTK (`rtk`) is a token-optimizing CLI proxy. If `frun` is unavailable but `rtk` exists, prefix noisy read-only commands with `rtk` (e.g. `rtk git status`, `rtk git diff`).
- Use `rtk` directly for RTK meta commands like `rtk gain`, `rtk gain --history`, or `rtk discover`.
- Do not wrap commands where exact output matters: tests, analyzers, Dart, Flutter, or FVM.
- When `sudo` needs authentication in a non-interactive tool session, use `sudo -A` with `SUDO_ASKPASS=~/.local/bin/sudo-askpass` so the user can approve through a graphical password dialog.
- Never request, capture, pipe, print, or store the sudo password. If graphical askpass is unavailable or the user cancels, stop and ask them to run the command manually.
- For X (Twitter) research — model reputations, AI tooling chatter, practitioner sentiment — use the `x-research` skill when available; otherwise run its Hermes Agent CLI workflow directly. If Hermes is unavailable, say so.
- If a required subagent or model lane fails because its session expired or authentication needs refreshing, try the provider's normal interactive login flow through the available browser or PickLab session. For Claude, ChatGPT, and Ollama, use Google sign-in with the user's `elberte.dev@gmail.com` account when the existing browser session makes that account available. For Grok, use Microsoft sign-in with `eoberte@outlook.com` when that existing browser account is available. Never request, type, expose, or store passwords, recovery codes, 2FA codes, cookies, or tokens. If re-authentication cannot be completed without the user's direct interaction, stop and prompt them instead of substituting silently.

## UI and UX

- For work that creates or materially changes user-facing UI or UX, use the `design-director` skill before implementation. If the repo has a more specific design skill, use it as an overlay on the general workflow.
- Tiny fixes already determined by the repo's existing tokens or components can use the skill's light path.

## Grok routing

- Whenever Grok 4.5 is used for any task—implementation, research, review, vision, or verification—run it at `high` effort. Never invoke Grok 4.5 at `medium` or `low`.
- Select Grok from the current model table only when it best fits the call; every Grok 4.5 call still uses `high` effort.
- The weekly pool is finite. Check PickGauge before non-review multi-agent waves and select from live headroom.

## Model effort and fallback rules

- Whenever Opus 4.8 is used in a multi-model workflow or orchestration call, run it at `xhigh` effort. Never invoke Opus 4.8 at a lower effort.
- If a selected model is unavailable or incompatible, reselect the closest compatible candidate from the current model table and report the substitution. Stop when the user required that exact model or no candidate fits.
- Preserve tool and modality compatibility; GLM-5.2 remains text-only.

## Usage-aware orchestration

- Prefer direct work for routine tasks. Delegate only when an independent context, isolated writer, or different model capability materially improves correctness or latency.
- Default to one active issue or PR slice at a time. Broad roadmap requests proceed slice by slice unless the user explicitly prioritizes parallel throughput and the relevant pools have headroom.
- Before every multi-agent wave, check PickGauge once. Static cost ratings never override live quota headroom.
- Reuse or resume the original builder for fixes. Do not create a fresh agent for each verification step, and do not repeat a whole review panel after fixes.
- Select the model and effort independently for every call from the current table, task requirements, validation surface, and live headroom. Never bind a model to a task class, role, or lane.
- Keep one accountable owner for taste-heavy work; provider identity does not define ownership.

## Model restrictions

- Never use Anthropic Haiku, directly or indirectly through a tool, skill, search provider, subagent, fallback, or hidden/default route. Choose a non-Haiku route instead. If a tool unexpectedly reports Haiku, stop using that route and report it.
- Never use GPT-5.6 Luna. Use GPT-5.6 Terra or Sol instead.

## Provider-diverse review

- For shipping review, `$local-review` owns profiles and review counts. Select each reviewer independently from the current model table for the concrete failure mode; do not assign review roles to fixed models.

## Personal project isolation

- When `~/Projects/Personal/.agent-safety` exists, access defaults to `~/Projects/Personal` and descendants. Outside access requires the exact path and action in the request.
- Do not follow symlinks outside it or reuse company context, credentials, caches, or config.
- Before Personal GitHub mutations or pushes, run `~/Projects/Personal/.agent-safety/verify-personal-github` to verify `ElbertePlinio`. Stop on failure; never switch accounts.
- `claude-work` is company-only and forbidden there; use only a user-approved personal profile.

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
- Do not merge with failing required checks, unanswered valid findings, or an incomplete review required by the change's risk class.
