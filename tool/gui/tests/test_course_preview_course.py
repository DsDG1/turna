from __future__ import annotations

import copy
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

_GUI = Path(__file__).resolve().parents[1]
_REPO = _GUI.parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.course_preview import cli
from src.backend.course_preview.course import load_course_bundle
from src.backend.course_preview.document import build_document
from src.backend.course_preview.store import PreviewStore


class CourseBundleTest(unittest.TestCase):
    def test_real_nouveau_turkish_loads_words_and_placeholders(self) -> None:
        bundle = load_course_bundle(_REPO / "assets" / "courses" / "nouveau-turkish")

        self.assertEqual(bundle["course_id"], "nouveau-turkish")
        self.assertEqual(bundle["title"], "Türkçe öğren")
        self.assertEqual(len(bundle["entries"]), 8)
        self.assertEqual(
            [entry["section_id"] for entry in bundle["entries"] if entry["section"] is None],
            [f"nt-s{number}" for number in range(2, 9)],
        )
        document = build_document(bundle["entries"][0]["section"])
        self.assertEqual(document.lessons[0].items[0].prompt, "Türkçe — 土耳其语")
        self.assertEqual(document.item_count, 26)

    def test_section_path_cannot_escape_course_directory(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            course = root / "course"
            course.mkdir()
            (root / "outside.json").write_text('{"id":"s1","units":[]}', encoding="utf-8")
            (course / "index.json").write_text(
                '{"sections":[{"id":"s1","file":"../outside.json"}]}',
                encoding="utf-8",
            )

            with self.assertRaisesRegex(ValueError, "越出课程目录"):
                load_course_bundle(course)

    def test_index_and_section_ids_must_match(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            course = Path(temporary)
            (course / "sections").mkdir()
            (course / "index.json").write_text(
                '{"sections":[{"id":"s1","file":"sections/s1.json"}]}',
                encoding="utf-8",
            )
            (course / "sections" / "s1.json").write_text(
                '{"id":"other","units":[]}',
                encoding="utf-8",
            )

            with self.assertRaisesRegex(ValueError, "id 与文件 id 不一致"):
                load_course_bundle(course)


class CoursePublicationTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.store = PreviewStore(self.tmp.name)
        self.bundle = load_course_bundle(_REPO / "assets" / "courses" / "nouveau-turkish")

    def test_publish_reuses_urls_and_only_increments_changed_sections(self) -> None:
        first = self.store.publish_course(self.bundle)
        second = self.store.publish_course(self.bundle)
        changed = copy.deepcopy(self.bundle)
        changed["entries"][0]["section"]["name"] = "起步 · 第二版"
        third = self.store.publish_course(changed)

        first_entry = first["entries"][0]
        second_entry = second["entries"][0]
        third_entry = third["entries"][0]
        self.assertTrue(second["unchanged"])
        self.assertEqual(second["updated_at"], first["updated_at"])
        self.assertEqual(second_entry["preview_id"], first_entry["preview_id"])
        self.assertEqual(second_entry["current_revision"], 1)
        self.assertEqual(third_entry["preview_id"], first_entry["preview_id"])
        self.assertEqual(third_entry["current_revision"], 2)
        self.assertEqual(self.store.meta(first_entry["preview_id"])["course_id"], "nouveau-turkish")
        self.assertEqual(
            sum(entry["status"] == "placeholder" for entry in third["entries"]),
            7,
        )

    def test_removed_section_leaves_course_but_keeps_feedback_history(self) -> None:
        first = self.store.publish_course(self.bundle)
        preview_id = first["entries"][0]["preview_id"]
        changed = copy.deepcopy(self.bundle)
        changed["entries"] = changed["entries"][1:]

        second = self.store.publish_course(changed)
        restored = self.store.publish_course(self.bundle)

        self.assertNotIn(
            "nt-s1",
            {entry["section_id"] for entry in second["entries"]},
        )
        self.assertEqual(self.store.meta(preview_id)["current_revision"], 1)
        self.assertEqual(restored["entries"][0]["preview_id"], preview_id)
        self.assertEqual(restored["entries"][0]["current_revision"], 1)
        self.assertFalse(second["unchanged"])

    def test_invalid_bundle_does_not_publish_any_section(self) -> None:
        invalid = copy.deepcopy(self.bundle)
        invalid["entries"][1]["section"] = {"id": "nt-s2", "units": []}

        with self.assertRaises(ValueError):
            self.store.publish_course(invalid)

        self.assertEqual(self.store.courses(), [])
        self.assertFalse(any(self.store.root.glob("*/meta.json")))


class CourseServerCliTest(unittest.TestCase):
    def test_publish_course_returns_course_and_section_urls(self) -> None:
        bundle = load_course_bundle(_REPO / "assets" / "courses" / "nouveau-turkish")
        with tempfile.TemporaryDirectory() as temporary:
            stdout = io.StringIO()
            with (
                patch("sys.stdin", io.StringIO(json.dumps(bundle))),
                patch("sys.stdout", stdout),
            ):
                code = cli.main(
                    [
                        "--root",
                        temporary,
                        "--public-base",
                        "https://example.test/course-preview",
                        "publish-course",
                    ]
                )

        result = json.loads(stdout.getvalue())
        self.assertEqual(code, 0)
        self.assertEqual(
            result["url"],
            "https://example.test/course-preview/c/nouveau-turkish/",
        )
        self.assertTrue(result["publications"][0]["url"].endswith("/"))
        self.assertIn("/p/", result["publications"][0]["url"])
        self.assertNotIn("url", result["publications"][1])


if __name__ == "__main__":
    unittest.main()
