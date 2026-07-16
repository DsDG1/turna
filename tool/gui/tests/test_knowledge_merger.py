"""Tests for src.backend.knowledge_merger (bookplan2 Phase 4)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.knowledge_merger import analyze, apply, resource_key
from src.backend.knowledge_schema import KnowledgePoints
from src.backend.markdown_chopper import Chapter


def _chapter(idx: int, title: str) -> Chapter:
    return Chapter(idx=idx, level=2, title=title, slug=f"ch{idx}", markdown=title)


def _kp(**kwargs) -> KnowledgePoints:
    return KnowledgePoints(
        words=kwargs.get("words", []),
        expressions=kwargs.get("expressions", []),
        grammarPoints=kwargs.get("grammarPoints", []),
    )


class FakeAdapter:
    def __init__(self, vocab=None, expressions=None, grammar_points=None):
        self.vocab = vocab or []
        self.expressions = expressions or []
        self.grammar_points = grammar_points or []


class ResourceKeyTest(unittest.TestCase):
    def test_word_key_ignores_punctuation_and_case(self) -> None:
        self.assertEqual(
            resource_key("word", {"term": "Merhaba!", "translation": "Hello."}),
            resource_key("word", {"term": "merhaba", "translation": "hello"}),
        )

    def test_grammar_key_is_title_only(self) -> None:
        self.assertEqual(
            resource_key("grammarPoint", {"title": "Greetings", "explanation": "x"}),
            resource_key("grammarPoint", {"title": "greetings", "explanation": "y"}),
        )


class AnalyzeTest(unittest.TestCase):
    def test_no_collisions_for_unique_resources(self) -> None:
        ch1 = _chapter(1, "A")
        ch2 = _chapter(2, "B")
        kp1 = _kp(words=[{"id": "ch-ch1-w-merhaba", "term": "merhaba", "translation": "hello"}])
        kp2 = _kp(words=[{"id": "ch-ch2-w-gule", "term": "güle", "translation": "bye"}])
        report = analyze([(ch1, kp1), (ch2, kp2)])
        self.assertEqual(report.intra_project_count, 0)
        self.assertEqual(report.course_collision_count, 0)

    def test_intra_project_duplicate_flagged(self) -> None:
        ch1 = _chapter(1, "A")
        ch2 = _chapter(2, "B")
        kp1 = _kp(words=[{"id": "ch-ch1-w-merhaba", "term": "merhaba", "translation": "hello"}])
        kp2 = _kp(words=[{"id": "ch-ch2-w-merhaba", "term": "merhaba", "translation": "hello"}])
        report = analyze([(ch1, kp1), (ch2, kp2)])
        self.assertEqual(report.intra_project_count, 1)
        self.assertEqual(report.course_collision_count, 0)
        col = report.intra_project[0]
        self.assertEqual(col.chapter_index, 1)  # later occurrence
        self.assertEqual(col.entry_id, "ch-ch2-w-merhaba")
        self.assertEqual(col.target_id, "ch-ch1-w-merhaba")  # first occurrence canonical

    def test_intra_project_grammar_flagged_by_title(self) -> None:
        ch1 = _chapter(1, "A")
        ch2 = _chapter(2, "B")
        kp1 = _kp(grammarPoints=[{"id": "g1", "title": "Vowel Harmony"}])
        kp2 = _kp(grammarPoints=[{"id": "g2", "title": "vowel harmony"}])
        report = analyze([(ch1, kp1), (ch2, kp2)])
        self.assertEqual(report.intra_project_count, 1)
        self.assertEqual(report.intra_project[0].target_id, "g1")

    def test_course_collision_flagged(self) -> None:
        ch1 = _chapter(1, "A")
        kp1 = _kp(words=[{"id": "ch-ch1-w-merhaba", "term": "merhaba", "translation": "hello"}])
        adapter = FakeAdapter(vocab=[{"id": "existing-merhaba", "term": "merhaba", "translation": "hello"}])
        report = analyze([(ch1, kp1)], adapter)
        self.assertEqual(report.course_collision_count, 1)
        self.assertEqual(report.intra_project_count, 0)
        col = report.course_collisions[0]
        self.assertEqual(col.target_id, "existing-merhaba")

    def test_course_collision_supersedes_intra_project(self) -> None:
        # Same term in two chapters AND in the course -> both are course
        # collisions pointing at the course id; no intra-project entry.
        ch1 = _chapter(1, "A")
        ch2 = _chapter(2, "B")
        kp1 = _kp(words=[{"id": "ch-ch1-w-merhaba", "term": "merhaba", "translation": "hello"}])
        kp2 = _kp(words=[{"id": "ch-ch2-w-merhaba", "term": "merhaba", "translation": "hello"}])
        adapter = FakeAdapter(vocab=[{"id": "course-merhaba", "term": "merhaba", "translation": "hello"}])
        report = analyze([(ch1, kp1), (ch2, kp2)], adapter)
        self.assertEqual(report.course_collision_count, 2)
        self.assertEqual(report.intra_project_count, 0)
        for col in report.course_collisions:
            self.assertEqual(col.target_id, "course-merhaba")

    def test_collisions_for_chapter_filters(self) -> None:
        ch1 = _chapter(1, "A")
        ch2 = _chapter(2, "B")
        kp1 = _kp(words=[{"id": "a", "term": "merhaba", "translation": "hello"}])
        kp2 = _kp(words=[{"id": "b", "term": "merhaba", "translation": "hello"}])
        report = analyze([(ch1, kp1), (ch2, kp2)])
        self.assertEqual(len(report.collisions_for_chapter(0)), 0)
        self.assertEqual(len(report.collisions_for_chapter(1)), 1)


class ApplyTest(unittest.TestCase):
    def test_apply_unifies_intra_project_ids(self) -> None:
        ch1 = _chapter(1, "A")
        ch2 = _chapter(2, "B")
        kp1 = _kp(words=[{"id": "ch-ch1-w-merhaba", "term": "merhaba", "translation": "hello"}])
        kp2 = _kp(words=[{"id": "ch-ch2-w-merhaba", "term": "merhaba", "translation": "hello"}])
        chapters = [(ch1, kp1), (ch2, kp2)]
        report = apply(chapters)
        self.assertEqual(report.intra_project_count, 1)
        # Chapter 2's word id rewritten to chapter 1's canonical id.
        self.assertEqual(chapters[1][1].words[0]["id"], "ch-ch1-w-merhaba")
        self.assertEqual(chapters[0][1].words[0]["id"], "ch-ch1-w-merhaba")

    def test_apply_aligns_course_collision_id(self) -> None:
        ch1 = _chapter(1, "A")
        kp1 = _kp(words=[{"id": "ch-ch1-w-merhaba", "term": "merhaba", "translation": "hello"}])
        adapter = FakeAdapter(vocab=[{"id": "course-merhaba", "term": "merhaba", "translation": "hello"}])
        chapters = [(ch1, kp1)]
        apply(chapters, adapter)
        self.assertEqual(chapters[0][1].words[0]["id"], "course-merhaba")

    def test_apply_is_idempotent(self) -> None:
        ch1 = _chapter(1, "A")
        ch2 = _chapter(2, "B")
        kp1 = _kp(words=[{"id": "a", "term": "merhaba", "translation": "hello"}])
        kp2 = _kp(words=[{"id": "b", "term": "merhaba", "translation": "hello"}])
        chapters = [(ch1, kp1), (ch2, kp2)]
        first = apply(chapters)
        second = apply(chapters)
        self.assertEqual(first.intra_project_count, 1)
        self.assertEqual(second.intra_project_count, 0)  # already unified
        self.assertEqual(chapters[1][1].words[0]["id"], "a")

    def test_apply_preserves_unique_resources(self) -> None:
        ch1 = _chapter(1, "A")
        kp1 = _kp(
            words=[
                {"id": "w1", "term": "merhaba", "translation": "hello"},
                {"id": "w2", "term": "evet", "translation": "yes"},
            ]
        )
        chapters = [(ch1, kp1)]
        report = apply(chapters)
        self.assertEqual(report.total_count, 0)
        self.assertEqual(chapters[0][1].words[0]["id"], "w1")
        self.assertEqual(chapters[0][1].words[1]["id"], "w2")

    def test_course_collision_without_course_id_recorded_not_applied(self) -> None:
        # Course entry has an empty id -> collision is reported for display but
        # the project entry is left unchanged (nothing to align to).
        ch1 = _chapter(1, "A")
        kp1 = _kp(words=[{"id": "proj-merhaba", "term": "merhaba", "translation": "hello"}])
        adapter = FakeAdapter(vocab=[{"id": "", "term": "merhaba", "translation": "hello"}])
        chapters = [(ch1, kp1)]
        report = apply(chapters, adapter)
        self.assertEqual(report.course_collision_count, 1)
        self.assertEqual(report.course_collisions[0].target_id, "")
        self.assertEqual(chapters[0][1].words[0]["id"], "proj-merhaba")


if __name__ == "__main__":
    unittest.main()
