"""R-06 (v4.51): 词表「高级 ▾」→「复现不足的词 → 一键练习」（复用 K-08）。

Bridges the course-level vocab view to section-level ``evaluate_unit_spiral``:
no gaps → statusBar hint; gaps → dispatch ``unit.spiral_vocab`` for the
section with the most unsurfaced words.
"""
from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from tests._qtapp import qt_app  # noqa: E402


def _section(sid: str, terms: list[str]) -> dict:
    """Section where every word is introduced (showWord) but never practiced."""
    words = [{"id": f"{sid}-w{i}", "term": t} for i, t in enumerate(terms)]
    intro_items = [
        {"runtimeType": "showWord", "id": f"{sid}-intro-{i}", "wordId": w["id"]}
        for i, w in enumerate(words)
    ]
    practice_items = [
        {
            "runtimeType": "multipleChoice",
            "id": f"{sid}-mcq",
            "prompt": "unrelated prompt",
            "options": ["x", "y"],
            "correctIndex": 0,
        }
    ]
    return {
        "id": sid,
        "words": words,
        "units": [
            {
                "id": f"{sid}-u1",
                "lessons": [
                    {
                        "id": f"{sid}-l1",
                        "content": {
                            "stages": [{"id": f"{sid}-s1", "items": intro_items}]
                        },
                    },
                    {
                        "id": f"{sid}-l2",
                        "content": {
                            "stages": [{"id": f"{sid}-s2", "items": practice_items}]
                        },
                    },
                ],
            }
        ],
    }


class VocabSpiralEntryTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        qt_app()

    def _table(self, sections: list[dict]):
        from PySide6.QtWidgets import QDialog, QMainWindow

        from src.backend.course_adapter import CourseAdapter
        from src.teacher.vocab_table import VocabTableWidget

        host = QMainWindow()
        self.addCleanup(host.deleteLater)
        host.experience_metrics = SimpleNamespace()  # type: ignore[attr-defined]
        dlg = QDialog(host)
        table = VocabTableWidget(CourseAdapter(), dlg)
        table.adapter = SimpleNamespace(sections=sections)  # type: ignore[assignment]
        return host, table

    def test_menu_entry_exists(self) -> None:
        _, table = self._table([])
        self.assertEqual(table.spiral_action.text(), "复现不足的词 → 一键练习")

    def test_no_gaps_reports_via_statusbar_without_dispatch(self) -> None:
        host, table = self._table([_section("sec-a", [])])
        with patch(
            "src.application.experience_dispatch.dispatch_experience_action"
        ) as disp:
            table._on_spiral_vocab()
        self.assertEqual(disp.call_count, 0)
        self.assertIn("未发现", host.statusBar().currentMessage())

    def test_dispatches_section_with_most_gaps(self) -> None:
        sections = [
            _section("sec-a", ["apple"]),
            _section("sec-b", ["banana", "cherry"]),
        ]
        host, table = self._table(sections)
        with patch(
            "src.application.experience_dispatch.dispatch_experience_action"
        ) as disp:
            table._on_spiral_vocab()
        self.assertEqual(disp.call_count, 1)
        args = disp.call_args.args
        self.assertIs(args[0], host)
        self.assertEqual(
            args[1],
            {"action_id": "unit.spiral_vocab", "scope": {"section_id": "sec-b"}},
        )


if __name__ == "__main__":
    unittest.main()
