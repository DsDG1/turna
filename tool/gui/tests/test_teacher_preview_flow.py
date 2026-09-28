"""T-6 preview flow fixes: verdict alignment, scroll, submit guards.

#17/#18/#19: true/false verdicts must match the editor (missing answer =
False), the try-it dialog must scroll for long lessons, and submitting
without a selection / without a reference answer must say so instead of
issuing a wrong verdict.
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

from PySide6.QtWidgets import QPushButton, QRadioButton, QScrollArea

from src.backend.course_adapter import CourseAdapter
from src.teacher.preview_window import LessonPreviewDialog, _PreviewCard
from tests._qtapp import _App


def _lesson(items_by_type: dict[str, list[dict]]) -> dict:
    items: list[dict] = []
    for rt, its in items_by_type.items():
        for it in its:
            merged = {"runtimeType": rt}
            merged.update(it)
            items.append(merged)
    return {
        "id": "l-preview",
        "name": "Preview Lesson",
        "content": {"stages": [{"id": "st1", "name": "S", "items": items}]},
    }


def _submit_buttons(card: _PreviewCard) -> list[QPushButton]:
    return [b for b in card.findChildren(QPushButton) if b.text() == "提交"]


def _status_text(card: _PreviewCard) -> str:
    # The inline status label is the card's last QLabel added by the builder.
    labels = [
        lbl.text()
        for lbl in card.findChildren(
            __import__("PySide6.QtWidgets", fromlist=["QLabel"]).QLabel
        )
        if lbl.text()
    ]
    return labels[-1] if labels else ""


class TrueFalseVerdictTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        _App.get()

    def _card(self, item: dict) -> tuple[_PreviewCard, LessonPreviewDialog]:
        adapter = CourseAdapter()
        dlg = LessonPreviewDialog(adapter, _lesson({"readingTrueFalse": [item]}))
        cards = dlg.findChildren(_PreviewCard)
        self.assertEqual(len(cards), 1)
        return cards[0], dlg

    def test_missing_answer_defaults_to_false_like_editor(self) -> None:
        card, dlg = self._card({"statement": "S"})
        radios = card.findChildren(QRadioButton)
        with patch(
            "src.teacher.preview_window.QMessageBox.information"
        ) as info:
            radios[0].setChecked(True)  # user picks 正确
            _submit_buttons(card)[0].click()
            info.assert_called_once()
            self.assertIn("正确答案", info.call_args.args[2])
            self.assertIn("错误", info.call_args.args[2])
        dlg.deleteLater()

    def test_unselected_submit_hints_instead_of_judging(self) -> None:
        card, dlg = self._card({"statement": "S", "answer": True})
        with patch("src.teacher.preview_window.QMessageBox.information") as info:
            _submit_buttons(card)[0].click()
            info.assert_not_called()
            self.assertIn("请先选择答案", card.statusTip() or _status_text(card))
        dlg.deleteLater()

    def test_missing_answer_hint_shown_in_editor(self) -> None:
        # #17 companion: the editor card flags the unset answer explicitly.
        from src.backend.lesson_content import default_interaction
        from src.teacher.question_cards import QuestionCard

        item = default_interaction("readingTrueFalse")
        item.pop("answer", None)
        card = QuestionCard(CourseAdapter(), item)
        texts = [
            lbl.text()
            for lbl in card.findChildren(
                __import__("PySide6.QtWidgets", fromlist=["QLabel"]).QLabel
            )
        ]
        self.assertTrue(any("未设置答案" in t for t in texts))


class SubmitGuardsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        _App.get()

    def test_single_choice_without_selection_hints(self) -> None:
        adapter = CourseAdapter()
        dlg = LessonPreviewDialog(
            adapter,
            _lesson(
                {"multipleChoice": [{"prompt": "P", "options": ["A", "B"], "correctIndex": 0}]}
            ),
        )
        card = dlg.findChildren(_PreviewCard)[0]
        with patch("src.teacher.preview_window.QMessageBox.information") as info:
            _submit_buttons(card)[0].click()
            info.assert_not_called()
            self.assertIn("请先选择答案", _status_text(card))
        dlg.deleteLater()

    def test_text_answer_without_reference_cannot_judge(self) -> None:
        adapter = CourseAdapter()
        dlg = LessonPreviewDialog(
            adapter,
            _lesson(
                {"translateSentence": [{"source": "hello", "expected": ""}]}
            ),
        )
        card = dlg.findChildren(_PreviewCard)[0]
        with patch("src.teacher.preview_window.QMessageBox.information") as info:
            _submit_buttons(card)[0].click()
            info.assert_not_called()
            self.assertIn("未提供参考答案", _status_text(card))
        dlg.deleteLater()


class PreviewScrollTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        _App.get()

    def test_long_lesson_lives_in_a_scroll_area(self) -> None:
        items = [
            {"prompt": f"Q{i}", "options": ["A", "B"], "correctIndex": 0}
            for i in range(20)
        ]
        dlg = LessonPreviewDialog(CourseAdapter(), _lesson({"multipleChoice": items}))
        scroll = dlg.findChild(QScrollArea)
        self.assertIsNotNone(scroll)
        self.assertTrue(scroll.widgetResizable())
        self.assertEqual(dlg.minimumWidth(), 480)
        self.assertEqual(dlg.minimumHeight(), 400)
        # All 20 cards are present inside the scroll host.
        self.assertEqual(len(scroll.findChildren(_PreviewCard)), 20)
        dlg.deleteLater()


if __name__ == "__main__":
    unittest.main()
