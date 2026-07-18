# Desktop capture, input, and screenshot handling

Procedures for this machine (KDE Plasma Wayland). Read before driving desktop
UI or loading screenshots into model context.

## Capture and input routing

- Never use ImageMagick `import` — it rings the X bell per capture and is
  unreliable under Xwayland.
- First check which layer the target app runs on: if
  `xdotool search --name <app>` finds the window it is Xwayland — use `xdotool`
  for input and `maim -i <window-id>` for capture.
- Otherwise it is native Wayland — use `spectacle -b -n -o <file>` (full
  screen) or `spectacle -b -n -a -o <file>` (active window) for capture and
  `ydotool` for input (daemon already running).
- Headless PickLab/Xvfb labs are pure X11: `xdotool` + `maim`.

## Screenshot downscaling

Before reading any screenshot into model context, downscale it:

```
magick <raw> -resize 1568x1568\> -quality 80 <out>.jpg
```

Vision cost scales with pixel dimensions, so a 4K capture wastes ~7x tokens
over a 1568px one with no readability loss. Keep the raw PNG on disk as
evidence; feed only the downscaled JPEG to the model.
