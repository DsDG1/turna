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
from tests._course_fixture import real_adapter_with_course  # noqa: E402

from PySide6.QtCore import Qt
from PySide6.QtGui import QColor, QUndoStack

from src.widgets.course_tree import CourseTreeWidget
from tests._qtapp import _App  # noqa: E402


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


def _real_adapter_with_course():
    """A real CourseAdapter loaded from the Turkish course for keyboard
    integration tests (duplicate/delete/move actually mutate the tree)."""
    return real_adapter_with_course(prefix="turna_tree_kb_")


class CourseTreeKeyboardTest(unittest.TestCase):
    """Keyboard shortcuts + multi-select (workshop2 P1)."""

    def setUp(self) -> None:
        _App.get()
        self.adapter, self.tmp = _real_adapter_with_course()
        self.tree = CourseTreeWidget()
        self.tree.undo_stack = QUndoStack()
        self.tree.display(self.adapter)
        # Pick the first lesson in the course for selection-based tests.
        for section in self.adapter.sections:
            for unit in section.get("units", []):
                for lesson in unit.get("lessons", []):
                    self.first_lesson_id = lesson["id"]
                    self.unit_id = unit["id"]
                    break
                if hasattr(self, "first_lesson_id"):
                    break
            if hasattr(self, "first_lesson_id"):
                break

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

    def _select_single(self, item) -> None:
        self.tree.clearSelection()
        self.tree.setCurrentItem(item)
        item.setSelected(True)

    def _unit_lesson_count(self) -> int:
        _s, unit = self.adapter.find_unit(self.unit_id)
        return len(unit.get("lessons", []))

    def _press(self, key, mods=Qt.KeyboardModifier.NoModifier) -> None:
        from PySide6.QtCore import QEvent
        from PySide6.QtGui import QKeyEvent

        ev = QKeyEvent(QEvent.Type.KeyPress, key, mods)
        self.tree.keyPressEvent(ev)

    def test_ctrl_d_duplicates_selected_lesson(self) -> None:
        item = self._item_for("lesson", self.first_lesson_id)
        self._select_single(item)
        before = self._unit_lesson_count()
        self._press(Qt.Key.Key_D, Qt.KeyboardModifier.ControlModifier)
        self.assertEqual(self._unit_lesson_count(), before + 1)

    def test_ctrl_down_moves_lesson_down(self) -> None:
        # Need at least 2 lessons in the unit for a move to take effect.
        _s, unit, _l = self.adapter.find_lesson(self.first_lesson_id)
        lessons = unit.get("lessons", [])
        if len(lessons) < 2:
            self.skipTest("need >=2 lessons in unit for move test")
        first_id = lessons[0]["id"]
        item = self._item_for("lesson", first_id)
        self._select_single(item)
        self._press(Qt.Key.Key_Down, Qt.KeyboardModifier.ControlModifier)
        _s2, unit2, _l2 = self.adapter.find_lesson(first_id)
        ids = [l["id"] for l in unit2.get("lessons", [])]
        self.assertEqual(ids[1], first_id)

    def test_f2_emits_rename_requested(self) -> None:
        captured: list[tuple] = []
        self.tree.rename_requested.connect(lambda k, i: captured.append((k, i)))
        item = self._item_for("lesson", self.first_lesson_id)
        self._select_single(item)
        self._press(Qt.Key.Key_F2)
        self.assertEqual(captured, [("lesson", self.first_lesson_id)])

    def test_delete_single_lesson(self) -> None:
        from unittest.mock import patch

        from PySide6.QtWidgets import QMessageBox

        item = self._item_for("lesson", self.first_lesson_id)
        self._select_single(item)
        before = self._unit_lesson_count()
        with patch.object(QMessageBox, "question", return_value=QMessageBox.StandardButton.Yes):
            self._press(Qt.Key.Key_Delete)
        self.assertEqual(self._unit_lesson_count(), before - 1)

    def test_extended_selection_mode_enabled(self) -> None:
        from PySide6.QtWidgets import QTreeWidget

        self.assertEqual(
            self.tree.selectionMode(), QTreeWidget.SelectionMode.ExtendedSelection
        )


