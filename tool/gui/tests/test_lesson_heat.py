"""O-01 lesson heat: quality × empty × error composite."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.overview_stats import (  # noqa: E402
    HEAT_CRITICAL,
    HEAT_HOT,
    HEAT_OK,
    HEAT_WARM,
    heat_tint_hex,
    lesson_heat,
)


class LessonHeatTest(unittest.TestCase):
    def test_healthy(self) -> None:
        h = lesson_heat(empty=False, error_count=0, quality_mean=0.9)
        self.assertEqual(h.level, HEAT_OK)
        self.assertEqual(h.reasons, ())
        self.assertIsNone(heat_tint_hex(h.level))

    def test_empty_only(self) -> None:
        h = lesson_heat(empty=True)
        self.assertEqual(h.level, HEAT_HOT)  # +2
        self.assertIn("空课", h.reasons)

    def test_errors(self) -> None:
        h = lesson_heat(error_count=1)
        self.assertEqual(h.level, HEAT_WARM)
        h2 = lesson_heat(error_count=5)
        self.assertEqual(h2.level, HEAT_HOT)  # cap +2

    def test_quality_warning(self) -> None:
        h = lesson_heat(quality_mean=0.5)
        self.assertGreaterEqual(h.level, HEAT_WARM)
        self.assertTrue(any("质量" in r for r in h.reasons))

    def test_quality_error_badge(self) -> None:
        h = lesson_heat(quality_badge="error")
        self.assertGreaterEqual(h.level, HEAT_HOT)

    def test_combined_clamped(self) -> None:
        h = lesson_heat(
            empty=True, error_count=3, quality_mean=0.2, quality_badge="error"
        )
        self.assertEqual(h.level, HEAT_CRITICAL)
        self.assertIsNotNone(heat_tint_hex(h.level))

    def test_tint_scale(self) -> None:
        self.assertIsNone(heat_tint_hex(0))
        self.assertEqual(heat_tint_hex(1), "#D97706")
        self.assertEqual(heat_tint_hex(2), "#EA580C")
        self.assertEqual(heat_tint_hex(3), "#DC2626")


if __name__ == "__main__":
    unittest.main()
