"""FlowLayout — left-to-right layout that wraps at the available width.

Qt ships no flow layout. Rows built from ``QHBoxLayout`` cannot wrap, so a
row with many buttons (project-library footer, log filter row, …) forces the
dialog's minimum width past small screens — and when the window cannot grow
(embedded panels), the buttons get squeezed below their text width and the
labels clip. :class:`FlowLayout` keeps every item at its own size hint and
wraps to the next line instead, based on the Qt flow-layout reference
implementation.
"""
from __future__ import annotations

from PySide6.QtCore import QPoint, QRect, QSize, Qt
from PySide6.QtWidgets import QLayout, QStyle


class FlowLayout(QLayout):
    """Wrapping horizontal layout; items keep their size hints."""

    def __init__(self, parent=None, margin: int = 0, hspacing: int = -1, vspacing: int = -1) -> None:
        super().__init__(parent)
        self.setContentsMargins(margin, margin, margin, margin)
        self._hspacing = hspacing
        self._vspacing = vspacing
        self._items: list = []

    # --- QLayout item plumbing -------------------------------------------

    def addItem(self, item) -> None:
        self._items.append(item)

    def count(self) -> int:
        return len(self._items)

    def itemAt(self, index: int):
        if 0 <= index < len(self._items):
            return self._items[index]
        return None

    def takeAt(self, index: int):
        if 0 <= index < len(self._items):
            return self._items.pop(index)
        return None

    def expandingDirections(self) -> Qt.Orientations:
        return Qt.Orientations(Qt.Orientation(0))

    def hasHeightForWidth(self) -> bool:
        return True

    def heightForWidth(self, width: int) -> int:
        return self._do_layout(QRect(0, 0, width, 0), test_only=True)

    def setGeometry(self, rect: QRect) -> None:
        super().setGeometry(rect)
        self._do_layout(rect, test_only=False)

    def sizeHint(self) -> QSize:
        return self.minimumSize()

    # --- spacing ----------------------------------------------------------

    def horizontalSpacing(self) -> int:
        return self._hspacing if self._hspacing >= 0 else self._smart_spacing(
            QStyle.PixelMetric.PM_LayoutHorizontalSpacing
        )

    def verticalSpacing(self) -> int:
        return self._vspacing if self._vspacing >= 0 else self._smart_spacing(
            QStyle.PixelMetric.PM_LayoutVerticalSpacing
        )

    def _smart_spacing(self, pm: QStyle.PixelMetric) -> int:
        parent = self.parent()
        if parent is None:
            return 6
        holder = parent if parent.isWidgetType() else parent.parentWidget()
        if holder is None:
            return 6
        value = holder.style().pixelMetric(pm, None, holder)
        return value if value >= 0 else 6

    # --- geometry -----------------------------------------------------------

    def minimumSize(self) -> QSize:
        size = QSize()
        for item in self._items:
            size = size.expandedTo(item.minimumSize())
        margins = self.contentsMargins()
        size += QSize(margins.left() + margins.right(), margins.top() + margins.bottom())
        return size

    def _do_layout(self, rect: QRect, *, test_only: bool) -> int:
        margins = self.contentsMargins()
        effective = rect.adjusted(
            margins.left(), margins.top(), -margins.right(), -margins.bottom()
        )
        hspace = self.horizontalSpacing()
        vspace = self.verticalSpacing()
        x, y = effective.x(), effective.y()
        line_height = 0

        for item in self._items:
            hint = item.sizeHint()
            width = (item.hasHeightForWidth() and item.heightForWidth(hint.width())) or hint.width()
            next_x = x + width + hspace
            if next_x - hspace > effective.right() + 1 and line_height > 0:
                x = effective.x()
                y = y + line_height + vspace
                line_height = 0
                next_x = x + width + hspace
            if not test_only:
                item.setGeometry(QRect(QPoint(x, y), QSize(width, hint.height())))
            x = next_x
            line_height = max(line_height, hint.height())

        return y + line_height - rect.y() + margins.bottom()
