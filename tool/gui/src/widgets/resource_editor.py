"""Resource editor dialog: tabbed tables for vocab / expressions / grammar.

Each tab is a QTableWidget bound directly to the adapter's in-memory resource
list. CSV import/export are transport tools; edits land in memory and persist
via CourseAdapter.save() (guiplan §7.2). Reference dropdowns in lesson forms
refresh when this dialog closes (see MainWindow._on_resources).

Vocab rows carry a ``pos`` combo column (closed POS set, Chinese labels,
English enum values). Grammar rows carry a ``practiceItems`` button column
opening an ItemListPanel dialog bound to the entry's practice list — the list
is editor-only (CSV stays column-free; interactions do not fit table cells).
"""
from __future__ import annotations

from PySide6.QtCore import Qt
from PySide6.QtWidgets import (
    QComboBox,
    QDialog,
    QDialogButtonBox,
    QFileDialog,
    QHBoxLayout,
    QHeaderView,
    QLabel,
    QLineEdit,
    QMessageBox,
    QPushButton,
    QStyledItemDelegate,
    QTableWidget,
    QTableWidgetItem,
    QTabWidget,
    QVBoxLayout,
    QWidget,
)

# api.py is the single gateway to course_cli (it puts tool/ on sys.path);
# importing the module through it keeps this file importable standalone.
from src.backend.api import course_cli

from src.backend.course_adapter import CourseAdapter
from src.backend.experience.pos_constants import POS_LABELS, POS_TAGS
from src.widgets.lesson_editor import ItemListPanel

RESOURCE_TYPES = ("vocab", "expressions", "grammar_points")
TYPE_LABELS = {
    "vocab": "词库 (Vocab)",
    "expressions": "表达 (Expressions)",
    "grammar_points": "语法 (Grammar)",
}

_LIST_FIELD = {
    "vocab": "tags",
    "expressions": "tags",
    "grammar_points": "exampleExpressionIds",
}
_LIST_FIELDS = {
    "vocab": {"tags"},
    "expressions": {"tags"},
    "grammar_points": {"exampleExpressionIds", "exampleSentenceIds"},
}

#: Editor-only columns appended past the CSV headers.
_EXTRA_COLUMNS = {
    "grammar_points": ["practiceItems"],
}


class _PosDelegate(QStyledItemDelegate):
    """Combo editor for the vocab ``pos`` column.

    The table shows Chinese labels but stores English enum values in the
    item's UserRole; commit writes the enum back via setData so
    ``_on_cell_changed`` persists ``entry['pos']``.
    """

    def createEditor(self, parent, option, index):  # noqa: N802
        combo = QComboBox(parent)
        combo.addItem("（未设置）", "")
        for value in POS_TAGS:
            combo.addItem(POS_LABELS[value], value)
        return combo

    def setEditorData(self, editor, index):  # noqa: N802
        value = index.data(Qt.ItemDataRole.UserRole) or ""
        pos = editor.findData(value)
        editor.setCurrentIndex(max(0, pos))

    def setModelData(self, editor, model, index):  # noqa: N802
        value = editor.currentData() or ""
        label = POS_LABELS.get(value, "")
        # UserRole first: _on_cell_changed (fired by the DisplayRole setData
        # below) reads the enum from UserRole.
        model.setData(index, value, Qt.ItemDataRole.UserRole)
        model.setData(index, label, Qt.ItemDataRole.DisplayRole)


def _columns(row_type: str) -> list[str]:
    headers, _rows = course_cli.build_csv_rows(row_type, [])
    return headers + _EXTRA_COLUMNS.get(row_type, [])


