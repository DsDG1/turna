"""E3-B3: real AI goal lesson generation → sandbox → merge (v4.33).

Covers the swap from E3-B2 stub fill to real ``request_lesson_transform``-
shaped lessons staged into the sandbox, plus the skip-on-fail, offline
fallback, and id-preserve red-lines. The AI worker is replaced by a fake
factory (``host._goal_fill_worker_factory``) that runs the target inline
and emits ``result_ready`` synchronously so the chain completes before
the controller returns — no real network / no API key.
"""
from __future__ import annotations

import copy
import json
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from typing import Any
from unittest.mock import MagicMock

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.experience.goal_generate import (  # noqa: E402
    is_lesson_payload_mergeable,
    payload_summary,
)
from src.backend.experience.sandbox import CourseSandbox  # noqa: E402
from src.backend.experience.planner import plan_from_context  # noqa: E402
from src.application.goal_controller import (  # noqa: E402
    _collect_fill_lesson_ids,
    apply_merge_plan_on_host,
    apply_sandbox_lessons_to_host,
    run_sandbox_real_fill_for_host,
    show_batch_diff_for_merge,
)


def _empty_lesson(lid: str) -> dict:
    return {
        "id": lid,
        "name": f"Empty {lid}",
        "template": "intro",
        "content": {"subLessons": []},
    }


def _real_ai_lesson(lid: str) -> dict:
    """Shape mirroring request_lesson_transform output (id-preserving, with
    content.subLessons so is_lesson_payload_mergeable → True)."""
    return {
        "id": lid,
        "name": f"AI {lid}",
        "template": "intro",
        "content": {
            "subLessons": [
                {
                    "id": f"{lid}-sub1",
                    "stages": [
                        {
                            "id": f"{lid}-st1",
                            "items": [
                                {"id": f"{lid}-i1", "runtimeType": "showWord", "wordId": "merhaba"}
                            ],
                        }
                    ],
                }
            ]
        },
    }


def _adapter(lessons: list[dict] | None = None) -> Any:
    les = lessons or [_empty_lesson("s1-l1"), _empty_lesson("s1-l2")]
    section = {
        "id": "section1",
        "name": "S1",
        "units": [{"id": "u1", "name": "U", "lessons": les}],
    }

    class Adapter:
        def __init__(self) -> None:
            self.sections = [copy.deepcopy(section)]
            self._invalidated = 0

        def find_lesson(self, lesson_id: str) -> tuple[dict, dict, dict]:
            for sec in self.sections:
                for unit in sec["units"]:
                    for l in unit["lessons"]:
                        if l["id"] == lesson_id:
                            return sec, unit, l
            raise KeyError(lesson_id)

        def find_section(self, section_id: str) -> dict:
            for sec in self.sections:
                if sec["id"] == section_id:
                    return sec
            raise KeyError(section_id)

        def invalidate_node_index(self) -> None:
            self._invalidated += 1

    return Adapter()


def _make_signal():
    """Minimal Signal stand-in: ``connect(handler)`` records handlers; emit
    is manual via the factory's inline start()."""
    sig = MagicMock()

    def connect(handler):
        sig._handlers.append(handler)

    sig._handlers = []
    sig.connect = connect
    return sig


def _fake_worker_factory():
    """Factory returning workers that run the target inline and deliver
    result/error to registered handlers synchronously (headless, no Qt)."""

    def factory(target):
        w = SimpleNamespace()
        w.result_ready = _make_signal()
        w.error_occurred = _make_signal()

        def start(*args: Any, **kwargs: Any) -> None:
            try:
                result = target()
            except Exception as exc:  # noqa: BLE001
                for cb in list(w.error_occurred._handlers):
                    cb(str(exc))
            else:
                for cb in list(w.result_ready._handlers):
                    cb(result)

        w.start = start
        return w

    return factory


class _Stack:
    def __init__(self) -> None:
        self.cmds: list[Any] = []

    def push(self, cmd: Any) -> None:
        self.cmds.append(cmd)
        cmd.redo()


