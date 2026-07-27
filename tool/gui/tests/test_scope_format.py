"""S-04 / S-12 pure helpers: scope target + yellow quality hints."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path
from types import SimpleNamespace

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.experience.scope_format import (  # noqa: E402
    format_scope_target,
    has_yellow_quality_hints,
    infer_scope_node_key,
    yellow_quality_summary,
)
from src.backend.experience.context_bus import NodeRef  # noqa: E402


class InferScopeNodeKeyTest(unittest.TestCase):
    def test_prefers_item_over_lesson(self) -> None:
        key = infer_scope_node_key(
            {"item_id": "q1", "lesson_id": "l1", "section_id": "s1"}
        )
        self.assertEqual(key, "item:q1")

    def test_first_lesson_id(self) -> None:
        self.assertEqual(
            infer_scope_node_key({"first_lesson_id": "s1-l2"}),
            "lesson:s1-l2",
        )

    def test_selection_tuple_fallback(self) -> None:
        self.assertEqual(
            infer_scope_node_key({}, selection=("unit", "u9")),
            "unit:u9",
        )

    def test_selection_noderef(self) -> None:
        self.assertEqual(
            infer_scope_node_key({}, selection=NodeRef("lesson", "lx", "Hi")),
            "lesson:lx",
        )

    def test_empty(self) -> None:
        self.assertIsNone(infer_scope_node_key(None))
        self.assertIsNone(infer_scope_node_key({}))


class FormatScopeTargetTest(unittest.TestCase):
    def test_section_with_quality_extra(self) -> None:
        text = format_scope_target(
            "quality.campaign_worst_n",
            {"section_id": "section2", "mean": 0.42},
        )
        self.assertIn("section2", text)
        self.assertIn("0.42", text)

    def test_listening_gaps(self) -> None:
        text = format_scope_target(
            "listening.fill_gaps",
            {"section_id": "s1", "gap_count": 3},
        )
        self.assertIn("s1", text)
        self.assertIn("3", text)

    def test_resource_stubs_counts(self) -> None:
        text = format_scope_target(
            "resource.fill_stubs",
            {"placeholder_count": 4, "needs_review_count": 1},
        )
        self.assertIn("待补", text)
        self.assertIn("4", text)

    def test_selection_fallback(self) -> None:
        text = format_scope_target(
            "lesson.fill_empty",
            {},
            selection=("lesson", "l3"),
        )
        self.assertEqual(text, "lesson l3")

    def test_default_fallback(self) -> None:
        self.assertEqual(format_scope_target("x", {}), "当前课程")


class YellowQualityHintsTest(unittest.TestCase):
    def test_none_and_healthy(self) -> None:
        self.assertFalse(has_yellow_quality_hints(None))
        ctx = SimpleNamespace(
            validate_warning_count=0,
            empty_lesson_count=0,
            hygiene={},
            quality_by_section={"s1": 0.95},
        )
        self.assertFalse(has_yellow_quality_hints(ctx))
        self.assertEqual(yellow_quality_summary(ctx)["message"], "")

    def test_empty_and_weak_and_warning(self) -> None:
        ctx = SimpleNamespace(
            validate_warning_count=2,
            empty_lesson_count=3,
            hygiene={"placeholder_count": 1, "needs_review_count": 0},
            quality_by_section={"s1": 0.5, "s2": 0.9},
        )
        summary = yellow_quality_summary(ctx)
        self.assertTrue(summary["has_hints"])
        self.assertEqual(summary["warning_count"], 2)
        self.assertEqual(summary["empty_lesson_count"], 3)
        self.assertEqual(summary["weak_section_count"], 1)
        self.assertEqual(summary["placeholder_count"], 1)
        self.assertIn("已保存", summary["message"])
        self.assertIn("空课", summary["message"])
        self.assertIn("低质节", summary["message"])

    def test_dict_ctx(self) -> None:
        summary = yellow_quality_summary(
            {
                "validate_warning_count": 0,
                "empty_lesson_count": 1,
                "hygiene": {},
                "quality_by_section": {},
            }
        )
        self.assertTrue(summary["has_hints"])
        self.assertIn("空课 1", summary["message"])

    def test_never_raises(self) -> None:
        self.assertFalse(has_yellow_quality_hints(object()))
        self.assertEqual(yellow_quality_summary(object())["has_hints"], False)


if __name__ == "__main__":
    unittest.main()
