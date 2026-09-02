#!/usr/bin/env python3
import json
import re
import sys
from pathlib import Path

root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
manifest_path = Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else root / "dot_agents/skill-targets.json"
manifest = json.loads(manifest_path.read_text())
supported = {"claude", "codex", "grok", "pi", "omp"}
canonical_root = root / manifest["canonical_source"]
policy = (root / ".chezmoitemplates/agents-shared.md").read_text()
canonical_names = set()
for skill_file in canonical_root.glob("*/SKILL.md"):
    match = re.search(r"(?m)^name:\s*([^\s]+)\s*$", skill_file.read_text())
    if not match:
        raise SystemExit(f"canonical skill has no frontmatter name: {skill_file.relative_to(root)}")
    canonical_names.add(match.group(1))

non_skill_hyphen_tokens = set()
policy_tokens = set(re.findall(r"`([a-z][a-z0-9]*(?:-[a-z0-9]+)+)`", policy))
protected_portable_skills = set()
required = (policy_tokens - non_skill_hyphen_tokens) | protected_portable_skills
for name in sorted(required):
    if name not in canonical_names:
        raise SystemExit(f"required portable skill {name} has no canonical source")
    targets = set(manifest.get("skills", {}).get(name, []))
    if targets != supported:
        raise SystemExit(f"required portable skill {name} must target all supported harnesses; got {sorted(targets)}")

seen = {}
source_roots = {canonical_root}
for pattern in ("dot_*/skills", "dot_*/*/skills"):
    source_roots.update(path for path in root.glob(pattern) if path.is_dir())
for source_root in source_roots:
    if not source_root.exists():
        continue
    for skill_file in source_root.glob("*/*SKILL.md*"):
        source_name = skill_file.name.removeprefix("private_").removesuffix(".tmpl")
        if source_name != "SKILL.md":
            continue
        match = re.search(r"(?m)^name:\s*([^\s]+)\s*$", skill_file.read_text())
        if not match:
            continue
        name = match.group(1)
        previous = seen.get(name)
        if previous and previous != skill_file:
            raise SystemExit(f"duplicate skill name {name}: {previous.relative_to(root)} and {skill_file.relative_to(root)}")
        seen[name] = skill_file
print("portable skill source policy valid")
