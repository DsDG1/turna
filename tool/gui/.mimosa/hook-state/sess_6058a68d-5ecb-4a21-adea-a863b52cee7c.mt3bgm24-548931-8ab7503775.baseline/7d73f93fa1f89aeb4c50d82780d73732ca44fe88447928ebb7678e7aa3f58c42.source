"""v4.16 K-07 lesson.balance + K-12 item.distractor_boost tests."""
from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from tests._qtapp import qt_app  # noqa: E402


def _lesson(types: list[str], template: str = "practice", lid: str = "l1") -> dict:
    return {
        "id": lid,
        "template": template,
        "content": {
            "stages": [
                {"id": "st1", "items": [{"id": f"q{i}", "runtimeType": t} for i, t in enumerate(types)]}
            ]
        },
    }


class EvaluateLessonBalanceTest(unittest.TestCase):
    def test_healthy_lesson_is_balanced(self) -> None:
        from src.backend.content_quality import evaluate_lesson_balance

        lesson = _lesson(["multipleChoice", "fillBlank", "translateSentence"])
        report = evaluate_lesson_balance(lesson)
        self.assertTrue(report["balanced"], report["issues"])
        self.assertEqual(report["unique"], 3)
        self.assertTrue(report["hint_hit"])
        self.assertIsNone(report["dominant"])

    def test_dominant_type_is_imbalanced(self) -> None:
        from src.backend.content_quality import evaluate_lesson_balance

        lesson = _lesson(["multipleChoice"] * 4 + ["fillBlank"])
        report = evaluate_lesson_balance(lesson)
        self.assertFalse(report["balanced"])
        self.assertEqual(report["dominant"]["type"], "multipleChoice")
        self.assertGreaterEqual(report["dominant"]["share"], 0.7)
        self.assertTrue(any("占比" in i for i in report["issues"]))

    def test_hint_miss_reports_missing_types(self) -> None:
        from src.backend.content_quality import evaluate_lesson_balance

        lesson = _lesson(["showWord", "matchWords", "listenAndPick"], template="reading")
        report = evaluate_lesson_balance(lesson)
        self.assertFalse(report["balanced"])
        self.assertFalse(report["hint_hit"])
        self.assertIn("multipleChoice", report["missing_hint_types"])

    def test_empty_lesson_reports_no_items(self) -> None:
        from src.backend.content_quality import evaluate_lesson_balance

        report = evaluate_lesson_balance(_lesson([]))
        self.assertFalse(report["balanced"])
        self.assertEqual(report["total"], 0)
        self.assertTrue(any("没有任何题目" in i for i in report["issues"]))


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
    def __init__(self) -> None:
        self.jobs: list[str] = []

    def is_busy_ai(self) -> bool:
        return False

    def start_job(self, job_id, *a, **k) -> None:
        self.jobs.append(job_id)

    def finish_job(self, job_id) -> None:
        if job_id in self.jobs:
            self.jobs.remove(job_id)


_UNBALANCED = _lesson(["multipleChoice"] * 4 + ["fillBlank"])
_BALANCED = _lesson(["multipleChoice", "fillBlank", "translateSentence"])


class _Adapter:
    def __init__(self, lesson: dict) -> None:
        self.section = {"id": "s1", "units": [{"id": "u1", "lessons": [lesson]}]}

    def find_lesson(self, lesson_id: str):
        lesson = self.section["units"][0]["lessons"][0]
        if lesson["id"] != lesson_id:
            raise KeyError(lesson_id)
        return self.section, self.section["units"][0], lesson

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


class BalanceSkillTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        qt_app()

    def setUp(self) -> None:
        _FakeWorker.last = None

    def _make_window(self, lesson: dict):
        from PySide6.QtWidgets import QWidget
        from src.application.experience_skills_mixin import ExperienceSkillsMixin
        from src.backend.experience.conflict_guard import ConflictGuard

        win = QWidget()
        self.addCleanup(win.deleteLater)
        win._run_regen_flow = lambda **kw: ExperienceSkillsMixin._run_regen_flow(
            win, **kw
        )
        win.course_dir = "/tmp/course"
        win._current_node_ref = ("lesson", lesson["id"])
        win.adapter = _Adapter(lesson)
        win.conflict_guard = ConflictGuard()
        win.experience_metrics = _Metrics()
        win.job_tray = _JobTray()
        win.undo_stack = _UndoStack()
        win._messages = []
        win.statusBar = lambda: SimpleNamespace(
            showMessage=lambda m, ms=0: win._messages.append(m)
        )
        win._ai_config = object()
        win._sync_focus_ring = lambda: None
        win._refresh_experience = lambda **k: None
        win._on_ai_edit_applied = lambda *a: None
        win._refresh_validate_after_ai = lambda msg: None
        win._record_experience_event = lambda *a, **k: None
        return win

    def test_balanced_lesson_zero_llm(self) -> None:
        from src.application.experience_skills_mixin import ExperienceSkillsMixin

        win = self._make_window(_BALANCED)
        ExperienceSkillsMixin._experience_balance_lesson(win, {})
        self.assertIsNone(_FakeWorker.last)
        self.assertTrue(any("配比健康" in m for m in win._messages))

    def _run_unbalanced(self, win, *, confirm: bool, diff_accept: bool = True):
        from PySide6.QtWidgets import QDialog
        from src.application.experience_skills_mixin import ExperienceSkillsMixin

        captured: dict = {}

        def _regen(config, spec, draft, node_id, instruction=None, **kw):
            captured["instruction"] = instruction
            return {**draft, "touched": True}

        # v4.46+: confirm goes through ui_guard.safe_question imported into
        # the regenerate handler namespace; MergeAiSectionCommand likewise.
        with patch(
            "src.application.experience_handlers.regenerate.safe_question",
            return_value=confirm,
        ), patch(
            "src.dialogs.ai.worker.AiRequestWorker", _FakeWorker
        ), patch(
            "src.backend.ai_generator.regenerate_lesson_in_section",
            side_effect=_regen,
        ), patch(
            "src.widgets.diff_view.SectionDiffView"
        ) as diff_cls, patch(
            "src.application.experience_handlers.regenerate.MergeAiSectionCommand",
            _FakeMergeCommand,
        ):
            diff_cls.return_value.exec.return_value = (
                QDialog.DialogCode.Accepted
                if diff_accept
                else QDialog.DialogCode.Rejected
            )
            ExperienceSkillsMixin._experience_balance_lesson(win, {})
            worker = _FakeWorker.last
            if worker is not None:
                worker.result_ready.emit(worker.fn())
        return captured

    def test_unbalanced_confirm_runs_worker_with_instruction(self) -> None:
        win = self._make_window(_UNBALANCED)
        captured = self._run_unbalanced(win, confirm=True)
        self.assertIsNotNone(_FakeWorker.last)
        instr = captured.get("instruction") or ""
        self.assertIn("题型配比", instr)
        self.assertIn("multipleChoice", instr)
        m = win.experience_metrics.counts
        self.assertEqual(m.get(("suggestion", "lesson.balance", "applied")), 1)
        self.assertEqual(m.get(("job", "ai", "started")), 1)
        self.assertEqual(m.get(("job", "ai", "finished")), 1)
        self.assertEqual(len(win.undo_stack.commands), 1)
        self.assertEqual(win.job_tray.jobs, [])

    def test_unbalanced_decline_records_rejected_no_worker(self) -> None:
        win = self._make_window(_UNBALANCED)
        self._run_unbalanced(win, confirm=False)
        self.assertIsNone(_FakeWorker.last)
        m = win.experience_metrics.counts
        self.assertEqual(m.get(("suggestion", "lesson.balance", "rejected")), 1)
        self.assertEqual(len(win.undo_stack.commands), 0)

    def test_guard_busy_blocks_after_confirm(self) -> None:
        win = self._make_window(_UNBALANCED)
        self.assertTrue(win.conflict_guard.try_acquire("lesson:l1", "other"))
        self._run_unbalanced(win, confirm=True)
        self.assertIsNone(_FakeWorker.last)
        m = win.experience_metrics.counts
        self.assertEqual(m.get(("guard", "rejected")), 1)


class DistractorBoostContractTest(unittest.TestCase):
    """K-12: registry + routing only (execution stays on the teacher chip)."""

    def test_registered_implemented_needs_confirm(self) -> None:
        from src.backend.experience import get_action

        spec = get_action("item.distractor_boost")
        self.assertIsNotNone(spec)
        self.assertTrue(spec.implemented)
        self.assertTrue(spec.needs_confirm)

    def test_dispatch_guides_without_writing(self) -> None:
        from src.application.experience_skills_mixin import ExperienceSkillsMixin

        qt_app()
        from PySide6.QtWidgets import QWidget

        win = QWidget()
        self.addCleanup(win.deleteLater)
        win._messages = []
        win.statusBar = lambda: SimpleNamespace(
            showMessage=lambda m, ms=0: win._messages.append(m)
        )
        win.experience_metrics = _Metrics()
        with patch(
            "src.application.experience_dispatch.telemetry"
        ):
            ExperienceSkillsMixin._on_experience_suggestion(
                win, {"action_id": "item.distractor_boost", "scope": {}}
            )
        self.assertTrue(any("换干扰" in m for m in win._messages))


class ImbalanceSuggestionTest(unittest.TestCase):
    def test_report_issues_to_suggestion(self) -> None:
        from src.backend.experience.context_bus import (
            _imbalance_from_report,
            local_suggestions,
            ExperienceContext,
        )

        report = SimpleNamespace(
            issues=[
                SimpleNamespace(
                    dimension="balance",
                    lesson_id="l1",
                    message="课时 l1 没有任何题目",  # skipped: fill_empty 域
                ),
                SimpleNamespace(
                    dimension="balance",
                    lesson_id="l2",
                    message="课时 l2（template=reading）题型 ['showWord'] 与建议题型交集为空",
                ),
                SimpleNamespace(  # dedupe: same lesson twice
                    dimension="balance",
                    lesson_id="l2",
                    message="listening 课时 l2 缺少 listeningPhases",
                ),
                SimpleNamespace(
                    dimension="audio_ready",  # other dimension ignored
                    lesson_id="l3",
                    message="缺 audioAsset",
                    item_id="q1",
                ),
            ]
        )
        imb = _imbalance_from_report(report, section_id="s1")
        self.assertEqual(len(imb), 1)
        self.assertEqual(imb[0]["lesson_id"], "l2")

        ctx = ExperienceContext(imbalanced_lessons=imb, lesson_count=3)
        suggestions = local_suggestions(ctx, limit=3)
        balance = [s for s in suggestions if s["action_id"] == "lesson.balance"]
        self.assertEqual(len(balance), 1)
        self.assertEqual(balance[0]["scope"]["lesson_id"], "l2")


if __name__ == "__main__":
    unittest.main()
