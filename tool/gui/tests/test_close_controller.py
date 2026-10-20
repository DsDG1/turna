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

from src.application.close_controller import (
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


class _InlineWorker:
    """Runs the target synchronously and emits the result immediately.

    The close path now saves on a worker (the synchronous save froze the
    window for the whole save chain). Tests run the worker inline so the
    assertions stay deterministic.
    """

    def __init__(self, target, *args, **kwargs):
        self.target = target
        self.args = args
        self.kwargs = kwargs
        self.result_ready = _FakeSignal()
        self.error_occurred = _FakeSignal()

    def start(self) -> None:
        try:
            result = self.target(*self.args, **self.kwargs)
        except Exception as exc:  # pragma: no cover - mirrors worker behaviour
            self.error_occurred.emit(str(exc))
            return
        self.result_ready.emit(result)

    def cancel(self) -> None:
        pass

    def isRunning(self) -> bool:
        return False

    def wait(self, _ms: int = 0) -> bool:
        return True


class _FakeSignal:
    def __init__(self) -> None:
        self._callbacks: list = []

    def connect(self, callback) -> None:
        self._callbacks.append(callback)

    def emit(self, *args) -> None:
        for cb in self._callbacks:
            cb(*args)


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
            close=MagicMock(),
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
        """A failed async close-save keeps the window open and warns."""
        host = self._host(dirty=True, auto_save=True)
        host._settings_obj.ai_api_key = ""
        host._settings_obj.save_to_qsettings = MagicMock()
        ev = _Event()
        fail = SimpleNamespace(ok=False, message="boom", errors=[{"level": "error", "message": "e"}])
        with (
            patch("src.infrastructure.telemetry.telemetry"),
            patch(
                "src.application.ai_request_worker.AiRequestWorker",
                _InlineWorker,
            ),
            patch(
                "src.application.save_host.execute_save", return_value=fail
            ),
            patch(
                "src.application.ui_guard.safe_warning"
            ) as warn,
        ):
            handle_close_event(host, ev)
        # The save runs on a worker; the close is deferred, so the event is
        # ignored and the window stays open until the save resolves.
        self.assertTrue(ev._ignored)
        warn.assert_called()
        host._flush_experience_metrics.assert_not_called()

    def test_auto_save_success_closes_window(self) -> None:
        """A successful async close-save closes the window itself."""
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
                "src.application.ai_request_worker.AiRequestWorker",
                _InlineWorker,
            ),
            patch(
                "src.application.save_host.execute_save", return_value=ok
            ),
        ):
            handle_close_event(host, ev)
        # The first pass defers the close (the save is still running from the
        # handler's point of view); the save completion asks the window to
        # close.
        self.assertTrue(ev._ignored)
        host.close.assert_called()
        self.assertTrue(host._close_after_save)


class SaveWorkerWaitTest(unittest.TestCase):
    """T18: a stuck background save must not hang the close forever."""

    def _host(self):
        host = MagicMock()
        host._settings_obj = MagicMock()
        host._flush_experience_metrics = MagicMock()
        host._record_window_duration = MagicMock()
        worker = MagicMock()
        worker.isRunning.return_value = True
        worker.wait.return_value = False  # timeout
        host._save_worker = worker
        host._workshop_window = None
        host._overview_window = None
        return host, worker

    def test_wait_timeout_ignores_close_and_warns(self) -> None:
        host, worker = self._host()
        ev = _Event()
        with (
            patch("src.infrastructure.telemetry.telemetry"),
            patch("src.application.ui_guard.safe_warning") as warned,
        ):
            handle_close_event(host, ev)
        worker.wait.assert_called_once_with(5000)  # bounded, not forever
        self.assertTrue(ev._ignored)
        warned.assert_called_once()

    def test_wait_success_proceeds_to_dirty_check(self) -> None:
        host, worker = self._host()
        worker.wait.return_value = True
        host.course_dir = None
        host.adapter = MagicMock()
        ev = _Event()
        with patch("src.infrastructure.telemetry.telemetry"):
            handle_close_event(host, ev)
        # Clean course (course_dir None) → accepted without prompts.
        self.assertTrue(ev.isAccepted())


if __name__ == "__main__":
    unittest.main()
