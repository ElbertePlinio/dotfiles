# Gate baseline (v1)

Defines "gated repo": the enforced-CI floor a repo must meet before the
no-read review tier is available. Every check is blocking in PR CI.
Installing and closing gaps is owned by the `gate-installer` skill.

## All repos

- Secrets scan: gitleaks CI job.
- Dependency audit: osv-scanner over all lockfiles, blocking on high/critical
  advisories. Unscored advisories block too (fail closed), except OSV records
  marked informational (unmaintained/notice), which are logged but never
  blocking. Any explicit ignore is an exact advisory ID with a reason and a
  tracking issue; prefer an `ignoreUntil` expiry.
- The CI workflow is a required status check on the default branch (branch
  protection), not only workflow-internal failure.
- Tests run with exact-output commands, `--locked` where the toolchain
  supports it.

## Rust (Tauri apps)

- `cargo test --workspace --locked --all-targets`.
- `cargo clippy --workspace --all-targets -- -D warnings`, with `clippy.toml`
  setting `cognitive-complexity-threshold = 15`; deny `too_many_lines` at its
  default 100.
- Coverage: `cargo llvm-cov` line floor at the ratchet.

## TS frontends (SolidJS, Svelte) and TS packages

- `tsc --noEmit` (or `svelte-check`).
- ESLint with at minimum: `complexity: ["error", 15]`,
  `max-lines-per-function: ["error", {"max": 100, "skipBlankLines": true, "skipComments": true}]`,
  `max-depth: ["error", 4]`. Test files are exempt from the function-size cap.
- Vitest coverage floors (lines and branches) at the ratchet.

## Ratchet rule

Floors start at current actual coverage, rounded down to a whole percent.
Floors only move up: when actual coverage exceeds the floor by more than 5
points, raise the floor to actual minus 2. Never lower a floor to make CI
pass — that is a full-read-tier change requiring explicit user approval.

## Deferred to v2

- Mutation testing (explicitly out of v1).
- Semgrep baseline ruleset.
