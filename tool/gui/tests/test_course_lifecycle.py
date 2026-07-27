"""E5-C CourseLifecycle: single clear list + bind/switch semantics."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from typing import Any
from unittest.mock import MagicMock

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.application.course_lifecycle import (  # noqa: E402
    REASON_CLOSE_COURSE,
    REASON_COURSE_SWITCH,
    bind_loaded_course,
    clear_experience_session,
    prepare_course_switch,
)
from src.backend.experience.conflict_guard import ConflictGuard  # noqa: E402
from src.backend.experience.focus_ring import FocusRing, FocusRole  # noqa: E402
from src.backend.experience.job_registry import JobRegistry  # noqa: E402
from src.backend.experience.metrics import ExperienceMetrics  # noqa: E402
from src.backend.experience.timeline import ExperienceTimeline  # noqa: E402


class _FakeTray:
    def __init__(self) -> None:
        self.registry = JobRegistry()

    def clear(self) -> None:
        self.registry.clear()

    def start_job(self, job_id: str, label: str, **kwargs: Any) -> bool:
        return self.registry.start(job_id, label, **kwargs)

    def is_busy(self) -> bool:
        return self.registry.is_busy()


class _FakeShell:
    def __init__(self) -> None:
        self.adapter = object()
        self.null_calls = 0

    def set_adapter(self, adapter: Any) -> None:
        self.adapter = adapter
        if adapter is None:
            self.null_calls += 1


class _FakeHost:
    """Minimal host for pure lifecycle tests (no Qt MainWindow)."""

    def __init__(self) -> None:
        from src.backend.experience.memory import ExperienceMemory

        self.course_dir: Path | None = Path("/tmp/old-course")
        self.experience = _FakeShell()
        self.experience_timeline = ExperienceTimeline(maxlen=10)
        self.experience_timeline.record("x", "hello", action_id="app.help")
        self.job_tray = _FakeTray()
        self.job_tray.start_job("ai-1", "busy", kind="ai", node_key="lesson:l1")
        self.conflict_guard = ConflictGuard()
        self.conflict_guard.try_acquire("lesson:l1", "ai-1", label="busy")
        self.focus_ring = FocusRing()
        self.focus_ring.set("lesson:l1", FocusRole.BUSY, label="busy")
        self.experience_metrics = ExperienceMetrics()
        self.experience_metrics.inc_intent_resolved()
        self.experience_memory = ExperienceMemory()
        self.experience_memory.bind_course("/tmp/old-course")
        self.experience_memory.record_intent("app.help", label="help")
        self._shown_suggestion_keys: set[str] = {"a:1"}
        self._ambient_archived: set[str] = {"p1"}
        self.tree = MagicMock()
        self.undo_stack = MagicMock()
        self.adapter = MagicMock()
        self._current_node_ref = ("lesson", "l1")
        self._flush_calls: list[tuple[str, Any]] = []
        self._diagnose_calls = 0
        self._enabled = 0
        self._recent: list[Path] = []
        self._status: list[str] = []
        self._workshop_window = MagicMock()
        self.experience_dock_widget = MagicMock()

    def _flush_experience_metrics(self, reason: str, *, course_dir=None) -> None:
        self._flush_calls.append((reason, course_dir))

    def _enable_editor_actions(self) -> None:
        self._enabled += 1

    def _add_recent_repo(self, path: Path) -> None:
        self._recent.append(path)

    def statusBar(self):  # noqa: N802
        host = self

        class _SB:
            def showMessage(self, msg: str, _ms: int = 0) -> None:  # noqa: N802
                host._status.append(msg)

        return _SB()

    def _refresh_experience(self, *, immediate: bool = False, focus_only: bool = False) -> None:
        self.experience.set_adapter(self.adapter)

    def _start_experience_diagnose(self) -> None:
        self._diagnose_calls += 1


class ClearExperienceSessionTest(unittest.TestCase):
    def test_clear_empties_jobs_guard_focus_timeline(self) -> None:
        host = _FakeHost()
        self.assertTrue(host.job_tray.is_busy())
        clear_experience_session(
            host,
            reason=REASON_CLOSE_COURSE,
            flush_metrics=True,
            null_adapter=True,
        )
        self.assertFalse(host.job_tray.is_busy())
        self.assertEqual(host.conflict_guard.busy_summary(), "")
        self.assertEqual(host.focus_ring.as_id_role_map(), {})
        self.assertEqual(host.experience_timeline.recent(), [])
        self.assertIsNone(host.experience.adapter)
        self.assertEqual(len(host.experience_memory.session), 0)  # C-13 session cleared
        self.assertEqual(host._shown_suggestion_keys, set())
        self.assertEqual(host._ambient_archived, set())
        self.assertEqual(host._flush_calls[0][0], REASON_CLOSE_COURSE)
        host.tree.apply_badges.assert_called_with(None)
        host.tree.apply_focus_ring.assert_called_with({})
        host.experience_dock_widget.clear.assert_called()

    def test_prepare_switch_flushes_old_dir_then_clears(self) -> None:
        host = _FakeHost()
        old = Path("/tmp/old-course")
        prepare_course_switch(host, old)
        self.assertEqual(host._flush_calls[0][0], REASON_COURSE_SWITCH)
        self.assertEqual(host._flush_calls[0][1], old)
        self.assertFalse(host.job_tray.is_busy())
        host._workshop_window.interrupt_and_save.assert_called()
        host._workshop_window.hide.assert_called()

    def test_prepare_switch_noop_without_old(self) -> None:
        host = _FakeHost()
        prepare_course_switch(host, None)
        self.assertEqual(host._flush_calls, [])
        self.assertTrue(host.job_tray.is_busy())


class BindLoadedCourseTest(unittest.TestCase):
    def test_bind_switch_clears_stale_job(self) -> None:
        host = _FakeHost()
        new_path = Path("/tmp/new-course")
        bind_loaded_course(
            host,
            new_path,
            status_message=f"已加载: {new_path}",
            telemetry_event="repo.open",
        )
        self.assertEqual(host.course_dir, new_path)
        self.assertFalse(host.job_tray.is_busy())
        self.assertEqual(host._diagnose_calls, 1)
        self.assertEqual(host._enabled, 1)
        self.assertIn(new_path, host._recent)
        host.tree.display.assert_called()
        host.undo_stack.clear.assert_called()
        self.assertIsNone(host._current_node_ref)

    def test_bind_first_open_skips_switch_flush(self) -> None:
        host = _FakeHost()
        host.course_dir = None
        # Still has a busy job from construction — first open should NOT
        # clear unless we switch; first open leaves previous session only
        # when course_dir was set. With course_dir None, no prepare_switch.
        host.job_tray.clear()
        bind_loaded_course(host, Path("/tmp/only"), status_message="已加载: x")
        self.assertEqual(host._flush_calls, [])
        self.assertEqual(host.course_dir, Path("/tmp/only"))
        self.assertEqual(host._diagnose_calls, 1)


class MainWindowLifecycleWiringTest(unittest.TestCase):
    """Smoke: MainWindow close-course path uses clear_experience_session."""

    @classmethod
    def setUpClass(cls) -> None:
        from tests._mainwindow_fixture import build_main_window, qt_app

        qt_app()
        cls.win = build_main_window()

    def setUp(self) -> None:
        from tests._mainwindow_fixture import reset_main_window

        reset_main_window(self.win)

    def test_refresh_with_no_course_clears_jobs(self) -> None:
        self.win.course_dir = None
        self.win.job_tray.start_job("leak", "should clear", kind="ai")
        self.win.conflict_guard.try_acquire("item:q1", "leak", label="x")
        self.win._refresh_experience(immediate=True)
        self.assertFalse(self.win.job_tray.is_busy())
        self.assertEqual(self.win.conflict_guard.busy_summary(), "")


if __name__ == "__main__":
    unittest.main()
