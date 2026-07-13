"""Tests for teacher-view pure functions: lesson wizard + error mapper.

Covers T.2 (intro lesson generation round-trips through validate) and T.7
(error path parsing / humanization). No PySide6 dependency.
"""
from __future__ import annotations

import shutil
import sys
import tempfile
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.course_adapter import CourseAdapter  # noqa: E402
from src.teacher.error_mapper import (  # noqa: E402
    humanize_problem,
    parse_path,
    problem_to_node_ref,
)
from src.teacher.lesson_wizard import build_intro_lesson  # noqa: E402

COURSE_SRC = Path(__file__).resolve().parents[3] / "assets" / "courses" / "turkish"


class LessonWizardTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="varnamala_wizard_"))
        self.course_dir = self.tmp / "turkish"
        shutil.copytree(COURSE_SRC, self.course_dir)

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_build_intro_lesson_structure(self) -> None:
        words = [
            {"id": "w-a", "term": "A", "translation": "甲"},
            {"id": "w-b", "term": "B", "translation": "乙"},
        ]
        lesson = build_intro_lesson("测试课", "desc", words)
        self.assertEqual(lesson["template"], "intro")
        self.assertEqual(lesson["type"], "normal")
        subs = lesson["content"]["subLessons"]
        self.assertEqual(len(subs), 2)
        for sl in subs:
            stages = sl["stages"]
            self.assertEqual(len(stages), 3)
            rts = [st["items"][0]["runtimeType"] for st in stages]
            self.assertEqual(rts, ["showWord", "translateSentence", "fillBlank"])

    def test_generated_intro_lesson_validates(self) -> None:
        """The wizard output must pass course_cli validate after save (§15.13)."""
        adapter = CourseAdapter()
        adapter.load(self.course_dir)
        words = adapter.vocab[:2]
        lesson = build_intro_lesson("向导课", "向导生成", words)
        adapter.sections[0]["units"][0]["lessons"].append(lesson)
        result = adapter.save()
        self.assertTrue(result.ok, f"save failed: {result.message} errors={result.errors}")


class ErrorMapperTest(unittest.TestCase):
    def test_parse_path_full(self) -> None:
        parts = parse_path("section:section4/unit:u-1/lesson:l-1")
        self.assertEqual(parts["section"], "section4")
        self.assertEqual(parts["unit"], "u-1")
        self.assertEqual(parts["lesson"], "l-1")

    def test_parse_path_section_only(self) -> None:
        parts = parse_path("section:section2")
        self.assertEqual(parts["section"], "section2")
        self.assertEqual(parts["unit"], "")

    def test_parse_path_empty(self) -> None:
        self.assertEqual(parse_path(""), {"section": "", "unit": "", "lesson": ""})

    def test_humanize_dangling_word(self) -> None:
        msg = humanize_problem(
            {"message": "ShowWord sw-1 references missing wordId w-x", "path": ""}
        )
        self.assertIn("引用了不存在的词", msg)

    def test_humanize_duplicate(self) -> None:
        msg = humanize_problem({"message": "Duplicate lesson id: s1-l1", "path": ""})
        self.assertIn("重复", msg)

    def test_problem_to_node_ref_lesson(self) -> None:
        ref = problem_to_node_ref(
            {"path": "section:section1/unit:u-1/lesson:s1-l2"}, []
        )
        self.assertEqual(ref, ("lesson", "s1-l2"))

    def test_problem_to_node_ref_none_for_empty_path(self) -> None:
        self.assertIsNone(problem_to_node_ref({"path": ""}, []))


if __name__ == "__main__":
    unittest.main()