def _host(
    adapter: Any,
    *,
    ai_complete: bool = True,
    worker_factory: Any = None,
) -> SimpleNamespace:
    from src.backend.experience.conflict_guard import ConflictGuard
    from src.backend.experience.job_registry import JobRegistry
    from src.backend.experience.metrics import ExperienceMetrics

    config = SimpleNamespace(is_complete=ai_complete)
    host = SimpleNamespace(
        adapter=adapter,
        undo_stack=_Stack(),
        tree=MagicMock(),
        _refresh_experience=MagicMock(),
        _sync_focus_ring=MagicMock(),
        _refresh_validate_after_ai=MagicMock(),
        _record_experience_event=MagicMock(),
        _on_experience_suggestion=MagicMock(),
        experience_metrics=ExperienceMetrics(),
        conflict_guard=ConflictGuard(),
        job_tray=JobRegistry(),
        _ai_config=config,
        statusBar=MagicMock(),
    )
    if worker_factory is not None:
        host._goal_fill_worker_factory = worker_factory
    return host


class StageRealFillTest(unittest.TestCase):
    def test_stage_real_fill_forces_id_and_is_mergeable(self) -> None:
        ad = _adapter([_empty_lesson("keep")])
        box = CourseSandbox.from_adapter(ad, lesson_ids=["keep"])
        ai = _real_ai_lesson("X")  # id drifted
        self.assertTrue(box.stage_real_fill("keep", new_lesson=ai))
        mp = box.to_merge_plan()
        payload = mp.items[0].sandbox_payload
        self.assertEqual(payload["id"], "keep")  # id preserved over AI drift
        self.assertTrue(is_lesson_payload_mergeable(payload))
        # No stub tag → summary says「生成」not「stub」.
        self.assertIn("生成", payload_summary(payload))
        self.assertNotIn("stub", payload_summary(payload))

    def test_stage_real_fill_rejects_non_mergeable(self) -> None:
        ad = _adapter([_empty_lesson("keep")])
        box = CourseSandbox.from_adapter(ad, lesson_ids=["keep"])
        bad = {"id": "keep", "content": {"subLessons": []}}  # empty subLessons
        self.assertFalse(box.stage_real_fill("keep", new_lesson=bad))

    def test_stage_real_fill_does_not_mutate_adapter(self) -> None:
        ad = _adapter([_empty_lesson("s1-l1")])
        before = json.dumps(ad.sections, sort_keys=True)
        box = CourseSandbox.from_adapter(ad, lesson_ids=["s1-l1"])
        box.stage_real_fill("s1-l1", new_lesson=_real_ai_lesson("s1-l1"))
        after = json.dumps(ad.sections, sort_keys=True)
        self.assertEqual(before, after)


class CollectFillIdsTest(unittest.TestCase):
    def test_collects_unique_ordered(self) -> None:
        from src.backend.experience.planner import GoalStep

        plan = SimpleNamespace(
            steps=[
                GoalStep("a", "lesson.fill_empty", "f1", {"lesson_id": "l1"}, (), False),
                GoalStep("b", "validate.open_and_fix", "v", {"error_count": 1}, (), False),
                GoalStep("c", "lesson.fill_empty", "f2", {"lesson_id": "l2"}, (), False),
                GoalStep("d", "lesson.fill_empty", "f3", {"lesson_id": "l1"}, (), False),
            ]
        )
        self.assertEqual(_collect_fill_lesson_ids(plan), ["l1", "l2"])


