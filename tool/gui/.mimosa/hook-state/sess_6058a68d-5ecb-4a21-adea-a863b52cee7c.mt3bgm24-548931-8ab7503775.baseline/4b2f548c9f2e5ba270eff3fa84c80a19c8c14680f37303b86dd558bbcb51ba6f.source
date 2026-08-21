"""E3-B2: stub generate + LessonPatch merge isolation."""
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
    build_stub_lesson,
    force_lesson_id,
    is_lesson_payload_mergeable,
)
from src.backend.experience.sandbox import CourseSandbox  # noqa: E402
from src.backend.experience.planner import plan_from_context  # noqa: E402
from src.backend.experience.patch import lesson_patch_from_replace  # noqa: E402
from src.application.goal_controller import (  # noqa: E402
    apply_merge_plan_on_host,
    apply_sandbox_lessons_to_host,
)


def _empty_lesson(lid: str = "s1-l1") -> dict:
    return {
        "id": lid,
        "name": f"Empty {lid}",
        "template": "intro",
        "content": {"subLessons": []},
    }


def _adapter(lessons: list[dict] | None = None) -> SimpleNamespace:
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

        def invalidate_node_index(self) -> None:
            self._invalidated += 1

    return Adapter()


class StubGenerateTest(unittest.TestCase):
    def test_stub_forces_id_and_content(self) -> None:
        base = _empty_lesson("keep")
        stub = build_stub_lesson(base, lesson_id="keep")
        self.assertEqual(stub["id"], "keep")
        self.assertTrue(stub["content"]["subLessons"])
        self.assertTrue(is_lesson_payload_mergeable(stub))
        # force_id against hack
        hacked = force_lesson_id({"id": "X", "content": stub["content"]}, "keep")
        self.assertEqual(hacked["id"], "keep")

    def test_flag_only_not_mergeable(self) -> None:
        self.assertFalse(
            is_lesson_payload_mergeable({"id": "a", "sandbox_staged_fill": True})
        )

    def test_sandbox_stub_does_not_mutate_adapter(self) -> None:
        ad = _adapter()
        before = json.dumps(ad.sections, sort_keys=True)
        box = CourseSandbox.from_adapter(ad, lesson_ids=["s1-l1"])
        self.assertTrue(box.stage_stub_fill("s1-l1"))
        after = json.dumps(ad.sections, sort_keys=True)
        self.assertEqual(before, after)
        mp = box.to_merge_plan()
        self.assertTrue(is_lesson_payload_mergeable(mp.items[0].sandbox_payload))


class LessonPatchMergeTest(unittest.TestCase):
    def test_apply_sandbox_lessons_batch(self) -> None:
        ad = _adapter()
        box = CourseSandbox.from_adapter(ad)
        box.stage_stub_fill("s1-l1")
        box.stage_stub_fill("s1-l2")
        mp = box.to_merge_plan()

        # Fake undo stack that applies command immediately
        class Stack:
            def __init__(self) -> None:
                self.cmds: list[Any] = []

            def push(self, cmd: Any) -> None:
                self.cmds.append(cmd)
                cmd.redo()

        host = SimpleNamespace(
            adapter=ad,
            undo_stack=Stack(),
            tree=MagicMock(),
            _refresh_experience=MagicMock(),
        )
        n = apply_sandbox_lessons_to_host(host, mp)
        self.assertEqual(n, 2)
        # Live lessons now have content
        _s, _u, l1 = ad.find_lesson("s1-l1")
        self.assertTrue(l1["content"]["subLessons"])
        self.assertEqual(l1["id"], "s1-l1")
        # Undo restores empty
        host.undo_stack.cmds[0].undo()
        _s, _u, l1b = ad.find_lesson("s1-l1")
        self.assertEqual(l1b["content"].get("subLessons") or [], [])

    def test_merge_plan_patches_and_skills(self) -> None:
        ad = _adapter([_empty_lesson("only")])
        box = CourseSandbox.from_adapter(ad)
        box.stage_stub_fill("only")
        from src.backend.experience.planner import GoalStep

        box.mark_action(
            GoalStep(
                step_id="s9",
                action_id="validate.open_and_fix",
                label="修错",
                scope={"error_count": 1},
            )
        )
        mp = box.to_merge_plan()
        suggested: list[str] = []

        class Stack:
            def push(self, cmd: Any) -> None:
                cmd.redo()

        host = SimpleNamespace(
            adapter=ad,
            undo_stack=Stack(),
            tree=MagicMock(),
            _refresh_experience=MagicMock(),
            _on_experience_suggestion=lambda s: suggested.append(s["action_id"]),
        )
        n = apply_merge_plan_on_host(host, mp)
        self.assertGreaterEqual(n, 2)
        self.assertIn("validate.open_and_fix", suggested)
        _s, _u, les = ad.find_lesson("only")
        self.assertTrue(les["content"]["subLessons"])

    def test_plan_run_local_stub_path(self) -> None:
        ad = _adapter()
        ctx = SimpleNamespace(
            empty_lessons=["s1-l1"],
            validate_error_count=0,
            hygiene={},
            listening_gaps=[],
            imbalanced_lessons=[],
        )
        plan = plan_from_context(ctx, goal_text="空课")
        box = CourseSandbox.from_adapter(ad, lesson_ids=plan.lesson_ids)
        box.run_plan_local(plan)
        mp = box.to_merge_plan()
        self.assertTrue(
            any(is_lesson_payload_mergeable(i.sandbox_payload) for i in mp.items)
        )


if __name__ == "__main__":
    unittest.main()
