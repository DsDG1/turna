"""Tests for phased outline → lesson generation (aiEnhance P2-7..10)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest.mock import patch

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.ai_generator import AiApiConfig, AiCourseSpec  # noqa: E402
from src.backend.ai_phased import (  # noqa: E402
    build_lesson_fill_instruction,
    build_outline_prompt,
    fill_lessons_from_outline,
    iter_outline_lessons,
    outline_to_section_shell,
    request_course,
    validate_outline,
)


def _sample_outline() -> dict:
    return {
        "id": "ai-phased-demo",
        "name": "Phased Demo",
        "description": "test",
        "words": [
            {"id": "w-a", "term": "Merhaba", "translation": "你好", "tags": []},
            {"id": "w-b", "term": "Günaydın", "translation": "早上好", "tags": []},
        ],
        "expressions": [],
        "grammarPoints": [],
        "units": [
            {
                "id": "u1",
                "name": "U1",
                "lessons": [
                    {
                        "id": "u1-l1",
                        "name": "Hello",
                        "template": "intro",
                        "targetWordIds": ["w-a"],
                    },
                    {
                        "id": "u1-l2",
                        "name": "Morning",
                        "template": "practice",
                        "targetWordIds": ["w-b"],
                    },
                ],
            }
        ],
    }


class AiPhasedTest(unittest.TestCase):
    def test_validate_outline_ok(self) -> None:
        self.assertEqual(validate_outline(_sample_outline()), [])

    def test_validate_outline_unknown_word(self) -> None:
        ol = _sample_outline()
        ol["units"][0]["lessons"][0]["targetWordIds"] = ["w-missing"]
        errs = validate_outline(ol)
        self.assertTrue(any("w-missing" in e for e in errs))

    def test_validate_outline_dup_lesson_id(self) -> None:
        ol = _sample_outline()
        ol["units"][0]["lessons"][1]["id"] = "u1-l1"
        errs = validate_outline(ol)
        self.assertTrue(any("重复" in e for e in errs))

    def test_outline_to_shell_locks_ids(self) -> None:
        shell = outline_to_section_shell(_sample_outline())
        self.assertEqual(shell["id"], "ai-phased-demo")
        self.assertEqual(len(shell["words"]), 2)
        lessons = shell["units"][0]["lessons"]
        self.assertEqual([l["id"] for l in lessons], ["u1-l1", "u1-l2"])
        self.assertEqual(lessons[0]["template"], "intro")
        self.assertIn("subLessons", lessons[0]["content"])
        self.assertIn("subLessons", lessons[1]["content"])

    def test_build_outline_prompt_contains_counts(self) -> None:
        spec = AiCourseSpec(topic="问候", unit_count=2, lessons_per_unit=3, level="A1")
        text = build_outline_prompt(spec)
        self.assertIn("单元数：2", text)
        self.assertIn("每单元课时：3", text)
        self.assertIn("教学法", text)

    def test_build_lesson_fill_instruction(self) -> None:
        ol = _sample_outline()
        lesson = ol["units"][0]["lessons"][0]
        instr = build_lesson_fill_instruction(ol, lesson, level="A1", language="Turkish")
        self.assertIn("u1-l1", instr)
        self.assertIn("w-a", instr)
        self.assertIn("Merhaba", instr)

    def test_iter_outline_lessons(self) -> None:
        pairs = iter_outline_lessons(_sample_outline())
        self.assertEqual(len(pairs), 2)
        self.assertEqual(pairs[0][0], "u1")
        self.assertEqual(pairs[0][1]["id"], "u1-l1")

    def test_fill_lessons_splices_and_locks_ids(self) -> None:
        ol = _sample_outline()
        cfg = AiApiConfig(base_url="http://x", api_key="k", model="m")
        spec = AiCourseSpec(level="A1", language="Turkish")

        def fake_transform(config, lesson, instruction, **kwargs):
            lid = lesson["id"]
            return {
                "id": "SHOULD_BE_OVERWRITTEN",
                "name": lesson.get("name"),
                "template": "mastery",  # should be locked back
                "content": {
                    "subLessons": [
                        {
                            "id": "sl1",
                            "stages": [
                                {
                                    "id": "st1",
                                    "items": [
                                        {
                                            "runtimeType": "showWord",
                                            "id": f"i-{lid}",
                                            "wordId": "w-a",
                                        }
                                    ],
                                }
                            ],
                        }
                    ]
                },
            }

        with patch(
            "src.backend.ai_phased.request_lesson_transform",
            side_effect=fake_transform,
        ):
            section = fill_lessons_from_outline(cfg, spec, ol)

        l1 = section["units"][0]["lessons"][0]
        self.assertEqual(l1["id"], "u1-l1")
        self.assertEqual(l1["template"], "intro")  # locked from outline
        items = l1["content"]["subLessons"][0]["stages"][0]["items"]
        self.assertEqual(items[0]["runtimeType"], "showWord")

        l2 = section["units"][0]["lessons"][1]
        self.assertEqual(l2["id"], "u1-l2")
        self.assertEqual(l2["template"], "practice")

    def test_request_course_fast_dispatches(self) -> None:
        cfg = AiApiConfig(base_url="http://x", api_key="k", model="m")
        spec = AiCourseSpec(topic="x")
        with patch(
            "src.backend.ai_phased.request_course_with_retry",
            return_value={"id": "fast"},
        ) as m:
            out = request_course(cfg, spec, mode="fast")
        self.assertEqual(out["id"], "fast")
        m.assert_called_once()

    def test_request_course_phased_dispatches(self) -> None:
        cfg = AiApiConfig(base_url="http://x", api_key="k", model="m")
        spec = AiCourseSpec(topic="x")
        with patch(
            "src.backend.ai_phased.request_course_phased",
            return_value={"id": "phased"},
        ) as m:
            out = request_course(cfg, spec, mode="phased")
        self.assertEqual(out["id"], "phased")
        m.assert_called_once()


if __name__ == "__main__":
    unittest.main()
