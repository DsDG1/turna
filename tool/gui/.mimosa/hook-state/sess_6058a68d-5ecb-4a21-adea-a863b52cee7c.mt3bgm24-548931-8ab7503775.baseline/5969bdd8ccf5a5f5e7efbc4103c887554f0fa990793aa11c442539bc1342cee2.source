"""R-04 teacher keyboard helpers (pure logic + focus checks).

``[`` / ``]`` navigate Dock suggestions (wired by MainWindow + ExperienceDock).

Shortcuts must not steal keys from QLineEdit / QTextEdit / QComboBox /
QSpinBox (or other editable controls).
"""
from __future__ import annotations

from typing import Any

# Qt types imported lazily in helpers that need isinstance checks so pure
# unit tests can import this module without a display.


def is_editable_text_focus(widget: Any) -> bool:
    """True when *widget* is a free-text / spin / combo editor."""
    if widget is None:
        return False
    try:
        from PySide6.QtWidgets import (
            QAbstractSpinBox,
            QComboBox,
            QLineEdit,
            QPlainTextEdit,
            QTextEdit,
        )
    except Exception:
        return False
    return isinstance(
        widget, (QLineEdit, QTextEdit, QPlainTextEdit, QComboBox, QAbstractSpinBox)
    )


def should_handle_suggestion_nav(focus_widget: Any) -> bool:
    """``[``/``]`` only when focus is not an editable text control."""
    return not is_editable_text_focus(focus_widget)


def next_suggestion_index(
    current: int | None, count: int, *, delta: int
) -> int | None:
    """Move suggestion focus by *delta*; wraps; None when count==0."""
    if count <= 0:
        return None
    if current is None:
        return 0 if delta >= 0 else count - 1
    return (int(current) + int(delta)) % count
