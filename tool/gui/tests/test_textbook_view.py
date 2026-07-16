"""Lightweight tests for TextbookImportDialog (view layer).

These tests instantiate the dialog with a real QApplication but do **not** run
the event loop, so offscreen-platform hangs are avoided.
"""
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from PySide6.QtCore import Qt
from PySide6.QtWidgets import QApplication

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.ai_generator import AiApiConfig
from src.backend.import_strategy import ImportStrategy
from src.backend.knowledge_schema import coerce_knowledge_points
from src.backend.markdown_chopper import split_chapters
from src.backend.textbook_project import TextbookProject
from src.dialogs.textbook_import_dialog import TextbookImportDialog


class _FakeAdapter:
    """Minimal adapter for preview/strategy tests."""

    def __init__(self, sections=None, vocab=None):
        self.sections = sections or []
        self.index = {"sections": []}
        self.vocab = vocab or []
        self.expressions = []
        self.grammar_points = []


def _sample_md() -> str:
    return "## 1 Merhaba\nhello\n## 2 Aile\nfamily\n"


def _sample_kp():
    return coerce_knowledge_points(
        {
            "words": [
                {"term": "merhaba", "translation": "hello"},
                {"term": "aile", "translation": "family"},
            ],
            "expressions": [{"term": "Selam!", "translation": "Hi!"}],
            "grammarPoints": [{"title": "Greetings", "explanation": "hi"}],
        }
    )


class _TestApp:
    _app: QApplication | None = None

    @classmethod
    def get(cls) -> QApplication:
        if cls._app is None:
            cls._app = QApplication.instance() or QApplication([])
        return cls._app


class TextbookImportViewTest(unittest.TestCase):
    def setUp(self) -> None:
        _TestApp.get()
        self.dlg = TextbookImportDialog(None, None)

    def test_constructs_without_crash(self) -> None:
        self.assertEqual(self.dlg.windowTitle(), "导入教材（Beta）")
        self.assertIsNotNone(self.dlg._controller)

    def test_load_file_populates_chapters(self) -> None:
        with tempfile.NamedTemporaryFile(mode="w", suffix=".md", delete=False) as f:
            f.write(_sample_md())
            path = Path(f.name)
        try:
            self.dlg._load_file(path)
            self.assertEqual(len(self.dlg._controller.chapters), 2)
            self.assertEqual(self.dlg._chapter_list.count(), 2)
        finally:
            path.unlink()

    def test_select_all_and_invert(self) -> None:
        self.dlg._controller._md = _sample_md()
        self.dlg._controller._split_into_chapters()
        self.dlg._populate_chapters()
        self.dlg._set_all_chapters(False)
        self.assertTrue(all(cr.keep is False for cr in self.dlg._controller.chapters))
        self.dlg._invert_chapters()
        self.assertTrue(all(cr.keep is True for cr in self.dlg._controller.chapters))

    def test_import_emits_sections_for_kept_chapters(self) -> None:
        self.dlg._controller._md = _sample_md()
        self.dlg._controller._split_into_chapters()
        self.dlg._controller._chapters[0].knowledge = _sample_kp()
        self.dlg._controller._chapters[1].knowledge = _sample_kp()
        self.dlg._populate_review()
        captured: list = []
        self.dlg.sections_ready.connect(lambda secs, _strat: captured.extend(secs))
        self.dlg._on_import()
        self.assertEqual(len(captured), 2)

    def test_review_table_round_trips_edits(self) -> None:
        self.dlg._controller._md = _sample_md()
        self.dlg._controller._split_into_chapters()
        self.dlg._controller._chapters[0].knowledge = _sample_kp()
        self.dlg._populate_review()
        self.assertGreaterEqual(self.dlg._review_table.row_count(), 2)
        self.dlg._review_table.set_checked(0, False)
        self.dlg._on_import()
        kept_terms = [w["term"] for w in self.dlg._controller.chapters[0].knowledge.words]
        self.assertNotIn("merhaba", kept_terms)

    def test_dialog_restores_project_state(self) -> None:
        project = TextbookProject.create(
            project_id="p1",
            name="Resume",
            source_path=Path("/tmp/sample.md"),
            markdown=_sample_md(),
        )
        ch = split_chapters(_sample_md())
        project.set_chapters(
            [(ch[0], True, _sample_kp(), ""), (ch[1], True, None, "")]
        )
        project.current_step = 4
        dlg = TextbookImportDialog(None, None, project=project)
        self.assertEqual(dlg._controller.markdown, _sample_md())
        self.assertEqual(len(dlg._controller.chapters), 2)
        self.assertIsNotNone(dlg._controller.chapters[0].knowledge)


