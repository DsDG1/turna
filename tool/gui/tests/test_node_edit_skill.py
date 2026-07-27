"""v4.61 K-05: section/unit/lesson.edit Experience wrap of _on_ai_edit."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import MagicMock

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.application.experience_handlers.edit import (  # noqa: E402
    handle_node_edit,
    resolve_edit_target,
)
from src.backend.experience.actions import get_action  # noqa: E402
from src.backend.experience.intent_router import route_intent  # noqa: E402
from src.backend.experience.suggestions.p3_structure import collect  # noqa: E402


class ResolveEditTargetTest(unittest.TestCase):
    def test_from_scope(self) -> None:
        host = SimpleNamespace(_current_node_ref=None)
        self.assertEqual(
            resolve_edit_target(host, {"kind": "lesson", "id": "l1"}),
            ("lesson", "l1"),
        )

    def test_from_action_prefix_and_selection(self) -> None:
        host = SimpleNamespace(_current_node_ref=("unit", "u9"))
        self.assertEqual(
            resolve_edit_target(host, {}, action_id="unit.edit"),
            ("unit", "u9"),
        )

    def test_none_without_selection(self) -> None:
        host = SimpleNamespace(_current_node_ref=None)
        self.assertIsNone(resolve_edit_target(host, {}))

    def test_rejects_item_kind(self) -> None:
        host = SimpleNamespace(_current_node_ref=("item", "i1"))
        self.assertIsNone(
            resolve_edit_target(host, {"kind": "item", "id": "i1"})
        )


class HandleNodeEditTest(unittest.TestCase):
    def test_no_selection_status(self) -> None:
        status = MagicMock()
        host = SimpleNamespace(
            _current_node_ref=None,
            statusBar=MagicMock(return_value=status),
            _on_ai_edit=MagicMock(),
        )
        handle_node_edit(host, {})
        status.showMessage.assert_called()
        host._on_ai_edit.assert_not_called()

    def test_delegates_to_on_ai_edit(self) -> None:
        host = SimpleNamespace(
            _current_node_ref=None,
            _on_ai_edit=MagicMock(),
            _record_experience_event=MagicMock(),
            experience_metrics=MagicMock(),
            statusBar=MagicMock(return_value=MagicMock()),
            _dispatch_action_id="section.edit",
        )
        handle_node_edit(host, {"kind": "section", "id": "s1"})
        host._on_ai_edit.assert_called_once_with("section", "s1")
        host._record_experience_event.assert_called()
        scope = host._record_experience_event.call_args.kwargs.get("scope") or {}
        self.assertEqual(scope.get("kind"), "section")
        self.assertEqual(scope.get("id"), "s1")
        self.assertNotIn("prompt", scope)


class ContractTest(unittest.TestCase):
    def test_actions_registered(self) -> None:
        for aid in ("section.edit", "unit.edit", "lesson.edit"):
            with self.subTest(aid=aid):
                spec = get_action(aid)
                self.assertIsNotNone(spec)
                assert spec is not None
                self.assertTrue(spec.needs_confirm)
                self.assertFalse(spec.dangerous)

    def test_route_slash_and_keyword(self) -> None:
        r = route_intent("/ai-edit")
        self.assertIsNotNone(r)
        assert r is not None
        self.assertEqual(r.action_id, "lesson.edit")
        r2 = route_intent("AI 编辑")
        self.assertIsNotNone(r2)
        assert r2 is not None
        self.assertEqual(r2.action_id, "lesson.edit")


class SuggestionTest(unittest.TestCase):
    def test_p3_offers_edit_for_tree_selection(self) -> None:
        ctx = SimpleNamespace(
            imbalanced_lessons=[],
            unsurfaced_words=[],
            empty_reading_passages=[],
            misaligned_pos_count=0,
            selection=SimpleNamespace(kind="lesson", id="l1"),
        )
        items = collect(ctx)
        aids = [i["action_id"] for i in items]
        self.assertIn("lesson.edit", aids)
        for i in items:
            if i["action_id"] == "lesson.edit":
                self.assertEqual(i["scope"].get("id"), "l1")
                self.assertNotIn("prompt", i["scope"])


if __name__ == "__main__":
    unittest.main()
