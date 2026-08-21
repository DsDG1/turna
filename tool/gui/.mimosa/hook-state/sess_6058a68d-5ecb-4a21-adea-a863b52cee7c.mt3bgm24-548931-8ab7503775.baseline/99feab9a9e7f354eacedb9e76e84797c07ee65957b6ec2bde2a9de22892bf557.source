"""v4.37 K-08 unit.spiral_vocab tests (词汇螺旋)."""
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


def _section(*, sid: str = "s1", units: list[dict] | None = None,
             words: list[dict] | None = None) -> dict:
    return {
        "id": sid,
        "level": "A1",
        "words": words or [{"id": "w1", "term": "merhaba"},
                           {"id": "w2", "term": "teşekkür"}],
        "units": units or [
            {"id": "u1", "lessons": [
                {"id": "l1", "content": {"stages": [{"id": "st1", "items": [
                    {"id": "i1", "runtimeType": "showWord", "wordId": "w1"},
                    {"id": "i2", "runtimeType": "showWord", "wordId": "w2"},
                ]}]}},
                {"id": "l2", "content": {"stages": [{"id": "st2", "items": [
                    {"id": "i3", "runtimeType": "multipleChoice", "wordId": "w2",
                     "expected": "teşekkür", "options": ["teşekkür", "x"]},
                ]}]}},
            ]},
        ],
    }


