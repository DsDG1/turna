"""Tests for WorkshopWindow (connectplan Phase 2 + merge overhaul Phase A)."""
from __future__ import annotations

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

from PySide6.QtCore import Qt, QSettings  # noqa: E402
from PySide6.QtWidgets import QApplication, QMessageBox  # noqa: E402

from src.backend.import_step_result import ImportStepResult  # noqa: E402
from src.backend.knowledge_schema import coerce_knowledge_points  # noqa: E402
from src.backend.markdown_chopper import split_chapters  # noqa: E402
from src.backend.textbook_project import TextbookProject  # noqa: E402
from src.backend.textbook_project_store import TextbookProjectStore  # noqa: E402
from src.dialogs.workshop_window import WorkshopWindow  # noqa: E402


class _App:
    _app = None

    @classmethod
    def get(cls) -> QApplication:
        if cls._app is None:
            cls._app = QApplication.instance() or QApplication([])
        return cls._app


def _stage_enabled(win: WorkshopWindow, i: int) -> bool:
    item = win._stage_list.item(i)
    return bool(item.flags() & Qt.ItemFlag.ItemIsEnabled)


def _sample_md() -> str:
    return "## 1 Merhaba\nhello\n"


def _make_source(tmp: str) -> Path:
    """Write a real source file so the project counts as a textbook project
    (source_path=None now means a blank AI project)."""
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

    def test_constructs_on_project_stage(self) -> None:
        self.assertEqual(self.win.windowTitle(), "课程工坊")
        self.assertEqual(self.win._stack.currentIndex(), 0)
        self.assertEqual(self.win._stage_list.count(), 6)
        # Only the project stage is reachable before a project is chosen.
        self.assertTrue(_stage_enabled(self.win, 0))
        for i in range(1, 6):
            self.assertFalse(_stage_enabled(self.win, i))

    def test_project_selection_builds_panel_and_unlocks_stages(self) -> None:
        project = _resumed_project(self.store, self.src)
        self.win._on_project_selected(project)
        self.assertIsNotNone(self.win._panel)
        self.assertEqual(self.win._stack.currentIndex(), 1)
        # Panel stepper + bottom bar hidden — the workshop provides the
        # outer navigation and the unified bottom bar.
        self.assertTrue(self.win._panel._stepper_widget.isHidden())
        self.assertTrue(self.win._panel._bottom_bar.isHidden())
        # Resumed at review (knowledge page) → stages up to 设计 enabled;
        # 审校 needs a draft, 导入 not reached yet.
        self.assertTrue(_stage_enabled(self.win, 1))  # 素材
        self.assertTrue(_stage_enabled(self.win, 2))  # 知识
        self.assertTrue(_stage_enabled(self.win, 3))  # 设计
        self.assertFalse(_stage_enabled(self.win, 4))  # 审校
        self.assertFalse(_stage_enabled(self.win, 5))  # 导入
        # Panel landed on the knowledge page.
        self.assertEqual(self.win._panel._stack.currentIndex(), 1)

    def test_stage_navigation_round_trip(self) -> None:
        project = _resumed_project(self.store, self.src)
        self.win._on_project_selected(project)
        self.win._go_to_stage(0)
        self.assertEqual(self.win._stack.currentIndex(), 0)
        self.win._go_to_stage(1)  # 素材 → panel page 0
        self.assertEqual(self.win._stack.currentIndex(), 1)
        self.assertEqual(self.win._panel._stack.currentIndex(), 0)
        # Data survives the round trip (chapters still loaded).
        self.assertEqual(len(self.win._panel._controller.chapters), 1)

    def test_embedded_panel_does_not_close_on_import_success(self) -> None:
        project = _resumed_project(self.store, self.src)
        self.win._on_project_selected(project)
        panel = self.win._panel
        panel._on_step_changed(5, ImportStepResult.success("import", "ok"))
        # Widget was not hidden/closed despite the dialog's close() path.
        self.assertFalse(panel.isHidden())

    def test_locate_flow(self) -> None:
        captured: list[str] = []
        self.win.locate_requested.connect(captured.append)
        self.assertFalse(self.win._locate_btn.isEnabled())
        self.win.on_import_finished("sec-xyz")
        self.assertTrue(self.win._locate_btn.isEnabled())
        self.win._locate_btn.click()
        self.assertEqual(captured, ["sec-xyz"])

    def test_sections_ready_is_forwarded(self) -> None:
        project = _resumed_project(self.store, self.src)
        self.win._on_project_selected(project)
        captured: list = []
        self.win.sections_ready.connect(lambda s, st: captured.append((s, st)))
        self.win._panel.sections_ready.emit([{"id": "s1"}], "merge")
        self.assertEqual(captured, [([{"id": "s1"}], "merge")])


