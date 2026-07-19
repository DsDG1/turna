"""Tests for GitLibraryDialog async handlers.

Uses fake git backend and fake workers so no real network or QThread is
needed. A QApplication is still required for widget construction.
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path
from typing import Any

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from PySide6.QtWidgets import QApplication, QMessageBox

from src.backend.course_adapter import CourseAdapter
from src.dialogs import git_library_dialog
from src.dialogs.git_library_dialog import GitLibraryDialog


class _FakeSignal:
    def __init__(self) -> None:
        self._callbacks: list[Any] = []

    def connect(self, callback: Any) -> None:
        self._callbacks.append(callback)

    def emit(self, *args: Any, **kwargs: Any) -> None:
        for cb in self._callbacks:
            cb(*args, **kwargs)


class _FakeWorker:
    """Fake background worker that calls the target synchronously in start()."""

    def __init__(self, target, *args):
        self._target = target
        self._args = args
        self.result_ready = _FakeSignal()
        self.error_occurred = _FakeSignal()
        self.completed = _FakeSignal()
        self.started = False
        self._result: Any = None
        self._error: str | None = None

    def start(self) -> None:
        self.started = True
        try:
            self._result = self._target(*self._args)
        except Exception as exc:
            self._error = str(exc)

    def emit_result(self) -> None:
        if self._error is not None:
            self.error_occurred.emit(self._error)
        else:
            self.result_ready.emit(self._result)


class _FakeGit:
    def __init__(self, clone_result: Any = None, error: str | None = None) -> None:
        self.clone_calls: list[tuple[str, Path]] = []
        self.pull_calls: list[Path] = []
        self.push_calls: list[tuple[Path, str]] = []
        self._clone_result = clone_result
        self._error = error

    def clone(self, url: str, local_dir: Path) -> Path:
        self.clone_calls.append((url, local_dir))
        if self._error is not None:
            raise RuntimeError(self._error)
        result = self._clone_result or local_dir
        # Pretend a real clone happened so _refresh_state sees a git repo.
        (result / ".git").mkdir(parents=True, exist_ok=True)
        return result

    def pull(self, local_dir: Path) -> None:
        self.pull_calls.append(local_dir)
        if self._error is not None:
            raise RuntimeError(self._error)

    def commit_and_push(self, local_dir: Path, message: str) -> None:
        self.push_calls.append((local_dir, message))
        if self._error is not None:
            raise RuntimeError(self._error)

    def status(self, local_dir: Path) -> Any:
        class _St:
            dirty = False
            ahead = 0
            behind = 0
            branch = "main"
        return _St()


class GitLibraryDialogAsyncTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.app = QApplication.instance() or QApplication([])

    def setUp(self) -> None:
        self.workers: list[_FakeWorker] = []
        self._orig_worker = git_library_dialog.AiRequestWorker
        git_library_dialog.AiRequestWorker = self._make_worker
        self._message_boxes: list[tuple[str, str]] = []
        self._orig_info = QMessageBox.information
        self._orig_critical = QMessageBox.critical
        QMessageBox.information = self._fake_information
        QMessageBox.critical = self._fake_critical

    def tearDown(self) -> None:
        git_library_dialog.AiRequestWorker = self._orig_worker
        QMessageBox.information = self._orig_info
        QMessageBox.critical = self._orig_critical

    def _fake_information(self, *args, **kwargs) -> None:
        self._message_boxes.append(("information", str(args[1:3])))

    def _fake_critical(self, *args, **kwargs) -> None:
        self._message_boxes.append(("critical", str(args[1:3])))

    def _make_worker(self, target, *args):
        # The last worker created matches the current request.
        worker = _FakeWorker(target, *args)
        self.workers.append(worker)
        return worker

    def _dialog(self, fake_git: _FakeGit) -> GitLibraryDialog:
        adapter = CourseAdapter()
        dlg = GitLibraryDialog(adapter)
        dlg.git = fake_git
        return dlg

    def test_connect_success_enables_buttons(self) -> None:
        fake_git = _FakeGit()
        dlg = self._dialog(fake_git)
        dlg.url_edit.setText("https://example.com/repo.git")
        dlg.dir_edit.setText("/tmp/clone")
        dlg._on_connect()

        self.assertEqual(len(self.workers), 1)
        worker = self.workers[0]
        self.assertTrue(worker.started)
        # Busy state disables action buttons.
        self.assertFalse(dlg.connect_btn.isEnabled())

        worker.emit_result()
        # After success clone_dir is set and buttons reflect connected state.
        self.assertEqual(dlg._clone_dir, Path("/tmp/clone"))
        self.assertTrue(dlg.open_btn.isEnabled())
        self.assertTrue(dlg.pull_btn.isEnabled())
        self.assertTrue(dlg.push_btn.isEnabled())

    def test_connect_failure_restores_buttons(self) -> None:
        fake_git = _FakeGit(error="network down")
        dlg = self._dialog(fake_git)
        dlg.url_edit.setText("https://example.com/repo.git")
        dlg.dir_edit.setText("/tmp/clone")
        dlg._on_connect()

        worker = self.workers[0]
        worker.emit_result()
        self.assertIsNone(dlg._clone_dir)
        self.assertTrue(dlg.connect_btn.isEnabled())
        self.assertFalse(dlg.pull_btn.isEnabled())

    def test_stale_worker_result_is_ignored(self) -> None:
        fake_git = _FakeGit()
        dlg = self._dialog(fake_git)
        dlg.url_edit.setText("https://example.com/repo.git")
        dlg.dir_edit.setText("/tmp/clone")
        dlg._on_connect()
        first = self.workers[0]

        # Trigger a second connect before the first finishes.
        dlg.url_edit.setText("https://example.com/other.git")
        dlg._on_connect()
        second = self.workers[1]

        first.emit_result()
        # _clone_dir must not be set by the stale worker.
        self.assertIsNone(dlg._clone_dir)

        second.emit_result()
        self.assertEqual(dlg._clone_dir, Path("/tmp/clone"))


if __name__ == "__main__":
    unittest.main()
