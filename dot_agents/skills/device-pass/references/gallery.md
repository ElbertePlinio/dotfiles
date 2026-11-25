Run `python3 <skill-directory>/scripts/render_report.py <manifest.json>` using the bundled [renderer](../scripts/render_report.py). It writes `<manifest>.html` beside the manifest and prints its path, its size, and the count and total bytes of embedded images. Add `--cards` to also write `cards/<nn>-<id>.png`, one PNG per card at 2x for the PR. The card export needs Chrome or Chromium; set `CHROME` when the binary is not in a usual place. The renderer never changes the evidence files.

```json
{
  "title": "Pricing redesign: device vs Figma",
  "intro": "One short paragraph: branch, backend, accounts.",
  "revision": "a1b2c3d on feat/pricing, no uncommitted changes",
  "target": "Debug build on the iPhone 17 Pro simulator",
  "environment": ["iPhone 17 Pro simulator, iOS 26.1, 402 x 874 pt, 3x"],
  "links": [{"label": "Figma", "url": "https://www.figma.com/design/..."}],
  "defaults": {
    "device": {"scale": 3, "cropTopPt": 62, "caption": "status bar cropped (62 pt)"},
    "figma": {"scale": 3, "cropTopPt": 49, "caption": "status bar cropped (49 pt)"},
    "widget": {"scale": 3, "caption": "flutter test render, no app build"}
  },
  "videos": [{"src": "videos/choose-plan.mp4", "title": "Choose a plan", "desc": "One sentence."}],
  "journeys": [{"name": "Choose a plan", "mode": "iOS Simulator", "browser": "native app",
                "viewport": "402 x 874", "status": "pass", "steps": ["Open pricing", "Tap Lite"]}],
  "findings": [],
  "limitations": ["No physical device."],
  "cards": [{
    "id": "v2-pricing",
    "title": "V2: Lite first",
    "desc": "What the reader should see, in one or two sentences.",
    "device": "raw/device/v2-pricing.png",
    "figma": "raw/figma/v2-pricing.png",
    "widget": "raw/widget/v2-pricing.png",
    "note": "What explains a difference, such as live promotion copy."
  }]
}
```

The manifest requires `title`, `revision`, `target`, and at least one card. A card needs an `id` of lowercase letters, digits, and dashes, a `title`, and at least one pane. A pane is a path or an object with `src` and optional `scale`, `cropTopPt`, `cropBottomPt`, `caption`, and `label`. Values in `defaults` apply to every pane of that kind, and the pane overrides them. A kind can take a list of panes, shown side by side, each with its own `label`, such as the smallest and largest text size.

`scale` is image pixels per point, so a 3x screenshot of a 402 pt screen shows at 402 pt. Every pane then keeps its true size next to the others, and the zoom slider scales them together. Set the crops so every app bar starts at the top edge. For the device, use the top safe area in points (62 on an iPhone 17 Pro, 20 on an iPhone SE). On Android, use the status bar height in pixels divided by the density. For Figma, take the frame's app bar height and subtract the toolbar height. Component exports use no crop. State every crop in the caption. A card with a device and a Figma pane also gets an overlay with an opacity slider on the page.

Journeys carry the outcome of each tested journey: `name`, `mode`, `browser`, `viewport`, `status` (`pass`, `fail`, or `blocked`), and optional `steps` and `findings`. The page shows them, with `findings` and `limitations`, above the videos. The card PNGs never show them. Write card text as plain short sentences: the title names the state, `desc` says what to see, and `note` explains a difference.

By default the page is one self-contained file. Styles, script, and every image are embedded once, at their original bytes, and a strict Content Security Policy blocks remote loading. Images need JavaScript to display. Videos are never embedded. The page plays them from `videos/` while it sits in the evidence folder, and it lists them under "Kept beside this file". Send the video with the page when it matters. Add `--linked` for a page that links every image instead.

Each image is capped at 32 MiB, and embedding is capped at 256 MiB in total. Exceeding a cap fails with a clear error instead of reducing quality; recapture the image, or use `--linked`. Artifact paths must be relative to the manifest folder, stay inside it, contain no symlinks or `..`, and name regular files. Images must be complete PNG, JPEG, or WebP files. Videos must be MP4 or WebM. Correct an error rather than weakening validation.

To share the page, send the HTML file, with the videos when they matter. Forward the original file; a copy saved from the browser loses the images. If a channel blocks HTML attachments, ZIP the file. The page uses the Pickforge dark palette with one ember accent and no logo. If you change it, keep the [HTML](../scripts/report.html), [CSS](../scripts/report.css), and [JavaScript](../scripts/report.js) consistent.
