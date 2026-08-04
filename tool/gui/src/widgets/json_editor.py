"""A small JSON editor widget with syntax highlighting + formatting (guiplan2 P3.2).

Wraps ``QPlainTextEdit`` with a ``QSyntaxHighlighter`` (keys / strings / numbers
/ booleans / null), a ``Ctrl+Shift+F`` pretty-print action, and per-line error
markers for parse failures. Colors come from the active theme palette so the
editor follows the light/dark theme.
"""
from __future__ import annotations

import json
from typing import Any

from PySide6.QtCore import Qt, Signal
from PySide6.QtGui import (
    QColor,
    QSyntaxHighlighter,
    QTextCharFormat,
    QTextCursor,
)
from PySide6.QtWidgets import QPlainTextEdit, QWidget

try:  # theme is optional at import time (tests may not apply_theme)
    from src.theme import current_palette
except Exception:  # noqa: BLE001
    current_palette = None  # type: ignore[assignment]


def _palette() -> dict[str, str]:
    if current_palette is not None:
        try:
            return current_palette()
        except Exception:  # noqa: BLE001
            pass
    return {
        "ai_accent": "#78C7B8",
        "text": "#E8EAF0",
        "text_secondary": "#9CA3AF",
        "warning": "#FF9F43",
        "error": "#E74C3C",
        "ai_card_bg": "#1F232C",
    }


class _JsonHighlighter(QSyntaxHighlighter):
    """Minimal JSON syntax highlighter."""

    def __init__(self, parent, palette: dict[str, str]) -> None:
        super().__init__(parent)
        self._fmts = self._build_formats(palette)

    def _build_formats(self, p: dict[str, str]) -> dict[str, QTextCharFormat]:
        fmts: dict[str, QTextCharFormat] = {}

        def mk(color: str, bold: bool = False) -> QTextCharFormat:
            f = QTextCharFormat()
            f.setForeground(QColor(color))
            if bold:
                f.setFontWeight(700)
            return f

        fmts["key"] = mk(p.get("ai_accent", "#78C7B8"), bold=True)
        fmts["string"] = mk(p.get("text", "#E8EAF0"))
        fmts["number"] = mk(p.get("warning", "#FF9F43"))
        fmts["keyword"] = mk(p.get("text_secondary", "#9CA3AF"))
        return fmts

    def set_palette(self, palette: dict[str, str]) -> None:
        self._fmts = self._build_formats(palette)
        self.rehighlight()

    def highlightBlock(self, text: str) -> None:  # noqa: N802 (Qt API)
        # Tokenize a single line. JSON is line-oriented enough for a simple
        # scanner; this is intentionally lightweight (no multi-line strings).
        i = 0
        n = len(text)
        while i < n:
            c = text[i]
            if c == '"':
                # Find the closing quote (no escape handling beyond \").
                j = i + 1
                while j < n:
                    if text[j] == "\\" and j + 1 < n:
                        j += 2
                        continue
                    if text[j] == '"':
                        break
                    j += 1
                # Determine key vs string value: a key is a quoted string
                # followed (after whitespace) by ':'.
                k = j + 1
                while k < n and text[k] in " \t":
                    k += 1
                kind = "key" if k < n and text[k] == ":" else "string"
                self.setFormat(i, j - i + 1, self._fmts[kind])
                i = j + 1
            elif c in "-0123456789":
                j = i + 1
                while j < n and text[j] in "-0123456789.eE+":
                    j += 1
                self.setFormat(i, j - i, self._fmts["number"])
                i = j
            elif c.isalpha():
                j = i
                while j < n and text[j].isalpha():
                    j += 1
                word = text[i:j]
                if word in ("true", "false", "null"):
                    self.setFormat(i, j - i, self._fmts["keyword"])
                i = j
            else:
                i += 1


class JsonEditor(QPlainTextEdit):
    """QPlainTextEdit + JSON highlighting + format action + error markers."""

    error_marked = Signal(int, str)  # line_no (1-based), message

    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.setPlaceholderText("点击「生成课程」后，JSON 会显示在这里供你检查与修改。")
        self._highlighter = _JsonHighlighter(self.document(), _palette())
        self._error_line: int | None = None

    # --- public API ------------------------------------------------------

    def restyle(self, palette: dict[str, str]) -> None:
        self._highlighter.set_palette(palette)
        bg = palette.get("ai_card_bg", "#1F232C")
        fg = palette.get("text", "#E8EAF0")
        self.setStyleSheet(
            f"QPlainTextEdit {{ background-color: {bg}; color: {fg}; "
            "font-family: Consolas, 'JetBrains Mono', monospace; font-size: 12px; "
            f"border: 1px solid {palette.get('ai_bubble_bg', '#2C313C')}; border-radius: 6px; }}"
        )

    def set_json(self, obj: Any) -> None:
        """Replace the editor content with a pretty-printed JSON object."""
        self.setPlainText(json.dumps(obj, ensure_ascii=False, indent=2))
        self.clear_errors()

    def to_json(self) -> Any:
        """Parse and return the current JSON content (raises ValueError)."""
        raw = self.toPlainText().strip()
        if not raw:
            raise ValueError("JSON 为空。")
        try:
            return json.loads(raw)
        except json.JSONDecodeError as exc:
            self.mark_error(getattr(exc, "lineno", 1) or 1, str(exc))
            raise ValueError(f"JSON 解析失败: {exc}") from exc

    def format(self) -> bool:
        """Pretty-print the current content. Returns True on success."""
        raw = self.toPlainText().strip()
        if not raw:
            return True
        try:
            data = json.loads(raw)
        except json.JSONDecodeError as exc:
            self.mark_error(getattr(exc, "lineno", 1) or 1, str(exc))
            return False
        self.setPlainText(json.dumps(data, ensure_ascii=False, indent=2))
        self.clear_errors()
        return True

    def mark_error(self, line_no: int, message: str) -> None:
        """Highlight a parse-error line and jump to it (1-based line)."""
        self._error_line = max(1, line_no)
        cursor = QTextCursor(self.document())
        cursor.movePosition(QTextCursor.MoveOperation.Start)
        for _ in range(self._error_line - 1):
            cursor.movePosition(QTextCursor.MoveOperation.Down)
        cursor.movePosition(QTextCursor.MoveOperation.StartOfLine)
        cursor.movePosition(QTextCursor.MoveOperation.EndOfLine, QTextCursor.MoveMode.KeepAnchor)
        fmt = QTextCharFormat()
        fmt.setBackground(QColor(_palette().get("error", "#E74C3C")))
        fmt.setForeground(QColor("#FFFFFF"))
        cursor.mergeCharFormat(fmt)
        # Move the visible cursor onto the line so it scrolls into view.
        self.setTextCursor(cursor)
        self.error_marked.emit(self._error_line, message)

    def clear_errors(self) -> None:
        if self._error_line is None:
            return
        self._error_line = None
        # Re-highlight to drop the per-line char format override.
        self._highlighter.rehighlight()

    # --- key handling ----------------------------------------------------

    def keyPressEvent(self, event) -> None:  # noqa: N802 (Qt API)
        if (
            event.key() == Qt.Key.Key_F
            and event.modifiers() == (Qt.KeyboardModifier.ControlModifier | Qt.KeyboardModifier.ShiftModifier)
        ):
            self.format()
            return
        super().keyPressEvent(event)