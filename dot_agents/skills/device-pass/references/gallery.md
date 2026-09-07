Run `python3 <skill-directory>/scripts/render_report.py <manifest.json>` using the bundled [renderer](../scripts/render_report.py). It writes HTML beside the manifest and prints its path. Styles and scripts are embedded, but screenshots and video remain separate files in the evidence folder; keep them together when sharing.

The manifest requires `title`, `revision`, `target`, and `scenarios`. Each scenario records `name`, `mode`, `browser`, `viewport`, `status` (`pass`, `fail`, or `blocked`), `steps` as strings, and `screenshots` as objects with `file` and `caption`. Optional `video` is a file path. Optional top-level `limitations` is a list of strings. Include device scale and touch settings in the environment description.

Artifact paths must be relative to the manifest directory and resolve to existing files within it. Passing scenarios require screenshots. Correct missing evidence and invalid status errors rather than weakening validation. Open the report and images to verify the links and rendered evidence.

The bundled Pickforge gallery uses charcoal surfaces, orange accents, device filters, search, and a keyboard-accessible image viewer. If extending it, keep [HTML](../scripts/report.html), [CSS](../scripts/report.css), and [JavaScript](../scripts/report.js) consistent. Gallery styling does not replace inspection of the tested application.
