Machine capture reference. Check the active desktop and available tools before choosing a command.

On macOS, screencapture -x <file> captures the screen; -o -l <window-id> selects a window and -R<x,y,w,h> a region. Screen Recording permission is required for capture and Accessibility for input. Check permissions when capture is black or empty. Prefer an app API or test harness when it serves the task.

On Linux, avoid ImageMagick import: it rings the X bell and is unreliable under Xwayland. X11 or Xwayland windows can use xdotool for input and maim -i <window-id> for capture. Headless PickLab/Xvfb labs use this pair. On KDE Plasma Wayland, spectacle -b -n -o <file> captures the screen and -a selects the active window; ydotool requires its daemon. Other Wayland desktops need their own available capture tools.

Preserve original evidence. Inspect it at the resolution the task needs. Crop or zoom dense text and small details; resize only when the resulting image remains useful. There is no universal downscale size or guarantee of unchanged readability. Follow the active vision tool's capabilities.
