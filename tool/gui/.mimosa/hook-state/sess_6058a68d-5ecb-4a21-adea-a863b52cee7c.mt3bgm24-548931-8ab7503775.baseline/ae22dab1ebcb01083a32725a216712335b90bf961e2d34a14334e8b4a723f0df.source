"""Reusable mixin that records per-window running time.

Classes whose ``closeEvent`` is trivial (or absent) can mix this in to get
``window.open`` and ``window.duration`` events for free. The mixin's
``closeEvent`` calls ``super().closeEvent(event)`` so existing overrides that
delegate upward still run.

For windows with non-trivial ``closeEvent`` logic (e.g. ``MainWindow``'s
save/discard prompt), do NOT use the mixin — instead record the two events
directly inside the existing ``closeEvent`` to avoid interfering with the
accept/ignore flow.
"""
from __future__ import annotations

import time

from PySide6.QtGui import QCloseEvent, QShowEvent

from src.infrastructure.operations_log import operations


class WindowUsageMixin:
    """Record ``window.open`` on show and ``window.duration`` on close."""

    _usage_t0: float = 0.0

    def _window_name(self) -> str:
        try:
            return self.windowTitle() or self.objectName() or type(self).__name__  # type: ignore[attr-defined]
        except Exception:
            return type(self).__name__

    def showEvent(self, event: QShowEvent) -> None:  # noqa: N802
        self._usage_t0 = time.perf_counter()
        try:
            operations.record_action("window.open", self._window_name())
        except Exception:
            pass
        super().showEvent(event)  # type: ignore[misc]

    def closeEvent(self, event: QCloseEvent) -> None:  # noqa: N802
        try:
            start = getattr(self, "_usage_t0", 0.0) or time.perf_counter()
            duration_ms = (time.perf_counter() - start) * 1000.0
            operations.record_duration(
                "window.duration",
                duration_ms,
                payload={"window": self._window_name()},
            )
            operations.record_action("window.close", self._window_name())
        except Exception:
            pass
        super().closeEvent(event)  # type: ignore[misc]