"""K-02 why expansion — content_quality dimension explanations (v4.17).

``why_explain`` must cover the 6 content_quality dimensions carried by
``ContentQualityReport.to_problem_dicts()`` (dimension-tagged problem dicts),
in addition to the existing structural validate rules. Dimension rules are
checked after structural rules and before the generic fallback.
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))


from src.backend.experience.why import why_explain, why_explain_many  # noqa: E402


class WhyDimensionTests(unittest.TestCase):
    def _dim_problem(self, dim, *, message="", level="error"):
        return {
            "level": level,
            "path": f"quality.{dim}",
            "message": f"[{dim}] {message or 'content quality issue'}",
            "dimension": dim,
        }

    def test_each_dimension_hits_its_rule(self):
        expected = {
            "coverage": "quality_coverage",
            "balance": "quality_balance",
            "distractor": "quality_distractor",
            "level_fit": "quality_level_fit",
            "audio_ready": "quality_audio_ready",
            "resource_hygiene": "quality_resource_hygiene",
        }
        for dim, rule_id in expected.items():
            r = why_explain(self._dim_problem(dim))
            self.assertEqual(r.rule_id, rule_id, dim)
            self.assertTrue(r.summary)

    def test_dimension_action_ids_reuse_existing_skills(self):
        actions = {
            "balance": "lesson.balance",
            "distractor": "item.distractor_boost",
            "level_fit": "validate.open_and_fix",
            "audio_ready": "listening.fill_gaps",
            "resource_hygiene": "resource.open_hygiene",
        }
        for dim, aid in actions.items():
            r = why_explain(self._dim_problem(dim))
            self.assertEqual(r.action_id, aid, dim)
        # coverage is advisory-only -> no action
        self.assertIsNone(why_explain(self._dim_problem("coverage")).action_id)

    def test_structural_problem_still_works(self):
        r = why_explain({"level": "error", "message": "dangling wordId w-x", "path": ""})
        self.assertEqual(r.rule_id, "dangling_word")

    def test_dimension_beats_fallback(self):
        # A dimension-tagged issue with an unfamiliar message must NOT fall to
        # the generic fallback rule.
        r = why_explain(self._dim_problem("distractor", message="something unusual"))
        self.assertEqual(r.rule_id, "quality_distractor")
        self.assertNotEqual(r.rule_id, "fallback")

    def test_unknown_dimension_falls_back(self):
        r = why_explain(self._dim_problem("no_such_dimension"))
        self.assertEqual(r.rule_id, "fallback")

    def test_to_problem_dicts_output_is_explainable(self):
        # The bridge output of ContentQualityReport.to_problem_dicts() must be
        # directly explainable. Construct a minimal report-like object.
        from src.backend.content_quality import ContentQualityIssue, ContentQualityReport

        issues = [
            ContentQualityIssue(
                level="error",
                dimension="distractor",
                message="duplicate options",
                path="section:section1/lesson:l-1",
                lesson_id="l-1",
                item_id="q1",
            ),
            ContentQualityIssue(
                level="warning",
                dimension="balance",
                message="single runtimeType >= 70%",
                path="section:section1/lesson:l-2",
                lesson_id="l-2",
                item_id="",
            ),
        ]
        report = ContentQualityReport(
            scores={"distractor": 0.4, "balance": 0.5},
            issues=issues,
            hygiene={},
        )
        dicts = report.to_problem_dicts()
        self.assertTrue(dicts)
        r0 = why_explain(dicts[0])
        r1 = why_explain(dicts[1])
        self.assertEqual(r0.rule_id, "quality_distractor")
        self.assertEqual(r1.rule_id, "quality_balance")

    def test_why_explain_many_mixed(self):
        problems = [
            {"level": "error", "message": "dangling wordId w-x", "path": ""},
            self._dim_problem("audio_ready"),
        ]
        out = why_explain_many(problems)
        self.assertEqual(len(out), 2)
        self.assertEqual(out[0].rule_id, "dangling_word")
        self.assertEqual(out[1].rule_id, "quality_audio_ready")


if __name__ == "__main__":
    unittest.main()