"""Tests for the pure-function overview stats module (no Qt required)."""
from __future__ import annotations

import sys
import unittest
from collections import Counter
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.overview_stats import (  # noqa: E402
    OverviewStats,
    SectionStats,
    compute_overview_stats,
    export_markdown,
    filter_lessons,
    format_interaction_line,
    format_stats_line,
    iter_lesson_interactions,
    iter_lesson_refs,
    lesson_is_empty,
)


def _item(runtime_type: str, **refs) -> dict:
    d = {"runtimeType": runtime_type, "id": "x"}
    d.update(refs)
    return d


def _adapter(
    *,
    sections=None,
    vocab=None,
    expressions=None,
    grammar_points=None,
):
    """Minimal adapter stub with the attributes compute_overview_stats reads."""

    class _A:
        def __init__(self):
            self.sections = sections or []
            self.vocab = vocab or []
            self.expressions = expressions or []
            self.grammar_points = grammar_points or []
            self.course_dir = None

    return _A()


class IterInteractionsTest(unittest.TestCase):
    def test_sublessons_stages_items(self) -> None:
        lesson = {
            "template": "intro",
            "content": {
                "subLessons": [
                    {"stages": [{"items": [_item("showWord"), _item("fillBlank")]}]},
                    {"stages": [{"items": [_item("multipleChoice")]}]},
                ]
            },
        }
        rts = [i["runtimeType"] for i in iter_lesson_interactions(lesson)]
        self.assertEqual(rts, ["showWord", "fillBlank", "multipleChoice"])

    def test_top_level_stages(self) -> None:
        lesson = {
            "template": "mastery",
            "content": {"stages": [{"items": [_item("translateSentence")]}]},
        }
        rts = [i["runtimeType"] for i in iter_lesson_interactions(lesson)]
        self.assertEqual(rts, ["translateSentence"])

    def test_listening_phases(self) -> None:
        lesson = {
            "template": "listening",
            "content": {
                "listeningPhases": [
                    {"items": [_item("listenAndPick"), _item("typeTheWord")]},
                    {"items": []},
                ]
            },
        }
        rts = [i["runtimeType"] for i in iter_lesson_interactions(lesson)]
        self.assertEqual(rts, ["listenAndPick", "typeTheWord"])

    def test_empty_lesson_yields_nothing(self) -> None:
        self.assertEqual(list(iter_lesson_interactions({})), [])
        self.assertEqual(list(iter_lesson_interactions({"content": {}})), [])


class IterRefsTest(unittest.TestCase):
    def test_collects_word_expression_grammar_refs(self) -> None:
        lesson = {
            "content": {
                "stages": [
                    {
                        "items": [
                            _item("showWord", wordId="w1"),
                            _item("multipleChoice", grammarPointId="g1"),
                            _item("translateSentence", expressionId="e1"),
                            _item("fillBlank"),  # no refs
                        ]
                    }
                ],
                "readingPassage": {
                    "linkedWordIds": ["w2", "w3"],
                    "linkedExpressionIds": ["e2"],
                },
            }
        }
        refs = sorted(iter_lesson_refs(lesson))
        self.assertEqual(
            refs,
            [
                ("expression", "e1"),
                ("expression", "e2"),
                ("grammar", "g1"),
                ("word", "w1"),
                ("word", "w2"),
                ("word", "w3"),
            ],
        )


class LessonIsEmptyTest(unittest.TestCase):
    def test_empty_subLessons(self) -> None:
        self.assertTrue(lesson_is_empty({"template": "intro", "content": {"subLessons": []}}))

    def test_populated_subLessons(self) -> None:
        self.assertFalse(
            lesson_is_empty(
                {"template": "intro", "content": {"subLessons": [{"stages": []}]}}
            )
        )

    def test_missing_content(self) -> None:
        self.assertTrue(lesson_is_empty({"template": "mastery"}))

    def test_reading_with_paragraphs(self) -> None:
        lesson = {
            "template": "reading",
            "content": {
                "readingPassage": {"paragraphs": ["a"], "linkedWordIds": []},
                "stages": [],
            },
        }
        self.assertFalse(lesson_is_empty(lesson))

    def test_reading_empty_passage(self) -> None:
        lesson = {
            "template": "reading",
            "content": {
                "readingPassage": {"paragraphs": [], "linkedWordIds": []},
                "stages": [],
            },
        }
        self.assertTrue(lesson_is_empty(lesson))


