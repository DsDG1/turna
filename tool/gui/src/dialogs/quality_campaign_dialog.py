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


def build_campaign_items(
    *,
    quality_by_section: dict[str, float] | None = None,
    empty_lessons: list[str] | None = None,
    sections: list[dict[str, Any]] | None = None,
    worst_n: int = 3,
    quality_threshold: float = 0.7,
) -> list[dict[str, Any]]:
    """Pure helper: rank campaign targets (no Qt).

    Each item: {kind, id, title, score?, reason}
    """
    items: list[dict[str, Any]] = []
    empty_set = set(empty_lessons or [])

    # Empty lessons first (actionable fill).
    for lid in list(empty_lessons or [])[: max(worst_n * 2, 1)]:
        items.append(
            {
                "kind": "lesson",
                "id": lid,
                "title": f"空课 {lid}",
                "reason": "empty",
                "score": 0.0,
            }
        )

    weak = [
        (sid, float(mean))
        for sid, mean in (quality_by_section or {}).items()
        if mean is not None and float(mean) < quality_threshold
    ]
    weak.sort(key=lambda x: x[1])
    for sid, mean in weak[:worst_n]:
        name = sid
        for sec in sections or []:
            if isinstance(sec, dict) and sec.get("id") == sid:
                name = str(sec.get("name") or sid)
                break
        items.append(
            {
                "kind": "section",
                "id": sid,
                "title": f"低质节 {name}（{mean:.2f}）",
                "reason": "low_quality",
                "score": mean,
            }
        )

    # Dedupe by kind+id, keep order, cap.
    seen: set[tuple[str, str]] = set()
    out: list[dict[str, Any]] = []
    for it in items:
        key = (it["kind"], it["id"])
        if key in seen:
            continue
        seen.add(key)
        out.append(it)
        if len(out) >= worst_n + len(empty_set):
            # Prefer worst_n + empties but hard-cap 12.
            if len(out) >= 12:
                break
    return out[:12]


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
        self.locate_btn.clicked.connect(lambda: self._finish("locate"))
        self.ai_btn = QPushButton("AI 处理")
        self.ai_btn.setToolTip("空课→填充路径；节→AI 编辑该节（现有对话框）")
        self.ai_btn.clicked.connect(lambda: self._finish("ai_edit"))
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
