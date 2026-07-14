"""Tests for teacher_view_model pure functions (C2, no PySide6)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.teacher_view_model import (
    bool_answer_for,
    correct_index_for,
    correct_indices_for,
    expression_label,
    grammar_label,
    is_answerable,
    options_for,
    prompt_for,
    text_answer_for,
    visible_field_specs,
    word_label,
)


def _adapter():
    a = MagicMock()
    a.vocab = [{"id": "w-1", "term": "Merhaba", "translation": "Hello"}]
    a.expressions = [{"id": "e-1", "term": "Selam", "translation": "Hi"}]
    a.grammar_points = [{"id": "g-1", "title": "主谓宾"}]
    return a


class PromptTest(unittest.TestCase):
    def test_prompt_field(self) -> None:
        self.assertEqual(prompt_for({"prompt": "p?"}), "p?")

    def test_sentence_field_fallback(self) -> None:
        self.assertEqual(prompt_for({"sentence": "fill this"}), "fill this")

    def test_statement_field(self) -> None:
        self.assertEqual(prompt_for({"statement": "stmt"}), "stmt")

    def test_empty(self) -> None:
        self.assertEqual(prompt_for({}), "")


class CorrectnessTest(unittest.TestCase):
    def test_correct_index_default(self) -> None:
        self.assertEqual(correct_index_for({}), 0)

    def test_correct_index_value(self) -> None:
        self.assertEqual(correct_index_for({"correctIndex": 2}), 2)

    def test_correct_index_invalid(self) -> None:
        self.assertEqual(correct_index_for({"correctIndex": "x"}), 0)

    def test_correct_indices(self) -> None:
        self.assertEqual(correct_indices_for({"correctIndices": [0, 2]}), [0, 2])

    def test_correct_indices_filters(self) -> None:
        self.assertEqual(correct_indices_for({"correctIndices": [0, "bad", 3]}), [0, 3])

    def test_correct_indices_empty(self) -> None:
        self.assertEqual(correct_indices_for({}), [])


class AnswerTest(unittest.TestCase):
    def test_text_answer_expected(self) -> None:
        self.assertEqual(text_answer_for({"expected": "yes"}), "yes")

    def test_text_answer_fallback_answer(self) -> None:
        self.assertEqual(text_answer_for({"answer": "no"}), "no")

    def test_text_answer_fallback_expectedAnswer(self) -> None:
        self.assertEqual(text_answer_for({"expectedAnswer": "sa"}), "sa")

    def test_text_answer_empty(self) -> None:
        self.assertEqual(text_answer_for({}), "")

    def test_bool_answer(self) -> None:
        self.assertTrue(bool_answer_for({"answer": True}))
        self.assertFalse(bool_answer_for({}))


class LabelTest(unittest.TestCase):
    def test_word_label_found(self) -> None:
        self.assertEqual(word_label(_adapter(), "w-1"), "Merhaba — Hello")

    def test_word_label_missing(self) -> None:
        self.assertEqual(word_label(_adapter(), "w-x"), "w-x")

    def test_word_label_empty(self) -> None:
        self.assertEqual(word_label(_adapter(), ""), "")

    def test_expression_label(self) -> None:
        self.assertEqual(expression_label(_adapter(), "e-1"), "Selam — Hi")

    def test_grammar_label(self) -> None:
        self.assertEqual(grammar_label(_adapter(), "g-1"), "主谓宾")


class SchemaTest(unittest.TestCase):
    def test_visible_field_specs_excludes_id(self) -> None:
        names = {spec.name for spec in visible_field_specs("multipleChoice")}
        self.assertNotIn("id", names)
        self.assertNotIn("runtimeType", names)
        self.assertIn("prompt", names)

    def test_options_for(self) -> None:
        self.assertEqual(options_for({"options": ["a", "b"]}), ["a", "b"])

    def test_options_for_empty(self) -> None:
        self.assertEqual(options_for({}), [])


class AnswerableTest(unittest.TestCase):
    def test_showWord_not_answerable(self) -> None:
        self.assertFalse(is_answerable("showWord"))

    def test_multipleChoice_answerable(self) -> None:
        self.assertTrue(is_answerable("multipleChoice"))

    def test_reorderSentence_not_answerable(self) -> None:
        self.assertFalse(is_answerable("reorderSentence"))


if __name__ == "__main__":
    unittest.main()