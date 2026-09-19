"""Toast / ToastHost — stacked transient notifications (UI kit).

Non-blocking alternative to informational ``QMessageBox``: toasts stack
bottom-right inside the parent window, auto-dismiss after ~4s, and are
clickable to dismiss early. Confirmations and errors still belong in modals.
"""
from __future__ import annotations

import contextlib
import logging

from PySide6.QtCore import QEasingCurve, QEvent, QPropertyAnimation, Qt, QTimer
from PySide6.QtGui import QCursor
from PySide6.QtWidgets import (
    QFrame,
    QGraphicsOpacityEffect,
    QHBoxLayout,
    QLabel,
    QToolButton,
    QWidget,
)

from src.icons import icon

logger = logging.getLogger(__name__)

_SEVERITY_ICON = {
    "info": "info",
    "success": "check-circle",
    "warning": "alert-triangle",
    "danger": "alert-circle",
}
_SEVERITY_ROLE = {
    "info": "info",
    "success": "success",
    "warning": "warning",
    "danger": "danger",
}

_MARGIN = 16
_GAP = 8


class Toast(QFrame):
    """One notification card: severity icon + message + close button."""

    def __init__(
        self,
        message: str,
        *,
        severity: str = "info",
        parent=None,
    ) -> None:
        super().__init__(parent)
        self.setObjectName("Toast")
        self.setProperty(
            "severity", severity if severity in _SEVERITY_ICON else "info"
        )
        self.setFrameShape(QFrame.Shape.NoFrame)
        self.setCursor(Qt.CursorShape.PointingHandCursor)

        row = QHBoxLayout(self)
        row.setContentsMargins(12, 8, 8, 8)
        row.setSpacing(8)

        sev = str(self.property("severity"))
        self._icon_label = QLabel(self)
        self._icon_label.setPixmap(
            icon(_SEVERITY_ICON[sev], size=16, role=_SEVERITY_ROLE[sev]).pixmap(16)
        )
        row.addWidget(self._icon_label, 0, Qt.AlignmentFlag.AlignTop)

        self._label = QLabel(message, self)
        self._label.setObjectName("ToastMessage")
        self._label.setWordWrap(True)
        row.addWidget(self._label, stretch=1)

        self._close = QToolButton(self)
        self._close.setAutoRaise(True)
        self._close.setIcon(icon("x", size=12, role="muted"))
        self._close.setToolTip("关闭")
        self._close.clicked.connect(self.dismiss)
        row.addWidget(self._close, 0, Qt.AlignmentFlag.AlignTop)

        self.adjustSize()
        self.setMinimumWidth(220)
        self.setMaximumWidth(420)

    def mousePressEvent(self, event) -> None:
        # Click anywhere on the card dismisses (except the close button's own
        # area — it handles itself).
        if event.button() == Qt.MouseButton.LeftButton:
            self.dismiss()
            return
        super().mousePressEvent(event)

    def dismiss(self) -> None:
        host = self.parent()
        self.hide()
        self.deleteLater()
        if isinstance(host, ToastHost):
            host._on_toast_dismissed(self)


class ToastHost(QWidget):
    """Transparent overlay pinned to a parent widget's bottom-right corner.

    Construct once against the window whose content area should host toasts::

        self.toast_host = ToastHost(self)
        self.toast_host.show_toast("已保存", severity="success")

    The overlay is click-through (``WA_TransparentForMouseEvents``); each
    :class:`Toast` child is positioned manually and remains interactive.
    """

    _MAX_STACK = 5

    def __init__(self, parent: QWidget) -> None:
        super().__init__(parent)
        self.setAttribute(Qt.WidgetAttribute.WA_TransparentForMouseEvents, True)
        self.setAttribute(Qt.WidgetAttribute.WA_StyledBackground, False)
        self._toasts: list[Toast] = []
        parent.installEventFilter(self)
        self._track_geometry()

    def eventFilter(self, obj, event) -> bool:
        if obj is self.parent() and event.type() in (
            QEvent.Type.Resize,
            QEvent.Type.Move,
        ):
            self._track_geometry()
            self._relayout()
        return super().eventFilter(obj, event)

    def _track_geometry(self) -> None:
        parent = self.parent()
        if parent is not None:
            self.setGeometry(parent.rect())

    # --- public API ----------------------------------------------------

    def show_toast(
        self,
        message: str,
        *,
        severity: str = "info",
        duration_ms: int = 4000,
    ) -> Toast:
        """Push a toast; oldest beyond ``_MAX_STACK`` are dropped."""
        toast = Toast(message, severity=severity, parent=self)
        toast.setAttribute(Qt.WidgetAttribute.WA_TransparentForMouseEvents, False)
        toast.show()
        toast.raise_()
        self._toasts.append(toast)
        while len(self._toasts) > self._MAX_STACK:
            oldest = self._toasts.pop(0)
            oldest.hide()
            oldest.deleteLater()
        self._relayout()
        self.raise_()
        if duration_ms > 0:
            QTimer.singleShot(duration_ms, toast.dismiss)
        return toast

    def info(self, message: str, **kw) -> Toast:
        return self.show_toast(message, severity="info", **kw)

    def success(self, message: str, **kw) -> Toast:
        return self.show_toast(message, severity="success", **kw)

    def warning(self, message: str, **kw) -> Toast:
        return self.show_toast(message, severity="warning", **kw)

    def clear(self) -> None:
        for toast in list(self._toasts):
            toast.hide()
            toast.deleteLater()
        self._toasts.clear()

    def _on_toast_dismissed(self, toast: Toast) -> None:
        with contextlib.suppress(ValueError):
            self._toasts.remove(toast)
        self._relayout()

    # --- layout ---------------------------------------------------------

    def _relayout(self) -> None:
        """Stack live toasts upward from the bottom-right corner."""
        y = self.height() - _MARGIN
        for toast in reversed(self._toasts):
            toast.adjustSize()
            h = toast.height()
            y -= h
            x = self.width() - _MARGIN - toast.width()
            toast.move(max(_MARGIN, x), max(_MARGIN, y))
            y -= _GAP
