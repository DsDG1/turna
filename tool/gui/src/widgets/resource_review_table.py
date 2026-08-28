"""Reusable review table for textbook-import knowledge resources.

Replaces the ad-hoc ``QTableWidget`` used in the textbook import dialog with a
 dedicated ``QTableWidget`` subclass wired for batch operations, search/filter,
 and AI-fix requests. The underlying data is kept in a plain-Python
 ``ResourceTableModel`` so tests can inspect it without a QApplication.

Performance contract: the table always holds one row per model entry, and
filter-only changes (search / tag / chapter) just hide rows via
``setRowHidden`` instead of rebuilding items. Structural changes (set_rows,
check toggles, deletes) are the only full rebuilds.
"""
from __future__ import annotations

import json
from dataclasses import dataclass, field
from typing import Any

from PySide6.QtCore import Qt, Signal, QMimeData, QPoint
from PySide6.QtGui import QDrag, QPixmap, QPainter, QColor, QBrush
from PySide6.QtWidgets import (
    QAbstractItemView,
    QApplication,
    QComboBox,
    QHBoxLayout,
    QLineEdit,
    QPushButton,
    QTableWidget,
    QTableWidgetItem,
    QVBoxLayout,
    QWidget,
)

from src.backend.extraction_quality import QualityIssue
from src.theme_tokens import resource_type_color



@dataclass
class ResourceRow:
    """One row in the review table."""

    chapter_index: int
    resource_type: str  # "word" | "expression" | "grammarPoint"
    entry: dict[str, Any]
    issues: list[QualityIssue] = field(default_factory=list)
    checked: bool = True

    def display_term(self) -> str:
        return str(self.entry.get("term") or self.entry.get("title") or "")

    def display_translation(self) -> str:
        return str(
            self.entry.get("translation") or self.entry.get("explanation") or ""
        )

    def display_tags(self) -> str:
        tags = self.entry.get("tags")
        if isinstance(tags, list):
            return ", ".join(str(t) for t in tags)
        return str(tags or "")

    def set_display_term(self, value: str) -> None:
        if self.resource_type == "grammarPoint":
            self.entry["title"] = value
        else:
            self.entry["term"] = value

    def set_display_translation(self, value: str) -> None:
        if self.resource_type == "grammarPoint":
            self.entry["explanation"] = value
        else:
            self.entry["translation"] = value

    def set_display_tags(self, value: str) -> None:
        self.entry["tags"] = [t.strip() for t in value.split(",") if t.strip()]


class ResourceTableModel:
    """In-memory model backing the review table.

    Plain Python container; the Qt widget repopulates itself from this model.
    """

    COLUMNS = (
        "保留",
        "章节",
        "类型",
        "term / title",
        "translation / explanation",
        "tags",
        "质量",
    )

    def __init__(self, rows: list[ResourceRow] | None = None) -> None:
        self.rows: list[ResourceRow] = list(rows or [])

    def clear(self) -> None:
        self.rows = []

    def set_rows(self, rows: list[ResourceRow]) -> None:
        self.rows = list(rows)

    def remove_rows(self, indices: set[int]) -> None:
        self.rows = [r for i, r in enumerate(self.rows) if i not in indices]

    def row_count(self) -> int:
        return len(self.rows)

    def all_tags(self) -> list[str]:
        tags: set[str] = set()
        for r in self.rows:
            for t in r.entry.get("tags") or []:
                if t:
                    tags.add(str(t))
        return sorted(tags)