class ResourceTableWidget(QWidget):
    """Single resource type table: QTableWidget + add/del/import/export."""

    def __init__(self, adapter: CourseAdapter, row_type: str) -> None:
        super().__init__()
        self.adapter = adapter
        self.row_type = row_type
        self.columns = _columns(row_type)
        self._dirty = False
        self._build_ui()
        self._refresh()

    def is_dirty(self) -> bool:
        return self._dirty

    def _build_ui(self) -> None:
        layout = QVBoxLayout(self)
        self.table = QTableWidget()
        self.table.setColumnCount(len(self.columns))
        self.table.setHorizontalHeaderLabels(self.columns)
        self.table.horizontalHeader().setSectionResizeMode(
            QHeaderView.ResizeMode.Stretch
        )
        self.table.setSelectionBehavior(QTableWidget.SelectionBehavior.SelectRows)
        self.table.setSelectionMode(QTableWidget.SelectionMode.ExtendedSelection)
        self.table.itemChanged.connect(self._on_cell_changed)
        if self.row_type == "vocab" and "pos" in self.columns:
            self.table.setItemDelegateForColumn(
                self.columns.index("pos"), _PosDelegate(self.table)
            )
        layout.addWidget(self.table)

        row = QHBoxLayout()
        self.add_btn = QPushButton("+ 添加行")
        self.del_btn = QPushButton("- 删除行")
        self.batch_del_btn = QPushButton("批量删除")
        self.batch_del_btn.setToolTip("删除所有选中的行")
        self.import_btn = QPushButton("导入 CSV")
        self.export_btn = QPushButton("导出 CSV")
        row.addWidget(self.add_btn)
        row.addWidget(self.del_btn)
        row.addWidget(self.batch_del_btn)
        row.addStretch()
        row.addWidget(self.import_btn)
        row.addWidget(self.export_btn)
        layout.addLayout(row)

        self.add_btn.clicked.connect(self._on_add)
        self.del_btn.clicked.connect(self._on_del)
        self.batch_del_btn.clicked.connect(self._on_batch_del)
        self.import_btn.clicked.connect(self._on_import)
        self.export_btn.clicked.connect(self._on_export)

    def apply_filter(self, text: str) -> None:
        """Show only rows whose cells contain ``text`` (case-insensitive)."""
        text = text.strip().lower()
        for r in range(self.table.rowCount()):
            if not text:
                self.table.setRowHidden(r, False)
                continue
            match = False
            for c in range(self.table.columnCount()):
                item = self.table.item(r, c)
                if item and text in item.text().lower():
                    match = True
                    break
            self.table.setRowHidden(r, not match)

    def _refresh(self) -> None:
        self.table.blockSignals(True)
        entries = self.adapter._resource_list(self.row_type)
        self.table.setRowCount(len(entries))
        for r, entry in enumerate(entries):
            for c, col in enumerate(self.columns):
                if col == "practiceItems":
                    self._set_practice_button(r, c, entry)
                    continue
                value = entry.get(col, "")
                if col in _LIST_FIELDS.get(self.row_type, set()):
                    text = ", ".join(str(v) for v in (value or []))
                elif col == "pos":
                    text = POS_LABELS.get(value, "") if value else ""
                else:
                    text = "" if value is None else str(value)
                item = QTableWidgetItem(text)
                if col == "id":
                    item.setFlags(item.flags() & ~Qt.ItemFlag.ItemIsEditable)
                if col == "pos":
                    item.setData(Qt.ItemDataRole.UserRole, value or "")
                self.table.setItem(r, c, item)
        self.table.blockSignals(False)

    def _set_practice_button(
        self, row: int, col: int, entry: dict
    ) -> None:
        items = entry.get("practiceItems") or []
        btn = QPushButton(f"编辑练习（{len(items)} 题）")
        btn.clicked.connect(
            lambda _c, e=entry: self._open_practice_dialog(e)
        )
        self.table.setCellWidget(row, col, btn)

    def _open_practice_dialog(self, entry: dict) -> None:
        items = entry.setdefault("practiceItems", [])
        dialog = PracticeItemsDialog(
            self.adapter, entry, parent=self,
        )
        dialog.panel.show_stage({"items": items})
        dialog.exec()
        self._dirty = True
        self.adapter.notify_resources_changed()
        # Refresh the button label with the new count.
        for r in range(self.table.rowCount()):
            id_item = self.table.item(r, 0)
            if id_item is not None and id_item.text() == entry.get("id", ""):
                self._set_practice_button(r, self.columns.index("practiceItems"), entry)
                break

    def _current_entry_id(self) -> str | None:
        row = self.table.currentRow()
        if row < 0:
            return None
        item = self.table.item(row, 0)
        return item.text() if item else None

    def _on_cell_changed(self, item: QTableWidgetItem) -> None:
        col = self.columns[item.column()]
        entries = self.adapter._resource_list(self.row_type)
        row = item.row()
        if not (0 <= row < len(entries)):
            return
        entry = entries[row]
        if col == "pos":
            # Delegate stored the English enum in UserRole; empty means unset.
            value = item.data(Qt.ItemDataRole.UserRole) or ""
            entry["pos"] = value or None
        elif col in _LIST_FIELDS.get(self.row_type, set()):
            entry[col] = [p.strip() for p in item.text().split(",") if p.strip()]
        else:
            entry[col] = item.text()
        self._dirty = True
        self.adapter.notify_resources_changed()

    def _on_add(self) -> None:
        new_id = self.adapter.add_resource_entry(self.row_type)
        self._refresh()
        for r in range(self.table.rowCount()):
            if self.table.item(r, 0).text() == new_id:
                self.table.setCurrentCell(r, 1)
                break
        self._dirty = True
        self.adapter.notify_resources_changed()

    def _on_del(self) -> None:
        entry_id = self._current_entry_id()
        if not entry_id:
            return
        reply = QMessageBox.question(
            self, "删除", f"确认删除 {self.row_type} [{entry_id}]？\n保存时 validate 会校验悬空引用。",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
        )
        if reply != QMessageBox.StandardButton.Yes:
            return
        try:
            self.adapter.delete_resource_entry(self.row_type, entry_id)
        except KeyError:
            return
        self._refresh()
        self._dirty = True
        self.adapter.notify_resources_changed()

    def _on_batch_del(self) -> None:
        """Delete all selected rows at once."""
        rows = sorted(
            {idx.row() for idx in self.table.selectedIndexes()},
            reverse=True,
        )
        if not rows:
            QMessageBox.information(self, "批量删除", "请先选中要删除的行。")
            return
        reply = QMessageBox.question(
            self, "批量删除",
            f"确认删除 {len(rows)} 行？保存时 validate 会校验悬空引用。",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
        )
        if reply != QMessageBox.StandardButton.Yes:
            return
        for r in rows:
            item = self.table.item(r, 0)
            if not item:
                continue
            entry_id = item.text()
            try:
                self.adapter.delete_resource_entry(self.row_type, entry_id)
            except KeyError:
                pass
        self._refresh()
        self._dirty = True
        self.adapter.notify_resources_changed()

    def _on_import(self) -> None:
        path, _ = QFileDialog.getOpenFileName(
            self, f"导入 {self.row_type} CSV", "", "CSV Files (*.csv)"
        )
        if not path:
            return
        from pathlib import Path

        problems = self.adapter.import_csv(self.row_type, Path(path))
        errors = [p for p in problems if p["level"] == "error"]
        if errors:
            detail = "\n".join(f"[{p['level']}] {p['message']}" for p in problems)
            QMessageBox.warning(self, "导入失败（未应用）", detail)
        else:
            self._refresh()
            self._dirty = True
            self.adapter.notify_resources_changed()
            if problems:
                detail = "\n".join(f"[{p['level']}] {p['message']}" for p in problems)
                QMessageBox.information(self, "导入完成（含警告）", detail)
            else:
                QMessageBox.information(self, "导入完成", "CSV 已合并到内存，记得保存。")

    def _on_export(self) -> None:
        path, _ = QFileDialog.getSaveFileName(
            self, f"导出 {self.row_type} CSV", f"{self.row_type}.csv", "CSV Files (*.csv)"
        )
        if not path:
            return
        from pathlib import Path

        try:
            self.adapter.export_csv(self.row_type, Path(path))
        except Exception as exc:
            QMessageBox.warning(self, "导出失败", str(exc))
            return
        QMessageBox.information(self, "导出完成", f"已写入 {path}")


