"""Tests for Ctrl+Shift+D demote action + _on_demote_experience handler."""
from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from PySide6.QtWidgets import QMainWindow

from tests._qtapp import qt_app
from src.application.experience_skills_mixin import ExperienceSkillsMixin
from src.application.main_window_shell import build_experience_actions
from src.application.presence_mode import DEMOTE_SHORTCUT
from src.application.settings import Settings


def _make_qsettings() -> MagicMock:
    store: dict = {}
    qs = MagicMock()
    qs.value = lambda key, default=None: store.get(key, default)
    qs.setValue = lambda key, value: store.__setitem__(key, value)
    return qs


class _Host(QMainWindow, ExperienceSkillsMixin):
    """Minimal MainWindow stand-in for the demote valve."""

    def __init__(self, mode: str = "immersive") -> None:
        super().__init__()
        self._settings_obj = Settings(experience_mode=mode)
        self._settings = _make_qsettings()
        self.refresh_calls: list = []

    def _refresh_experience(self, immediate: bool = False) -> None:
        self.refresh_calls.append(immediate)


class DemoteActionTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls._app = qt_app()

    def _make_host(self, mode: str = "immersive") -> _Host:
        host = _Host(mode)
        self.addCleanup(host.deleteLater)
        return host

    def test_demote_action_registered_with_shortcut(self) -> None:
        host = self._make_host()
        build_experience_actions(host)
        self.assertEqual(host.demote_action.shortcut().toString(), DEMOTE_SHORTCUT)
        self.assertEqual(DEMOTE_SHORTCUT, "Ctrl+Shift+D")

    def test_handler_demotes_immersive_and_persists(self) -> None:
        host = self._make_host(mode="immersive")
        host._on_demote_experience()
        self.assertEqual(host._settings_obj.experience_mode, "copilot")
        self.assertEqual(host._settings_obj.experience_mode, "copilot")
        self.assertEqual(host._settings.value("experience/mode"), "copilot")
        self.assertTrue(host.refresh_calls)  # experience refreshed

    def test_handler_noop_when_already_copilot(self) -> None:
        host = self._make_host(mode="copilot")
        host._on_demote_experience()
        self.assertEqual(host._settings_obj.experience_mode, "copilot")
        self.assertFalse(host.refresh_calls)

    def test_trigger_action_demotes(self) -> None:
        host = self._make_host(mode="active")
        build_experience_actions(host)
        host.demote_action.trigger()
        self.assertEqual(host._settings_obj.experience_mode, "copilot")


if __name__ == "__main__":
    unittest.main()
