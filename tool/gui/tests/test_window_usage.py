"""Tests for the WindowUsageMixin (window.open + window.duration)."""
from __future__ import annotations

import json
import os
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from PySide6.QtWidgets import QDialog  # noqa: E402

from src.infrastructure import operations_log  # noqa: E402
from src.infrastructure import window_usage as wu_mod  # noqa: E402
from src.infrastructure.telemetry import Telemetry  # noqa: E402
from src.infrastructure.window_usage import WindowUsageMixin  # noqa: E402
from tests._qtapp import _App  # noqa: E402


class _SampleWindow(WindowUsageMixin, QDialog):
    def __init__(self) -> None:
        super().__init__()
        self.setWindowTitle("SampleWindow")


class WindowUsageTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="varnamala_winuse_"))
        self.log_file = self.tmp / "operations.log"
        self._orig_ops = operations_log.operations
        self.ops = Telemetry(self.log_file)
        operations_log.operations = self.ops
        wu_mod.operations = self.ops

    def tearDown(self) -> None:
        wu_mod.operations = operations_log.operations
        operations_log.operations = self._orig_ops
        self.ops.close()
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _lines(self) -> list[dict]:
        return [json.loads(l) for l in self.log_file.read_text(encoding="utf-8").splitlines() if l.strip()]

    def test_show_and_close_records_open_and_duration(self) -> None:
        app = _App.get()
        win = _SampleWindow()
        win.show()
        app.processEvents()
        win.close()
        app.processEvents()

        events = [l["event"] for l in self._lines()]
        self.assertIn("ui.window.open", events)
        self.assertIn("window.duration", events)
        duration_records = [l for l in self._lines() if l["event"] == "window.duration"]
        self.assertTrue(duration_records)
        self.assertGreaterEqual(duration_records[-1]["duration_ms"], 0.0)
        self.assertEqual(duration_records[-1]["payload"]["window"], "SampleWindow")

    def test_subclass_with_own_closeevent_still_records_duration(self) -> None:
        class _WithClose(WindowUsageMixin, QDialog):
            def __init__(self) -> None:
                super().__init__()
                self.setWindowTitle("WithClose")
                self.closed = False

            def closeEvent(self, event) -> None:  # noqa: N802
                self.closed = True
                super().closeEvent(event)

        app = _App.get()
        win = _WithClose()
        win.show()
        app.processEvents()
        win.close()
        app.processEvents()

        self.assertTrue(win.closed)
        events = [l["event"] for l in self._lines()]
        self.assertIn("window.duration", events)


if __name__ == "__main__":
    unittest.main()