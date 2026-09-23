"""Tests for W3 editor-view deepening.

Covers:
- CourseTreeWidget: search filter (name/id/teacher-label), ancestor retention,
  filter survival across rebuilds, Lucide icon assignment, drag/drop planning.
- TreeSidebar: search wiring, collapse/expand, toolbar buttons.
- DetailPanel: 编辑|预览|JSON tabs, LessonPreviewWidget embedding, JSON apply
  through the undo stack.
- ReplaceNodeDataCommand: id immutability, undo restoring old data.
"""
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from tests._course_fixture import real_adapter_with_course

from PySide6.QtGui import QUndoStack
from PySide6.QtWidgets import QAbstractItemView, QTreeWidgetItem

from src.widgets.course_tree import CourseTreeWidget
from tests._qtapp import _App


def _simple_adapter() -> MagicMock:
    adapter = MagicMock()
    adapter.sections = [
        {
            "id": "s1",
            "name": "Section One",
            "units": [
                {
                    "id": "u1",
                    "name": "Unit Alpha",
                    "lessons": [
                        {"id": "l1", "name": "Intro Lesson", "template": "intro"},
                        {"id": "l2", "name": "Practice X", "template": "practice"},
                    ],
                },
                {
                    "id": "u2",
                    "name": "Unit Beta",
                    "lessons": [
                        {"id": "l3", "name": "Reading Y", "template": "reading"},
                    ],
                },
            ],
        },
        {"id": "s2", "name": "Section Two", "units": []},
    ]

    def _find_unit(uid):
        for s in adapter.sections:
            for u in s.get("units", []):
                if u["id"] == uid:
                    return s, u
        raise KeyError(uid)

    def _find_lesson(lid):
        for s in adapter.sections:
            for u in s.get("units", []):
                for item in u.get("lessons", []):
                    if item["id"] == lid:
                        return s, u, item
        raise KeyError(lid)

    def _find_section(sid):
        for s in adapter.sections:
            if s["id"] == sid:
                return s
        raise KeyError(sid)

    adapter.find_unit = MagicMock(side_effect=_find_unit)
    adapter.find_lesson = MagicMock(side_effect=_find_lesson)
    adapter.find_section = MagicMock(side_effect=_find_section)
    return adapter


def _visible_paths(tree: CourseTreeWidget) -> list[str]:
    paths: list[str] = []

    def walk(item: QTreeWidgetItem, prefix: str) -> None:
        if not item.isHidden():
            paths.append(prefix + item.text(0))
        for i in range(item.childCount()):
            child = item.child(i)
            if child is not None:
                walk(child, prefix + item.text(0) + "/")

    for i in range(tree.topLevelItemCount()):
        top = tree.topLevelItem(i)
        if top is not None:
            walk(top, "")
    return paths


class CourseTreeFilterTest(unittest.TestCase):
    def setUp(self) -> None:
        _App.get()
        self.tree = CourseTreeWidget()
        self.adapter = _simple_adapter()
        self.tree.display(self.adapter)

    def test_filter_matches_name(self) -> None:
        self.tree.set_filter("Practice")
        paths = _visible_paths(self.tree)
        self.assertTrue(any("Practice X" in p for p in paths))
        self.assertFalse(any("Intro Lesson" in p for p in paths))

    def test_filter_keeps_ancestors(self) -> None:
        self.tree.set_filter("l3")
        paths = _visible_paths(self.tree)
        self.assertTrue(any("Section One" in p for p in paths))
        self.assertTrue(any("Unit Beta" in p for p in paths))
        self.assertTrue(any("Reading Y" in p for p in paths))
        self.assertFalse(any("Section Two" in p for p in paths))

    def test_filter_matches_id(self) -> None:
        self.tree.set_filter("u2")
        paths = _visible_paths(self.tree)
        self.assertTrue(any("Unit Beta" in p for p in paths))

    def test_filter_clear_restores_all(self) -> None:
        self.tree.set_filter("zzz-no-match")
        self.assertEqual(_visible_paths(self.tree), [])
        self.tree.set_filter("")
        self.assertGreaterEqual(len(_visible_paths(self.tree)), 7)

    def test_filter_survives_rebuild(self) -> None:
        self.tree.set_filter("Reading")
        self.tree.refresh_incremental()
        paths = _visible_paths(self.tree)
        self.assertTrue(any("Reading Y" in p for p in paths))
        self.assertFalse(any("Intro Lesson" in p for p in paths))

    def test_filter_matches_teacher_type_label(self) -> None:
        self.tree.set_teacher_mode(True)
        label_item = self.tree._id_index["l1"].text(1)
        self.tree.set_filter(label_item)
        paths = _visible_paths(self.tree)
        self.assertTrue(any("Intro Lesson" in p for p in paths))


