"""Tests for global button-text sizing: the app-wide size-policy filter and
the FlowLayout used by the teacher editor header."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from PySide6.QtWidgets import QApplication, QPushButton, QSizePolicy, QWidget

from src.app import _ButtonSizePolicyFilter
from src.widgets.flow_layout import FlowLayout

from tests._qtapp import _App


class ButtonSizePolicyFilterTest(unittest.TestCase):
    def setUp(self) -> None:
        self.app = _App.get()
        self.f = _ButtonSizePolicyFilter()
        self.app.installEventFilter(self.f)

    def tearDown(self) -> None:
        self.app.removeEventFilter(self.f)

    def test_button_gets_minimum_horizontal_policy(self) -> None:
        # Default is Preferred; the filter flips it to Minimum on polish so a
        # tight layout can't shrink the button below its text width.
        b = QPushButton("一个较长的按钮文字")
        b.ensurePolished()
        self.assertEqual(
            b.sizePolicy().horizontalPolicy(), QSizePolicy.Policy.Minimum
        )

    def test_filter_is_idempotent(self) -> None:
        b = QPushButton("x")
        b.ensurePolished()
        b.ensurePolished()  # second polish must not recurse or error
        self.assertEqual(
            b.sizePolicy().horizontalPolicy(), QSizePolicy.Policy.Minimum
        )


class FlowLayoutWrapTest(unittest.TestCase):
    def setUp(self) -> None:
        _App.get()

    def test_height_for_width_increases_when_narrow(self) -> None:
        # A flow layout must be taller (more rows) when its width is smaller.
        container = QWidget()
        flow = FlowLayout(container)
        for text in ("按钮一", "按钮二", "按钮三", "按钮四", "按钮五"):
            flow.addWidget(QPushButton(text))
        container.show()
        QApplication.processEvents()
        wide = flow.heightForWidth(4000)
        narrow = flow.heightForWidth(40)
        self.assertGreater(narrow, wide)
        self.assertGreaterEqual(narrow, wide)


if __name__ == "__main__":
    unittest.main()
