"""Tests for WorkshopWindow (unified canvas IA)."""
from __future__ import annotations

import json
import os
import sys
import tempfile
import unittest
import unittest.mock
from pathlib import Path

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from PySide6.QtCore import QSettings  # noqa: E402
from PySide6.QtWidgets import QMessageBox  # noqa: E402

from src.backend.import_step_result import ImportStepResult  # noqa: E402
from src.backend.knowledge_schema import coerce_knowledge_points  # noqa: E402
from src.backend.markdown_chopper import split_chapters  # noqa: E402
from src.backend.textbook_project import TextbookProject  # noqa: E402
from src.backend.textbook_project_store import TextbookProjectStore  # noqa: E402
from src.dialogs.workshop_window import WorkshopWindow  # noqa: E402
from tests._qtapp import _App  # noqa: E402


def _sample_md() -> str:
    return "## 1 Merhaba\nhello\n"


def _make_source(tmp: str) -> Path:
    path = Path(tmp) / "book.md"
    path.write_text(_sample_md(), encoding="utf-8")
    return path


def _resumed_project(store: TextbookProjectStore, source_path: Path) -> TextbookProject:
    project = store.create_project(name="Book", source_path=source_path)
    ch = split_chapters(_sample_md())
    kp = coerce_knowledge_points(
        {"words": [{"term": "merhaba", "translation": "hello"}]}
    )
    project.set_chapters([(ch[0], True, kp, "")])
    project.update_resource_pool()
    project.current_step = 4  # STEP_REVIEW
    store.save_project(project)
    return project


def _clear_last_project_key() -> None:
    QSettings("Varnamala", "CourseEditor").remove("workshop/last_project_id")


class WorkshopWindowTest(unittest.TestCase):
    def setUp(self) -> None:
        _App.get()
        self.tmp = tempfile.TemporaryDirectory()
        self.store = TextbookProjectStore(base_dir=Path(self.tmp.name))
        self.src = _make_source(self.tmp.name)
        self.win = WorkshopWindow(None, None, store=self.store)

    def tearDown(self) -> None:
        self.win.deleteLater()
        self.tmp.cleanup()
        _clear_last_project_key()

    def test_constructs_on_library(self) -> None:
        self.assertEqual(self.win.windowTitle(), "课程工坊")
        self.assertEqual(self.win._stack.currentIndex(), 0)
        self.assertEqual(self.win._page_title.text(), "项目库")

    def test_project_selection_builds_canvas(self) -> None:
        project = _resumed_project(self.store, self.src)
        self.win._on_project_selected(project)
        self.assertIsNotNone(self.win._panel)
        self.assertIsNotNone(self.win._design_panel)
        self.assertIsNotNone(self.win._review_panel)
        self.assertIsNotNone(self.win._unified_workspace)
        self.assertEqual(self.win._stack.currentIndex(), 1)
        self.assertEqual(self.win._page_title.text(), "创意画布")
        # Embedded chrome hidden — workshop owns bottom bar.
        self.assertTrue(self.win._panel._stepper_widget.isHidden())
        self.assertTrue(self.win._panel._bottom_bar.isHidden())
        # Chapters survive into the canvas.
        self.assertEqual(len(self.win._panel._controller.chapters), 1)

    def test_checklist_marks_material_and_knowledge(self) -> None:
        project = _resumed_project(self.store, self.src)
        self.win._on_project_selected(project)
        text = self.win._checklist_label.text()
        self.assertIn("✓素材", text)
        self.assertIn("✓知识", text)
        self.assertIn("○草稿", text)

    def test_go_to_library_and_back(self) -> None:
        project = _resumed_project(self.store, self.src)
        self.win._on_project_selected(project)
        self.win._go_to_library()
        self.assertEqual(self.win._stack.currentIndex(), 0)
        self.assertEqual(self.win._page_title.text(), "项目库")
        self.win._go_to_canvas()
        self.assertEqual(self.win._stack.currentIndex(), 1)
        self.assertEqual(self.win._page_title.text(), "创意画布")

    def test_embedded_panel_does_not_close_on_import_success(self) -> None:
        project = _resumed_project(self.store, self.src)
        self.win._on_project_selected(project)
        panel = self.win._panel
        panel._on_step_changed(5, ImportStepResult.success("import", "ok"))
        self.assertFalse(panel.isHidden())

    def test_locate_flow(self) -> None:
        project = _resumed_project(self.store, self.src)
        self.win._on_project_selected(project)
        captured: list[str] = []
        self.win.locate_requested.connect(captured.append)
        self.assertFalse(self.win._locate_btn.isEnabled())
        self.win.on_import_finished("sec-xyz")
        self.assertTrue(self.win._locate_btn.isEnabled())
        self.win._locate_btn.click()
        self.assertEqual(captured, ["sec-xyz"])
        self.assertIn("✓导入", self.win._checklist_label.text())

    def test_sections_ready_is_forwarded(self) -> None:
        project = _resumed_project(self.store, self.src)
        self.win._on_project_selected(project)
        captured: list = []
        self.win.sections_ready.connect(lambda s, st: captured.append((s, st)))
        self.win._panel.sections_ready.emit([{"id": "s1"}], "merge")
        self.assertEqual(captured, [([{"id": "s1"}], "merge")])

    def test_degrade_stage_maps_to_stack_pages(self) -> None:
        self.assertEqual(self.win._degrade_stage(0), 0)
        self.assertEqual(self.win._degrade_stage(3), 1)
        self.assertEqual(self.win._degrade_stage(5), 1)


