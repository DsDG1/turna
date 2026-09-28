"""E5-C CourseLifecycle: single clear list + bind/switch semantics."""
from __future__ import annotations

import sys
import tempfile
import unittest
from datetime import datetime
from pathlib import Path
from types import SimpleNamespace
from typing import Any
from unittest.mock import MagicMock, patch

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.application.course_lifecycle import (
    REASON_CLOSE_COURSE,
    REASON_COURSE_SWITCH,
    bind_loaded_course,
    clear_experience_session,
    confirm_course_switch,
    open_course_flow,
    prepare_course_switch,
)
from src.backend.experience.conflict_guard import ConflictGuard
from src.backend.experience.focus_ring import FocusRing, FocusRole
from src.backend.experience.job_registry import JobRegistry
from src.backend.experience.metrics import ExperienceMetrics
from src.backend.experience.timeline import ExperienceTimeline


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
        self._load_errors: list[str] = []

    def _show_load_error(self, message: str) -> None:
        self._load_errors.append(message)

    def _flush_experience_metrics(self, reason: str, *, course_dir=None) -> None:
        self._flush_calls.append((reason, course_dir))

    def _enable_editor_actions(self) -> None:
        self._enabled += 1

    def _add_recent_repo(self, path: Path) -> None:
        self._recent.append(path)

    def statusBar(self):
        host = self

        class _SB:
            def showMessage(self, msg: str, _ms: int = 0) -> None:
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


def _dirty_host() -> _FakeHost:
    host = _FakeHost()
    host.adapter.detect_changes.return_value = {"unit:u1": True}
    return host


class ConfirmCourseSwitchTest(unittest.TestCase):
    """#1/#14: switching courses must never silently discard dirty edits."""

    def _ask(self, answer: str):
        """Patch the modal so headless tests can drive each choice."""
        from PySide6.QtWidgets import QMessageBox

        button = {
            "save": QMessageBox.StandardButton.Save,
            "discard": QMessageBox.StandardButton.Discard,
            "cancel": QMessageBox.StandardButton.Cancel,
        }[answer]
        return (
            patch("src.application.ui_guard.is_headless_ui", return_value=False),
            patch.object(QMessageBox, "question", return_value=button),
        )

    def test_clean_course_never_asks(self) -> None:
        with patch("PySide6.QtWidgets.QMessageBox.question") as ask:
            self.assertTrue(confirm_course_switch(_FakeHost()))
            ask.assert_not_called()

    def test_dirty_headless_discards_and_proceeds(self) -> None:
        # Headless keeps close_controller's contract: auto-discard, never
        # hang CI on a modal.
        self.assertTrue(confirm_course_switch(_dirty_host()))

    def test_dirty_cancel_blocks_switch(self) -> None:
        host = _dirty_host()
        no_ui, ask = self._ask("cancel")
        with no_ui, ask:
            self.assertFalse(confirm_course_switch(host))
        self.assertEqual(host.course_dir, Path("/tmp/old-course"))

    def test_dirty_save_success_proceeds_through_pipeline(self) -> None:
        host = _dirty_host()
        outcome = SimpleNamespace(ok=True, message="保存成功", errors=[])
        no_ui, ask = self._ask("save")
        with no_ui, ask, patch(
            "src.application.save_host.execute_save", return_value=outcome
        ) as save:
            self.assertTrue(confirm_course_switch(host))
            save.assert_called_once()
            self.assertEqual(save.call_args.args[1].reason, REASON_COURSE_SWITCH)

    def test_dirty_save_failure_blocks_switch(self) -> None:
        host = _dirty_host()
        outcome = SimpleNamespace(ok=False, message="校验失败", errors=[{"level": "error", "message": "bad"}])
        no_ui, ask = self._ask("save")
        with no_ui, ask, patch(
            "src.application.save_host.execute_save", return_value=outcome
        ), patch("src.application.ui_guard.safe_warning") as warned:
            self.assertFalse(confirm_course_switch(host))
            warned.assert_called_once()
        self.assertEqual(host.course_dir, Path("/tmp/old-course"))


