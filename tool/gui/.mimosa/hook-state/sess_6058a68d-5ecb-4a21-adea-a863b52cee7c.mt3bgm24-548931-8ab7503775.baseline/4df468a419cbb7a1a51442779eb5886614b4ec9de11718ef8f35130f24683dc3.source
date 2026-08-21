"""Tests for AI fix problem grouping (aiEnhance perception U1-2)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

_GUI_ROOT = Path(__file__).resolve().parents[1]
if str(_GUI_ROOT) not in sys.path:
    sys.path.insert(0, str(_GUI_ROOT))

from src.backend.ai_fix_batch import (  # noqa: E402
    FixBatch,
    group_problems_for_fix,
    selected_problems_with_refs,
)
from src.backend.ai_presets_ui import EDIT_PRESETS, EDIT_PRESET_LABELS  # noqa: E402


class GroupProblemsForFixTest(unittest.TestCase):
    def test_group_by_lesson_path(self) -> None:
        sections = [
            {
                "id": "s1",
                "units": [
                    {
                        "id": "u1",
                        "lessons": [{"id": "l1", "name": "L1"}],
                    }
                ],
            }
        ]
        problems = [
            {
                "level": "error",
                "path": "section:s1/unit:u1/lesson:l1",
                "message": "a",
            },
            {
                "level": "error",
                "path": "section:s1/unit:u1/lesson:l1/items/0",
                "message": "b",
            },
            {
                "level": "warning",
                "path": "section:s1/unit:u1",
                "message": "c",
            },
        ]
        batches = group_problems_for_fix(problems, sections)
        self.assertEqual(len(batches), 2)
        self.assertEqual(batches[0].kind, "lesson")
        self.assertEqual(batches[0].node_id, "l1")
        self.assertEqual(len(batches[0].problems), 2)
        self.assertEqual(batches[1].kind, "unit")
        self.assertEqual(batches[1].node_id, "u1")

    def test_fallback_ref_for_unmapped(self) -> None:
        problems = [{"level": "error", "path": "", "message": "orphan"}]
        batches = group_problems_for_fix(
            problems, [], fallback_ref=("section", "s-fallback")
        )
        self.assertEqual(len(batches), 1)
        self.assertEqual(batches[0].node_ref, ("section", "s-fallback"))

    def test_unmapped_without_fallback_dropped(self) -> None:
        problems = [{"level": "error", "path": "", "message": "orphan"}]
        batches = group_problems_for_fix(problems, [])
        self.assertEqual(batches, [])

    def test_empty_input(self) -> None:
        self.assertEqual(group_problems_for_fix(None, None), [])
        self.assertEqual(group_problems_for_fix([], []), [])

    def test_preserves_first_seen_order(self) -> None:
        sections = [{"id": "s1", "units": []}]
        problems = [
            {"level": "error", "path": "section:s1", "message": "1"},
            {
                "level": "error",
                "path": "section:s2",
                "message": "2",
            },
            {"level": "error", "path": "section:s1", "message": "3"},
        ]
        batches = group_problems_for_fix(problems, sections)
        self.assertEqual([b.node_id for b in batches], ["s1", "s2"])
        self.assertEqual(len(batches[0].problems), 2)

    def test_selected_problems_with_refs(self) -> None:
        pairs = selected_problems_with_refs(
            [{"level": "error", "path": "section:s1", "message": "x"}],
            [{"id": "s1"}],
        )
        self.assertEqual(len(pairs), 1)
        self.assertEqual(pairs[0][1], ("section", "s1"))


class FixBatchDataclassTest(unittest.TestCase):
    def test_node_ref_property(self) -> None:
        b = FixBatch(kind="lesson", node_id="l9", problems=[])
        self.assertEqual(b.node_ref, ("lesson", "l9"))


class PresetsUiTest(unittest.TestCase):
    def test_presets_aligned(self) -> None:
        self.assertEqual(len(EDIT_PRESETS), len(EDIT_PRESET_LABELS))
        self.assertGreaterEqual(len(EDIT_PRESETS), 5)
        self.assertTrue(any("待补" in p for p in EDIT_PRESETS))


if __name__ == "__main__":
    unittest.main()
