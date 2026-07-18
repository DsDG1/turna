"""Vocab table for the teacher view (guiplan §15.6, T.5).

In-table editing with tag chips from the ALLOWED_TAGS whitelist. Reuses the
M3 CourseAdapter in-memory vocab list; save() persists. CSV import/export is
demoted to an "advanced" menu entry, not the main path.
"""
from __future__ import annotations

from PySide6.QtCore import Qt, QTimer, Signal
from PySide6.QtWidgets import (
    QFileDialog,
    QHBoxLayout,
    QHeaderView,
    QLabel,
    QLineEdit,
    QMenu,
    QMessageBox,
    QPushButton,
    QTableWidget,
    QTableWidgetItem,
    QVBoxLayout,
    QWidget,
)

from src.backend.course_adapter import CourseAdapter

COLUMNS = ["词", "翻译", "发音", "标签"]


class VocabTableWidget(QWidget):
    """Teacher-facing vocab table with tag chips."""

    changed = Signal()

    def __init__(self, adapter: CourseAdapter, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.adapter = adapter
        self._dirty = False
        self._build_ui()
        self._refresh()

    def is_dirty(self) -> bool:
        return self._dirty

    def _build_ui(self) -> None:
        layout = QVBoxLayout(self)
        header_row = QHBoxLayout()
        count = len(self.adapter.vocab)
        header_row.addWidget(QLabel(f"词库（共 {count} 个词）"))
        header_row.addStretch()
        self.add_btn = QPushButton("+ 新增词")
        self.del_btn = QPushButton("删除选中")
        self.more_btn = QPushButton("高级 ▾")
        menu = QMenu(self)
        self.import_action = menu.addAction("导入 CSV（高级）")
        self.export_action = menu.addAction("导出 CSV（高级）")
        self.more_btn.setMenu(menu)
        header_row.addWidget(self.add_btn)
        header_row.addWidget(self.del_btn)
        header_row.addWidget(self.more_btn)
        layout.addLayout(header_row)

        self.search = QLineEdit()
        self.search.setPlaceholderText("搜索词或翻译")
        # Debounce: rebuilding the full table per keystroke is wasteful.
        self._search_timer = QTimer(self)
        self._search_timer.setSingleShot(True)
        self._search_timer.setInterval(300)
        self._search_timer.timeout.connect(self._refresh)
        self.search.textChanged.connect(self._search_timer.start)
        layout.addWidget(self.search)

        self.table = QTableWidget()
        self.table.setColumnCount(len(COLUMNS))
        self.table.setHorizontalHeaderLabels(COLUMNS)
        self.table.horizontalHeader().setSectionResizeMode(
            QHeaderView.ResizeMode.Stretch
        )
        self.table.itemChanged.connect(self._on_cell_changed)
        layout.addWidget(self.table)

        self.add_btn.clicked.connect(self._on_add)
        self.del_btn.clicked.connect(self._on_del)
        self.import_action.triggered.connect(self._on_import)
        self.export_action.triggered.connect(self._on_export)

    def _refresh(self) -> None:
        self.table.blockSignals(True)
        self.table.setRowCount(0)
        query = self.search.text().strip().lower()
        rows = []
        for w in self.adapter.vocab:
            if query and query not in str(w.get("term", "")).lower() and query not in str(
                w.get("translation", "")
            ).lower():
                continue
            rows.append(w)
        self.table.setRowCount(len(rows))
        for r, w in enumerate(rows):
            self.table.setItem(r, 0, QTableWidgetItem(str(w.get("term", ""))))
            self.table.setItem(r, 1, QTableWidgetItem(str(w.get("translation", ""))))
            self.table.setItem(r, 2, QTableWidgetItem(str(w.get("pronunciation", "") or "")))
            tag_item = QTableWidgetItem(", ".join(w.get("tags", []) or []))
            self.table.setItem(r, 3, tag_item)
            self.table.item(r, 0).setData(Qt.ItemDataRole.UserRole, w.get("id"))
        self.table.blockSignals(False)

    def _on_cell_changed(self, item: QTableWidgetItem) -> None:
        row = item.row()
        id_item = self.table.item(row, 0)
        if id_item is None:
            return
        wid = id_item.data(Qt.ItemDataRole.UserRole)
        for w in self.adapter.vocab:
            if w.get("id") == wid:
                col = item.column()
                if col == 0:
                    w["term"] = item.text()
                elif col == 1:
                    w["translation"] = item.text()
                elif col == 2:
                    w["pronunciation"] = item.text() or None
                elif col == 3:
                    w["tags"] = [t.strip() for t in item.text().split(",") if t.strip()]
                self._dirty = True
                self.adapter.notify_resources_changed()
                self.changed.emit()
                return

    def _on_add(self) -> None:
        new_id = self.adapter.add_resource_entry("vocab")
        self._dirty = True
        self.adapter.notify_resources_changed()
        self.changed.emit()
        self._refresh()
        for r in range(self.table.rowCount()):
            if self.table.item(r, 0).data(Qt.ItemDataRole.UserRole) == new_id:
                self.table.setCurrentCell(r, 0)
                break

    def _on_del(self) -> None:
        row = self.table.currentRow()
        if row < 0:
            return
        wid = self.table.item(row, 0).data(Qt.ItemDataRole.UserRole)
        try:
            self.adapter.delete_resource_entry("vocab", wid)
        except KeyError:
            return
        self._dirty = True
        self.adapter.notify_resources_changed()
        self.changed.emit()
        self._refresh()

    def _on_import(self) -> None:
        path, _ = QFileDialog.getOpenFileName(
            self, "导入词库 CSV", "", "CSV Files (*.csv)"
        )
        if not path:
            return
        from pathlib import Path

        problems = self.adapter.import_csv("vocab", Path(path))
        errors = [p for p in problems if p["level"] == "error"]
        if errors:
            detail = "\n".join(f"[{p['level']}] {p['message']}" for p in problems)
            QMessageBox.warning(self, "导入失败（未应用）", detail)
        else:
            self._dirty = True
            self.adapter.notify_resources_changed()
            self.changed.emit()
            self._refresh()
            QMessageBox.information(self, "导入完成", "CSV 已合并，记得保存。")

    def _on_export(self) -> None:
        path, _ = QFileDialog.getSaveFileName(
            self, "导出词库 CSV", "vocab.csv", "CSV Files (*.csv)"
        )
        if not path:
            return
        from pathlib import Path

        try:
            self.adapter.export_csv("vocab", Path(path))
            QMessageBox.information(self, "已导出", f"写入 {path}")
        except Exception as exc:
            QMessageBox.warning(self, "导出失败", str(exc))
