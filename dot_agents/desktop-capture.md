# Desktop capture, input, and screenshot handling

Read before driving desktop UI or loading screenshots into model context.
Capture tooling is per-OS; the downscaling rule at the bottom is not.

## macOS

- Capture with `screencapture -x <file>` (silent, full screen), `-o -l <window-id>`
  for one window, `-R<x,y,w,h>` for a region.
- Capture needs Screen Recording permission and input driving needs
  Accessibility. If a capture comes back black or empty, that permission is
  missing — say so instead of retrying.
- Prefer the app's own CLI, `osascript`, or a test harness over synthetic
  clicks.

## Linux (KDE Plasma Wayland)

- Never use ImageMagick `import` — it rings the X bell per capture and is
  unreliable under Xwayland.
- Check which layer the target app runs on first: if
  `xdotool search --name <app>` finds the window it is Xwayland — use `xdotool`
  for input and `maim -i <window-id>` for capture.
- Otherwise it is native Wayland — use `spectacle -b -n -o <file>` (full
  screen) or `spectacle -b -n -a -o <file>` (active window) for capture and
  `ydotool` for input (daemon already running).
- Headless PickLab/Xvfb labs are pure X11: `xdotool` + `maim`.

## Screenshot downscaling (every platform)

Before reading any screenshot into model context, downscale it:

```
magick <raw> -resize 1568x1568\> -quality 80 <out>.jpg
```

Vision cost scales with pixel dimensions, so a 4K capture wastes ~7x tokens
over a 1568px one with no readability loss. Keep the raw PNG on disk as
evidence; feed only the downscaled JPEG to the model.
