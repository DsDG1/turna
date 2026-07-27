"""C-08 / v4.58: SectionPatch + ApplySectionPatchCommand."""
from __future__ import annotations

import sys
import unittest
from copy import deepcopy
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.application.commands import ApplySectionPatchCommand  # noqa: E402
from src.backend.experience.patch import (  # noqa: E402
    PatchError,
    section_patch_from_replace,
)


class _Adapter:
    def __init__(self, section: dict, vocab: list | None = None) -> None:
        self.sections = [deepcopy(section)]
        self.vocab = list(vocab or [])
        self.expressions: list = []
        self.grammar_points: list = []
        self.index = {"sections": [{"id": section["id"]}]}

    def find_section(self, sid: str) -> dict:
        for s in self.sections:
            if s.get("id") == sid:
                return s
        raise KeyError(sid)

    def replace_section(self, sid: str, new_section: dict) -> None:
        for i, s in enumerate(self.sections):
            if s.get("id") == sid:
                self.sections[i] = new_section
                return
        raise KeyError(sid)

    def merge_section_resources(self, section: dict) -> None:
        seen = {w.get("id") for w in self.vocab}
        for w in section.get("words") or []:
            if isinstance(w, dict) and w.get("id") and w["id"] not in seen:
                self.vocab.append(deepcopy(w))
                seen.add(w["id"])

    def invalidate_node_index(self) -> None:
        pass


class SectionPatchFactoryTest(unittest.TestCase):
    def test_forces_section_id(self) -> None:
        old = {"id": "s1", "name": "A", "units": []}
        new = {"id": "HACK", "name": "B", "units": [{"id": "u1"}]}
        p = section_patch_from_replace(old, new)
        self.assertEqual(p.section_id, "s1")
        self.assertEqual(p.new_section["id"], "s1")
        self.assertEqual(p.new_section["name"], "B")

    def test_missing_id_raises(self) -> None:
        with self.assertRaises(PatchError):
            section_patch_from_replace({"name": "x"}, {"name": "y"})


class ApplySectionPatchTest(unittest.TestCase):
    def test_apply_undo_section_and_resources(self) -> None:
        from PySide6.QtGui import QUndoStack

        old = {
            "id": "s1",
            "name": "Old",
            "units": [{"id": "u1", "lessons": [{"id": "l1", "name": "A"}]}],
            "words": [],
        }
        new = {
            "id": "s1",
            "name": "New",
            "units": [
                {
                    "id": "u1",
                    "lessons": [{"id": "l1", "name": "A2", "content": {}}],
                }
            ],
            "words": [{"id": "w_new", "term": "su", "translation": "水"}],
        }
        adapter = _Adapter(old, vocab=[{"id": "w0", "term": "hi"}])
        patch = section_patch_from_replace(old, new)
        stack = QUndoStack()
        stack.push(ApplySectionPatchCommand(adapter, patch))
        self.assertEqual(adapter.find_section("s1")["name"], "New")
        self.assertEqual(adapter.find_section("s1")["units"][0]["lessons"][0]["name"], "A2")
        ids = {w["id"] for w in adapter.vocab}
        self.assertIn("w_new", ids)
        self.assertIn("w0", ids)
        stack.undo()
        self.assertEqual(adapter.find_section("s1")["name"], "Old")
        ids2 = {w["id"] for w in adapter.vocab}
        self.assertNotIn("w_new", ids2)
        self.assertIn("w0", ids2)


if __name__ == "__main__":
    unittest.main()
