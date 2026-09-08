"""E4/M-01 attachments: wired routing contract.

The snapshot/injection machinery (``build_attachment_snapshot`` /
``ExperienceShell.set_attachments``) has no production caller — ctx.attachments
is always empty at runtime — so only the wired parts (action spec + slash
route) are tested here.
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.experience.actions import (  # noqa: E402
    DANGEROUS_ACTION_IDS,
    get_action,
)
from src.backend.experience.intent_router import route_intent  # noqa: E402


class ContractRoutingTest(unittest.TestCase):
    def test_action_spec_readonly(self) -> None:
        spec = get_action("attachment.open_in_workshop")
        self.assertIsNotNone(spec)
        assert spec is not None
        self.assertTrue(spec.implemented)
        self.assertFalse(spec.needs_confirm)
        self.assertNotIn("attachment.open_in_workshop", DANGEROUS_ACTION_IDS)

    def test_slash_route(self) -> None:
        intent = route_intent("/attachments")
        self.assertIsNotNone(intent)
        assert intent is not None
        self.assertEqual(intent.action_id, "attachment.open_in_workshop")
        self.assertEqual(intent.confidence, 1.0)


if __name__ == "__main__":
    unittest.main()