class OpenCourseFlowTest(unittest.TestCase):
    def test_clean_open_loads_then_binds(self) -> None:
        host = _FakeHost()
        loaded: list[Path] = []
        ok = open_course_flow(
            host, Path("/tmp/new"), load=loaded.append
        )
        self.assertTrue(ok)
        self.assertEqual(loaded, [Path("/tmp/new")])
        self.assertEqual(host.course_dir, Path("/tmp/new"))
        self.assertEqual(host._diagnose_calls, 1)
        self.assertEqual(host._load_errors, [])

    def test_load_failure_shows_error_and_keeps_current_course(self) -> None:
        host = _FakeHost()

        def _boom(_p: Path) -> None:
            raise RuntimeError("course.yaml 缺失")

        ok = open_course_flow(host, Path("/tmp/new"), load=_boom)
        self.assertFalse(ok)
        self.assertEqual(host._load_errors, ["course.yaml 缺失"])
        self.assertEqual(host.course_dir, Path("/tmp/old-course"))
        self.assertEqual(host._diagnose_calls, 0)

    def test_switch_resets_session_state_and_save_timestamp(self) -> None:
        """#14: no stale suggestion keys / save time / node ref across courses."""
        host = _dirty_host()
        host._last_saved_at = datetime(2026, 9, 28, 10, 30)
        # Offscreen → dirty resolves as discard; the switch must still land.
        self.assertTrue(
            open_course_flow(host, Path("/tmp/new"), load=lambda _p: None)
        )
        self.assertIsNone(host._last_saved_at)
        self.assertIsNone(host._current_node_ref)
        self.assertEqual(host._shown_suggestion_keys, set())
        self.assertEqual(host.course_dir, Path("/tmp/new"))

    def test_confirmed_cancel_aborts_before_load(self) -> None:
        from PySide6.QtWidgets import QMessageBox

        host = _dirty_host()
        loaded: list[Path] = []
        with patch(
            "src.application.ui_guard.is_headless_ui", return_value=False
        ), patch.object(
            QMessageBox, "question",
            return_value=QMessageBox.StandardButton.Cancel,
        ):
            ok = open_course_flow(host, Path("/tmp/new"), load=loaded.append)
        self.assertFalse(ok)
        self.assertEqual(loaded, [])
        self.assertEqual(host.course_dir, Path("/tmp/old-course"))


class RepoSessionOpenPathsTest(unittest.TestCase):
    """The three open paths must delegate to open_course_flow (#1)."""

    def test_open_repo_path_routes_through_flow(self) -> None:
        from src.application import repo_session_host

        host = _FakeHost()
        with tempfile.TemporaryDirectory() as td, patch.object(
            repo_session_host.CourseAdapter, "is_course_dir", return_value=True
        ), patch(
            "src.application.course_lifecycle.open_course_flow",
            return_value=True,
        ) as flow:
            repo_session_host.open_repo_path(host, td)
            flow.assert_called_once()
            load_fn = flow.call_args.kwargs["load"]
            load_fn(Path(td))
            host.adapter.load.assert_called_once_with(Path(td))

    def test_on_open_routes_through_flow(self) -> None:
        from src.application import repo_session_host

        host = _FakeHost()
        with patch.object(
            repo_session_host.QFileDialog,
            "getExistingDirectory",
            return_value="D:/courses/new",
        ), patch(
            "src.application.course_lifecycle.open_course_flow",
            return_value=True,
        ) as flow:
            repo_session_host.on_open(host)
            flow.assert_called_once()
            self.assertEqual(flow.call_args.args[1], Path("D:/courses/new"))

    def test_on_new_course_confirms_before_dialog_then_binds(self) -> None:
        from src.application import repo_session_host

        host = _FakeHost()
        order: list[str] = []

        def _confirm(_host) -> bool:
            order.append("confirm")
            return True

        fake_dlg = MagicMock()
        fake_dlg.exec.return_value = True
        fake_dlg.init_dir.return_value = Path("/tmp/fresh")

        def _dialog(*_a, **_k):
            order.append("dialog")
            return fake_dlg

        with patch(
            "src.application.course_lifecycle.confirm_course_switch",
            side_effect=_confirm,
        ), patch(
            "src.dialogs.init_course_dialog.InitCourseDialog", side_effect=_dialog
        ), patch(
            "src.application.course_lifecycle.open_course_flow",
            return_value=True,
        ) as flow:
            repo_session_host.on_new_course(host)

        # The dirty check must run BEFORE the dialog mutates the adapter.
        self.assertEqual(order, ["confirm", "dialog"])
        flow.assert_called_once()
        kwargs = flow.call_args.kwargs
        self.assertFalse(kwargs["confirm"])
        self.assertEqual(kwargs["telemetry_event"], "repo.new")


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
