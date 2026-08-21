"""E1.7 O-06 / K-02: local why_explain rules."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.experience.why import why_explain, why_explain_many  # noqa: E402


class WhyExplainTest(unittest.TestCase):
    def test_eight_rule_families(self) -> None:
        cases = [
            ({"level": "error", "message": "dangling wordId w-x", "path": ""}, "dangling_word"),
            (
                {"level": "error", "message": "missing expressionId e-1", "path": ""},
                "dangling_expression",
            ),
            ({"level": "error", "message": "duplicate id lesson-1", "path": ""}, "duplicate_id"),
            ({"level": "error", "message": "empty prompt on item", "path": ""}, "empty_prompt"),
            (
                {"level": "error", "message": "duplicate options in MCQ", "path": ""},
                "duplicate_options",
            ),
            (
                {"level": "error", "message": "listening phase missing transcript", "path": ""},
                "missing_transcript",
            ),
            ({"level": "error", "message": "empty lesson has no items", "path": ""}, "empty_lesson"),
            (
                {"level": "error", "message": "unknown runtimeType FooBar", "path": ""},
                "unknown_runtime",
            ),
            ({"level": "warning", "message": "needs-review placeholder [待补]", "path": ""}, "placeholder"),
        ]
        for problem, rule_id in cases:
            result = why_explain(problem)
            self.assertEqual(result.rule_id, rule_id, problem)
            self.assertTrue(result.summary)
            self.assertTrue(result.detail)

    def test_fallback_never_empty(self) -> None:
        r = why_explain({"level": "error", "message": "weird xyz", "path": "a/b"})
        self.assertEqual(r.rule_id, "fallback")
        self.assertIn("weird xyz", r.detail)

    def test_invalid_input(self) -> None:
        r = why_explain(None)
        self.assertEqual(r.rule_id, "invalid")

    def test_does_not_mutate_problem(self) -> None:
        p = {"level": "error", "message": "dangling wordId", "path": "x"}
        snap = dict(p)
        why_explain(p)
        self.assertEqual(p, snap)

    def test_why_explain_many(self) -> None:
        results = why_explain_many(
            [
                {"message": "dangling wordId"},
                {"message": "empty prompt"},
            ]
        )
        self.assertEqual(len(results), 2)

    def test_audio_ready_routes_to_listening_fill(self) -> None:
        # E2.1: content_quality audio_ready issues route to listening.fill_gaps,
        # not validate.open_and_fix.
        r = why_explain(
            {"level": "warning", "message": "听力题缺少 audioAsset / transcript", "path": "x"}
        )
        self.assertEqual(r.rule_id, "missing_transcript")
        self.assertEqual(r.action_id, "listening.fill_gaps")
        self.assertNotIn("已通过", r.detail)


if __name__ == "__main__":
    unittest.main()
