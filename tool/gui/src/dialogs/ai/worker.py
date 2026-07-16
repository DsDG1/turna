"""Background AI request worker + small shared helpers.

Extracted from the original monolithic ``ai_generator_dialog.py`` (guiplan2 P5).
``AiRequestWorker`` runs a synchronous AI call in a QThread and forwards
result / error / streaming-chunk / usage signals to the UI thread.
"""
from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from PySide6.QtCore import QThread, Signal
from PySide6.QtWidgets import QWidget

from src.backend.ai_generator import AiCancelled


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

    def __init__(self, target, *args, parent: QWidget | None = None, **kwargs) -> None:
        super().__init__(parent)
        self._target = target
        self._args = args
        self._kwargs = kwargs
        self._cancelled = False

    def cancel(self) -> None:
        """Request cooperative cancellation of the in-flight call."""
        self._cancelled = True

    def is_cancelled(self) -> bool:
        return self._cancelled

    def _check_cancel(self) -> bool:
        return self._cancelled

    def _emit_chunk(self, fragment: str) -> None:
        """Forward a streamed content fragment to the UI thread."""
        self.chunk_ready.emit(fragment)

    def _emit_usage(self, usage: dict) -> None:
        """Forward the final usage block to the UI thread."""
        self.usage_ready.emit(usage)

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
            ):
                if name not in kwargs and self._target_accepts(self._target, name):
                    kwargs[name] = inject
            result = self._target(*self._args, **kwargs)
        except AiCancelled as exc:
            self.error_occurred.emit(str(exc) or "请求已取消。")
        except Exception as exc:  # noqa: BLE001
            self.error_occurred.emit(str(exc))
        else:
            if not self._cancelled:
                self.result_ready.emit(result)
        finally:
            self.completed.emit()


def is_valid_http_url(url: str) -> bool:
    """True if ``url`` looks like an http(s) URL."""
    if not url:
        return False
    return bool(re.match(r"^https?://[^\s]+$", url, re.IGNORECASE))


# Backwards-compat alias for the old private name.
_is_valid_http_url = is_valid_http_url


def QApplication_safe_process_events() -> None:
    """Process pending Qt events without re-entrancy hazards (module helper)."""
    from PySide6.QtWidgets import QApplication

    app = QApplication.instance()
    if app is not None:
        app.processEvents()