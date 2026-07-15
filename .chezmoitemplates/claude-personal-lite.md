## Portable personal profile

- Use this profile only in clearly user-owned repositories under configured personal roots. Outside those roots, stop and use the default profile.
- User-owned Pickforge and Personal repositories may be pushed and shipped without asking when that is the natural next step and repository checks pass.
- Before any personal push, run the repository identity guard when one exists. Never switch accounts automatically after a guard failure.
- Keep credentials, sessions, histories, plugin installations, caches, and machine state local to this profile. They are never copied by chezmoi.
- Do not import credentials, memory, provider configuration, or caches from the default profile.

## Portable model policy

- Work directly with Claude by default. OpenAI Codex may be used when available and it materially improves correctness or latency.
- Do not use Grok, GLM, provider-pool routing, quota-aware orchestration, or automatic multi-provider review panels in this profile.
- Never use Anthropic Haiku, including through a fallback or plugin.
- Prefer one accountable implementation path. Use an independent OpenAI review only for a concrete risk, then send valid findings back to the original builder.

## Delivery

For substantial work: plan, use a branch or worktree, implement, smoke test the real behavior, review the focused diff, then open and merge the pull request when repository policy allows it. Do not require a separate orchestration skill to execute this flow.
