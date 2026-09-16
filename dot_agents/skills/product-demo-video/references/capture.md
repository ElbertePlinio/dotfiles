Tool discovery. Before planning, check with `command -v` which of gpu-screen-recorder, ffmpeg, ffprobe, grim, hyprctl, wtype, Chromium, and Bun are installed, and read `gpu-screen-recorder --help` for the flags your installed version supports. A missing required tool is a blocker to report precisely, not something to install globally without authorization.

Recorder. The validated recorder on this machine is gpu-screen-recorder run with `-cursor no`, which excludes the cursor from the video so the pointer can be drawn in editing from metadata, and `-write-first-frame-ts yes`, which writes a timestamp sidecar next to the recording holding the first frame's monotonic and realtime timestamps in microseconds. The command takes the shape `gpu-screen-recorder -w <output> -f 60 -cursor no -write-first-frame-ts yes -o <file.mp4>`; confirm every flag against the installed version instead of copying blindly, and record the sidecar path in the manifest.

Time alignment. Frames and input events must share one time origin. Use the sidecar's monotonic and realtime microseconds as the mapping between clocks: convert pointer and click event timestamps, in whatever clock they arrive, onto the video timeline using the first frame timestamp, and record the chosen origin and conversion in the manifest. If the event source cannot provide trustworthy timestamps, report that rather than estimating or fabricating.

Coordinates. Pointer events usually arrive in global screen coordinates. When recording a region or a single monitor, record the region offset and any scale in the manifest and transform events into video pixel coordinates. Verify the transform in the proof by confirming that a click lands on its visible target in the extracted frames.

Proof first. Before any full take, record about five seconds, run ffprobe on it for codec, frame rate, and duration, extract and inspect frames, and check that the cursor is excluded, the region is right, no private content is visible, and a click aligns with its visible effect. Only a verified proof authorizes a full capture.

Interaction metadata. Save pointer positions and click events as structured data synchronized to the video timeline. Never synthesize plausible events after the fact and never log keystrokes; keyboard input stays out of the metadata entirely. If reliable event capture is unavailable, stop and report the blocker.

Privacy staging. Use synthetic demo data and accounts. Close or silence notifications, hide bookmarks and personal tabs, and pick a clean workspace. Do not close the user's own applications; minimize or move only what you are authorized to arrange. No private account, no terminal output with hostnames or paths, and no notification popups may appear in any frame.

Restoration and cleanup. Note what you changed, including window arrangement, focus, do-not-disturb, volume, and files created for the demo, and restore it when capture ends. Stop the recorder by the process ID you started and wait for it to exit; never kill by name pattern, which can hit the user's own processes.

Reproducibility. Write a manifest beside the captures recording sanitized command lines (never credentials, tokens, or authentication arguments), sidecar paths, resolution, frame rate, time origin and conversion, coordinate transform, and shot list, so the same take can be reproduced without guesswork.