class RealFillChainTest(unittest.TestCase):
    def test_real_fill_isolates_and_stages(self) -> None:
        ad = _adapter([_empty_lesson("s1-l1")])
        before = json.dumps(ad.sections, sort_keys=True)
        host = _host(ad, worker_factory=_fake_worker_factory())

        # Monkeypatch regenerate_lesson_in_section to return a section whose
        # lesson s1-l1 is the real AI lesson.
        import src.backend.ai_generator as ai_gen

        orig = ai_gen.regenerate_lesson_in_section

        def fake_regen(config, spec, section, lid, instruction=None, **kw):
            new_section = copy.deepcopy(section)
            for u in new_section.get("units") or []:
                for i, l in enumerate(u.get("lessons") or []):
                    if l.get("id") == lid:
                        u["lessons"][i] = _real_ai_lesson(lid)
            return new_section

        ai_gen.regenerate_lesson_in_section = fake_regen
        try:
            ctx = SimpleNamespace(
                empty_lessons=["s1-l1"],
                validate_error_count=0,
                hygiene={},
                listening_gaps=[],
                imbalanced_lessons=[],
            )
            plan = plan_from_context(ctx, goal_text="空课")
            box, mp, err = run_sandbox_real_fill_for_host(host, plan)
            self.assertEqual(err, "")
            after = json.dumps(ad.sections, sort_keys=True)
            self.assertEqual(before, after)  # isolation
            self.assertIsNotNone(mp)
            payload = mp.items[0].sandbox_payload
            self.assertTrue(is_lesson_payload_mergeable(payload))
            self.assertEqual(payload["id"], "s1-l1")
        finally:
            ai_gen.regenerate_lesson_in_section = orig

    def test_real_fill_skip_on_fail_keeps_others(self) -> None:
        ad = _adapter([_empty_lesson("s1-l1"), _empty_lesson("s1-l2"), _empty_lesson("s1-l3")])
        before = json.dumps(ad.sections, sort_keys=True)
        host = _host(ad, worker_factory=_fake_worker_factory())
        import src.backend.ai_generator as ai_gen

        orig = ai_gen.regenerate_lesson_in_section
        calls = {"n": 0}

        def fake_regen(config, spec, section, lid, instruction=None, **kw):
            calls["n"] += 1
            if lid == "s1-l2":
                raise RuntimeError("boom")
            new_section = copy.deepcopy(section)
            for u in new_section.get("units") or []:
                for i, l in enumerate(u.get("lessons") or []):
                    if l.get("id") == lid:
                        u["lessons"][i] = _real_ai_lesson(lid)
            return new_section

        ai_gen.regenerate_lesson_in_section = fake_regen
        try:
            ctx = SimpleNamespace(
                empty_lessons=["s1-l1", "s1-l2", "s1-l3"],
                validate_error_count=0,
                hygiene={},
                listening_gaps=[],
                imbalanced_lessons=[],
            )
            plan = plan_from_context(ctx, goal_text="全部空课")
            box, mp, err = run_sandbox_real_fill_for_host(host, plan)
            self.assertEqual(err, "")
            self.assertEqual(before, json.dumps(ad.sections, sort_keys=True))
            staged_ids = [it.id for it in mp.items if it.kind == "lesson"]
            self.assertIn("s1-l1", staged_ids)
            self.assertIn("s1-l3", staged_ids)
            self.assertNotIn("s1-l2", staged_ids)  # failed → skipped
            self.assertEqual(calls["n"], 3)
        finally:
            ai_gen.regenerate_lesson_in_section = orig

    def test_fallback_stub_when_no_ai_config(self) -> None:
        ad = _adapter([_empty_lesson("s1-l1")])
        host = _host(ad, ai_complete=False, worker_factory=None)
        ctx = SimpleNamespace(
            empty_lessons=["s1-l1"],
            validate_error_count=0,
            hygiene={},
            listening_gaps=[],
            imbalanced_lessons=[],
        )
        plan = plan_from_context(ctx, goal_text="空课")
        box, mp, err = run_sandbox_real_fill_for_host(host, plan)
        self.assertEqual(err, "")
        payload = mp.items[0].sandbox_payload
        self.assertTrue(is_lesson_payload_mergeable(payload))
        # fallback payload is stub-tagged.
        self.assertTrue(payload.get("meta", {}).get("sandbox_stub_fill"))
        # fallback event recorded.
        kinds = [c.args[0] for c in host._record_experience_event.call_args_list]
        self.assertIn("goal.fallback_stub", kinds)


class ApplyAndUndoTest(unittest.TestCase):
    def test_apply_real_payload_then_undo_restores(self) -> None:
        ad = _adapter([_empty_lesson("only")])
        box = CourseSandbox.from_adapter(ad, lesson_ids=["only"])
        box.stage_real_fill("only", new_lesson=_real_ai_lesson("only"))
        mp = box.to_merge_plan()
        host = _host(ad)
        n = apply_sandbox_lessons_to_host(host, mp)
        self.assertEqual(n, 1)
        _s, _u, les = ad.find_lesson("only")
        self.assertTrue(les["content"]["subLessons"])
        self.assertEqual(les["id"], "only")
        # Undo restores empty
        host.undo_stack.cmds[0].undo()
        _s, _u, les2 = ad.find_lesson("only")
        self.assertEqual(les2["content"].get("subLessons") or [], [])


class BatchDiffConfirmTest(unittest.TestCase):
    def test_batch_diff_auto_confirms_headless(self) -> None:
        ad = _adapter([_empty_lesson("only")])
        box = CourseSandbox.from_adapter(ad, lesson_ids=["only"])
        box.stage_real_fill("only", new_lesson=_real_ai_lesson("only"))
        mp = box.to_merge_plan()
        host = _host(ad)
        # No Qt event loop → SectionDiffView construction raises → auto-confirm.
        self.assertTrue(show_batch_diff_for_merge(host, mp))


if __name__ == "__main__":
    unittest.main()