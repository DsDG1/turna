"""Tests for shared reference option models."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from PySide6.QtCore import Qt
from PySide6.QtWidgets import QApplication, QComboBox

from src.widgets.option_models import build_options_model, select_by_id


class _QAppTestCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.app = QApplication.instance() or QApplication([])


class BuildOptionsModelTest(_QAppTestCase):
    def test_placeholder_row_zero_with_empty_data(self) -> None:
        model = build_options_model(
            [("w1", "hello — 你好")], placeholder="(未选择)"
        )
        self.assertEqual(model.rowCount(), 2)
        self.assertEqual(model.item(0, 0).text(), "(未选择)")
        self.assertEqual(
            model.item(0, 0).data(Qt.ItemDataRole.UserRole), ""
        )

    def test_option_rows_store_id_in_user_role(self) -> None:
        model = build_options_model(
            [("w1", "a"), ("w2", "b")], placeholder="(无)"
        )
        self.assertEqual(model.item(1, 0).text(), "a")
        self.assertEqual(
            model.item(1, 0).data(Qt.ItemDataRole.UserRole), "w1"
        )
        self.assertEqual(model.item(2, 0).text(), "b")
        self.assertEqual(
            model.item(2, 0).data(Qt.ItemDataRole.UserRole), "w2"
        )

    def test_items_are_not_editable(self) -> None:
        model = build_options_model([("w1", "a")], placeholder="(无)")
        for row in range(model.rowCount()):
            flags = model.item(row, 0).flags()
            self.assertFalse(flags & Qt.ItemFlag.ItemIsEditable)


class SelectByIdTest(_QAppTestCase):
    def test_selects_matching_row(self) -> None:
        model = build_options_model(
            [("w1", "a"), ("w2", "b")], placeholder="(无)"
        )
        combo = QComboBox()
        combo.setModel(model)
        select_by_id(combo, model, "w2")
        self.assertEqual(combo.currentIndex(), 2)
        self.assertEqual(combo.currentData(Qt.ItemDataRole.UserRole), "w2")

    def test_missing_id_falls_back_to_placeholder(self) -> None:
        model = build_options_model([("w1", "a")], placeholder="(无)")
        combo = QComboBox()
        combo.setModel(model)
        combo.setCurrentIndex(1)
        select_by_id(combo, model, "missing")
        self.assertEqual(combo.currentIndex(), 0)

    def test_empty_id_selects_placeholder(self) -> None:
        model = build_options_model([("w1", "a")], placeholder="(无)")
        combo = QComboBox()
        combo.setModel(model)
        combo.setCurrentIndex(1)
        select_by_id(combo, model, "")
        self.assertEqual(combo.currentIndex(), 0)


if __name__ == "__main__":
    unittest.main()