class ComputeStatsTest(unittest.TestCase):
    def _sample_adapter(self) -> object:
        sections = [
            {
                "id": "s1",
                "name": "Section 1",
                "level": "A1",
                "units": [
                    {
                        "id": "s1-u1",
                        "name": "Unit 1",
                        "lessons": [
                            {
                                "id": "l1",
                                "name": "Greetings",
                                "template": "intro",
                                "content": {
                                    "subLessons": [
                                        {
                                            "stages": [
                                                {"items": [
                                                    _item("showWord", wordId="w1"),
                                                    _item("multipleChoice", wordId="w1"),
                                                ]}
                                            ]
                                        }
                                    ]
                                },
                            },
                            {
                                "id": "l2",
                                "name": "Empty practice",
                                "template": "practice",
                                "content": {"subLessons": []},
                            },
                        ],
                    }
                ],
            }
        ]
        return _adapter(
            sections=sections,
            vocab=[{"id": "w1"}, {"id": "w2"}, {"id": "w3"}],
            expressions=[{"id": "e1"}],
            grammar_points=[{"id": "g1"}, {"id": "g2"}],
        )

    def test_structural_counts(self) -> None:
        stats = compute_overview_stats(self._sample_adapter(), include_validation=False)
        self.assertEqual(stats.section_count, 1)
        self.assertEqual(stats.unit_count, 1)
        self.assertEqual(stats.lesson_count, 2)
        self.assertEqual(stats.empty_lesson_count, 1)
        self.assertEqual(stats.template_counts["intro"], 1)
        self.assertEqual(stats.template_counts["practice"], 1)

    def test_interaction_counts(self) -> None:
        stats = compute_overview_stats(self._sample_adapter(), include_validation=False)
        self.assertEqual(stats.interaction_counts["showWord"], 1)
        self.assertEqual(stats.interaction_counts["multipleChoice"], 1)

    def test_coverage_ratios(self) -> None:
        stats = compute_overview_stats(self._sample_adapter(), include_validation=False)
        # w1 referenced; w2/w3 not.
        self.assertEqual(stats.vocab_referenced, 1)
        self.assertEqual(stats.vocab_total, 3)
        self.assertAlmostEqual(stats.vocab_coverage_pct, 100.0 / 3.0, places=1)
        self.assertEqual(stats.expression_referenced, 0)
        self.assertEqual(stats.grammar_referenced, 0)
        self.assertEqual(stats.expression_coverage_pct, 0.0)

    def test_section_stats(self) -> None:
        stats = compute_overview_stats(self._sample_adapter(), include_validation=False)
        self.assertEqual(len(stats.sections), 1)
        s = stats.sections[0]
        self.assertEqual(s.section_id, "s1")
        self.assertEqual(s.lesson_count, 2)
        self.assertEqual(s.empty_lesson_count, 1)
        self.assertEqual(s.interaction_counts["showWord"], 1)

    def test_no_validation_when_dir_none(self) -> None:
        stats = compute_overview_stats(self._sample_adapter(), include_validation=True)
        self.assertEqual(stats.validation_errors, 0)
        self.assertEqual(stats.validation_warnings, 0)


class FormatStatsLineTest(unittest.TestCase):
    def test_includes_coverage_and_empty(self) -> None:
        stats = OverviewStats(
            section_count=2,
            unit_count=3,
            lesson_count=8,
            empty_lesson_count=2,
            vocab_total=10,
            vocab_referenced=5,
            expression_total=4,
            expression_referenced=4,
            grammar_total=6,
            grammar_referenced=0,
        )
        text = format_stats_line(stats)
        self.assertIn("Sections: 2", text)
        self.assertIn("空课时: 2", text)
        self.assertIn("词汇: 5/10", text)
        self.assertIn("表达: 4/4", text)
        self.assertIn("语法: 0/6", text)
        self.assertIn("(50%)", text)
        self.assertIn("(100%)", text)
        self.assertIn("(0%)", text)

    def test_omits_empty_line_when_no_templates(self) -> None:
        stats = OverviewStats(section_count=0, unit_count=0, lesson_count=0)
        text = format_stats_line(stats)
        self.assertNotIn("课型分布", text)


