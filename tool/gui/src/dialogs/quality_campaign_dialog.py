"""Quality campaign dialog — worst-N queue (E2.0 / K-16).

Lists weak sections / empty lessons for the author to locate or open AI edit.
Does not generate content itself — only navigates / signals intent.
"""
from __future__ import annotations

from typing import Any

from PySide6.QtCore import Qt
from PySide6.QtWidgets import (
    QDialog,
    QDialogButtonBox,
    QHBoxLayout,
    QLabel,
    QListWidget,
    QListWidgetItem,
    QPushButton,
    QVBoxLayout,
)

# Ranking logic lives Qt-free in the backend; re-exported for compat.
from src.backend.quality_campaign import build_campaign_items  # noqa: F401


class QualityCampaignDialog(QDialog):
    """Modal queue: select a target then Locate or AI-edit."""

    def __init__(
        self,
        items: list[dict[str, Any]],
        parent=None,
        *,
        title: str = "低质 / 空课战役",
    ) -> None:
        super().__init__(parent)
        self.setWindowTitle(title)
        self.resize(480, 360)
        self._items = list(items)
        self._chosen: dict[str, Any] | None = None
        self._action: str = ""  # locate | ai_edit

        layout = QVBoxLayout(self)
        layout.addWidget(
            QLabel("选择一项：定位到树，或打开 AI 编辑/填充（需预览确认，不会静默写盘）。")
        )
        self.list = QListWidget()
        for it in self._items:
            text = str(it.get("title") or it.get("id") or "?")
            row = QListWidgetItem(text)
            row.setData(Qt.ItemDataRole.UserRole, it)
            self.list.addItem(row)
        if self._items:
            self.list.setCurrentRow(0)
        layout.addWidget(self.list, stretch=1)

        row = QHBoxLayout()
        self.locate_btn = QPushButton("定位")
        self.locate_btn.clicked.connect(self._on_locate_clicked)
        self.ai_btn = QPushButton("AI 处理")
        self.ai_btn.setToolTip("空课→填充路径；节→AI 编辑该节（现有对话框）")
        self.ai_btn.clicked.connect(self._on_ai_edit_clicked)
        row.addWidget(self.locate_btn)
        row.addWidget(self.ai_btn)
        row.addStretch()
        layout.addLayout(row)

        buttons = QDialogButtonBox(QDialogButtonBox.StandardButton.Close)
        buttons.rejected.connect(self.reject)
        buttons.button(QDialogButtonBox.StandardButton.Close).setText("关闭")
        layout.addWidget(buttons)

    def chosen(self) -> dict[str, Any] | None:
        return self._chosen

    def action(self) -> str:
        return self._action

    def _on_locate_clicked(self) -> None:
        self._finish("locate")

    def _on_ai_edit_clicked(self) -> None:
        self._finish("ai_edit")

    def _finish(self, action: str) -> None:
        item = self.list.currentItem()
        if item is None:
            return
        data = item.data(Qt.ItemDataRole.UserRole)
        if not isinstance(data, dict):
            return
        self._chosen = dict(data)
        self._action = action
        self.accept()
