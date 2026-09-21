#!/usr/bin/env python3
"""Source-only Hermes adapter contract; never reads live configuration."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
def render(path):
    return subprocess.check_output(["chezmoi", "--source", str(ROOT), "execute-template", "--file", str(ROOT / path)])

hashes = json.loads((ROOT / "scripts/check/hermes-policy-render-hashes.json").read_text())
for path, expected in hashes.items():
    assert hashlib.sha256(render(path)).hexdigest() == expected, path + " changed semantics/bytes"
policy = render("dot_agents/hermes-system-prompt.md.tmpl").decode()
for part in ("prefix", "suffix"):
    text = (ROOT / (".chezmoitemplates/agents-shared-neutral-" + part + ".md")).read_text()
    assert policy.count(text) == 1
for forbidden in ("lanes_models", "pickforge-lanes models", "named profiles", "assessment attempts", "Task records survive", "Pi lanes", "SOUL.md"):
    assert forbidden not in policy, forbidden
for required in ("Never expose, commit, or send secrets", "publishing stay drafts", "explicitly request takes precedence", "Execute small tasks directly", "native Hermes orchestration"):
    assert required in policy, required
# Optional integration test against the installed runtime's real config resolver.
if len(sys.argv) > 1:
    sys.path.insert(0, sys.argv[1])
    from hermes_cli.personality import resolve_ephemeral_system_prompt
    cfg = {"agent": {"system_prompt": policy}, "display": {"personality": "none"}}
    assert resolve_ephemeral_system_prompt(cfg) == policy.strip()
    cfg["display"]["personality"] = "concise"
    assert resolve_ephemeral_system_prompt(cfg) != policy.strip(), "personality must be checked before activation"
print("PASS: five existing harnesses match approved render hashes; Hermes neutral-only; supported prompt resolver" if len(sys.argv) > 1 else "PASS: five existing harnesses match approved render hashes; Hermes neutral-only")
