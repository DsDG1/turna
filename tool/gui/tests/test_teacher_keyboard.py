"""R-04 teacher keyboard helpers + Dock suggestion navigation."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.teacher.keyboard import (  # noqa: E402
    next_suggestion_index,
    should_handle_suggestion_nav,
)
from tests._qtapp import _App  # noqa: E402


class NextSuggestionIndexTest(unittest.TestCase):
    def test_empty(self) -> None:
        self.assertIsNone(next_suggestion_index(None, 0, delta=1))
        self.assertIsNone(next_suggestion_index(0, 0, delta=-1))

    def test_start_none(self) -> None:
        self.assertEqual(next_suggestion_index(None, 3, delta=1), 0)
        self.assertEqual(next_suggestion_index(None, 3, delta=-1), 2)

    def test_wrap(self) -> None:
        self.assertEqual(next_suggestion_index(2, 3, delta=1), 0)
        self.assertEqual(next_suggestion_index(0, 3, delta=-1), 2)
        self.assertEqual(next_suggestion_index(1, 3, delta=1), 2)


class SuggestionNavGuardTest(unittest.TestCase):
    def setUp(self) -> None:
        _App._ensure()

    def test_editable_focus_blocks_bracket_nav(self) -> None:
        from PySide6.QtWidgets import QLineEdit

        edit = QLineEdit()
        edit.setText("hello")
        # Suggestion nav must not steal when typing.
        self.assertFalse(should_handle_suggestion_nav(edit))


class DockSuggestionNavTest(unittest.TestCase):
    def setUp(self) -> None:
        _App._ensure()

    def test_navigate_and_activate(self) -> None:
        from src.widgets.experience_dock import ExperienceDock

        dock = ExperienceDock()
        captured: list[dict] = []
        dock.suggestion_clicked.connect(lambda s: captured.append(s))
        dock.apply_suggestions(
            [
                {"title": "A", "action_id": "app.help"},
                {"title": "B", "action_id": "app.why"},
                {"title": "C", "action_id": "app.undo"},
            ]
        )
        self.assertEqual(dock.suggestion_count(), 3)
        self.assertIsNone(dock.focused_suggestion_index())
        self.assertEqual(dock.navigate_suggestions(1), 0)
        self.assertEqual(dock.navigate_suggestions(1), 1)
        self.assertEqual(dock.navigate_suggestions(-1), 0)
        self.assertTrue(dock.activate_focused_suggestion())
        self.assertEqual(len(captured), 1)
        self.assertEqual(captured[0]["action_id"], "app.help")


if __name__ == "__main__":
    unittest.main()
