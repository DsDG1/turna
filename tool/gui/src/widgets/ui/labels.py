"""ElidedLabel — single-line label that ends in an ellipsis instead of wrapping.

Qt's ``QLabel`` either wraps (which costs vertical space in dense panels) or
clips hard at the widget edge (which silently cuts a word in half, so the reader
cannot tell whether text continues). This label keeps the full text in
``full_text`` and paints an elided version that tracks the current width.
"""
from __future__ import annotations

from PySide6.QtCore import Qt
from PySide6.QtWidgets import QLabel, QSizePolicy


class ElidedLabel(QLabel):
    """One line, always ends in "…" when the text does not fit."""

    def __init__(self, text: str = "", parent=None) -> None:
        super().__init__(text, parent)
        self._full_text = text
        self.setWordWrap(False)
        # Ignored horizontally: the label may shrink below its text width
        # instead of pushing the window wider.
        self.setSizePolicy(QSizePolicy.Policy.Ignored, QSizePolicy.Policy.Preferred)
        self.setTextInteractionFlags(Qt.TextInteractionFlag.TextSelectableByMouse)

    def setText(self, text: str) -> None:
        self._full_text = text
        self._apply_elide()

    def full_text(self) -> str:
        """The untruncated text (QLabel.text() returns the elided copy)."""
        return self._full_text

    def resizeEvent(self, event) -> None:
        super().resizeEvent(event)
        self._apply_elide()

    def _apply_elide(self) -> None:
        metrics = self.fontMetrics()
        width = max(0, self.contentsRect().width())
        elided = metrics.elidedText(self._full_text, Qt.TextElideMode.ElideRight, width)
        if elided != self.text():
            # Bypass our own setText override while painting the copy.
            QLabel.setText(self, elided)
