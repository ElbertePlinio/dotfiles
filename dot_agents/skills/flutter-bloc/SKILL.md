---
name: flutter-bloc
description: Use for Flutter BLoC/Cubit state, events, states, side effects, tests, and review.
---

# Flutter BLoC

Use BLoC/Cubit only when it fits the repo and the feature.

- Existing repo state management wins.
- Local state is fine for simple UI-only state.
- Use Cubit for simple feature state and direct actions.
- Use BLoC when events, async flows, or auditability matter.
- Keep states explicit and immutable.
- Avoid boolean soup; prefer clear status/value objects or sealed variants when the repo supports them.
- Put one-off effects in listeners, not builders.
- Use selectors/build filters to avoid broad rebuilds.
- Test the important state paths with the repo's existing test style.

When reporting back, state why Cubit, BLoC, or local state was the right fit.