class CourseTreeIconTest(unittest.TestCase):
    def setUp(self) -> None:
        _App.get()
        self.tree = CourseTreeWidget()
        self.tree.display(_simple_adapter())

    def test_items_have_icons(self) -> None:
        for nid in ("s1", "u1", "l1"):
            item = self.tree._id_index[nid]
            self.assertFalse(item.icon(0).isNull(), nid)

    def test_icon_cache_populated(self) -> None:
        self.assertIsNotNone(CourseTreeWidget._section_icon)
        self.assertIsNotNone(CourseTreeWidget._unit_icon)
        self.assertIsNotNone(CourseTreeWidget._lesson_icon)


class CourseTreeDropPlanTest(unittest.TestCase):
    def setUp(self) -> None:
        _App.get()
        self.tree = CourseTreeWidget()
        self.adapter = _simple_adapter()
        self.tree.display(self.adapter)
        self.pos = QAbstractItemView.DropIndicatorPosition

    def test_lesson_onto_unit_reparents(self) -> None:
        plan = self.tree._drop_plan(
            ("lesson", "l1"), self.tree._id_index["u2"], self.pos.OnItem
        )
        self.assertIsNotNone(plan)
        self.assertEqual(plan[0], "reparent_lesson")
        self.assertEqual(plan[2], "u2")

    def test_lesson_below_lesson_reorders(self) -> None:
        plan = self.tree._drop_plan(
            ("lesson", "l1"), self.tree._id_index["l2"], self.pos.BelowItem
        )
        self.assertIsNotNone(plan)
        self.assertEqual(plan[0], "move_or_reparent_lesson")

    def test_lesson_onto_section_rejected(self) -> None:
        self.assertIsNone(
            self.tree._drop_plan(
                ("lesson", "l1"), self.tree._id_index["s2"], self.pos.OnItem
            )
        )

    def test_unit_onto_section_reparents(self) -> None:
        plan = self.tree._drop_plan(
            ("unit", "u1"), self.tree._id_index["s2"], self.pos.OnItem
        )
        self.assertIsNotNone(plan)
        self.assertEqual(plan[0], "reparent_unit")

    def test_section_above_section_reorders(self) -> None:
        plan = self.tree._drop_plan(
            ("section", "s2"), self.tree._id_index["s1"], self.pos.AboveItem
        )
        self.assertIsNotNone(plan)
        self.assertEqual(plan[0], "move_section")

    def test_self_drop_rejected(self) -> None:
        self.assertIsNone(
            self.tree._drop_plan(
                ("lesson", "l1"), self.tree._id_index["l1"], self.pos.OnItem
            )
        )

    def test_drop_onto_own_descendant_rejected(self) -> None:
        self.assertIsNone(
            self.tree._drop_plan(
                ("section", "s1"), self.tree._id_index["u1"], self.pos.OnItem
            )
        )

    def test_internal_move_enabled(self) -> None:
        self.assertEqual(
            self.tree.dragDropMode(), QAbstractItemView.DragDropMode.InternalMove
        )


class TreeSidebarTest(unittest.TestCase):
    def setUp(self) -> None:
        _App.get()
        from src.widgets.tree_sidebar import TreeSidebar

        self.tree = CourseTreeWidget()
        self.adapter = _simple_adapter()
        self.tree.display(self.adapter)
        self.sidebar = TreeSidebar(self.tree)

    def test_search_wires_to_tree_filter(self) -> None:
        self.sidebar.search.setText("Practice")
        self.assertEqual(self.tree._filter_text, "practice")
        paths = _visible_paths(self.tree)
        self.assertTrue(any("Practice X" in p for p in paths))

    def test_collapse_expand_all(self) -> None:
        self.sidebar._expand_all()
        self.assertTrue(self.tree._id_index["s1"].isExpanded())
        self.sidebar._collapse_all()
        self.assertFalse(self.tree._id_index["s1"].isExpanded())

    def test_has_move_buttons(self) -> None:
        names = [
            self.sidebar.new_btn,
            self.sidebar.move_up_btn,
            self.sidebar.move_down_btn,
            self.sidebar.collapse_btn,
            self.sidebar.expand_btn,
        ]
        for btn in names:
            self.assertIsNotNone(btn)


class ReplaceNodeDataCommandTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        _App.get()

    def setUp(self) -> None:
        self.adapter, self.tmp = real_adapter_with_course(prefix="turna_w3cmd_")
        self.stack = QUndoStack()
        for s in self.adapter.sections:
            for u in s.get("units", []):
                for item in u.get("lessons", []):
                    self.lesson_id = item["id"]
                    break
                else:
                    continue
                break
            else:
                continue
            break
        self.unit_id = self.adapter.find_lesson(self.lesson_id)[1]["id"]
        self.section_id = self.adapter.find_lesson(self.lesson_id)[0]["id"]

    def tearDown(self) -> None:
        import shutil

        shutil.rmtree(self.tmp, ignore_errors=True)

    def _make(self, kind: str, node_id: str, data: dict):
        from src.application.commands import ReplaceNodeDataCommand

        return ReplaceNodeDataCommand(self.adapter, kind, node_id, data)

    def test_id_change_rejected(self) -> None:
        with self.assertRaises(ValueError):
            self._make("lesson", self.lesson_id, {"id": "different", "name": "x"})

    def test_missing_id_rejected(self) -> None:
        with self.assertRaises(ValueError):
            self._make("unit", self.unit_id, {"name": "no id"})

    def test_lesson_replace_and_undo(self) -> None:
        _s, _u, lesson = self.adapter.find_lesson(self.lesson_id)
        new_data = dict(lesson)
        new_data["name"] = "RENAMED-BY-JSON"
        cmd = self._make("lesson", self.lesson_id, new_data)
        self.stack.push(cmd)
        _s2, _u2, after = self.adapter.find_lesson(self.lesson_id)
        self.assertEqual(after["name"], "RENAMED-BY-JSON")
        self.stack.undo()
        _s3, _u3, restored = self.adapter.find_lesson(self.lesson_id)
        self.assertEqual(restored["name"], lesson["name"])

    def test_section_replace_and_undo(self) -> None:
        section = self.adapter.find_section(self.section_id)
        old_name = section["name"]
        new_data = dict(section)
        new_data["name"] = "SEC-JSON"
        self.stack.push(self._make("section", self.section_id, new_data))
        self.assertEqual(self.adapter.find_section(self.section_id)["name"], "SEC-JSON")
        self.stack.undo()
        self.assertEqual(self.adapter.find_section(self.section_id)["name"], old_name)

    def test_unit_replace_and_undo(self) -> None:
        _s, unit = self.adapter.find_unit(self.unit_id)
        old_name = unit["name"]
        new_data = dict(unit)
        new_data["name"] = "UNIT-JSON"
        self.stack.push(self._make("unit", self.unit_id, new_data))
        self.assertEqual(self.adapter.find_unit(self.unit_id)[1]["name"], "UNIT-JSON")
        self.stack.undo()
        self.assertEqual(self.adapter.find_unit(self.unit_id)[1]["name"], old_name)

    def test_exported_from_package(self) -> None:
        import src.application.commands as pkg

        self.assertIn("ReplaceNodeDataCommand", pkg.__all__)
        self.assertTrue(hasattr(pkg, "ReplaceNodeDataCommand"))


