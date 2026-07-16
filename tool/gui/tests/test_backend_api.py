"""Tests for the stable backend API layer (src.backend.api)."""
from __future__ import annotations

import shutil
import sys
import tempfile
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend import api  # noqa: E402

_REPO = _GUI.parents[1]
COURSE_SRC = _REPO / "assets" / "courses" / "turkish"


class BackendApiTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="varnamala_api_"))
        self.course_dir = self.tmp / "turkish"
        shutil.copytree(COURSE_SRC, self.course_dir)

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_load_course_returns_bundle(self) -> None:
        bundle = api.load_course(self.course_dir)
        self.assertEqual(bundle.index.get("language"), "tr")
        self.assertGreaterEqual(len(bundle.sections), 1)
        self.assertIsInstance(bundle.vocab, list)
        self.assertIsInstance(bundle.expressions, list)
        self.assertIsInstance(bundle.grammar_points, list)
        self.assertGreaterEqual(bundle.expressions_version, 1)

    def test_validate_course_dir_ok(self) -> None:
        result = api.validate_course_dir(self.course_dir)
        self.assertIsInstance(result.ok, bool)
        self.assertIsInstance(result.problems, list)
        for p in result.problems:
            self.assertIn(p.level, ("error", "warning"))

    def test_lint_course_dir_returns_problems(self) -> None:
        problems = api.lint_course_dir(self.course_dir)
        self.assertIsInstance(problems, list)
        for p in problems:
            self.assertIn(p.level, ("error", "warning"))

    def test_export_import_csv_rows_round_trip(self) -> None:
        bundle = api.load_course(self.course_dir)
        headers, rows = api.export_csv_rows("vocab", bundle.vocab)
        self.assertIn("id", headers)
        self.assertIn("term", headers)
        self.assertTrue(all("id" in r for r in rows))

        merged, problems = api.import_csv_rows(
            "vocab", bundle.vocab, rows, {e["id"] for e in bundle.expressions}
        )
        self.assertEqual(problems, [])
        self.assertEqual(len(merged), len(bundle.vocab))

    def test_validate_lesson_catches_dangling_word_id(self) -> None:
        lesson = {
            "id": "l-test",
            "template": "intro",
            "content": {
                "subLessons": [
                    {
                        "id": "sl-test",
                        "stages": [
                            {
                                "id": "st-test",
                                "items": [
                                    {
                                        "runtimeType": "showWord",
                                        "id": "sw-test",
                                        "wordId": "w-does-not-exist",
                                    }
                                ],
                            }
                        ],
                    }
                ]
            },
        }
        problems = api.validate_lesson(lesson, {"w-merhaba"}, set(), set())
        self.assertTrue(
            any("wordId" in p.message or "missing" in p.message for p in problems),
            f"expected dangling wordId error, got {problems}",
        )

    def test_build_audio_manifest_rows_returns_list(self) -> None:
        rows = api.build_audio_manifest_rows(self.course_dir)
        self.assertIsInstance(rows, list)
        for r in rows:
            self.assertIn("asset_id", r)
            self.assertIn("status", r)
            self.assertIn(r["status"], ("present", "missing"))

    def test_save_and_load_course_bundle(self) -> None:
        bundle = api.load_course(self.course_dir)
        bundle.index["displayName"] = "Updated Name"
        target = self.tmp / "course-copy"

        def section_path(sid: str) -> Path:
            return target / "sections" / f"{sid}.json"

        api.save_course_bundle(bundle, target, section_path)
        self.assertTrue((target / "index.json").exists())
        self.assertTrue((target / "vocab.json").exists())
        self.assertTrue((target / "expressions.json").exists())
        self.assertTrue((target / "grammar_points.json").exists())

        reloaded = api.load_course(target)
        self.assertEqual(reloaded.index.get("displayName"), "Updated Name")


if __name__ == "__main__":
    unittest.main()
