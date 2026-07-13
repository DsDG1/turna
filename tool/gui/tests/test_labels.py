"""Tests for the teacher-view label mapping (guiplan §15.2, T.1).

Guards against mapping/contract drift (§15.15): every runtimeType and template
in the contract must have a teaching-language label.
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.lesson_content import (  # noqa: E402
    ALLOWED_RUNTIME_TYPES,
    CONTENT_BY_TEMPLATE,
)
from src.i18n import labels  # noqa: E402


class LabelsTest(unittest.TestCase):
    def test_every_runtime_type_has_label(self) -> None:
        for rt in ALLOWED_RUNTIME_TYPES:
            self.assertIn(rt, labels.INTERACTION_LABELS, f"missing label for {rt}")
            self.assertTrue(labels.interaction_label(rt))

    def test_every_template_has_label(self) -> None:
        for tpl in CONTENT_BY_TEMPLATE:
            self.assertIn(tpl, labels.TEMPLATE_LABELS, f"missing label for {tpl}")
            self.assertTrue(labels.template_label(tpl))

    def test_field_label_returns_string(self) -> None:
        self.assertEqual(labels.field_label("wordId"), "词")
        self.assertEqual(labels.field_label("correctIndex"), "正确答案")
        self.assertEqual(labels.field_label("unknown_field"), "unknown_field")

    def test_hidden_fields_cover_engineering_only(self) -> None:
        self.assertTrue(labels.is_hidden("id"))
        self.assertTrue(labels.is_hidden("runtimeType"))
        self.assertFalse(labels.is_hidden("wordId"))
        self.assertFalse(labels.is_hidden("prompt"))


if __name__ == "__main__":
    unittest.main()