class DetailPanelW3Test(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        _App.get()

    def setUp(self) -> None:
        from src.widgets.detail_panel import DetailPanel

        self.adapter, self.tmp = real_adapter_with_course(prefix="turna_w3dp_")
        self.detail = DetailPanel()
        self.detail.undo_stack = QUndoStack()
        self.section = self.adapter.sections[0]
        self.unit = self.section["units"][0]
        self.lesson = self.unit["lessons"][0]

    def tearDown(self) -> None:
        import shutil

        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_three_tabs_exist(self) -> None:
        tabs = self.detail.detail_tabs
        self.assertEqual(tabs.count(), 3)
        self.assertEqual(tabs.tabText(0), "编辑")
        self.assertEqual(tabs.tabText(1), "预览")
        self.assertEqual(tabs.tabText(2), "JSON")

    def test_legacy_attributes_preserved(self) -> None:
        for attr in (
            "breadcrumb",
            "title",
            "form",
            "content_host",
            "content_layout",
            "view_header",
            "kind_pill",
            # W4: collapsible metadata header replaces the inner splitter.
            "meta_toggle",
        ):
            self.assertTrue(hasattr(self.detail, attr), attr)
        self.assertFalse(hasattr(self.detail, "splitter"), "inner splitter removed in W4")

    def test_show_lesson_sets_context_and_header(self) -> None:
        self.detail.show_node(self.adapter, ("lesson", self.lesson["id"]))
        self.assertIsNotNone(self.detail._node_context)
        self.assertEqual(self.detail._node_context[1], "lesson")
        self.assertIn(self.lesson["name"], self.detail.view_header.title())

    def test_node_switch_resets_to_edit_tab(self) -> None:
        self.detail.show_node(self.adapter, ("lesson", self.lesson["id"]))
        self.detail.detail_tabs.setCurrentIndex(2)
        self.detail.show_node(self.adapter, ("unit", self.unit["id"]))
        self.assertEqual(self.detail.detail_tabs.currentIndex(), 0)

    def test_preview_tab_empty_for_non_lesson(self) -> None:
        self.detail.show_node(self.adapter, ("section", self.section["id"]))
        self.detail._render_preview_tab()
        from src.widgets.ui.containers import EmptyState

        widget = self.detail._preview_layout.itemAt(0).widget()
        self.assertIsInstance(widget, EmptyState)

    def test_preview_tab_builds_for_lesson(self) -> None:
        self.detail.show_node(self.adapter, ("lesson", self.lesson["id"]))
        self.detail._render_preview_tab()
        from PySide6.QtWidgets import QScrollArea

        widget = self.detail._preview_layout.itemAt(0).widget()
        self.assertIsInstance(widget, QScrollArea)
        from src.teacher.preview_window import LessonPreviewWidget

        self.assertIsInstance(widget.widget(), LessonPreviewWidget)

    def test_json_tab_populates_and_apply_undo(self) -> None:
        self.detail.show_node(self.adapter, ("lesson", self.lesson["id"]))
        self.detail._render_json_tab()
        data = self.detail.json_editor.to_json()
        self.assertEqual(data["id"], self.lesson["id"])

        old_name = self.lesson["name"]
        data["name"] = "JSON-APPLIED"
        self.detail.json_editor.set_json(data)
        self.detail._apply_json()
        _s, _u, after = self.adapter.find_lesson(self.lesson["id"])
        self.assertEqual(after["name"], "JSON-APPLIED")

        self.detail.undo_stack.undo()
        _s2, _u2, restored = self.adapter.find_lesson(self.lesson["id"])
        self.assertEqual(restored["name"], old_name)

    def test_apply_json_rejects_id_change(self) -> None:
        self.detail.show_node(self.adapter, ("lesson", self.lesson["id"]))
        self.detail._render_json_tab()
        data = self.detail.json_editor.to_json()
        data["id"] = "hijacked"
        self.detail.json_editor.set_json(data)
        before = dict(self.adapter.find_lesson(self.lesson["id"])[2])
        self.detail._apply_json()
        _s, _u, after = self.adapter.find_lesson(self.lesson["id"])
        self.assertEqual(after, before)
        self.assertEqual(self.detail.undo_stack.count(), 0)

    def test_apply_json_rejects_malformed(self) -> None:
        self.detail.show_node(self.adapter, ("lesson", self.lesson["id"]))
        self.detail._render_json_tab()
        self.detail.json_editor.setPlainText("{ not json !!!")
        self.detail._apply_json()
        self.assertEqual(self.detail.undo_stack.count(), 0)

    def test_apply_json_rejects_non_object(self) -> None:
        self.detail.show_node(self.adapter, ("lesson", self.lesson["id"]))
        self.detail._render_json_tab()
        self.detail.json_editor.setPlainText("[1, 2, 3]")
        self.detail._apply_json()
        self.assertEqual(self.detail.undo_stack.count(), 0)


class DetailPanelW4CollapseTest(unittest.TestCase):
    """W4: collapsible 属性 section + segmented 蓝图/高级编辑 toggle."""

    @classmethod
    def setUpClass(cls) -> None:
        _App.get()

    def setUp(self) -> None:
        from src.widgets.detail_panel import DetailPanel

        self.adapter, self.tmp = real_adapter_with_course(prefix="turna_w4dp_")
        self.detail = DetailPanel()
        self.detail.undo_stack = QUndoStack()
        self.section = self.adapter.sections[0]
        self.unit = self.section["units"][0]
        self.lesson = self.unit["lessons"][0]
        # Hermetic QSettings store for collapse-memory persistence.
        store: dict = {}
        qs = MagicMock()
        qs.value = lambda key, default=None: store.get(key, default)
        qs.setValue = lambda key, value: store.__setitem__(key, value)
        self._qs_store = store
        self._qs_patch = patch(
            "src.widgets.detail_panel.QSettings", return_value=qs
        )
        self._qs_patch.start()
        self.addCleanup(self._qs_patch.stop)

    def tearDown(self) -> None:
        import shutil

        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_lesson_metadata_collapsed_by_default(self) -> None:
        self.detail.show_node(self.adapter, ("lesson", self.lesson["id"]))
        self.assertFalse(self.detail.form.isVisibleTo(self.detail.content_host.parentWidget()))

    def test_section_metadata_expanded_by_default(self) -> None:
        self.detail.show_node(self.adapter, ("section", self.section["id"]))
        self.assertTrue(self.detail.form.isVisibleTo(self.detail))

    def test_toggle_flips_visibility_and_persists_per_kind(self) -> None:
        self.detail.show_node(self.adapter, ("lesson", self.lesson["id"]))
        self.detail._on_meta_toggle_clicked()  # expand
        self.assertTrue(self.detail.form.isVisibleTo(self.detail))
        self.assertEqual(self._qs_store["edit/meta_collapsed_lesson"], False)
        # Re-selecting the same lesson keeps the expanded choice.
        self.detail.show_node(self.adapter, ("lesson", self.lesson["id"]))
        self.assertTrue(self.detail.form.isVisibleTo(self.detail))
        # Sections keep their own (default expanded) state.
        self.detail.show_node(self.adapter, ("section", self.section["id"]))
        self.assertTrue(self.detail.form.isVisibleTo(self.detail))

    def test_reveal_metadata_expands_for_rename(self) -> None:
        self.detail.show_node(self.adapter, ("lesson", self.lesson["id"]))
        self.assertFalse(self.detail.form.isVisibleTo(self.detail))
        self.detail.reveal_metadata()
        self.assertTrue(self.detail.form.isVisibleTo(self.detail))

    def test_lesson_view_toggle_is_segmented(self) -> None:
        self.detail.show_node(self.adapter, ("lesson", self.lesson["id"]))
        bp, adv = self.detail._blueprint_btn, self.detail._advanced_btn
        self.assertEqual(bp.objectName(), "LessonViewToggle")
        self.assertEqual(adv.objectName(), "LessonViewToggle")
        self.assertNotEqual(bp.isChecked(), adv.isChecked())
        adv.click()
        self.assertTrue(adv.isChecked())
        self.assertFalse(bp.isChecked())


class LessonPreviewWidgetTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        _App.get()

    def setUp(self) -> None:
        self.adapter, self.tmp = real_adapter_with_course(prefix="turna_w3pv_")

    def tearDown(self) -> None:
        import shutil

        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_iter_preview_items_shared(self) -> None:
        from src.teacher.preview_window import iter_preview_items

        lesson = {
            "content": {
                "stages": [{"items": [{"type": "a"}, {"type": "b"}]}, {"items": [{"type": "c"}]}]
            }
        }
        items = list(iter_preview_items(lesson))
        self.assertEqual(len(items), 3)

    def test_widget_empty_lesson_shows_state(self) -> None:
        from src.teacher.preview_window import LessonPreviewWidget

        w = LessonPreviewWidget(self.adapter, {"id": "x", "name": "Empty", "content": {}})
        self.assertIsNotNone(w.layout())
        self.assertGreater(w.layout().count(), 0)


if __name__ == "__main__":
    unittest.main()
