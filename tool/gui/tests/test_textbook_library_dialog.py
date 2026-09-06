"""Tests for TextbookLibraryDialog."""
from __future__ import annotations

import sys
import tempfile
import unittest
import unittest.mock
from pathlib import Path

from PySide6.QtWidgets import QMessageBox

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.textbook_project_store import TextbookProjectStore
from src.dialogs.textbook_library_dialog import TextbookLibraryDialog
from tests._qtapp import _App as _TestApp  # noqa: E402


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


class GitAsyncTest(unittest.TestCase):
    """Git import/publish must run on a worker (no main-thread network)."""

    def setUp(self) -> None:
        _TestApp.get()
        self.tmp = tempfile.TemporaryDirectory()
        self.store = TextbookProjectStore(base_dir=Path(self.tmp.name))
        self.dlg = TextbookLibraryDialog(store=self.store)

    def tearDown(self) -> None:
        self.tmp.cleanup()

    @staticmethod
    def _wait_git_finished(dlg, timeout: float = 5.0) -> None:
        import time

        from tests._qtapp import qt_app

        app = qt_app()
        t0 = time.perf_counter()
        while dlg._git_worker is not None:
            app.processEvents()
            if time.perf_counter() - t0 > timeout:
                raise AssertionError("git worker did not finish in time")

    def test_run_git_async_success_and_busy_state(self) -> None:
        seen: list[str] = []

        def _fake_clone(url, local_dir):
            seen.append(url)
            return "ok"

        self.dlg._run_git_async(
            "正在克隆…", _fake_clone, "https://example.com/r.git", Path("/tmp/clone"),
            on_ok=lambda result: seen.append(str(result)),
        )
        self.assertFalse(self.dlg._from_git_btn.isEnabled())
        # The dialog itself is never shown() in tests, so query the explicit
        # hide flag rather than isVisible().
        self.assertFalse(self.dlg._git_busy_label.isHidden())
        self._wait_git_finished(self.dlg)
        self.assertEqual(seen, ["https://example.com/r.git", "ok"])
        self.assertTrue(self.dlg._from_git_btn.isEnabled())
        self.assertTrue(self.dlg._git_busy_label.isHidden())

    def test_run_git_async_error_shows_critical(self) -> None:
        def _boom():
            raise RuntimeError("network down")

        with unittest.mock.patch.object(
            QMessageBox, "critical", return_value=None
        ) as critic:
            self.dlg._run_git_async("正在克隆…", _boom)
            self._wait_git_finished(self.dlg)
            critic.assert_called_once()
            self.assertIn("network down", critic.call_args[0][2])
        self.assertTrue(self.dlg._from_git_btn.isEnabled())

    def test_publish_chain_runs_in_worker(self) -> None:
        """The publish chain is the worker target: pure backend, no Qt calls."""
        summary = self.store.create_project(name="P", source_path=None)
        project = self.store.load_project(summary.project_id)
        project.design["draft_sections"] = [
            {"id": "s1", "name": "Section 1", "units": []},
            {"id": "s2", "name": "Section 2", "units": []},
        ]
        self.store.save_project(project)

        pushed: list[str] = []
        fake_git = unittest.mock.MagicMock()
        fake_git.commit_and_push.side_effect = (
            lambda local_dir, msg: pushed.append(msg)
        )
        with tempfile.TemporaryDirectory() as clone_dir:
            remote = unittest.mock.MagicMock()
            remote.name = "r1"
            remote.url = "https://example.com/r.git"
            remote.local_dir = str(clone_dir)
            with unittest.mock.patch(
                "src.application.git_remote_catalog.load_remotes",
                return_value=[remote],
            ), unittest.mock.patch(
                "src.application.git_remote_catalog.mark_synced",
            ), unittest.mock.patch(
                "src.backend.git_library.GitLibrary", return_value=fake_git
            ), unittest.mock.patch(
                "PySide6.QtWidgets.QInputDialog.getItem",
                return_value=("r1 — https://example.com/r.git", True),
            ), unittest.mock.patch(
                "PySide6.QtWidgets.QMessageBox.information", return_value=None
            ) as info:
                self.dlg._refresh_list()
                self.dlg._table.selectRow(0)
                self.dlg._on_publish_to_git()
                self.assertFalse(self.dlg._publish_git_btn.isEnabled())
                self._wait_git_finished(self.dlg)
                info.assert_called_once()
                self.assertTrue(
                    (Path(clone_dir) / "sections" / "s1.json").exists()
                )
        self.assertEqual(len(pushed), 1)
        self.assertIn("2 sections", pushed[0])


if __name__ == "__main__":
    unittest.main()
