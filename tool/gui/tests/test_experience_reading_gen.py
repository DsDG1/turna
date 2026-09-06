"""v4.39 K-18 reading.passages_gen tests (evaluator + context + dispatch)."""
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


def _reading_lesson(*, lid="r1", title="", paragraphs=None):
    return {
        "id": lid, "template": "reading",
        "content": {"readingPassage": {"title": title, "paragraphs": paragraphs or []}},
    }


class EvaluateReadingPassageTest(unittest.TestCase):
    def test_empty_title(self) -> None:
        from src.backend.content_quality import evaluate_reading_passage

        self.assertTrue(evaluate_reading_passage(_reading_lesson(title="", paragraphs=["p"]))["empty"])

    def test_empty_paragraphs(self) -> None:
        from src.backend.content_quality import evaluate_reading_passage

        self.assertTrue(evaluate_reading_passage(_reading_lesson(title="T", paragraphs=[]))["empty"])

    def test_stub_paragraphs(self) -> None:
        from src.backend.content_quality import evaluate_reading_passage

        r = evaluate_reading_passage(_reading_lesson(title="T", paragraphs=["…", "TBD"]))
        self.assertTrue(r["empty"])
        self.assertIn("占位", r["reason"])

    def test_real_content_not_empty(self) -> None:
        from src.backend.content_quality import evaluate_reading_passage

        r = evaluate_reading_passage(_reading_lesson(title="T", paragraphs=["real paragraph"]))
        self.assertFalse(r["empty"])

    def test_non_reading_not_empty(self) -> None:
        from src.backend.content_quality import evaluate_reading_passage

        lesson = {"id": "x", "template": "intro", "content": {}}
        self.assertFalse(evaluate_reading_passage(lesson)["empty"])

    def test_no_passage_empty(self) -> None:
        from src.backend.content_quality import evaluate_reading_passage

        lesson = {"id": "x", "template": "reading", "content": {}}
        self.assertTrue(evaluate_reading_passage(lesson)["empty"])

    def test_never_raises_on_bad_input(self) -> None:
        from src.backend.content_quality import evaluate_reading_passage

        self.assertFalse(evaluate_reading_passage(None)["empty"])  # type: ignore[arg-type]
        self.assertFalse(evaluate_reading_passage({})["empty"])


class SuggestionContextTest(unittest.TestCase):
    def test_suggestion_only_when_empty(self) -> None:
        from src.backend.experience.context_bus import ExperienceContext, local_suggestions

        ctx = ExperienceContext(
            empty_reading_passages=[{"lesson_id": "r1", "section_id": "s1", "reason": "标题空"}],
            lesson_count=1,
        )
        sug = [s for s in local_suggestions(ctx, limit=5) if s["action_id"] == "reading.passages_gen"]
        self.assertEqual(len(sug), 1)
        scope = sug[0]["scope"]
        self.assertEqual(scope["lesson_id"], "r1")
        # closed-set scope: no paragraph raw text
        for key in ("paragraphs", "title", "reason"):
            self.assertNotIn(key, scope)

    def test_no_suggestion_when_healthy(self) -> None:
        from src.backend.experience.context_bus import ExperienceContext, local_suggestions

        ctx = ExperienceContext(empty_reading_passages=[], lesson_count=1)
        self.assertEqual([s for s in local_suggestions(ctx, limit=5) if s["action_id"] == "reading.passages_gen"], [])


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


class _CmdSignals:
    def __init__(self) -> None:
        self.changed = self

    def connect(self, _cb) -> None:
        pass


class _FakeMergeCommand:
    def __init__(self, adapter, plan) -> None:
        self.plan = plan
        self.signals = _CmdSignals()


class _Adapter:
    def __init__(self, section: dict) -> None:
        self.sections = [section]
        self.course_dir = "/tmp/course"

    def find_lesson(self, lesson_id: str):
        for unit in self.sections[0].get("units") or []:
            for lesson in unit.get("lessons") or []:
                if lesson.get("id") == lesson_id:
                    return self.sections[0], unit, lesson
        raise KeyError(lesson_id)

    def plan_section_merge(self, sid, result):
        return {"section_id": sid, "result": result}


class _UndoStack:
    def __init__(self) -> None:
        self.commands: list = []

    def push(self, cmd) -> None:
        self.commands.append(cmd)


