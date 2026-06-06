<!-- context7 -->
Use Context7 MCP to fetch current documentation whenever the user asks about a library, framework, SDK, API, CLI tool, or cloud service -- even well-known ones like React, Next.js, Prisma, Express, Tailwind, Django, or Spring Boot. This includes API syntax, configuration, version migration, library-specific debugging, setup instructions, and CLI tool usage. Use even when you think you know the answer -- your training data may not reflect recent changes. Prefer this over web search for library docs.

Do not use for: refactoring, writing scripts from scratch, debugging business logic, code review, or general programming concepts.

## Steps

1. Always start with `resolve-library-id` using the library name and the user's question, unless the user provides an exact library ID in `/org/project` format
2. Pick the best match (ID format: `/org/project`) by: exact name match, description relevance, code snippet count, source reputation (High/Medium preferred), and benchmark score (higher is better). If results don't look right, try alternate names or queries (e.g., "next.js" not "nextjs", or rephrase the question). Use version-specific IDs when the user mentions a version
3. `query-docs` with the selected library ID and the user's full question (not single words)
4. Answer using the fetched docs
<!-- context7 -->


<claude-mem-context>
# Memory Context

# [dev] recent context, 2026-06-04 8:42am GMT-3

Legend: 🎯session 🔴bugfix 🟣feature 🔄refactor ✅change 🔵discovery ⚖️decision 🚨security_alert 🔐security_note
Format: ID TIME TYPE TITLE
Fetch details: get_observations([IDs]) | Search: mem-search skill

Stats: 0 obs (0t read) | 0t work

### Apr 19, 2026
S21 Dotfiles Repo History Reset and Force-Push to GitHub (Apr 19, 7:49 PM)
S32 Dotfiles Repo Pushed to GitHub — 7-Commit History Complete (Apr 19, 7:50 PM)
S33 Recommendation for encrypting sensitive AI tool credentials (Context7, Codex, etc.) in chezmoi dotfiles repo (Apr 19, 7:56 PM)
S43 User asked "How you know this?" — questioning how Claude diagnosed backup script status from process table (Apr 19, 7:57 PM)
S44 Dotfiles Chezmoi Session Completed — Repo Fully Synced (Apr 19, 8:09 PM)
S45 Chezmoi dotfiles restore procedure for a new/fresh PC (Apr 19, 8:09 PM)
S48 Backup Bundle Completeness Verification — User asked if the 2026-04-19 backup bundle is correct and complete (Apr 19, 8:11 PM)
S49 sudo -S Option — Read Password from stdin (Apr 19, 8:18 PM)
S50 CachyOS Home Backup Integrity Verified (Apr 19, 8:19 PM)
### Jun 2, 2026
S873 Execute codex-claude usage tray implementation plan end-to-end in a new repository-root worktree under .worktrees/ (Jun 2, 3:00 PM)
**Investigated**: No primary-session tool activity has been observed yet beyond the initial implementation request.

**Learned**: The requested work must follow the plan in codex-claude-usage-tray-implementation-plan.md, use a new .worktrees/ worktree, avoid touching existing worktrees, and validate changes in the real app with appropriate runtime tools.

**Completed**: No implementation changes, validations, or shipped updates have been observed yet.

**Next Steps**: The current trajectory is to create a new repository-root worktree under .worktrees/, inspect the implementation plan, execute tasks continuously, and validate behavior using the repository’s conventions and runtime tooling.
</claude-mem-context>

## Git

Never sign commits as an AI or as anyone. Nothing of 'Co-Authored By' or 'Signed-Off-By' in commit messages.
Never use the word "Claude" in commit messages.
Use conventional commits standard.
Commit messages must be in English.

## Code Style

Prefer concise, direct responses — no excessive explanations unless asked.
When suggesting fixes, show only the relevant changed code, not the entire file.
Never add comments explaining what the code does unless explicitly asked.

## Flutter

If the project contains an `.fvmrc` file or a `.fvm/` directory, always use `fvm flutter` and `fvm dart` instead of calling `flutter` or `dart` directly in any shell command.

## General Behavior

Do not add unrequested features or refactors.
Ask before making architectural decisions.
If unsure, ask — don't assume.
