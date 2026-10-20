"""Background AI request worker + small shared helpers.

Extracted from the original monolithic ``ai_generator_dialog.py`` (guiplan2 P5),
then relocated from ``src/dialogs/ai/worker.py`` to the application layer so
``src/application/**`` no longer reaches into the dialogs UI package.
``AiRequestWorker`` runs a synchronous AI call in a QThread and forwards
result / error / streaming-chunk / usage signals to the UI thread.
"""
from __future__ import annotations

import logging
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from PySide6.QtCore import QThread, Signal
from PySide6.QtWidgets import QWidget

from src.backend.ai import AiCancelled

logger = logging.getLogger(__name__)


@dataclass
class AttachmentRecord:
    """A user-supplied attachment copied to a temp file + its extracted content.

    Renamed from the private ``_AttachmentRecord``; the leading underscore is
    dropped now that it is shared across modules. The dataclass is plain data
    with no Qt dependency so it can be imported freely.
    """

    temp_path: Path
    original_name: str
    content: dict[str, Any]


# Backwards-compat alias for any code/tests referencing the old private name.
_AttachmentRecord = AttachmentRecord


# Strong references to workers whose run() has not finished yet. Owner dialogs
# may be closed while a request is still in flight; destroying the last
# reference to a running QThread aborts the process
# ("QThread: Destroyed while thread is still running"), so the registry keeps
# every started worker alive until it is released.
#
# The release runs on the ``finished`` signal, which Qt delivers on the
# thread that owns the QThread object (the GUI thread). That matters:
# touching a QThread from the worker thread can deadlock.
#
# Two call sites used to disconnect *all* of a worker's signals when
# superseding it (``generator_worker_hub``, ``git_worker_hub``) — and that
# list included ``finished``. With the release hooked to ``finished``, such
# a disconnect stranded the worker in this set: the registry grew without
# bound and the worker was never joined. Both hubs now exclude ``finished``,
# and ``_sweep_finished_workers`` is the fallback for anything that still
# ends up disconnected.
_LIVE_WORKERS: set[AiRequestWorker] = set()

#: Host attributes that may hold an in-flight **AI** worker — the ones the
#: tray's "取消" button may stop.
#:
#: The save worker is deliberately NOT here: a save is not an AI request,
#: and cancelling it half-way would leave the course in an unclear state.
AI_WORKER_ATTRS: tuple[str, ...] = (
    "_open_worker",
    "_experience_worker",
    "_diagnose_worker",
    "_palette_llm_worker",
    "_generate_worker",
    "_publish_worker",
    "_chip_ai_worker",
    "_audio_save_worker",
)

#: Every host attribute that may hold an in-flight background worker.
#:
#: Single source of truth for the close path
#: (``close_controller._cancel_in_flight_workers``), which must stop and
#: join *all* of them — including the save worker — before the window is
#: torn down. It used to live in two places with different contents, so
#: workers the cancel path did not know about (course open, publish, TTS)
#: could not be stopped.
IN_FLIGHT_WORKER_ATTRS: tuple[str, ...] = (
    "_save_worker",
    *AI_WORKER_ATTRS,
)


