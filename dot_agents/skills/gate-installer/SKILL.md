---
name: gate-installer
description: Audit a repo against the enforced gate baseline (coverage floors, complexity caps, secrets scan, dependency audit, branch protection) and close the gaps. Use before enabling the no-read review tier in a repo, or when local-review reports the repo ungated.
---

# Gate Installer

Target state is `~/.agents/skills/local-review/references/gate-baseline.md`.
This skill audits one repo against it and closes gaps. Idempotent: re-running
on a compliant repo changes nothing. Suitable for a cheap implementation lane.

## Workflow

1. **Audit.** For each baseline item, record present / missing / blocked with
   evidence (file path, CI job name). Read the repo; never assume.
2. **Measure before gating.** Run the repo's coverage commands and record
   actual numbers; floors follow the baseline's ratchet rule (actual, rounded
   down). Never copy thresholds from another repo.
3. **Close gaps**, one commit per gate, smallest first:
   - Rust: clippy CI step with `-D warnings`; `clippy.toml` thresholds;
     llvm-cov floor.
   - TS: ESLint complexity / max-lines-per-function / max-depth rules;
     vitest coverage thresholds; `tsc --noEmit` or `svelte-check` step.
   - All: gitleaks job; osv-scanner job; branch protection requiring the CI
     check via `gh api`.
4. **Existing violations of a new cap:** fix trivial ones in the same change.
   For structural ones, add an explicit per-site suppression
   (`#[allow]`, `eslint-disable`) with a tracking issue reference so new code
   cannot regress while legacy sites stay visible and countable. Never raise
   the cap or make the rule warn-only to get green.
5. **Validate.** Run each new check locally with exact-output commands and
   confirm green.
6. **Report.** Table of baseline item → already present / installed / blocked,
   commands run with results, coverage floors set, suppression count, and the
   decision list required by the global finishing rules. A repo is "gated"
   only when every baseline item is enforced and blocking.

## Boundaries

- Never lower an existing floor, cap, or threshold.
- Scope dependency overrides to the consumer that needs them; never pin a
  package globally when its consumers span major versions.
- Branch protection needs `gh` with admin on the repo; if unavailable, report
  the item as blocked with the exact `gh api` command — do not guess or skip
  silently.
- Follow the repo's own `AGENTS.md`; workspace push rules apply unchanged.
