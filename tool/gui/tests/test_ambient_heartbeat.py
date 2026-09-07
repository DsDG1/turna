"""Unit tests for AmbientHeartbeatService tick gating (migrated from test_sovereign_and_ambient)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from PySide6.QtCore import QRect

from tests._qtapp import qt_app
from src.application.ambient_heartbeat import AmbientHeartbeatService
from src.application.settings import Settings


class MockHost:
    def __init__(self, mode: str = "copilot") -> None:
        self._settings_obj = Settings()
        self._settings_obj.experience_mode = mode
        self.experience = self
        self.refreshed_ambient = False
        self.processed_defer = False

    def refresh_ambient_proposals(self) -> None:
        self.refreshed_ambient = True

    def process_defer_backfill(self) -> None:
        self.processed_defer = True

    def rect(self):
        return QRect(0, 0, 800, 600)

    def statusBar(self):
        return None


class AmbientHeartbeatTickTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls._app = qt_app()

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

    def test_ambient_heartbeat_tick_immersive(self) -> None:
        host = MockHost("immersive")
        svc = AmbientHeartbeatService(host)
        svc._on_heartbeat_tick()
        self.assertTrue(host.refreshed_ambient)
        self.assertTrue(host.processed_defer)


if __name__ == "__main__":
    unittest.main()