class CourseTreeBulkTest(unittest.TestCase):
    """Tree-level bulk-operation wiring (workshop2 P5)."""

    def setUp(self) -> None:
        _App.get()
        self.adapter, self.tmp = _real_adapter_with_course()
        self.tree = CourseTreeWidget()
        self.stack = QUndoStack()
        self.tree.undo_stack = self.stack
        self.tree.display(self.adapter)
        # Collect a source lesson + a different target unit.
        self.lesson_id = None
        self.source_unit = None
        self.target_unit = None
        for section in self.adapter.sections:
            for unit in section.get("units", []):
                if unit.get("lessons"):
                    if self.lesson_id is None:
                        self.lesson_id = unit["lessons"][0]["id"]
                        self.source_unit = unit["id"]
                elif self.target_unit is None and unit["id"] != self.source_unit:
                    self.target_unit = unit["id"]
                if self.lesson_id and self.target_unit:
                    break
            if self.lesson_id and self.target_unit:
                break
        if self.target_unit is None:
            self.skipTest("course needs a second empty unit for bulk-move test")

    def test_bulk_move_via_tree_pushes_command_and_undo_restores(self) -> None:
        from unittest.mock import patch

        _s, src_unit, _l = self.adapter.find_lesson(self.lesson_id)
        before = len(src_unit.get("lessons", []))
        with patch.object(self.tree, "_pick_target_unit", return_value=self.target_unit):
            self.tree._bulk_move_lessons([self.lesson_id])
        # Lesson now lives in the target unit.
        _s2, t_unit, _l2 = self.adapter.find_unit(self.target_unit)
        self.assertIn(self.lesson_id, [l["id"] for l in t_unit.get("lessons", [])])
        # Source unit lost it.
        _s3, src_unit2, _l3 = self.adapter.find_unit(self.source_unit)
        self.assertNotIn(self.lesson_id, [l["id"] for l in src_unit2.get("lessons", [])])
        # Undo restores.
        self.stack.undo()
        _s4, src_unit4, _l4 = self.adapter.find_unit(self.source_unit)
        self.assertIn(self.lesson_id, [l["id"] for l in src_unit4.get("lessons", [])])
        self.assertEqual(len(src_unit4.get("lessons", [])), before)

    def test_bulk_apply_preset_via_tree(self) -> None:
        from unittest.mock import patch

        from PySide6.QtWidgets import QMessageBox

        from src.backend.lesson_presets import FUNCTIONAL_PRESETS

        with patch.object(self.tree, "_pick_target_unit", return_value=None), \
                patch("PySide6.QtWidgets.QInputDialog.getItem",
                      return_value=(f"{FUNCTIONAL_PRESETS[0].label}（{FUNCTIONAL_PRESETS[0].template}）", True)), \
                patch.object(QMessageBox, "question", return_value=QMessageBox.StandardButton.Yes):
            self.tree._bulk_apply_preset([self.lesson_id])
        _s, _u, lesson = self.adapter.find_lesson(self.lesson_id)
        self.assertEqual(lesson["template"], FUNCTIONAL_PRESETS[0].template)
        self.stack.undo()
        # Undo restores something (template reverts to original).
        self.stack.redo()