class WorkshopBlankProjectTest(unittest.TestCase):
    """Phase A: blank AI projects (原「AI 生成课程」的新形态)."""

    def setUp(self) -> None:
        _App.get()
        self.tmp = tempfile.TemporaryDirectory()
        self.store = TextbookProjectStore(base_dir=Path(self.tmp.name))
        self.win = WorkshopWindow(None, None, store=self.store)

    def tearDown(self) -> None:
        self.win.deleteLater()
        self.tmp.cleanup()
        _clear_last_project_key()

    def test_blank_project_goes_straight_to_design(self) -> None:
        project = self.store.create_project(name="Blank", source_path=None)
        self.win._on_project_selected(project)
        # No textbook import panel for blank projects.
        self.assertIsNone(self.win._panel)
        self.assertIsNotNone(self.win._design_panel)
        # Landed on the design stage (stack index 2).
        self.assertEqual(self.win._stack.currentIndex(), 2)
        # Only 项目 and 设计 are reachable; textbook stages are disabled,
        # and 审校 needs a draft first.
        self.assertTrue(_stage_enabled(self.win, 0))
        for i in (1, 2, 4, 5):
            self.assertFalse(_stage_enabled(self.win, i))
        self.assertTrue(_stage_enabled(self.win, 3))
        # The design stage is persisted for exact restore.
        loaded = self.store.load_project(project.project_id)
        self.assertEqual(loaded.ui_stage, 3)

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
            self.assertEqual(win2._stack.currentIndex(), 2)
        finally:
            win2.deleteLater()


class WorkshopSessionContinuityTest(unittest.TestCase):
    """Phase A: 随时中断、无限次恢复 — ui_stage + last_project_id."""

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

    def test_ui_stage_persisted_on_navigation(self) -> None:
        self.win._go_to_stage(3)  # 设计
        loaded = self.store.load_project(self.project.project_id)
        self.assertEqual(loaded.ui_stage, 3)
        self.win._go_to_stage(1)  # 素材
        loaded = self.store.load_project(self.project.project_id)
        self.assertEqual(loaded.ui_stage, 1)

    def test_ui_stage_restored_on_reopen(self) -> None:
        self.win._go_to_stage(3)
        win2 = WorkshopWindow(None, None, store=self.store)
        try:
            win2._on_project_selected(
                self.store.load_project(self.project.project_id)
            )
            # Restored to the design page (stack index 2), not the panel page.
            self.assertEqual(win2._stack.currentIndex(), 2)
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

    def test_interrupt_persists_current_stage(self) -> None:
        self.win._go_to_stage(2)  # 知识
        self.win.interrupt_and_save()
        loaded = self.store.load_project(self.project.project_id)
        self.assertEqual(loaded.ui_stage, 2)

    def test_repeated_interrupt_restore_is_idempotent(self) -> None:
        """无限次中断-恢复：project.json 内容幂等，状态不劣化。"""
        self.win._go_to_stage(3)
        self.win.interrupt_and_save()
        first = (Path(self.tmp.name) / self.project.project_id / "project.json").read_text()
        for _ in range(3):
            self.win.interrupt_and_save()
        second = (
            Path(self.tmp.name) / self.project.project_id / "project.json"
        ).read_text()
        # Only updated_at may drift; the meaningful state is unchanged.
        import json

        d1, d2 = json.loads(first), json.loads(second)
        d1.pop("updated_at")
        d2.pop("updated_at")
        self.assertEqual(d1, d2)


