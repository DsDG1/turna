"""E2.0 C-16: ConflictGuard."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.experience.conflict_guard import ConflictGuard, node_key  # noqa: E402


class ConflictGuardTest(unittest.TestCase):
    def test_acquire_release(self) -> None:
        g = ConflictGuard()
        self.assertTrue(g.try_acquire("lesson:l1", "job1", label="chip"))
        self.assertTrue(g.is_busy("lesson:l1"))
        self.assertFalse(g.try_acquire("lesson:l1", "job2"))
        self.assertTrue(g.release("lesson:l1", "job1"))
        self.assertFalse(g.is_busy("lesson:l1"))
        self.assertTrue(g.try_acquire("lesson:l1", "job2"))

    def test_same_job_reentrant(self) -> None:
        g = ConflictGuard()
        self.assertTrue(g.try_acquire("item:q1", "j"))
        self.assertTrue(g.try_acquire("item:q1", "j"))

    def test_release_job(self) -> None:
        g = ConflictGuard()
        g.try_acquire("a", "j1")
        g.try_acquire("b", "j1")
        g.try_acquire("c", "j2")
        self.assertEqual(g.release_job("j1"), 2)
        self.assertFalse(g.is_busy("a"))
        self.assertTrue(g.is_busy("c"))

    def test_node_key(self) -> None:
        self.assertEqual(node_key("lesson", "x"), "lesson:x")

    def test_empty_key_fails(self) -> None:
        g = ConflictGuard()
        self.assertFalse(g.try_acquire("", "j"))
        self.assertFalse(g.try_acquire("k", ""))

    def test_clear_empties_holds(self) -> None:
        """C-16: close-course must clear all holds."""
        g = ConflictGuard()
        g.try_acquire("lesson:l1", "edit-l1")
        g.try_acquire("item:q1", "chip-q1")
        self.assertEqual(len(g), 2)
        g.clear()
        self.assertEqual(len(g), 0)
        self.assertEqual(g.busy_summary(), "")
        # re-acquire after clear
        self.assertTrue(g.try_acquire("lesson:l1", "edit-l1-again"))

    def test_release_wrong_job_keeps_hold(self) -> None:
        g = ConflictGuard()
        g.try_acquire("lesson:l1", "job-a")
        self.assertFalse(g.release("lesson:l1", "job-b"))
        self.assertTrue(g.is_busy("lesson:l1"))
        self.assertTrue(g.release("lesson:l1", "job-a"))

    def test_busy_summary_lists_labels(self) -> None:
        g = ConflictGuard()
        g.try_acquire("lesson:l1", "j1", label="AI 编辑")
        text = g.busy_summary()
        self.assertIn("lesson:l1", text)
        self.assertIn("AI 编辑", text)

    def test_fingerprint_hold(self) -> None:
        g = ConflictGuard()
        g.try_acquire("lesson:l1", "j1", fingerprint="fp12345")
        self.assertEqual(g.hold_fingerprint("lesson:l1"), "fp12345")
        self.assertTrue(g.verify_fingerprint("lesson:l1", "fp12345"))
        self.assertFalse(g.verify_fingerprint("lesson:l1", "different_fp"))
        self.assertTrue(g.verify_fingerprint("lesson:unknown", "any"))


if __name__ == "__main__":
    unittest.main()

