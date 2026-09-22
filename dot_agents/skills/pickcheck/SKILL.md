---
name: pickcheck
description: Use before publishing code by push or PR, for refactoring requests, and for pickcheck FAIL output. Not a per-edit, per-commit, or code-review step.
---

Run the gate once at the publication boundary, before a push or PR, alongside the repository's tests, lint, and type checks. No harness hook runs it automatically, and it is not required for each edit or commit, for code review, or before a review. Its result stays valid evidence while the published revision and working tree are unchanged; rerun only after they change.

`pickcheck check --changed` measures changed functions in uncommitted work against `HEAD`. On a clean committed branch it checks nothing and exits 0, so it is not evidence for committed changes. The CLI has no base or commit-range option. For committed work, pass the files changed since the publication base in a Bash script that fails when the base is missing or `git diff` fails:

```bash
set -euo pipefail
base=origin/main
git rev-parse --verify --quiet "$base^{commit}" >/dev/null
git diff -z --name-only --diff-filter=d "$base...HEAD" -- | xargs -0 -r pickcheck check --
```

Also run `--changed` when uncommitted edits remain. File paths are measured whole, so failures in untouched legacy functions of those files are reported too; fix functions the change touched and report the rest as preexisting.

A repository that wants enforcement declares that range command in its own CI or a repository-local `.git/hooks/pre-push`, using the base branch or the pushed range; the global Git hook dispatcher chains to that local hook. Never add the gate to the global dispatcher, where it would run in every unrelated repository.

Only the binary supplies accepted measurements. Use `pickcheck check <file>` for a file and the reported `DETAILS` command for failures. Read [output interpretation](references/output.md) when interpreting detailed results or unsupported languages.

Fix listed violations without suppressing, renaming, moving, or compressing code to escape the diff or hide branches. Never raise limits in `.pickcheck.json` to get green. Untouched legacy functions are outside this change's scope.

Preserve behavior and public APIs; ask before changing exported signatures. Use relevant existing behavior checks as a baseline, then verify affected behavior after the refactor. Do not repeat checks on unchanged code. If checks are absent or blocked, report that and refactor conservatively.

Report changes, relevant behavior evidence, and remaining failures or unverified files. Include before/after binary measurements when useful, without a mandatory table or PASS dump.
