"""Unit tests for CourseSectionMergeService."""
from __future__ import annotations

import unittest

from src.backend.course_section_merge import (
    CourseSectionMergeService,
    MergeAction,
    SectionMergePlan,
)


class DummyAdapter:
    def __init__(self):
        self.sections = [
            {
                "id": "s1",
                "name": "Section 1",
                "units": [
                    {
                        "id": "u1",
                        "title": "Unit 1",
                        "lessons": [
                            {"id": "l1", "title": "Lesson 1", "steps": []}
                        ],
                    }
                ],
            }
        ]
        self.index = {"sections": [{"id": "s1"}]}
        self.vocab = [{"id": "w-merhaba"}]
        self.expressions = []
        self.grammar_points = []

    def find_section(self, sid: str):
        for s in self.sections:
            if s["id"] == sid:
                return s
        raise KeyError(sid)


class TestCourseSectionMergeService(unittest.TestCase):
    def test_validate_section_json_valid(self):
        adapter = DummyAdapter()
        valid = {
            "id": "ai-travel",
            "name": "AI Travel",
            "description": "",
            "prerequisiteSectionIds": [],
            "units": [
                {
                    "id": "ai-travel-u1",
                    "name": "Unit 1",
                    "description": "",
                    "prerequisiteUnitIds": [],
                    "lessons": [
                        {
                            "id": "ai-travel-u1-l1",
                            "name": "Lesson 1",
                            "description": "",
                            "type": "normal",
                            "template": "intro",
                            "prerequisiteLessonIds": [],
                            "content": {
                                "subLessons": [
                                    {
                                        "id": "ai-travel-u1-l1-sl1",
                                        "name": "Words",
                                        "stages": [
                                            {
                                                "id": "ai-travel-u1-l1-sl1-st1",
                                                "name": "Learn",
                                                "items": [
                                                    {
                                                        "runtimeType": "showWord",
                                                        "id": "sw-1",
                                                        "wordId": "w-merhaba",
                                                        "context": "",
                                                    }
                                                ],
                                            }
                                        ],
                                    }
                                ]
                            },
                        }
                    ],
                }
            ],
        }
        problems = CourseSectionMergeService.validate_section_json(adapter, valid)
        self.assertEqual(problems, [])

    def test_validate_section_json_errors(self):
        adapter = DummyAdapter()
        # Missing id
        p1 = CourseSectionMergeService.validate_section_json(adapter, {"name": "S"})
        self.assertTrue(any(p["path"] == "id" for p in p1))

        # Duplicate id
        p2 = CourseSectionMergeService.validate_section_json(adapter, {"id": "s1", "name": "S", "units": []})
        self.assertTrue(any("已存在" in p["message"] for p in p2))

        # Empty units
        p3 = CourseSectionMergeService.validate_section_json(adapter, {"id": "s2", "name": "S", "units": []})
        self.assertTrue(any(p["path"] == "units" for p in p3))

    def test_plan_section_merge_new(self):
        adapter = DummyAdapter()
        incoming = {
            "id": "s2",
            "name": "Section 2",
            "units": [
                {"id": "u2", "lessons": []}
            ]
        }
        plan = CourseSectionMergeService.plan_section_merge(adapter, None, incoming)
        self.assertEqual(len(plan.added_units), 1)
        self.assertEqual(plan.added_units[0].action, "add")
        self.assertEqual(len(plan.replaced_units), 0)

    def test_plan_section_merge_existing(self):
        adapter = DummyAdapter()
        incoming = {
            "id": "s1",
            "name": "Section 1",
            "units": [
                {
                    "id": "u1",  # existing
                    "lessons": [
                        {"id": "l1", "title": "Lesson 1 updated"},  # existing
                        {"id": "l2", "title": "Lesson 2 new"},      # new
                    ],
                },
                {"id": "u3", "lessons": []}  # new
            ]
        }
        plan = CourseSectionMergeService.plan_section_merge(adapter, "s1", incoming)
        self.assertEqual(len(plan.replaced_units), 1)
        self.assertEqual(plan.replaced_units[0].target_index, 0)
        self.assertEqual(len(plan.added_units), 1)

        # Lessons in u1
        replaced_lessons = plan.replaced_lessons_by_unit.get("u1", [])
        added_lessons = plan.added_lessons_by_unit.get("u1", [])
        self.assertEqual(len(replaced_lessons), 1)
        self.assertEqual(replaced_lessons[0].target_index, 0)
        self.assertEqual(len(added_lessons), 1)


    def test_validate_section_json_unit_id_duplicates(self):
        adapter = DummyAdapter()
        section = {
            "id": "s2",
            "name": "S",
            "units": [
                {"id": "u1", "lessons": []},  # collides with existing u1
                {"id": "u1", "lessons": []},  # and is a local duplicate
                {"id": "", "lessons": []},  # empty id
            ],
        }
        problems = CourseSectionMergeService.validate_section_json(adapter, section)
        dup = [p for p in problems if p["path"] == "unit:u1"]
        self.assertEqual(len(dup), 2)  # existing-collision + local duplicate
        self.assertTrue(any(p["path"] == "units" and "unit id" in p["message"] for p in problems))

    def test_validate_section_json_check_existing_ids_flag(self):
        adapter = DummyAdapter()
        section = {"id": "s1", "name": "S", "units": [{"id": "u1", "lessons": []}]}
        # Default: reusing the existing section/unit ids is flagged.
        strict = CourseSectionMergeService.validate_section_json(adapter, section)
        self.assertTrue(any("已存在" in p["message"] for p in strict))
        # Merge paths pass check_existing_ids=False: existing ids are reused
        # on purpose and only local duplicates remain errors.
        merged = CourseSectionMergeService.validate_section_json(
            adapter, section, check_existing_ids=False
        )
        self.assertFalse(any("已存在" in p["message"] for p in merged))

    def test_validate_section_json_unit_limit(self):
        from src.backend import api

        adapter = DummyAdapter()
        section = {
            "id": "s2",
            "name": "S",
            "units": [
                {"id": f"u{i}", "lessons": []}
                for i in range(api.MAX_UNITS_PER_SECTION + 1)
            ],
        }
        problems = CourseSectionMergeService.validate_section_json(adapter, section)
        self.assertTrue(
            any(
                p["path"] == "units" and "超过上限" in p["message"]
                for p in problems
            )
        )


if __name__ == "__main__":
    unittest.main()
