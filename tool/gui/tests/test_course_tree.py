"""Tests for CourseTreeWidget incremental refresh (A1).

Covers state preservation across refresh: expand/selection for sections,
units, lessons, and fallback to parent when the selected node is deleted.
PySide6 is required (run locally, not in the sandbox).
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from PySide6.QtWidgets import QApplication

from src.widgets.course_tree import CourseTreeWidget


class _App:
    _app: QApplication | None = None

    @classmethod
    def get(cls) -> QApplication:
        if cls._app is None:
            cls._app = QApplication.instance() or QApplication([])
        return cls._app


def _adapter_with_data():
    adapter = MagicMock()
    adapter.sections = [
        {
            "id": "section1",
            "name": "Section 1",
            "units": [
                {
                    "id": "u-1",
                    "name": "Unit 1",
                    "lessons": [
                        {"id": "s1-l1", "name": "Lesson 1", "template": "intro"},
                        {"id": "s1-l2", "name": "Lesson 2", "template": "practice"},
                    ],
                },
                {
                    "id": "u-2",
                    "name": "Unit 2",
                    "lessons": [],
                },
            ],
        },
        {
            "id": "section2",
            "name": "Section 2",
            "units": [],
        },
    ]
    return adapter


class CourseTreeIncrementalTest(unittest.TestCase):
    def setUp(self) -> None:
        _App.get()
        self.tree = CourseTreeWidget()
        self.adapter = _adapter_with_data()
        self.tree.display(self.adapter)

    def _item_for(self, kind: str, node_id: str):
        for top_idx in range(self.tree.topLevelItemCount()):
            top = self.tree.topLevelItem(top_idx)
            ref = top.data(0, 0x0100)
            if ref == (kind, node_id):
                return top
            for i in range(top.childCount()):
                child = top.child(i)
                cref = child.data(0, 0x0100)
                if cref == (kind, node_id):
                    return child
                for j in range(child.childCount()):
                    grand = child.child(j)
                    gref = grand.data(0, 0x0100)
                    if gref == (kind, node_id):
                        return grand
        return None

    def test_initial_display_builds_three_levels(self) -> None:
        self.assertGreaterEqual(self.tree.topLevelItemCount(), 2)
        s1 = self._item_for("section", "section1")
        self.assertIsNotNone(s1)
        self.assertEqual(s1.childCount(), 2)
        u1 = self._item_for("unit", "u-1")
        self.assertEqual(u1.childCount(), 2)

    def test_refresh_preserves_expanded_sections(self) -> None:
        s2 = self._item_for("section", "section2")
        s2.setExpanded(True)
        u2 = self._item_for("unit", "u-2")
        u2.setExpanded(True)
        self.tree.refresh()
        self.assertTrue(self._item_for("section", "section2").isExpanded())
        self.assertTrue(self._item_for("unit", "u-2").isExpanded())

    def test_refresh_preserves_selection(self) -> None:
        u1 = self._item_for("unit", "u-1")
        self.tree.setCurrentItem(u1)
        self.tree.refresh()
        current = self.tree.currentItem()
        self.assertIsNotNone(current)
        self.assertEqual(current.data(0, 0x0100), ("unit", "u-1"))

    def test_refresh_falls_back_to_parent_when_selected_lesson_deleted(self) -> None:
        l2 = self._item_for("lesson", "s1-l2")
        self.tree.setCurrentItem(l2)
        self.adapter.sections[0]["units"][0]["lessons"] = [
            {"id": "s1-l1", "name": "Lesson 1", "template": "intro"},
        ]
        self.tree.refresh()
        current = self.tree.currentItem()
        self.assertIsNotNone(current)
        ref = current.data(0, 0x0100)
        self.assertEqual(ref[0], "unit")
        self.assertEqual(ref[1], "u-1")

    def test_refresh_clears_selection_when_parent_also_gone(self) -> None:
        u2 = self._item_for("unit", "u-2")
        self.tree.setCurrentItem(u2)
        self.adapter.sections[0]["units"] = [
            self.adapter.sections[0]["units"][0]
        ]
        self.tree.refresh()
        self.assertIsNone(self.tree.currentItem())

    def test_refresh_incremental_with_no_adapter_is_noop(self) -> None:
        tree = CourseTreeWidget()
        tree.refresh_incremental()
        self.assertEqual(tree.topLevelItemCount(), 0)


if __name__ == "__main__":
    unittest.main()