"""Unit tests for R1 secondary cursor / PresenceVisualHost and AmbientHeartbeat."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from PySide6.QtCore import QPoint, QRect
from PySide6.QtWidgets import QApplication

from tests._qtapp import qt_app
from src.application.ambient_heartbeat import AmbientHeartbeatService
from src.application.settings import Settings
from src.backend.experience.policy import resolve_policy
from src.widgets.gaze_cursor_overlay import GazeCursorOverlay


class MockHost:
    def __init__(self, mode: str = "copilot") -> None:
        self._settings_obj = Settings()
        self._settings_obj.experience_mode = mode
        self.experience = self
        self.refreshed_ambient = False
        self.processed_defer = False
        self._gaze_overlay = None

    def refresh_ambient_proposals(self) -> None:
        self.refreshed_ambient = True

    def process_defer_backfill(self) -> None:
        self.processed_defer = True

    def rect(self):
        return QRect(0, 0, 800, 600)

    def statusBar(self):
        return None


class SovereignAndAmbientTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls._app = qt_app()

    def test_gaze_cursor_disabled_by_default_no_timer(self) -> None:
        from PySide6.QtCore import Qt

        overlay = GazeCursorOverlay()
        self.assertTrue(overlay.testAttribute(Qt.WA_TransparentForMouseEvents))
        self.assertFalse(overlay.is_tracking_enabled())
        self.assertFalse(overlay._anim_timer.isActive())

        overlay.enable_tracking(True)
        self.assertTrue(overlay.is_tracking_enabled())
        self.assertTrue(overlay._anim_timer.isActive())

        overlay.set_mouse_global(QPoint(100, 200))
        # Target updated in local coords (no parent → identity-ish map)
        self.assertNotEqual(overlay._target_pos, QPoint(-100, -100))

        rect = QRect(50, 50, 200, 100)
        overlay.set_lockout(rect, "Test Lockout")
        self.assertTrue(overlay.is_locked())
        self.assertFalse(overlay.testAttribute(Qt.WA_TransparentForMouseEvents))

        overlay.clear_lockout()
        self.assertFalse(overlay.is_locked())
        self.assertTrue(overlay.testAttribute(Qt.WA_TransparentForMouseEvents))

        overlay.enable_tracking(False)
        self.assertFalse(overlay.is_tracking_enabled())
        self.assertFalse(overlay._anim_timer.isActive())

    def test_presence_visual_host_mouse_follow_default_off(self) -> None:
        """P0-a: immersive does not auto-enable continuous mouse tracking."""
        from src.application.presence_visual_host import (
            should_follow_mouse,
            should_job_lockout_visual,
            should_show_secondary_cursor,
            sync_secondary_cursor,
        )
        from src.widgets.gaze_cursor_overlay import GazeCursorOverlay

        host = MockHost("copilot")
        host._gaze_overlay = GazeCursorOverlay()
        self.assertFalse(should_show_secondary_cursor(host))
        sync_secondary_cursor(host)
        self.assertFalse(host._gaze_overlay.is_tracking_enabled())

        host._settings_obj.experience_mode = "immersive"
        self.assertFalse(should_follow_mouse(host))
        sync_secondary_cursor(host)
        self.assertFalse(host._gaze_overlay.is_tracking_enabled())

        host._settings_obj.experience_mode = "sovereign"
        self.assertFalse(should_follow_mouse(host))
        # Job lockout chrome remains available by default.
        self.assertTrue(should_job_lockout_visual(host))

        host._settings_obj.experience_gaze_cursor = True
        self.assertTrue(should_follow_mouse(host))

    def test_ambient_heartbeat_tick_copilot(self) -> None:
        host = MockHost("copilot")
        svc = AmbientHeartbeatService(host)
        svc._on_heartbeat_tick()
        self.assertFalse(host.refreshed_ambient)
        self.assertFalse(host.processed_defer)

    def test_ambient_heartbeat_tick_active(self) -> None:
        host = MockHost("active")
        svc = AmbientHeartbeatService(host)
        svc._on_heartbeat_tick()
        self.assertTrue(host.refreshed_ambient)
        self.assertFalse(host.processed_defer)

    def test_ambient_heartbeat_tick_sovereign(self) -> None:
        host = MockHost("sovereign")
        svc = AmbientHeartbeatService(host)
        svc._on_heartbeat_tick()
        self.assertTrue(host.refreshed_ambient)
        self.assertTrue(host.processed_defer)


if __name__ == "__main__":
    unittest.main()
