"""Shared QApplication singleton for tests.

Avoids re-creating ``QApplication`` in every test file. Importing this module
is side-effect free; call :func:`qt_app` to obtain (and lazily create) the
singleton.
"""
from __future__ import annotations

import os

# Default to offscreen platform for all tests to prevent headless execution from hanging on native modal dialogs
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PySide6.QtWidgets import QApplication

_app: QApplication | None = None


def qt_app() -> QApplication:
    """Return a process-wide ``QApplication``, creating it on first call."""
    global _app
    if _app is None:
        _app = QApplication.instance() or QApplication([])
    return _app


class _App:
    """Backwards-compatible singleton shell delegating to :func:`qt_app`.

    Existing call sites use ``_App.get()`` / ``_App._ensure()``; keeping this
    alias here lets test files drop their local copy without touching call
    sites. Prefer calling :func:`qt_app` directly in new code.
    """

    @classmethod
    def get(cls) -> QApplication:
        return qt_app()

    @classmethod
    def _ensure(cls) -> QApplication:
        return qt_app()


# Alias used by some test files under the name ``_TestApp``.
_TestApp = _App