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

from PySide6.QtGui import QUndoStack
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


def _real_lookup_adapter():
    """An adapter stub whose find_unit/find_lesson/search behave like the real
    CourseAdapter (returning the actual parent dicts), so the tree's
    _sibling_index / _move_current can locate nodes for move tests."""
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

    def find_section(section_id):
        for s in adapter.sections:
            if s.get("id") == section_id:
                return s
        raise KeyError(section_id)

    def find_unit(unit_id):
        for s in adapter.sections:
            for u in s.get("units", []):
                if u.get("id") == unit_id:
                    return s, u
        raise KeyError(unit_id)

    def find_lesson(lesson_id):
        for s in adapter.sections:
            for u in s.get("units", []):
                for l in u.get("lessons", []):
                    if l.get("id") == lesson_id:
                        return s, u, l
        raise KeyError(lesson_id)

    adapter.find_section.side_effect = find_section
    adapter.find_unit.side_effect = find_unit
    adapter.find_lesson.side_effect = find_lesson
    # move_within is a real staticmethod on CourseAdapter; the tree calls it
    # via the command classes which import CourseAdapter directly, so the mock
    # does not need to provide it.
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


class CourseTreeMoveTest(unittest.TestCase):
    def setUp(self) -> None:
        _App.get()
        self.tree = CourseTreeWidget()
        self.adapter = _real_lookup_adapter()
        self.tree.display(self.adapter)
        self.stack = QUndoStack()
        self.tree.undo_stack = self.stack

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

    def test_move_current_reorders_lessons(self) -> None:
        l1 = self._item_for("lesson", "s1-l1")
        self.tree.setCurrentItem(l1)
        self.tree._move_current(1)  # down
        ids = [l["id"] for l in self.adapter.sections[0]["units"][0]["lessons"]]
        self.assertEqual(ids, ["s1-l2", "s1-l1"])

    def test_move_current_at_bounds_is_noop(self) -> None:
        l1 = self._item_for("lesson", "s1-l1")
        self.tree.setCurrentItem(l1)
        before = [l["id"] for l in self.adapter.sections[0]["units"][0]["lessons"]]
        self.tree._move_current(-1)  # already first -> no-op
        after = [l["id"] for l in self.adapter.sections[0]["units"][0]["lessons"]]
        self.assertEqual(before, after)
        self.assertEqual(self.stack.count(), 0)

    def test_move_preserves_selection_after_refresh(self) -> None:
        l1 = self._item_for("lesson", "s1-l1")
        self.tree.setCurrentItem(l1)
        self.tree._move_current(1)
        current = self.tree.currentItem()
        self.assertIsNotNone(current)
        self.assertEqual(current.data(0, 0x0100), ("lesson", "s1-l1"))

    def test_move_buttons_enable_state(self) -> None:
        # Hold the container so it (and the reparented tree) is not GC'd.
        self._toolbar_container = self.tree.wrap_with_move_toolbar()
        l1 = self._item_for("lesson", "s1-l1")
        self.tree.setCurrentItem(l1)
        self.assertTrue(self.tree._move_down_btn.isEnabled())
        self.assertFalse(self.tree._move_up_btn.isEnabled())
        l2 = self._item_for("lesson", "s1-l2")
        self.tree.setCurrentItem(l2)
        self.assertTrue(self.tree._move_up_btn.isEnabled())
        self.assertFalse(self.tree._move_down_btn.isEnabled())


if __name__ == "__main__":
    unittest.main()