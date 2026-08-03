#!/usr/bin/env python3
"""Tests for course_cli validate scale gates and JSON output."""

from __future__ import annotations

import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tool"))

import course_cli  # noqa: E402


def _minimal_course(units: int, lessons_per_unit: int) -> Path:
    """Build a tiny valid-enough course tree for validate scale checks."""
    tmp = Path(tempfile.mkdtemp(prefix="turna-course-"))
    sections = tmp / "sections"
    sections.mkdir()
    units_json = []
    for u in range(units):
        lessons = []
        for li in range(lessons_per_unit):
            lessons.append(
                {
                    "id": f"l-{u}-{li}",
                    "name": f"L{li}",
                    "type": "normal",
                    "template": "legacy",
                    "content": {
                        "stages": [
                            {
                                "id": "st",
                                "name": "S",
                                "items": [
                                    {
                                        "runtimeType": "multipleChoice",
                                        "id": "mc",
                                        "prompt": "p",
                                        "options": ["a", "b"],
                                        "correctAnswer": "a",
                                    }
                                ],
                            }
                        ]
                    },
                }
            )
        units_json.append(
            {"id": f"u-{u}", "name": f"U{u}", "lessons": lessons}
        )
    section = {
        "id": "s-1",
        "name": "Section 1",
        "units": units_json,
    }
    (sections / "s1.json").write_text(
        json.dumps(section, indent=2) + "\n", encoding="utf-8"
    )
    (tmp / "index.json").write_text(
        json.dumps(
            {
                "version": 1,
                "language": "tr",
                "displayName": "Test",
                "sections": [
                    {
                        "id": "s-1",
                        "name": "Section 1",
                        "description": "",
                        "prerequisiteSectionIds": [],
                        "file": "sections/s1.json",
                    }
                ],
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    (tmp / "vocab.json").write_text(
        json.dumps({"words": []}, indent=2) + "\n", encoding="utf-8"
    )
    (tmp / "expressions.json").write_text(
        json.dumps({"version": 1, "expressions": []}, indent=2) + "\n",
        encoding="utf-8",
    )
    (tmp / "grammar_points.json").write_text(
        json.dumps({"grammarPoints": []}, indent=2) + "\n", encoding="utf-8"
    )
    return tmp


class CourseCliValidateTest(unittest.TestCase):
    def tearDown(self) -> None:
        # Clean any leftover temp dirs recorded on the instance.
        for attr in ("_tmp",):
            p = getattr(self, attr, None)
            if p and Path(p).exists():
                shutil.rmtree(p, ignore_errors=True)

    def test_scale_units_exceeded(self) -> None:
        self._tmp = _minimal_course(
            units=course_cli.MAX_UNITS_PER_SECTION + 1,
            lessons_per_unit=1,
        )
        code = course_cli.main(
            ["--course-dir", str(self._tmp), "validate", "--format", "json"]
        )
        self.assertEqual(code, 1)

    def test_scale_lessons_exceeded(self) -> None:
        self._tmp = _minimal_course(
            units=1,
            lessons_per_unit=course_cli.MAX_LESSONS_PER_UNIT + 1,
        )
        code = course_cli.main(
            ["--course-dir", str(self._tmp), "validate", "--format", "json"]
        )
        self.assertEqual(code, 1)

    def test_json_ok_for_small_course(self) -> None:
        self._tmp = _minimal_course(units=2, lessons_per_unit=3)
        # Capture stdout via main print — just check exit code here.
        code = course_cli.main(
            ["--course-dir", str(self._tmp), "validate", "--format", "json"]
        )
        self.assertEqual(code, 0)


if __name__ == "__main__":
    unittest.main()
