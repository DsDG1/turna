"""Textbook project library: create, resume, or delete import projects."""
from __future__ import annotations

from pathlib import Path
from typing import Any

from PySide6.QtCore import Qt, Signal
from PySide6.QtWidgets import (
    QComboBox,
    QDialog,
    QDialogButtonBox,
    QFileDialog,
    QFormLayout,
    QHBoxLayout,
    QHeaderView,
    QLabel,
    QMessageBox,
    QPushButton,
    QTableWidget,
    QTableWidgetItem,
    QVBoxLayout,
)

from src.backend.textbook_project import TextbookProject
from src.backend.textbook_project_store import TextbookProjectStore

_STEP_LABELS = [
    "选择教材",
    "解析课本",
    "章节勾选",
    "提取知识点",
    "审校",
    "导入",
]


class TextbookLibraryDialog(QDialog):
    """Dialog for managing textbook import projects.

    Emits ``project_selected`` when the user chooses to create or continue a
    project. The caller then opens ``TextbookImportDialog`` with that project.
    """

    project_selected = Signal(object)  # TextbookProject | None

    def __init__(
        self,
        store: TextbookProjectStore | None = None,
        parent: Any | None = None,
        *,
        embedded: bool = False,
    ) -> None:
        super().__init__(parent)
        self._store = store or TextbookProjectStore()
        self.selected_project: TextbookProject | None = None
        # Embedded mode (P2-2): hosted inside WorkshopWindow as a plain
        # widget — project selection is signalled, never accept()/hide.
        self._embedded = embedded
        self.setWindowTitle("课本项目库")
        self.resize(720, 420)
        self._build_ui()
        self._refresh_list()

    def _build_ui(self) -> None:
        layout = QVBoxLayout(self)
        layout.setContentsMargins(16, 16, 16, 16)
        layout.setSpacing(12)

        layout.addWidget(QLabel("选择一个现有项目继续，或新建项目开始导入。"))

        self._table = QTableWidget(0, 5)
        self._table.setHorizontalHeaderLabels(
            ["项目名称", "源文件", "当前步骤", "更新时间", "已导入"]
        )
        self._table.horizontalHeader().setSectionResizeMode(0, QHeaderView.ResizeMode.Stretch)
        self._table.horizontalHeader().setSectionResizeMode(1, QHeaderView.ResizeMode.Stretch)
        self._table.setSelectionBehavior(QTableWidget.SelectionBehavior.SelectRows)
        self._table.setSelectionMode(QTableWidget.SelectionMode.SingleSelection)
        self._table.doubleClicked.connect(self._on_continue)
        layout.addWidget(self._table)

        self._empty_label = QLabel("还没有课本项目，点击「新建项目」开始。")
        self._empty_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self._empty_label.setStyleSheet("color: #9CA3AF; padding: 40px;")
        layout.addWidget(self._empty_label)

        btn_row = QHBoxLayout()
        self._new_btn = QPushButton("新建项目")
        self._new_btn.clicked.connect(self._on_new)
        self._continue_btn = QPushButton("继续")
        self._continue_btn.setEnabled(False)
        self._continue_btn.clicked.connect(self._on_continue)
        self._delete_btn = QPushButton("删除")
        self._delete_btn.setEnabled(False)
        self._delete_btn.clicked.connect(self._on_delete)
        btn_row.addWidget(self._new_btn)
        btn_row.addStretch()
        btn_row.addWidget(self._continue_btn)
        btn_row.addWidget(self._delete_btn)
        layout.addLayout(btn_row)

        self._table.itemSelectionChanged.connect(self._update_button_state)

    def _refresh_list(self) -> None:
        self._projects = self._store.list_projects()
        self._table.setRowCount(len(self._projects))
        for row, project in enumerate(self._projects):
            self._table.setItem(row, 0, QTableWidgetItem(project.name))
            source_name = Path(project.source_path).name if project.source_path else "—"
            self._table.setItem(row, 1, QTableWidgetItem(source_name))
            step_label = (
                _STEP_LABELS[project.current_step]
                if 0 <= project.current_step < len(_STEP_LABELS)
                else "未知"
            )
            self._table.setItem(row, 2, QTableWidgetItem(step_label))
            self._table.setItem(row, 3, QTableWidgetItem(project.updated_at[:19].replace("T", " ")))
            imported = "是" if project.is_fully_imported else "否"
            self._table.setItem(row, 4, QTableWidgetItem(imported))

        has_projects = len(self._projects) > 0
        self._table.setVisible(has_projects)
        self._empty_label.setVisible(not has_projects)
        self._update_button_state()

    def _selected_project(self) -> TextbookProject | None:
        rows = self._table.selectionModel().selectedRows()
        if not rows:
            return None
        idx = rows[0].row()
        if 0 <= idx < len(self._projects):
            return self._projects[idx]
        return None

    def _update_button_state(self) -> None:
        has_selection = self._selected_project() is not None
        self._continue_btn.setEnabled(has_selection)
        self._delete_btn.setEnabled(has_selection)

    def _on_new(self) -> None:
        path, _ = QFileDialog.getOpenFileName(
            self,
            "选择教材",
            "",
            "教材 (*.md *.txt *.pdf);;所有文件 (*)",
        )
        if not path:
            return
        languages = self._pick_languages()
        if languages is None:
            return
        source = Path(path)
        name = source.stem
        project = self._store.create_project(
            name=name,
            source_path=source,
            language=languages[0],
            source_language=languages[1],
        )
        self.selected_project = project
        self.project_selected.emit(project)
        if not self._embedded:
            self.accept()

    def _pick_languages(self) -> tuple[str, str] | None:
        """Ask for the target/source language pair of a new project (P0-3).

        Returns ``(target_language, source_language)`` or None on cancel.
        """
        dlg = QDialog(self)
        dlg.setWindowTitle("项目语言")
        lay = QVBoxLayout(dlg)
        lay.addWidget(QLabel("选择这本教材的目标语言（要学）与讲解语言："))
        form = QFormLayout()
        target = QComboBox()
        target.setEditable(True)
        target.addItems(
            ["Turkish", "English", "Spanish", "Japanese", "Korean", "German", "French"]
        )
        source = QComboBox()
        source.setEditable(True)
        source.addItems(["Chinese", "English", "Japanese", "Korean"])
        form.addRow("目标语言", target)
        form.addRow("讲解语言", source)
        lay.addLayout(form)
        btns = QDialogButtonBox(
            QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel
        )
        btns.accepted.connect(dlg.accept)
        btns.rejected.connect(dlg.reject)
        lay.addWidget(btns)
        if dlg.exec() != QDialog.DialogCode.Accepted:
            return None
        return (
            target.currentText().strip() or "Turkish",
            source.currentText().strip() or "Chinese",
        )

    def _on_continue(self) -> None:
        project = self._selected_project()
        if project is None:
            return
        if project.source_path and project.source_changed():
            reply = QMessageBox.question(
                self,
                "源文件已变更",
                "教材源文件自上次保存后已被修改。是否继续？",
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
            )
            if reply != QMessageBox.StandardButton.Yes:
                return
        self.selected_project = project
        self.project_selected.emit(project)
        if not self._embedded:
            self.accept()

    def _on_delete(self) -> None:
        project = self._selected_project()
        if project is None:
            return
        reply = QMessageBox.question(
            self,
            "删除项目",
            f"确定要删除项目「{project.name}」吗？本地项目文件将被一并删除。",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
        )
        if reply == QMessageBox.StandardButton.Yes:
            self._store.delete_project(project.project_id)
            self._refresh_list()
