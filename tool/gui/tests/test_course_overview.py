"""Tests for the course structure overview window (workshop2 P4)."""
from __future__ import annotations

import shutil
import sys
import tempfile
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from PySide6.QtWidgets import QApplication  # noqa: E402

from src.backend.course_adapter import CourseAdapter  # noqa: E402
from src.widgets.course_overview import CourseOverviewWindow, _LessonChip  # noqa: E402

_REPO = _GUI.parents[1]
COURSE_SRC = _REPO / "assets" / "courses" / "turkish"


def _load_adapter(tmp: Path) -> CourseAdapter:
    course_dir = tmp / "turkish"
    shutil.copytree(COURSE_SRC, course_dir)
    adapter = CourseAdapter()
    adapter.load(course_dir)
    return adapter


class CourseOverviewTest(unittest.TestCase):
    def setUp(self) -> None:
        _App._ensure()
        self.tmp = Path(tempfile.mkdtemp(prefix="varnamala_ov_"))
        self.adapter = _load_adapter(self.tmp)
        self.win = CourseOverviewWindow(self.adapter)

    def test_renders_sections_and_chips(self) -> None:
        chips = self.win.findChildren(_LessonChip)
        self.assertGreaterEqual(len(chips), 1)
        # Stats label mentions Sections / Units / Lessons.
        stats = self.win._stats_label.text()
        self.assertIn("Sections", stats)
        self.assertIn("Lessons", stats)

    def test_stats_counts_match_adapter(self) -> None:
        expected_lessons = sum(
            len(u.get("lessons", []))
            for s in self.adapter.sections
            for u in s.get("units", [])
        )
        chips = self.win.findChildren(_LessonChip)
        self.assertEqual(len(chips), expected_lessons)

    def test_chip_click_emits_lesson_selected(self) -> None:
        captured: list[str] = []
        self.win.lesson_selected.connect(lambda lid: captured.append(lid))
        chips = self.win.findChildren(_LessonChip)
        first = chips[0]
        first.click()
        self.assertEqual(len(captured), 1)
        self.assertTrue(captured[0])
        # The emitted id must correspond to a real lesson in the adapter.
        ids = {
            l["id"]
            for s in self.adapter.sections
            for u in s.get("units", [])
            for l in u.get("lessons", [])
        }
        self.assertIn(captured[0], ids)

    def test_refresh_after_mutation(self) -> None:
        before = len(self.win.findChildren(_LessonChip))
        # Mutate: add a lesson to the first unit via the adapter directly.
        for section in self.adapter.sections:
            for unit in section.get("units", []):
                unit.setdefault("lessons", []).append(
                    {"id": "ov-new", "name": "OV new", "template": "intro"}
                )
                break
            break
        self.win.refresh()
        after = len(self.win.findChildren(_LessonChip))
        self.assertEqual(after, before + 1)


class _App:
    _app: QApplication | None = None

    @classmethod
    def _ensure(cls) -> QApplication:
        if cls._app is None:
            cls._app = QApplication.instance() or QApplication([])
        return cls._app


if __name__ == "__main__":
    unittest.main()
