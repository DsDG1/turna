"""Tests for syllabus → course-plan extraction (heuristic + coercion + seam)."""
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.application.course_plan_service import CoursePlanService
from src.backend.syllabus_brief import (
    SyllabusBrief,
    brief_summary,
    brief_to_spec_values,
    build_brief_messages,
    coerce_brief,
    heuristic_brief,
)

_SYLLABUS = """# Türkçe A1-A2 Ders İzlencesi

本教学纲领覆盖 A1 与 A2 两个等级，每单元 6 课，词汇量：800。

Ünite 1: Tanışma ve selamlaşma
- 教学目标：能进行简单的自我介绍
- 能问候他人并道别
- 语法：kişi zamirleri

Ünite 2: Aile ve yakınlar
- 能介绍家庭成员
- 语法：iyelik ekleri

Ünite 3: Günlük rutin
- 能说出日常活动与时间
- 语法：şimdiki zaman

考核：单元小测 40%，期末口试 60%。
"""


class HeuristicBriefTest(unittest.TestCase):
    def setUp(self) -> None:
        self.brief = heuristic_brief(_SYLLABUS)

    def test_units_follow_document_order(self) -> None:
        self.assertEqual(len(self.brief.units), 3)
        self.assertIn("Ünite 1", self.brief.units[0])

    def test_level_range(self) -> None:
        self.assertEqual(self.brief.level_from, "A1")
        self.assertEqual(self.brief.level_to, "A2")

    def test_section_count_matches_units(self) -> None:
        self.assertEqual(self.brief.section_count, len(self.brief.units))

    def test_lessons_per_section_read_from_text(self) -> None:
        self.assertEqual(self.brief.lessons_per_section, 6)

    def test_word_budget_read_from_text(self) -> None:
        self.assertEqual(self.brief.word_budget, 800)

    def test_can_do_lines_extracted(self) -> None:
        joined = " ".join(self.brief.can_do)
        self.assertIn("自我介绍", joined)
        self.assertIn("家庭成员", joined)

    def test_topic_strips_unit_word(self) -> None:
        self.assertNotIn("Ünite", self.brief.topic)
        self.assertTrue(self.brief.topic)

    def test_constraints_carry_unit_ladder(self) -> None:
        self.assertIn("Tanışma", self.brief.constraints)
        self.assertIn("Aile", self.brief.constraints)
        self.assertIn("严格按教学纲领", self.brief.constraints)

    def test_summary_mentions_counts(self) -> None:
        text = brief_summary(self.brief)
        self.assertIn("3 个单元", text)
        self.assertIn("A1→A2", text)

    def test_defaults_warn_when_nothing_detected(self) -> None:
        brief = heuristic_brief("sadece düz bir metin", default_level="B1")
        self.assertEqual(brief.level_from, "B1")
        self.assertTrue(brief.warnings)

    def test_spec_values_shape(self) -> None:
        values = brief_to_spec_values(self.brief)
        for key in (
            "topic",
            "level_from",
            "level_to",
            "section_count",
            "lessons_per_section",
            "word_budget",
            "can_do",
            "constraints",
        ):
            self.assertIn(key, values)
        self.assertIsInstance(values["can_do"], list)


class CoerceBriefTest(unittest.TestCase):
    def setUp(self) -> None:
        self.fallback = heuristic_brief(_SYLLABUS)

    def test_model_units_override_and_force_section_count(self) -> None:
        brief = coerce_brief(
            {
                "topic": "日常土耳其语",
                "units": ["Selamlaşma", "Aile", "Rutin", "Alışveriş"],
                "section_count": 9,
                "level_from": "A1",
                "level_to": "A2",
                "can_do": ["能购物"],
                "constraints": "按顺序覆盖",
            },
            self.fallback,
        )
        self.assertEqual(brief.section_count, 4)  # units are the authority
        self.assertEqual(brief.topic, "日常土耳其语")
        self.assertEqual(brief.can_do, ("能购物",))
        self.assertEqual(brief.source, "ai")

    def test_reversed_levels_are_swapped(self) -> None:
        brief = coerce_brief({"level_from": "B1", "level_to": "A1"}, self.fallback)
        self.assertEqual((brief.level_from, brief.level_to), ("A1", "B1"))

    def test_unknown_levels_fall_back(self) -> None:
        brief = coerce_brief({"level_from": "Z9", "level_to": "Z8"}, self.fallback)
        self.assertEqual(brief.level_from, self.fallback.level_from)
        self.assertEqual(brief.level_to, self.fallback.level_to)

    def test_bad_numbers_fall_back(self) -> None:
        brief = coerce_brief(
            {"lessons_per_section": "many", "word_budget": None}, self.fallback
        )
        self.assertEqual(brief.lessons_per_section, self.fallback.lessons_per_section)
        self.assertEqual(brief.word_budget, self.fallback.word_budget)

    def test_prompt_requests_strict_json(self) -> None:
        messages = build_brief_messages("Turkish", "Chinese", _SYLLABUS, self.fallback)
        user = messages[1]["content"]
        self.assertIn("STRICT JSON", user)
        self.assertIn("can_do", user)
        self.assertIn("Ünite 1", user)


class CoursePlanServiceSeamTest(unittest.TestCase):
    def _service(self) -> CoursePlanService:
        return CoursePlanService(adapter=None)

    def test_load_syllabus_from_text_file(self) -> None:
        tmp = Path(tempfile.mkdtemp(prefix="syllabus_"))
        path = tmp / "syllabus.md"
        path.write_text(_SYLLABUS, encoding="utf-8")
        payload = self._service().load_syllabus(str(path))
        self.assertIn("values", payload)
        self.assertEqual(payload["values"]["section_count"], 3)
        self.assertEqual(payload["source"], "heuristic")
        self.assertIn("教学纲领已解析", payload["summary"])
        self.assertIsInstance(payload["warnings"], list)

    def test_missing_file_raises(self) -> None:
        with self.assertRaises(RuntimeError):
            self._service().load_syllabus(str(Path(tempfile.gettempdir()) / "nope.md"))


if __name__ == "__main__":
    unittest.main()