class FormatInteractionLineTest(unittest.TestCase):
    def test_renders_labels(self) -> None:
        line = format_interaction_line(
            Counter(["multipleChoice", "multipleChoice", "fillBlank"])
        )
        self.assertIn("选择题 2", line)
        self.assertIn("填空题 1", line)

    def test_empty_returns_empty(self) -> None:
        self.assertEqual(format_interaction_line(Counter()), "")


class FilterLessonsTest(unittest.TestCase):
    def _sections(self):
        return [
            {
                "id": "s1",
                "units": [
                    {
                        "id": "s1-u1",
                        "lessons": [
                            {"id": "l1", "name": "Greetings", "template": "intro"},
                            {"id": "l2", "name": "Drills", "template": "practice"},
                        ],
                    }
                ],
            }
        ]

    def test_no_filter_returns_all(self) -> None:
        out = filter_lessons(self._sections())
        self.assertEqual(len(out), 2)

    def test_text_filter_matches_name(self) -> None:
        out = filter_lessons(self._sections(), text="greet")
        self.assertEqual(len(out), 1)
        self.assertEqual(out[0][2]["id"], "l1")

    def test_text_filter_matches_id(self) -> None:
        out = filter_lessons(self._sections(), text="l2")
        self.assertEqual(len(out), 1)
        self.assertEqual(out[0][2]["id"], "l2")

    def test_template_filter(self) -> None:
        out = filter_lessons(self._sections(), template="practice")
        self.assertEqual(len(out), 1)
        self.assertEqual(out[0][2]["template"], "practice")

    def test_combined_filters(self) -> None:
        out = filter_lessons(self._sections(), text="drills", template="intro")
        self.assertEqual(out, [])


class ExportMarkdownTest(unittest.TestCase):
    def test_renders_full_structure(self) -> None:
        adapter = _adapter(
            sections=[
                {
                    "id": "s1",
                    "name": "Section 1",
                    "level": "A1",
                    "units": [
                        {
                            "id": "s1-u1",
                            "name": "Unit 1",
                            "lessons": [
                                {
                                    "id": "l1",
                                    "name": "Greetings",
                                    "template": "intro",
                                    "content": {"subLessons": [{"stages": []}]},
                                },
                                {
                                    "id": "l2",
                                    "name": "Empty",
                                    "template": "practice",
                                    "content": {"subLessons": []},
                                },
                            ],
                        }
                    ],
                }
            ],
            vocab=[{"id": "w1"}],
        )
        stats = compute_overview_stats(adapter, include_validation=False)
        md = export_markdown(stats, adapter.sections)
        self.assertIn("# 课程结构总览", md)
        self.assertIn("## Section 1 (A1)", md)
        self.assertIn("### Unit 1", md)
        self.assertIn("**Greetings** · 认识新词", md)
        self.assertIn("**Empty** · 巩固练习  ·  _空_", md)
        self.assertIn("Sections: 1", md)

    def test_filtered_export_shows_note(self) -> None:
        adapter = _adapter(
            sections=[
                {
                    "id": "s1",
                    "name": "S1",
                    "level": "A1",
                    "units": [
                        {
                            "id": "u1",
                            "lessons": [
                                {"id": "l1", "name": "Alpha", "template": "intro"},
                                {"id": "l2", "name": "Beta", "template": "practice"},
                            ],
                        }
                    ],
                }
            ]
        )
        stats = compute_overview_stats(adapter, include_validation=False)
        md = export_markdown(stats, adapter.sections, text="alpha")
        self.assertIn("关键字：alpha", md)
        self.assertIn("**Alpha**", md)
        self.assertNotIn("**Beta**", md)


if __name__ == "__main__":
    unittest.main()
