#!/usr/bin/env python3
from __future__ import annotations

import sys
import unittest
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT / "tool"))

from course_cli import merge_csv_rows  # type: ignore


class CsvPrefixTest(unittest.TestCase):
    def row(self, entry_id: str) -> dict[str, str]:
        return {"id": entry_id, "term": "su", "translation": "水"}

    def test_course_prefix_is_inferred_from_existing_ids(self) -> None:
        existing = [{"id": "nt-w-su", "term": "su", "translation": "水"}]
        _merged, problems = merge_csv_rows(
            "vocab", existing, [self.row("nt-w-yeni")], set()
        )
        self.assertEqual(problems, [])
        _merged, problems = merge_csv_rows(
            "vocab", existing, [self.row("w-yeni")], set()
        )
        self.assertEqual(len(problems), 1)
        self.assertIn("nt-w-", problems[0].message)

    def test_empty_course_does_not_invent_a_prefix_rule(self) -> None:
        _merged, problems = merge_csv_rows(
            "vocab", [], [self.row("fr-word")], set()
        )
        self.assertEqual(problems, [])


if __name__ == "__main__":
    unittest.main()
