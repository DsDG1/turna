"""Chat history, attachments and expand window coordination for AI dialog.

Decoupled from AiGeneratorDialog.
"""
from __future__ import annotations

import html
import logging
import shutil
import tempfile
import uuid
from pathlib import Path
from typing import Any

from PySide6.QtCore import QObject, QSettings, Qt, Signal
from PySide6.QtWidgets import (
    QMessageBox,
    QPushButton,
    QTextEdit,
    QWidget,
)

from src.backend.ai import ChatMessage
from src.backend.attachment_extractor import extract_attachment
from src.dialogs.ai.attachment_bar import AttachmentBar
from src.dialogs.ai.chat_expand_window import ChatExpandWindow
from src.application.ai_request_worker import AttachmentRecord

logger = logging.getLogger(__name__)


def escape_html(text: str) -> str:
    """Escape text for safe inclusion in Qt rich text."""
    return html.escape(text).replace("\n", "<br>")


class GeneratorChatCoordinator(QObject):
    """Manages wish-mode chat messages, attachments, and the expand sub-window."""

    messages_updated = Signal()

    def __init__(self, parent: QObject | None = None) -> None:
        super().__init__(parent)
        self.messages: list[ChatMessage] = []
        self.attachments: list[AttachmentRecord] = []
        self.chat_expand_window: ChatExpandWindow | None = None

    def clear(self) -> None:
        self.messages.clear()
        self.cleanup_attachments()
        self.messages_updated.emit()

    def add_user_message(self, content: Any) -> ChatMessage:
        msg = ChatMessage(role="user", content=content)
        self.messages.append(msg)
        self.messages_updated.emit()
        return msg

    def add_assistant_message(self, content: Any) -> ChatMessage:
        msg = ChatMessage(role="assistant", content=content)
        self.messages.append(msg)
        self.messages_updated.emit()
        return msg

    def add_attachment_paths(
        self,
        paths: list[Path],
        attachment_bar: AttachmentBar,
        parent: QWidget | None = None,
    ) -> None:
        for path in paths:
            temp_name = f"turna_wish_{uuid.uuid4().hex[:8]}_{path.name}"
            temp_path = Path(tempfile.gettempdir()) / temp_name
            try:
                shutil.copy(str(path), str(temp_path))
            except OSError as exc:
                if parent:
                    QMessageBox.warning(parent, "添加失败", f"无法复制文件 {path.name}: {exc}")
                continue
            result = extract_attachment(temp_path)
            if not result.ok:
                if parent:
                    QMessageBox.warning(parent, "提取失败", f"{path.name}: {result.error}")
                try:
                    temp_path.unlink(missing_ok=True)
                except OSError:
                    logger.debug("dialogs/ai/generator_chat_coordinator.py:unlink best-effort failed", exc_info=True)
                continue
            record = AttachmentRecord(
                temp_path=temp_path,
                original_name=path.name,
                content=result.content or {},
            )
            attachment_bar.add_attachment(record)
        self.sync_attachments(attachment_bar)

    def sync_attachments(self, attachment_bar: AttachmentBar) -> None:
        self.attachments = list(attachment_bar.attachments())

    def cleanup_attachments(self, attachment_bar: AttachmentBar | None = None) -> None:
        records = list(self.attachments)
        for att in records:
            temp_path = getattr(att, "temp_path", None)
            if temp_path is not None:
                try:
                    Path(temp_path).unlink(missing_ok=True)
                except OSError:
                    logger.debug("dialogs/ai/generator_chat_coordinator.py:cleanup best-effort failed", exc_info=True)
        self.attachments.clear()
        if attachment_bar is not None:
            attachment_bar.clear_attachments()

    # --- Chat expand window ---------------------------------------------

    def open_chat_expand(
        self,
        parent: QWidget,
        chat_palette: dict[str, str],
        send_callback: Any,
        closed_callback: Any,
    ) -> ChatExpandWindow:
        if self.chat_expand_window is None:
            win = ChatExpandWindow(chat_palette, parent)
            win.send_requested.connect(send_callback)
            win.finished.connect(closed_callback)
            self._load_chat_expand_geometry(win)
            self.chat_expand_window = win
        win = self.chat_expand_window
        win.render(self.messages)
        win.show()
        win.raise_()
        win.activateWindow()
        return win

    def close_chat_expand(self) -> None:
        win = self.chat_expand_window
        if win is not None:
            self._save_chat_expand_geometry(win)
            win.close()

    def on_chat_expand_closed(self, expand_btn: QPushButton) -> None:
        if self.chat_expand_window is not None:
            self._save_chat_expand_geometry(self.chat_expand_window)
        expand_btn.blockSignals(True)
        expand_btn.setChecked(False)
        expand_btn.setText("↕ 放大聊天")
        expand_btn.blockSignals(False)

    def sync_expand_chat(self) -> None:
        win = self.chat_expand_window
        if win is not None and win.isVisible():
            win.render(self.messages)

    def render_streaming_expand_chat(self, partial_text: str) -> None:
        win = self.chat_expand_window
        if win is not None and win.isVisible():
            win.render_streaming(self.messages, partial_text)

    def _load_chat_expand_geometry(self, win: ChatExpandWindow) -> None:
        qs = QSettings("Turna", "CourseEditor")
        geo = qs.value("ai_chat_expand/geometry")
        if geo is not None:
            win.restoreGeometry(geo)
        if qs.value("ai_chat_expand/maximized", False) in (True, "true", "1"):
            win.showMaximized()

    def _save_chat_expand_geometry(self, win: ChatExpandWindow) -> None:
        qs = QSettings("Turna", "CourseEditor")
        qs.setValue("ai_chat_expand/geometry", win.saveGeometry())
        qs.setValue("ai_chat_expand/maximized", win.isMaximized())

    @staticmethod
    def handle_input_key_press(
        event: Any,
        input_edit: QTextEdit,
        send_callback: Any,
        enter_to_send: bool,
    ) -> bool:
        key = event.key()
        mods = event.modifiers()
        if key in (Qt.Key.Key_Return, Qt.Key.Key_Enter):
            if mods == Qt.KeyboardModifier.ControlModifier:
                send_callback()
                return True
            if mods == Qt.KeyboardModifier.NoModifier and enter_to_send:
                send_callback()
                return True
        QTextEdit.keyPressEvent(input_edit, event)
        return False
