"""Every referenced icon name must exist in the vendored SVG set.

``icon("chevron-right")`` silently renders nothing when the SVG is missing
— no exception, just an invisible button. That is easy to ship and hard to
notice, so the names are checked statically here.

The vendored icons are a subset of Lucide, so this test also keeps the
"which icons do we actually use" question answerable: adding a name that
is not vendored is a build-time error, not a runtime surprise.
"""
from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

_SVG_DIR = _GUI / "src" / "icons" / "svg"

# icon("name", ...) / pixmap("name", ...)
_ICON_CALL_RE = re.compile(r"""\b(?:icon|pixmap)\s*\(\s*["']([a-z0-9][a-z0-9\-]*)["']""")


def _available() -> set[str]:
    return {p.stem for p in _SVG_DIR.glob("*.svg")}


def _referenced() -> dict[str, list[str]]:
    found: dict[str, list[str]] = {}
    for path in sorted((_GUI / "src").rglob("*.py")):
        text = path.read_text(encoding="utf-8", errors="ignore")
        for m in _ICON_CALL_RE.finditer(text):
            line = text[: m.start()].count("\n") + 1
            rel = path.relative_to(_GUI).as_posix()
            found.setdefault(m.group(1), []).append(f"{rel}:{line}")
    return found


class IconNameTest(unittest.TestCase):
    def test_svg_dir_is_not_empty(self) -> None:
        self.assertTrue(
            _SVG_DIR.is_dir() and _available(),
            f"no vendored icons found in {_SVG_DIR}",
        )

    def test_every_referenced_icon_exists(self) -> None:
        available = _available()
        missing = {
            name: refs
            for name, refs in _referenced().items()
            if name not in available
        }
        self.assertEqual(
            {},
            missing,
            "referenced icons with no vendored SVG (they render as nothing): "
            + "; ".join(
                f"{name} -> {', '.join(refs[:3])}" for name, refs in sorted(missing.items())
            ),
        )


if __name__ == "__main__":
    unittest.main()
