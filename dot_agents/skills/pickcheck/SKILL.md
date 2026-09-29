---
name: pickcheck
description: Use before publishing code by push or PR, for refactoring requests, and for pickcheck FAIL output. Not a per-edit, per-commit, or code-review step.
---

Run the gate once at the publication boundary, before a push or PR, alongside the repository's tests, lint, and type checks. No harness hook runs it automatically, and it is not required for each edit or commit, for code review, or before a review. Its result stays valid evidence while the published revision and working tree are unchanged; rerun only after they change.

From inside the repository, run `pickcheck check --base origin/main --fail-on new,worsened,unmatched --format json`, naming the publication base instead of `origin/main` when the branch targets or stacks on another branch. One run checks every function changed since the branch forked from the base, committed or not, plus untracked files. It needs pickcheck 0.4.0 or newer; with an older binary, report that rather than falling back to whole-file checks. When the base ref or merge base is missing it exits 2; fetch the base branch, or more history in a shallow clone, instead of dropping `--base`. Plain `--changed` covers only uncommitted work against `HEAD` and is not evidence for committed changes.

Each violation has a `status` against the merge base. `new`, `worsened`, and `unmatched` fail the run and are findings to fix. `unchanged` and `improved` are existing debt: they print as `WARN`, never fail, and are reported as existing rather than fixed as part of this change. `base_metrics` holds the values before the change and `limits` the effective limits.

A repository that wants enforcement declares `pickcheck check --base <base branch> --fail-on new,worsened,unmatched` in its own CI or a repository-local `.git/hooks/pre-push`, using the base branch or the pushed range; the global Git hook dispatcher chains to that local hook. Never add the gate to the global dispatcher, where it would run in every unrelated repository.

Only the binary supplies accepted measurements. Use `pickcheck check <file>` for a file and the reported `DETAILS` command for failures. Read [output interpretation](references/output.md) when interpreting detailed results or unsupported languages.

Fix listed violations without suppressing, renaming, moving, or compressing code to escape the diff or hide branches; a renamed function counts as `new`. Never raise limits in `.pickcheck.json` to get green. Existing debt the change did not worsen is outside its scope.

Preserve behavior and public APIs; ask before changing exported signatures. Use relevant existing behavior checks as a baseline, then verify affected behavior after the refactor. Do not repeat checks on unchanged code. If checks are absent or blocked, report that and refactor conservatively.

Report changes, relevant behavior evidence, remaining failures, existing debt in touched functions, and unverified files. Include before/after binary measurements when useful, without a mandatory table or PASS dump.
