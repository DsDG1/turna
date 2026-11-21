"""Worker-identity guard in AiFixDialog.

A cancelled/superseded worker may still emit ``result_ready`` / ``error_occurred``
/ ``completed`` before terminating. The dialog's slots must ignore those stale
signals so they cannot overwrite the state of the new (current) worker.
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock

from PySide6.QtCore import QObject, Signal

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from tests._qtapp import qt_app


class _FakeWorker(QObject):
    """Drop-in for AiRequestWorker that records construction without starting
    a thread. Emits signals on demand to drive the slots."""

    result_ready = Signal(object)
    error_occurred = Signal(str)
    completed = Signal()

    def __init__(self, target, *args, parent=None, **kwargs) -> None:
        super().__init__(parent)
        self._target = target
        self._args = args
        self._kwargs = kwargs
        self._cancelled = False

    def cancel(self) -> None:
        self._cancelled = True

    def isRunning(self) -> bool:
        return False

    def start(self, *args, **kwargs) -> None:
        # No real thread; the test drives signals manually.
        pass


class AiFixDialogGuardTest(unittest.TestCase):
    def setUp(self) -> None:
        self._app = qt_app()
        self._dialogs: list = []
        # Keep AiRequestWorker patched for the whole test: dlg._run() is
        # invoked both during __init__ and again inside each test method, so
        # exiting the patch early would spawn a real QThread that crashes Qt
        # on Windows teardown ("QThread: Destroyed while thread is still running").
        patcher = unittest.mock.patch(
            "src.dialogs.ai_fix_dialog.AiRequestWorker", _FakeWorker
        )
        patcher.start()
        self.addCleanup(patcher.stop)

    def tearDown(self) -> None:
        for dlg in self._dialogs:
            dlg.close()
            dlg.deleteLater()
        self._dialogs.clear()
        self._app.processEvents()

    def _make_dialog(self):
        from src.dialogs.ai_fix_dialog import AiFixDialog

        problems = [{"level": "error", "path": "u", "message": "bad"}]
        node_json = {"id": "s1", "name": "S1", "units": []}
        course_context = {"node_kind": "section"}
        config = MagicMock()
        config.is_complete = True
        dlg = AiFixDialog(problems, node_json, course_context, config)
        self._dialogs.append(dlg)
        return dlg

    def test_stale_worker_result_is_ignored(self):
        dlg = self._make_dialog()
        stale = dlg._worker
        # Start a new worker (supersede the stale one).
        dlg._run()
        current = dlg._worker
        self.assertIsNot(stale, current)
        # Late result from the stale worker must not touch the dialog state.
        dlg._on_result(stale, {"id": "stale"})
        self.assertIsNone(dlg._corrected)
        # Result from the current worker is applied.
        dlg._on_result(current, {"id": "fresh"})
        self.assertEqual(dlg._corrected, {"id": "fresh"})

    def test_stale_worker_error_is_ignored(self):
        dlg = self._make_dialog()
        stale = dlg._worker
        dlg._run()
        current = dlg._worker
        dlg._on_error(stale, "stale boom")
        self.assertEqual(dlg._last_error_message, "")
        dlg._on_error(current, "real boom")
        self.assertEqual(dlg._last_error_message, "real boom")

    def test_stale_completed_does_not_clear_current_worker(self):
        dlg = self._make_dialog()
        stale = dlg._worker
        dlg._run()
        current = dlg._worker
        # Late completion from the stale worker must not clear the current one.
        dlg._on_completed(stale)
        self.assertIs(dlg._worker, current)
        # Completion from the current worker clears it.
        dlg._on_completed(current)
        self.assertIsNone(dlg._worker)


if __name__ == "__main__":
    unittest.main()
