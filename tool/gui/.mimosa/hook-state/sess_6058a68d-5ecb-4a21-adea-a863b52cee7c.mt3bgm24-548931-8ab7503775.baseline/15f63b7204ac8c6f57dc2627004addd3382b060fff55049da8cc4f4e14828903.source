"""E3-B1: filter_merge_plan, expand_goal_local, publish_brief, goal_llm parse."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path
from types import SimpleNamespace

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.experience.sandbox import (  # noqa: E402
    MergeItem,
    MergePlan,
    filter_merge_plan,
    merge_item_key,
)
from src.backend.experience.planner import expand_goal_local  # noqa: E402
from src.backend.experience.publish_brief import (  # noqa: E402
    build_publish_brief,
    format_publish_brief_html,
)
from src.backend.experience.goal_llm import (  # noqa: E402
    build_health_summary,
    expand_goal_with_llm,
    is_goal_llm_enabled,
    parse_expand_response,
)
import src.backend.experience.goal_llm as goal_llm_mod  # noqa: E402
from src.application.goal_controller import build_plan_for_host  # noqa: E402
from src.application.settings import Settings  # noqa: E402
from src.backend.experience.intent_router import route_intent  # noqa: E402


def _mp(*summaries: str) -> MergePlan:
    items = []
    for i, s in enumerate(summaries):
        items.append(
            MergeItem(
                kind="lesson" if i % 2 == 0 else "action",
                id=f"id{i}",
                summary=s,
                action_id="lesson.fill_empty" if i % 2 == 0 else "validate.open_and_fix",
                scope={"lesson_id": f"l{i}"} if i % 2 == 0 else {},
            )
        )
    return MergePlan(items=items, goal_text="t", summary="all")


class FilterMergePlanTest(unittest.TestCase):
    def test_filter_subset(self) -> None:
        mp = _mp("a", "b", "c")
        keys = [merge_item_key(mp.items[0]), merge_item_key(mp.items[2])]
        out = filter_merge_plan(mp, keys)
        self.assertEqual(len(out), 2)
        self.assertTrue(out.requires_confirm)
        self.assertIn("合并所选", out.summary)

    def test_filter_empty(self) -> None:
        mp = _mp("a", "b")
        out = filter_merge_plan(mp, [])
        self.assertEqual(len(out), 0)

    def test_filter_cap(self) -> None:
        mp = _mp(*[f"x{i}" for i in range(12)])
        keys = [merge_item_key(it) for it in mp.items]
        out = filter_merge_plan(mp, keys, max_items=3)
        self.assertEqual(len(out), 3)

    def test_filter_does_not_mutate(self) -> None:
        mp = _mp("a", "b")
        n = len(mp)
        filter_merge_plan(mp, [merge_item_key(mp.items[0])])
        self.assertEqual(len(mp), n)


class ExpandGoalLocalTest(unittest.TestCase):
    def test_all_empty_raises_cap(self) -> None:
        ctx = SimpleNamespace(
            empty_lessons=[f"l{i}" for i in range(15)],
            validate_error_count=0,
            hygiene={},
            listening_gaps=[],
            imbalanced_lessons=[],
        )
        plan = expand_goal_local(ctx, goal_text="全部空课")
        fills = [s for s in plan.steps if s.action_id == "lesson.fill_empty"]
        self.assertGreater(len(fills), 5)
        self.assertTrue(any("expand_goal_local" in n for n in plan.notes))

    def test_broad_health(self) -> None:
        ctx = SimpleNamespace(
            empty_lessons=["e1"],
            validate_error_count=2,
            hygiene={"placeholder_count": 1},
            listening_gaps=[],
            imbalanced_lessons=[],
        )
        plan = expand_goal_local(ctx, goal_text="发布前改善")
        aids = {s.action_id for s in plan.steps}
        self.assertIn("validate.open_and_fix", aids)


class PublishBriefTest(unittest.TestCase):
    def test_blocks_on_errors(self) -> None:
        ctx = SimpleNamespace(
            validate_error_count=3,
            validate_warning_count=1,
            empty_lesson_count=2,
            lesson_count=10,
            section_count=2,
            hygiene={"placeholder_count": 4},
        )
        b = build_publish_brief(ctx)
        self.assertTrue(b["blocks_publish"])
        self.assertEqual(b["error_count"], 3)
        html = format_publish_brief_html(b)
        self.assertIn("Brief", html)

    def test_no_block_when_clean(self) -> None:
        ctx = SimpleNamespace(
            validate_error_count=0,
            validate_warning_count=0,
            empty_lesson_count=0,
            lesson_count=5,
            section_count=1,
            hygiene={},
        )
        b = build_publish_brief(ctx)
        self.assertFalse(b["blocks_publish"])


class GoalLlmParseTest(unittest.TestCase):
    def test_parse_ok(self) -> None:
        raw = '{"actions":["lesson.fill_empty","validate.open_and_fix"],"confidence":0.9}'
        acts = parse_expand_response(raw)
        self.assertEqual(acts, ["lesson.fill_empty", "validate.open_and_fix"])

    def test_parse_low_confidence(self) -> None:
        raw = '{"actions":["lesson.fill_empty"],"confidence":0.1}'
        self.assertIsNone(parse_expand_response(raw))

    def test_llm_default_off(self) -> None:
        self.assertFalse(is_goal_llm_enabled(Settings()))
        self.assertFalse(
            is_goal_llm_enabled(
                Settings(experience_goal_enabled=True, experience_goal_llm=False)
            )
        )

    def test_routes(self) -> None:
        self.assertEqual(route_intent("/goal-expand").action_id, "goal.expand")
        self.assertEqual(route_intent("/publish").action_id, "publish.brief")


def _llm_settings() -> Settings:
    return Settings(experience_goal_enabled=True, experience_goal_llm=True)


def _ctx(**over: object) -> SimpleNamespace:
    base: dict = {
        "empty_lessons": [],
        "validate_error_count": 0,
        "validate_warning_count": 0,
        "hygiene": {},
        "listening_gaps": [],
        "imbalanced_lessons": [],
    }
    base.update(over)
    return SimpleNamespace(**base)


class GoalLlmExpandTest(unittest.TestCase):
    """K-09: goal_llm wired to a real chat_fn (default off, fallback local)."""

    def test_llm_plan_from_valid_json(self) -> None:
        ctx = _ctx(empty_lessons=["e1", "e2"])
        plan = expand_goal_with_llm(
            ctx,
            "填充空课",
            settings=_llm_settings(),
            chat_fn=lambda _p: '{"actions":["lesson.fill_empty"],"confidence":0.9}',
        )
        self.assertEqual(plan.source, "llm")
        aids = {s.action_id for s in plan.steps}
        self.assertIn("lesson.fill_empty", aids)

    def test_garbage_and_exception_fall_back_local(self) -> None:
        ctx = _ctx(empty_lessons=["e1"])
        plan = expand_goal_with_llm(
            ctx, "填空课", settings=_llm_settings(), chat_fn=lambda _p: "not json at all"
        )
        self.assertEqual(plan.source, "local")

        def _boom(_p: str) -> str:
            raise RuntimeError("network down")

        plan2 = expand_goal_with_llm(
            ctx, "填空课", settings=_llm_settings(), chat_fn=_boom
        )
        self.assertEqual(plan2.source, "local")

    def test_controller_switch_off_builds_no_chat_fn(self) -> None:
        ctx = _ctx(empty_lessons=["e1"])
        host = SimpleNamespace(
            experience=SimpleNamespace(context=ctx),
            _settings_obj=Settings(
                experience_goal_enabled=True, experience_goal_llm=False
            ),
            _ai_config=SimpleNamespace(is_complete=True),
        )
        called: list = []
        orig = goal_llm_mod.expand_goal_with_llm
        goal_llm_mod.expand_goal_with_llm = lambda *a, **k: called.append((a, k))  # type: ignore[assignment]
        try:
            plan = build_plan_for_host(host, "填空课", expand=True)
        finally:
            goal_llm_mod.expand_goal_with_llm = orig  # type: ignore[assignment]
        self.assertEqual(called, [])
        self.assertEqual(plan.source, "local")

    def test_controller_switch_on_passes_chat_fn(self) -> None:
        ctx = _ctx(empty_lessons=["e1"])
        host = SimpleNamespace(
            experience=SimpleNamespace(context=ctx),
            _settings_obj=_llm_settings(),
            _ai_config=SimpleNamespace(is_complete=True),
        )
        seen: dict = {}
        orig = goal_llm_mod.expand_goal_with_llm

        def _spy(c: object, text: str, *, settings: object = None, chat_fn: object = None) -> object:
            seen["chat_fn"] = chat_fn
            return orig(c, text, settings=settings, chat_fn=chat_fn)

        goal_llm_mod.expand_goal_with_llm = _spy  # type: ignore[assignment]
        try:
            plan = build_plan_for_host(host, "填空课", expand=True)
        finally:
            goal_llm_mod.expand_goal_with_llm = orig  # type: ignore[assignment]
        self.assertTrue(callable(seen.get("chat_fn")))
        # Fake config cannot really chat → chat_fn returns None → local fallback.
        self.assertEqual(plan.source, "local")

    def test_prompt_includes_health_counts(self) -> None:
        ctx = _ctx(
            empty_lessons=["a", "b"],
            validate_error_count=3,
            validate_warning_count=1,
            hygiene={"placeholder_count": 4},
            listening_gaps=["g1"],
            imbalanced_lessons=["i1", "i2", "i3"],
        )
        summary = build_health_summary(ctx)
        self.assertIn("errors=3", summary)
        self.assertIn("empty_lessons=2", summary)
        self.assertIn("placeholders=4", summary)
        self.assertIn("listening_gaps=1", summary)
        self.assertIn("imbalanced=3", summary)

        captured: list[str] = []

        def _chat(prompt: str) -> str:
            captured.append(prompt)
            return '{"actions":["lesson.fill_empty"],"confidence":0.9}'

        expand_goal_with_llm(ctx, "改善", settings=_llm_settings(), chat_fn=_chat)
        self.assertEqual(len(captured), 1)
        self.assertIn("errors=3", captured[0])
        self.assertIn("empty_lessons=2", captured[0])


if __name__ == "__main__":
    unittest.main()