class WorkshopBlankProjectTest(unittest.TestCase):
    def setUp(self) -> None:
        _App.get()
        self.tmp = tempfile.TemporaryDirectory()
        self.store = TextbookProjectStore(base_dir=Path(self.tmp.name))
        self.win = WorkshopWindow(None, None, store=self.store)

    def tearDown(self) -> None:
        self.win.deleteLater()
        self.tmp.cleanup()
        _clear_last_project_key()

    def test_blank_project_opens_canvas(self) -> None:
        project = self.store.create_project(name="Blank", source_path=None)
        self.win._on_project_selected(project)
        self.assertTrue(self.win._blank)
        self.assertIsNotNone(self.win._panel)
        self.assertIsNotNone(self.win._design_panel)
        self.assertEqual(self.win._stack.currentIndex(), 1)
        self.assertEqual(self.win._page_title.text(), "创意画布")
        # Blank skips material requirement.
        self.assertIn("✓素材", self.win._checklist_label.text())
        loaded = self.store.load_project(project.project_id)
        self.assertEqual(loaded.ui_stage, 1)

    def test_blank_project_free_generation_mode_label(self) -> None:
        project = self.store.create_project(name="Blank", source_path=None)
        self.win._on_project_selected(project)
        self.assertIn("自由生成", self.win._design_panel._pool_label.text())

    def test_blank_project_remembered_as_last(self) -> None:
        project = self.store.create_project(name="Blank", source_path=None)
        self.win._on_project_selected(project)
        win2 = WorkshopWindow(None, None, store=self.store)
        try:
            self.assertTrue(win2.restore_last_session())
            self.assertIsNotNone(win2.current_project())
            self.assertEqual(win2.current_project().project_id, project.project_id)
            self.assertEqual(win2._stack.currentIndex(), 1)
        finally:
            win2.deleteLater()


