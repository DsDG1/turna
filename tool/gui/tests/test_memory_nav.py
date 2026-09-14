"""Regression tests for memory_nav clear-author confirmation.

The GUI confirm branch once ignored the ``QMessageBox.question`` reply and
never assigned ``ok``, so clicking Yes/No raised UnboundLocalError at the
``if not ok:`` gate instead of clearing / cancelling.
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from PySide6.QtWidgets import QApplication, QMessageBox  # noqa: E402

from src.application.experience_handlers.memory_nav import (  # noqa: E402
    _experience_clear_author,
)


class _FakeApp:
    """Stands in for QApplication.instance() with a non-offscreen platform."""

    @staticmethod
    def platformName() -> str:
        return "windows"


def _memory() -> SimpleNamespace:
    return SimpleNamespace(
        author=SimpleNamespace(snapshot=lambda: {"style": "x"}),
        clear_author=MagicMock(),
    )


def _host(mem: SimpleNamespace) -> SimpleNamespace:
    return SimpleNamespace(
        experience_memory=mem,
        statusBar=MagicMock(return_value=MagicMock()),
        experience_metrics=MagicMock(),
    )


class ClearAuthorConfirmTest(unittest.TestCase):
    def test_gui_confirm_yes_clears_memory(self) -> None:
        mem = _memory()
        host = _host(mem)
        with (
            patch.object(QApplication, "instance", return_value=_FakeApp()),
            patch(
                "PySide6.QtWidgets.QMessageBox.question",
                return_value=QMessageBox.StandardButton.Yes,
            ),
        ):
            _experience_clear_author(host, {})  # must not raise
        mem.clear_author.assert_called_once()
        host.experience_metrics.inc_suggestion.assert_any_call(
            "memory.clear_author", "applied"
        )

    def test_gui_confirm_no_skips_clear(self) -> None:
        mem = _memory()
        host = _host(mem)
        with (
            patch.object(QApplication, "instance", return_value=_FakeApp()),
            patch(
                "PySide6.QtWidgets.QMessageBox.question",
                return_value=QMessageBox.StandardButton.No,
            ),
        ):
            _experience_clear_author(host, {})
        mem.clear_author.assert_not_called()
        host.experience_metrics.inc_suggestion.assert_any_call(
            "memory.clear_author", "rejected"
        )


if __name__ == "__main__":
    unittest.main()
