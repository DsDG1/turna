"""Tests for teacher view QuestionCard widgets."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

from PySide6.QtGui import QStandardItemModel
from PySide6.QtWidgets import QApplication, QComboBox, QLabel, QPushButton

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.course_adapter import CourseAdapter  # noqa: E402
from src.backend.lesson_content import ALLOWED_RUNTIME_TYPES, default_interaction  # noqa: E402
from src.teacher.question_cards import QuestionCard, _OptionRow  # noqa: E402
from src.widgets.option_models import build_options_model  # noqa: E402


class _TestApp:
    _app: QApplication | None = None

    @classmethod
    def get(cls) -> QApplication:
        if cls._app is None:
            cls._app = QApplication.instance() or QApplication([])
        return cls._app


class OptionRowTest(unittest.TestCase):
    def test_option_row_holds_selector_and_edit(self) -> None:
        _TestApp.get()
        row = _OptionRow("opt", True, exclusive=True)
        self.assertTrue(row.selector.isChecked())
        self.assertEqual(row.edit.text(), "opt")


class SingleChoiceSyncTest(unittest.TestCase):
    def setUp(self) -> None:
        _TestApp.get()
        self.adapter = CourseAdapter()
        self.item = default_interaction("multipleChoice")
        self.item["options"] = ["A", "B", "C", "D"]
        self.item["correctIndex"] = 0
        self.card = QuestionCard(self.adapter, self.item)

    def test_initial_correct_index_selected(self) -> None:
        rows = self.card.findChildren(_OptionRow)
        self.assertEqual(len(rows), 4)
        self.assertTrue(rows[0].selector.isChecked())
        self.assertFalse(rows[1].selector.isChecked())

    def test_switching_radio_updates_correct_index(self) -> None:
        rows = self.card.findChildren(_OptionRow)
        rows[2].selector.setChecked(True)
        self.assertEqual(self.item["correctIndex"], 2)

    def test_editing_option_text_updates_item(self) -> None:
        rows = self.card.findChildren(_OptionRow)
        rows[1].edit.setText("B-modified")
        self.assertEqual(self.item["options"][1], "B-modified")

    def test_add_option_appends_and_rebuilds(self) -> None:
        # Locate add button by text.
        add_btn = None
        for btn in self.card.findChildren(QPushButton):
            if btn.text() == "+ 添加选项":
                add_btn = btn
                break
        self.assertIsNotNone(add_btn)
        add_btn.click()
        rows = self.card.findChildren(_OptionRow)
        self.assertEqual(len(rows), 5)
        self.assertEqual(len(self.item["options"]), 5)


class MultiSelectSyncTest(unittest.TestCase):
    def setUp(self) -> None:
        _TestApp.get()
        self.adapter = CourseAdapter()
        self.item = default_interaction("multiSelect")
        self.item["options"] = ["A", "B", "C", "D"]
        self.item["correctIndices"] = [0, 2]
        self.card = QuestionCard(self.adapter, self.item)

    def test_initial_correct_indices_checked(self) -> None:
        rows = self.card.findChildren(_OptionRow)
        self.assertTrue(rows[0].selector.isChecked())
        self.assertFalse(rows[1].selector.isChecked())
        self.assertTrue(rows[2].selector.isChecked())

    def test_toggling_checkbox_updates_correct_indices(self) -> None:
        rows = self.card.findChildren(_OptionRow)
        rows[0].selector.setChecked(False)
        rows[1].selector.setChecked(True)
        self.assertEqual(set(self.item["correctIndices"]), {1, 2})

    def test_editing_option_text_updates_item(self) -> None:
        rows = self.card.findChildren(_OptionRow)
        rows[3].edit.setText("D-modified")
        self.assertEqual(self.item["options"][3], "D-modified")


class GrammarPointComboTest(unittest.TestCase):
    def setUp(self) -> None:
        _TestApp.get()
        self.adapter = CourseAdapter()
        self.adapter.grammar_points = [
            {"id": "g-1", "title": "Grammar 1"},
            {"id": "g-2", "title": "Grammar 2"},
        ]

    def test_all_runtime_types_expose_grammar_combo(self) -> None:
        for rt in ALLOWED_RUNTIME_TYPES:
            item = default_interaction(rt)
            card = QuestionCard(self.adapter, item)
            labels = [lbl.text() for lbl in card.findChildren(QLabel)]
            # The grammar combo is preceded by a label with the field name.
            self.assertTrue(
                any("grammarPointId" in text or "语法点" in text for text in labels),
                f"runtimeType {rt} missing grammarPointId label",
            )

    def test_grammar_selection_updates_item(self) -> None:
        item = default_interaction("multipleChoice")
        item["options"] = ["A", "B"]
        card = QuestionCard(self.adapter, item)
        combos = card.findChildren(QComboBox)
        # The grammar combo contains grammar point ids.
        grammar_combo = None
        for combo in combos:
            for i in range(combo.count()):
                data = combo.itemData(i)
                if data in ("g-1", "g-2", ""):
                    grammar_combo = combo
                    break
            if grammar_combo is not None:
                break
        self.assertIsNotNone(grammar_combo)
        idx = grammar_combo.findData("g-1")
        self.assertGreaterEqual(idx, 0)
        grammar_combo.setCurrentIndex(idx)
        self.assertEqual(item.get("grammarPointId"), "g-1")


class SharedModelTest(unittest.TestCase):
    def setUp(self) -> None:
        _TestApp.get()
        self.adapter = CourseAdapter()
        self.adapter.vocab = [
            {"id": "w-1", "term": "hello", "translation": "你好"},
            {"id": "w-2", "term": "world", "translation": "世界"},
        ]
        self.adapter.grammar_points = [
            {"id": "g-1", "title": "Grammar 1"},
        ]
        self.vocab_model = build_options_model(
            self.adapter.vocab_options(), placeholder="(未选择)"
        )
        self.grammar_model = build_options_model(
            self.adapter.grammar_options(), placeholder="(未关联)"
        )

    def test_shared_vocab_model_is_used_when_passed(self) -> None:
        item = default_interaction("showWord")
        card = QuestionCard(
            self.adapter,
            item,
            vocab_model=self.vocab_model,
            grammar_model=self.grammar_model,
        )
        combos = card.findChildren(QComboBox)
        word_combo = None
        for combo in combos:
            if combo.model() is self.vocab_model:
                word_combo = combo
                break
        self.assertIsNotNone(word_combo)
        self.assertEqual(word_combo.model().rowCount(), 3)  # placeholder + 2 words

    def test_multiple_cards_share_the_same_model(self) -> None:
        item1 = default_interaction("showWord")
        item2 = default_interaction("showWord")
        card1 = QuestionCard(
            self.adapter,
            item1,
            vocab_model=self.vocab_model,
            grammar_model=self.grammar_model,
        )
        card2 = QuestionCard(
            self.adapter,
            item2,
            vocab_model=self.vocab_model,
            grammar_model=self.grammar_model,
        )
        shared_models = set()
        for card in (card1, card2):
            for combo in card.findChildren(QComboBox):
                model = combo.model()
                if model in (self.vocab_model, self.grammar_model):
                    shared_models.add(model)
        self.assertEqual(len(shared_models), 2)
        self.assertIn(self.vocab_model, shared_models)
        self.assertIn(self.grammar_model, shared_models)


if __name__ == "__main__":
    unittest.main()