class EvaluateUnitSpiralTest(unittest.TestCase):
    def test_empty_section_no_gap(self) -> None:
        from src.backend.content_quality import evaluate_unit_spiral

        r = evaluate_unit_spiral({"id": "s1", "units": [], "words": []})
        self.assertEqual(r["unsurfaced_count"], 0)
        self.assertEqual(r["unsurfaced"], [])

    def test_wordless_section_no_gap(self) -> None:
        from src.backend.content_quality import evaluate_unit_spiral

        r = evaluate_unit_spiral({"id": "s1", "units": [{"id": "u1", "lessons": []}], "words": []})
        self.assertEqual(r["total_introduced"], 0)
        self.assertEqual(r["unsurfaced_count"], 0)

    def test_intro_then_reuse_in_later_lesson_surfaced(self) -> None:
        from src.backend.content_quality import evaluate_unit_spiral

        section = {
            "id": "s1", "words": [{"id": "w1", "term": "merhaba"}],
            "units": [{"id": "u1", "lessons": [
                {"id": "l1", "content": {"stages": [{"id": "st1", "items": [
                    {"id": "i1", "runtimeType": "showWord", "wordId": "w1"},
                ]}]}},
                {"id": "l2", "content": {"stages": [{"id": "st2", "items": [
                    {"id": "i2", "runtimeType": "multipleChoice", "wordId": "w1",
                     "expected": "merhaba", "options": ["merhaba", "x"]},
                ]}]}},
            ]}],
        }
        r = evaluate_unit_spiral(section)
        self.assertEqual(r["total_introduced"], 1)
        self.assertEqual(r["surfaced_count"], 1)
        self.assertEqual(r["unsurfaced_count"], 0)

    def test_intro_never_reused_unsurfaced(self) -> None:
        from src.backend.content_quality import evaluate_unit_spiral

        r = evaluate_unit_spiral(_section())
        # w1 introduced in l1, never re-surfaced; w2 surfaced in l2.
        self.assertEqual(r["unsurfaced_count"], 1)
        self.assertEqual(r["unsurfaced"][0]["word_id"], "w1")
        self.assertEqual(r["unsurfaced"][0]["intro_lesson_id"], "l1")
        self.assertEqual(r["unsurfaced"][0]["section_id"], "s1")

    def test_same_lesson_practice_does_not_count_as_later(self) -> None:
        from src.backend.content_quality import evaluate_unit_spiral

        section = {
            "id": "s1", "words": [{"id": "w1", "term": "merhaba"}],
            "units": [{"id": "u1", "lessons": [
                {"id": "l1", "content": {"stages": [{"id": "st1", "items": [
                    {"id": "i1", "runtimeType": "showWord", "wordId": "w1"},
                    {"id": "i2", "runtimeType": "multipleChoice", "wordId": "w1",
                     "expected": "merhaba", "options": ["merhaba", "x"]},
                ]}]}},
            ]}],
        }
        r = evaluate_unit_spiral(section)
        # No lesson strictly after l1 → w1 stays unsurfaced.
        self.assertEqual(r["surfaced_count"], 0)
        self.assertEqual(r["unsurfaced_count"], 1)

    def test_term_echo_in_options_counts_as_surfaced(self) -> None:
        from src.backend.content_quality import evaluate_unit_spiral

        # No explicit wordId on the MCQ, but term echoed in options.
        section = {
            "id": "s1", "words": [{"id": "w1", "term": "merhaba"}],
            "units": [{"id": "u1", "lessons": [
                {"id": "l1", "content": {"stages": [{"id": "st1", "items": [
                    {"id": "i1", "runtimeType": "showWord", "wordId": "w1"},
                ]}]}},
                {"id": "l2", "content": {"stages": [{"id": "st2", "items": [
                    {"id": "i2", "runtimeType": "multipleChoice",
                     "options": ["merhaba", "selam"], "expected": "merhaba"},
                ]}]}},
            ]}],
        }
        r = evaluate_unit_spiral(section)
        self.assertEqual(r["surfaced_count"], 1)
        self.assertEqual(r["unsurfaced_count"], 0)

    def test_cross_unit_later_lesson_surfaced(self) -> None:
        from src.backend.content_quality import evaluate_unit_spiral

        section = {
            "id": "s1", "words": [{"id": "w1", "term": "merhaba"}],
            "units": [
                {"id": "u1", "lessons": [
                    {"id": "l1", "content": {"stages": [{"id": "st1", "items": [
                        {"id": "i1", "runtimeType": "showWord", "wordId": "w1"},
                    ]}]}},
                ]},
                {"id": "u2", "lessons": [
                    {"id": "l2", "content": {"stages": [{"id": "st2", "items": [
                        {"id": "i2", "runtimeType": "fillBlank", "wordId": "w1"},
                    ]}]}},
                ]},
            ],
        }
        r = evaluate_unit_spiral(section)
        self.assertEqual(r["surfaced_count"], 1)
        self.assertEqual(r["unsurfaced_count"], 0)

    def test_closed_shape_no_item_body(self) -> None:
        from src.backend.content_quality import evaluate_unit_spiral

        r = evaluate_unit_spiral(_section())
        for u in r["unsurfaced"]:
            self.assertEqual(set(u.keys()), {"word_id", "term", "intro_lesson_id", "section_id"})
            # raw options/expected text must not leak into the report.
            self.assertNotIn("options", u)
            self.assertNotIn("expected", u)


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

    @property
    def section(self) -> dict:
        return self.sections[0]

    def find_section(self, sid: str) -> dict:
        if sid != self.sections[0].get("id"):
            raise KeyError(sid)
        return self.sections[0]

    def find_lesson(self, lesson_id: str):
        for unit in self.sections[0].get("units") or []:
            for lesson in unit.get("lessons") or []:
                if lesson.get("id") == lesson_id:
                    return self.sections[0], unit, lesson
        raise KeyError(lesson_id)

    def find_unit(self, unit_id: str):
        for unit in self.sections[0].get("units") or []:
            if unit.get("id") == unit_id:
                return self.sections[0], unit
        raise KeyError(unit_id)

    def plan_section_merge(self, sid: str, result: dict) -> dict:
        return {"section_id": sid, "result": result}


class _UndoStack:
    def __init__(self) -> None:
        self.commands: list = []

    def push(self, cmd) -> None:
        self.commands.append(cmd)


class SpiralSuggestionContextTest(unittest.TestCase):
    def test_suggestion_only_when_unsurfaced(self) -> None:
        from src.backend.experience.context_bus import ExperienceContext, local_suggestions

        ctx = ExperienceContext(
            unsurfaced_words=[
                {"word_id": "w1", "term": "merhaba", "intro_lesson_id": "l1", "section_id": "s1"},
            ],
            lesson_count=2,
        )
        sug = [s for s in local_suggestions(ctx, limit=3) if s["action_id"] == "unit.spiral_vocab"]
        self.assertEqual(len(sug), 1)
        scope = sug[0]["scope"]
        self.assertEqual(scope["count"], 1)
        self.assertEqual(scope["section_id"], "s1")
        self.assertIn("w1", scope["word_ids"])
        # closed-set scope: no raw item text leaks.
        for key in ("options", "expected", "term"):
            self.assertNotIn(key, scope)

    def test_no_suggestion_when_healthy(self) -> None:
        from src.backend.experience.context_bus import ExperienceContext, local_suggestions

        ctx = ExperienceContext(unsurfaced_words=[], lesson_count=2)
        sug = [s for s in local_suggestions(ctx, limit=3) if s["action_id"] == "unit.spiral_vocab"]
        self.assertEqual(sug, [])


