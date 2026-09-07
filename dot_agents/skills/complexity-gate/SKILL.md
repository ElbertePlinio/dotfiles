---
name: complexity-gate
description: Use for coding or code review, refactoring requests, and complexity-gate FAIL output.
---

Run `complexity-gate check --changed` from the repository before completing every coding or code-review task. Hooks do not replace this final check. Reuse its result while the checked revision is unchanged.

Only the binary supplies accepted measurements. Use `complexity-gate check <file>` for a file and the reported `DETAILS` command for failures. Read [output interpretation](references/output.md) when interpreting detailed results or unsupported languages.

Fix listed violations without suppressing, renaming, moving, or compressing code to escape the diff or hide branches. Never raise limits in `.complexity-gate.json` to get green. Untouched legacy functions are outside the changed gate.

Preserve behavior and public APIs; ask before changing exported signatures. Use relevant existing behavior checks as a baseline, then verify affected behavior after the refactor. Do not repeat checks on unchanged code. If checks are absent or blocked, report that and refactor conservatively. In a read-only review, have a writable worker run missing checks or authorized fixes.

Report changes, relevant behavior evidence, and remaining failures or unverified files. Include before/after binary measurements when useful, without a mandatory table or PASS dump.
