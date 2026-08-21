"""v4.62 P2: item.similar skill."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.application.experience_handlers.memory_nav import (  # noqa: E402
    SIMILAR_ITEM_INSTRUCTION,
    _locate_item_in_course,
    handle_item_similar,
)
from src.backend.experience.actions import get_action  # noqa: E402
from src.backend.experience.intent_router import route_intent  # noqa: E402
from src.backend.ai_presets_ui import (  # noqa: E402
    ITEM_CHIP_INSTRUCTIONS,
    ITEM_CHIP_LABELS,
)


class LocateItemTest(unittest.TestCase):
    def _adapter(self):
        item = {"id": "i1", "runtimeType": "multipleChoice", "prompt": "hi"}
        stage = {"id": "st1", "items": [item]}
        lesson = {"id": "l1", "content": {"stages": [stage]}}
        unit = {"id": "u1", "lessons": [lesson]}
        section = {"id": "s1", "units": [unit]}

        class A:
            sections = [section]

            def find_lesson(self, lid):
                if lid == "l1":
                    return section, unit, lesson
                raise KeyError(lid)

        return A(), stage, item

    def test_locate(self) -> None:
        a, stage, item = self._adapter()
        st, it, lid = _locate_item_in_course(a, "i1")
        self.assertIs(st, stage)
        self.assertIs(it, item)
        self.assertEqual(lid, "l1")


class HandlerTest(unittest.TestCase):
    def test_no_item_status(self) -> None:
        status = MagicMock()
        host = SimpleNamespace(
            course_dir=Path("/tmp/c"),
            adapter=None,
            _current_node_ref=None,
            statusBar=MagicMock(return_value=status),
        )
        handle_item_similar(host, {})
        status.showMessage.assert_called()

    def test_calls_run_item_chip_with_similar_instruction(self) -> None:
        item = {"id": "i1", "runtimeType": "multipleChoice", "prompt": "hi"}
        stage = {"id": "st1", "items": [item]}
        lesson = {"id": "l1", "content": {"stages": [stage]}}
        unit = {"id": "u1", "lessons": [lesson]}
        section = {"id": "s1", "units": [unit]}

        class A:
            sections = [section]

            def find_lesson(self, lid):
                return section, unit, lesson

        host = SimpleNamespace(
            course_dir=Path("/tmp/c"),
            adapter=A(),
            undo_stack=MagicMock(),
            _current_node_ref=("item", "i1"),
            _on_ai_edit_applied=MagicMock(),
            _record_experience_event=MagicMock(),
            statusBar=MagicMock(return_value=MagicMock()),
        )
        with patch(
            "src.teacher.item_ai_chip.run_item_chip"
        ) as run:
            handle_item_similar(host, {"item_id": "i1", "lesson_id": "l1"})
        run.assert_called_once()
        kwargs = run.call_args.kwargs
        self.assertEqual(kwargs["instruction"], SIMILAR_ITEM_INSTRUCTION)
        self.assertEqual(kwargs["item"]["id"], "i1")
        # Keep id contract in instruction text.
        self.assertIn("id", kwargs["instruction"].lower())


class ContractTest(unittest.TestCase):
    def test_action(self) -> None:
        spec = get_action("item.similar")
        self.assertIsNotNone(spec)
        assert spec is not None
        self.assertTrue(spec.needs_confirm)
        self.assertFalse(spec.dangerous)

    def test_route(self) -> None:
        r = route_intent("/similar")
        self.assertIsNotNone(r)
        assert r is not None
        self.assertEqual(r.action_id, "item.similar")
        r2 = route_intent("出相似题")
        self.assertIsNotNone(r2)
        assert r2 is not None
        self.assertEqual(r2.action_id, "item.similar")

    def test_chip_has_similar(self) -> None:
        self.assertIn("相似", ITEM_CHIP_LABELS)
        self.assertEqual(len(ITEM_CHIP_LABELS), len(ITEM_CHIP_INSTRUCTIONS))
        self.assertIn("id", ITEM_CHIP_INSTRUCTIONS[-1].lower())


class BusyBadgeTest(unittest.TestCase):
    """v4.62 P6: node_badges busy from active_jobs."""

    def test_busy_from_jobs(self) -> None:
        from src.backend.experience.context_bus import (
            _build_node_badges,
            _busy_ids_from_jobs,
        )

        self.assertEqual(
            _busy_ids_from_jobs([{"node_key": "lesson:l9"}, SimpleNamespace(node_key="unit:u2")]),
            {"l9", "u2"},
        )
        badges = _build_node_badges(
            [],
            {},
            active_jobs=[{"node_key": "lesson:lx"}],
        )
        self.assertEqual(badges.get("lx", {}).get("busy"), 1)


if __name__ == "__main__":
    unittest.main()
