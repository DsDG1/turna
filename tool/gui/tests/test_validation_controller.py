"""S-10 final v4.56: validation_controller jump_to_node (pure)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import MagicMock

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.application.validation_controller import jump_to_node  # noqa: E402


class JumpToNodeTest(unittest.TestCase):
    def test_routes_kinds(self) -> None:
        tree = MagicMock()
        host = SimpleNamespace(tree=tree)
        jump_to_node(host, ("lesson", "l1"))
        tree.select_lesson.assert_called_with("l1")
        jump_to_node(host, ("section", "s1"))
        tree.select_section.assert_called_with("s1")
        jump_to_node(host, ("unit", "u1"))
        tree.select_unit.assert_called_with("u1")

    def test_missing_tree_safe(self) -> None:
        jump_to_node(SimpleNamespace(tree=None), ("lesson", "x"))


if __name__ == "__main__":
    unittest.main()
