#!/usr/bin/env python3
import sys
sys.dont_write_bytecode = True
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch, MagicMock
import subprocess

SOURCE = Path(__file__).resolve().parents[1] / "run_onchange_after_configure_codex_lanes_mcp.py"
spec = importlib.util.spec_from_file_location("codex_lanes", SOURCE)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class CodexLanesConfigTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.config = Path(self.temp.name) / "config.toml"
        self.env = patch.dict("os.environ", {"CODEX_HOME": self.temp.name})
        self.env.start()
        self.addCleanup(self.env.stop)

    def test_missing_registration_uses_explicit_codex_origin(self):
        self.config.write_text('[features.context_management]\nexperimental_mode = true\n')
        process = MagicMock()
        process.__enter__.return_value = process
        process.wait.return_value = 0
        with patch.object(module.shutil, "which", return_value="/bin/codex"), patch.object(module.subprocess, "Popen", return_value=process) as spawn:
            self.assertEqual(module.configure(), 0)
        self.assertEqual(spawn.call_args.args[0], ["/bin/codex", "mcp", "add", "pickforge-lanes", "--", "pickforge-lanes-mcp", "--origin", "codex"])
        self.assertEqual(spawn.call_args.kwargs["stdout"], subprocess.DEVNULL)
        self.assertIn("experimental_mode = true", self.config.read_text())

    def test_matching_entry_is_idempotent_and_custom_entry_is_preserved(self):
        self.config.write_text('[mcp_servers.pickforge-lanes]\ncommand="pickforge-lanes-mcp"\nargs=["--origin","codex"]\n')
        with patch.object(module.shutil, "which", return_value="/bin/codex"), patch.object(module.subprocess, "Popen") as spawn:
            self.assertEqual(module.configure(), 0)
            self.config.write_text('[mcp_servers.pickforge-lanes]\ncommand="custom"\n')
            self.assertEqual(module.configure(), 1)
            spawn.assert_not_called()
        self.assertIn('command="custom"', self.config.read_text())

    def test_missing_cli_and_failed_registration(self):
        with patch.object(module.shutil, "which", return_value=None):
            self.assertEqual(module.configure(), 0)
        process = MagicMock()
        process.__enter__.return_value = process
        process.wait.return_value = 1
        with patch.object(module.shutil, "which", return_value="/bin/codex"), patch.object(module.subprocess, "Popen", return_value=process):
            self.assertEqual(module.configure(), 1)

    def test_timeout_kills_the_process_group(self):
        process = MagicMock(pid=123)
        process.__enter__.return_value = process
        process.wait.side_effect = [subprocess.TimeoutExpired("codex", 15), 0]
        with patch.object(module.shutil, "which", return_value="/bin/codex"), patch.object(module.subprocess, "Popen", return_value=process), patch.object(module.os, "killpg") as kill:
            self.assertEqual(module.configure(), 1)
            kill.assert_called_once_with(123, module.signal.SIGKILL)


if __name__ == "__main__":
    unittest.main()