class WorkshopPhaseBUiTest(unittest.TestCase):
    """Phase B: sidebar nav, unified bottom bar, nav row, review placeholder."""

    def setUp(self) -> None:
        _App.get()
        self.tmp = tempfile.TemporaryDirectory()
        self.store = TextbookProjectStore(base_dir=Path(self.tmp.name))
        self.src = _make_source(self.tmp.name)
        self.win = WorkshopWindow(None, None, store=self.store)
        self.project = _resumed_project(self.store, self.src)
        self.win._on_project_selected(self.project)
        # Visibility assertions need an actually-shown window (offscreen).
        self.win.show()

    def tearDown(self) -> None:
        self.win.hide()
        self.win.deleteLater()
        self.tmp.cleanup()
        _clear_last_project_key()

    def test_sidebar_shows_completion_marks(self) -> None:
        # Pool exists (resumed at review) → 知识 marked complete; 素材 too.
        self.assertIn("✓", self.win._stage_list.item(1).text())
        self.assertIn("✓", self.win._stage_list.item(2).text())
        self.assertNotIn("✓", self.win._stage_list.item(3).text())

    def test_header_shows_project_and_languages(self) -> None:
        self.assertEqual(self.win._project_btn.text(), "Book")
        self.assertEqual(self.win._lang_label.text(), "Chinese → Turkish")
        self.assertEqual(self.win._page_title.text(), "3 知识")

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

    def test_nav_row_only_on_workshop_owned_pages(self) -> None:
        self.win._go_to_stage(3)  # 设计
        self.assertTrue(self.win._nav_row.isVisible())
        self.assertFalse(self.win._next_btn.isEnabled())  # no draft yet
        self.win._go_to_stage(2)  # 知识 (embedded page)
        self.assertTrue(self.win._nav_row.isHidden())

    def test_draft_unlocks_review_stage(self) -> None:
        self.assertFalse(_stage_enabled(self.win, 4))
        draft = {"id": "d1", "name": "草稿", "units": [{"lessons": [{}]}], "words": []}
        self.win._design_panel._controller.set_draft(draft)
        self.win._design_panel._on_draft_ready(draft)
        self.assertTrue(_stage_enabled(self.win, 4))
        self.win._go_to_stage(4)
        self.assertEqual(self.win._stack.currentIndex(), 3)
        self.assertIn("1 单元", self.win._review_panel._hint_label.text())
        self.assertIn("1 课时", self.win._review_panel._hint_label.text())

    def test_review_refresh_without_draft(self) -> None:
        self.win._design_panel._json_editor.setPlainText("")
        self.win._review_refresh()
        self.assertIn("还没有草稿", self.win._review_panel._hint_label.text())
        self.assertFalse(self.win._review_panel._import_btn.isEnabled())

    def test_panel_busy_blocks_navigation_unless_confirmed(self) -> None:
        controller = self.win._panel._controller
        with unittest.mock.patch.object(
            type(controller), "is_busy", new_callable=unittest.mock.PropertyMock
        ) as busy:
            busy.return_value = True
            # Declined: stays on the current stage.
            with unittest.mock.patch.object(
                QMessageBox, "question", return_value=QMessageBox.StandardButton.No
            ):
                self.win._go_to_stage(0)
            self.assertNotEqual(self.win._stack.currentIndex(), 0)
            # Confirmed: cancels extraction and switches.
            with unittest.mock.patch.object(
                QMessageBox, "question", return_value=QMessageBox.StandardButton.Yes
            ), unittest.mock.patch.object(controller, "cancel") as cancel:
                self.win._go_to_stage(0)
            cancel.assert_called_once()
            self.assertEqual(self.win._stack.currentIndex(), 0)

    def test_design_busy_allows_free_navigation(self) -> None:
        controller = self.win._design_panel._controller
        with unittest.mock.patch.object(
            type(controller), "is_busy", new_callable=unittest.mock.PropertyMock
        ) as busy:
            busy.return_value = True
            self.win._go_to_stage(0)
            self.assertEqual(self.win._stack.currentIndex(), 0)
            self.win._go_to_stage(3)
            self.assertEqual(self.win._stack.currentIndex(), 2)

    def test_degrade_stage_when_data_missing(self) -> None:
        # A persisted 审校 stage without a draft degrades to 设计.
        self.assertEqual(self.win._degrade_stage(4), 3)
        # A persisted 导入 stage beyond _max_stage degrades too.
        self.assertEqual(self.win._degrade_stage(5), 3)
        self.assertEqual(self.win._degrade_stage(0), 0)


class WorkshopDesignStageTest(unittest.TestCase):
    """Phase 3: grounded design stage inside the workshop."""

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
        panel = self.win._design_panel
        self.assertIsNotNone(panel)
        pool = panel._controller.resource_pool
        self.assertEqual(len(pool), 1)
        self.assertEqual(pool[0]["_kind"], "word")
        self.assertEqual(pool[0]["term"], "merhaba")
        self.assertIn("1 词", panel._pool_label.text())

    def test_knowledge_page_button_jumps_to_design(self) -> None:
        self.win._panel.design_requested.emit()
        self.assertEqual(self.win._stack.currentIndex(), 2)  # design page

    def test_design_sections_forwarded(self) -> None:
        captured: list = []
        self.win.sections_ready.connect(lambda s, st: captured.append((s, st)))
        self.win._design_panel.sections_ready.emit([{"id": "dg-1"}], "merge")
        self.assertEqual(captured, [([{"id": "dg-1"}], "merge")])

    def test_design_state_persisted_to_project(self) -> None:
        panel = self.win._design_panel
        panel._topic_edit.setText("问候")
        panel._sync_params()  # triggers controller.set_params → autosave
        loaded = self.store.load_project(self.project.project_id)
        self.assertEqual(loaded.design["params"]["topic"], "问候")

    def test_pool_refresh_hint_when_draft_exists(self) -> None:
        panel = self.win._design_panel
        panel._controller.set_draft({"id": "old-draft"})
        # Knowledge stage edits the pool (a second word appears).
        ch, keep, kp, err = self.project.get_chapters()[0]
        kp.words.append({"id": "w-2", "term": "günaydın", "translation": "早安"})
        self.project.set_chapters([(ch, keep, kp, err)])
        self.project.update_resource_pool()
        self.win._go_to_stage(3)
        self.assertEqual(len(panel._controller.resource_pool), 2)
        self.assertIn("建议重新生成", panel._pool_label.text())


if __name__ == "__main__":
    unittest.main()

