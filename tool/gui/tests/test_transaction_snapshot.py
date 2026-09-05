"""Unit tests for TransactionSnapshot and verification service (E2.0)."""
from __future__ import annotations

import copy
import sys
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.experience.transaction import (
    TransactionSnapshot,
    _compute_fingerprint,
    create_transaction_snapshot,
    rollback_transaction,
    verify_transaction_integrity,
)


class DummyAdapter:
    def __init__(self, sections: list[dict]):
        self.sections = copy.deepcopy(sections)
        self.notified = False

    def find_lesson(self, lesson_id: str):
        for s in self.sections:
            for u in s.get("units") or []:
                for l in u.get("lessons") or []:
                    if l.get("id") == lesson_id:
                        return s, u, l
        return None, None, None

    def find_unit(self, unit_id: str):
        for s in self.sections:
            for u in s.get("units") or []:
                if u.get("id") == unit_id:
                    return s, u
        return None, None

    def notify_resources_changed(self):
        self.notified = True


class TestTransactionSnapshot(unittest.TestCase):
    def setUp(self):
        self.raw_sections = [
            {
                "id": "s1",
                "name": "Section 1",
                "units": [
                    {
                        "id": "u1",
                        "name": "Unit 1",
                        "lessons": [
                            {
                                "id": "l1",
                                "name": "Lesson 1",
                                "content": {"stages": [{"items": ["q1", "q2"]}]},
                            },
                            {
                                "id": "l2",
                                "name": "Lesson 2",
                                "content": {"stages": []},
                            },
                        ],
                    }
                ],
            }
        ]
        self.adapter = DummyAdapter(self.raw_sections)

    def test_create_snapshot_captures_sections_and_fingerprints(self):
        snap = create_transaction_snapshot(
            self.adapter,
            "lesson.regenerate",
            ["lesson:l1"],
        )
        self.assertEqual(snap.action_id, "lesson.regenerate")
        self.assertIn("s1", snap.affected_sections)
        self.assertIn("lesson:l1", snap.node_fingerprints)
        self.assertTrue(len(snap.node_fingerprints["lesson:l1"]) > 0)

    def test_verify_integrity_passes_when_untouched(self):
        snap = create_transaction_snapshot(
            self.adapter,
            "lesson.regenerate",
            ["lesson:l1"],
        )
        ok, reason = verify_transaction_integrity(self.adapter, snap)
        self.assertTrue(ok)
        self.assertEqual(reason, "")

    def test_verify_integrity_fails_when_node_deleted(self):
        snap = create_transaction_snapshot(
            self.adapter,
            "lesson.regenerate",
            ["lesson:l1"],
        )
        # Delete lesson 1
        self.adapter.sections[0]["units"][0]["lessons"].pop(0)
        ok, reason = verify_transaction_integrity(self.adapter, snap)
        self.assertFalse(ok)
        self.assertIn("删除或移动", reason)

    def test_verify_integrity_fails_when_content_modified(self):
        snap = create_transaction_snapshot(
            self.adapter,
            "lesson.regenerate",
            ["lesson:l1"],
        )
        # Mutate lesson content
        _s, _u, l = self.adapter.find_lesson("l1")
        l["name"] = "Mutated Name"
        ok, reason = verify_transaction_integrity(self.adapter, snap)
        self.assertFalse(ok)
        self.assertIn("指纹不一致", reason)

    def test_rollback_transaction_restores_data(self):
        snap = create_transaction_snapshot(
            self.adapter,
            "lesson.regenerate",
            ["lesson:l1"],
        )
        # Damage the section
        self.adapter.sections[0]["name"] = "Corrupted Section"
        self.adapter.sections[0]["units"] = []

        res = rollback_transaction(self.adapter, snap)
        self.assertTrue(res)
        self.assertEqual(self.adapter.sections[0]["name"], "Section 1")
        self.assertEqual(len(self.adapter.sections[0]["units"]), 1)
        self.assertTrue(self.adapter.notified)

    def test_graceful_handling_none_adapter(self):
        snap = create_transaction_snapshot(None, "lesson.regenerate", ["lesson:l1"])
        self.assertEqual(len(snap.affected_sections), 0)
        ok, _ = verify_transaction_integrity(None, snap)
        self.assertTrue(ok)
        res = rollback_transaction(None, snap)
        self.assertFalse(res)


if __name__ == "__main__":
    unittest.main()
