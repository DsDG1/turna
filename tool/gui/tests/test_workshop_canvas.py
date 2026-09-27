"""Tests for WorkshopCanvas (four-stage canvas IA).

The canvas replaced the three-column UnifiedWorkspaceWidget: there are no tabs
any more, so these tests assert *stage reachability and data flow* instead of
tab titles. Everything that is data (bubble pool reconcile, generate chain,
focus summary, per-project stage persistence) is asserted here unchanged.
"""
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

from PySide6.QtCore import QSettings
from PySide6.QtWidgets import QMessageBox, QWidget

from src.backend.knowledge_schema import coerce_knowledge_points
from src.backend.markdown_chopper import split_chapters
from src.backend.textbook_project_store import TextbookProjectStore
from src.dialogs.ai.design_panel import DesignPanel
from src.dialogs.ai.review_panel import ReviewPanel
from src.dialogs.textbook_import_controller import TextbookImportController
from src.dialogs.textbook_import_dialog import TextbookImportDialog
from src.widgets.resource_review_table import ResourceRow
from src.widgets.workshop_canvas import (
    STAGE_DRAFT,
    STAGE_IMPORT,
    STAGE_KNOWLEDGE,
    STAGE_MATERIAL,
    STAGES,
    WorkshopCanvas,
)
from tests._qtapp import _App

_SETTINGS = QSettings("Turna", "CourseEditor")


def _sample_md() -> str:
    return "## 1 Merhaba\nhello\n"


def _row(entry_id: str, term: str, *, checked: bool = True) -> ResourceRow:
    return ResourceRow(
        chapter_index=0,
        resource_type="word",
        entry={"id": entry_id, "term": term, "translation": term},
        checked=checked,
    )


def _busy_import_controller():
    """Force ``TextbookImportController.is_busy`` True (it is a read-only
    property, so an instance-level patch cannot be undone)."""
    return unittest.mock.patch.object(
        TextbookImportController,
        "is_busy",
        new_callable=unittest.mock.PropertyMock,
        return_value=True,
    )