class CourseTreeTeacherModeTest(unittest.TestCase):
    def setUp(self) -> None:
        _App.get()
        self.tree = CourseTreeWidget()
        self.adapter = _adapter_with_data()
        self.tree.display(self.adapter)

    def _lesson_item(self, lesson_id: str):
        for top_idx in range(self.tree.topLevelItemCount()):
            top = self.tree.topLevelItem(top_idx)
            for i in range(top.childCount()):
                unit = top.child(i)
                for j in range(unit.childCount()):
                    lesson = unit.child(j)
                    if lesson.data(0, 0x0100) == ("lesson", lesson_id):
                        return lesson
        return None

    def test_expert_mode_shows_raw_template_text(self) -> None:
        lesson = self._lesson_item("s1-l1")
        self.assertIsNotNone(lesson)
        self.assertEqual(lesson.text(1), "lesson (intro)")

    def test_teacher_mode_shows_friendly_badge(self) -> None:
        self.tree.set_teacher_mode(True)
        lesson = self._lesson_item("s1-l1")
        self.assertIsNotNone(lesson)
        self.assertEqual(lesson.text(1), "认识新词")

    def test_teacher_mode_blanks_section_unit_type(self) -> None:
        self.tree.set_teacher_mode(True)
        section = self.tree.topLevelItem(0)
        self.assertEqual(section.text(1), "")
        self.assertEqual(section.child(0).text(1), "")

    def test_teacher_mode_colors_lesson_badge(self) -> None:
        from src.backend.lesson_content import TEMPLATE_COLORS

        self.tree.set_teacher_mode(True)
        lesson = self._lesson_item("s1-l1")
        expected = QColor(TEMPLATE_COLORS["intro"]).name()
        self.assertEqual(lesson.foreground(1).color().name(), expected)


