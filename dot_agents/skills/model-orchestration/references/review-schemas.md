# Review Schemas

Use `$local-review` as the source of truth. Give every read-only reviewer one primary failure-mode profile and require actionable findings only.

## General Review

Each finding must include:

- severity: `P0`, `P1`, `P2`, or `P3`
- file and line or exact symbol when applicable
- observable problem
- evidence tying it to the reviewed diff
- smallest correct fix or verification path

Prompt shape:

```text
You are a read-only reviewer. Do not write files.
Primary profile: <one local-review profile>.
Review the actual diff, affected call paths, and validation evidence.
Return actionable findings first. Reject vague concerns, style preferences,
and speculative future requirements. If none exist, return CLEAN.
```

The orchestrator deduplicates and adjudicates findings. A clean verdict means no actionable finding, not merely no major finding.

## Frontend Review

Add checks for:

- Visual hierarchy and density.
- Responsive layout and overflow.
- Accessibility and keyboard paths.
- Loading, empty, error, and disabled states.
- Copy clarity and product fit.

Choose a vision/taste-capable reviewer such as Grok, Opus, or Fable based on the risk. Use Fable/Opus when final product judgment is the main concern.

## Backend Review

Add checks for:

- API contracts and compatibility.
- Data integrity and migrations.
- Auth, permissions, secrets, and tenant boundaries.
- Error handling and observability.
- Test coverage for edge cases.

Choose an independent technical reviewer such as Sol, Grok, or GLM. Add Fable/Opus when architecture tradeoffs or product judgment are material.
