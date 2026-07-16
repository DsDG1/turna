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

from src.backend.course_adapter import CourseAdapter  # noqa: E402

_REPO = _GUI.parents[1]
COURSE_SRC = _REPO / "assets" / "courses" / "turkish"


class SaveAtomicityTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="varnamala_atomic_"))
        self.course_dir = self.tmp / "turkish"
        shutil.copytree(COURSE_SRC, self.course_dir)

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

        calls = {"count": 0}

        def failing_replace(src: str, dst: str) -> None:
            calls["count"] += 1
            if calls["count"] >= 2:
                raise OSError("simulated disk failure")
            return shutil.move(src, dst)

        with patch("src.backend.course_adapter.os.replace", side_effect=failing_replace):
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
