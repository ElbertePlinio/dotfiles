# Visual acceptance

Use the narrowest set that can expose a real failure.

## Inspect

- The primary job is obvious before secondary actions.
- Hierarchy, alignment, spacing, type, color, and icon treatment match the contract.
- Real content does not break the intended rhythm or density.
- Loading, empty, error, focus, disabled, selected, and destructive states are coherent where relevant.
- The layout works at target sizes and through intermediate resizing, not just one screenshot.
- Motion explains change or confirms action, remains responsive, and has a reduced-motion path.
- Keyboard order, focus visibility, contrast, labels, and touch targets fit the platform.
- The result belongs to the product rather than looking like a generic template.
- Subtraction: no element could be removed without breaking a job, and no state has more than one indicator.

## Evidence

Prefer rendered screenshots for stable states and a short recording or live inspection for motion. Compare against the contract and references at the same viewport when possible. Name any untested platform or state instead of implying it passed.

## Review output

Return:

```md
Decision: accepted | accepted with follow-up | revise
Highest-impact gap: <one sentence or none>
Contract deviations: <list or none>
Evidence inspected: <screens, states, sizes, motion>
```
