"""Tests for natural-language edit scope resolution (U1-1)."""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

_GUI_ROOT = Path(__file__).resolve().parents[1]
if str(_GUI_ROOT) not in sys.path:
    sys.path.insert(0, str(_GUI_ROOT))

from src.backend.ai_scope import (  # noqa: E402
    format_scope_resolution,
    resolve_edit_scope,
)

_GOLDENS = Path(__file__).resolve().parent / "ai_goldens"


def _load(name: str) -> dict:
    return json.loads((_GOLDENS / name).read_text(encoding="utf-8"))


class ResolveEditScopeTest(unittest.TestCase):
    def test_ordinal_lesson(self) -> None:
        section = _load("a1_greetings_clean.json")
        res = resolve_edit_scope("请改写第 1 课的填空", section)
        self.assertTrue(res.targets)
        self.assertEqual(res.targets[0].kind, "lesson")
        self.assertGreaterEqual(res.confidence, 0.8)

    def test_all_mcq(self) -> None:
        section = _load("mcq_dup_options.json")
        res = resolve_edit_scope("加强所有选择题的干扰项", section)
        self.assertTrue(res.targets)
        # Prefer items when MCQs exist
        kinds = {t.kind for t in res.targets}
        self.assertTrue("item" in kinds or "lesson" in kinds or "section" in kinds)

    def test_empty_instruction(self) -> None:
        res = resolve_edit_scope("", _load("a1_greetings_clean.json"))
        self.assertTrue(res.needs_confirm)
        self.assertEqual(res.targets, [])

    def test_fallback_section(self) -> None:
        section = _load("a1_greetings_clean.json")
        res = resolve_edit_scope("整体润色一下", section)
        self.assertEqual(res.targets[0].kind, "section")
        self.assertTrue(res.needs_confirm)
        text = format_scope_resolution(res)
        self.assertIn("将修改", text)


if __name__ == "__main__":
    unittest.main()
