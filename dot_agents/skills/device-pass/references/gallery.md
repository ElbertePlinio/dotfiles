Run `python3 <skill-directory>/scripts/render_report.py <manifest.json>` using the bundled [renderer](../scripts/render_report.py). It writes `<manifest>.html` beside the manifest and prints its path, its size, and the count and total bytes of embedded images. The renderer only writes that HTML file and never changes the evidence.

By default the report is one self-contained file. Styles, script, and every screenshot are embedded, so it opens offline from any folder with no server and no adjacent files. Each unique image is embedded once at its original bytes, with no re-encoding or downscaling, and a strict Content Security Policy blocks remote loading. Images need JavaScript to display. Add `--linked` for the older report that links to screenshots and video as separate files; keep them together with it when sharing that version.

Video is never embedded. The standalone report shows "Video not included in this portable file" with the file name and lists it in the context panel and footer. Share the video separately if it matters.

Embedding is capped at 32 MiB per image and 256 MiB in total. Exceeding a cap fails with a clear error instead of reducing quality or leaving evidence out; use `--linked` or split the pass. Base64 adds about a third to image size, so check the printed size before sending.

The manifest requires `title`, `revision`, `target`, and `scenarios`. Each scenario records `name`, `mode`, `browser`, `viewport`, `status` (`pass`, `fail`, or `blocked`), `steps` as strings, and `screenshots` as objects with `file` and `caption`. Optional `video` is a file path. Optional `findings` lists strings, at the top level or per scenario. Optional top-level `limitations` is a list of strings. Include device scale and touch settings in the environment description, since the standalone file must carry all the context a recipient needs.

Artifact paths must be relative to the manifest directory, stay inside it, contain no symlinks or `..`, and name regular files. Screenshots must be complete PNG, JPEG, or WebP images, checked by their content and structure; truncated or corrupt files fail with an error. Passing scenarios require screenshots. Correct missing evidence, unsupported images, and invalid status errors rather than weakening validation. Open the report and images to verify the rendered evidence.

To share a standalone report, send the single HTML file. The recipient downloads it and opens it in a browser. If an email or chat channel blocks HTML attachments or previews, ZIP the HTML file and send the ZIP. No hosted service is needed.

The bundled Pickforge gallery uses charcoal surfaces, orange accents, device filters, search, and a keyboard-accessible image viewer. If extending it, keep [HTML](../scripts/report.html), [CSS](../scripts/report.css), and [JavaScript](../scripts/report.js) consistent; the same script serves both standalone and linked reports. Gallery styling does not replace inspection of the tested application.
