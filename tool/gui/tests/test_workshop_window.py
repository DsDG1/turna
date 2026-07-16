"""Tests for WorkshopWindow (connectplan Phase 2)."""
from __future__ import annotations

import os
import sys
import tempfile
import unittest
from pathlib import Path

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from PySide6.QtWidgets import QApplication  # noqa: E402

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


def _sample_md() -> str:
    return "## 1 Merhaba\nhello\n"


def _resumed_project(store: TextbookProjectStore) -> TextbookProject:
    project = store.create_project(name="Book", source_path=None)
    ch = split_chapters(_sample_md())
    kp = coerce_knowledge_points(
        {"words": [{"term": "merhaba", "translation": "hello"}]}
    )
    project.set_chapters([(ch[0], True, kp, "")])
    project.update_resource_pool()
    project.current_step = 4  # STEP_REVIEW
    store.save_project(project)
    return project


class WorkshopWindowTest(unittest.TestCase):
    def setUp(self) -> None:
        _App.get()
        self.tmp = tempfile.TemporaryDirectory()
        self.store = TextbookProjectStore(base_dir=Path(self.tmp.name))
        self.win = WorkshopWindow(None, None, store=self.store)

    def tearDown(self) -> None:
        self.win.deleteLater()
        self.tmp.cleanup()

    def test_constructs_on_project_stage(self) -> None:
        self.assertEqual(self.win.windowTitle(), "课程工坊")
        self.assertEqual(self.win._stack.currentIndex(), 0)
        self.assertEqual(len(self.win._stage_buttons), 5)
        # Only the project stage is reachable before a project is chosen.
        self.assertTrue(self.win._stage_buttons[0].isEnabled())
        for btn in self.win._stage_buttons[1:]:
            self.assertFalse(btn.isEnabled())

    def test_project_selection_builds_panel_and_unlocks_stages(self) -> None:
        project = _resumed_project(self.store)
        self.win._on_project_selected(project)
        self.assertIsNotNone(self.win._panel)
        self.assertEqual(self.win._stack.currentIndex(), 1)
        # Panel stepper hidden — the workshop provides the outer navigation.
        self.assertTrue(self.win._panel._stepper_widget.isHidden())
        # Resumed at review (knowledge page) → stages up to 设计 enabled.
        self.assertTrue(self.win._stage_buttons[1].isEnabled())  # 素材
        self.assertTrue(self.win._stage_buttons[2].isEnabled())  # 知识
        self.assertTrue(self.win._stage_buttons[3].isEnabled())  # 设计
        self.assertFalse(self.win._stage_buttons[4].isEnabled())  # 导入
        # Panel landed on the knowledge page.
        self.assertEqual(self.win._panel._stack.currentIndex(), 1)

    def test_stage_navigation_round_trip(self) -> None:
        project = _resumed_project(self.store)
        self.win._on_project_selected(project)
        self.win._go_to_stage(0)
        self.assertEqual(self.win._stack.currentIndex(), 0)
        self.win._go_to_stage(1)  # 素材 → panel page 0
        self.assertEqual(self.win._stack.currentIndex(), 1)
        self.assertEqual(self.win._panel._stack.currentIndex(), 0)
        # Data survives the round trip (chapters still loaded).
        self.assertEqual(len(self.win._panel._controller.chapters), 1)

    def test_embedded_panel_does_not_close_on_import_success(self) -> None:
        project = _resumed_project(self.store)
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
        project = _resumed_project(self.store)
        self.win._on_project_selected(project)
        captured: list = []
        self.win.sections_ready.connect(lambda s, st: captured.append((s, st)))
        self.win._panel.sections_ready.emit([{"id": "s1"}], "merge")
        self.assertEqual(captured, [([{"id": "s1"}], "merge")])


class WorkshopDesignStageTest(unittest.TestCase):
    """Phase 3: grounded design stage inside the workshop."""

    def setUp(self) -> None:
        _App.get()
        self.tmp = tempfile.TemporaryDirectory()
        self.store = TextbookProjectStore(base_dir=Path(self.tmp.name))
        self.win = WorkshopWindow(None, None, store=self.store)
        self.project = _resumed_project(self.store)
        self.win._on_project_selected(self.project)

    def tearDown(self) -> None:
        self.win.deleteLater()
        self.tmp.cleanup()

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
