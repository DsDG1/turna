from __future__ import annotations

import unittest
from pathlib import Path

from src.backend.course_adapter import CourseAdapter
from src.backend.course_preview.course import load_course_bundle, validate_course_bundle

_FIXTURE = Path(__file__).resolve().parents[3] / "test" / "fixtures" / "french_course"


class MultilingualProductionTest(unittest.TestCase):
    def test_french_uses_gui_validation_and_web_preview_bundle(self) -> None:
        adapter = CourseAdapter()
        adapter.load(_FIXTURE)
        self.assertEqual(len(adapter.vocab), 5)
        self.assertEqual(len(adapter.expressions), 3)
        report = adapter.release_report()
        self.assertTrue(report["validation"]["ok"], report["validation"])
        self.assertEqual(report["version_bump"], {})

        bundle = load_course_bundle(_FIXTURE, course_id="french-pilot")
        validated = validate_course_bundle(bundle)
        self.assertEqual(validated["language"], "fr")
        self.assertEqual(validated["entries"][0]["section_id"], "fr-section1")


if __name__ == "__main__":
    unittest.main()