class WorkshopSessionContinuityTest(unittest.TestCase):
    def setUp(self) -> None:
        _App.get()
        self.tmp = tempfile.TemporaryDirectory()
        self.store = TextbookProjectStore(base_dir=Path(self.tmp.name))
        self.src = _make_source(self.tmp.name)
        self.win = WorkshopWindow(None, None, store=self.store)
        self.project = _resumed_project(self.store, self.src)
        self.win._on_project_selected(self.project)

    def tearDown(self) -> None:
        self.win.deleteLater()
        self.tmp.cleanup()
        _clear_last_project_key()

    def test_ui_stage_persisted_as_canvas(self) -> None:
        loaded = self.store.load_project(self.project.project_id)
        self.assertEqual(loaded.ui_stage, 1)
        self.win._go_to_library()
        loaded = self.store.load_project(self.project.project_id)
        self.assertEqual(loaded.ui_stage, 0)

    def test_canvas_restored_on_reopen(self) -> None:
        win2 = WorkshopWindow(None, None, store=self.store)
        try:
            win2._on_project_selected(self.store.load_project(self.project.project_id))
            self.assertEqual(win2._stack.currentIndex(), 1)
        finally:
            win2.deleteLater()

    def test_restore_last_session_returns_false_without_history(self) -> None:
        _clear_last_project_key()
        win2 = WorkshopWindow(None, None, store=self.store)
        try:
            self.assertFalse(win2.restore_last_session())
        finally:
            win2.deleteLater()

    def test_interrupt_and_save_cancels_busy_design(self) -> None:
        controller = self.win._design_panel._controller
        with unittest.mock.patch.object(
            type(controller), "is_busy", new_callable=unittest.mock.PropertyMock
        ) as busy, unittest.mock.patch.object(controller, "cancel") as cancel:
            busy.return_value = True
            self.win.interrupt_and_save()
            cancel.assert_called_once()

    def test_interrupt_persists_canvas_stage(self) -> None:
        self.win.interrupt_and_save()
        loaded = self.store.load_project(self.project.project_id)
        self.assertEqual(loaded.ui_stage, 1)

    def test_repeated_interrupt_restore_is_idempotent(self) -> None:
        self.win.interrupt_and_save()
        first = (Path(self.tmp.name) / self.project.project_id / "project.json").read_text()
        for _ in range(3):
            self.win.interrupt_and_save()
        second = (
            Path(self.tmp.name) / self.project.project_id / "project.json"
        ).read_text()
        d1, d2 = json.loads(first), json.loads(second)
        d1.pop("updated_at", None)
        d2.pop("updated_at", None)
        self.assertEqual(d1, d2)


class WorkshopBottomBarTest(unittest.TestCase):
    def setUp(self) -> None:
        _App.get()
        self.tmp = tempfile.TemporaryDirectory()
        self.store = TextbookProjectStore(base_dir=Path(self.tmp.name))
        self.src = _make_source(self.tmp.name)
        self.win = WorkshopWindow(None, None, store=self.store)
        self.project = _resumed_project(self.store, self.src)
        self.win._on_project_selected(self.project)
        self.win.show()

    def tearDown(self) -> None:
        self.win.hide()
        self.win.deleteLater()
        self.tmp.cleanup()
        _clear_last_project_key()

    def test_header_shows_project_and_languages(self) -> None:
        self.assertEqual(self.win._project_btn.text(), "Book")
        self.assertEqual(self.win._lang_label.text(), "Chinese → Turkish")
        self.assertEqual(self.win._page_title.text(), "创意画布")

    def test_bottom_bar_fed_by_panel_signals(self) -> None:
        self.assertFalse(self.win._ws_progress.isVisible())
        self.win._panel.busy_changed.emit(True, "提取中…")
        self.assertTrue(self.win._ws_progress.isVisible())
        self.assertTrue(self.win._ws_cancel_btn.isVisible())
        self.assertEqual(self.win._ws_stage_label.text(), "提取中…")
        self.win._panel.busy_changed.emit(False, "")
        self.assertFalse(self.win._ws_progress.isVisible())
        self.assertFalse(self.win._ws_cancel_btn.isVisible())

    def test_bottom_bar_fed_by_design_signals(self) -> None:
        self.win._design_panel.busy_changed.emit(True, "生成中…")
        self.assertTrue(self.win._ws_progress.isVisible())
        self.win._design_panel.busy_changed.emit(False, "")
        self.assertFalse(self.win._ws_progress.isVisible())
        self.win._design_panel.usage_changed.emit("100 tok")
        self.assertEqual(self.win._ws_usage_label.text(), "100 tok")

    def test_cancel_routes_to_busy_source(self) -> None:
        controller = self.win._design_panel._controller
        self.win._set_busy_source("design", True, "生成中…")
        with unittest.mock.patch.object(controller, "cancel") as cancel:
            self.win._on_cancel_busy()
            cancel.assert_called_once()

    def test_design_status_widgets_hidden(self) -> None:
        self.assertTrue(self.win._design_panel._stage_label.isHidden())
        self.assertTrue(self.win._design_panel._usage_label.isHidden())

    def test_draft_updates_checklist_and_outline(self) -> None:
        draft = {
            "id": "d1",
            "name": "草稿",
            "units": [{"lessons": [{}]}],
            "words": [],
        }
        self.win._design_panel._controller.set_draft(draft)
        self.win._design_panel._on_draft_ready(draft)
        self.assertIn("✓草稿", self.win._checklist_label.text())
        self.assertIn("1 单元", self.win._review_panel._hint_label.text())
        self.assertIn("1 课时", self.win._review_panel._hint_label.text())

    def test_review_refresh_without_draft(self) -> None:
        self.win._design_panel._json_editor.setPlainText("")
        # Clear controller draft if any.
        self.win._design_panel._controller.set_draft(None)  # type: ignore[arg-type]
        self.win._review_refresh()
        self.assertIn("还没有草稿", self.win._review_panel._hint_label.text())
        self.assertFalse(self.win._review_panel._import_btn.isEnabled())

    def test_panel_busy_blocks_library_unless_confirmed(self) -> None:
        controller = self.win._panel._controller
        with unittest.mock.patch.object(
            type(controller), "is_busy", new_callable=unittest.mock.PropertyMock
        ) as busy:
            busy.return_value = True
            with unittest.mock.patch.object(
                QMessageBox, "question", return_value=QMessageBox.StandardButton.No
            ):
                self.win._go_to_library()
            self.assertEqual(self.win._stack.currentIndex(), 1)
            with unittest.mock.patch.object(
                QMessageBox, "question", return_value=QMessageBox.StandardButton.Yes
            ), unittest.mock.patch.object(controller, "cancel") as cancel:
                self.win._go_to_library()
            cancel.assert_called_once()
            self.assertEqual(self.win._stack.currentIndex(), 0)

    def test_design_busy_allows_free_navigation(self) -> None:
        controller = self.win._design_panel._controller
        with unittest.mock.patch.object(
            type(controller), "is_busy", new_callable=unittest.mock.PropertyMock
        ) as busy:
            busy.return_value = True
            self.win._go_to_library()
            self.assertEqual(self.win._stack.currentIndex(), 0)
            self.win._go_to_canvas()
            self.assertEqual(self.win._stack.currentIndex(), 1)