class SpiralRoutingTest(unittest.TestCase):
    def test_slash_exact_high_confidence(self) -> None:
        from src.backend.experience.intent_router import route_intent

        i = route_intent("/spiral")
        self.assertIsNotNone(i)
        self.assertEqual(i.action_id, "unit.spiral_vocab")
        self.assertEqual(i.confidence, 1.0)

    def test_keyword_route(self) -> None:
        from src.backend.experience.intent_router import route_intent

        i = route_intent("词汇螺旋")
        self.assertIsNotNone(i)
        self.assertEqual(i.action_id, "unit.spiral_vocab")

    def test_golden_file_has_spiral(self) -> None:
        import json

        path = Path(__file__).resolve().parent / "ai_goldens" / "intent_routes.json"
        rows = json.loads(path.read_text(encoding="utf-8"))
        self.assertTrue(any(r.get("text") == "/spiral" for r in rows))


class SpiralActionContractTest(unittest.TestCase):
    def test_registered_needs_confirm_not_dangerous(self) -> None:
        from src.backend.experience import get_action
        from src.backend.experience.actions import DANGEROUS_ACTION_IDS

        spec = get_action("unit.spiral_vocab")
        self.assertIsNotNone(spec)
        self.assertTrue(spec.needs_confirm)
        self.assertFalse(spec.dangerous)
        self.assertNotIn("unit.spiral_vocab", DANGEROUS_ACTION_IDS)


class SpiralSkillTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        qt_app()

    def setUp(self) -> None:
        _FakeWorker.last = None

    def _make_window(self, section: dict):
        from PySide6.QtWidgets import QWidget
        from src.application.experience_skills_mixin import ExperienceSkillsMixin
        from src.backend.experience.conflict_guard import ConflictGuard

        win = QWidget()
        self.addCleanup(win.deleteLater)
        win._run_regen_flow = lambda **kw: ExperienceSkillsMixin._run_regen_flow(
            win, **kw
        )
        win.course_dir = "/tmp/course"
        win._current_node_ref = ("lesson", "l1")
        win.adapter = _Adapter(section)
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

    def test_no_course_dir_status_bar(self) -> None:
        from src.application.experience_skills_mixin import ExperienceSkillsMixin

        win = self._make_window(_section())
        win.course_dir = ""
        with patch("src.application.experience_skills_mixin.QMessageBox") as mb:
            mb.StandardButton = __import__(
                "PySide6.QtWidgets", fromlist=["QMessageBox"]
            ).QMessageBox.StandardButton
            ExperienceSkillsMixin._experience_spiral_vocab(win, {})
        self.assertIsNone(_FakeWorker.last)

    def test_healthy_section_zero_llm(self) -> None:
        from src.application.experience_skills_mixin import ExperienceSkillsMixin
        from src.backend.content_quality import evaluate_unit_spiral

        # Both words surfaced in l2 → healthy.
        section = {
            "id": "s1", "words": [{"id": "w1", "term": "merhaba"},
                                  {"id": "w2", "term": "teşekkür"}],
            "units": [{"id": "u1", "lessons": [
                {"id": "l1", "content": {"stages": [{"id": "st1", "items": [
                    {"id": "i1", "runtimeType": "showWord", "wordId": "w1"},
                    {"id": "i2", "runtimeType": "showWord", "wordId": "w2"},
                ]}]}},
                {"id": "l2", "content": {"stages": [{"id": "st2", "items": [
                    {"id": "i3", "runtimeType": "multipleChoice", "wordId": "w1",
                     "expected": "merhaba", "options": ["merhaba", "x"]},
                    {"id": "i4", "runtimeType": "fillBlank", "wordId": "w2"},
                ]}]}},
            ]}],
        }
        self.assertEqual(evaluate_unit_spiral(section)["unsurfaced_count"], 0)
        win = self._make_window(section)
        ExperienceSkillsMixin._experience_spiral_vocab(win, {"section_id": "s1"})
        self.assertIsNone(_FakeWorker.last)
        self.assertTrue(any("螺旋健康" in m for m in win._messages))

    def _run_unsurfaced(self, win, *, confirm: bool, diff_accept: bool = True):
        from PySide6.QtWidgets import QDialog
        from src.application.experience_skills_mixin import ExperienceSkillsMixin

        captured: dict = {}

        def _regen(config, spec, draft, node_id, instruction=None, **kw):
            captured["instruction"] = instruction
            captured["node_id"] = node_id
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
                QDialog.DialogCode.Accepted if diff_accept else QDialog.DialogCode.Rejected
            )
            ExperienceSkillsMixin._experience_spiral_vocab(win, {"section_id": "s1"})
            worker = _FakeWorker.last
            if worker is not None:
                worker.result_ready.emit(worker.fn())
        return captured

    def test_confirm_runs_worker_with_spiral_instruction(self) -> None:
        win = self._make_window(_section())
        captured = self._run_unsurfaced(win, confirm=True)
        self.assertIsNotNone(_FakeWorker.last)
        instr = captured.get("instruction") or ""
        self.assertIn("螺旋复现", instr)
        self.assertIn("保持全部 id", instr)
        self.assertIn("merhaba", instr)  # term listed
        m = win.experience_metrics.counts
        self.assertEqual(m.get(("suggestion", "unit.spiral_vocab", "applied")), 1)
        self.assertEqual(m.get(("job", "ai", "started")), 1)
        self.assertEqual(m.get(("job", "ai", "finished")), 1)
        self.assertEqual(len(win.undo_stack.commands), 1)
        self.assertEqual(win.job_tray.jobs, [])

    def test_decline_records_rejected_no_worker(self) -> None:
        win = self._make_window(_section())
        self._run_unsurfaced(win, confirm=False)
        self.assertIsNone(_FakeWorker.last)
        m = win.experience_metrics.counts
        self.assertEqual(m.get(("suggestion", "unit.spiral_vocab", "rejected")), 1)
        self.assertEqual(len(win.undo_stack.commands), 0)

    def test_guard_busy_blocks_after_confirm(self) -> None:
        win = self._make_window(_section())
        self.assertTrue(win.conflict_guard.try_acquire("lesson:l1", "other"))
        self._run_unsurfaced(win, confirm=True)
        self.assertIsNone(_FakeWorker.last)
        m = win.experience_metrics.counts
        self.assertEqual(m.get(("guard", "rejected")), 1)

    def test_diff_cancel_no_write(self) -> None:
        win = self._make_window(_section())
        self._run_unsurfaced(win, confirm=True, diff_accept=False)
        self.assertEqual(len(win.undo_stack.commands), 0)
        m = win.experience_metrics.counts
        self.assertEqual(m.get(("suggestion", "unit.spiral_vocab", "rejected")), 1)
        self.assertNotIn(("suggestion", "unit.spiral_vocab", "applied"), m)

    def test_resolves_section_from_selection_when_scope_empty(self) -> None:
        from src.application.experience_skills_mixin import ExperienceSkillsMixin
        from src.backend.content_quality import evaluate_unit_spiral

        # Healthy section + empty scope → resolves section from selection and
        # short-circuits with a healthy status bar (no confirm dialog).
        section = {
            "id": "s1", "words": [{"id": "w1", "term": "merhaba"}],
            "units": [{"id": "u1", "lessons": [
                {"id": "l1", "content": {"stages": [{"id": "st1", "items": [
                    {"id": "i1", "runtimeType": "showWord", "wordId": "w1"},
                ]}]}},
                {"id": "l2", "content": {"stages": [{"id": "st2", "items": [
                    {"id": "i2", "runtimeType": "fillBlank", "wordId": "w1"},
                ]}]}},
            ]}],
        }
        self.assertEqual(evaluate_unit_spiral(section)["unsurfaced_count"], 0)
        win = self._make_window(section)
        win._current_node_ref = ("lesson", "l1")  # scope has no section_id
        ExperienceSkillsMixin._experience_spiral_vocab(win, {})
        self.assertIsNone(_FakeWorker.last)
        self.assertTrue(any("螺旋健康" in m for m in win._messages))


if __name__ == "__main__":
    unittest.main()