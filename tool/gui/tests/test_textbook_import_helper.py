"""Tests for app.py's _import_section_dict / _import_section_dict_result helper.

These tests exercise the import-into-course logic against a real CourseAdapter
with modal dialogs patched out. They do not need the full dialog UI.
"""
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

from PySide6.QtWidgets import QApplication, QDialog

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.course_adapter import CourseAdapter
from src.backend.knowledge_schema import coerce_knowledge_points
from src.backend.markdown_chopper import split_chapters
from src.backend.textbook_to_course import build_section_from_chapter


def _sample_kp():
    return coerce_knowledge_points(
        {
            "words": [
                {"term": "merhaba", "translation": "hello", "tags": ["greeting"]},
                {"term": "günaydın", "translation": "good morning"},
            ],
            "expressions": [{"term": "Selam!", "translation": "Hi!", "tags": ["greeting"]}],
            "grammarPoints": [{"title": "Greetings", "explanation": "common greetings"}],
        }
    )


def _build_main_window():
    """Minimal MainWindow wired to a temp course dir, modals suppressed."""
    from src.app import MainWindow

    fake_settings = MagicMock()
    fake_settings.value.return_value = "[]"
    with patch("src.app.QSettings", return_value=fake_settings):
        win = MainWindow()
    return win


class _TestApp:
    _app: QApplication | None = None

    @classmethod
    def get(cls) -> QApplication:
        if cls._app is None:
            cls._app = QApplication.instance() or QApplication([])
        return cls._app


class ImportSectionDictTest(unittest.TestCase):
    def setUp(self) -> None:
        _TestApp.get()
        self.win = _build_main_window()
        self.tmp = tempfile.TemporaryDirectory()
        self.win.course_dir = Path(self.tmp.name)
        self.win.adapter = CourseAdapter()
        self.win.adapter.course_dir = Path(self.tmp.name)
        self.win.adapter.index = {
            "version": 5,
            "language": "tr",
            "displayName": "Turkish",
            "sections": [],
        }
        self.win.adapter.sections = []
        self.win.tree._on_command_changed = lambda: None

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def _sample_section(self) -> dict:
        chapter = split_chapters("## 1 Merhaba\n")[0]
        kp = _sample_kp()
        return build_section_from_chapter(chapter, kp, 1)

    def test_imports_new_section(self) -> None:
        section = self._sample_section()
        with patch.object(self.win, "statusBar") as bar, patch("src.app.QMessageBox") as mb:
            outcome = self.win._import_section_dict(section)
        self.assertEqual(outcome, "imported")
        self.assertEqual(len(self.win.adapter.sections), 1)
        self.assertEqual(len(self.win.adapter.vocab), 2)
        self.assertEqual(len(self.win.adapter.expressions), 1)
        self.assertEqual(len(self.win.adapter.grammar_points), 1)

    def test_blocked_on_missing_id(self) -> None:
        section = self._sample_section()
        section["id"] = ""
        with patch("src.app.QMessageBox") as mb:
            outcome = self.win._import_section_dict(section)
        self.assertEqual(outcome, "blocked")
        self.assertEqual(len(self.win.adapter.sections), 0)

    def test_merge_when_id_exists_and_user_accepts(self) -> None:
        section = self._sample_section()
        with patch.object(self.win, "statusBar"), patch("src.app.QMessageBox"):
            self.win._import_section_dict(section)
        with patch.object(self.win, "statusBar"), patch("src.app.QMessageBox"), patch(
            "src.dialogs.ai.ai_merge_preview_dialog.AiMergePreviewDialog"
        ) as dlg_cls:
            dlg = MagicMock()
            dlg.exec.return_value = QDialog.DialogCode.Accepted
            dlg.plan.return_value = self.win.adapter.plan_section_merge(section["id"], section)
            dlg_cls.return_value = dlg
            outcome = self.win._import_section_dict(section)
        self.assertEqual(outcome, "merged")
        self.assertEqual(len(self.win.adapter.sections), 1)

    def test_merge_skipped_when_user_cancels(self) -> None:
        section = self._sample_section()
        with patch.object(self.win, "statusBar"), patch("src.app.QMessageBox"):
            self.win._import_section_dict(section)
        with patch.object(self.win, "statusBar"), patch("src.app.QMessageBox"), patch(
            "src.dialogs.ai.ai_merge_preview_dialog.AiMergePreviewDialog"
        ) as dlg_cls:
            dlg = MagicMock()
            dlg.exec.return_value = QDialog.DialogCode.Rejected
            dlg_cls.return_value = dlg
            outcome = self.win._import_section_dict(section)
        self.assertEqual(outcome, "skipped")

    def test_result_version_returns_structured_outcome(self) -> None:
        section = self._sample_section()
        with patch.object(self.win, "statusBar"), patch("src.app.QMessageBox"):
            result = self.win._import_section_dict_result(section)
        self.assertEqual(result.outcome, "success")
        self.assertEqual(result.details.get("outcome"), "imported")
        self.assertEqual(result.details.get("section_id"), section["id"])


