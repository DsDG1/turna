"""Draggable bubble widget for knowledge points (words, expressions, grammar points)."""
from __future__ import annotations

import json
from typing import Any

from PySide6.QtCore import Qt, QPoint, Signal
from PySide6.QtGui import QDrag, QPixmap, QPainter, QCursor
from PySide6.QtWidgets import (
    QApplication,
    QHBoxLayout,
    QLabel,
    QPushButton,
    QWidget,
)

from src.theme import current_palette
from src.theme_tokens import resource_type_color


class KnowledgeBubble(QWidget):
    """A visual pill/bubble widget representing a single knowledge point.
    
    Supports dragging via QMimeData with format 'application/x-knowledge-point'.
    """

    closed = Signal()

    def __init__(
        self,
        data: dict[str, Any],
        resource_type: str,  # "word" | "expression" | "grammarPoint"
        parent: QWidget | None = None,
        *,
        show_close: bool = False,
    ) -> None:
        super().__init__(parent)
        self.data = data
        self.resource_type = resource_type
        self.show_close = show_close
        self._drag_start_pos: QPoint | None = None

        self._build_ui()
        self._apply_style()

    def _build_ui(self) -> None:
        layout = QHBoxLayout(self)
        layout.setContentsMargins(10, 4, 10, 4)
        layout.setSpacing(6)

        # Retrieve displaying properties
        term = self.data.get("term") or self.data.get("title") or ""
        trans = self.data.get("translation") or self.data.get("explanation") or ""

        type_prefix = {
            "word": "词",
            "expression": "译",
            "grammarPoint": "法",
        }.get(self.resource_type, "•")

        self.prefix_label = QLabel(type_prefix)
        self.prefix_label.setStyleSheet("font-weight: bold; font-size: 10px; opacity: 0.8;")
        layout.addWidget(self.prefix_label)

        self.term_label = QLabel(term)
        self.term_label.setStyleSheet("font-weight: 600; font-size: 12px;")
        layout.addWidget(self.term_label)

        if trans:
            self.trans_label = QLabel(f"({trans})")
            self.trans_label.setStyleSheet("font-size: 11px; opacity: 0.7;")
            layout.addWidget(self.trans_label)

        if self.show_close:
            self.close_btn = QPushButton("×")
            self.close_btn.setFixedSize(14, 14)
            self.close_btn.setCursor(Qt.CursorShape.PointingHandCursor)
            self.close_btn.setStyleSheet(
                "QPushButton {"
                "  border: none;"
                "  background: transparent;"
                "  color: #FFFFFF;"
                "  font-weight: bold;"
                "  font-size: 12px;"
                "  line-height: 12px;"
                "  padding: 0;"
                "}"
                f"QPushButton:hover {{ color: {current_palette()['error']}; }}"
            )
            self.close_btn.clicked.connect(self.closed.emit)
            layout.addWidget(self.close_btn)

        self.setAttribute(Qt.WidgetAttribute.WA_StyledBackground, True)
        self.setCursor(Qt.CursorShape.OpenHandCursor)

    def _apply_style(self) -> None:
        # Styled pill colors - Turna-harmonized via theme_tokens.
        # Turna teal for words, emerald for expressions, amber for grammar points.
        bg = resource_type_color(self.resource_type)

        self.setStyleSheet(
            f"QWidget {{"
            f"  background-color: {bg};"
            f"  color: #FFFFFF;"
            f"  border-radius: 12px;"
            f"  border: none;"
            f"}}"
        )

    # --- Drag & Drop logic ----------------------------------------------------

    def mousePressEvent(self, event) -> None:  # noqa: N802
        if event.button() == Qt.MouseButton.LeftButton:
            self._drag_start_pos = event.pos()
            self.setCursor(Qt.CursorShape.ClosedHandCursor)
        super().mousePressEvent(event)

    def mouseReleaseEvent(self, event) -> None:  # noqa: N802
        self.setCursor(Qt.CursorShape.OpenHandCursor)
        super().mouseReleaseEvent(event)

    def mouseMoveEvent(self, event) -> None:  # noqa: N802
        if not (event.buttons() & Qt.MouseButton.LeftButton):
            return
        if self._drag_start_pos is None:
            return
        if (event.pos() - self._drag_start_pos).manhattanLength() < QApplication.startDragDistance():
            return

        drag = QDrag(self)
        from PySide6.QtCore import QMimeData
        mime = QMimeData()
        
        # Package data as JSON
        payload = {
            "entry": self.data,
            "resource_type": self.resource_type,
        }
        mime.setData("application/x-knowledge-point", json.dumps(payload, ensure_ascii=False).encode("utf-8"))
        drag.setMimeData(mime)

        # Grab visual pixmap of bubble for dragging visual
        pixmap = QPixmap(self.size())
        pixmap.fill(Qt.GlobalColor.transparent)
        self.render(pixmap)
        drag.setPixmap(pixmap)
        drag.setHotSpot(event.pos())

        drag.exec(Qt.DropAction.CopyAction)
        self.setCursor(Qt.CursorShape.OpenHandCursor)
