"""E3-A C-11 / Q-06 Goal sandbox isolation tests."""
from __future__ import annotations

import copy
import json
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.experience.planner import plan_from_context  # noqa: E402
from src.backend.experience.sandbox import (  # noqa: E402
    CourseSandbox,
    adapter_lesson_fingerprint,
)
from src.backend.experience.policy import (  # noqa: E402
    can_dispatch,
    resolve_policy,
)
from src.backend.experience.actions import get_action  # noqa: E402
from src.application.settings import Settings  # noqa: E402


def _adapter_with_lesson(lid: str = "s1-l1", *, empty: bool = True):
    content = {"subLessons": []} if empty else {
        "subLessons": [
            {
                "id": f"{lid}-sub",
                "stages": [
                    {
                        "id": f"{lid}-st",
                        "items": [
                            {
                                "id": f"{lid}-i1",
                                "runtimeType": "showWord",
                                "wordId": "w1",
                            }
                        ],
                    }
                ],
            }
        ]
    }
    lesson = {"id": lid, "name": "L", "template": "intro", "content": content}
    section = {
        "id": "section1",
        "name": "S1",
        "units": [{"id": "u1", "name": "U", "lessons": [lesson]}],
    }
    return SimpleNamespace(sections=[section], course_dir=None)


class SandboxIsolationTest(unittest.TestCase):
    def test_sandbox_does_not_mutate_adapter(self) -> None:
        adapter = _adapter_with_lesson("s1-l1")
        before = json.dumps(adapter.sections, sort_keys=True, ensure_ascii=False)
        fp = adapter_lesson_fingerprint(adapter, "s1-l1")
        box = CourseSandbox.from_adapter(adapter, lesson_ids=["s1-l1"])
        self.assertEqual(len(box), 1)
        ok = box.stage_placeholder_fill("s1-l1")
        self.assertTrue(ok)
        after = json.dumps(adapter.sections, sort_keys=True, ensure_ascii=False)
        self.assertEqual(before, after)
        self.assertEqual(fp, adapter_lesson_fingerprint(adapter, "s1-l1"))
        # Sandbox copy has meta flag; live lesson does not.
        live = adapter.sections[0]["units"][0]["lessons"][0]
        self.assertNotIn("sandbox_staged_fill", (live.get("meta") or {}))

    def test_apply_lesson_forces_id(self) -> None:
        adapter = _adapter_with_lesson("keep-me")
        box = CourseSandbox.from_adapter(adapter)
        ok = box.apply_lesson_dict(
            "keep-me",
            {"id": "HACKED", "name": "x", "content": {"subLessons": []}},
        )
        self.assertTrue(ok)
        les = box.get_lesson("keep-me")
        assert les is not None
        self.assertEqual(les["id"], "keep-me")

    def test_run_plan_local_merge_requires_confirm(self) -> None:
        adapter = _adapter_with_lesson("e1")
        ctx = SimpleNamespace(
            empty_lessons=["e1"],
            validate_error_count=0,
            hygiene={"placeholder_count": 1},
            listening_gaps=[],
            imbalanced_lessons=[],
        )
        plan = plan_from_context(ctx, goal_text="空课和待补")
        box = CourseSandbox.from_adapter(adapter, lesson_ids=plan.lesson_ids or None)
        box.run_plan_local(plan)
        mp = box.to_merge_plan()
        self.assertTrue(mp.requires_confirm)
        self.assertGreater(len(mp), 0)
        self.assertTrue(all(i.id for i in mp.items))

    def test_policy_goal_default_off(self) -> None:
        pol = resolve_policy(Settings())
        self.assertFalse(pol.allow_goal)
        self.assertFalse(pol.allow_autonomous_write)
        spec = get_action("goal.plan")
        assert spec is not None
        ok, reason = can_dispatch(spec, pol)
        self.assertFalse(ok)
        self.assertIn("Goal", reason)

    def test_policy_goal_on_copilot(self) -> None:
        pol = resolve_policy(Settings(experience_goal_enabled=True))
        self.assertTrue(pol.allow_goal)
        ok, _ = can_dispatch(get_action("goal.plan"), pol)
        self.assertTrue(ok)
        ok2, _ = can_dispatch(get_action("goal.run"), pol)
        self.assertTrue(ok2)

    def test_policy_goal_observer_zero(self) -> None:
        pol = resolve_policy(
            Settings(experience_goal_enabled=True, experience_mode="observer")
        )
        self.assertFalse(pol.allow_goal)
        ok, _ = can_dispatch(get_action("goal.run"), pol)
        self.assertFalse(ok)

    def test_deep_copy_independence(self) -> None:
        adapter = _adapter_with_lesson("z")
        box = CourseSandbox.from_adapter(adapter)
        les = box.get_lesson("z")
        assert les is not None
        les["name"] = "mutated"
        # get returns copy; internal still original name until apply
        self.assertEqual(box.get_lesson("z")["name"], "L")


if __name__ == "__main__":
    unittest.main()