class ImportStrategyTest(unittest.TestCase):
    """bookplan2 Phase 4: skip / force_replace / append_as_new strategies."""

    def setUp(self) -> None:
        _TestApp.get()
        self.win = _build_main_window()
        self.tmp = tempfile.TemporaryDirectory()
        self.win.course_dir = Path(self.tmp.name)
        self.win.adapter = CourseAdapter()
        self.win.adapter.course_dir = Path(self.tmp.name)
        self.win.adapter.index = {
            "version": 5,
            "language": "tr",
            "displayName": "Turkish",
            "sections": [],
        }
        self.win.adapter.sections = []
        self.win.tree._on_command_changed = lambda: None

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def _sample_section(self) -> dict:
        chapter = split_chapters("## 1 Merhaba\n")[0]
        kp = _sample_kp()
        return build_section_from_chapter(chapter, kp, 1)

    def _import_once(self, section) -> None:
        with patch.object(self.win, "statusBar"), patch("src.app.QMessageBox"):
            self.win._import_section_dict(section)

    def test_skip_strategy_skips_existing(self) -> None:
        from src.backend.import_strategy import ImportStrategy

        section = self._sample_section()
        self._import_once(section)
        self.assertEqual(len(self.win.adapter.sections), 1)
        with patch.object(self.win, "statusBar"), patch("src.app.QMessageBox"):
            outcome = self.win._import_section_dict(
                section, strategy=ImportStrategy.SKIP_EXISTING.value
            )
        self.assertEqual(outcome, "skipped")
        self.assertEqual(len(self.win.adapter.sections), 1)

    def test_force_replace_strategy_overwrites(self) -> None:
        from src.backend.import_strategy import ImportStrategy

        section = self._sample_section()
        self._import_once(section)
        original_lesson_count = len(section["units"][0]["lessons"])
        # Mutate the incoming section so we can detect the overwrite.
        replaced = self._sample_section()
        replaced["name"] = "Replaced Title"
        with patch.object(self.win, "statusBar"), patch("src.app.QMessageBox"):
            outcome = self.win._import_section_dict(
                replaced, strategy=ImportStrategy.FORCE_REPLACE.value
            )
        self.assertEqual(outcome, "replaced")
        self.assertEqual(len(self.win.adapter.sections), 1)  # not duplicated
        self.assertEqual(self.win.adapter.sections[0]["name"], "Replaced Title")
        self.assertEqual(
            len(self.win.adapter.sections[0]["units"][0]["lessons"]), original_lesson_count
        )

    def test_append_new_strategy_creates_unique_id(self) -> None:
        from src.backend.import_strategy import ImportStrategy

        section = self._sample_section()
        self._import_once(section)
        with patch.object(self.win, "statusBar"), patch("src.app.QMessageBox"):
            outcome = self.win._import_section_dict(
                section, strategy=ImportStrategy.APPEND_AS_NEW.value
            )
        self.assertEqual(outcome, "imported")
        self.assertEqual(len(self.win.adapter.sections), 2)  # original + new
        ids = {s.get("id") for s in self.win.adapter.sections}
        self.assertIn(section["id"], ids)
        self.assertIn(f"{section['id']}-2", ids)

    def test_default_strategy_preserves_ai_generator_behaviour(self) -> None:
        # No strategy arg -> merge on collision, append otherwise (unchanged).
        section = self._sample_section()
        with patch.object(self.win, "statusBar"), patch("src.app.QMessageBox"):
            outcome = self.win._import_section_dict(section)
        self.assertEqual(outcome, "imported")


if __name__ == "__main__":
    unittest.main()
