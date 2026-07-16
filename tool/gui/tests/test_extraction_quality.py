"""Tests for src.backend.extraction_quality."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.extraction_quality import (
    QualityIssue,
    compute_quality_report,
)
from src.backend.knowledge_schema import KnowledgePoints
from src.backend.markdown_chopper import Chapter


def _chapter(idx: int, title: str, markdown: str) -> Chapter:
    return Chapter(idx=idx, level=2, title=title, slug=f"ch{idx}", markdown=markdown)


def _kp(**kwargs) -> KnowledgePoints:
    return KnowledgePoints(
        words=kwargs.get("words", []),
        expressions=kwargs.get("expressions", []),
        grammarPoints=kwargs.get("grammarPoints", []),
    )


class FakeAdapter:
    """Minimal adapter stub for duplicate/collision tests."""

    def __init__(self, vocab=None, expressions=None, grammar_points=None):
        self.vocab = vocab or []
        self.expressions = expressions or []
        self.grammar_points = grammar_points or []


class ExtractionQualityTest(unittest.TestCase):
    def test_empty_knowledge_marks_coverage_error(self) -> None:
        ch = _chapter(1, "Hello", "some text here")
        kp = _kp()
        report = compute_quality_report([(ch, kp)])
        self.assertEqual(report.badge_for_chapter(0), "error")
        issues = report.chapter_quality(0).issues
        self.assertTrue(any(i.kind == "coverage" for i in issues))

    def test_coverage_score_increases_with_more_resources(self) -> None:
        ch = _chapter(1, "Short", "a " * 500)  # ~1000 chars -> expected ~5 resources
        many = _kp(words=[{"term": f"w{i}", "translation": f"t{i}"} for i in range(10)])
        report_many = compute_quality_report([(ch, many)])
        self.assertGreater(report_many.chapter_quality(0).scores["coverage"], 0.5)

        few = _kp(words=[{"term": "w", "translation": "t"}])
        report_few = compute_quality_report([(ch, few)])
        self.assertLess(report_few.chapter_quality(0).scores["coverage"], 0.5)

    def test_duplicate_within_project(self) -> None:
        ch1 = _chapter(1, "A", "text")
        ch2 = _chapter(2, "B", "text")
        entry = {"term": "merhaba", "translation": "hello"}
        kp = _kp(words=[entry])
        report = compute_quality_report([(ch1, kp), (ch2, kp)])
        dup_issues = [
            i
            for i in report.chapters[0].issues + report.chapters[1].issues
            if i.kind == "duplicate"
        ]
        self.assertEqual(len(dup_issues), 1)
        self.assertEqual(dup_issues[0].level, "warning")

    def test_duplicate_against_existing_course(self) -> None:
        ch = _chapter(1, "A", "text")
        kp = _kp(words=[{"term": "merhaba", "translation": "hello"}])
        adapter = FakeAdapter(vocab=[{"term": "merhaba", "translation": "hello"}])
        report = compute_quality_report([(ch, kp)], adapter=adapter)
        issues = [i for i in report.chapters[0].issues if i.kind == "duplicate"]
        self.assertEqual(len(issues), 1)
        self.assertIn("现有课程", issues[0].message)

    def test_consistency_bad_example_expression_id(self) -> None:
        ch = _chapter(1, "A", "text")
        kp = _kp(
            expressions=[{"id": "expr-1", "term": "selam", "translation": "hi"}],
            grammarPoints=[
                {
                    "id": "gp-1",
                    "title": "Greeting",
                    "explanation": "...",
                    "exampleExpressionIds": ["missing-id"],
                }
            ],
        )
        report = compute_quality_report([(ch, kp)])
        issues = [i for i in report.chapters[0].issues if i.kind == "consistency"]
        self.assertEqual(len(issues), 1)
        self.assertIn("missing-id", issues[0].message)

    def test_consistency_ok_when_id_exists(self) -> None:
        ch = _chapter(1, "A", "text")
        kp = _kp(
            expressions=[{"id": "expr-1", "term": "selam", "translation": "hi"}],
            grammarPoints=[
                {
                    "id": "gp-1",
                    "title": "Greeting",
                    "explanation": "...",
                    "exampleExpressionIds": ["expr-1"],
                }
            ],
        )
        report = compute_quality_report([(ch, kp)])
        issues = [i for i in report.chapters[0].issues if i.kind == "consistency"]
        self.assertEqual(len(issues), 0)
        self.assertEqual(report.chapters[0].scores["consistency"], 1.0)

    def test_lang_check_empty_translation_warning(self) -> None:
        ch = _chapter(1, "A", "text")
        kp = _kp(words=[{"term": "merhaba", "translation": ""}])
        report = compute_quality_report([(ch, kp)])
        issues = [i for i in report.chapters[0].issues if i.kind == "lang_check"]
        self.assertEqual(len(issues), 1)
        self.assertEqual(issues[0].field, "translation")

    def test_lang_check_cjk_in_term_when_target_not_cjk(self) -> None:
        ch = _chapter(1, "A", "text")
        kp = _kp(words=[{"term": "你好", "translation": "hello"}])
        report = compute_quality_report(
            [(ch, kp)], language="Turkish", source_language="Chinese"
        )
        issues = [i for i in report.chapters[0].issues if i.kind == "lang_check"]
        self.assertTrue(any("混入" in i.message for i in issues))

    def test_overall_aggregates_scores(self) -> None:
        ch = _chapter(1, "A", "text " * 500)
        kp = _kp(words=[{"term": "w", "translation": "t"}])
        report = compute_quality_report([(ch, kp)])
        overall = report.overall
        self.assertIn("coverage", overall)
        self.assertIn("duplicate_rate", overall)
        self.assertIn("consistency", overall)
        self.assertIn("lang_check", overall)
        self.assertEqual(overall["error_count"] + overall["warning_count"], overall["issue_count"])


if __name__ == "__main__":
    unittest.main()