class ImportPreviewPageTest(unittest.TestCase):
    """bookplan2 Phase 4: strategy radios + bulk preview on the import page."""

    def setUp(self) -> None:
        _TestApp.get()
        self.dlg = TextbookImportDialog(None, None)
        self.dlg._controller._md = _sample_md()
        self.dlg._controller._split_into_chapters()
        self.dlg._controller._chapters[0].knowledge = _sample_kp()
        self.dlg._controller._chapters[1].knowledge = _sample_kp()
        # Populate the review table so _goto_import_preview / _on_import do not
        # wipe knowledge via apply_review_rows([]) (which would make build_sections
        # fail and pop a modal QMessageBox, hanging offscreen).
        self.dlg._populate_review()

    def test_strategy_radios_present_with_default_merge(self) -> None:
        self.assertEqual(len(self.dlg._strategy_buttons), 4)
        self.assertEqual(self.dlg._current_strategy(), ImportStrategy.MERGE.value)

    def test_goto_import_preview_populates_panel(self) -> None:
        self.dlg.adapter = _FakeAdapter()
        self.dlg._goto_import_preview()
        self.assertEqual(self.dlg._stack.currentIndex(), 5)  # STEP_IMPORT
        self.assertEqual(self.dlg._preview_panel._table.rowCount(), 2)

    def test_strategy_change_refreshes_preview_action(self) -> None:
        # Chapter 0's section id collides with the loaded course.
        self.dlg.adapter = _FakeAdapter(sections=[{"id": "ch-1-merhaba-1"}])
        self.dlg._goto_import_preview()
        # Default merge strategy -> colliding section is an interactive merge.
        self.assertEqual(self.dlg._preview_panel.previews[0].action, "merge")
        # Switch to append_as_new -> preview re-plans with a fresh target id.
        self.dlg._strategy_buttons[ImportStrategy.APPEND_AS_NEW.value].setChecked(True)
        self.assertEqual(self.dlg._current_strategy(), ImportStrategy.APPEND_AS_NEW.value)
        self.assertEqual(self.dlg._preview_panel.previews[0].action, "append_new")
        self.assertEqual(
            self.dlg._preview_panel.previews[0].target_id, "ch-1-merhaba-1-2"
        )

    def test_confirm_import_emits_sections_with_strategy(self) -> None:
        self.dlg.adapter = _FakeAdapter()
        captured: list = []
        seen_strategies: list = []
        self.dlg.sections_ready.connect(
            lambda secs, strat: (captured.extend(secs), seen_strategies.append(strat))
        )
        # Patch the modal QMessageBox so a build failure cannot hang offscreen.
        with patch("src.dialogs.textbook_import_dialog.QMessageBox"):
            self.dlg._on_import()
        self.assertEqual(len(captured), 2)
        self.assertEqual(seen_strategies, [ImportStrategy.MERGE.value])


class ExtractionOptionsTest(unittest.TestCase):
    """bookplan2 Phase 5: textbook-type preset + concurrency + usage label."""

    def setUp(self) -> None:
        _TestApp.get()
        self.dlg = TextbookImportDialog(None, None)

    def test_preset_combo_has_four_types_and_defaults_to_general(self) -> None:
        self.assertEqual(self.dlg._preset_combo.count(), 4)
        self.dlg._apply_preset()
        self.assertEqual(self.dlg._controller.preset.name, "general")

    def test_preset_combo_changes_controller_preset(self) -> None:
        # index 2 = dialogue (general/grammar/dialogue/reading)
        self.dlg._preset_combo.setCurrentIndex(2)
        self.assertEqual(self.dlg._controller.preset.name, "dialogue")

    def test_concurrency_spin_sets_controller(self) -> None:
        self.dlg._concurrency_spin.setValue(3)
        self.assertEqual(self.dlg._controller.max_concurrent, 3)

    def test_usage_label_updates_with_project_total(self) -> None:
        self.dlg._ai_config = lambda: type("C", (), {"model": "deepseek-chat"})()
        self.dlg._on_usage_update(
            0,
            {"prompt_tokens": 100, "completion_tokens": 50, "total_tokens": 150},
            {"prompt_tokens": 100, "completion_tokens": 50, "total_tokens": 150},
        )
        text = self.dlg._usage_label.text()
        self.assertIn("项目用量", text)
        self.assertIn("150", text)


if __name__ == "__main__":
    unittest.main()
