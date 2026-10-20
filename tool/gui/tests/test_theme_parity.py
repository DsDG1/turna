"""Cross-language palette parity: tool/gui vs the Flutter app.

The brand palette has two homes: ``lib/core/theme.dart`` (the app) and
``src/theme_tokens.py`` (the creator tool). ``AGENTS.md`` §6 names them as
a single source of truth, and ADR 0033 locks the values — but nothing
asserted that they still matched. Changing a color on the Flutter side
silently left the GUI on the old one.

This module parses the Dart file and compares the brand colors. It is a
text-level check on purpose: the Dart file is not importable from Python,
and the values are plain ``Color(0xFF......)`` constants.
"""
from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

_REPO_ROOT = _GUI.parents[1]
_DART_THEME = _REPO_ROOT / "lib" / "core" / "theme.dart"

# Dart constant name -> Python constant name in src/theme_tokens.py.
_BRAND_PAIRS = {
    "brandNavy": "BRAND_NAVY",
    "brandTeal": "BRAND_TEAL",
    "brandTealLight": "BRAND_TEAL_LIGHT",
    "brandTealDark": "BRAND_TEAL_DARK",
    "brandSky": "BRAND_SKY",
    "brandReed": "BRAND_REED",
    "anatolianClay": "BRAND_CLAY",
    "warmSand": "BRAND_SAND",
}

# `static const Color brandTeal = Color(0xFF1F727E);`
_DART_COLOR_RE = re.compile(
    r"static\s+const\s+Color\s+(\w+)\s*=\s*Color\(0x([0-9A-Fa-f]{8})\)\s*;"
)
# `BRAND_TEAL = "#1F727E"`
_PY_COLOR_RE = re.compile(r"^(\w+)\s*=\s*\"#([0-9A-Fa-f]{6})\"")


def _dart_colors() -> dict[str, str]:
    if not _DART_THEME.is_file():
        return {}
    out: dict[str, str] = {}
    for name, argb in _DART_COLOR_RE.findall(_DART_THEME.read_text(encoding="utf-8")):
        out[name] = "#" + argb[2:].upper()
    return out


def _python_colors() -> dict[str, str]:
    import src.theme_tokens as tokens

    out: dict[str, str] = {}
    for name in dir(tokens):
        value = getattr(tokens, name)
        if isinstance(value, str) and name.startswith("BRAND_"):
            match = _PY_COLOR_RE.match(f"{name} = {value!r}".replace("'", '"'))
            if match:
                out[match.group(1)] = "#" + match.group(2).upper()
    return out


class ThemeParityTest(unittest.TestCase):
    """The GUI palette must match the app palette, color by color."""

    def test_dart_theme_file_exists(self) -> None:
        # A missing file would make every other assertion vacuously pass.
        self.assertTrue(
            _DART_THEME.is_file(),
            f"missing {_DART_THEME} — the parity check would be meaningless",
        )

    def test_every_brand_color_matches(self) -> None:
        dart = _dart_colors()
        py = _python_colors()
        self.assertTrue(dart, f"no colors parsed from {_DART_THEME}")
        mismatches: list[str] = []
        for dart_name, py_name in _BRAND_PAIRS.items():
            self.assertIn(
                dart_name, dart, f"{dart_name} not found in {_DART_THEME.name}"
            )
            self.assertIn(
                py_name, py, f"{py_name} not found in theme_tokens.py"
            )
            if dart[dart_name] != py[py_name]:
                mismatches.append(
                    f"{dart_name}: dart={dart[dart_name]} py={py[py_name]}"
                )
        self.assertEqual(
            [], mismatches, "palette drift between Flutter and the GUI"
        )

    def test_brand_color_set_is_complete(self) -> None:
        """Every BRAND_* constant in Python must have a Dart counterpart.

        A new brand color added on one side only is exactly the drift this
        test exists to catch.
        """
        dart = _dart_colors()
        py = _python_colors()
        dart_names = set(dart.values())
        orphan = {
            name: value
            for name, value in py.items()
            if value not in dart_names
        }
        self.assertEqual(
            {},
            orphan,
            "Python brand colors with no Flutter counterpart "
            "(add the color to lib/core/theme.dart or drop it here)",
        )


if __name__ == "__main__":
    unittest.main()