class DraggableTableWidget(QTableWidget):
    """Subclass of QTableWidget that supports dragging rows as knowledge points."""

    def __init__(self, review_table: ResourceReviewTable, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.review_table = review_table
        self._drag_start_pos = None

    def mousePressEvent(self, event) -> None:  # noqa: N802
        if event.button() == Qt.MouseButton.LeftButton:
            self._drag_start_pos = event.pos()
        super().mousePressEvent(event)

    def mouseMoveEvent(self, event) -> None:  # noqa: N802
        if not (event.buttons() & Qt.MouseButton.LeftButton):
            return
        if self._drag_start_pos is None:
            return
        if (event.pos() - self._drag_start_pos).manhattanLength() < QApplication.startDragDistance():
            return

        row = self.rowAt(event.pos().y())
        if row < 0:
            return

        # Table rows map 1:1 onto model rows; filtered-out rows are hidden,
        # not removed, so index the full model directly.
        rows = self.review_table._model.rows
        if 0 <= row < len(rows):
            row_obj = rows[row]
            payload = {
                "entry": row_obj.entry,
                "resource_type": row_obj.resource_type,
            }
            
            mime = QMimeData()
            mime.setData("application/x-knowledge-point", json.dumps(payload, ensure_ascii=False).encode("utf-8"))
            
            drag = QDrag(self)
            drag.setMimeData(mime)
            
            # Create a visual capsule pill representation for drag icon
            term = row_obj.display_term()
            pixmap = QPixmap(130, 26)
            pixmap.fill(Qt.GlobalColor.transparent)
            
            painter = QPainter(pixmap)
            painter.setRenderHint(QPainter.RenderHint.Antialiasing)
            
            # Pill bg color based on resource type (Turna-harmonized)
            bg = resource_type_color(row_obj.resource_type)
            
            painter.setBrush(QBrush(QColor(bg)))
            painter.setPen(Qt.PenStyle.NoPen)
            painter.drawRoundedRect(pixmap.rect(), 13, 13)
            
            # Text
            painter.setPen(Qt.GlobalColor.white)
            font = painter.font()
            font.setBold(True)
            font.setPointSize(10)
            painter.setFont(font)
            painter.drawText(pixmap.rect(), Qt.AlignmentFlag.AlignCenter, term)
            painter.end()
            
            drag.setPixmap(pixmap)
            drag.setHotSpot(QPoint(65, 13))
            
            drag.exec(Qt.DropAction.CopyAction)
            self._drag_start_pos = None


class ResourceReviewTable(QWidget):
    """Review table with search, tag filter, batch ops, and AI-fix requests."""

    rows_changed = Signal()
    fix_requested = Signal(list)  # list[ResourceRow]

    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self._model = ResourceTableModel()
        self._chapter_filter: int | None = None
        self._tag_filter: str = ""
        self._search_text: str = ""
        self._build_ui()

    def _build_ui(self) -> None:
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(8)

        toolbar = QHBoxLayout()
        toolbar.setSpacing(6)

        self._search_edit = QLineEdit()
        self._search_edit.setPlaceholderText("搜索 term / translation / tags")
        self._search_edit.textChanged.connect(self._on_search_changed)
        toolbar.addWidget(self._search_edit, 2)

        self._tag_combo = QComboBox()
        self._tag_combo.addItem("全部 tags")
        self._tag_combo.currentTextChanged.connect(self._on_tag_changed)
        toolbar.addWidget(self._tag_combo, 1)

        self._select_all_btn = QPushButton("全选")
        self._select_all_btn.clicked.connect(self._select_all)
        toolbar.addWidget(self._select_all_btn)

        self._select_none_btn = QPushButton("反选")
        self._select_none_btn.clicked.connect(self._invert_selection)
        toolbar.addWidget(self._select_none_btn)

        self._delete_btn = QPushButton("删除选中")
        self._delete_btn.clicked.connect(self._delete_selected)
        toolbar.addWidget(self._delete_btn)

        self._fix_btn = QPushButton("AI 修复选中")
        self._fix_btn.setToolTip("对选中的问题行调用 AI 自动修正")
        self._fix_btn.clicked.connect(self._on_fix_clicked)
        toolbar.addWidget(self._fix_btn)

        layout.addLayout(toolbar)

        self._table = DraggableTableWidget(self)
        self._table.setSelectionBehavior(QAbstractItemView.SelectionBehavior.SelectRows)
        self._table.itemChanged.connect(self._on_item_changed)
        layout.addWidget(self._table, 1)

    # ------------------------------------------------------------------ public

    def set_rows(self, rows: list[ResourceRow]) -> None:
        self._model.set_rows(rows)
        self._refresh_tag_combo()
        self._refresh_table()
        # Column sizing is O(cols x rows); do it once on a structural change,
        # not on every filter/search refresh (bookplan2 Phase 6 perf).
        self._table.resizeColumnsToContents()

    def kept_rows(self) -> list[tuple[int, str, dict[str, Any]]]:
        """Return ``(chapter_index, resource_type, entry)`` for all checked rows."""
        self._apply_edits_from_table()
        return [
            (row.chapter_index, row.resource_type, row.entry)
            for row in self._model.rows
            if row.checked
        ]

    def row_count(self) -> int:
        return len(self._visible_rows())

    def set_chapter_filter(self, chapter_index: int | None) -> None:
        self._chapter_filter = chapter_index
        self._apply_row_visibility()

    def selected_rows(self) -> list[ResourceRow]:
        """Return the underlying ResourceRow objects for selected rows."""
        rows = self._model.rows
        selected: list[ResourceRow] = []
        for idx in self._table.selectionModel().selectedRows():
            source_row = idx.row()
            if 0 <= source_row < len(rows):
                selected.append(rows[source_row])
        return selected

    def set_checked(self, visible_row: int, checked: bool) -> None:
        visible = self._visible_rows()
        if 0 <= visible_row < len(visible):
            visible[visible_row].checked = checked
            self._refresh_table()
            self.rows_changed.emit()

    def set_checked_by_term(self, term: str, checked: bool) -> None:
        """Convenience helper for tests."""
        for row in self._model.rows:
            if row.display_term() == term:
                row.checked = checked
        self._refresh_table()
        self.rows_changed.emit()

    def set_all_checked(self, checked: bool) -> None:
        """Batch-check all model rows and emit ``rows_changed`` once (P2)."""
        for row in self._model.rows:
            row.checked = checked
        self._refresh_table()
        self.rows_changed.emit()

    # ------------------------------------------------------------------ events

    def _on_search_changed(self, text: str) -> None:
        self._search_text = text.strip().lower()
        self._apply_row_visibility()

    def _on_tag_changed(self, text: str) -> None:
        self._tag_filter = "" if text in ("", "全部 tags") else text
        self._apply_row_visibility()

    def _select_all(self) -> None:
        # Model updates only; _refresh_table blocks itemChanged so one emit.
        for r in self._visible_rows():
            r.checked = True
        self._refresh_table()
        self.rows_changed.emit()

    def _invert_selection(self) -> None:
        for r in self._visible_rows():
            r.checked = not r.checked
        self._refresh_table()
        self.rows_changed.emit()

    def _delete_selected(self) -> None:
        # ResourceRow is a dataclass with dict fields, so list.index() would
        # deep-compare entries per lookup (O(n^2) on large tables); key by
        # identity instead.
        index_by_id = {id(r): i for i, r in enumerate(self._model.rows)}
        to_remove = {index_by_id[id(r)] for r in self._visible_rows() if r.checked}
        if not to_remove:
            return
        self._model.remove_rows(to_remove)
        self._refresh_tag_combo()
        self._refresh_table()
        self.rows_changed.emit()

    def _on_fix_clicked(self) -> None:
        selected = self.selected_rows()
        if selected:
            self.fix_requested.emit(selected)
            return
        issue_rows = [r for r in self._visible_rows() if r.checked and r.issues]
        if issue_rows:
            self.fix_requested.emit(issue_rows)

    def _on_item_changed(self, item: QTableWidgetItem) -> None:
        """Sync inline edits and checkbox toggles back to the model."""
        if item is None:
            return
        row = item.data(Qt.ItemDataRole.UserRole)
        if not isinstance(row, ResourceRow):
            return
        col = item.column()
        if col == 0:
            row.checked = item.checkState() == Qt.CheckState.Checked
            self.rows_changed.emit()
        elif col == 3:
            row.set_display_term(item.text())
        elif col == 4:
            row.set_display_translation(item.text())
        elif col == 5:
            row.set_display_tags(item.text())

    # ------------------------------------------------------------------ refresh

    def _row_matches(self, row: ResourceRow) -> bool:
        """Whether a row passes the chapter/tag/search filters."""
        if self._chapter_filter is not None:
            if row.chapter_index != self._chapter_filter:
                return False
        if self._tag_filter:
            if self._tag_filter not in (row.entry.get("tags") or []):
                return False
        if self._search_text:
            if not (
                self._search_text in row.display_term().lower()
                or self._search_text in row.display_translation().lower()
                or self._search_text in row.display_tags().lower()
            ):
                return False
        return True

    def _visible_rows(self) -> list[ResourceRow]:
        return [r for r in self._model.rows if self._row_matches(r)]

    def _apply_row_visibility(self) -> None:
        """Filter-only refresh: hide/show rows, keep all items alive.

        Used by search/tag/chapter changes so typing in the search box never
        rebuilds QTableWidgetItems (O(rows) hide toggles instead of a full
        clear + repopulate).
        """
        if self._table.rowCount() != len(self._model.rows):
            # Table out of sync (should not happen; structural ops rebuild).
            self._refresh_table()
            return
        self._table.setUpdatesEnabled(False)
        try:
            for row_idx, row in enumerate(self._model.rows):
                self._table.setRowHidden(row_idx, not self._row_matches(row))
        finally:
            self._table.setUpdatesEnabled(True)

    def _refresh_tag_combo(self) -> None:
        current = self._tag_combo.currentText()
        self._tag_combo.blockSignals(True)
        self._tag_combo.clear()
        self._tag_combo.addItem("全部 tags")
        tags = self._model.all_tags()
        self._tag_combo.addItems(tags)
        if current in ("", "全部 tags"):
            self._tag_combo.setCurrentIndex(0)
        else:
            index = self._tag_combo.findText(current)
            self._tag_combo.setCurrentIndex(index if index >= 0 else 0)
        self._tag_combo.blockSignals(False)

    def _refresh_table(self) -> None:
        """Rebuild the QTableWidget with one row per model entry.

        Filter state is applied afterwards as row visibility; hidden rows keep
        their items so filter changes never rebuild the table.
        """
        self._table.blockSignals(True)
        self._table.setRowCount(len(self._model.rows))
        self._table.setColumnCount(len(ResourceTableModel.COLUMNS))
        self._table.setHorizontalHeaderLabels(list(ResourceTableModel.COLUMNS))

        for row_idx, row in enumerate(self._model.rows):
            # Keep column
            item_keep = QTableWidgetItem("✓" if row.checked else "")
            item_keep.setFlags(
                Qt.ItemFlag.ItemIsEnabled
                | Qt.ItemFlag.ItemIsSelectable
                | Qt.ItemFlag.ItemIsUserCheckable
            )
            item_keep.setCheckState(
                Qt.CheckState.Checked if row.checked else Qt.CheckState.Unchecked
            )
            item_keep.setData(Qt.ItemDataRole.UserRole, row)
            self._table.setItem(row_idx, 0, item_keep)

            # Chapter column
            self._table.setItem(
                row_idx, 1, QTableWidgetItem(str(row.chapter_index + 1))
            )

            # Type column
            type_label = {
                "word": "词汇",
                "expression": "表达",
                "grammarPoint": "语法",
            }.get(row.resource_type, row.resource_type)
            self._table.setItem(row_idx, 2, QTableWidgetItem(type_label))

            # Term/title
            term_item = QTableWidgetItem(row.display_term())
            term_item.setFlags(
                Qt.ItemFlag.ItemIsEnabled
                | Qt.ItemFlag.ItemIsSelectable
                | Qt.ItemFlag.ItemIsEditable
            )
            term_item.setData(Qt.ItemDataRole.UserRole, row)
            self._table.setItem(row_idx, 3, term_item)

            # Translation/explanation
            trans_item = QTableWidgetItem(row.display_translation())
            trans_item.setFlags(
                Qt.ItemFlag.ItemIsEnabled
                | Qt.ItemFlag.ItemIsSelectable
                | Qt.ItemFlag.ItemIsEditable
            )
            trans_item.setData(Qt.ItemDataRole.UserRole, row)
            self._table.setItem(row_idx, 4, trans_item)

            # Tags
            tags_item = QTableWidgetItem(row.display_tags())
            tags_item.setFlags(
                Qt.ItemFlag.ItemIsEnabled
                | Qt.ItemFlag.ItemIsSelectable
                | Qt.ItemFlag.ItemIsEditable
            )
            tags_item.setData(Qt.ItemDataRole.UserRole, row)
            self._table.setItem(row_idx, 5, tags_item)

            # Quality
            quality_text, quality_color = self._quality_display(row)
            quality_item = QTableWidgetItem(quality_text)
            quality_item.setBackground(quality_color)
            quality_item.setForeground(Qt.GlobalColor.white)
            quality_item.setFlags(
                Qt.ItemFlag.ItemIsEnabled | Qt.ItemFlag.ItemIsSelectable
            )
            quality_item.setToolTip(self._quality_tooltip(row))
            self._table.setItem(row_idx, 6, quality_item)

        # Column sizing is O(cols x rows) and is done once on set_rows /
        # structural changes; we deliberately do NOT resize on every
        # filter/search refresh (bookplan2 Phase 6 perf item).
        self._table.blockSignals(False)
        self._apply_row_visibility()

    def _apply_edits_from_table(self) -> None:
        """Read back any inline edits made to visible cells."""
        for row_idx, row in enumerate(self._model.rows):
            term_item = self._table.item(row_idx, 3)
            if term_item is not None:
                row.set_display_term(term_item.text())
            trans_item = self._table.item(row_idx, 4)
            if trans_item is not None:
                row.set_display_translation(trans_item.text())
            tags_item = self._table.item(row_idx, 5)
            if tags_item is not None:
                row.set_display_tags(tags_item.text())

    def _quality_display(self, row: ResourceRow) -> tuple[str, Qt.GlobalColor]:
        error_count = sum(1 for i in row.issues if i.level == "error")
        warning_count = sum(1 for i in row.issues if i.level == "warning")
        if error_count:
            return f"{error_count} 错误", Qt.GlobalColor.red
        if warning_count:
            return f"{warning_count} 警告", Qt.GlobalColor.darkYellow
        return "OK", Qt.GlobalColor.darkGreen

    def _quality_tooltip(self, row: ResourceRow) -> str:
        if not row.issues:
            return "无质量问题"
        return "\n".join(f"[{i.level}] {i.message}" for i in row.issues[:5])
