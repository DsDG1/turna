"""E2.1+ C-17 FocusRing pure model tests."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.experience.focus_ring import FocusRole, FocusRing  # noqa: E402


class FocusRingTest(unittest.TestCase):
    def test_set_and_get(self) -> None:
        ring = FocusRing()
        ring.set("lesson:l1", FocusRole.SELECTION)
        self.assertEqual(ring.role_of("lesson:l1"), FocusRole.SELECTION)
        self.assertEqual(len(ring), 1)

    def test_priority_busy_wins(self) -> None:
        ring = FocusRing()
        ring.set("lesson:l1", FocusRole.SELECTION)
        ring.set("lesson:l1", FocusRole.PIN)
        ring.set("lesson:l1", FocusRole.BUSY, label="AI")
        self.assertEqual(ring.role_of("lesson:l1"), FocusRole.BUSY)
        # lower priority cannot downgrade
        ring.set("lesson:l1", FocusRole.SELECTION)
        self.assertEqual(ring.role_of("lesson:l1"), FocusRole.BUSY)

    def test_clear_roles(self) -> None:
        ring = FocusRing()
        ring.set("a:1", FocusRole.PIN)
        ring.set("b:2", FocusRole.BUSY)
        ring.clear_roles(FocusRole.BUSY)
        self.assertIsNone(ring.role_of("b:2"))
        self.assertEqual(ring.role_of("a:1"), FocusRole.PIN)

    def test_as_id_role_map(self) -> None:
        ring = FocusRing()
        ring.set("lesson:l2", FocusRole.AI_SCOPE)
        ring.set("section:s1", FocusRole.PIN)
        m = ring.as_id_role_map()
        self.assertEqual(m["l2"], FocusRole.AI_SCOPE)
        self.assertEqual(m["s1"], FocusRole.PIN)

    def test_replace_from_sources(self) -> None:
        ring = FocusRing()
        ring.replace_from_sources(
            selection="lesson:sel",
            pins=["lesson:p1"],
            busy={"section:s1": "清待补"},
        )
        self.assertEqual(ring.role_of("lesson:sel"), FocusRole.SELECTION)
        self.assertEqual(ring.role_of("lesson:p1"), FocusRole.PIN)
        self.assertEqual(ring.role_of("section:s1"), FocusRole.BUSY)

    def test_remove_and_clear(self) -> None:
        ring = FocusRing()
        ring.set("x:1", FocusRole.PIN)
        self.assertTrue(ring.remove("x:1"))
        self.assertFalse(ring.remove("x:1"))
        ring.set("y:2", FocusRole.PIN)
        ring.clear()
        self.assertEqual(len(ring), 0)


class ConflictGuardHoldsTest(unittest.TestCase):
    def test_holds_snapshot(self) -> None:
        from src.backend.experience.conflict_guard import ConflictGuard

        g = ConflictGuard()
        self.assertTrue(g.try_acquire("item:q1", "job-1", label="芯片"))
        holds = g.holds()
        self.assertEqual(len(holds), 1)
        self.assertEqual(holds[0].node_key, "item:q1")
        self.assertEqual(g.busy_keys(), ["item:q1"])


if __name__ == "__main__":
    unittest.main()
