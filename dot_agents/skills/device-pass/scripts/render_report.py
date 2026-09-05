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
import re
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


def screenshot_html(root, screenshot, index):
    url = artifact_url(root, screenshot['file'])
    caption = text(screenshot['caption'])
    return f'<figure class="shot"><a href="{url}" aria-label="Open {caption}"><div class="image-stage"><img src="{url}" alt="{caption}"></div><figcaption><span class="shot-number">{index:02d}</span><span>{caption}</span></figcaption></a></figure>'


def scenario_html(root, scenario):
    status = scenario['status']
    if status not in ('pass', 'fail', 'blocked'):
        raise ValueError(f"Invalid scenario status: {status}")
    screenshots = scenario.get('screenshots', [])
    if status == 'pass' and not screenshots:
        raise ValueError(f"Passing scenario needs screenshots: {scenario['name']}")
    details = ' · '.join(text(scenario[key]) for key in ('mode', 'browser', 'viewport'))
    steps = ''.join(f'<li>{text(step)}</li>' for step in scenario['steps'])
    images = ''.join(screenshot_html(root, shot, i + 1) for i, shot in enumerate(screenshots))
    video = ''
    if scenario.get('video'):
        url = artifact_url(root, scenario['video'])
        video = f'<video controls preload="metadata" src="{url}"></video>'
    mode = 'mobile' if 'mobile' in scenario['mode'].lower() else 'desktop'
    return f'<section class="scenario {mode}" data-mode="{mode}"><div class="scenario-head"><div><h3>{text(scenario["name"])}</h3><p class="scenario-meta">{details}</p></div><span class="badge {status}">{status}</span></div><details class="steps"><summary>Journey · {len(scenario["steps"])} verified steps</summary><ol>{steps}</ol></details><div class="images">{images}</div>{video}</section>'


def report_context(data):
    limitations = ''.join(f'<p>{text(item)}</p>' for item in data.get('limitations', []))
    return f'<details class="context"><summary>Test environment, revision & limitations</summary><div class="context-body"><p class="revision mono">{text(data["revision"])}</p><p>{text(data["target"])}</p>{limitations}</div></details>'


def report_stats(data):
    scenarios = data['scenarios']
    passed = sum(item['status'] == 'pass' for item in scenarios)
    captures = sum(len(item.get('screenshots', [])) for item in scenarios)
    return f'<div class="stats"><div class="stat"><strong>{passed}/{len(scenarios)}</strong><span>Journeys passed</span></div><div class="stat"><strong>{captures:02d}</strong><span>Saved captures</span></div><div class="stat"><strong>Local</strong><span>Evidence source</span></div></div>'


def render(manifest):
    data = json.loads(manifest.read_text())
    scenarios = ''.join(scenario_html(manifest.parent, item) for item in data['scenarios'])
    assets = Path(__file__).parent
    template = (assets / 'report.html').read_text()
    values = {
        'TITLE': text(data['title']), 'STATS': report_stats(data),
        'SUBTITLE': text(data.get('subtitle', 'A visual record of the tested journeys. Open any capture for a closer look.')),
        'CONTEXT': report_context(data), 'SCENARIOS': scenarios,
        'CSS': (assets / 'report.css').read_text(),
        'JS': (assets / 'report.js').read_text(),
        'CAPTURES': str(sum(len(item.get('screenshots', [])) for item in data['scenarios'])),
    }
    return re.sub(r'\{\{([A-Z]+)\}\}', lambda match: values[match[1]], template)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('manifest', type=Path)
    args = parser.parse_args()
    output = args.manifest.with_suffix('.html')
    output.write_text(render(args.manifest))
    print(output)


if __name__ == '__main__':
    main()
