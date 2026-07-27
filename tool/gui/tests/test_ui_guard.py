"""v4.46 ui_guard: headless detection + safe message boxes."""
from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.application.ui_guard import (  # noqa: E402
    is_headless_ui,
    safe_information,
    safe_question,
    safe_warning,
)


class IsHeadlessUiTest(unittest.TestCase):
    def test_offscreen_is_headless(self) -> None:
        # Default CI platform is offscreen.
        self.assertTrue(is_headless_ui())

    def test_none_app_is_headless(self) -> None:
        with patch("PySide6.QtWidgets.QApplication.instance", return_value=None):
            self.assertTrue(is_headless_ui())

    def test_xcb_not_headless(self) -> None:
        app = MagicMock()
        app.platformName.return_value = "xcb"
        with patch("PySide6.QtWidgets.QApplication.instance", return_value=app):
            self.assertFalse(is_headless_ui())


class SafeMessageBoxTest(unittest.TestCase):
    def test_safe_information_headless_uses_status(self) -> None:
        host = SimpleNamespace()
        msgs: list[str] = []

        class SB:
            def showMessage(self, m, ms=0):  # noqa: N802
                msgs.append(m)

        host.statusBar = lambda: SB()  # type: ignore[method-assign]
        with patch(
            "src.application.ui_guard.is_headless_ui", return_value=True
        ), patch("PySide6.QtWidgets.QMessageBox.information") as mock_info:
            safe_information(host, "T", "hello")
            mock_info.assert_not_called()
        self.assertTrue(any("hello" in m for m in msgs))

    def test_safe_warning_headless_no_modal(self) -> None:
        with patch(
            "src.application.ui_guard.is_headless_ui", return_value=True
        ), patch("PySide6.QtWidgets.QMessageBox.warning") as mock_w:
            safe_warning(None, "T", "w")
            mock_w.assert_not_called()

    def test_safe_question_headless_default_yes(self) -> None:
        with patch(
            "src.application.ui_guard.is_headless_ui", return_value=True
        ), patch("PySide6.QtWidgets.QMessageBox.question") as mock_q:
            self.assertTrue(safe_question(None, "t", "q", default_yes=True))
            self.assertFalse(safe_question(None, "t", "q", default_yes=False))
            mock_q.assert_not_called()

    def test_safe_question_interactive_calls_qt(self) -> None:
        from PySide6.QtWidgets import QMessageBox

        with patch(
            "src.application.ui_guard.is_headless_ui", return_value=False
        ), patch(
            "PySide6.QtWidgets.QMessageBox.question",
            return_value=QMessageBox.StandardButton.Yes,
        ) as mock_q:
            self.assertTrue(safe_question(None, "t", "q", default_yes=False))
            mock_q.assert_called_once()


class GoalControllerDelegatesTest(unittest.TestCase):
    def test_goal_is_headless_delegates(self) -> None:
        from src.application import goal_controller as gc

        with patch(
            "src.application.ui_guard.is_headless_ui", return_value=True
        ) as mock:
            self.assertTrue(gc._is_headless_ui())
            mock.assert_called()


if __name__ == "__main__":
    unittest.main()
