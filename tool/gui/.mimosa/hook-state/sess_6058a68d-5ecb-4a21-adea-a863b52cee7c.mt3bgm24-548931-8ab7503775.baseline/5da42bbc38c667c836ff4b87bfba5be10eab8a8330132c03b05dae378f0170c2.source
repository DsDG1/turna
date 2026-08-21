"""Tests for grounded pool summary and draft coverage helpers."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.grounded_stats import (  # noqa: E402
    count_pool_kinds,
    draft_coverage,
    format_coverage_line,
    format_pool_summary,
)


class GroundedStatsTest(unittest.TestCase):
    def test_count_pool_kinds(self) -> None:
        pool = [
            {"id": "w1", "_kind": "word", "term": "a"},
            {"id": "e1", "_kind": "expression", "term": "b"},
            {"id": "g1", "_kind": "grammar", "title": "c"},
        ]
        c = count_pool_kinds(pool)
        self.assertEqual(c["words"], 1)
        self.assertEqual(c["expressions"], 1)
        self.assertEqual(c["grammar"], 1)

    def test_format_pool_summary_empty(self) -> None:
        self.assertIn("空", format_pool_summary([]))

    def test_format_pool_summary_focused(self) -> None:
        text = format_pool_summary(
            [{"_kind": "word", "id": "w1"}], focused=True
        )
        self.assertIn("聚焦", text)
        self.assertIn("1 词", text)

    def test_draft_coverage_in_pool(self) -> None:
        pool = [{"id": "w1", "_kind": "word"}, {"id": "w2", "_kind": "word"}]
        draft = {
            "words": [
                {"id": "w1", "term": "a"},
                {"id": "w-new", "term": "x", "tags": ["new"]},
            ],
            "expressions": [],
            "grammarPoints": [],
        }
        stats = draft_coverage(draft, pool)
        self.assertEqual(stats["in_pool"], 1)
        self.assertEqual(stats["outside_pool"], 1)
        self.assertEqual(stats["new_tagged"], 1)
        self.assertAlmostEqual(stats["coverage_ratio"], 0.5)

    def test_format_coverage_line(self) -> None:
        line = format_coverage_line(
            {
                "pool_size": 2,
                "draft_words": 2,
                "draft_expressions": 0,
                "draft_grammar": 0,
                "in_pool": 1,
                "outside_pool": 1,
                "new_tagged": 1,
                "coverage_ratio": 0.5,
            }
        )
        self.assertIn("50%", line)
        self.assertIn("池外", line)
        self.assertIn("new", line)


if __name__ == "__main__":
    unittest.main()
