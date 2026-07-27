"""v4.62 P4 / Q-03: table-driven write-skill contracts (L1 pure)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.experience.actions import ACTIONS, get_action  # noqa: E402


# Open-only / navigation may set needs_confirm=False (mirrors adversarial D2).
_READONLY_PREFIXES = (
    "app.",
    "help.",
    "git.",
    "attachment.",
    "memory.",
    "publish.",
    "resource.open",
    "resource.dedupe",
    "course.compare",
    "textbook.open",
    "textbook.ocr",
)


def _is_write_skill(action_id: str) -> bool:
    if any(action_id.startswith(p) for p in _READONLY_PREFIXES):
        return False
    # goal.plan/expand are planning; goal.run writes via merge.
    if action_id in ("goal.plan", "goal.expand"):
        return False
    return True


class SkillContractQ03Test(unittest.TestCase):
    def test_all_actions_registered(self) -> None:
        self.assertGreaterEqual(len(ACTIONS), 40)

    def test_write_skills_need_confirm(self) -> None:
        for aid, spec in ACTIONS.items():
            if not _is_write_skill(aid):
                continue
            with self.subTest(aid=aid):
                self.assertTrue(
                    spec.needs_confirm,
                    f"{aid} write skill must needs_confirm",
                )
                self.assertTrue(spec.implemented)

    def test_item_similar_contract(self) -> None:
        spec = get_action("item.similar")
        self.assertIsNotNone(spec)
        assert spec is not None
        self.assertTrue(spec.needs_confirm)
        self.assertFalse(spec.dangerous)

    def test_node_edit_contract(self) -> None:
        for aid in ("section.edit", "unit.edit", "lesson.edit"):
            with self.subTest(aid=aid):
                spec = get_action(aid)
                self.assertIsNotNone(spec)
                assert spec is not None
                self.assertTrue(spec.needs_confirm)


if __name__ == "__main__":
    unittest.main()
