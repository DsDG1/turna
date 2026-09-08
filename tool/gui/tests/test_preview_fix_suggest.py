"""R-05 (v4.51): 试做答错 → 可选「获取 AI 改题建议」入口（默认关）。

Covers the ``_PreviewCard.answered_wrong`` signal (wrong only), the
LessonPreviewDialog suggest bar gated by ``experience_preview_fix_suggest``,
and the fixed instruction constant fed into ``run_item_chip``.
"""
from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from tests._qtapp import qt_app  # noqa: E402


def _lesson() -> dict:
    return {
        "id": "l-1",
        "name": "Lesson 1",
        "content": {
            "stages": [
                {
                    "id": "st-1",
                    "name": "Stage 1",
                    "items": [
                        {
                            "runtimeType": "fillBlank",
                            "id": "i-1",
                            "prompt": "Fill: cat",
                            "answer": "cat",
                        }
                    ],
                }
            ]
        },
    }


class PreviewCardWrongSignalTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        qt_app()

    def _card(self, item: dict):
        from src.backend.course_adapter import CourseAdapter
        from src.teacher.preview_window import _PreviewCard

        return _PreviewCard(CourseAdapter(), item, stage={"id": "st-1"})

    def _answer(self, card, text: str) -> list:
        from PySide6.QtWidgets import QLineEdit, QPushButton

        got: list = []
        card.answered_wrong.connect(got.append)
        edit = card.findChildren(QLineEdit)[0]
        btn = card.findChildren(QPushButton)[0]
        edit.setText(text)
        with patch("src.teacher.preview_window.QMessageBox"):
            btn.click()
        return got

    def test_wrong_answer_emits_item_and_stage(self) -> None:
        item = {"runtimeType": "fillBlank", "id": "i-1", "prompt": "p", "answer": "cat"}
        card = self._card(item)
        got = self._answer(card, "dog")
        self.assertEqual(len(got), 1)
        # Signal(dict) copies across the Qt boundary — compare by value.
        self.assertEqual(got[0]["item"], item)
        self.assertEqual(got[0]["stage"], {"id": "st-1"})

    def test_correct_answer_does_not_emit(self) -> None:
        item = {"runtimeType": "fillBlank", "id": "i-1", "prompt": "p", "answer": "cat"}
        card = self._card(item)
        self.assertEqual(self._answer(card, "cat"), [])


class PreviewFixSuggestBarTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        qt_app()

    def _dialog(self):
        from src.backend.course_adapter import CourseAdapter
        from src.teacher.preview_window import LessonPreviewDialog

        dlg = LessonPreviewDialog(CourseAdapter(), _lesson())
        self.addCleanup(dlg.deleteLater)
        return dlg

    def test_bar_hidden_by_default_and_when_setting_off(self) -> None:
        dlg = self._dialog()
        self.assertTrue(dlg._fix_bar.isHidden())
        with patch(
            "src.teacher.preview_window._preview_fix_suggest_enabled",
            return_value=False,
        ):
            dlg._on_card_answered_wrong({"item": {"id": "i-1"}, "stage": {"id": "st-1"}})
        self.assertTrue(dlg._fix_bar.isHidden())

    def test_bar_shows_when_setting_on(self) -> None:
        dlg = self._dialog()
        with patch(
            "src.teacher.preview_window._preview_fix_suggest_enabled",
            return_value=True,
        ):
            dlg._on_card_answered_wrong(
                {
                    "item": {"id": "i-1", "runtimeType": "fillBlank"},
                    "stage": {"id": "st-1"},
                }
            )
        self.assertFalse(dlg._fix_bar.isHidden())

    def test_click_runs_chip_with_fixed_instruction(self) -> None:
        from src.teacher.preview_window import PREVIEW_FIX_INSTRUCTION

        dlg = self._dialog()
        payload = {"item": {"id": "i-1"}, "stage": {"id": "st-1"}}
        with patch(
            "src.teacher.preview_window._preview_fix_suggest_enabled",
            return_value=True,
        ):
            dlg._on_card_answered_wrong(payload)
        with patch("src.teacher.item_ai_chip.run_item_chip") as run:
            dlg._on_fix_suggest_clicked()
        self.assertEqual(run.call_count, 1)
        kwargs = run.call_args.kwargs
        self.assertEqual(kwargs["instruction"], PREVIEW_FIX_INSTRUCTION)
        self.assertIs(kwargs["item"], payload["item"])
        self.assertIs(kwargs["stage"], payload["stage"])
        self.assertEqual(kwargs["lesson_id"], "l-1")

    def test_refresh_reuses_layout_single(self) -> None:
        """refresh() must not create a second QVBoxLayout on the dialog.

        Regression for the Qt warning "Attempting to add QLayout to
        LessonPreviewDialog which already has a layout": refresh() previously
        called _build(), which re-ran ``QVBoxLayout(self)``.
        """
        dlg = self._dialog()
        layout_before = dlg.layout()
        dlg.refresh()
        layout_after = dlg.layout()
        self.assertIs(layout_before, layout_after, "refresh must reuse the same layout")


if __name__ == "__main__":
    unittest.main()
