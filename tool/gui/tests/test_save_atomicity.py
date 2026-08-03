"""Atomic save and rollback tests for CourseAdapter."""
from __future__ import annotations

import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))
from tests._course_fixture import copy_turkish_course  # noqa: E402

from src.backend.course_adapter import CourseAdapter  # noqa: E402


class SaveAtomicityTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="turna_atomic_"))
        self.course_dir = self.tmp / "turkish"
        copy_turkish_course(self.course_dir)

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_save_creates_backup_directory(self) -> None:
        adapter = CourseAdapter()
        adapter.load(self.course_dir)
        adapter.sections[0]["name"] = "Edited Section"
        result = adapter.save()
        self.assertTrue(result.ok, f"save failed: {result.message}")

        backups = list((self.course_dir / ".varnamala-backup").iterdir())
        self.assertEqual(len(backups), 1)
        backup_dir = backups[0]
        self.assertTrue((backup_dir / "index.json").exists())

    def test_backup_excludes_old_backups(self) -> None:
        adapter = CourseAdapter()
        adapter.load(self.course_dir)
        adapter.sections[0]["name"] = "Edit 1"
        self.assertTrue(adapter.save().ok)
        adapter.sections[0]["name"] = "Edit 2"
        self.assertTrue(adapter.save().ok)

        backups = sorted((self.course_dir / ".varnamala-backup").iterdir())
        self.assertEqual(len(backups), 2)
        # The second backup must not recursively contain the first backup.
        nested_backups = list(backups[1].rglob(".varnamala-backup"))
        self.assertEqual(nested_backups, [])

    def test_rollback_keeps_original_files_on_replace_failure(self) -> None:
        adapter = CourseAdapter()
        adapter.load(self.course_dir)
        original_index = adapter.index.get("displayName")
        adapter.index["displayName"] = "Should Not Persist"

        # Simulate a failure during the atomic file-replacement step
        # (``_replace_course_files_with``). Previously this test counted
        # ``os.replace`` calls across the whole save, but now ``save_json``
        # itself does an atomic rename via ``os.replace`` per file, so a
        # call-count threshold is fragile. Patch the replacement step
        # directly so the failure lands exactly where we want it.
        def boom(tmp_dir, course_dir):
            raise OSError("simulated disk failure")

        with patch.object(CourseAdapter, "_replace_course_files_with", side_effect=boom):
            result = adapter.save()

        self.assertFalse(result.ok)
        self.assertIn("simulated disk failure", result.message)

        # Original files must still contain the original value.
        reloaded = CourseAdapter()
        reloaded.load(self.course_dir)
        self.assertEqual(reloaded.index.get("displayName"), original_index)

    def test_rollback_restores_memory_on_validation_failure(self) -> None:
        adapter = CourseAdapter()
        adapter.load(self.course_dir)
        lesson = adapter.sections[0]["units"][0]["lessons"][0]
        lid = lesson["id"]
        original_content = lesson["content"]
        lesson["content"] = {}
        result = adapter.save()
        self.assertFalse(result.ok)
        self.assertGreater(len(result.errors), 0)
        self.assertEqual(adapter.find_lesson(lid)[2]["content"], original_content)


if __name__ == "__main__":
    unittest.main()
