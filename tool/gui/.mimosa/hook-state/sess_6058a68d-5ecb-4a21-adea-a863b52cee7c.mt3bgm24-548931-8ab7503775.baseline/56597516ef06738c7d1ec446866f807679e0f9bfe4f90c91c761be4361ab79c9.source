"""S-15 Observer mode hardening — zero Ambient / Soft side-effects.

Covers the defensive contract in experienceai.md §6.2 ("Observer 不得半关"):
in observer mode the editor must not produce Ambient proposals and must not
push SoftHygieneCommand. The Soft guard lives in
``app._maybe_soft_autopilot_before_save``; the Ambient guard lives in
``app._refresh_ambient``.
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))


class MainWindowObserverModeTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        from tests._mainwindow_fixture import build_main_window

        cls.win = build_main_window()

    def setUp(self) -> None:
        from tests._mainwindow_fixture import reset_main_window

        reset_main_window(self.win)

    def _set_dirty_vocab(self) -> None:
        """Give the adapter dirty whitespace so Soft *would* fire if enabled."""
        self.win.adapter.vocab = [
            {"id": "w1", "term": "  merhaba  ", "translation": "你好", "tags": ["", "a"]}
        ]
        self.win.adapter.expressions = []

    def test_observer_skips_soft_even_when_flag_on(self) -> None:
        """S-15: observer mode short-circuits Soft regardless of the flag."""
        self._set_dirty_vocab()
        # Turn soft ON and switch to observer — observer guard must win.
        self.win._settings_obj.experience_soft_autopilot = True
        self.win._settings_obj.experience_mode = "observer"
        n = self.win._maybe_soft_autopilot_before_save()
        self.assertEqual(n, 0)
        # No SoftHygieneCommand was pushed.
        self.assertEqual(self.win.undo_stack.count(), 0)
        # Vocabulary untouched.
        self.assertEqual(self.win.adapter.vocab[0]["term"], "  merhaba  ")

    def test_copilot_soft_applies_when_flag_on(self) -> None:
        """Control: copilot + soft on → fixes applied (guard is observer-specific)."""
        self._set_dirty_vocab()
        self.win._settings_obj.experience_soft_autopilot = True
        self.win._settings_obj.experience_mode = "copilot"
        n = self.win._maybe_soft_autopilot_before_save()
        self.assertGreater(n, 0)
        self.assertEqual(self.win.adapter.vocab[0]["term"], "merhaba")

    def test_observer_clears_ambient(self) -> None:
        """S-15: observer mode clears the Ambient banner and proposes nothing."""
        self.win._settings_obj.experience_mode = "observer"
        # Provide a context with errors so evaluate_ambient *would* propose.
        self.win.adapter.sections = [
            {
                "id": "section1",
                "name": "S1",
                "level": "A1",
                "units": [
                    {
                        "id": "u1",
                        "name": "U",
                        "lessons": [
                            {"id": "s1-l1", "name": "Empty", "template": "intro",
                             "content": {"subLessons": []}}
                        ],
                    }
                ],
            }
        ]
        self.win.adapter.index = {"language": "tr"}
        self.win.adapter.vocab = []
        self.win.adapter.expressions = []
        self.win.adapter.grammar_points = []
        self.win.course_dir = Path("/tmp/fake-observer-course")
        self.win._settings_obj.experience_mute_json = ""  # not muted
        self.win._refresh_experience(immediate=True)
        # Now invoke the Ambient refresh path directly.
        self.win._refresh_ambient()
        self.assertIsNone(self.win.ambient_banner.proposal())


if __name__ == "__main__":
    unittest.main()