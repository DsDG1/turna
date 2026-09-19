"""Wheel guard: wheel no longer adjusts spin boxes / combos app-wide."""
from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from PySide6.QtCore import QPoint, QPointF, Qt
from PySide6.QtGui import QWheelEvent
from PySide6.QtWidgets import (
    QApplication,
    QComboBox,
    QDoubleSpinBox,
    QScrollArea,
    QSpinBox,
    QVBoxLayout,
    QWidget,
)

from src.infrastructure.wheel_guard import install_wheel_guard
from tests._qtapp import _App


def _send_wheel(widget: QWidget, delta_y: int = 120) -> None:
    """Deliver a wheel notch to *widget* as if the mouse hovered over it."""
    pos = QPointF(widget.width() / 2, widget.height() / 2)
    event = QWheelEvent(
        pos,
        pos,
        QPoint(0, 0),
        QPoint(0, delta_y),
        Qt.MouseButton.NoButton,
        Qt.KeyboardModifier.NoModifier,
        Qt.ScrollPhase.NoScrollPhase,
        False,
    )
    QApplication.sendEvent(widget, event)


class WheelGuardTest(unittest.TestCase):
    def setUp(self) -> None:
        app = _App.get()
        self._guard = install_wheel_guard(app)
        self.addCleanup(app.removeEventFilter, self._guard)

    def test_spinbox_wheel_blocked(self) -> None:
        spin = QSpinBox()
        spin.setRange(0, 100)
        spin.setValue(50)
        spin.resize(120, 24)
        _send_wheel(spin, 120)
        _send_wheel(spin, -240)
        self.assertEqual(spin.value(), 50)

    def test_double_spinbox_wheel_blocked(self) -> None:
        spin = QDoubleSpinBox()
        spin.setRange(0.0, 10.0)
        spin.setValue(5.0)
        spin.resize(120, 24)
        _send_wheel(spin, 120)
        self.assertEqual(spin.value(), 5.0)

    def test_combo_wheel_blocked(self) -> None:
        combo = QComboBox()
        combo.addItem("a", 1)
        combo.addItem("b", 2)
        combo.setCurrentIndex(0)
        combo.resize(120, 24)
        _send_wheel(combo, 120)
        self.assertEqual(combo.currentIndex(), 0)

    def test_wheel_over_spinbox_scrolls_enclosing_area(self) -> None:
        area = QScrollArea()
        area.setWidgetResizable(True)
        content = QWidget()
        content.setMinimumHeight(800)
        lay = QVBoxLayout(content)
        spin = QSpinBox()
        spin.setRange(0, 100)
        spin.setValue(10)
        lay.addWidget(spin)
        area.setWidget(content)
        area.resize(200, 150)
        area.show()
        _App.get().processEvents()

        self.assertEqual(area.verticalScrollBar().value(), 0)
        _send_wheel(spin, -120)  # wheel down: page scrolls down, value intact
        self.assertGreater(area.verticalScrollBar().value(), 0)
        self.assertEqual(spin.value(), 10)
        area.hide()

    def test_plain_viewport_scroll_still_works(self) -> None:
        """The guard must not break wheel scrolling on non-value widgets."""
        area = QScrollArea()
        area.setWidgetResizable(True)
        content = QWidget()
        content.setMinimumHeight(800)
        area.setWidget(content)
        area.resize(200, 150)
        area.show()
        _App.get().processEvents()

        _send_wheel(area.viewport(), -120)
        self.assertGreater(area.verticalScrollBar().value(), 0)
        area.hide()

    def test_without_guard_wheel_still_adjusts(self) -> None:
        """Sanity: the wheel event itself triggers default Qt handling."""
        app = _App.get()
        app.removeEventFilter(self._guard)
        self.addCleanup(app.installEventFilter, self._guard)
        spin = QSpinBox()
        spin.setRange(0, 100)
        spin.setValue(50)
        spin.resize(120, 24)
        _send_wheel(spin, 120)
        self.assertEqual(spin.value(), 51)


if __name__ == "__main__":
    unittest.main()
