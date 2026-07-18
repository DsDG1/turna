"""Tests for TextbookLibraryDialog."""
from __future__ import annotations

import sys
import tempfile
import unittest
import unittest.mock
from pathlib import Path

from PySide6.QtWidgets import QApplication, QMessageBox

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.textbook_project_store import TextbookProjectStore
from src.dialogs.textbook_library_dialog import TextbookLibraryDialog


class _TestApp:
    _app: QApplication | None = None

    @classmethod
    def get(cls) -> QApplication:
        if cls._app is None:
            cls._app = QApplication.instance() or QApplication([])
        return cls._app


class TextbookLibraryDialogTest(unittest.TestCase):
    def setUp(self) -> None:
        _TestApp.get()
        self.tmp = tempfile.TemporaryDirectory()
        self.store = TextbookProjectStore(base_dir=Path(self.tmp.name))
        self.dlg = TextbookLibraryDialog(store=self.store)

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def test_constructs_and_shows_empty(self) -> None:
        self.assertEqual(self.dlg.windowTitle(), "课本项目库")
        self.assertFalse(self.dlg._empty_label.isHidden())
        self.assertTrue(self.dlg._table.isHidden())

    def test_lists_existing_projects(self) -> None:
        self.store.create_project(name="A", source_path=None)
        self.store.create_project(name="B", source_path=None)
        self.dlg._refresh_list()
        self.assertEqual(self.dlg._table.rowCount(), 2)
        self.assertFalse(self.dlg._empty_label.isVisible())

    def test_delete_refreshes_list(self) -> None:
        project = self.store.create_project(name="DeleteMe", source_path=None)
        self.dlg._refresh_list()
        self.assertEqual(self.dlg._table.rowCount(), 1)
        self.dlg._table.selectRow(0)
        with unittest.mock.patch.object(
            QMessageBox, "question", return_value=QMessageBox.StandardButton.Yes
        ):
            self.dlg._on_delete()
        self.assertEqual(self.dlg._table.rowCount(), 0)
        self.assertIsNone(self.store.load_project(project.project_id))

    def test_new_project_uses_picked_languages(self) -> None:
        """P0-3: language pair is chosen at creation, no longer hardcoded."""
        with tempfile.NamedTemporaryFile(suffix=".md", delete=False) as f:
            path = Path(f.name)
        try:
            with unittest.mock.patch(
                "src.dialogs.textbook_library_dialog.QFileDialog.getOpenFileName",
                return_value=(str(path), ""),
            ), unittest.mock.patch.object(
                self.dlg, "_pick_languages", return_value=("Spanish", "English")
            ):
                self.dlg._on_new()
            project = self.dlg.selected_project
            self.assertIsNotNone(project)
            self.assertEqual(project.language, "Spanish")
            self.assertEqual(project.source_language, "English")
            loaded = self.store.load_project(project.project_id)
            self.assertEqual(loaded.language, "Spanish")
        finally:
            path.unlink()

    def test_new_project_cancel_languages_creates_nothing(self) -> None:
        with tempfile.NamedTemporaryFile(suffix=".md", delete=False) as f:
            path = Path(f.name)
        try:
            with unittest.mock.patch(
                "src.dialogs.textbook_library_dialog.QFileDialog.getOpenFileName",
                return_value=(str(path), ""),
            ), unittest.mock.patch.object(
                self.dlg, "_pick_languages", return_value=None
            ):
                self.dlg._on_new()
            self.assertIsNone(self.dlg.selected_project)
            self.assertEqual(self.store.list_projects(), [])
        finally:
            path.unlink()

    def test_new_blank_project(self) -> None:
        """Phase A: 空白 AI 项目 — no source file, chosen name/languages."""
        with unittest.mock.patch.object(
            self.dlg, "_pick_blank_meta", return_value=("我的课", "Japanese", "English")
        ):
            self.dlg._on_new_blank()
        project = self.dlg.selected_project
        self.assertIsNotNone(project)
        self.assertEqual(project.name, "我的课")
        self.assertIsNone(project.source_path)
        self.assertEqual(project.language, "Japanese")
        self.assertEqual(project.source_language, "English")
        loaded = self.store.load_project(project.project_id)
        self.assertIsNotNone(loaded)

    def test_new_blank_cancel_creates_nothing(self) -> None:
        with unittest.mock.patch.object(
            self.dlg, "_pick_blank_meta", return_value=None
        ):
            self.dlg._on_new_blank()
        self.assertIsNone(self.dlg.selected_project)
        self.assertEqual(self.store.list_projects(), [])

    def test_blank_project_shown_as_pure_ai(self) -> None:
        self.store.create_project(name="Blank", source_path=None)
        self.dlg._refresh_list()
        self.assertEqual(self.dlg._table.item(0, 1).text(), "—（纯 AI 项目）")


if __name__ == "__main__":
    unittest.main()
