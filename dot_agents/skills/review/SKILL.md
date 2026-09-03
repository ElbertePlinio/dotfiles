---
name: review
description: Review a diff or branch before it ships. Use when asked to review, check, or look over changes.
---

# Review

Read the diff and the code around it. Run the tests if they exist.

Look for, in this order:

- Correctness: wrong behavior, missed edge cases, broken call sites, error paths.
- Security: auth, permissions, input boundaries, secrets, data exposure.
- Tests: do they pin the new behavior, and would they fail without the change?
- Over-engineering: abstractions, layers, options or files the change doesn't need.
- Duplication: logic that already exists nearby.

Report findings ranked by severity, each with file and line, what breaks, and the fix. Then one short section, "Simpler": what you would cut or collapse, or "nothing" if it's already tight.

Don't pad. No praise, no restating the diff. If it's fine, say it's fine.
