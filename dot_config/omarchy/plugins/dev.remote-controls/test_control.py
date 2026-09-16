import unittest
from unittest.mock import patch
import control


class ControlTests(unittest.TestCase):
    def test_rejects_unknown_action(self):
        with self.assertRaises(ValueError):
            control.action("kill", "0x123")

    def test_rejects_injected_address(self):
        with self.assertRaises(ValueError):
            control.action("focus", '0x123"; os.execute("bad")')

    def test_rejects_invalid_workspace(self):
        for workspace in (None, "0", "11", "2;bad"):
            with self.subTest(workspace=workspace), self.assertRaises(ValueError):
                control.action("move", "0x123", workspace)

    @patch("control.windows", return_value=[])
    @patch("control.hypr")
    def test_closed_window_is_not_dispatched(self, run, windows):
        with self.assertRaises(ValueError):
            control.action("close", "0x123")
        run.assert_not_called()

    @patch("control.windows", return_value=[{"address": "0x123"}])
    @patch("control.hypr", return_value="ok")
    def test_fullscreen_is_explicit_not_toggle(self, run, windows):
        control.action("fullscreen", "0x123")
        self.assertIn("internal = 2, client = 2", run.call_args.args[1])
        self.assertIn('window = "address:0x123"', run.call_args.args[1])

    @patch("control.windows", return_value=[{"address": "0x123"}])
    @patch("control.hypr", return_value="ok")
    def test_windowed_is_explicit(self, run, windows):
        control.action("windowed", "0x123")
        self.assertIn("internal = 0, client = 0", run.call_args.args[1])

    @patch("control.windows", return_value=[{"address": "0x123"}])
    @patch("control.hypr", return_value="ok")
    def test_move_follows_window(self, run, windows):
        control.action("move", "0x123", "10")
        self.assertIn('workspace = "10", follow = true', run.call_args.args[1])

    @patch("control.windows", return_value=[{"address": "0x123"}])
    @patch("control.hypr", return_value="ok")
    def test_close_requests_graceful_close_of_selected_window(self, run, windows):
        control.action("close", "0x123")
        command = run.call_args.args[1]
        self.assertIn('hl.dsp.window.close({ window = "address:0x123" })', command)
        self.assertNotIn("kill", command)
        self.assertNotIn("signal", command)

    @patch("control.windows", return_value=[{"address": "0x123"}])
    @patch("control.hypr", return_value="failure")
    def test_dispatch_error_is_reported(self, run, windows):
        with self.assertRaises(RuntimeError):
            control.action("focus", "0x123")


if __name__ == "__main__":
    unittest.main()
