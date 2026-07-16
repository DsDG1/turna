"""Tests for textbook-import backend: markdown_chopper, knowledge_schema,
textbook_to_course. Verifies build_section_from_chapter yields a section that
passes CourseAdapter.validate_section_json(check_existing_ids=False) with zero
errors.
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.course_adapter import CourseAdapter  # noqa: E402
from src.backend.knowledge_schema import coerce_knowledge_points  # noqa: E402
from src.backend.lesson_content import slugify  # noqa: E402
from src.backend.markdown_chopper import split_chapters  # noqa: E402
from src.backend.textbook_to_course import build_section_from_chapter  # noqa: E402


# --------------------------------------------------------------------------- #
# split_chapters
# --------------------------------------------------------------------------- #


class SplitChaptersTest(unittest.TestCase):
    def test_no_headings_returns_empty(self) -> None:
        self.assertEqual(split_chapters("just some prose\nno titles"), [])

    def test_empty_input(self) -> None:
        self.assertEqual(split_chapters(""), [])

    def test_splits_by_level2_headings(self) -> None:
        md = (
            "# Book Title\n"
            "intro\n"
            "## 1 Merhaba\n"
            "body of merhaba\n"
            "## 2 Aile\n"
            "body of aile\n"
        )
        chs = split_chapters(md)
        self.assertEqual(len(chs), 2)
        self.assertEqual([c.idx for c in chs], [1, 2])
        self.assertEqual([c.level for c in chs], [2, 2])
        self.assertEqual(chs[0].title, "1 Merhaba")
        self.assertEqual(chs[1].title, "2 Aile")
        self.assertIn("body of merhaba", chs[0].markdown)
        self.assertIn("body of aile", chs[1].markdown)
        self.assertNotIn("body of aile", chs[0].markdown)
        self.assertNotIn("Book Title", chs[0].markdown)

    def test_level1_is_boundary_not_chapter(self) -> None:
        md = "# Book\npart intro\n## Chapter One\nbody\n## Chapter Two\nbody2\n"
        chs = split_chapters(md, min_level=2)
        self.assertEqual(len(chs), 2)
        self.assertEqual([c.title for c in chs], ["Chapter One", "Chapter Two"])
        # "part intro" after a level-1 boundary is dropped (not absorbed).
        self.assertNotIn("part intro", chs[0].markdown)

    def test_deeper_subheadings_stay_inside_chapter(self) -> None:
        md = (
            "## 1 Merhaba\n"
            "intro\n"
            "### 1.1 Selam\n"
            "sub body\n"
            "## 2 Aile\n"
            "body2\n"
        )
        chs = split_chapters(md)
        self.assertEqual(len(chs), 2)
        self.assertIn("### 1.1 Selam", chs[0].markdown)
        self.assertIn("sub body", chs[0].markdown)
        self.assertNotIn("### 1.1 Selam", chs[1].markdown)

    def test_min_level_boundary(self) -> None:
        md = "### deep\nbody1\n### deep2\nbody2\n"
        chs = split_chapters(md, min_level=3)
        self.assertEqual(len(chs), 2)
        self.assertEqual([c.level for c in chs], [3, 3])

    def test_slug_is_deterministic_via_slugify(self) -> None:
        md = "## Merhaba Dünya!\nbody\n"
        chs = split_chapters(md)
        self.assertEqual(chs[0].slug, slugify("Merhaba Dünya!"))

    def test_chapter_includes_its_own_heading_line(self) -> None:
        md = "## 1 X\nbody\n## 2 Y\nbody2\n"
        chs = split_chapters(md)
        self.assertTrue(chs[0].markdown.startswith("## 1 X"))


# --------------------------------------------------------------------------- #
# coerce_knowledge_points
# --------------------------------------------------------------------------- #


class CoerceKnowledgePointsTest(unittest.TestCase):
    def test_fills_missing_ids_and_defaults(self) -> None:
        raw = {"words": [{"term": "merhaba", "translation": "hello"}]}
        kp = coerce_knowledge_points(raw)
        self.assertEqual(len(kp.words), 1)
        w = kp.words[0]
        self.assertEqual(w["id"], "w-merhaba")
        self.assertEqual(w["pronunciation"], "")
        self.assertEqual(w["tags"], [])

    def test_accepts_vocab_alias_for_words(self) -> None:
        raw = {"vocab": [{"term": "ev", "translation": "house"}]}
        kp = coerce_knowledge_points(raw)
        self.assertEqual(len(kp.words), 1)
        self.assertEqual(kp.words[0]["id"], "w-ev")

    def test_preserves_existing_id(self) -> None:
        raw = {"words": [{"id": "w-custom", "term": "x", "translation": "y"}]}
        kp = coerce_knowledge_points(raw)
        self.assertEqual(kp.words[0]["id"], "w-custom")

    def test_expressions_coerced(self) -> None:
        raw = {"expressions": [{"term": "Selam!", "translation": "Hi!"}]}
        kp = coerce_knowledge_points(raw)
        self.assertEqual(kp.expressions[0]["id"], "e-selam")
        self.assertEqual(kp.expressions[0]["pronunciation"], "")
        self.assertEqual(kp.expressions[0]["tags"], [])

    def test_grammar_point_requires_title(self) -> None:
        with self.assertRaises(ValueError):
            coerce_knowledge_points({"grammarPoints": [{"explanation": "x"}]})

    def test_grammar_point_filled(self) -> None:
        raw = {"grammarPoints": [{"title": "Plural", "explanation": "how to"}]}
        kp = coerce_knowledge_points(raw)
        g = kp.grammarPoints[0]
        self.assertEqual(g["id"], "g-plural")
        self.assertEqual(g["exampleExpressionIds"], [])
        self.assertEqual(g["exampleSentenceIds"], [])
        self.assertEqual(g["practiceItems"], [])

    def test_word_requires_term(self) -> None:
        with self.assertRaises(ValueError):
            coerce_knowledge_points({"words": [{"translation": "x"}]})

    def test_dedupes_by_id(self) -> None:
        raw = {
            "words": [
                {"id": "w-x", "term": "x", "translation": "x1"},
                {"id": "w-x", "term": "dup", "translation": "dup1"},
            ]
        }
        kp = coerce_knowledge_points(raw)
        self.assertEqual(len(kp.words), 1)
        self.assertEqual(kp.words[0]["term"], "x")

    def test_id_prefix_applied_to_synthesized_ids(self) -> None:
        raw = {"words": [{"term": "merhaba", "translation": "hi"}]}
        kp = coerce_knowledge_points(raw, id_prefix="ch-1-")
        self.assertEqual(kp.words[0]["id"], "ch-1-w-merhaba")


# --------------------------------------------------------------------------- #
# build_section_from_chapter
# --------------------------------------------------------------------------- #


def _sample_chapter() -> "object":
    md = "## 1 Merhaba\nmerhaba means hello\n"
    chs = split_chapters(md)
    return chs[0]


def _sample_kp() -> "object":
    return coerce_knowledge_points(
        {
            "words": [
                {"term": "merhaba", "translation": "hello", "tags": ["greeting"]},
                {"term": "günaydın", "translation": "good morning"},
            ],
            "expressions": [
                {"term": "Selam!", "translation": "Hi!", "tags": ["greeting"]}
            ],
            "grammarPoints": [
                {"title": "Greetings", "explanation": "common greetings"}
            ],
        }
    )


class BuildSectionFromChapterTest(unittest.TestCase):
    def test_section_id_is_deterministic(self) -> None:
        ch = _sample_chapter()
        kp = _sample_kp()
        s1 = build_section_from_chapter(ch, kp, 3)
        s2 = build_section_from_chapter(ch, kp, 3)
        self.assertEqual(s1["id"], s2["id"])
        self.assertEqual(s1["id"], "ch-1-merhaba-3")

    def test_resources_under_correct_keys(self) -> None:
        ch = _sample_chapter()
        kp = _sample_kp()
        section = build_section_from_chapter(ch, kp, 1)
        self.assertIn("words", section)
        self.assertIn("expressions", section)
        self.assertIn("grammarPoints", section)
        # NOT 'vocab' — merge_section_resources only reads these three names.
        self.assertNotIn("vocab", section)
        self.assertEqual(len(section["words"]), 2)
        self.assertEqual(len(section["expressions"]), 1)
        self.assertEqual(len(section["grammarPoints"]), 1)

    def test_single_unit_single_intro_lesson(self) -> None:
        ch = _sample_chapter()
        kp = _sample_kp()
        section = build_section_from_chapter(ch, kp, 1)
        self.assertEqual(len(section["units"]), 1)
        lessons = section["units"][0]["lessons"]
        self.assertEqual(len(lessons), 1)
        self.assertEqual(lessons[0]["template"], "intro")
        # Each word → one sub-lesson with 3 stages.
        self.assertEqual(len(lessons[0]["content"]["subLessons"]), 2)
        stages = lessons[0]["content"]["subLessons"][0]["stages"]
        self.assertEqual([s["items"][0]["runtimeType"] for s in stages], [
            "showWord",
            "translateSentence",
            "fillBlank",
        ])

    def test_practice_lesson_template(self) -> None:
        ch = _sample_chapter()
        kp = _sample_kp()
        section = build_section_from_chapter(ch, kp, 1, lesson_template="practice")
        lesson = section["units"][0]["lessons"][0]
        self.assertEqual(lesson["template"], "practice")

    def test_review_lesson_template(self) -> None:
        ch = _sample_chapter()
        kp = _sample_kp()
        section = build_section_from_chapter(ch, kp, 1, lesson_template="review")
        lesson = section["units"][0]["lessons"][0]
        self.assertEqual(lesson["template"], "review")

    def test_unknown_lesson_template_falls_back_to_intro(self) -> None:
        ch = _sample_chapter()
        kp = _sample_kp()
        section = build_section_from_chapter(ch, kp, 1, lesson_template="listening")
        lesson = section["units"][0]["lessons"][0]
        self.assertEqual(lesson["template"], "intro")

    def test_level_param_applied(self) -> None:
        ch = _sample_chapter()
        kp = _sample_kp()
        section = build_section_from_chapter(ch, kp, 1, level="B1")
        self.assertEqual(section["level"], "B1")
        # Default remains A1.
        self.assertEqual(build_section_from_chapter(ch, kp, 1)["level"], "A1")

    def test_section_passes_validate_with_zero_errors(self) -> None:
        ch = _sample_chapter()
        kp = _sample_kp()
        section = build_section_from_chapter(ch, kp, 1)
        adapter = CourseAdapter()
        problems = adapter.validate_section_json(
            section, check_existing_ids=False
        )
        errors = [p for p in problems if p["level"] == "error"]
        self.assertEqual(
            errors,
            [],
            f"expected zero errors, got: {errors}",
        )

    def test_empty_words_still_valid_section(self) -> None:
        # A chapter with no extractable words: intro lesson has no sub-lessons,
        # which validate_section_json flags. This documents that behavior:
        # upstream must skip empty-word chapters rather than import them.
        ch = _sample_chapter()
        kp = coerce_knowledge_points({})
        section = build_section_from_chapter(ch, kp, 1)
        adapter = CourseAdapter()
        problems = adapter.validate_section_json(
            section, check_existing_ids=False
        )
        errors = [p for p in problems if p["level"] == "error"]
        # Empty intro lesson (no subLessons) → expect at least one error,
        # proving the caller must filter empty chapters.
        self.assertTrue(errors, "empty-word chapter should fail validation")


if __name__ == "__main__":
    unittest.main()