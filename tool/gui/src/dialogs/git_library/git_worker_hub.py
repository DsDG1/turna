"""Shared async git-call plumbing (B5).

Extracted from ``GitLibraryDialog`` so ``textbook_library_dialog``'s mirrored
plumbing can reuse it too. Runs a blocking git call on an ``AiRequestWorker``,
cancels any still-running previous call, and reports busy state / refreshes
through the owning dialog (``_set_git_busy`` / ``_refresh_state``).
"""
from __future__ import annotations

import functools
import logging
from typing import Any

from PySide6.QtCore import QObject

from src.application.ai_request_worker import AiRequestWorker, safe_disconnect

logger = logging.getLogger(__name__)


class GitWorkerHub(QObject):
    """Run blocking git calls on background workers (one in flight per hub)."""

    def __init__(self, owner: Any) -> None:
        super().__init__(owner)
        self._owner = owner  # GitLibraryDialog (or textbook_library_dialog)
        self._worker: Any | None = None

    def run_async(
        self,
        label: str,
        fn,
        *args,
        on_ok=None,
        ok_title: str = "",
        ok_message: str = "",
        error_title: str = "",
        on_error=None,
    ) -> None:
        """Run ``fn(*args)`` in a background worker.

        Cancels any still-running previous git worker before starting the new
        one: without this, firing a second op while the first is in flight
        would leave the old QThread running (its result is dropped by the
        ``worker is not self._worker`` guard in ``_on_result``) and could race
        on the shared git clone's index. (B5)
        """
        prev = self._worker
        if prev is not None:
            try:
                if prev.isRunning():
                    prev.cancel()
                for sig_name in ("result_ready", "error_occurred", "completed", "finished"):
                    safe_disconnect(getattr(prev, sig_name, None))
            except Exception:  # noqa: BLE001 — defensive; never block new op
                logger.debug("dialogs/git_library/git_worker_hub.py:run_async best-effort step failed", exc_info=True)
        self._owner._set_git_busy(True, label)
        worker = AiRequestWorker(fn, *args)
        worker.result_ready.connect(
            functools.partial(
                self._on_worker_result, worker, on_ok, ok_title, ok_message
            )
        )
        worker.error_occurred.connect(
            functools.partial(self._on_worker_error, worker, error_title, on_error)
        )
        self._worker = worker
        worker.start()

    def _on_worker_result(
        self,
        worker: Any,
        on_ok: Any,
        ok_title: str,
        ok_message: str,
        result: Any,
    ) -> None:
        self._on_result(worker, result, on_ok, ok_title, ok_message)

    def _on_worker_error(
        self,
        worker: Any,
        error_title: str,
        on_error: Any,
        msg: str,
    ) -> None:
        self._on_error(worker, msg, error_title, on_error)

    def _on_result(
        self,
        worker: Any,
        result: Any,
        on_ok,
        ok_title: str,
        ok_message: str,
    ) -> None:
        if worker is not self._worker:
            return
        self._worker = None
        self._owner._set_git_busy(False, "")
        if on_ok is not None:
            on_ok(result)
        refresh = getattr(self._owner, "_refresh_state", None)
        if refresh is not None:
            refresh()
        if ok_title:
            from PySide6.QtWidgets import QMessageBox

            QMessageBox.information(self._owner, ok_title, ok_message)

    def _on_error(self, worker: Any, message: str, error_title: str, on_error=None) -> None:
        if worker is not self._worker:
            return
        self._worker = None
        self._owner._set_git_busy(False, "")
        refresh = getattr(self._owner, "_refresh_state", None)
        if refresh is not None:
            refresh()
        if on_error is not None:
            on_error(message)
        elif error_title:
            from PySide6.QtWidgets import QMessageBox

            QMessageBox.critical(self._owner, error_title, message)
