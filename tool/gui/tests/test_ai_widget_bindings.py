"""Unit tests for AI & Widget bindings (MainWindow, Tree, GazeCursorOverlay, Status Bar)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from PySide6.QtCore import QPoint, QRect
from PySide6.QtWidgets import QApplication

from tests._qtapp import qt_app
from src.app import MainWindow


@unittest.skip("MainWindow._gaze_overlay and _on_ai_job_started retired")
class AIWidgetBindingsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls._app = qt_app()

    def setUp(self) -> None:
        self.win = MainWindow()

    def tearDown(self) -> None:
        self.win.close()

    def test_gaze_overlay_initialized(self) -> None:
        self.assertIsNotNone(self.win._gaze_overlay)

    def test_ai_job_started_and_finished_bindings(self) -> None:
        # Start AI Job
        self.win._on_ai_job_started("lesson_01", "生成课时内容")
        self.assertTrue(self.win._gaze_overlay._is_locked)
        self.assertIn("SYSTEM SOVEREIGN", self.win.statusBar().currentMessage())

        # Finish AI Job
        self.win._on_ai_job_finished("lesson_01")
        self.assertFalse(self.win._gaze_overlay._is_locked)
        self.assertIsNone(self.win._gaze_overlay._locked_rect)


if __name__ == "__main__":
    unittest.main()