class WorkshopCanvasTest(unittest.TestCase):
    def setUp(self) -> None:
        _App.get()
        self.tmp = tempfile.TemporaryDirectory()
        self.store = TextbookProjectStore(base_dir=Path(self.tmp.name))
        src = Path(self.tmp.name) / "book.md"
        src.write_text(_sample_md(), encoding="utf-8")
        project = self.store.create_project(name="Book", source_path=src)
        ch = split_chapters(_sample_md())
        kp = coerce_knowledge_points(
            {"words": [{"term": "merhaba", "translation": "hello"}]}
        )
        project.set_chapters([(ch[0], True, kp, "")])
        project.update_resource_pool()
        self.store.save_project(project)
        self.project = project
        _SETTINGS.remove(f"workshop/ui/{project.project_id}/stage")

        self.panel = TextbookImportDialog(
            None, None, project=project, store=self.store, embedded=True
        )
        self.design = DesignPanel(None, None)
        self.design.set_project(project, self.store)
        self.review = ReviewPanel(self.design, None, None)
        self.ws = WorkshopCanvas(
            None,
            self.panel,
            self.design,
            self.review,
            None,
            blank=False,
            project_id=project.project_id,
        )

    def tearDown(self) -> None:
        self.ws.deleteLater()
        self.design.deleteLater()
        self.review.deleteLater()
        self.panel.deleteLater()
        self.tmp.cleanup()

    # --- stage IA --------------------------------------------------------
    def test_all_four_stages_exist(self) -> None:
        for stage in STAGES:
            self.assertIsNotNone(self.ws.stage_widget(stage), stage)

    def test_import_stack_pages_were_removed(self) -> None:
        """摘页手术: the three pages move into stages, not tabs."""
        self.assertEqual(self.panel._stack.count(), 0)

    def test_ripped_pages_are_not_explicitly_hidden(self) -> None:
        """QStackedLayout.removeWidget leaves pages explicitly hidden.

        Layouts skip explicitly-hidden widgets, so a page carrying that flag
        paints nothing once its stage shows and keeps the stale 640x480 stack
        geometry (blank stages + frozen width). The canvas must clear the
        flag when it re-parents a page.
        """
        for page in (self.ws._source_page, self.ws._knowledge_page, self.ws._import_page):
            self.assertFalse(page.isHidden())

    def test_stage_navigation_switches_stack(self) -> None:
        seen: list[str] = []
        self.ws.stage_changed.connect(seen.append)
        self.assertTrue(self.ws.set_stage(STAGE_KNOWLEDGE))
        self.assertIs(
            self.ws._stages.currentWidget(), self.ws.stage_widget(STAGE_KNOWLEDGE)
        )
        self.assertEqual(seen, [STAGE_KNOWLEDGE])
        self.assertEqual(self.ws.current_stage(), STAGE_KNOWLEDGE)

    def test_unknown_stage_is_a_noop(self) -> None:
        before = self.ws.current_stage()
        self.assertFalse(self.ws.set_stage("nope"))
        self.assertEqual(self.ws.current_stage(), before)

    def test_resumed_project_with_knowledge_opens_knowledge_stage(self) -> None:
        # A project that already has knowledge rows resumes on 知识.
        self.panel._review_table.set_rows([_row("w1", "merhaba")])
        self.ws.set_stage(STAGE_KNOWLEDGE, force=True)
        self.assertEqual(self.ws.current_stage(), STAGE_KNOWLEDGE)

    def test_first_knowledge_rows_switch_to_knowledge_stage(self) -> None:
        self.ws.set_stage(STAGE_MATERIAL, force=True)
        self.panel._review_table.set_rows([_row("w1", "merhaba")])
        self.ws._on_rows_changed()
        self.assertEqual(self.ws.current_stage(), STAGE_KNOWLEDGE)

    def test_draft_ready_switches_to_import_stage(self) -> None:
        self.ws.set_stage(STAGE_DRAFT, force=True)
        draft = {
            "id": "s1",
            "name": "S",
            "units": [{"lessons": [{}]}],
            "words": [],
        }
        self.design._controller.set_draft(draft)
        self.design._on_draft_ready(draft)
        self.assertEqual(self.ws.current_stage(), STAGE_IMPORT)

    def test_chat_button_focuses_draft_stage(self) -> None:
        self.ws.set_stage(STAGE_IMPORT, force=True)
        self.ws.focus_design_chat()
        self.assertEqual(self.ws.current_stage(), STAGE_DRAFT)

    def test_leaving_extraction_while_busy_asks_first(self) -> None:
        self.ws.set_stage(STAGE_MATERIAL, force=True)
        with _busy_import_controller():
            with unittest.mock.patch.object(
                QMessageBox, "question", return_value=QMessageBox.StandardButton.No
            ) as ask:
                self.assertFalse(self.ws.set_stage(STAGE_DRAFT))
                ask.assert_called_once()
            with unittest.mock.patch.object(
                QMessageBox, "question", return_value=QMessageBox.StandardButton.Yes
            ), unittest.mock.patch.object(
                self.panel._controller, "cancel"
            ) as cancel:
                self.assertTrue(self.ws.set_stage(STAGE_DRAFT))
                cancel.assert_called_once()

    def test_leaving_draft_stage_never_asks(self) -> None:
        self.ws.set_stage(STAGE_DRAFT, force=True)
        with _busy_import_controller(), unittest.mock.patch.object(
            QMessageBox, "question"
        ) as ask:
            self.assertTrue(self.ws.set_stage(STAGE_IMPORT))
            ask.assert_not_called()

    # --- design panel placement -----------------------------------------
    def test_design_panel_lives_in_draft_stage(self) -> None:
        draft = self.ws.stage_widget(STAGE_DRAFT)
        self.assertIs(self._find_parent(draft, self.design), draft)

    def test_review_panel_lives_in_import_stage(self) -> None:
        stage = self.ws.stage_widget(STAGE_IMPORT)
        self.assertIs(self._find_parent(stage, self.review), stage)

    @staticmethod
    def _find_parent(root: QWidget, target: QWidget) -> QWidget | None:
        if root is target:
            return root
        for child in root.findChildren(object):
            if child is target:
                return root
        return None

    def test_design_panel_chat_not_hidden(self) -> None:
        # Chat stays visible; topic lives on the orbit band (hidden mirror on
        # the design panel).
        self.assertFalse(self.design._chat_input.isHidden())
        self.assertTrue(self.design._topic_edit.isHidden())
        self.assertFalse(self.ws.orbit_widget.topic_edit.isHidden())

    def test_pool_popover_button_is_on_the_param_band(self) -> None:
        self.assertGreaterEqual(
            self.ws.orbit_widget._action_row.indexOf(self.ws._pool_popup_btn), 0
        )

    # --- data flow -------------------------------------------------------
    def test_bubble_pool_from_checked_rows(self) -> None:
        rows = self.panel._review_table._model.rows
        if not rows:
            self.panel._review_table.set_rows([_row("w1", "merhaba")])
        else:
            for r in rows:
                r.checked = True
            self.panel._review_table.rows_changed.emit()
        self.ws.refresh_bubble_pool()
        self.assertGreater(self.ws.bubble_pool_layout.count(), 0)

    def test_generate_pushes_params_to_controller(self) -> None:
        self.ws.orbit_widget.topic_edit.setText("机场")
        self.ws.orbit_widget.level_combo.setCurrentText("A2")
        self.ws.orbit_widget.unit_spin.setValue(2)
        self.ws.orbit_widget.whisper_edit.setText("偏口语")
        with unittest.mock.patch.object(
            self.design._controller, "generate"
        ) as gen:
            self.ws._on_generate_clicked()
            gen.assert_called_once()
        params = self.design._controller.params
        self.assertEqual(params.get("topic"), "机场")
        self.assertEqual(params.get("level"), "A2")
        self.assertEqual(params.get("unit_count"), 2)
        self.assertEqual(params.get("extra_instructions"), "偏口语")

    def test_add_selected_to_orbit(self) -> None:
        self.panel._review_table.set_rows([_row("w1", "merhaba")])
        if self.panel._review_table._table.rowCount() > 0:
            self.panel._review_table._table.selectRow(0)
        before = len(self.ws.orbit_widget.dropped_items)
        self.ws.add_selected_to_orbit()
        self.assertGreater(len(self.ws.orbit_widget.dropped_items), before)

    def test_pool_popover_adds_checked_rows(self) -> None:
        rows = [_row("w1", "a"), _row("w2", "b")]
        self.panel._review_table.set_rows(rows)
        self.ws._open_pool_popup()
        try:
            self.assertIsNotNone(self.ws._pool_popup)
            self.assertFalse(self.ws._pool_popup.isModal())
        finally:
            if self.ws._pool_popup is not None:
                self.ws._pool_popup.close()
        self.ws._add_rows_to_orbit(rows)
        self.assertEqual(len(self.ws.orbit_widget.dropped_items), 2)

    def test_bubble_pool_incremental_keeps_widgets(self) -> None:
        rows = [_row("w1", "a"), _row("w2", "b")]
        self.panel._review_table.set_rows(rows)
        self.ws.refresh_bubble_pool()
        first = self.ws._bubble_widgets.get("word:w1")
        self.assertIsNotNone(first)
        # Second refresh with same set must keep the same widget instance.
        self.ws.refresh_bubble_pool()
        self.assertIs(self.ws._bubble_widgets.get("word:w1"), first)
        # Uncheck one → only that key removed.
        rows[1].checked = False
        self.panel._review_table._model.rows = rows
        self.ws.refresh_bubble_pool()
        self.assertIn("word:w1", self.ws._bubble_widgets)
        self.assertNotIn("word:w2", self.ws._bubble_widgets)

    def test_bubble_refresh_debounce_merges(self) -> None:
        calls = {"n": 0}
        original = self.ws.refresh_bubble_pool

        def _counting() -> None:
            calls["n"] += 1
            original()

        self.ws.refresh_bubble_pool = _counting  # type: ignore[method-assign]
        self.ws.schedule_bubble_refresh()
        self.ws.schedule_bubble_refresh()
        self.ws.schedule_bubble_refresh()
        self.assertEqual(calls["n"], 0)
        self.ws.flush_bubble_refresh()
        self.assertEqual(calls["n"], 1)

    def test_focus_summary_updates_for_pool(self) -> None:
        self.ws._update_focus_summary()
        text = self.ws.orbit_widget.focus_summary.text()
        self.assertTrue(text)
        self.assertIn("词", text)

    def test_focus_summary_focused_when_dropped(self) -> None:
        self.ws.orbit_widget.add_knowledge_point(
            {"id": "w1", "term": "selam", "translation": "hi"}, "word"
        )
        self.ws._update_focus_summary()
        self.assertIn("聚焦", self.ws.orbit_widget.focus_summary.text())

    # --- persistence -----------------------------------------------------
    def test_save_restore_stage(self) -> None:
        self.ws.set_stage(STAGE_IMPORT, force=True)
        self.ws.save_ui_state()
        self.assertEqual(
            _SETTINGS.value(f"workshop/ui/{self.project.project_id}/stage"),
            STAGE_IMPORT,
        )

        panel = TextbookImportDialog(
            None, None, project=self.project, store=self.store, embedded=True
        )
        design = DesignPanel(None, None)
        design.set_project(self.project, self.store)
        review = ReviewPanel(design, None, None)
        ws2 = WorkshopCanvas(
            None,
            panel,
            design,
            review,
            None,
            blank=False,
            project_id=self.project.project_id,
        )
        try:
            self.assertEqual(ws2.current_stage(), STAGE_IMPORT)
        finally:
            ws2.deleteLater()
            design.deleteLater()
            review.deleteLater()
            panel.deleteLater()

    def test_abandoned_tab_keys_are_not_migrated(self) -> None:
        """A saved tab index has no meaning in a stage layout: the canvas must
        ignore it (and must not write one) rather than guessing a stage."""
        prefix = f"workshop/ui/{self.project.project_id}"
        legacy = {f"{prefix}/left_tab": 2, f"{prefix}/right_tab": 1}
        for key, value in legacy.items():
            _SETTINGS.setValue(key, value)
        _SETTINGS.remove(f"{prefix}/stage")
        try:
            # A fresh canvas with only the legacy keys on disk.
            panel = TextbookImportDialog(
                None, None, project=self.project, store=self.store, embedded=True
            )
            design = DesignPanel(None, None)
            design.set_project(self.project, self.store)
            review = ReviewPanel(design, None, None)
            ws2 = WorkshopCanvas(
                None,
                panel,
                design,
                review,
                None,
                blank=False,
                project_id=self.project.project_id,
            )
            try:
                # Legacy left_tab=2 (气泡池) / right_tab=1 (对话与高级) are
                # ignored: the canvas opens the stage the project state implies
                # (empty review table → 素材), not one derived from tab indices.
                self.assertEqual(ws2.current_stage(), STAGE_MATERIAL)
                ws2.save_ui_state()
                self.assertEqual(
                    _SETTINGS.value(f"{prefix}/stage"), STAGE_MATERIAL
                )
            finally:
                ws2.deleteLater()
                design.deleteLater()
                review.deleteLater()
                panel.deleteLater()
        finally:
            for key in legacy:
                _SETTINGS.remove(key)

    def test_blank_project_opens_draft_stage(self) -> None:
        project = self.store.create_project(name="Blank", source_path=None)
        panel = TextbookImportDialog(
            None, None, project=project, store=self.store, embedded=True
        )
        design = DesignPanel(None, None)
        design.set_project(project, self.store)
        review = ReviewPanel(design, None, None)
        ws2 = WorkshopCanvas(
            None, panel, design, review, None, blank=True, project_id=project.project_id
        )
        try:
            self.assertEqual(ws2.current_stage(), STAGE_DRAFT)
        finally:
            ws2.deleteLater()
            design.deleteLater()
            review.deleteLater()
            panel.deleteLater()

    def test_banner_dismiss_persists(self) -> None:
        _SETTINGS.remove("workshop/canvas_tips_dismissed")
        self.ws._update_banner()
        if not self.ws._banner.isVisible():
            # Force show for dismiss path.
            self.ws._banner_label.setText("tip")
            self.ws._banner.setVisible(True)
        self.ws._dismiss_banner()
        self.assertFalse(self.ws._banner.isVisible())
        self.assertTrue(
            bool(_SETTINGS.value("workshop/canvas_tips_dismissed", False))
        )


if __name__ == "__main__":
    unittest.main()
