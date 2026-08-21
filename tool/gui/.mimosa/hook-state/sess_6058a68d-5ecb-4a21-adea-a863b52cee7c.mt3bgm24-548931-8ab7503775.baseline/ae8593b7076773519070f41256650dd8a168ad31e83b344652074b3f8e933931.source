"""S-10 v4.55: overview_controller pure heat + duck-host open wiring."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.application.overview_controller import (  # noqa: E402
    lesson_error_counts_from_problems,
    on_overview_destroyed,
    on_overview_lesson_selected,
    on_overview_validation,
    open_overview,
    sync_overview_heat_errors,
)


class LessonErrorCountsTest(unittest.TestCase):
    def test_counts_errors_by_lesson_id(self) -> None:
        problems = [
            {"level": "error", "path": "section:s1/unit:u1/lesson:l1/item:x"},
            {"level": "err", "path": "lesson:l1"},
            {"level": "warning", "path": "lesson:l1"},
            {"level": "error", "path": "lesson:l2"},
            {"level": "error", "path": "unit:u1"},  # no lesson
            "junk",
        ]
        self.assertEqual(
            lesson_error_counts_from_problems(problems),
            {"l1": 2, "l2": 1},
        )

    def test_empty_and_garbage_safe(self) -> None:
        self.assertEqual(lesson_error_counts_from_problems(None), {})
        self.assertEqual(lesson_error_counts_from_problems([]), {})
        self.assertEqual(lesson_error_counts_from_problems([None, 1, {}]), {})


class SyncHeatTest(unittest.TestCase):
    def test_noop_without_window(self) -> None:
        host = SimpleNamespace(_overview_window=None, experience=None)
        sync_overview_heat_errors(host)  # must not raise

    def test_prefers_context_validate_problems(self) -> None:
        win = MagicMock()
        ctx = SimpleNamespace(
            validate_problems=[
                {"level": "error", "path": "lesson:L9"},
            ]
        )
        exp = SimpleNamespace(
            _validate_problems=[{"level": "error", "path": "lesson:OLD"}],
            context=ctx,
        )
        host = SimpleNamespace(_overview_window=win, experience=exp)
        sync_overview_heat_errors(host)
        win.set_lesson_error_counts.assert_called_once_with({"L9": 1})


class OpenOverviewTest(unittest.TestCase):
    def test_lazy_create_wires_signals_once(self) -> None:
        fake_win = MagicMock()
        host = SimpleNamespace(
            adapter=object(),
            _overview_window=None,
            experience=SimpleNamespace(_validate_problems=[], context=None),
            _on_overview_lesson_selected=MagicMock(),
            _on_overview_validation=MagicMock(),
            _on_overview_destroyed=MagicMock(),
        )
        with (
            patch(
                "src.widgets.course_overview.CourseOverviewWindow",
                return_value=fake_win,
            ) as ctor,
            patch("src.infrastructure.telemetry.telemetry") as tel,
        ):
            open_overview(host)
            ctor.assert_called_once()
            tel.record_event.assert_called_with("overview.open")
            fake_win.lesson_selected.connect.assert_called()
            fake_win.validation_requested.connect.assert_called()
            fake_win.destroyed.connect.assert_called()
            fake_win.refresh.assert_called()
            fake_win.show.assert_called()
            # Second open reuses window (no second construct).
            open_overview(host)
            self.assertEqual(ctor.call_count, 1)

    def test_lesson_selected_selects_tree(self) -> None:
        tree = MagicMock()
        host = SimpleNamespace(
            tree=tree,
            showNormal=MagicMock(),
            raise_=MagicMock(),
            activateWindow=MagicMock(),
        )
        on_overview_lesson_selected(host, "s1-l2")
        tree.select_lesson.assert_called_once_with("s1-l2")

    def test_validation_forwards_report(self) -> None:
        host = SimpleNamespace(_show_validation_report=MagicMock())
        on_overview_validation(host, [{"level": "error"}])
        host._show_validation_report.assert_called_once()
        args, kwargs = host._show_validation_report.call_args
        self.assertEqual(args[0], [{"level": "error"}])
        self.assertIn("总览", kwargs.get("title", args[1] if len(args) > 1 else ""))

    def test_destroyed_clears_slot(self) -> None:
        host = SimpleNamespace(_overview_window=object())
        on_overview_destroyed(host)
        self.assertIsNone(host._overview_window)


if __name__ == "__main__":
    unittest.main()
