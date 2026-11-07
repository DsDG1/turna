#!/usr/bin/env python3
from __future__ import annotations

import sys
import unittest
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT / "tool"))

from course_cli import _validate_course, cmd_lint  # type: ignore
from course_quality_report import build_quality_report  # type: ignore


class Args:
    strict = True
    course_dir = PROJECT_ROOT / "test" / "fixtures" / "french_course"


class FrenchProductionPilotTest(unittest.TestCase):
    def test_real_second_language_passes_validate_and_strict_lint(self) -> None:
        self.assertEqual(_validate_course(Args.course_dir), [])
        self.assertEqual(cmd_lint(Args()), 0)

    def test_second_language_uses_the_same_quality_inventory(self) -> None:
        report = build_quality_report(Args.course_dir)
        self.assertEqual(len(report["words"]), 5)
        self.assertEqual(report["interaction_counts"]["showWord"], 5)
        self.assertEqual(report["playable_nodes"], 1)


if __name__ == "__main__":
    unittest.main()
