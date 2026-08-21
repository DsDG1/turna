"""Shared MainWindow construction for GUI tests (speed + hang safety).

Why this exists
---------------
Profiling shows full-suite time is dominated by Qt/MainWindow tests
(~150 UI tests ≈ minutes; pure tests ≈ sub-second for hundreds of cases).

Two recurring costs / hazards:

1. **Construction** — each ``MainWindow()`` rebuilds toolbar/tree/dock (~0.1s+).
2. **Hang** — ``MainWindow.__init__`` calls ``_maybe_open_last_repo()``, which
   may pop a modal ``QMessageBox``. Under offscreen CI a poorly mocked
   QSettings can leave the suite blocked for minutes.

All test code that needs a real window should go through
:func:`build_main_window` (or :class:`SharedMainWindowTestCase`).
"""
from __future__ import annotations

from contextlib import contextmanager
from typing import Any, Iterator
from unittest.mock import MagicMock, patch

from tests._qtapp import qt_app


def make_qsettings_mock(values: dict[str, Any] | None = None) -> MagicMock:
    """QSettings mock backed by a dict (default empty recent_repos).

    ``setValue`` / ``value`` remain MagicMocks so tests can assert call history.
    """
    store: dict[str, Any] = {"recent_repos": "[]"}
    if values:
        store.update(values)
    qs = MagicMock()

    def _value(key: str, default: Any = None) -> Any:
        return store.get(key, default)

    def _set_value(key: str, value: Any) -> None:
        store[key] = value

    def _contains(key: str) -> bool:
        return key in store

    def _remove(key: str) -> None:
        store.pop(key, None)

    qs.value.side_effect = _value
    qs.setValue.side_effect = _set_value
    qs.contains.side_effect = _contains
    qs.remove.side_effect = _remove
    qs._store = store  # type: ignore[attr-defined]
    return qs


@contextmanager
def patch_main_window_env(
    values: dict[str, Any] | None = None,
) -> Iterator[MagicMock]:
    """Patch QSettings and suppress last-repo open prompt for MainWindow ctor."""
    fake = make_qsettings_mock(values)
    with patch("src.app.QSettings", return_value=fake), patch(
        "src.app.MainWindow._maybe_open_last_repo",
        autospec=False,
        return_value=None,
    ):
        yield fake


def build_main_window(values: dict[str, Any] | None = None):
    """Construct a MainWindow safe for headless tests (no last-repo modal)."""
    from src.app import MainWindow

    qt_app()
    with patch_main_window_env(values):
        return MainWindow()


def build_main_window_with_settings(
    values: dict[str, Any] | None = None,
) -> tuple[Any, MagicMock]:
    """Like :func:`build_main_window` but also return the QSettings mock."""
    from src.app import MainWindow

    qt_app()
    fake = make_qsettings_mock(values)
    with patch("src.app.QSettings", return_value=fake), patch(
        "src.app.MainWindow._maybe_open_last_repo",
        return_value=None,
    ):
        win = MainWindow()
    return win, fake


def reset_main_window(win) -> None:
    """Clear course/adapter/undo state so a shared window can be reused."""
    from src.backend.course_adapter import CourseAdapter

    win.course_dir = None
    win.adapter = CourseAdapter()
    try:
        win.adapter.add_resource_listener(win._on_experience_resources_changed)
    except Exception:  # noqa: BLE001 — listener optional in stubs
        pass
    win._current_node_ref = None
    win._last_imported_section_id = None
    win.teacher_mode = False
    if hasattr(win, "mode_action") and win.mode_action is not None:
        try:
            win.mode_action.blockSignals(True)
            win.mode_action.setChecked(False)
            win.mode_action.blockSignals(False)
        except Exception:  # noqa: BLE001
            pass
    if hasattr(win, "undo_stack") and win.undo_stack is not None:
        win.undo_stack.clear()
    if hasattr(win, "conflict_guard") and win.conflict_guard is not None:
        try:
            win.conflict_guard.clear()  # type: ignore[attr-defined]
        except Exception:  # noqa: BLE001
            pass
    if hasattr(win, "experience") and win.experience is not None:
        try:
            win.experience.set_adapter(win.adapter)
            win.experience.set_usage_today({})
        except Exception:  # noqa: BLE001
            pass
    if hasattr(win, "tree") and win.tree is not None:
        try:
            win.tree.adapter = win.adapter
            win.tree._on_command_changed = lambda: None
        except Exception:  # noqa: BLE001
            pass


class SharedMainWindowTestCase:
    """Mixin: one MainWindow per test class; reset between methods.

    Usage::

        class MyTest(SharedMainWindowTestCase, unittest.TestCase):
            def test_x(self):
                self.win....
    """

    win: Any

    @classmethod
    def setUpClass(cls) -> None:
        qt_app()
        cls.win = build_main_window()

    def setUp(self) -> None:
        reset_main_window(self.win)
