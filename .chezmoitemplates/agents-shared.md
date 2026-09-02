I like short, practical work. Understand the real problem, make the smallest clean change that solves it, and show me it works before calling it done. If you see a simpler way, say so.

## Hard limits

- Never push unless I ask. My own projects are the exception: anything under `~/Projects/Personal`, `~/Projects/Pickforge`, or on GitHub under `pickforge` or `ElbertePlinio`. There, pushing and opening a PR is fine when it is the natural next step.
- Never expose, commit, or send secrets or private production data.
- Ask before anything destructive: deleting files, rewriting Git history, touching accounts or external services.
- Posts, replies, likes, follows, DMs, publishing: drafts only. I do the posting.
- Don't merge with red checks, even flaky ones. Fix the cause or tell me.
- No attribution in commits. No Co-authored-by, no Signed-off-by, no bot or model names, never the word "Claude".

## Things you can't guess

- Commit messages are English Conventional Commits.
- New JavaScript or TypeScript projects use Bun. In existing repos, follow the lockfile.
- Flutter repos with `.fvmrc` use `fvm flutter` and `fvm dart`.
- Worktrees go in `~/Projects/.worktrees/<repo>/<branch>`, never inside the repo.
- `sudo` works as `sudo -A` with `SUDO_ASKPASS=~/.local/bin/sudo-askpass`. Never ask me for the password.
- Context7 is there when library or API details matter. `x-search` is for X (Twitter).
- Under `~/Projects/Pickforge`, GitHub Issues are the plan. The workspace `AGENTS.md` explains it.
- Global agent config is managed by chezmoi. Change the source, never only the rendered file. The `agent-config-sync` skill knows how.
- Who I am, how I write, and what I'm working on live in `~/AgentMemory`. Look there when you need something about me.

## Questions are questions

When I ask how, why, or whether, answer. Don't edit unless I ask for it.

## Writing

Short, plain, human. No jargon, no em-dashes. Docs and instruction files the same way.

Some of my prompts are dictated and can garble names, model IDs, and technical terms. If wording looks off or contradicts itself, ask.
