#!/usr/bin/env python3
"""Render a device-pass manifest as a local HTML evidence gallery.

Required: title, revision, target, scenarios.
Each scenario: name, mode, browser, viewport, status (pass/fail/blocked),
steps (strings), screenshots ({file, caption}); optional video (file).
Optional top-level limitations is a list of strings.
Artifact paths must exist inside the manifest directory.
"""

import argparse
import html
import json
from pathlib import Path
from urllib.parse import quote


def text(value):
    return html.escape(str(value), quote=True)


def artifact_url(root, filename):
    path = Path(filename)
    resolved = (root / path).resolve()
    if path.is_absolute() or not resolved.is_relative_to(root.resolve()):
        raise ValueError(f"Artifact must stay inside the evidence folder: {filename}")
    if not resolved.is_file():
        raise ValueError(f"Missing evidence artifact: {filename}")
    return quote(path.as_posix(), safe="/")


def screenshot_html(root, screenshot):
    url = artifact_url(root, screenshot['file'])
    caption = text(screenshot['caption'])
    return f'<figure><a href="{url}"><img src="{url}" alt="{caption}" loading="lazy"></a><figcaption>{caption}</figcaption></figure>'


def scenario_html(root, scenario):
    status = scenario['status']
    if status not in ('pass', 'fail', 'blocked'):
        raise ValueError(f"Invalid scenario status: {status}")
    screenshots = scenario.get('screenshots', [])
    if status == 'pass' and not screenshots:
        raise ValueError(f"Passing scenario needs screenshots: {scenario['name']}")
    details = ' · '.join(text(scenario[key]) for key in ('mode', 'browser', 'viewport'))
    steps = ''.join(f'<p>{text(step)}</p>' for step in scenario['steps'])
    images = ''.join(screenshot_html(root, shot) for shot in screenshots)
    video = ''
    if scenario.get('video'):
        url = artifact_url(root, scenario['video'])
        video = f'<video controls preload="metadata" src="{url}"></video>'
    return f'<section><p class="scenario">{text(scenario["name"])} · {text(status)}</p><p>{details}</p>{steps}<div class="images">{images}</div>{video}</section>'


def render(manifest):
    data = json.loads(manifest.read_text())
    scenarios = ''.join(scenario_html(manifest.parent, item) for item in data['scenarios'])
    limitations = ''.join(f'<p>{text(item)}</p>' for item in data.get('limitations', []))
    return f'''<!doctype html>
<html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>{text(data['title'])}</title>
<style>
body{{font:16px/1.5 system-ui,sans-serif;max-width:1200px;margin:24px auto;padding:0 16px;color:#18212b;background:#fff}}
.title{{font-size:24px}}.scenario{{font-size:20px}}section{{border-top:1px solid #ccd2d8;margin-top:28px;padding-top:12px}}
.images{{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,320px),1fr));gap:16px}}
figure{{margin:0}}img,video{{width:100%;height:auto;border:1px solid #ccd2d8}}figcaption{{font-size:14px}}p{{overflow-wrap:anywhere}}
</style><body><p class="title">{text(data['title'])}</p>
<p>Revision: {text(data['revision'])}</p><p>Target: {text(data['target'])}</p>
{limitations}{scenarios}</body></html>'''


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('manifest', type=Path)
    args = parser.parse_args()
    output = args.manifest.with_suffix('.html')
    output.write_text(render(args.manifest))
    print(output)


if __name__ == '__main__':
    main()
