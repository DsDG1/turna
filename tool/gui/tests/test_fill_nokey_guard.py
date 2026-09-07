"""No-key guards for lesson.fill_empty / resource.fill_stubs (silent-drive hardening).

Incomplete AI config must be a statusBar dead-end — never a modal dialog —
so immersive silent drive cannot pop NodeAiEditDialog / async failure boxes.
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import MagicMock

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))


class _Status:
    def __init__(self, host) -> None:
        self._host = host

    def showMessage(self, text: str, ms: int = 0) -> None:
        self._host._status.append(str(text))


class _NoKeyHost:
    """Fake host whose AI config is incomplete."""

    def __init__(self, *, course_dir="/tmp/course") -> None:
        self.course_dir = course_dir
        self._ai_config = SimpleNamespace(is_complete=False)
        self._status: list[str] = []
        self._ai_edit_calls: list = []
        self.tree = SimpleNamespace(select_lesson=lambda _lid: None)
        self.job_tray = SimpleNamespace(is_busy_ai=lambda: False)
        self._deny_ai_write_if_blocked = lambda *, label="AI": False

    def statusBar(self):  # noqa: N802
        return _Status(self)

    def _on_ai_edit(self, kind: str, lesson_id: str) -> None:
        self._ai_edit_calls.append((kind, lesson_id))


class FillNoKeyGuardTest(unittest.TestCase):
    def test_fill_empty_no_key_is_statusbar_dead_end(self) -> None:
        from src.application.experience_handlers.fill import handle_fill_empty

        host = _NoKeyHost()
        handle_fill_empty(host, {"first_lesson_id": "l1", "lesson_ids": ["l1"]})
        self.assertTrue(any("AI 配置不完整" in m for m in host._status))
        # Legacy modal fallback must no longer fire.
        self.assertEqual(host._ai_edit_calls, [])

    def test_fill_stubs_no_key_short_circuits_before_worker(self) -> None:
        from src.application.experience_handlers.fill import handle_fill_stubs

        host = _NoKeyHost()
        # Everything past the guard would explode on this minimal host;
        # the precheck must return before touching any of it.
        handle_fill_stubs(host)
        self.assertTrue(any("AI 配置不完整" in m for m in host._status))

    def test_complete_config_still_reaches_legacy_paths(self) -> None:
        """Guard only blocks incomplete config; complete config passes the gate.

        For fill_empty the next gate is job_tray/adapter — assert the status
        list stays empty of the no-key message when config is complete.
        """
        from src.application.experience_handlers.fill import handle_fill_empty

        host = _NoKeyHost()
        host._ai_config = SimpleNamespace(is_complete=True)
        host.job_tray = SimpleNamespace(is_busy_ai=lambda: True)  # next gate
        handle_fill_empty(host, {"first_lesson_id": "l1"})
        self.assertFalse(any("AI 配置不完整" in m for m in host._status))


if __name__ == "__main__":
    unittest.main()
