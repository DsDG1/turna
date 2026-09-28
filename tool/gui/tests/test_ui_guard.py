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

from src.application.ui_guard import (
    CANCEL,
    NO,
    YES,
    is_headless_ui,
    safe_information,
    safe_question,
    safe_question3,
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
            def showMessage(self, m, ms=0):
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


class SafeQuestion3Test(unittest.TestCase):
    """Three-way confirmations: headless and immersive-auto must not modal."""

    def test_headless_uses_auto_choice_without_modal(self) -> None:
        with patch(
            "src.application.ui_guard.is_headless_ui", return_value=True
        ), patch("PySide6.QtWidgets.QMessageBox.question") as mock_q:
            self.assertEqual(
                safe_question3(None, "t", "q", auto_choice=CANCEL), CANCEL
            )
            self.assertEqual(safe_question3(None, "t", "q", auto_choice=YES), YES)
            mock_q.assert_not_called()

    def test_default_auto_choice_is_cancel(self) -> None:
        # "Do nothing" is the only safe unattended answer for the destructive
        # prompts this helper was built for.
        with patch(
            "src.application.ui_guard.is_headless_ui", return_value=True
        ):
            self.assertEqual(safe_question3(None, "t", "q"), CANCEL)

    def test_interactive_maps_each_button(self) -> None:
        from PySide6.QtWidgets import QMessageBox

        for button, expected in (
            (QMessageBox.StandardButton.Yes, YES),
            (QMessageBox.StandardButton.No, NO),
            (QMessageBox.StandardButton.Cancel, CANCEL),
        ):
            with self.subTest(button=button), patch(
                "src.application.ui_guard.is_headless_ui", return_value=False
            ), patch(
                "src.application.ui_guard.resolve_auto_apply_state",
                return_value=(False, False, ""),
            ), patch(
                "PySide6.QtWidgets.QMessageBox.question", return_value=button
            ):
                self.assertEqual(safe_question3(None, "t", "q"), expected)

    def test_immersive_auto_uses_auto_choice_without_modal(self) -> None:
        with patch(
            "src.application.ui_guard.is_headless_ui", return_value=False
        ), patch(
            "src.application.ui_guard.resolve_auto_apply_state",
            return_value=(True, False, "tok"),
        ), patch("PySide6.QtWidgets.QMessageBox.question") as mock_q:
            self.assertEqual(
                safe_question3(None, "t", "q", auto_choice=YES), YES
            )
            self.assertEqual(
                safe_question3(None, "t", "q", auto_choice=CANCEL), CANCEL
            )
            mock_q.assert_not_called()


class NoRawModalLeftInBusinessCodeTest(unittest.TestCase):
    """Every confirmation outside ui_guard goes through the guard.

    A raw QMessageBox.question blocks a headless run and ignores the immersive
    auto-confirm scope, which is the modal that 4.8 was written to remove.
    """

    def test_only_ui_guard_uses_qmessagebox_question(self) -> None:
        import pathlib

        src = pathlib.Path(__file__).resolve().parents[1] / "src"
        offenders = []
        for path in sorted(src.rglob("*.py")):
            if path.name == "ui_guard.py":
                continue
            text = path.read_text(encoding="utf-8")
            if "QMessageBox.question(" in text:
                offenders.append(str(path.relative_to(src)))
        self.assertEqual(
            offenders,
            [],
            f"raw QMessageBox.question outside ui_guard: {offenders}",
        )

    def test_guard_itself_owns_the_two_modal_calls(self) -> None:
        import pathlib

        src = (
            pathlib.Path(__file__).resolve().parents[1]
            / "src"
            / "application"
            / "ui_guard.py"
        ).read_text(encoding="utf-8")
        self.assertEqual(src.count("QMessageBox.question("), 2)


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
