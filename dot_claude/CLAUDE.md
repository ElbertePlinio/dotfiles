# Global Claude Rules

## Context & Tools

Always use Context7 when I need library/API documentation, code generation, setup or configuration steps without me having to explicitly ask.

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

@RTK.md