class ReadingGenSkillTest(unittest.TestCase):
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
        win._run_regen_flow = lambda **kw: ExperienceSkillsMixin._run_regen_flow(win, **kw)
        win.course_dir = "/tmp/course"
        win._current_node_ref = ("lesson", lesson["id"])
        win.adapter = _Adapter({"id": "s1", "units": [{"id": "u1", "lessons": [lesson]}]})
        win.conflict_guard = ConflictGuard()
        win.experience_metrics = _Metrics()
        win.job_tray = _JobTray()
        win.undo_stack = _UndoStack()
        win._messages: list[str] = []
        win.statusBar = lambda: SimpleNamespace(
            showMessage=lambda m, ms=0: win._messages.append(m)
        )
        win._ai_config = object()
        win._sync_focus_ring = lambda: None
        win._refresh_experience = lambda **k: None
        win._on_ai_edit_applied = lambda *a: None
        win._refresh_validate_after_ai = lambda msg: None
        win._record_experience_event = lambda *a, **k: None
        win._deny_ai_write_if_blocked = lambda label="": False
        return win

    def test_no_course_dir_status(self) -> None:
        from src.application.experience_skills_mixin import ExperienceSkillsMixin

        win = self._make_window(_reading_lesson())
        win.course_dir = ""
        with patch("src.application.experience_skills_mixin.QMessageBox") as mb:
            mb.StandardButton = __import__(
                "PySide6.QtWidgets", fromlist=["QMessageBox"]
            ).QMessageBox.StandardButton
            ExperienceSkillsMixin._experience_reading_gen(win, {"lesson_id": "r1"})
        self.assertIsNone(_FakeWorker.last)

    def test_healthy_lesson_zero_llm(self) -> None:
        from src.application.experience_skills_mixin import ExperienceSkillsMixin

        lesson = _reading_lesson(title="T", paragraphs=["real"])
        win = self._make_window(lesson)
        ExperienceSkillsMixin._experience_reading_gen(win, {"lesson_id": "r1"})
        self.assertIsNone(_FakeWorker.last)
        self.assertTrue(any("已就绪" in m for m in win._messages))

    def _run_empty(self, win, *, confirm: bool, diff_accept: bool = True):
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
            "src.application.ai_request_worker.AiRequestWorker", _FakeWorker
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
                QDialog.DialogCode.Accepted if diff_accept else QDialog.DialogCode.Rejected
            )
            ExperienceSkillsMixin._experience_reading_gen(win, {"lesson_id": "r1"})
            worker = _FakeWorker.last
            if worker is not None:
                worker.result_ready.emit(worker.fn())
        return captured

    def test_confirm_runs_worker_with_reading_instruction(self) -> None:
        win = self._make_window(_reading_lesson())
        captured = self._run_empty(win, confirm=True)
        self.assertIsNotNone(_FakeWorker.last)
        instr = captured.get("instruction") or ""
        self.assertIn("readingPassage", instr)
        self.assertIn("保持全部 id", instr)
        m = win.experience_metrics.counts
        self.assertEqual(m.get(("suggestion", "reading.passages_gen", "applied")), 1)
        self.assertEqual(len(win.undo_stack.commands), 1)
        self.assertEqual(win.job_tray.jobs, [])

    def test_decline_records_rejected(self) -> None:
        win = self._make_window(_reading_lesson())
        self._run_empty(win, confirm=False)
        self.assertIsNone(_FakeWorker.last)
        m = win.experience_metrics.counts
        self.assertEqual(m.get(("suggestion", "reading.passages_gen", "rejected")), 1)
        self.assertEqual(len(win.undo_stack.commands), 0)

    def test_diff_cancel_no_write(self) -> None:
        win = self._make_window(_reading_lesson())
        self._run_empty(win, confirm=True, diff_accept=False)
        self.assertEqual(len(win.undo_stack.commands), 0)
        m = win.experience_metrics.counts
        self.assertEqual(m.get(("suggestion", "reading.passages_gen", "rejected")), 1)
        self.assertNotIn(("suggestion", "reading.passages_gen", "applied"), m)


class RoutingContractTest(unittest.TestCase):
    def test_slash_exact(self) -> None:
        from src.backend.experience.intent_router import route_intent

        i = route_intent("/reading-gen")
        self.assertEqual(i.action_id, "reading.passages_gen")
        self.assertEqual(i.confidence, 1.0)

    def test_keyword(self) -> None:
        from src.backend.experience.intent_router import route_intent

        self.assertEqual(route_intent("阅读段落").action_id, "reading.passages_gen")

    def test_golden_has_reading_gen(self) -> None:
        import json

        path = Path(__file__).resolve().parent / "ai_goldens" / "intent_routes.json"
        rows = json.loads(path.read_text(encoding="utf-8"))
        self.assertTrue(any(r.get("text") == "/reading-gen" for r in rows))

    def test_action_spec_needs_confirm_not_dangerous(self) -> None:
        from src.backend.experience import get_action
        from src.backend.experience.actions import DANGEROUS_ACTION_IDS

        spec = get_action("reading.passages_gen")
        self.assertTrue(spec.needs_confirm)
        self.assertFalse(spec.dangerous)
        self.assertNotIn("reading.passages_gen", DANGEROUS_ACTION_IDS)


if __name__ == "__main__":
    unittest.main()