"""Unit tests for CourseIoService."""
import shutil
import tempfile
import unittest
from pathlib import Path
from unittest.mock import MagicMock

from src.backend.course_io import CourseIoService, SaveResult


class FakeAdapter:
    def __init__(self, course_dir=None):
        self.course_dir = course_dir
        self.index = {"language": "en", "sections": []}
        self.sections = [{"id": "s1"}]
        self.vocab = [{"id": "w1"}]
        self.expressions = [{"id": "e1"}]
        self.grammar_points = [{"id": "g1"}]
        self._snapshot = None
        self.invalidate_node_index = MagicMock()


class TestCourseIoService(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="test_course_io_"))

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_deep_snapshot_and_restore(self):
        adapter = FakeAdapter(self.tmp)
        snap = CourseIoService.deep_snapshot(adapter)

        # Mutate adapter
        adapter.index["language"] = "tr"
        adapter.sections.append({"id": "s2"})
        adapter.vocab.clear()

        # Verify snapshot remained untouched
        self.assertEqual(snap["index"]["language"], "en")
        self.assertEqual(len(snap["sections"]), 1)
        self.assertEqual(len(snap["vocab"]), 1)

        # Restore
        CourseIoService.restore_from(adapter, snap)
        self.assertEqual(adapter.index["language"], "en")
        self.assertEqual(len(adapter.sections), 1)
        self.assertEqual(len(adapter.vocab), 1)
        adapter.invalidate_node_index.assert_called_once()

    def test_prune_old_backups(self):
        root = self.tmp / "backups"
        root.mkdir()
        # Create 5 backup directories
        for i in range(5):
            d = root / f"2026090{i}-120000-000000"
            d.mkdir()

        CourseIoService.prune_old_backups(root, keep=3)
        remaining = sorted([p.name for p in root.iterdir() if p.is_dir()])
        self.assertEqual(len(remaining), 3)
        self.assertEqual(remaining, [
            "20260902-120000-000000",
            "20260903-120000-000000",
            "20260904-120000-000000",
        ])

    def test_replace_course_files_with(self):
        course = self.tmp / "course"
        (course / "sections").mkdir(parents=True)
        (course / "sections" / "s1.json").write_text("s1", encoding="utf-8")
        (course / "sections" / "old_s2.json").write_text("old", encoding="utf-8")

        staging = self.tmp / "staging"
        (staging / "sections").mkdir(parents=True)
        (staging / "sections" / "s1.json").write_text("s1_updated", encoding="utf-8")

        CourseIoService.replace_course_files_with(staging, course)

        self.assertEqual((course / "sections" / "s1.json").read_text(encoding="utf-8"), "s1_updated")
        self.assertFalse((course / "sections" / "old_s2.json").exists())

    def test_save_returns_error_when_no_course_dir(self):
        adapter = FakeAdapter(None)
        res = CourseIoService.save(adapter)
        self.assertFalse(res.ok)
        self.assertIn("未加载课程目录", res.message)

    def test_backup_skips_dot_directories(self):
        """A2 复审回归：save 的 .turna-save-* 暂存目录建在课程目录内，
        备份不得把它收编进去（否则每个备份体积翻倍、还原带回垃圾目录）。"""
        import tempfile

        src = Path(tempfile.mkdtemp(prefix="turna_backup_test_"))
        self.addCleanup(lambda: shutil.rmtree(src, ignore_errors=True))
        (src / "sections").mkdir()
        (src / "index.json").write_text("{}", encoding="utf-8")
        (src / "sections" / "s1.json").write_text("s1", encoding="utf-8")
        staging = src / ".turna-save-abc123"
        (staging / "sections").mkdir(parents=True)
        (staging / "sections" / "s1.json").write_text("stale", encoding="utf-8")
        (staging / "index.json").write_text("{}", encoding="utf-8")

        dst = src / ".varnamala-backup" / "20260928-120000-000000"
        CourseIoService.backup_json_files(src, dst)

        backed = sorted(
            str(p.relative_to(dst)).replace("\\", "/") for p in dst.rglob("*.json")
        )
        self.assertEqual(backed, ["index.json", "sections/s1.json"])
        # And the staged copy must not have overwritten the real file.
        self.assertEqual(
            (dst / "sections" / "s1.json").read_text(encoding="utf-8"), "s1"
        )


if __name__ == "__main__":
    unittest.main()
