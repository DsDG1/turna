"""E3-A C-10 Goal planner pure tests."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path
from types import SimpleNamespace

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.experience.planner import (  # noqa: E402
    format_plan_summary,
    plan_from_context,
)
from src.backend.experience.intent_router import route_intent  # noqa: E402


class GoalPlannerTest(unittest.TestCase):
    def test_empty_context_notes(self) -> None:
        plan = plan_from_context(None, goal_text="")
        self.assertEqual(plan.source, "local")
        self.assertEqual(len(plan), 0)
        self.assertTrue(plan.notes)

    def test_fill_empty_from_context(self) -> None:
        ctx = SimpleNamespace(
            empty_lessons=["s1-l1", "s1-l2", "s1-l3"],
            validate_error_count=0,
            hygiene={},
            listening_gaps=[],
            imbalanced_lessons=[],
            quality_by_section={},
        )
        plan = plan_from_context(ctx, goal_text="填充空课", max_fill_lessons=2)
        fills = [s for s in plan.steps if s.action_id == "lesson.fill_empty"]
        self.assertEqual(len(fills), 2)
        self.assertEqual(fills[0].scope.get("lesson_id"), "s1-l1")
        self.assertTrue(any("未列入" in n for n in plan.notes))

    def test_validate_priority(self) -> None:
        ctx = SimpleNamespace(
            empty_lessons=["x"],
            validate_error_count=3,
            hygiene={"placeholder_count": 2},
            listening_gaps=[],
            imbalanced_lessons=[],
        )
        plan = plan_from_context(ctx, goal_text="")
        self.assertGreaterEqual(len(plan), 2)
        self.assertEqual(plan.steps[0].action_id, "validate.open_and_fix")

    def test_keyword_focus_stubs_only(self) -> None:
        ctx = SimpleNamespace(
            empty_lessons=["a"],
            validate_error_count=5,
            hygiene={"placeholder_count": 4},
            listening_gaps=[],
            imbalanced_lessons=[],
        )
        plan = plan_from_context(ctx, goal_text="清理待补词条")
        aids = {s.action_id for s in plan.steps}
        self.assertIn("resource.fill_stubs", aids)
        self.assertNotIn("lesson.fill_empty", aids)
        self.assertNotIn("validate.open_and_fix", aids)

    def test_depends_on_chain(self) -> None:
        ctx = SimpleNamespace(
            empty_lessons=["l1", "l2"],
            validate_error_count=0,
            hygiene={},
            listening_gaps=[],
            imbalanced_lessons=[],
        )
        plan = plan_from_context(ctx, goal_text="空课")
        fills = [s for s in plan.steps if s.action_id == "lesson.fill_empty"]
        self.assertEqual(fills[1].depends_on, (fills[0].step_id,))

    def test_format_summary(self) -> None:
        ctx = SimpleNamespace(
            empty_lessons=["l1"],
            validate_error_count=1,
            hygiene={},
            listening_gaps=[],
            imbalanced_lessons=[],
        )
        plan = plan_from_context(ctx, goal_text="修错并填空课")
        text = format_plan_summary(plan)
        self.assertIn("目标", text)
        self.assertIn("validate.open_and_fix", text)

    def test_slash_goal(self) -> None:
        i = route_intent("/goal")
        self.assertIsNotNone(i)
        assert i is not None
        self.assertEqual(i.action_id, "goal.plan")
        self.assertEqual(i.confidence, 1.0)
        i2 = route_intent("/goal-run")
        assert i2 is not None
        self.assertEqual(i2.action_id, "goal.run")


if __name__ == "__main__":
    unittest.main()
