"""Bulk-import preview table for the textbook import flow (bookplan2 Phase 4).

Read-only ``QTableWidget`` that renders one row per chapter's
``SectionImportPreview`` so the teacher can see, before confirming, which
section id each chapter will land on, whether it collides with the loaded
course, the resolved action (append / merge / skip / replace / append_new),
and how many of its resources are new vs. duplicates of existing course or
intra-project entries.

The panel is display-only; strategy selection and the confirm button live in
``TextbookImportDialog``'s import page, which calls ``set_previews`` after
recomputing the plan via ``TextbookImportController.preview_import``.
"""
from __future__ import annotations

from PySide6.QtCore import Qt
from PySide6.QtWidgets import QLabel, QTableWidget, QTableWidgetItem, QVBoxLayout, QWidget

from src.backend.import_strategy import SectionImportPreview
from src.theme import current_palette

_ACTION_LABELS = {
    "append": "新增",
    "merge": "合并（交互）",
    "skip": "跳过",
    "replace": "覆盖",
    "append_new": "追加为新",
}

_HEADERS = ("章节", "目标 section id", "动作", "新增（词/表/语）", "重复（词/表/语）", "冲突")


def action_label(action: str) -> str:
    return _ACTION_LABELS.get(action, action)


def _id_cell(p: SectionImportPreview) -> str:
    if p.action == "append_new" and p.target_id != p.source_id:
        return f"{p.source_id} -> {p.target_id}"
    return p.target_id or p.source_id


class BulkImportPreviewPanel(QWidget):
    """Renders a list of ``SectionImportPreview`` as a read-only table + summary."""

    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self._previews: list[SectionImportPreview] = []
        root = QVBoxLayout(self)
        root.setContentsMargins(0, 0, 0, 0)
        self._summary = QLabel("")
        self._summary.setWordWrap(True)
        self._summary.setStyleSheet(f"color: {current_palette()['ai_accent']}; font-size: 12px;")
        root.addWidget(self._summary)

        self._table = QTableWidget(0, len(_HEADERS))
        self._table.setHorizontalHeaderLabels(list(_HEADERS))
        self._table.verticalHeader().setVisible(False)
        self._table.setEditTriggers(QTableWidget.EditTrigger.NoEditTriggers)
        self._table.setSelectionBehavior(QTableWidget.SelectionBehavior.SelectRows)
        self._table.horizontalHeader().setStretchLastSection(False)
        root.addWidget(self._table, 1)

    @property
    def previews(self) -> list[SectionImportPreview]:
        return list(self._previews)

    def clear(self) -> None:
        self._previews = []
        self._table.setRowCount(0)
        self._summary.setText("")

    def set_previews(self, previews: list[SectionImportPreview]) -> None:
        self._previews = list(previews)
        self._table.setRowCount(len(previews))
        for row, p in enumerate(previews):
            self._table.setItem(row, 0, QTableWidgetItem(p.title))
            self._table.setItem(row, 1, QTableWidgetItem(_id_cell(p)))
            self._table.setItem(row, 2, QTableWidgetItem(action_label(p.action)))
            self._table.setItem(
                row,
                3,
                QTableWidgetItem(f"{p.new_words} / {p.new_expressions} / {p.new_grammar}"),
            )
            self._table.setItem(
                row,
                4,
                QTableWidgetItem(
                    f"{p.duplicate_words} / {p.duplicate_expressions} / {p.duplicate_grammar}"
                ),
            )
            self._table.setItem(row, 5, QTableWidgetItem("是" if p.exists else "-"))
            self._style_conflict_row(row, p)
        self._table.resizeColumnsToContents()
        self._summary.setText(self._summary_text(previews))

    def _style_conflict_row(self, row: int, p: SectionImportPreview) -> None:
        """Tint rows that need the teacher's attention: collisions and skips."""
        colour = ""
        if p.action == "skip":
            colour = "#9CA3AF"  # greyed out - will not be imported
        elif p.exists:
            colour = "#FF9F43"  # warning - collides with existing section
        if not colour:
            return
        for col in range(len(_HEADERS)):
            item = self._table.item(row, col)
            if item is not None:
                item.setForeground(Qt.GlobalColor.gray if p.action == "skip" else item.foreground())
                # Use a tooltip rather than background to keep theme-safe.
                if p.exists:
                    item.setToolTip("该 section id 已存在于当前课程。")

    @staticmethod
    def _summary_text(previews: list[SectionImportPreview]) -> str:
        if not previews:
            return "无可导入的章节。"
        counts: dict[str, int] = {}
        for p in previews:
            counts[p.action] = counts.get(p.action, 0) + 1
        parts = [f"{action_label(a)}：{n}" for a, n in counts.items() if n]
        dup_total = sum(
            p.duplicate_words + p.duplicate_expressions + p.duplicate_grammar
            for p in previews
        )
        new_total = sum(
            p.new_words + p.new_expressions + p.new_grammar for p in previews
        )
        return (
            f"共 {len(previews)} 个章节 | {' | '.join(parts)} | "
            f"新增资源 {new_total} 项，重复资源 {dup_total} 项"
        )
