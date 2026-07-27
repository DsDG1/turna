"""T-11: metadata-form dirty conflict hardening (needs offscreen Qt).

Covers the two real bugs:
1. Empty commits (focus in → Tab out with no change) must not push a
   same-value command onto the undo stack (fake dirty " *").
2. Undo must re-sync the detail form so a later focus-loss commit cannot
   resurrect pre-undo values.
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))
from tests._qtapp import qt_app  # noqa: E402

from PySide6.QtGui import QUndoStack  # noqa: E402

from src.backend.course_adapter import CourseAdapter  # noqa: E402
from src.widgets.metadata_form import MetadataForm  # noqa: E402


def _make_adapter() -> tuple[CourseAdapter, dict]:
    lesson = {
        "id": "l1",
        "name": "课一",
        "description": "描述一",
        "prerequisiteLessonIds": [],
    }
    unit = {
        "id": "u1",
        "name": "单元一",
        "description": "",
        "prerequisiteUnitIds": [],
        "lessons": [lesson],
    }
    section = {
        "id": "s1",
        "name": "章节一",
        "description": "",
        "prerequisiteSectionIds": [],
        "units": [unit],
    }
    adapter = CourseAdapter()
    adapter.sections = [section]
    adapter.index = {"sections": [{"id": "s1", "name": "章节一", "description": ""}]}
    return adapter, lesson


def _make_form() -> tuple[MetadataForm, QUndoStack, CourseAdapter, dict]:
    adapter, lesson = _make_adapter()
    form = MetadataForm()
    stack = QUndoStack()
    form.undo_stack = stack
    form.show_lesson(adapter, lesson)
    return form, stack, adapter, lesson


class TestEmptyCommitGuard(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.app = qt_app()

    def test_focus_loss_without_change_pushes_nothing(self) -> None:
        form, stack, _adapter, _lesson = _make_form()
        form._commit_name_desc()
        form._commit_prereqs()
        self.assertEqual(stack.count(), 0)
        self.assertTrue(stack.isClean())

    def test_real_change_pushes_once_then_noop(self) -> None:
        form, stack, _adapter, lesson = _make_form()
        form.name_edit.setText("改名")
        form._commit_name_desc()
        self.assertEqual(stack.count(), 1)
        self.assertEqual(lesson["name"], "改名")
        # Second commit with identical values must be a no-op.
        form._commit_name_desc()
        self.assertEqual(stack.count(), 1)

    def test_is_in_sync_tracks_model(self) -> None:
        form, stack, _adapter, _lesson = _make_form()
        self.assertTrue(form.is_in_sync())
        form.name_edit.setText("改名")
        form._commit_name_desc()
        self.assertTrue(form.is_in_sync())
        stack.undo()  # model reverts; widget still shows the new name
        self.assertFalse(form.is_in_sync())


class TestUndoRefill(unittest.TestCase):
    """Undo of a meta command re-syncs the detail form via MainWindow hook."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.app = qt_app()

    def test_undo_refills_form_and_focus_out_does_not_resurrect(self) -> None:
        from tests._mainwindow_fixture import build_main_window

        win = build_main_window()
        try:
            adapter, lesson = _make_adapter()
            win.adapter = adapter
            win.course_dir = Path(".")  # any truthy path: enables detail render
            win._on_node_selected(("lesson", "l1"))
            form = win.detail.form
            self.assertEqual(form.name_edit.text(), "课一")

            form.name_edit.setText("改名")
            form._commit_name_desc()
            self.assertEqual(lesson["name"], "改名")
            self.assertEqual(win.undo_stack.count(), 1)

            win.undo_stack.undo()
            self.assertEqual(lesson["name"], "课一")
            # indexChanged started the debounce timer.
            self.assertTrue(win._undo_detail_timer.isActive())
            # Form is stale until the debounced flush runs.
            self.assertFalse(form.is_in_sync())
            win._flush_undo_detail_refresh()
            self.assertEqual(form.name_edit.text(), "课一")
            self.assertEqual(form.desc_edit.toPlainText(), "描述一")

            # A focus-loss commit after the refill must not resurrect the
            # pre-undo value nor push anything.
            form._commit_name_desc()
            self.assertEqual(lesson["name"], "课一")
            self.assertEqual(win.undo_stack.count(), 1)  # the undone command
            self.assertEqual(win.undo_stack.index(), 0)  # no new push
        finally:
            win.deleteLater()


if __name__ == "__main__":
    unittest.main()
