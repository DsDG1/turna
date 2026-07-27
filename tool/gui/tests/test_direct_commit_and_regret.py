"""Unit tests for Sovereign RegretSuppressionEngine + demote cooldown."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from tests._qtapp import qt_app
from src.application.settings import Settings
from src.backend.experience.policy import resolve_policy
from src.backend.experience.regret_suppression import RegretSuppressionEngine


class MockHost:
    def __init__(self, mode: str = "sovereign") -> None:
        self._settings_obj = Settings()
        self._settings_obj.experience_mode = mode

    def statusBar(self):
        return None


class RegretSuppressionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls._app = qt_app()

    def test_regret_suppression_engine_weights_and_reapply(self) -> None:
        engine = RegretSuppressionEngine()
        fingerprint = "fp_node_01_syntax_norm"

        self.assertEqual(engine.get_anti_undo_weight(fingerprint), 1.0)

        # Log an Undo event
        engine.log_undo_action("undo.syntax_norm", fingerprint, score_loss=1.5)
        self.assertAlmostEqual(engine.get_anti_undo_weight(fingerprint), 1.5)

        # Evaluate under Copilot mode -> Should be False
        host_copilot = MockHost("copilot")
        policy_copilot = resolve_policy(host_copilot._settings_obj)
        self.assertFalse(engine.should_force_reapply(fingerprint, policy_copilot))

        # Evaluate under Sovereign mode -> Should be True (prob >= 0.25)
        host_sovereign = MockHost("sovereign")
        policy_sovereign = resolve_policy(host_sovereign._settings_obj)
        self.assertTrue(engine.should_force_reapply(fingerprint, policy_sovereign))

    def test_r4_log_undo_command_text_ai_marker(self) -> None:
        engine = RegretSuppressionEngine()
        self.assertIsNone(engine.log_undo_command_text("修改 title"))
        fp = engine.log_undo_command_text("Sovereign 直写补全")
        self.assertIsNotNone(fp)
        self.assertGreater(engine.get_anti_undo_weight(fp), 1.0)

    def test_r4_sovereign_demote_cooldown(self) -> None:
        from src.application.presence_mode import (
            demote_to_copilot,
            mark_sovereign_entered,
            sovereign_demote_cooldown_remaining,
        )

        host = MockHost("sovereign")
        mark_sovereign_entered(host)
        rem = sovereign_demote_cooldown_remaining(host)
        self.assertGreater(rem, 290)
        # Blocked demote
        self.assertFalse(demote_to_copilot(host._settings_obj, host=host))
        self.assertEqual(host._settings_obj.experience_mode, "sovereign")
        # Force demote works
        self.assertTrue(demote_to_copilot(host._settings_obj, host=host, force=True))
        self.assertEqual(host._settings_obj.experience_mode, "copilot")


if __name__ == "__main__":
    unittest.main()
