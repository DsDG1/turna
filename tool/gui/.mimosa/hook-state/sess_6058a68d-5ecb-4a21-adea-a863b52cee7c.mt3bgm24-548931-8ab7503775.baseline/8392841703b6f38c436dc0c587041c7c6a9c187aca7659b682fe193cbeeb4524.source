"""S-10 final v4.56: close_controller headless / auto_save / teardown."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.application.close_controller import (  # noqa: E402
    clear_ai_key_on_exit,
    handle_close_event,
)


class _Event:
    def __init__(self) -> None:
        self._accepted = False
        self._ignored = False

    def accept(self) -> None:
        self._accepted = True
        self._ignored = False

    def ignore(self) -> None:
        self._ignored = True
        self._accepted = False

    def isAccepted(self) -> bool:
        return self._accepted


class ClearKeyTest(unittest.TestCase):
    def test_clears_memory_and_settings(self) -> None:
        cfg = SimpleNamespace(api_key="SECRET")
        settings_obj = SimpleNamespace(ai_api_key="SECRET", save_to_qsettings=MagicMock())
        host = SimpleNamespace(
            _ai_config=cfg,
            _settings_obj=settings_obj,
            _settings=object(),
        )
        clear_ai_key_on_exit(host)
        self.assertEqual(cfg.api_key, "")
        self.assertEqual(settings_obj.ai_api_key, "")
        settings_obj.save_to_qsettings.assert_called_once()


class CloseEventTest(unittest.TestCase):
    def _host(self, *, dirty=True, auto_save=False):
        adapter = MagicMock()
        adapter.detect_changes.return_value = {"section1": True} if dirty else {}
        return SimpleNamespace(
            course_dir=Path("/tmp/c") if dirty else None,
            adapter=adapter,
            _settings_obj=SimpleNamespace(auto_save_on_close=auto_save),
            _workshop_window=None,
            _overview_window=None,
            _flush_experience_metrics=MagicMock(),
            _record_window_duration=MagicMock(),
            _ai_config=SimpleNamespace(api_key="k"),
            _settings=object(),
        )

    def test_clean_accepts_and_teardown(self) -> None:
        host = self._host(dirty=False)
        host.course_dir = None
        ev = _Event()
        with patch("src.infrastructure.telemetry.telemetry"):
            handle_close_event(host, ev)
        self.assertTrue(ev.isAccepted())
        host._flush_experience_metrics.assert_called_with("app_close")
        host._record_window_duration.assert_called()

    def test_headless_dirty_discards(self) -> None:
        host = self._host(dirty=True, auto_save=False)
        host._settings_obj.ai_api_key = "x"
        host._settings_obj.save_to_qsettings = MagicMock()
        ev = _Event()
        with (
            patch("src.infrastructure.telemetry.telemetry") as tel,
            patch(
                "src.application.ui_guard.is_headless_ui", return_value=True
            ),
        ):
            handle_close_event(host, ev)
        self.assertTrue(ev.isAccepted())
        tel.record_event.assert_any_call("app.close_discarded")

    def test_auto_save_failure_ignores(self) -> None:
        host = self._host(dirty=True, auto_save=True)
        host._settings_obj.ai_api_key = ""
        host._settings_obj.save_to_qsettings = MagicMock()
        ev = _Event()
        fail = SimpleNamespace(ok=False, message="boom", errors=[{"level": "error", "message": "e"}])
        with (
            patch("src.infrastructure.telemetry.telemetry"),
            patch(
                "src.application.save_host.execute_save", return_value=fail
            ),
            patch(
                "src.application.ui_guard.safe_warning"
            ) as warn,
        ):
            handle_close_event(host, ev)
        self.assertTrue(ev._ignored)
        warn.assert_called()
        host._flush_experience_metrics.assert_not_called()

    def test_auto_save_success_teardown(self) -> None:
        host = self._host(dirty=True, auto_save=True)
        host._settings_obj.ai_api_key = ""
        host._settings_obj.save_to_qsettings = MagicMock()
        ww = MagicMock()
        host._workshop_window = ww
        ev = _Event()
        ok = SimpleNamespace(ok=True, message="ok", errors=[])
        with (
            patch("src.infrastructure.telemetry.telemetry"),
            patch(
                "src.application.save_host.execute_save", return_value=ok
            ),
        ):
            handle_close_event(host, ev)
        self.assertTrue(ev.isAccepted())
        ww.interrupt_and_save.assert_called()
        self.assertIsNone(host._workshop_window)


if __name__ == "__main__":
    unittest.main()
