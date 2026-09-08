"""S-10 v4.55: overview_controller duck-host open wiring."""
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
    on_overview_destroyed,
    on_overview_lesson_selected,
    on_overview_validation,
    open_overview,
)


class OpenOverviewTest(unittest.TestCase):
    def test_lazy_create_wires_signals_once(self) -> None:
        fake_win = MagicMock()
        host = SimpleNamespace(
            adapter=object(),
            _overview_window=None,
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
