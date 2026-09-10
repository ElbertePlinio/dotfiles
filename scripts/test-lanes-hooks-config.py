#!/usr/bin/env python3
"""Check the managed hooks needed for notification delivery and Stop rearming."""
import json
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
SOURCES = {
    "codex": "dot_codex/hooks.json.tmpl",
    "claude": "dot_claude/settings.json.tmpl",
}


def lane_hooks(harness, event, listen=False):
    document = json.loads((ROOT / SOURCES[harness]).read_text())
    command = f"pickforge-lanes hook {harness}" + (" --listen" if listen else "")
    return [
        (group, hook)
        for group in document["hooks"][event]
        for hook in group["hooks"]
        if hook.get("command") == command
    ]


class LaneHookConfigurationTests(unittest.TestCase):
    def test_lifecycle_tracking_is_synchronous_and_includes_shutdown(self):
        for harness in SOURCES:
            for event in ("SessionStart", "PostToolUse", "Stop", "SessionEnd"):
                with self.subTest(harness=harness, event=event):
                    entries = lane_hooks(harness, event)
                    self.assertEqual(len(entries), 1)
                    group, hook = entries[0]
                    self.assertFalse(hook.get("async"))
                    self.assertFalse(hook.get("asyncRewake"))
                    self.assertFalse(group.get("matcher"))
                    if event == "Stop":
                        self.assertGreaterEqual(hook["timeout"], 3)

    def test_listeners_use_the_harness_wake_mechanism_and_rearm_at_stop(self):
        for harness in SOURCES:
            flag = "async" if harness == "codex" else "asyncRewake"
            for event in ("PostToolUse", "Stop"):
                with self.subTest(harness=harness, event=event):
                    entries = lane_hooks(harness, event, listen=True)
                    self.assertEqual(len(entries), 1)
                    group, hook = entries[0]
                    self.assertIs(hook[flag], True)
                    self.assertGreater(hook["timeout"], 14400)
                    if event == "Stop":
                        self.assertFalse(group.get("matcher"))
                    else:
                        self.assert_result_matcher(group["matcher"])

    def assert_result_matcher(self, matcher):
        # Codex code mode emits the same canonical inner MCP name as direct calls.
        for server in ("pickforge-lanes", "pickforge_lanes"):
            for tool in ("spawn", "continue", "wait", "status", "abandon"):
                self.assertIsNotNone(re.search(matcher, f"mcp__{server}__lanes_{tool}"))


if __name__ == "__main__":
    unittest.main()
