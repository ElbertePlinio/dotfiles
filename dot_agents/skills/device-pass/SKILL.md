---
name: device-pass
description: Run an interactive browser acceptance pass on desktop and mobile viewports, inspect the rendered results, and save reviewable screenshots and evidence. Use for device passes, responsive QA, or a request to verify a user journey in the browser after code changes.
---

Test the changed user journey in a rendered browser. Unit tests, HTTP probes, and screenshots of the landing page alone do not establish an end-to-end pass.

Record the tested commit and any PR stack, the target URL, browser version, viewport, device scale, touch settings, and whether each run is desktop, mobile emulation, or physical hardware. Choose a representative desktop width and narrow phone width from the product's supported range. Emulating an iPhone in Chromium is not a Safari or physical-device test. Only claim those when they were actually used.

Follow the active browser tool's instructions and the user's browser choice. If no browser is connected and no browser family was requested, use an available isolated browser session. A headed browser is preferable for interactive inspection. Report unavailable capabilities instead of silently replacing browser work with API calls. Never attach to or copy a personal browser profile to obtain credentials.

Use a permitted test environment and synthetic accounts/data. Perform the journey through visible controls: navigation, form entry, validation, the main action, and its persisted result after reload. For mobile emulation, exercise touch targets, menus, scrolling, dialogs, and the main action at the narrow width. Exercise keyboard focus and dialog dismissal on desktop. Select steps that matter to the change instead of reproducing every automated test.

Capture uncaught page errors and unexpected failed requests without storing request bodies, credentials, cookies, or session state in evidence. Start recordings after credential entry. Save screenshots of the important intermediate and final states, then open and inspect them. Check clipped text, horizontal overflow, excessive blank space, footer reachability, controls covered by sticky elements, and focus/validation visibility. A successful assertion does not replace visual inspection.

Keep evidence outside the repository, for example `~/Artifacts/<project>/<date>/device-pass/`, with a JSON manifest, screenshots, and optional video. Do not commit reports, screenshots, or design drafts to application documentation. Keep repository docs concise and useful for setup, features, and agent guidance. The manifest records the revision, scenarios, steps, outcomes, and limitations; use `scripts/render_report.py <manifest.json>` to make a self-contained Pickforge HTML gallery with charcoal surfaces, orange accents, device filters, search, and a keyboard-accessible image viewer. Keep these styles aligned with the bundled report assets when extending the report. Use its validation errors to correct missing evidence. Link the gallery and relevant images in the handoff.

If a defect is found, preserve its evidence, fix it in the PR that owns the change, and rerun the affected journey on the resulting revision. For stacked PRs, record which exact combined revisions were tested. Keep emulation evidence separate from any pending physical-device acceptance.

The pass is complete when the scoped journeys succeed on the stated viewports, their saved images have been inspected, the relevant automated checks pass on the tested code, and the evidence links work. Mark any untested or blocked scenario explicitly. Before handing the browser back, restore a normal desktop viewport; a fixed mobile viewport in a large browser window can leave misleading blank space. Report readiness for review; a device pass does not itself approve a merge or deployment.