class AiRequestWorker(QThread):
    """Run a synchronous AI call in a background thread.

    ``target`` is any callable; ``*args``/``**kwargs`` are forwarded to it.
    The result or exception is delivered via Qt signals.

    A cooperative ``cancel_check`` callable is forwarded to ``request_chat``-
    based targets so a long HTTP read can be interrupted. Call ``cancel()``
    from the UI thread to request cancellation; the running call raises
    ``AiCancelled`` and the error is surfaced via ``error_occurred``.
    """

    result_ready = Signal(object)
    error_occurred = Signal(str)
    completed = Signal()
    # Incremental streaming fragments from the model (one per SSE delta content).
    chunk_ready = Signal(str)
    # Final token-usage block extracted from the response (for cost display).
    usage_ready = Signal(object)
    # Intermediate progress objects from pipeline-style targets (e.g.
    # ``ai_pipeline.run_pipeline`` emits ``PipelineState`` after each step).
    progress_ready = Signal(object)

    def __init__(self, target, *args, parent: QWidget | None = None, **kwargs) -> None:
        super().__init__(parent)
        self._target = target
        self._args = args
        self._kwargs = kwargs
        self._cancelled = False

    def cancel(self) -> None:
        """Request cooperative cancellation of the in-flight call."""
        self._cancelled = True

    def start(self, *args, **kwargs) -> None:
        # Sweep entries left behind by a previous worker whose ``finished``
        # signal was disconnected before it fired. The sweep runs on the GUI
        # thread, so it is safe to touch the QThread objects.
        self._sweep_finished_workers()
        # Register before starting so the worker can never be garbage
        # collected mid-run, even if every owner drops its reference.
        _LIVE_WORKERS.add(self)
        # Release on ``finished``. The slot is connected to a QThread object
        # that lives in the GUI thread, so it runs there — which matters:
        # touching a QThread from the worker thread can deadlock.
        #
        # ``finished`` used to be disconnected together with the other
        # signals when a worker was superseded, which stranded the worker in
        # the registry forever (unbounded growth, never joined). The
        # disconnect lists in ``generator_worker_hub`` / ``git_worker_hub``
        # now exclude it, and ``_sweep_finished_workers`` catches the rest.
        self.finished.connect(self._release_keepalive)
        super().start(*args, **kwargs)

    @staticmethod
    def _sweep_finished_workers() -> None:
        """Drop registry entries whose thread has already ended.

        The fallback for the case where ``finished`` was disconnected
        before it fired. Runs on the GUI thread (called from ``start``).
        """
        for worker in list(_LIVE_WORKERS):
            try:
                if not worker.isRunning():
                    _LIVE_WORKERS.discard(worker)
            except RuntimeError:
                # The C++ object is already gone.
                _LIVE_WORKERS.discard(worker)

    def _release_keepalive(self) -> None:
        _LIVE_WORKERS.discard(self)

    def _check_cancel(self) -> bool:
        return self._cancelled

    def _emit_chunk(self, fragment: str) -> None:
        """Forward a streamed content fragment to the UI thread."""
        self.chunk_ready.emit(fragment)

    def _emit_usage(self, usage: dict) -> None:
        """Forward the final usage block to the UI thread."""
        self.usage_ready.emit(usage)

    def _emit_progress(self, progress: object) -> None:
        """Forward intermediate pipeline progress to the UI thread."""
        self.progress_ready.emit(progress)

    @staticmethod
    def _target_accepts(target, name: str) -> bool:
        """True if ``target``'s signature declares ``name`` or accepts **kwargs."""
        import inspect

        try:
            sig = inspect.signature(target)
        except (TypeError, ValueError):
            return False
        return name in sig.parameters or any(
            p.kind == inspect.Parameter.VAR_KEYWORD for p in sig.parameters.values()
        )

    def run(self) -> None:
        try:
            kwargs = dict(self._kwargs)
            # Forward the cooperative cancel flag + streaming callbacks to
            # request_chat-based targets that accept them. Plain callables
            # used in unit tests would otherwise raise TypeError.
            for name, inject in (
                ("cancel_check", self._check_cancel),
                ("on_chunk", self._emit_chunk),
                ("usage_callback", self._emit_usage),
                ("on_progress", self._emit_progress),
            ):
                if name not in kwargs and self._target_accepts(self._target, name):
                    kwargs[name] = inject
            result = self._target(*self._args, **kwargs)
        except AiCancelled as exc:
            self.error_occurred.emit(str(exc) or "请求已取消。")
        except Exception as exc:
            logger.debug(
                "src/application/ai_request_worker.py:180 best-effort step failed",
                exc_info=True,
            )
            self.error_occurred.emit(str(exc))
        else:
            if not self._cancelled:
                self.result_ready.emit(result)
        finally:
            self.completed.emit()


# Pre-compiled so the hot path (``_ensure_api_configured`` runs this on every
# request) doesn't recompile/re-resolve the pattern per call. (M3)
_HTTP_URL_RE = re.compile(r"^https?://[^\s]+$", re.IGNORECASE)


def is_valid_http_url(url: str) -> bool:
    """True if ``url`` looks like an http(s) URL."""
    if not url:
        return False
    return bool(_HTTP_URL_RE.match(url))


# Backwards-compat alias for the old private name.
_is_valid_http_url = is_valid_http_url

def safe_disconnect(sig: Any, slot: Any = None) -> bool:
    """Disconnect a Qt signal, tolerating the "not connected" failure modes.

    Qt raises ``RuntimeError`` when the slot is not connected; fake workers in
    tests may raise ``AttributeError``/``TypeError`` instead. Returns True when
    a connection was actually removed. Shared by the dialogs that manage their
    own ``AiRequestWorker`` lifecycles (ai_fix_dialog, textbook_library_dialog).
    """
    try:
        if slot is None:
            sig.disconnect()
        else:
            sig.disconnect(slot)
        return True
    except (AttributeError, TypeError, RuntimeError):
        logger.debug("application/ai_request_worker.py:safe_disconnect safe skip", exc_info=True)
        return False
