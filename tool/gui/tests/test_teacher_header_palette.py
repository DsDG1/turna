"""T20: the teacher header must follow the active palette.

The breadcrumb and 课型 badge used module-level dark-palette constants
(#9CA3AF text on a #1E3A8A pill). Switching to the light theme left dark
chrome on a white panel — unreadable breadcrumb, and a badge whose accent
no longer matched the rest of the app.
"""
from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.teacher.shell_header import breadcrumb_label, template_badge
from tests._qtapp import _App

_SECTION = {"name": "S1", "id": "s1"}
_UNIT = {"name": "U1", "id": "u1"}
_LESSON = {"name": "L1", "id": "l1", "template": "listening"}

_DARK = {"text_secondary": "#B9CCC0", "accent": "#1F727E", "text_on_accent": "#FFF"}
_LIGHT = {"text_secondary": "#4A5568", "accent": "#1F727E", "text_on_accent": "#FFF"}
_HC_LIGHT = {
    "text_secondary": "#1A1A1A",
    "accent": "#145A64",
    "text_on_accent": "#FFF",
}


class HeaderPaletteTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        _App.get()

    def test_breadcrumb_follows_the_palette(self) -> None:
        for palette in (_DARK, _LIGHT, _HC_LIGHT):
            with self.subTest(palette=palette["text_secondary"]), patch(
                "src.teacher.shell_header.current_palette", return_value=palette
            ):
                label = breadcrumb_label(_SECTION, _UNIT, _LESSON)
                self.assertIn(palette["text_secondary"], label.styleSheet())

    def test_badge_follows_the_palette(self) -> None:
        for palette in (_DARK, _LIGHT, _HC_LIGHT):
            with self.subTest(accent=palette["accent"]), patch(
                "src.teacher.shell_header.current_palette", return_value=palette
            ):
                badge = template_badge(_LESSON)
                sheet = badge.styleSheet()
                self.assertIn(palette["accent"], sheet)
                self.assertIn(palette["text_on_accent"], sheet)

    def test_no_hardcoded_dark_constants_in_the_source(self) -> None:
        # The old values must not reappear as literals.
        src = (_GUI / "src" / "teacher" / "shell_header.py").read_text(
            encoding="utf-8"
        )
        for legacy in ("#9CA3AF", "#60A5FA", "#1E3A8A"):
            self.assertNotIn(legacy, src, f"{legacy} is the pre-T20 constant")

    def test_palette_is_read_per_call_not_cached(self) -> None:
        # A theme switch must be picked up by rebuilding the chrome.
        first = template_badge(_LESSON)
        with patch(
            "src.teacher.shell_header.current_palette", return_value=_HC_LIGHT
        ):
            second = template_badge(_LESSON)
        self.assertNotEqual(first.styleSheet(), second.styleSheet())
        self.assertIn(_HC_LIGHT["accent"], second.styleSheet())


if __name__ == "__main__":
    unittest.main()
