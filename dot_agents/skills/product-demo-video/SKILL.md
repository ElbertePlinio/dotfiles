---
name: product-demo-video
description: Use when creating or editing a short product marketing demo video from real desktop or web screen recordings, including Remotion editing, captions, zoom or blur effects, a 16:9 master with a 4:5 mobile reframe and thumbnail, or recording synchronized pointer and click metadata for such a video. Triggers include make a demo video of this feature, turn this screen recording into a marketing clip, record a product demo, or reframe a demo for social.
---

The video shows only what actually happened on screen. Repeatable automation may operate the real interface during capture; record its actual pointer positions and click timestamps. Interpolate or smooth between measured pointer samples while preserving real click and hover timing. Never fabricate events or product responses, never log keyboard input, and never present results the product did not produce. A slideshow of screenshots with pans is not a screen recording. If only stills are possible, report that limitation rather than presenting them as footage.

Interactive capture and computer-use steps follow the standing model, effort, and tool-access policy. Confirm the actual control mechanism before dispatch: native desktop capture may use shell tools, and browser control may use an explicitly available Playwright installation even without inherited MCP tools. Shell access alone does not prove browser control is available. Never claim a worker has tools it lacks.

Discover installed tools before planning and do not install dependencies globally without authorization. Validated on this machine are gpu-screen-recorder, ffmpeg, ffprobe, Bun, Chromium, grim, hyprctl, and wtype. New Remotion projects use Bun, and Remotion dependencies install project-locally.

Recordings contain no private accounts, terminals, or notifications. Stage synthetic demo state before recording. Do not close the user's own applications; arrange only what you are authorized to arrange and restore the previous state afterward. Track the process IDs of recorders you started and stop only those, never by broad process name. Nothing is uploaded or published; outputs stay local for the user to submit.

Plan the shots, stage privacy-safe state, then record a five second proof and inspect it before any full capture. Full capture records real interactions with the cursor excluded from the video and pointer and click events saved as synchronized metadata. Editing happens in a Remotion project driven by that metadata, with zooms, blurs, and captions. Use the [capture reference](references/capture.md) for recorder commands, time alignment, coordinate transforms, and privacy staging, and the [Remotion reference](references/remotion.md) for project setup, editing, and rendering.

Video frames and pointer events must share one time origin, and event coordinates must be transformed into the recorded region's pixel space. Verify both in the proof before committing to a full take.

Produce a 16:9 master, a 4:5 mobile reframe, a thumbnail, the Remotion source project, and a metadata manifest tying them to the captures. Validate each output with ffprobe for codec, frame rate, and duration, inspect extracted frames, and confirm real playback. Passing renders or tests are not visual proof; look at the actual output.

The task is complete when the proof and full captures exist as real footage with aligned metadata, all output artifacts exist and have been inspected, codec, frame rate, and duration match the plan, playback was confirmed, the desktop state was restored, and the manifest records commands, time origin, coordinate transform, and file paths. If a required tool is missing or capture fails, report the precise blocker; never fabricate or substitute footage.
