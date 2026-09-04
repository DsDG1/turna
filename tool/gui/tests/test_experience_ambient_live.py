"""A3 ③ continuous re-evaluation heartbeat (v4.66 P3 / F4).

The heartbeat is a cheap 8s timer that re-evaluates Ambient when
``ambient_live`` or ``defer_resurface`` is on and the window is active.
F4: banner visibility is **not** required (opaque immersive clears banner).
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest.mock import patch

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from tests._qtapp import qt_app  # noqa: E402


@unittest.skip("Ambient banner and MainWindow.experience retired")
class AmbientHeartbeatTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        from tests._mainwindow_fixture import build_main_window

        cls.win = build_main_window()

    def setUp(self) -> None:
        from tests._mainwindow_fixture import reset_main_window

        reset_main_window(self.win)
        self.win.course_dir = Path("/tmp/fake-a3-course")
        self.win._settings_obj.experience_mode = "copilot"
        self.win._settings_obj.experience_mute_json = ""
        self.win._settings_obj.experience_ambient_live = False
        self.win._settings_obj.experience_defer_resurface = False

    def _active(self):
        """Patch the window as active for the heartbeat (F4: no banner gate)."""
        return (patch.object(self.win, "isActiveWindow", return_value=True),)

    def test_noop_when_both_settings_off(self) -> None:
        with patch.object(self.win, "_refresh_ambient") as refresh:
            self.win._on_ambient_heartbeat()
            refresh.assert_not_called()

    def test_noop_in_observer_mode(self) -> None:
        self.win._settings_obj.experience_ambient_live = True
        self.win._settings_obj.experience_mode = "observer"
        with patch.object(self.win, "_refresh_ambient") as refresh:
            self.win._on_ambient_heartbeat()
            refresh.assert_not_called()

    def test_noop_when_no_course(self) -> None:
        self.win._settings_obj.experience_ambient_live = True
        self.win.course_dir = None
        with patch.object(self.win, "_refresh_ambient") as refresh:
            self.win._on_ambient_heartbeat()
            refresh.assert_not_called()

    def test_refreshes_when_live_active_and_not_stale(self) -> None:
        self.win._settings_obj.experience_ambient_live = True
        self.win.experience._content_stale = False
        (a1,) = self._active()
        with a1, patch.object(self.win, "_refresh_ambient") as refresh:
            self.win._on_ambient_heartbeat()
            refresh.assert_called_once()

    def test_f4_refreshes_even_when_banner_hidden(self) -> None:
        """Opaque immersive clears banner; heartbeat must still evaluate."""
        self.win._settings_obj.experience_mode = "immersive"
        self.win._settings_obj.experience_ambient_live = False  # bundle ORs live
        self.win.experience._content_stale = False
        with patch.object(self.win, "isActiveWindow", return_value=True), patch.object(
            self.win.ambient_banner, "isVisible", return_value=False
        ), patch.object(self.win, "_refresh_ambient") as refresh:
            self.win._on_ambient_heartbeat()
            refresh.assert_called_once()

    def test_p2_skips_refresh_when_ai_busy(self) -> None:
        self.win._settings_obj.experience_mode = "immersive"
        self.win.experience._content_stale = False
        with patch.object(self.win, "isActiveWindow", return_value=True), patch(
            "src.application.presence_drive.is_experience_ai_busy",
            return_value=True,
        ), patch.object(self.win, "_refresh_ambient") as refresh:
            self.win._on_ambient_heartbeat()
            refresh.assert_not_called()

    def test_p2_idle_restarts_heartbeat_timer(self) -> None:
        self.win._settings_obj.experience_mode = "immersive"
        self.win._ambient_heartbeat.stop()
        self.win._heartbeat_wait_idle = True
        self.win._on_job_tray_ai_busy_changed(True)
        self.assertFalse(self.win._ambient_heartbeat.isActive())
        self.win._on_job_tray_ai_busy_changed(False)
        self.assertTrue(self.win._ambient_heartbeat.isActive())
        from src.application.presence_drive import HEARTBEAT_IDLE_INTERVAL_MS

        self.assertEqual(
            self.win._ambient_heartbeat.interval(), HEARTBEAT_IDLE_INTERVAL_MS
        )

    def test_invalidates_when_live_and_stale(self) -> None:
        self.win._settings_obj.experience_ambient_live = True
        self.win.experience._content_stale = True
        (a1,) = self._active()
        with a1, patch.object(
            self.win.experience, "invalidate"
        ) as invalidate, patch.object(
            self.win, "_refresh_ambient"
        ) as refresh:
            self.win._on_ambient_heartbeat()
            invalidate.assert_called_once()
            refresh.assert_not_called()

    def test_active_mode_enables_heartbeat_without_live_flag(self) -> None:
        """P2: presence_level>=2 ORs ambient_live for heartbeat guard."""
        self.win._settings_obj.experience_mode = "active"
        self.win._settings_obj.experience_ambient_live = False
        self.win._settings_obj.experience_defer_resurface = False
        self.win.experience._content_stale = False
        (a1,) = self._active()
        with a1, patch.object(self.win, "_refresh_ambient") as refresh:
            self.win._on_ambient_heartbeat()
            refresh.assert_called_once()

    def test_demote_to_copilot_disables_bundle_heartbeat(self) -> None:
        self.win._settings_obj.experience_mode = "active"
        self.win._settings_obj.experience_ambient_live = False
        from src.application.presence_mode import demote_to_copilot

        demote_to_copilot(self.win._settings_obj)
        with patch.object(self.win, "_refresh_ambient") as refresh:
            self.win._on_ambient_heartbeat()
            refresh.assert_not_called()


if __name__ == "__main__":
    unittest.main()
