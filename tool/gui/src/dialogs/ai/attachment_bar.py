"""Attachment chip bar + preview popup for wish-mode file attachments.

Replaces the inline attachment rendering previously embedded in
``AiGeneratorDialog``. Each chip shows the original file name plus a short
extraction preview; clicking opens a preview dialog, Delete removes the selected
chip.
"""
from __future__ import annotations

import base64

from PySide6.QtCore import Qt, Signal
from PySide6.QtGui import QKeyEvent, QPixmap
from PySide6.QtWidgets import (
    QDialog,
    QDialogButtonBox,
    QHBoxLayout,
    QLabel,
    QPlainTextEdit,
    QPushButton,
    QRadioButton,
    QScrollArea,
    QVBoxLayout,
    QWidget,
)

from src.dialogs.ai.worker import AttachmentRecord


class AttachmentPreviewDialog(QDialog):
    """Preview a single attachment's extracted content and reference mode."""

    def __init__(self, record: AttachmentRecord, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.setWindowTitle(f"附件预览 - {record.original_name}")
        self.resize(640, 520)
        self._record = record
        self._reference_mode = "inline"  # or "standalone"
        self._build_ui()

    def _build_ui(self) -> None:
        layout = QVBoxLayout(self)
        layout.setSpacing(12)
        layout.setContentsMargins(16, 16, 16, 16)

        info = QLabel(f"<b>{self._record.original_name}</b>")
        layout.addWidget(info)

        content_type = self._record.content.get("type", "")
        if content_type == "image_url":
            scroll = QScrollArea()
            image_label = QLabel()
            image_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
            pixmap = self._pixmap_from_record()
            if pixmap and not pixmap.isNull():
                image_label.setPixmap(pixmap)
            else:
                image_label.setText("无法加载图片预览")
            scroll.setWidget(image_label)
            scroll.setWidgetResizable(True)
            layout.addWidget(scroll, 1)
        else:
            text_edit = QPlainTextEdit()
            text_edit.setReadOnly(True)
            text = self._text_from_record()
            text_edit.setPlainText(text[:100_000])
            layout.addWidget(text_edit, 1)

        mode_box = QHBoxLayout()
        mode_box.setSpacing(12)
        mode_box.addWidget(QLabel("引用方式:"))
        self.inline_radio = QRadioButton("作为当前消息附件")
        self.inline_radio.setChecked(True)
        self.inline_radio.toggled.connect(self._on_mode_changed)
        self.standalone_radio = QRadioButton("作为独立 user 消息")
        mode_box.addWidget(self.inline_radio)
        mode_box.addWidget(self.standalone_radio)
        mode_box.addStretch()
        layout.addLayout(mode_box)

        buttons = QDialogButtonBox(QDialogButtonBox.StandardButton.Close)
        buttons.rejected.connect(self.reject)
        layout.addWidget(buttons)

    def _on_mode_changed(self, checked: bool) -> None:
        self._reference_mode = "inline" if checked else "standalone"

    def _text_from_record(self) -> str:
        content = self._record.content
        if content.get("type") == "text":
            return str(content.get("text", ""))
        return "[非文本附件]"

    def _pixmap_from_record(self) -> QPixmap | None:
        content = self._record.content
        image_url = content.get("image_url", {}).get("url", "")
        if not image_url.startswith("data:"):
            return None
        try:
            header, encoded = image_url.split(",", 1)
            data = base64.b64decode(encoded)
            pixmap = QPixmap()
            pixmap.loadFromData(data)
            if not pixmap.isNull() and (pixmap.width() > 800 or pixmap.height() > 600):
                pixmap = pixmap.scaled(
                    800, 600, Qt.AspectRatioMode.KeepAspectRatio
                )
            return pixmap
        except Exception:
            return None


class AttachmentBar(QWidget):
    """Horizontal chip list of attachments with preview and deletion."""

    attachments_changed = Signal()

    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self._attachments: list[AttachmentRecord] = []
        layout = QHBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(8)
        layout.addWidget(QLabel("附件:"))
        self._chips_layout = QHBoxLayout()
        self._chips_layout.setSpacing(6)
        self._chips_layout.setContentsMargins(0, 0, 0, 0)
        layout.addLayout(self._chips_layout)
        layout.addStretch()
        self._placeholder = QLabel("无附件")
        self._placeholder.setObjectName("hintLabel")
        self._chips_layout.addWidget(self._placeholder)
        self.setFocusPolicy(Qt.FocusPolicy.StrongFocus)

    def attachments(self) -> list[AttachmentRecord]:
        return list(self._attachments)

    def add_attachment(self, record: AttachmentRecord) -> None:
        self._attachments.append(record)
        self._rebuild_chips()
        self.attachments_changed.emit()

    def remove_attachment(self, record: AttachmentRecord) -> None:
        if record in self._attachments:
            self._attachments.remove(record)
            self._rebuild_chips()
            self.attachments_changed.emit()

    def clear_attachments(self) -> None:
        self._attachments.clear()
        self._rebuild_chips()
        self.attachments_changed.emit()

    def _rebuild_chips(self) -> None:
        # Remove existing widgets from the chips layout.
        while self._chips_layout.count():
            item = self._chips_layout.takeAt(0)
            widget = item.widget()
            if widget is not None:
                widget.deleteLater()

        if not self._attachments:
            self._chips_layout.addWidget(QLabel("无附件"))
            self._chips_layout.addStretch()
            return

        for idx, record in enumerate(self._attachments):
            btn = QPushButton(self._chip_label(record))
            btn.setToolTip(f"{record.original_name}\n点击预览，按 Delete 移除")
            btn.setCursor(Qt.CursorShape.PointingHandCursor)
            btn.setFlat(True)
            btn.setProperty("attachment_index", idx)
            btn.clicked.connect(lambda _c=False, r=record: self._preview_attachment(r))
            self._chips_layout.addWidget(btn)

        self._chips_layout.addStretch()

    @staticmethod
    def _chip_label(record: AttachmentRecord) -> str:
        preview = _preview_text(record)
        text = f"{record.original_name}: {preview[:20]}"
        if len(preview) > 20:
            text += "..."
        return text

    def _preview_attachment(self, record: AttachmentRecord) -> None:
        dlg = AttachmentPreviewDialog(record, parent=self)
        dlg.exec()

    def keyPressEvent(self, event: QKeyEvent) -> None:  # noqa: N802
        if event.key() == Qt.Key.Key_Delete:
            self._remove_selected_attachment()
        else:
            super().keyPressEvent(event)

    def _remove_selected_attachment(self) -> None:
        focus = self.focusWidget()
        if focus is None:
            return
        idx = focus.property("attachment_index")
        if idx is None or not isinstance(idx, int):
            return
        if 0 <= idx < len(self._attachments):
            record = self._attachments[idx]
            self.remove_attachment(record)


def _preview_text(record: AttachmentRecord) -> str:
    content = record.content
    if content.get("type") == "image_url":
        return "[图片]"
    text = str(content.get("text", ""))
    preview = text.replace("\n", " ")[:120]
    return preview or "[空内容]"


def summarize_attachment(record: AttachmentRecord) -> str:
    """Human-readable one-line summary of an attachment."""
    return _preview_text(record)
