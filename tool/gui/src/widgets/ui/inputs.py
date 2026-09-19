"""SearchField — debounced search input with a leading icon (UI kit)."""
from __future__ import annotations

from PySide6.QtCore import QTimer, Signal
from PySide6.QtWidgets import QLineEdit

from src.icons import icon


class SearchField(QLineEdit):
    """QLineEdit with a leading search icon, a clear button, and a debounced
    ``text_changed_debounced`` signal for filter-as-you-type.

    ``debounce_ms`` defaults to 250 (same convention as the tree-refresh
    debounce). Instant filtering code should connect to
    ``text_changed_debounced``; ``textChanged`` still fires per keystroke.
    """

    text_changed_debounced = Signal(str)

    def __init__(
        self,
        placeholder: str = "",
        *,
        debounce_ms: int = 250,
        parent=None,
    ) -> None:
        super().__init__(parent)
        self.setObjectName("SearchField")
        self.setPlaceholderText(placeholder)
        self.setClearButtonEnabled(True)
        self.addAction(
            icon("search", size=14, role="muted"),
            QLineEdit.ActionPosition.LeadingPosition,
        )
        self._debounce = QTimer(self)
        self._debounce.setSingleShot(True)
        self._debounce.setInterval(max(0, int(debounce_ms)))
        self._debounce.timeout.connect(self._emit_debounced)
        self.textChanged.connect(self._on_text_changed)

    def _on_text_changed(self, _text: str) -> None:
        self._debounce.start()

    def _emit_debounced(self) -> None:
        self.text_changed_debounced.emit(self.text())

    def set_debounce_ms(self, ms: int) -> None:
        self._debounce.setInterval(max(0, int(ms)))
