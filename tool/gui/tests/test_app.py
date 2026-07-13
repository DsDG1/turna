"""Tests for the main application window behavior."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

from PySide6.QtCore import QSettings
from PySide6.QtGui import QCloseEvent
from PySide6.QtWidgets import QApplication, QMessageBox

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.app import MainWindow  # noqa: E402
from src.backend.course_adapter import SaveResult  # noqa: E402


class _TestApp:
    _app: QApplication | None = None

    @classmethod
    def get(cls) -> QApplication:
        if cls._app is None:
            cls._app = QApplication.instance() or QApplication([])
        return cls._app


def _build_main_window() -> MainWindow:
    """Create a MainWindow with QSettings and recent-repo prompts suppressed."""
    fake_settings = MagicMock()
    fake_settings.value.return_value = "[]"
    with patch("src.app.QSettings", return_value=fake_settings):
        return MainWindow()


class CloseEventTest(unittest.TestCase):
    def setUp(self) -> None:
        _TestApp.get()
        self.win = _build_main_window()
        self.win.course_dir = Path("/tmp/fake-course")
        self.adapter = MagicMock()
        self.win.adapter = self.adapter

    def test_no_changes_accepts_close(self) -> None:
        self.adapter.detect_changes.return_value = {
            "index": False,
            "sections": False,
            "vocab": False,
            "expressions": False,
            "grammar_points": False,
        }
        event = QCloseEvent()
        with patch.object(QMessageBox, "question") as mock_question:
            self.win.closeEvent(event)
            mock_question.assert_not_called()
        self.assertTrue(event.isAccepted())

    def test_dirty_save_accepts_close(self) -> None:
        self.adapter.detect_changes.return_value = {"index": True}
        self.adapter.save.return_value = SaveResult(ok=True)
        event = QCloseEvent()
        with patch.object(QMessageBox, "question", return_value=QMessageBox.StandardButton.Save):
            self.win.closeEvent(event)
        self.adapter.save.assert_called_once()
        self.assertTrue(event.isAccepted())

    def test_dirty_discard_accepts_close(self) -> None:
        self.adapter.detect_changes.return_value = {"vocab": True}
        event = QCloseEvent()
        with patch.object(
            QMessageBox, "question", return_value=QMessageBox.StandardButton.Discard
        ):
            self.win.closeEvent(event)
        self.adapter.save.assert_not_called()
        self.assertTrue(event.isAccepted())

    def test_dirty_cancel_ignores_close(self) -> None:
        self.adapter.detect_changes.return_value = {"sections": True}
        event = QCloseEvent()
        with patch.object(
            QMessageBox, "question", return_value=QMessageBox.StandardButton.Cancel
        ):
            self.win.closeEvent(event)
        self.adapter.save.assert_not_called()
        self.assertFalse(event.isAccepted())

    def test_dirty_save_failure_ignores_close_and_warns(self) -> None:
        self.adapter.detect_changes.return_value = {"index": True}
        self.adapter.save.return_value = SaveResult(
            ok=False, errors=[{"level": "error", "message": "bad"}]
        )
        event = QCloseEvent()
        with patch.object(QMessageBox, "question", return_value=QMessageBox.StandardButton.Save):
            with patch.object(QMessageBox, "warning") as mock_warning:
                self.win.closeEvent(event)
        self.assertFalse(event.isAccepted())
        mock_warning.assert_called_once()


if __name__ == "__main__":
    unittest.main()
