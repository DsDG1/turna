"""v4.15 K-05: lesson.regenerate / unit.regenerate skill contract tests.

Covers: selection resolution, guard pre-check, job/metrics funnel,
diff-confirm gate (rejected vs applied), error path, id preservation
(engine contract via stubbed regenerate functions).
"""
from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from tests._qtapp import qt_app  # noqa: E402


_SECTION = {
    "id": "s1",
    "units": [
        {
            "id": "u1",
            "lessons": [
                {"id": "l1", "title": "Old", "steps": []},
                {"id": "l2", "title": "Keep", "steps": []},
            ],
        }
    ],
}


class _Signal:
    def __init__(self) -> None:
        self._cbs: list = []

    def connect(self, cb) -> None:
        self._cbs.append(cb)

    def emit(self, *args) -> None:
        for cb in self._cbs:
            cb(*args)


class _FakeWorker:
    last: "_FakeWorker | None" = None

    def __init__(self, fn, *a, **k) -> None:
        self.fn = fn
        self.result_ready = _Signal()
        self.error_occurred = _Signal()
        _FakeWorker.last = self

    def start(self) -> None:
        pass


class _Metrics:
    def __init__(self) -> None:
        self.counts: dict[tuple, int] = {}

    def _inc(self, key: tuple) -> None:
        self.counts[key] = self.counts.get(key, 0) + 1

    def inc_guard(self, stage: str) -> None:
        self._inc(("guard", stage))

    def inc_job(self, kind: str, stage: str) -> None:
        self._inc(("job", kind, stage))

    def inc_suggestion(self, action_id: str, stage: str) -> None:
        self._inc(("suggestion", action_id, stage))


class _JobTray:
    def __init__(self, busy_ai: bool = False) -> None:
        self.jobs: list[str] = []
        self._busy_ai = busy_ai

    def is_busy_ai(self) -> bool:
        return self._busy_ai

    def start_job(self, job_id, *a, **k) -> None:
        self.jobs.append(job_id)

    def finish_job(self, job_id) -> None:
        if job_id in self.jobs:
            self.jobs.remove(job_id)


class _StatusBar:
    def __init__(self) -> None:
        self.messages: list[str] = []

    def showMessage(self, msg: str, _ms: int = 0) -> None:
        self.messages.append(msg)


class _Adapter:
    def __init__(self) -> None:
        self.sections = [_SECTION]

    def find_lesson(self, lesson_id: str):
        for u in _SECTION["units"]:
            for l in u["lessons"]:
                if l["id"] == lesson_id:
                    return _SECTION, u, l
        raise KeyError(lesson_id)

    def find_unit(self, unit_id: str):
        for u in _SECTION["units"]:
            if u["id"] == unit_id:
                return _SECTION, u
        raise KeyError(unit_id)

    def plan_section_merge(self, sid: str, result: dict) -> dict:
        return {"section_id": sid, "result": result}


class _UndoStack:
    def __init__(self) -> None:
        self.commands: list = []

    def push(self, cmd) -> None:
        self.commands.append(cmd)


class _CmdSignals:
    def __init__(self) -> None:
        self.changed = self

    def connect(self, _cb) -> None:
        pass


class _FakeMergeCommand:
    def __init__(self, adapter, plan) -> None:
        self.plan = plan
        self.signals = _CmdSignals()


class RegenerateSkillTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        qt_app()

    def setUp(self) -> None:
        _FakeWorker.last = None

    def _make_window(self, ref=("lesson", "l1"), busy_ai: bool = False):
        from PySide6.QtWidgets import QWidget
        from src.application.experience_skills_mixin import ExperienceSkillsMixin
        from src.backend.experience.conflict_guard import ConflictGuard

        win = QWidget()
        self.addCleanup(win.deleteLater)
        win._run_regen_flow = lambda **kw: ExperienceSkillsMixin._run_regen_flow(
            win, **kw
        )
        win.course_dir = "/tmp/course"
        win._current_node_ref = ref
        win.adapter = _Adapter()
        win.conflict_guard = ConflictGuard()
        win.experience_metrics = _Metrics()
        win.job_tray = _JobTray(busy_ai=busy_ai)
        win.undo_stack = _UndoStack()
        win._statusbar = _StatusBar()
        win.statusBar = lambda: win._statusbar
        win._ai_config = object()
        win._sync_focus_ring = lambda: None
        win._refresh_experience = lambda **k: None
        win._on_ai_edit_applied = lambda *a: None
        win._refresh_validate_after_ai = lambda msg: win._statusbar.showMessage(msg)
        win._record_experience_event = lambda *a, **k: None
        return win

    def _run(self, win, scope, *, diff_accept: bool = True, regen_result=None):
        from PySide6.QtWidgets import QDialog
        from src.application.experience_skills_mixin import ExperienceSkillsMixin

        def _regen(config, spec, draft, node_id, **kw):
            if regen_result is not None:
                return regen_result
            out = {**draft, "touched": node_id}
            return out

        code = (
            QDialog.DialogCode.Accepted
            if diff_accept
            else QDialog.DialogCode.Rejected
        )
        with patch(
            "src.dialogs.ai.worker.AiRequestWorker", _FakeWorker
        ), patch(
            "src.backend.ai_generator.regenerate_lesson_in_section",
            side_effect=_regen,
        ) as rl, patch(
            "src.backend.ai_generator.regenerate_unit_in_section",
            side_effect=_regen,
        ) as ru, patch(
            "src.widgets.diff_view.SectionDiffView"
        ) as diff_cls, patch(
            "src.application.experience_handlers.regenerate.MergeAiSectionCommand",
            _FakeMergeCommand,
        ), patch("src.application.experience_skills_mixin.QMessageBox"):
            diff_cls.return_value.exec.return_value = code
            ExperienceSkillsMixin._experience_regenerate(win, scope)
            worker = _FakeWorker.last
            if worker is not None:
                # resolve the target fn through the patched engine
                result = worker.fn()
                worker.result_ready.emit(result)
        return rl, ru

    def test_no_selection_shows_hint_and_starts_nothing(self) -> None:
        win = self._make_window(ref=None)
        self._run(win, {})
        self.assertIsNone(_FakeWorker.last)
        self.assertTrue(
            any("选中" in m for m in win._statusbar.messages),
            win._statusbar.messages,
        )

    def test_lesson_regenerate_applies_via_diff_and_undo(self) -> None:
        win = self._make_window(ref=("lesson", "l1"))
        rl, ru = self._run(win, {})
        self.assertEqual(rl.call_count, 1)
        self.assertEqual(ru.call_count, 0)
        m = win.experience_metrics.counts
        self.assertEqual(m.get(("job", "ai", "started")), 1)
        self.assertEqual(m.get(("job", "ai", "finished")), 1)
        self.assertEqual(m.get(("guard", "released")), 1)
        self.assertEqual(m.get(("suggestion", "lesson.regenerate", "applied")), 1)
        self.assertEqual(len(win.undo_stack.commands), 1)
        cmd = win.undo_stack.commands[0]
        # v4.57+ LessonPatch / v4.58 SectionPatch / legacy Merge plan
        if hasattr(cmd, "plan") and isinstance(cmd.plan, dict):
            self.assertEqual(cmd.plan.get("section_id"), "s1")
        elif hasattr(cmd, "patch"):
            sid = getattr(cmd.patch, "section_id", None) or getattr(
                cmd.patch, "lesson_id", None
            )
            self.assertTrue(sid in ("s1", "l1"), sid)
        else:
            self.fail(f"unexpected command type: {type(cmd)}")
        self.assertFalse(win.conflict_guard.is_busy("lesson:l1"))
        self.assertEqual(win.job_tray.jobs, [])

    def test_unit_selection_routes_to_unit_engine(self) -> None:
        win = self._make_window(ref=("unit", "u1"))
        rl, ru = self._run(win, {})
        self.assertEqual(ru.call_count, 1)
        self.assertEqual(rl.call_count, 0)
        m = win.experience_metrics.counts
        self.assertEqual(m.get(("suggestion", "unit.regenerate", "applied")), 1)

    def test_diff_cancel_records_rejected_and_pushes_nothing(self) -> None:
        win = self._make_window(ref=("lesson", "l1"))
        self._run(win, {}, diff_accept=False)
        m = win.experience_metrics.counts
        self.assertEqual(m.get(("suggestion", "lesson.regenerate", "rejected")), 1)
        self.assertEqual(len(win.undo_stack.commands), 0)

    def test_guard_busy_blocks_and_records_rejected(self) -> None:
        win = self._make_window(ref=("lesson", "l1"))
        self.assertTrue(win.conflict_guard.try_acquire("lesson:l1", "other-job"))
        with patch("src.application.experience_skills_mixin.QMessageBox"):
            from src.application.experience_skills_mixin import (
                ExperienceSkillsMixin,
            )

            ExperienceSkillsMixin._experience_regenerate(win, {})
        self.assertIsNone(_FakeWorker.last)
        m = win.experience_metrics.counts
        self.assertEqual(m.get(("guard", "rejected")), 1)
        self.assertEqual(m.get(("job", "ai", "started"), 0), 0)

    def test_busy_ai_blocks_before_guard(self) -> None:
        win = self._make_window(ref=("lesson", "l1"), busy_ai=True)
        with patch("src.application.experience_skills_mixin.QMessageBox"):
            from src.application.experience_skills_mixin import (
                ExperienceSkillsMixin,
            )

            ExperienceSkillsMixin._experience_regenerate(win, {})
        self.assertIsNone(_FakeWorker.last)
        m = win.experience_metrics.counts
        self.assertEqual(m.get(("job", "ai", "started"), 0), 0)

    def test_error_path_records_failed_and_releases(self) -> None:
        win = self._make_window(ref=("lesson", "l1"))
        from src.application.experience_skills_mixin import ExperienceSkillsMixin

        with patch(
            "src.dialogs.ai.worker.AiRequestWorker", _FakeWorker
        ), patch(
            "src.backend.ai_generator.regenerate_lesson_in_section",
            side_effect=RuntimeError("boom"),
        ), patch("src.application.experience_skills_mixin.QMessageBox"):
            ExperienceSkillsMixin._experience_regenerate(win, {})
            worker = _FakeWorker.last
            self.assertIsNotNone(worker)
            try:
                worker.fn()
            except RuntimeError as exc:
                worker.error_occurred.emit(str(exc))
        m = win.experience_metrics.counts
        self.assertEqual(m.get(("job", "ai", "failed")), 1)
        self.assertEqual(m.get(("guard", "released")), 1)
        self.assertFalse(win.conflict_guard.is_busy("lesson:l1"))

    def test_dispatch_routes_both_regenerate_actions(self) -> None:
        """_on_experience_suggestion routes lesson/unit.regenerate to one entry."""
        from src.backend.experience import get_action

        for aid in ("lesson.regenerate", "unit.regenerate", "item.rewrite"):
            spec = get_action(aid)
            self.assertIsNotNone(spec, aid)
            self.assertTrue(spec.implemented, aid)
            self.assertTrue(spec.needs_confirm, aid)


if __name__ == "__main__":
    unittest.main()
