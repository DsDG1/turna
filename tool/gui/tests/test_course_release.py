"""Unit tests for CourseReleaseService."""
from __future__ import annotations

import unittest
from unittest.mock import MagicMock

from src.backend.course_release import CourseReleaseService


class DummyAdapter:
    def __init__(self):
        self.course_dir = None
        self.index = {"version": 1, "sections": [{"id": "s1"}]}
        self.sections = [{"id": "s1"}]
        self.vocab = [{"id": "w-1"}]
        self.expressions = [{"id": "e-1"}]
        self.grammar_points = [{"id": "g-1"}]
        self.expressions_version = 1
        self._hash_cache = {}
        self._snapshot = None

    def _refresh_hash_cache(self):
        self._hash_cache = {
            "index": CourseReleaseService.state_hash({"index": self.index}),
            "sections": CourseReleaseService.state_hash({"sections": self.sections}),
            "vocab": CourseReleaseService.state_hash({"vocab": self.vocab}),
            "expressions": CourseReleaseService.state_hash({"expressions": self.expressions}),
            "grammar_points": CourseReleaseService.state_hash({"grammar_points": self.grammar_points}),
        }

    def _deep_snapshot(self):
        return {
            "index": dict(self.index),
            "sections": list(self.sections),
            "vocab": list(self.vocab),
            "expressions": list(self.expressions),
            "grammar_points": list(self.grammar_points),
        }


class TestCourseReleaseService(unittest.TestCase):
    def test_state_hash(self):
        h1 = CourseReleaseService.state_hash({"a": 1, "b": [2, 3]})
        h2 = CourseReleaseService.state_hash({"b": [2, 3], "a": 1})
        self.assertEqual(h1, h2)
        self.assertIsInstance(h1, str)
        self.assertEqual(len(h1), 64)

    def test_detect_changes_no_changes(self):
        adapter = DummyAdapter()
        adapter._refresh_hash_cache()
        changes = CourseReleaseService.detect_changes(adapter)
        self.assertFalse(any(changes.values()))

    def test_detect_changes_when_mutated(self):
        adapter = DummyAdapter()
        adapter._refresh_hash_cache()
        adapter.vocab.append({"id": "w-2"})
        changes = CourseReleaseService.detect_changes(adapter)
        self.assertTrue(changes["vocab"])
        self.assertFalse(changes["index"])

    def test_version_bump_plan(self):
        adapter = DummyAdapter()
        adapter._refresh_hash_cache()

        # No changes
        plan = CourseReleaseService.version_bump_plan(adapter)
        self.assertEqual(plan, {})

        # Vocab changed -> expressions bumped
        adapter.vocab.append({"id": "w-2"})
        plan = CourseReleaseService.version_bump_plan(adapter)
        self.assertIn("expressions", plan)
        self.assertEqual(plan["expressions"], (1, 2))
        self.assertNotIn("index", plan)

        # Section changed -> index bumped
        adapter.sections.append({"id": "s2"})
        plan = CourseReleaseService.version_bump_plan(adapter)
        self.assertIn("index", plan)
        self.assertEqual(plan["index"], (1, 2))

    def test_apply_version_bump(self):
        adapter = DummyAdapter()
        plan = {"index": (1, 2), "expressions": (1, 2)}
        CourseReleaseService.apply_version_bump(adapter, plan)
        self.assertEqual(adapter.index["version"], 2)
        self.assertEqual(adapter.expressions_version, 2)

    def test_release_diff(self):
        adapter = DummyAdapter()
        adapter._snapshot = adapter._deep_snapshot()

        # Mutate
        adapter.vocab.append({"id": "w-2"})
        adapter.expressions.pop()

        diff = CourseReleaseService.release_diff(adapter)
        self.assertEqual(diff["vocab"]["added"], ["w-2"])
        self.assertEqual(diff["vocab"]["removed"], [])
        self.assertEqual(diff["vocab"]["unchanged_count"], 1)

        self.assertEqual(diff["expressions"]["added"], [])
        self.assertEqual(diff["expressions"]["removed"], ["e-1"])
        self.assertEqual(diff["expressions"]["unchanged_count"], 0)

    def test_release_report(self):
        adapter = DummyAdapter()
        adapter._snapshot = adapter._deep_snapshot()
        report = CourseReleaseService.release_report(adapter)
        self.assertIn("changes", report)
        self.assertIn("version_bump", report)
        self.assertIn("diff", report)
        self.assertIn("validation", report)


if __name__ == "__main__":
    unittest.main()
