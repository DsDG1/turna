"""C-04 / v4.57: selection_hub focus protocol."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import MagicMock

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.application.selection_hub import (  # noqa: E402
    apply_teacher_item_focus,
    apply_tree_selection,
    sync_focus,
)


class SelectionHubTest(unittest.TestCase):
    def test_apply_tree_selection(self) -> None:
        exp = MagicMock()
        host = SimpleNamespace(
            teacher_mode=False,
            _current_node_ref=None,
            experience=exp,
            _sync_focus_ring=MagicMock(),
            _refresh_experience=MagicMock(),
        )
        apply_tree_selection(
            host, ("lesson", "l1"), multi=[("lesson", "l1"), ("lesson", "l2")]
        )
        self.assertEqual(host._current_node_ref, ("lesson", "l1"))
        exp.set_surface.assert_called_with("tree")
        exp.set_selection.assert_called()
        host._sync_focus_ring.assert_called()
        host._refresh_experience.assert_called_with(
            immediate=False, focus_only=True
        )

    def test_teacher_item_focus(self) -> None:
        exp = MagicMock()
        host = SimpleNamespace(
            experience=exp,
            _teacher_focused_item_id=None,
            _sync_focus_ring=MagicMock(),
            _refresh_experience=MagicMock(),
        )
        apply_teacher_item_focus(host, "item-9")
        self.assertEqual(host._teacher_focused_item_id, "item-9")
        exp.set_selection.assert_called_with(("item", "item-9"))
        host._refresh_experience.assert_called_with(
            immediate=True, focus_only=True
        )

    def test_sync_focus_never_raises(self) -> None:
        host = SimpleNamespace(
            _sync_focus_ring=MagicMock(side_effect=RuntimeError("x")),
            _refresh_experience=MagicMock(),
        )
        sync_focus(host)  # must not raise


if __name__ == "__main__":
    unittest.main()
