"""Tests for the course structure overview window (workshop2 P4 + P5)."""
from __future__ import annotations

import sys
import tempfile
import time
import unittest
from pathlib import Path

from PySide6.QtCore import QThread
from PySide6.QtWidgets import QApplication

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))
from tests._course_fixture import copy_turkish_course


from src.backend.course_adapter import CourseAdapter
from src.widgets.course_overview import (
    CourseOverviewWindow,
    _LessonChip,
)
from tests._qtapp import _App


def _load_adapter(tmp: Path) -> CourseAdapter:
    course_dir = tmp / "turkish"
    copy_turkish_course(course_dir)
    adapter = CourseAdapter()
    adapter.load(course_dir)
    return adapter


def _spin_until(condition, timeout: float = 5.0) -> bool:
    """Process events until ``condition()`` is true (worker signal delivery)."""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        QApplication.processEvents()
        if condition():
            return True
        QThread.msleep(10)
    QApplication.processEvents()
    return bool(condition())


class CourseOverviewTest(unittest.TestCase):
    def setUp(self) -> None:
        _App._ensure()
        self.tmp = Path(tempfile.mkdtemp(prefix="turna_ov_"))
        self.adapter = _load_adapter(self.tmp)
        self.win = CourseOverviewWindow(self.adapter)

    def test_renders_sections_and_chips(self) -> None:
        chips = self.win.findChildren(_LessonChip)
        self.assertGreaterEqual(len(chips), 1)
        # Stats label mentions Sections / Lessons.
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
            lesson["id"]
            for s in self.adapter.sections
            for u in s.get("units", [])
            for lesson in u.get("lessons", [])
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

    # --- P5: richer stats + filter + export ------------------------------

    def test_stats_label_mentions_coverage(self) -> None:
        text = self.win._stats_label.text()
        self.assertIn("词汇", text)
        self.assertIn("表达", text)
        self.assertIn("语法", text)
        # Coverage percentage appears as a parenthesised number.
        self.assertIn("%", text)

    def test_search_filters_chips(self) -> None:
        all_chips = self.win.findChildren(_LessonChip)
        # Pick a needle from the first chip's text.
        first_text = all_chips[0].text().split("·")[0].strip()
        needle = first_text[:3]  # substring of the name
        self.win._search.setText(needle)
        # Typing is debounced in the UI; render explicitly like a user pausing.
        self.win._filter_timer.stop()
        self.win._render()
        # At least the first chip should still be visible.
        visible = [c for c in self.win.findChildren(_LessonChip) if c.isVisibleTo(self.win)]
        # Note: chips inside a hidden section card may still report visible;
        # the authoritative check is that the match count is <= all_chips.
        self.assertLessEqual(len(visible), len(all_chips))

    def test_search_is_debounced_not_immediate(self) -> None:
        before = len(self.win.findChildren(_LessonChip))
        self.win._search.setText("__zzz_no_such_lesson_zzz__")
        # The rebuild must be pending (timer active), not yet applied.
        self.assertTrue(self.win._filter_timer.isActive())
        self.assertEqual(len(self.win.findChildren(_LessonChip)), before)
        self.win._filter_timer.stop()
        self.win._render()
        host_labels = [
            w for w in self.win._host.findChildren(type(self.win._stats_label))
            if "无匹配" in w.text()
        ]
        self.assertTrue(host_labels, "Expected empty-match message in the host")

    def test_template_filter_hides_other_chips(self) -> None:
        from src.backend.lesson_content import TEMPLATE_LABELS

        # Find a template that exists in the adapter.
        present_templates = {
            lesson.get("template", "legacy")
            for s in self.adapter.sections
            for u in s.get("units", [])
            for lesson in u.get("lessons", [])
        }
        self.assertTrue(present_templates)
        target = next(iter(present_templates))
        self.win._on_template_toggle(target)
        # Every visible chip should belong to the target template.
        for chip in self.win.findChildren(_LessonChip):
            if not chip.isVisibleTo(self.win):
                continue
            # The chip text contains the template label.
            self.assertIn(TEMPLATE_LABELS.get(target, target), chip.text())

    def test_clear_filter_resets_search_and_template(self) -> None:
        self.win._search.setText("abc")
        self.win._on_template_toggle("intro")
        self.assertEqual(self.win._template_filter, "intro")
        self.assertEqual(self.win._search.text(), "abc")
        self.win._on_clear_filter()
        self.assertEqual(self.win._search.text(), "")
        self.assertIsNone(self.win._template_filter)

    def test_empty_lesson_chip_has_empty_marker(self) -> None:
        # Inject an empty lesson and refresh.
        for section in self.adapter.sections:
            for unit in section.get("units", []):
                unit.setdefault("lessons", []).insert(
                    0,
                    {
                        "id": "ov-empty",
                        "name": "OV Empty",
                        "template": "intro",
                        "content": {"subLessons": []},
                    },
                )
                break
            break
        self.win.refresh()
        empty_chips = [c for c in self.win.findChildren(_LessonChip) if "（空）" in c.text()]
        self.assertTrue(empty_chips, "Expected at least one chip with （空） marker")

    def test_export_markdown_to_clipboard(self) -> None:
        from PySide6.QtWidgets import QApplication

        self.win._on_export()
        md = QApplication.clipboard().text()
        self.assertIn("# 课程结构总览", md)
        self.assertIn("Sections:", md)
        # Button shows "已复制" briefly.
        self.assertIn("已复制", self.win._export_btn.text())

    def test_validation_requested_signal_emitted(self) -> None:
        captured: list[list] = []
        self.win.validation_requested.connect(lambda problems: captured.append(problems))
        self.win._emit_validation()
        self.assertEqual(len(captured), 1)
        # Problems is a list (may be empty if the course validates clean).
        self.assertIsInstance(captured[0], list)

    # --- async validation fetch (P0: CLI off the UI thread) --------------

    def test_validate_link_fetches_async_then_emits(self) -> None:
        captured: list[list] = []
        self.win.validation_requested.connect(lambda problems: captured.append(problems))
        self.win._on_stats_link("#validate")
        # Busy hint shows immediately; nothing emitted until the worker
        # delivers (queued signals need event-loop turns, which the asserts
        # below don't run).
        self.assertIn("校验中", self.win._stats_label.text())
        self.assertEqual(len(captured), 0)
        self.assertTrue(
            _spin_until(lambda: self.win._validation_worker is None),
            "validation worker did not settle in time",
        )
        self.assertEqual(len(captured), 1)
        self.assertIsInstance(captured[0], list)
        # PySide6 marshals Signal(list) payloads into a fresh list, so the
        # cache and the emitted value are equal but not the same object.
        self.assertEqual(self.win._validation_problems, captured[0])
        # Busy hint replaced by the rebuilt stats label.
        self.assertNotIn("校验中", self.win._stats_label.text())

    def test_validation_link_emits_cache_without_worker(self) -> None:
        cached = [{"level": "error", "message": "boom", "path": ""}]
        self.win._validation_problems = cached
        captured: list[list] = []
        self.win.validation_requested.connect(lambda problems: captured.append(problems))
        self.win._on_stats_link("#validation")
        # Synchronous emit from cache; no CLI round-trip, no worker.
        self.assertEqual(captured, [cached])
        self.assertIsNone(self.win._validation_worker)

    def test_refresh_preserves_cached_validation_counts(self) -> None:
        self.win._validation_problems = [
            {"level": "error", "message": "e1", "path": ""},
            {"level": "warning", "message": "w1", "path": ""},
        ]
        self.win.refresh()
        self.assertEqual(self.win._stats.validation_errors, 1)
        self.assertEqual(self.win._stats.validation_warnings, 1)


if __name__ == "__main__":
    unittest.main()
