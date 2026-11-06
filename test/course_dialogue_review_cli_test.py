#!/usr/bin/env python3
from __future__ import annotations

import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT / "tool"))

from course_cli import cmd_validate  # type: ignore


class Args:
    def __init__(self, course_dir: Path) -> None:
        self.course_dir = course_dir
        self.format = "text"


class DialogueReviewValidationTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.course_dir = Path(self.temp.name) / "course"
        shutil.copytree(
            PROJECT_ROOT / "assets" / "courses" / "nouveau-turkish",
            self.course_dir,
        )
        self.section_path = self.course_dir / "sections" / "section1.json"

    def tearDown(self) -> None:
        self.temp.cleanup()

    def _write_section(self, section: dict) -> None:
        self.section_path.write_text(
            json.dumps(section, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )

    def _review_lesson(self, max_items: int) -> dict:
        return {
            "id": "review-test",
            "name": "Review",
            "type": "review",
            "template": "review",
            "content": {
                "reviewPolicy": {
                    "minItems": 1,
                    "maxItems": max_items,
                    "typeWeights": {"multipleChoice": 1.0},
                },
                "stages": [
                    {
                        "id": "review-stage",
                        "name": "Pool",
                        "items": [
                            {
                                "runtimeType": "multipleChoice",
                                "id": "review-q1",
                                "prompt": "Question",
                                "options": ["A", "B"],
                                "correctIndex": 0,
                            }
                        ],
                    }
                ],
            },
        }

    def test_real_dialogue_lesson_passes(self) -> None:
        self.assertEqual(cmd_validate(Args(self.course_dir)), 0)

    def test_unknown_dialogue_speaker_fails(self) -> None:
        section = json.loads(self.section_path.read_text(encoding="utf-8"))
        lesson = next(
            lesson
            for lesson in section["units"][0]["lessons"]
            if lesson["id"] == "nt-u1-l2-dialogue"
        )
        lesson["content"]["dialogueScene"]["turns"][0]["speakerId"] = "missing"
        self._write_section(section)
        self.assertEqual(cmd_validate(Args(self.course_dir)), 1)

    def test_bounded_review_pool_passes(self) -> None:
        section = json.loads(self.section_path.read_text(encoding="utf-8"))
        section["units"][0]["lessons"].append(self._review_lesson(1))
        self._write_section(section)
        self.assertEqual(cmd_validate(Args(self.course_dir)), 0)

    def test_review_sample_larger_than_pool_fails(self) -> None:
        section = json.loads(self.section_path.read_text(encoding="utf-8"))
        section["units"][0]["lessons"].append(self._review_lesson(2))
        self._write_section(section)
        self.assertEqual(cmd_validate(Args(self.course_dir)), 1)


if __name__ == "__main__":
    unittest.main()
