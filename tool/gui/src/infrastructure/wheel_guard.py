"""Global QApplication event filter disabling wheel-driven value edits.

Installed once in ``main.py`` via ``install_wheel_guard(app)``. By default
Qt lets the mouse wheel adjust ``QSpinBox`` / ``QDoubleSpinBox`` /
``QDateTimeEdit`` / ``QComboBox`` (and sliders) simply on hover — scrolling
a form then silently rewrites timeouts, temperatures, ports, undo limits.
The guard blocks those wheel events app-wide; when the widget sits inside a
scroll area the scroll is forwarded to its vertical scrollbar instead, so
wheeling over a value widget scrolls the page like anywhere else.

Explicit adjustment stays available: arrow keys, typing, the spin buttons,
and the dropdown remain untouched. Combo popups (internal list views) are
not intercepted, so wheel-scrolling an open dropdown list still works.

Like :class:`UserActionFilter`, the filter never raises; on any internal
error it lets normal Qt dispatch proceed.
"""
from __future__ import annotations

import logging

from PySide6.QtCore import QEvent, QObject
from PySide6.QtGui import QWheelEvent
from PySide6.QtWidgets import (
    QAbstractScrollArea,
    QAbstractSlider,
    QAbstractSpinBox,
    QApplication,
    QComboBox,
    QScrollBar,
    QWidget,
)

logger = logging.getLogger(__name__)

# Fallback lines-per-notch when styleHints() is unavailable (matches Qt's
# default of 3 wheel scroll lines).
_DEFAULT_WHEEL_LINES = 3


def _wheel_lines() -> int:
    """System wheel scroll lines, falling back to the Qt default."""
    try:
        app = QApplication.instance()
        if app is not None:
            lines = app.styleHints().wheelScrollLines()
            if lines > 0:
                return lines
    except Exception:
        logger.debug("wheel_guard: styleHints unavailable", exc_info=True)
    return _DEFAULT_WHEEL_LINES


def _scroll_enclosing_area(widget: QWidget, event: QWheelEvent) -> bool:
    """Scroll the nearest scroll-area ancestor by *event*'s notch count.

    Returns True when a scrollbar moved, False when there is nothing to
    scroll (no ancestor scroll area, or its vertical bar is inert).
    """
    area: QWidget | None = widget
    while area is not None and not isinstance(area, QAbstractScrollArea):
        area = area.parentWidget()
    if area is None:
        return False
    bar = area.verticalScrollBar()
    if bar is None or bar.maximum() == bar.minimum():
        return False
    notch_count = event.angleDelta().y() / 120
    if notch_count == 0:
        return False
    step = bar.singleStep()
    if step <= 0:
        step = 20
    # Wheel up (positive notch) scrolls toward the top: value decreases.
    bar.setValue(round(bar.value() - notch_count * step * _wheel_lines()))
    return True


class WheelGuard(QObject):
    """Blocks wheel-driven value edits; scrolls the enclosing page instead."""

    def eventFilter(self, obj: QObject, event: QEvent) -> bool:
        if event.type() != QEvent.Type.Wheel:
            return False
        try:
            # QScrollBar is a QAbstractSlider subclass — never intercept it,
            # or all scrolling would die. (QSlider/QDial are covered.)
            if isinstance(obj, (QAbstractSpinBox, QComboBox)) or (
                isinstance(obj, QAbstractSlider) and not isinstance(obj, QScrollBar)
            ):
                _scroll_enclosing_area(obj, event)
                return True  # consume: the value must never change
        except Exception:
            logger.debug("wheel_guard: filter step failed", exc_info=True)
        return False


def install_wheel_guard(app: QApplication) -> WheelGuard:
    """Install the app-wide wheel guard; safe to call once per process."""
    guard = WheelGuard(app)
    app.installEventFilter(guard)
    return guard
