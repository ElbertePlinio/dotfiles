---
name: device-pass
description: Use for device passes, responsive browser QA, verifying a changed user journey on desktop and mobile, or PR evidence that compares the build with Figma through cards, screenshots and a screen recording.
---

The executing model needs the required browser/device tools. If the current session lacks them, hand off to one that has them, giving it the revision, scenarios, test environment, and evidence destination. Pi lanes disable extensions and do not inherit browser/MCP tools; do not assume a lane spawn can perform the pass. Confirm the worker has the required browser/device tools before spawning; a tool name alone does not guarantee access in the child. Use an execution mode that exposes those tools and limit the task to verification, not code edits. If no session with those tools is available, report the blocker.

Test the changed user journey in a rendered browser or on a device. Unit tests, HTTP probes, and screenshots of the landing page alone do not establish an end-to-end pass.

Record the tested commit, any uncommitted changes, and any PR stack, the target URL or build, browser or OS version, viewport, device scale, touch settings, and whether each run is desktop, mobile emulation, a simulator, or physical hardware. Choose a representative desktop width and narrow phone width from the product's supported range. Emulating an iPhone in Chromium is not a Safari or physical-device test. Only claim those when they were actually used.

Follow the active browser tool's instructions and the user's browser choice. If no browser is connected and no browser family was requested, use an available isolated browser session. A headed browser is preferable for interactive inspection. Report unavailable capabilities instead of silently replacing browser work with API calls. Never attach to or copy a personal browser profile to obtain credentials. Never boot, shut down, or drive a simulator, emulator, or phone that another session or the user is using.

Use a permitted test environment and synthetic accounts/data. Perform the journey through visible controls: navigation, form entry, validation, the main action, and its persisted result after reload. For mobile, exercise touch targets, menus, scrolling, dialogs, and the main action at the narrow width. On native apps, also change the text size to the smallest and largest setting with the screen open, and check clipping and the safe areas. Exercise keyboard focus and dialog dismissal on desktop. Select steps that matter to the change instead of reproducing every automated test.

Capture uncaught page errors and unexpected failed requests without storing request bodies, credentials, cookies, or session state in evidence. Save full-size screenshots of the important intermediate and final states, then open and inspect them. Check clipped text, horizontal overflow, excessive blank space, footer reachability, controls covered by sticky elements, and focus/validation visibility. A successful assertion does not replace visual inspection.

Keep evidence outside the repository and the session scratchpad. The default is `~/Artifacts/<project>/<date>/device-pass/`; a project rule may name another folder. Give each state one kebab-case name and use it in every folder where the state exists:

```
manifest.json      cards, videos, journeys; see the gallery reference
manifest.html      the built page
cards/             one PNG per card for the PR
videos/            one MP4 per recorded journey for the PR
raw/device/        screenshots from the browser or device
raw/figma/         Figma frames exported at 3x
raw/widget/        isolated renders of the changed widget or component
raw/video/         flow files, raw recordings, tap logs, and frame sheets
```

Each card compares one state: the device capture, the Figma frame at the same point scale, and an isolated widget render. Export Figma frames as PNG at scale 3 through the Figma connector or REST API, one call per frame node. A screenshot tool that returns the frame at 1x is too soft. Without Figma access, ask the user for the exported frames. When the design has no frame for a state, leave the Figma pane out and say so in the card note. A change that removes UI can put the base-branch build in the Figma pane with the label `main`. For Flutter widgets, render the widget with the flutter-component-preview skill's widget-test harness. For web components, use the project's existing isolated preview, such as Storybook. Leave the widget pane out when no isolated render exists.

Record one video of the main changed journey at the default text size. Record more only when a state needs motion, such as an animation, a sheet, or a live text size change. Record each journey as one whole video and never split it. Start recordings after login and credential entry. Test data such as a test card may show. For a native app, use the [flow recorder](scripts/record_flow.py), which replays the steps at a human pace with a clean status bar and draws a dot on each tap:

1. Drive the journey by hand first and note each element's label: the iOS `AXLabel` from `idb ui describe-all`, or the Android `content-desc` or `text` from `adb exec-out uiautomator dump /dev/tty`.
2. Write `raw/video/<journey>.flow.json` as a JSON list of steps. The script's docstring lists them. Start from a screen you can reach again, such as a deep link.
3. Rehearse with `python3 <skill-directory>/scripts/record_flow.py --udid <udid> --dry-run <flow>`, or `--serial <serial>` for Android. A failed step prints the labels on screen. On an emulator, the script records with the emulator's own recorder, because `screenrecord` drops frames there. Start a Linux emulator with `-gpu host`; software rendering is too slow for a smooth video.
4. Put the app back on the first screen and run the same command without `--dry-run`.
5. Read `raw/video/<journey>-sheet.png` and check that each step shows.

For a browser journey, record with the active browser tool's recording feature and save the file in `videos/`. Run `record_flow.py --sheet <video>`, which writes `<video>-sheet.png` beside it, then move the sheet to `raw/video/`.

Write the manifest as the [gallery reference](references/gallery.md) describes, then run `python3 <skill-directory>/scripts/render_report.py <manifest.json> --cards`. Open the page and every card PNG, and check that each crop starts at the app bar. Cards go on the PR, so they show facts only: no status, verdict, or open question. Journey outcomes, findings, and limitations go in the manifest, where the page shows them above the cards. Link the page, the cards, and the videos in the handoff; do not commit evidence to application documentation. Publishing, uploading, or attaching evidence to a PR needs the user's request.

If a defect is found, preserve its evidence. A verification-only request means report the defect, not repair it. If fixing is already authorized, fix it in the PR that owns the change and rerun the affected journey on the resulting revision. After a fix, replace the changed states' raw files, record the flows again, and rebuild. Do not keep stale shots next to new ones. For stacked PRs, record which exact combined revisions were tested. Keep emulation evidence separate from any pending physical-device acceptance.

The pass is complete when the scoped journeys succeed on the stated viewports or devices, their saved images and video sheets have been inspected, relevant automated evidence applies to the tested code, and the evidence links work. Mark any untested or blocked scenario explicitly. Before handing the browser back, restore a normal desktop viewport; a fixed mobile viewport in a large browser window can leave misleading blank space. Restore the device text size you changed. Report readiness for review; a device pass does not itself approve a merge or deployment.
