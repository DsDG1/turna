"""Tests for UnifiedWorkspaceWidget (canvas IA)."""
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


from src.backend.knowledge_schema import coerce_knowledge_points  # noqa: E402
from src.backend.markdown_chopper import split_chapters  # noqa: E402
from src.backend.textbook_project_store import TextbookProjectStore  # noqa: E402
from src.dialogs.ai.design_panel import DesignPanel  # noqa: E402
from src.dialogs.ai.review_panel import ReviewPanel  # noqa: E402
from src.dialogs.textbook_import_dialog import TextbookImportDialog  # noqa: E402
from src.widgets.unified_workspace import UnifiedWorkspaceWidget  # noqa: E402
from tests._qtapp import _App  # noqa: E402


def _sample_md() -> str:
    return "## 1 Merhaba\nhello\n"


class UnifiedWorkspaceTest(unittest.TestCase):
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

        self.panel = TextbookImportDialog(
            None, None, project=project, store=self.store, embedded=True
        )
        self.panel.setWindowFlags(self.panel.windowFlags())
        self.design = DesignPanel(None, None)
        self.design.set_project(project, self.store)
        self.review = ReviewPanel(self.design, None, None)
        self.ws = UnifiedWorkspaceWidget(
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

    def test_tabs_present(self) -> None:
        self.assertEqual(self.ws.left_tabs.count(), 3)
        self.assertEqual(self.ws.right_tabs.count(), 3)
        self.assertEqual(self.ws.right_tabs.tabText(0), "结构大纲")
        self.assertEqual(self.ws.right_tabs.tabText(1), "对话与高级")
        self.assertEqual(self.ws.right_tabs.tabText(2), "章节导入")

    def test_design_panel_chat_not_hidden(self) -> None:
        # Chat stays visible; topic lives on Orbit (hidden mirror on design panel).
        self.assertFalse(self.design._chat_input.isHidden())
        self.assertTrue(self.design._topic_edit.isHidden())
        self.assertFalse(self.ws.orbit_widget.topic_edit.isHidden())

    def test_bubble_pool_from_checked_rows(self) -> None:
        # Resumed project has one word checked by default in review table?
        # Populate rows if empty.
        from src.widgets.resource_review_table import ResourceRow

        rows = self.panel._review_table._model.rows
        if not rows:
            entry = {"id": "w1", "term": "merhaba", "translation": "hello"}
            self.panel._review_table.set_rows(
                [
                    ResourceRow(
                        chapter_index=0,
                        resource_type="word",
                        entry=entry,
                        checked=True,
                    )
                ]
            )
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

    def test_chat_button_focuses_design_tab(self) -> None:
        self.ws.right_tabs.setCurrentIndex(0)
        self.ws.focus_design_chat()
        self.assertIs(self.ws.right_tabs.currentWidget(), self.design)

    def test_draft_ready_switches_to_outline(self) -> None:
        self.ws.right_tabs.setCurrentIndex(1)
        draft = {
            "id": "s1",
            "name": "S",
            "units": [{"lessons": [{}]}],
            "words": [],
        }
        self.design._controller.set_draft(draft)
        self.design._on_draft_ready(draft)
        self.assertIs(self.ws.right_tabs.currentWidget(), self.review)

    def test_blank_layout_prefers_outline_tab(self) -> None:
        # Blank projects: right defaults to 结构大纲; left on 气泡池.
        project = self.store.create_project(name="Blank", source_path=None)
        panel = TextbookImportDialog(
            None, None, project=project, store=self.store, embedded=True
        )
        design = DesignPanel(None, None)
        design.set_project(project, self.store)
        review = ReviewPanel(design, None, None)
        ws2 = UnifiedWorkspaceWidget(
            None, panel, design, review, None, blank=True, project_id=project.project_id
        )
        try:
            self.assertEqual(ws2.right_tabs.currentIndex(), 0)
            self.assertEqual(ws2.left_tabs.currentIndex(), 2)
            self.assertIn("可选", ws2.left_tabs.tabText(0))
        finally:
            ws2.deleteLater()
            design.deleteLater()
            review.deleteLater()
            panel.deleteLater()

    def test_save_restore_ui_state(self) -> None:
        from PySide6.QtCore import QSettings

        QSettings("Turna", "CourseEditor").remove(
            f"workshop/ui/{self.project.project_id}/left_tab"
        )
        self.ws._project_id = self.project.project_id
        self.ws.left_tabs.setCurrentIndex(2)
        self.ws.right_tabs.setCurrentIndex(1)
        self.ws.save_ui_state()

        panel = TextbookImportDialog(
            None, None, project=self.project, store=self.store, embedded=True
        )
        design = DesignPanel(None, None)
        design.set_project(self.project, self.store)
        review = ReviewPanel(design, None, None)
        ws2 = UnifiedWorkspaceWidget(
            None,
            panel,
            design,
            review,
            None,
            blank=False,
            project_id=self.project.project_id,
        )
        try:
            self.assertEqual(ws2.left_tabs.currentIndex(), 2)
            self.assertEqual(ws2.right_tabs.currentIndex(), 1)
        finally:
            ws2.deleteLater()
            design.deleteLater()
            review.deleteLater()
            panel.deleteLater()

    def test_add_selected_to_orbit(self) -> None:
        from src.widgets.resource_review_table import ResourceRow

        entry = {"id": "w1", "term": "merhaba", "translation": "hello"}
        self.panel._review_table.set_rows(
            [
                ResourceRow(
                    chapter_index=0,
                    resource_type="word",
                    entry=entry,
                    checked=True,
                )
            ]
        )
        # Select first row if table has items.
        if self.panel._review_table._table.rowCount() > 0:
            self.panel._review_table._table.selectRow(0)
        before = len(self.ws.orbit_widget.dropped_items)
        self.ws.add_selected_to_orbit()
        self.assertGreater(len(self.ws.orbit_widget.dropped_items), before)

    def test_banner_dismiss_persists(self) -> None:
        from PySide6.QtCore import QSettings

        QSettings("Turna", "CourseEditor").remove("workshop/canvas_tips_dismissed")
        # Rebuild banner state
        self.ws._update_banner()
        # May or may not show depending on draft/knowledge — force message path.
        if not self.ws._banner.isVisible():
            # Force show for dismiss path.
            self.ws._banner_label.setText("tip")
            self.ws._banner.setVisible(True)
        self.ws._dismiss_banner()
        self.assertFalse(self.ws._banner.isVisible())
        self.assertTrue(
            bool(
                QSettings("Turna", "CourseEditor").value(
                    "workshop/canvas_tips_dismissed", False
                )
            )
        )

    def test_bubble_pool_incremental_keeps_widgets(self) -> None:
        from src.widgets.resource_review_table import ResourceRow

        rows = [
            ResourceRow(
                chapter_index=0,
                resource_type="word",
                entry={"id": "w1", "term": "a", "translation": "A"},
                checked=True,
            ),
            ResourceRow(
                chapter_index=0,
                resource_type="word",
                entry={"id": "w2", "term": "b", "translation": "B"},
                checked=True,
            ),
        ]
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
        # Resumed project has merhaba in the pool.
        self.assertTrue(text)
        self.assertIn("词", text)

    def test_focus_summary_focused_when_dropped(self) -> None:
        self.ws.orbit_widget.add_knowledge_point(
            {"id": "w1", "term": "selam", "translation": "hi"}, "word"
        )
        self.ws._update_focus_summary()
        self.assertIn("聚焦", self.ws.orbit_widget.focus_summary.text())


if __name__ == "__main__":
    unittest.main()
