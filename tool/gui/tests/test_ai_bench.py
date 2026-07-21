"""Unit tests for ai_bench hygiene probes (aiEnhance Phase 0)."""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.ai_bench import (
    count_mcq_duplicate_options,
    count_needs_review,
    count_placeholders,
    find_dangling_refs,
    format_hygiene_line,
    score_section_hygiene,
)

_GOLDENS = Path(__file__).resolve().parent / "ai_goldens"


def _load(name: str) -> dict:
    return json.loads((_GOLDENS / name).read_text(encoding="utf-8"))


class TestAiBenchGoldens(unittest.TestCase):
    def test_clean_greetings_ok(self) -> None:
        section = _load("a1_greetings_clean.json")
        m = score_section_hygiene(section)
        self.assertTrue(m["ok"])
        self.assertEqual(m["placeholder_count"], 0)
        self.assertEqual(m["needs_review_count"], 0)
        self.assertEqual(m["dangling_ref_count"], 0)
        self.assertEqual(m["lesson_count"], 1)
        self.assertEqual(m["word_count"], 2)

    def test_placeholders_counted(self) -> None:
        section = _load("a1_with_placeholders.json")
        self.assertEqual(count_placeholders(section), 2)
        self.assertEqual(count_needs_review(section), 2)
        m = score_section_hygiene(section)
        self.assertEqual(m["placeholder_count"], 2)
        self.assertEqual(m["needs_review_count"], 2)

    def test_dangling_refs(self) -> None:
        section = _load("a1_dangling_refs.json")
        dangling = find_dangling_refs(section)
        self.assertEqual(len(dangling), 1)
        self.assertIn("w-not-defined", dangling[0])
        m = score_section_hygiene(section)
        self.assertFalse(m["ok"])
        self.assertEqual(m["dangling_ref_count"], 1)

    def test_grounded_coverage(self) -> None:
        data = _load("a1_grounded_pool.json")
        m = score_section_hygiene(data["section"], resource_pool=data["pool"])
        self.assertEqual(m["in_pool"], 1)
        self.assertEqual(m["outside_pool"], 1)
        self.assertAlmostEqual(m["coverage_ratio"], 0.5)

    def test_listening_shape(self) -> None:
        section = _load("listening_phases.json")
        m = score_section_hygiene(section)
        self.assertTrue(m["has_units"])
        self.assertEqual(m["dangling_ref_count"], 0)
        self.assertEqual(m["lesson_count"], 1)

    def test_mcq_dup_options(self) -> None:
        section = _load("mcq_dup_options.json")
        self.assertEqual(count_mcq_duplicate_options(section), 1)
        m = score_section_hygiene(section)
        self.assertEqual(m["mcq_dup_options"], 1)

    def test_structural_errors_counted(self) -> None:
        section = _load("a1_greetings_clean.json")
        m = score_section_hygiene(
            section,
            structural_errors=[
                {"level": "warning", "message": "soft"},
                {"level": "error", "message": "hard"},
            ],
        )
        self.assertEqual(m["error_count"], 1)
        self.assertFalse(m["ok"])

    def test_format_hygiene_line(self) -> None:
        line = format_hygiene_line(
            {
                "error_count": 0,
                "placeholder_count": 1,
                "needs_review_count": 2,
                "dangling_ref_count": 0,
                "lesson_count": 3,
                "coverage_ratio": 0.5,
            }
        )
        self.assertIn("待补=1", line)
        self.assertIn("pool=50%", line)

    def test_none_section(self) -> None:
        m = score_section_hygiene(None)
        self.assertFalse(m["ok"])
        self.assertEqual(m["error_count"], 1)


if __name__ == "__main__":
    unittest.main()