class PracticeItemsDialog(QDialog):
    """Grammar-point practice editor: reuses ItemListPanel on practiceItems.

    The panel binds to ``{"items": entry["practiceItems"]}`` so add/delete/edit
    mutate the entry's actual list in place (same reference, no copy-back
    needed). Supports all 14 interaction runtimeTypes incl. anki cards.
    """

    def __init__(
        self,
        adapter: CourseAdapter,
        entry: dict,
        parent: QWidget | None = None,
    ) -> None:
        super().__init__(parent)
        self.setWindowTitle(
            f"练习题目 — {entry.get('title') or entry.get('id', '')}"
        )
        self.resize(780, 540)
        layout = QVBoxLayout(self)
        hint = QLabel("该语法点的配套练习题（开课时随语法点注册 SRS）。")
        hint.setStyleSheet("color: gray;")
        layout.addWidget(hint)
        self.panel = ItemListPanel(adapter)
        layout.addWidget(self.panel, 1)
        buttons = QDialogButtonBox(QDialogButtonBox.StandardButton.Close)
        buttons.rejected.connect(self.reject)
        buttons.clicked.connect(lambda _b: self.reject())
        layout.addWidget(buttons)


class ResourceEditorDialog(QWidget):
    """Tabbed dialog: vocab / expressions / grammar_points.

    Tracks dirty state across all tabs; MainWindow reads is_dirty() on close
    to decide whether to refresh reference dropdowns.
    """

    def __init__(self, adapter: CourseAdapter, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.setWindowTitle("资源编辑")
        self.resize(900, 560)
        self.adapter = adapter
        self.tabs: list[ResourceTableWidget] = []

        layout = QVBoxLayout(self)
        hint = QLabel("编辑后关闭此窗口，再点工具栏「保存」落盘并校验。")
        hint.setStyleSheet("color: gray;")
        layout.addWidget(hint)

        # Cross-tab search bar.
        search_row = QHBoxLayout()
        search_row.addWidget(QLabel("搜索:"))
        self.search_edit = QLineEdit()
        self.search_edit.setPlaceholderText("跨所有标签页过滤（输入即筛选）...")
        self.search_edit.textChanged.connect(self._on_search_changed)
        search_row.addWidget(self.search_edit, 1)

        self.dupes_btn = QPushButton("查重")
        self.dupes_btn.setToolTip("检测 vocab 和 expressions 之间的重复词条")
        self.dupes_btn.clicked.connect(self._on_detect_dupes)
        search_row.addWidget(self.dupes_btn)

        self.pack_export_btn = QPushButton("导出资源包")
        self.pack_export_btn.setToolTip("导出所有资源为单个 JSON 资源包")
        self.pack_export_btn.clicked.connect(self._on_export_pack)
        search_row.addWidget(self.pack_export_btn)

        self.pack_import_btn = QPushButton("导入资源包")
        self.pack_import_btn.setToolTip("从 JSON 资源包合并资源")
        self.pack_import_btn.clicked.connect(self._on_import_pack)
        search_row.addWidget(self.pack_import_btn)
        layout.addLayout(search_row)

        self.tab_widget = QTabWidget()
        for rt in RESOURCE_TYPES:
            tab = ResourceTableWidget(adapter, rt)
            self.tab_widget.addTab(tab, TYPE_LABELS[rt])
            self.tabs.append(tab)
        layout.addWidget(self.tab_widget)

    def is_dirty(self) -> bool:
        return any(tab.is_dirty() for tab in self.tabs)

    def _on_search_changed(self, text: str) -> None:
        for tab in self.tabs:
            tab.apply_filter(text)

    def _on_detect_dupes(self) -> None:
        dupes = self.adapter.detect_duplicates()
        if not dupes:
            QMessageBox.information(self, "查重", "未发现重复词条。")
            return
        lines = [
            f"发现 {len(dupes)} 个重复：\n"
        ]
        for d in dupes:
            lines.append(f"  {d['type']} [{d['id']}] 「{d['term']}」 与 {d['duplicate_in']} 重复")
        QMessageBox.information(self, "查重结果", "\n".join(lines))

    def _on_export_pack(self) -> None:
        path, _ = QFileDialog.getSaveFileName(
            self, "导出资源包", "resource-pack.json", "JSON Files (*.json)"
        )
        if not path:
            return
        from pathlib import Path
        try:
            self.adapter.export_resource_pack(Path(path))
            QMessageBox.information(self, "导出完成", f"资源包已写入 {path}")
        except Exception as exc:
            QMessageBox.warning(self, "导出失败", str(exc))

    def _on_import_pack(self) -> None:
        path, _ = QFileDialog.getOpenFileName(
            self, "导入资源包", "", "JSON Files (*.json)"
        )
        if not path:
            return
        from pathlib import Path
        reply = QMessageBox.question(
            self, "导入资源包",
            "合并模式（是=合并去重，否=完全替换）？",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No | QMessageBox.StandardButton.Cancel,
            QMessageBox.StandardButton.Yes,
        )
        if reply == QMessageBox.StandardButton.Cancel:
            return
        replace = reply == QMessageBox.StandardButton.No
        try:
            counts = self.adapter.import_resource_pack(Path(path), replace=replace)
            detail = "\n".join(f"{k}: {v}" for k, v in counts.items())
            for tab in self.tabs:
                tab._refresh()
            QMessageBox.information(self, "导入完成", f"已{'替换' if replace else '合并'}资源：\n{detail}")
        except Exception as exc:
            QMessageBox.warning(self, "导入失败", str(exc))
