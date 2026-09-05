"""Non-modal sub-window for an enlarged wish-mode chat (guiplan2 P5.5).

Replaces the old in-place resize + hide-chrome hack. The window holds a second
``ChatView`` driven by the same message list as the in-panel chat, plus an input
row that emits the same ``send_requested`` signal the dialog already handles.
Geometry is persisted to QSettings so restore is exact (fixes the old
"还原错位" issue).
"""
from __future__ import annotations

import logging
logger = logging.getLogger(__name__)


from PySide6.QtCore import Qt, Signal
from PySide6.QtWidgets import (
    QDialog,
    QHBoxLayout,
    QLabel,
    QProgressBar,
    QPushButton,
    QTextEdit,
    QVBoxLayout,
    QWidget,
)

from src.dialogs.ai.chat_view import ChatView
from src.infrastructure.operations_log import operations
from src.infrastructure.window_usage import WindowUsageMixin
from src.theme_tokens import BRAND_REED


class ChatExpandWindow(WindowUsageMixin, QDialog):
    """Enlarged, resizable/maximizable chat surface (non-modal)."""

    send_requested = Signal()

    def __init__(self, chat_palette: dict[str, str], parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.setWindowTitle("许愿聊天（放大）")
        self.resize(900, 700)
        self.setMinimumSize(600, 400)
        self.setWindowFlag(Qt.WindowType.Window, True)
        self._palette = chat_palette

        layout = QVBoxLayout(self)
        layout.setContentsMargins(10, 10, 10, 10)
        layout.setSpacing(8)

        self.chat_view = ChatView()
        self.chat_view.restyle(chat_palette)
        layout.addWidget(self.chat_view, 1)

        # Slim progress/stage row mirroring the in-panel one.
        self.progress = QProgressBar()
        self.progress.setRange(0, 0)
        self.progress.setVisible(False)
        self.stage_label = QLabel("")
        self.stage_label.setStyleSheet(
            f"color: {chat_palette.get('ai_accent', BRAND_REED)}; font-size: 12px;"
        )
        self.stage_label.setVisible(False)
        self.usage_label = QLabel("")
        self.usage_label.setStyleSheet(
            f"color: {chat_palette.get('text_secondary', '#9CA3AF')}; font-size: 11px;"
        )
        prog_row = QHBoxLayout()
        prog_row.setSpacing(8)
        prog_row.addWidget(self.progress)
        prog_row.addWidget(self.stage_label)
        prog_row.addStretch()
        prog_row.addWidget(self.usage_label)
        layout.addLayout(prog_row)

        self.input_edit = QTextEdit()
        self.input_edit.setPlaceholderText("输入你想说的，Ctrl+Enter 发送...")
        self.input_edit.setMaximumHeight(120)
        self.input_edit.setStyleSheet(
            "QTextEdit {"
            f"  border: 1px solid {chat_palette.get('ai_bubble_bg', '#2C313C')};"
            "  border-radius: 8px;"
            f"  background-color: {chat_palette.get('ai_card_bg', '#1F232C')};"
            "  font-family: system-ui, sans-serif;"
            "  font-size: 14px;"
            "  padding: 8px;"
            "}"
        )
        input_row = QHBoxLayout()
        input_row.setSpacing(8)
        input_row.addWidget(self.input_edit, 1)
        btn_col = QVBoxLayout()
        btn_col.setSpacing(6)
        self.send_btn = QPushButton("发送")
        self.send_btn.setToolTip("Ctrl+Enter 快捷发送")
        self.send_btn.clicked.connect(self._emit_send)
        btn_col.addWidget(self.send_btn)
        btn_col.addStretch()
        input_row.addLayout(btn_col)
        layout.addLayout(input_row)

        self.input_edit.keyPressEvent = self._input_key_press  # type: ignore[method-assign]

    def _input_key_press(self, event) -> None:
        if event.key() in (Qt.Key.Key_Return, Qt.Key.Key_Enter) and (
            event.modifiers() == Qt.KeyboardModifier.ControlModifier
            or event.modifiers() == Qt.KeyboardModifier.NoModifier
        ):
            self._emit_send()
        else:
            QTextEdit.keyPressEvent(self.input_edit, event)

    def _emit_send(self) -> None:
        text = self.input_edit.toPlainText().strip()
        if not text:
            return
        try:
            operations.record_action(
                "chat.send",
                text[:200],
                context={"window": "ChatExpand"},
            )
        except Exception:
            logger.debug("dialogs/ai/chat_expand_window.py:118 best-effort step failed", exc_info=True)
        self.send_requested.emit()

    def render(self, messages) -> None:
        self.chat_view.render(messages, self._palette)

    def render_streaming(self, messages, partial_text: str) -> None:
        self.chat_view.render_streaming(messages, partial_text, self._palette)

    def set_stage(self, stage: str) -> None:
        self.stage_label.setText(stage)
        self.stage_label.setVisible(bool(stage))

    def set_busy(self, busy: bool) -> None:
        self.progress.setVisible(busy)

    def set_usage(self, line: str) -> None:
        self.usage_label.setText(line)

    def clear_input(self) -> None:
        self.input_edit.clear()

    def input_text(self) -> str:
        return self.input_edit.toPlainText()