class WorkshopDesignStageTest(unittest.TestCase):
    def setUp(self) -> None:
        _App.get()
        self.tmp = tempfile.TemporaryDirectory()
        self.store = TextbookProjectStore(base_dir=Path(self.tmp.name))
        self.src = _make_source(self.tmp.name)
        self.win = WorkshopWindow(None, None, store=self.store)
        self.project = _resumed_project(self.store, self.src)
        self.win._on_project_selected(self.project)

    def tearDown(self) -> None:
        self.win.deleteLater()
        self.tmp.cleanup()
        _clear_last_project_key()

    def test_design_panel_grounded_on_resource_pool(self) -> None:
        pool = self.win._design_panel._controller.resource_pool
        self.assertTrue(pool)
        terms = {e.get("term") for e in pool if e.get("_kind") == "word"}
        self.assertIn("merhaba", terms)

    def test_design_chat_column_still_visible(self) -> None:
        """Unified canvas must not strip the design chat left pane."""
        ws = self.win._unified_workspace
        self.assertIs(ws.design_panel, self.win._design_panel)
        # Chat input exists and is still a child of the design panel.
        self.assertIsNotNone(self.win._design_panel._chat_input)
        self.assertFalse(self.win._design_panel._chat_input.isHidden())

    def test_escape_cancels_busy_after_confirm(self) -> None:
        controller = self.win._design_panel._controller
        self.win._set_busy_source("design", True, "生成中…")
        with unittest.mock.patch.object(
            QMessageBox, "question", return_value=QMessageBox.StandardButton.Yes
        ), unittest.mock.patch.object(controller, "cancel") as cancel:
            self.win._on_escape()
            cancel.assert_called_once()

    def test_escape_noop_when_idle(self) -> None:
        self.win._busy_sources.clear()
        with unittest.mock.patch.object(QMessageBox, "question") as q:
            self.win._on_escape()
            q.assert_not_called()

    def test_workspace_project_id_for_ui_state(self) -> None:
        self.assertEqual(
            self.win._unified_workspace._project_id, self.project.project_id
        )


if __name__ == "__main__":
    unittest.main()
