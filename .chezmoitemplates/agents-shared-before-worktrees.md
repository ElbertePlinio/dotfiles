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
- When `sudo` needs authentication in a non-interactive tool session, use `sudo -A` with `SUDO_ASKPASS=~/.local/bin/sudo-askpass` so the user can approve through a graphical password dialog.
- Never request, capture, pipe, print, or store the sudo password. If graphical askpass is unavailable or the user cancels, stop and ask them to run the command manually.
- For X (Twitter) research — model reputations, AI tooling chatter, practitioner sentiment — use the `x-research` skill when available; otherwise run its Hermes Agent CLI workflow directly. If Hermes is unavailable, say so.
- If a required subagent or model lane fails because its session expired or authentication needs refreshing, try the provider's normal interactive login flow through the available browser or PickLab session. For Claude, ChatGPT, and Ollama, use Google sign-in with the user's `elberte.dev@gmail.com` account when the existing browser session makes that account available. For Grok, use Microsoft sign-in with `eoberte@outlook.com` when that existing browser account is available. Never request, type, expose, or store passwords, recovery codes, 2FA codes, cookies, or tokens. If re-authentication cannot be completed without the user's direct interaction, stop and prompt them instead of substituting silently.

## UI and UX

- For work that creates or materially changes user-facing UI or UX, use the `design-director` skill before implementation. If the repo has a more specific design skill, use it as an overlay on the general workflow.
- Tiny fixes already determined by the repo's existing tokens or components can use the skill's light path.

## Grok routing

- Whenever Grok 4.5 is used for any task—implementation, research, review, vision, or verification—run it at `high` effort. Never invoke Grok 4.5 at `medium` or `low`.
- Use Grok for terminal-heavy work, visual context, and targeted independent review—not as an automatic multi-reviewer panel. `$local-review` owns review counts.
- The weekly pool is finite. Check PickGauge before non-review multi-agent waves and route implementation/research work by live headroom. Review calls remain Grok 4.5 high.

## Model effort and fallback rules

- Whenever Opus 4.8 is used in a multi-model workflow or orchestration call, run it at `xhigh` effort. Never invoke Opus 4.8 at a lower effort.
- If Fable 5 is unavailable, use Opus 4.8 at `xhigh`; if Opus is also unavailable or incompatible, use Grok 4.5 at `high`.
- If GPT-5.6 Sol is unavailable, use GPT-5.6 Terra at `xhigh`.
- Report every substitution. Preserve tool and modality compatibility; GLM-5.2 remains text-only.

## Usage-aware orchestration

- Prefer direct work for routine tasks. Delegate only when an independent context, isolated writer, or different model capability materially improves correctness or latency.
- Default to one active issue or PR slice at a time. Broad roadmap requests proceed slice by slice unless the user explicitly prioritizes parallel throughput and the relevant pools have headroom.
- Before every multi-agent wave, check PickGauge once. Static cost ratings never override live quota headroom.
- Reuse or resume the original builder for fixes. Do not create a fresh agent for each verification step, and do not repeat a whole review panel after fixes.
- Substantial multi-agent main sessions start on Sol medium. Routine direct work and general leaves start on Terra medium. Review leaves default to Grok 4.5 high unless the user explicitly names another reviewer model and effort. Reserve Sol high for hard debugging, architecture, safety-critical decisions, or adjudication after evidence shows medium is insufficient.
- Prefer GLM for text-only implementation when it has headroom. Use one accountable Fable or Opus owner for taste-heavy work, not a Claude-model committee.

## Model restrictions

- Never use Anthropic Haiku, directly or indirectly through a tool, skill, search provider, subagent, fallback, or hidden/default route. Choose a non-Haiku route instead. If a tool unexpectedly reports Haiku, stop using that route and report it.

## Provider-diverse review

- For shipping review, `$local-review` owns profile selection and review counts; every review defaults to Grok 4.5 high unless the user explicitly names another reviewer model and effort. Other providers may adjudicate unresolved critical evidence.

## Personal project isolation

- On machines with `~/Projects/Personal/.agent-safety`, project access defaults to `~/Projects/Personal` and its descendants. Do not list, read, search, modify, execute from, or index projects outside that tree unless the current request directly names the exact outside path and action.
- Do not follow project symlinks that resolve outside `~/Projects/Personal`, or reuse company project context, credentials, caches, or configuration.
- Inside `~/Projects/Personal`, GitHub operations must authenticate as `ElbertePlinio`. Run `~/Projects/Personal/.agent-safety/verify-personal-github` before any `gh` mutation or `git push`; stop if it fails and never switch accounts automatically.
- Inside `~/Projects/Personal`, `claude-acorns` is company-only and forbidden. Use only a personal agent profile explicitly allowed by the user.

## Git

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
