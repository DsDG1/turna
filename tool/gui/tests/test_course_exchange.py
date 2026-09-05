"""Unit tests for CourseExchangeService."""
from __future__ import annotations

import json
import shutil
import tempfile
import unittest
from pathlib import Path

from src.backend.course_exchange import CourseExchangeService


class DummyAdapter:
    def __init__(self):
        self.vocab = [
            {"id": "w-1", "term": "apple", "translation": "苹果"},
            {"id": "w-2", "term": "banana", "translation": "香蕉"},
        ]
        self.expressions = [
            {"id": "e-1", "source": "hello", "target": "你好"},
        ]
        self.grammar_points = [
            {"id": "g-1", "title": "Present Tense"},
        ]
        self.expressions_version = 1
        self.notified = False

    def notify_resources_changed(self):
        self.notified = True

    def _resource_list(self, row_type: str):
        if row_type == "vocab":
            return self.vocab
        if row_type == "expressions":
            return self.expressions
        if row_type == "grammar_points":
            return self.grammar_points
        return []

    def _set_resource_list(self, row_type: str, items):
        if row_type == "vocab":
            self.vocab = list(items)
        elif row_type == "expressions":
            self.expressions = list(items)
        elif row_type == "grammar_points":
            self.grammar_points = list(items)


class TestCourseExchangeService(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="test_exchange_"))

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_detect_duplicates(self):
        adapter = DummyAdapter()
        adapter.vocab.append({"id": "w-3", "term": "Apple", "translation": "苹果2"})
        adapter.expressions.append({"id": "e-2", "source": "apple", "target": "苹果3"})

        dupes = CourseExchangeService.detect_duplicates(adapter)
        self.assertEqual(len(dupes), 2)
        terms = [d["term"] for d in dupes]
        self.assertEqual(terms, ["apple", "apple"])

    def test_export_and_import_resource_pack(self):
        adapter = DummyAdapter()
        pack_path = self.tmp / "pack.json"
        exported = CourseExchangeService.export_resource_pack(adapter, pack_path)
        self.assertTrue(exported.is_file())

        data = json.loads(exported.read_text(encoding="utf-8"))
        self.assertIn("vocab", data)
        self.assertEqual(len(data["vocab"]), 2)

        # Merge mode
        new_adapter = DummyAdapter()
        new_adapter.vocab = []
        counts = CourseExchangeService.import_resource_pack(new_adapter, pack_path, replace=False)
        self.assertEqual(counts["vocab"], 2)
        self.assertEqual(len(new_adapter.vocab), 2)
        self.assertTrue(new_adapter.notified)

        # Replace mode
        new_adapter.vocab = [{"id": "old", "term": "old"}]
        counts = CourseExchangeService.import_resource_pack(new_adapter, pack_path, replace=True)
        self.assertEqual(counts["vocab"], 2)
        self.assertEqual(len(new_adapter.vocab), 2)
        self.assertFalse(any(v["id"] == "old" for v in new_adapter.vocab))

    def test_sync_resources_with_git(self):
        git_dir = self.tmp / "git_repo"
        git_dir.mkdir()

        adapter = DummyAdapter()
        result = CourseExchangeService.sync_resources_with_git(adapter, git_dir, "en")
        self.assertIn("vocab", result)
        self.assertTrue(adapter.notified)

        vocab_file = git_dir / "vocab.json"
        self.assertTrue(vocab_file.is_file())
        git_data = json.loads(vocab_file.read_text(encoding="utf-8"))
        self.assertEqual(len(git_data["words"]), 2)

    def test_export_and_import_csv(self):
        adapter = DummyAdapter()
        csv_path = self.tmp / "vocab.csv"
        CourseExchangeService.export_csv(adapter, "vocab", csv_path)
        self.assertTrue(csv_path.is_file())

        target_adapter = DummyAdapter()
        target_adapter.vocab = []
        problems = CourseExchangeService.import_csv(target_adapter, "vocab", csv_path)
        self.assertIsInstance(problems, list)
        self.assertEqual(len(target_adapter.vocab), 2)


if __name__ == "__main__":
    unittest.main()
