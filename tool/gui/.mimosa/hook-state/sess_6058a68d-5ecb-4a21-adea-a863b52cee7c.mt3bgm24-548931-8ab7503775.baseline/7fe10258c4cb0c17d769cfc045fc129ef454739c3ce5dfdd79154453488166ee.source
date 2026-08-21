"""Unit tests for full_section_diff (pure function, no PySide6 needed)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.ai_generator import full_section_diff


def _section(units, words=None, expressions=None, grammar=None):
    return {
        "id": "s1",
        "units": units,
        "words": words or [],
        "expressions": expressions or [],
        "grammarPoints": grammar or [],
    }


class TestFullSectionDiff(unittest.TestCase):
    def test_added_removed_changed(self) -> None:
        existing = _section(
            units=[
                {"id": "u1", "name": "U1", "lessons": [{"id": "l1", "name": "L1"}]},
                {"id": "u2", "name": "U2", "lessons": []},
            ],
            words=[{"id": "w1", "term": "a"}, {"id": "w2", "term": "b"}],
        )
        generated = _section(
            units=[
                {"id": "u1", "name": "U1-changed", "lessons": [
                    {"id": "l1", "name": "L1"},
                    {"id": "l2", "name": "L2-new"},
                ]},
            ],
            words=[{"id": "w1", "term": "a"}, {"id": "w3", "term": "c"}],
        )
        d = full_section_diff(existing, generated)
        self.assertEqual(d["units"]["removed"], ["u2"])
        self.assertEqual(d["units"]["changed"], ["u1"])
        self.assertEqual(d["lessons"]["added"], ["l2"])
        self.assertEqual(d["words"]["added"], ["w3"])
        self.assertEqual(d["words"]["removed"], ["w2"])

    def test_no_changes_empty(self) -> None:
        s = _section(units=[{"id": "u1", "lessons": [{"id": "l1"}]}], words=[{"id": "w1", "term": "a"}])
        d = full_section_diff(s, s)
        for cat in d:
            for kind in ("added", "removed", "changed"):
                self.assertEqual(d[cat][kind], [], f"{cat}.{kind} should be empty")

    def test_renamed_is_changed_not_added(self) -> None:
        existing = _section(units=[{"id": "u1", "name": "old", "lessons": []}], words=[{"id": "w1", "term": "old"}])
        generated = _section(units=[{"id": "u1", "name": "new", "lessons": []}], words=[{"id": "w1", "term": "new"}])
        d = full_section_diff(existing, generated)
        self.assertEqual(d["units"]["changed"], ["u1"])
        self.assertEqual(d["units"]["added"], [])
        self.assertEqual(d["units"]["removed"], [])
        self.assertEqual(d["words"]["changed"], ["w1"])

    def test_expressions_and_grammar(self) -> None:
        existing = _section(
            units=[], expressions=[{"id": "e1"}], grammar=[{"id": "g1"}],
        )
        generated = _section(
            units=[], expressions=[{"id": "e1"}, {"id": "e2"}], grammar=[],
        )
        d = full_section_diff(existing, generated)
        self.assertEqual(d["expressions"]["added"], ["e2"])
        self.assertEqual(d["grammar"]["removed"], ["g1"])


if __name__ == "__main__":
    unittest.main()