def _cross_tree_lookup_adapter():
    """Adapter stub with real find/delete behavior for cross-tree move tests.

    Layout:
      section1: u-1 [l1a, l1b], u-2 [l2a]
      section2: u-3 [l3a]
    """
    adapter = MagicMock()
    adapter.sections = [
        {"id": "section1", "name": "Section 1", "units": [
            {"id": "u-1", "name": "Unit 1", "lessons": [
                {"id": "l1a", "name": "L1a", "template": "intro"},
                {"id": "l1b", "name": "L1b", "template": "practice"},
            ]},
            {"id": "u-2", "name": "Unit 2", "lessons": [
                {"id": "l2a", "name": "L2a", "template": "intro"},
            ]},
        ]},
        {"id": "section2", "name": "Section 2", "units": [
            {"id": "u-3", "name": "Unit 3", "lessons": [
                {"id": "l3a", "name": "L3a", "template": "intro"},
            ]},
        ]},
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

    def delete_lesson(lesson_id):
        for s in adapter.sections:
            for u in s.get("units", []):
                lessons = u.get("lessons", [])
                for i, l in enumerate(lessons):
                    if l.get("id") == lesson_id:
                        del lessons[i]
                        return
        raise KeyError(lesson_id)

    def delete_unit(unit_id):
        for s in adapter.sections:
            units = s.get("units", [])
            for i, u in enumerate(units):
                if u.get("id") == unit_id:
                    del units[i]
                    return
        raise KeyError(unit_id)

    adapter.find_section.side_effect = find_section
    adapter.find_unit.side_effect = find_unit
    adapter.find_lesson.side_effect = find_lesson
    adapter.delete_lesson.side_effect = delete_lesson
    adapter.delete_unit.side_effect = delete_unit
    return adapter


class CourseTreeCrossTreeMoveTest(unittest.TestCase):
    """Cross-tree move: lessons cross units/sections, units cross sections,
    when an up/down move hits a sibling boundary (free-move)."""

    def setUp(self) -> None:
        _App.get()
        self.tree = CourseTreeWidget()
        self.adapter = _cross_tree_lookup_adapter()
        self.tree.display(self.adapter)
        self.stack = QUndoStack()
        self.tree.undo_stack = self.stack

    def _item_for(self, kind: str, node_id: str):
        for top_idx in range(self.tree.topLevelItemCount()):
            top = self.tree.topLevelItem(top_idx)
            if top.data(0, 0x0100) == (kind, node_id):
                return top
            for i in range(top.childCount()):
                child = top.child(i)
                if child.data(0, 0x0100) == (kind, node_id):
                    return child
                for j in range(child.childCount()):
                    grand = child.child(j)
                    if grand.data(0, 0x0100) == (kind, node_id):
                        return grand
        return None

    def _unit_lesson_ids(self, unit_id):
        _s, unit = self.adapter.find_unit(unit_id)
        return [l["id"] for l in unit.get("lessons", [])]

    def _section_unit_ids(self, section_id):
        s = self.adapter.find_section(section_id)
        return [u["id"] for u in s.get("units", [])]

    def test_lesson_crosses_unit_down(self):
        # l1b is the last lesson of u-1; down crosses into u-2 at the top.
        item = self._item_for("lesson", "l1b")
        self.tree.setCurrentItem(item)
        self.tree._move_current(1)
        self.assertEqual(self._unit_lesson_ids("u-1"), ["l1a"])
        self.assertEqual(self._unit_lesson_ids("u-2"), ["l1b", "l2a"])

    def test_lesson_crosses_section_down(self):
        # l2a is the last lesson of section1; down crosses into section2/u-3.
        item = self._item_for("lesson", "l2a")
        self.tree.setCurrentItem(item)
        self.tree._move_current(1)
        self.assertEqual(self._unit_lesson_ids("u-2"), [])
        self.assertEqual(self._unit_lesson_ids("u-3"), ["l2a", "l3a"])

    def test_lesson_crosses_unit_up(self):
        # l2a is the first lesson of u-2; up crosses into u-1 at the end.
        item = self._item_for("lesson", "l2a")
        self.tree.setCurrentItem(item)
        self.tree._move_current(-1)
        self.assertEqual(self._unit_lesson_ids("u-1"), ["l1a", "l1b", "l2a"])
        self.assertEqual(self._unit_lesson_ids("u-2"), [])

    def test_unit_crosses_section_down(self):
        # u-2 is the last unit of section1; down crosses into section2 at top.
        item = self._item_for("unit", "u-2")
        self.tree.setCurrentItem(item)
        self.tree._move_current(1)
        self.assertEqual(self._section_unit_ids("section1"), ["u-1"])
        self.assertEqual(self._section_unit_ids("section2"), ["u-2", "u-3"])

    def test_unit_crosses_section_up(self):
        # u-3 is the first unit of section2; up crosses into section1 at end.
        item = self._item_for("unit", "u-3")
        self.tree.setCurrentItem(item)
        self.tree._move_current(-1)
        self.assertEqual(self._section_unit_ids("section1"), ["u-1", "u-2", "u-3"])
        self.assertEqual(self._section_unit_ids("section2"), [])

    def test_first_lesson_up_is_noop(self):
        item = self._item_for("lesson", "l1a")
        self.tree.setCurrentItem(item)
        before = self._unit_lesson_ids("u-1")
        self.tree._move_current(-1)
        self.assertEqual(self._unit_lesson_ids("u-1"), before)
        self.assertEqual(self.stack.count(), 0)

    def test_last_lesson_down_is_noop(self):
        item = self._item_for("lesson", "l3a")
        self.tree.setCurrentItem(item)
        before = self._unit_lesson_ids("u-3")
        self.tree._move_current(1)
        self.assertEqual(self._unit_lesson_ids("u-3"), before)
        self.assertEqual(self.stack.count(), 0)

    def test_undo_reverses_cross_tree_lesson_move(self):
        item = self._item_for("lesson", "l1b")
        self.tree.setCurrentItem(item)
        self.tree._move_current(1)  # l1b -> u-2
        self.assertEqual(self._unit_lesson_ids("u-2"), ["l1b", "l2a"])
        self.stack.undo()
        self.assertEqual(self._unit_lesson_ids("u-1"), ["l1a", "l1b"])
        self.assertEqual(self._unit_lesson_ids("u-2"), ["l2a"])

    def test_undo_reverses_cross_tree_unit_move(self):
        item = self._item_for("unit", "u-2")
        self.tree.setCurrentItem(item)
        self.tree._move_current(1)  # u-2 -> section2
        self.assertEqual(self._section_unit_ids("section2"), ["u-2", "u-3"])
        self.stack.undo()
        self.assertEqual(self._section_unit_ids("section1"), ["u-1", "u-2"])
        self.assertEqual(self._section_unit_ids("section2"), ["u-3"])

if __name__ == "__main__":
    unittest.main()