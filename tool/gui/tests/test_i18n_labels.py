"""T22: teacher-facing labels.

Two things this locks down:
- the English mirror tables are gone (they were unreachable from any
  settings entry, CLI flag or caller);
- the reorder-sentence card reads its two field captions from
  field_label() instead of inline literals, so the wording cannot drift
  away from the rest of the teacher view.
"""
from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

import src.i18n.labels as labels
from src.i18n.labels import field_label, layer_label
from tests._qtapp import _App


class NoDeadEnglishTablesTest(unittest.TestCase):
    def test_en_tables_no_longer_exist(self) -> None:
        for name in (
            "FIELD_LABELS_EN",
            "NESTED_LAYER_LABELS_EN",
            "LEVEL_LABELS_EN",
        ):
            self.assertFalse(
                hasattr(labels, name), f"{name} should have been removed"
            )

    def test_module_no_longer_wires_an_en_locale(self) -> None:
        src = (_GUI / "src" / "i18n" / "labels.py").read_text(encoding="utf-8")
        # The only remaining mention of the removed tables is the comment
        # explaining why they are gone; no code path may register "en".
        code = [
            line
            for line in src.splitlines()
            if line.strip() and not line.strip().startswith("#")
        ]
        self.assertFalse([ln for ln in code if '"en":' in ln])

    def test_unknown_locale_falls_back_to_zh(self) -> None:
        # The locale parameter stays so a future locale setting has a home,
        # but anything unknown still resolves to the shipped Chinese labels.
        self.assertEqual(
            field_label("front", locale="en"), field_label("front", locale="zh")
        )
        self.assertEqual(field_label("front", locale="fr"), field_label("front"))


class LabelLookupTest(unittest.TestCase):
    def test_known_field_has_a_human_label(self) -> None:
        for field in ("scrambled", "correct", "options", "answer", "explanation"):
            with self.subTest(field=field):
                label = field_label(field)
                self.assertNotEqual(label, field)
                self.assertTrue(label.strip())

    def test_unknown_field_returns_itself(self) -> None:
        self.assertEqual(field_label("no_such_field"), "no_such_field")

    def test_layer_label_lookup(self) -> None:
        self.assertEqual(layer_label("no_such_layer"), "no_such_layer")


class ReorderSentenceCardLabelsTest(unittest.TestCase):
    """The card captions must come from the shared table, not literals."""

    @classmethod
    def setUpClass(cls) -> None:
        _App.get()

    def _card_labels(self):
        from PySide6.QtWidgets import QLabel

        from src.backend.course_adapter import CourseAdapter
        from src.backend.lesson_content import default_interaction
        from src.teacher.question_cards import QuestionCard

        item = default_interaction("reorderSentence")
        item["scrambled"] = ["a", "b"]
        item["correct"] = ["b", "a"]
        card = QuestionCard(CourseAdapter(), item)
        self.addCleanup(card.deleteLater)
        return [lbl.text() for lbl in card.findChildren(QLabel)]

    def test_card_shows_the_shared_labels(self) -> None:
        labels_seen = self._card_labels()
        self.assertIn(field_label("scrambled"), labels_seen)
        self.assertIn(field_label("correct"), labels_seen)

    def test_card_builder_has_no_inline_cjk_literal_captions(self) -> None:
        # Encoding-safe version of "no hardcoded wording": the builder must
        # not pass any quoted CJK string to QLabel.
        import re

        src = (_GUI / "src" / "teacher" / "question_cards.py").read_text(
            encoding="utf-8"
        )
        body = src.split("def _build_reorder_sentence", 1)[1].split("\n    def ", 1)[0]
        self.assertIsNone(
            re.search(r'QLabel\(\s*["\'][^"\']*[一-鿿]', body),
            "reorder-sentence captions must come from field_label()",
        )


if __name__ == "__main__":
    unittest.main()
