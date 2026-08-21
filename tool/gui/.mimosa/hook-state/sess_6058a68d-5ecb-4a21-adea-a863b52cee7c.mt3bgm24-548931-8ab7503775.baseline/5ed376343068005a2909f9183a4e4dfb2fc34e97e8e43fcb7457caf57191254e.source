"""Tests for src.backend.import_strategy (bookplan2 Phase 4)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.import_strategy import (
    ImportStrategy,
    plan_bulk_import,
    resolve_action,
    unique_section_id,
)


class FakeAdapter:
    def __init__(self, section_ids=None):
        self.sections = [{"id": sid} for sid in (section_ids or [])]
        self.index = {"sections": []}


class ResolveActionTest(unittest.TestCase):
    def test_no_collision_always_appends(self) -> None:
        for strat in ImportStrategy:
            self.assertEqual(resolve_action(False, strat.value), "append")

    def test_merge_is_default_on_collision(self) -> None:
        self.assertEqual(resolve_action(True, ImportStrategy.MERGE.value), "merge")
        self.assertEqual(resolve_action(True, "unknown"), "merge")  # safe fallback

    def test_skip_replace_append_new_on_collision(self) -> None:
        self.assertEqual(
            resolve_action(True, ImportStrategy.SKIP_EXISTING.value), "skip"
        )
        self.assertEqual(
            resolve_action(True, ImportStrategy.FORCE_REPLACE.value), "replace"
        )
        self.assertEqual(
            resolve_action(True, ImportStrategy.APPEND_AS_NEW.value), "append_new"
        )


class UniqueSectionIdTest(unittest.TestCase):
    def test_free_id_returned_unchanged(self) -> None:
        adapter = FakeAdapter(["s1"])
        self.assertEqual(unique_section_id(adapter, "s2"), "s2")

    def test_collision_suffixed(self) -> None:
        adapter = FakeAdapter(["s1", "s1-2"])
        self.assertEqual(unique_section_id(adapter, "s1"), "s1-3")

    def test_no_adapter_returns_base(self) -> None:
        self.assertEqual(unique_section_id(None, "s1"), "s1")


class PlanBulkImportTest(unittest.TestCase):
    def _sections(self, ids):
        return [{"id": i, "name": i} for i in ids]

    def test_all_new_sections_append(self) -> None:
        adapter = FakeAdapter(["existing"])
        plans = plan_bulk_import(self._sections(["a", "b"]), adapter, ImportStrategy.MERGE.value)
        self.assertEqual([p.action for p in plans], ["append", "append"])
        self.assertEqual([p.target_id for p in plans], ["a", "b"])
        self.assertFalse(any(p.exists for p in plans))

    def test_merge_strategy_collision_is_interactive(self) -> None:
        adapter = FakeAdapter(["a"])
        plans = plan_bulk_import(self._sections(["a"]), adapter, ImportStrategy.MERGE.value)
        self.assertEqual(plans[0].action, "merge")
        self.assertTrue(plans[0].exists)
        self.assertEqual(plans[0].target_id, "a")

    def test_skip_strategy_skips_collision(self) -> None:
        adapter = FakeAdapter(["a"])
        plans = plan_bulk_import(self._sections(["a", "b"]), adapter, ImportStrategy.SKIP_EXISTING.value)
        self.assertEqual([p.action for p in plans], ["skip", "append"])

    def test_force_replace_strategy_replaces_collision(self) -> None:
        adapter = FakeAdapter(["a"])
        plans = plan_bulk_import(self._sections(["a"]), adapter, ImportStrategy.FORCE_REPLACE.value)
        self.assertEqual(plans[0].action, "replace")
        self.assertEqual(plans[0].target_id, "a")

    def test_append_new_strategy_assigns_unique_ids(self) -> None:
        adapter = FakeAdapter(["a"])
        plans = plan_bulk_import(
            self._sections(["a", "b"]),
            adapter,
            ImportStrategy.APPEND_AS_NEW.value,
        )
        # "a" collides -> append_new with a fresh id; "b" is free -> append as-is.
        self.assertEqual(plans[0].action, "append_new")
        self.assertEqual(plans[0].target_id, "a-2")
        self.assertEqual(plans[1].action, "append")
        self.assertEqual(plans[1].target_id, "b")

    def test_append_new_sequential_unique_ids(self) -> None:
        # Two colliding sections must get distinct fresh ids.
        adapter = FakeAdapter(["a"])
        plans = plan_bulk_import(
            self._sections(["a", "a"]),
            adapter,
            ImportStrategy.APPEND_AS_NEW.value,
        )
        self.assertEqual(plans[0].target_id, "a-2")
        self.assertEqual(plans[1].target_id, "a-3")
        self.assertEqual(plans[1].action, "append_new")

    def test_skip_keeps_source_id_unchanged(self) -> None:
        # A skipped section is not imported; its target_id stays the source id
        # (no suffixing) so the preview can show what was skipped.
        adapter = FakeAdapter(["a"])
        plans = plan_bulk_import(
            self._sections(["a", "a"]),
            adapter,
            ImportStrategy.SKIP_EXISTING.value,
        )
        self.assertEqual([p.action for p in plans], ["skip", "skip"])
        self.assertEqual([p.target_id for p in plans], ["a", "a"])


if __name__ == "__main__":
    unittest.main()
