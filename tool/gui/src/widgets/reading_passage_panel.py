"""Unified ReadingPassage editor widget shared by LessonEditor, Blueprint, and Teacher view.

Covers every field of ``ReadingPassage`` (``lib/domain/course/reading_passage.dart``):
- ``title``, ``difficulty``, ``paragraphs``
- ``imageAsset`` (with media picker incl. ``.svg``) + ``imageAlt``
- ``wordFormMap`` (surface form -> vocab id table)
- ``linkedWordIds`` and ``linkedExpressionIds`` (checkable resource pickers)

Zero direct ``src.backend`` imports so ``max_ui_backend_imports`` stays unchanged.
"""
from __future__ import annotations

from typing import Any

from PySide6.QtCore import Qt, Signal
from PySide6.QtWidgets import (
    QComboBox,
    QFormLayout,
    QHBoxLayout,
    QHeaderView,
    QLabel,
    QLineEdit,
    QListWidget,
    QListWidgetItem,
    QPushButton,
    QSpinBox,
    QTableWidget,
    QTableWidgetItem,
    QTextEdit,
    QVBoxLayout,
    QWidget,
)

from src.theme import current_palette
from src.widgets.media_picker import pick_course_media


class ReadingPassagePanel(QWidget):
    """Editable or read-only panel bound directly to a ``readingPassage`` dict."""

    changed = Signal()

    def __init__(
        self,
        adapter: Any,
        passage: dict[str, Any],
        *,
        read_only: bool = False,
        parent: QWidget | None = None,
    ) -> None:
        super().__init__(parent)
        self.adapter = adapter
        self.passage = passage
        self.read_only = read_only
        self.passage.setdefault("title", "")
        self.passage.setdefault("paragraphs", [])
        self.passage.setdefault("difficulty", 1)
        self.passage.setdefault("linkedWordIds", [])
        self.passage.setdefault("linkedExpressionIds", [])
        self.passage.setdefault("wordFormMap", {})
        self.passage.setdefault("imageAsset", "")
        self.passage.setdefault("imageAlt", "")
        self._build_ui()

    def _build_ui(self) -> None:
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(8)
        pal = current_palette()

        if self.read_only:
            title_lbl = QLabel(self.passage.get("title") or "（无标题）")
            title_lbl.setStyleSheet(f"font-weight: 600; color: {pal['text']};")
            layout.addWidget(title_lbl)
            meta_parts = [f"难度 {self.passage.get('difficulty', 1)}"]
            if self.passage.get("imageAsset"):
                meta_parts.append(f"插图：{self.passage['imageAsset']}")
            if self.passage.get("wordFormMap"):
                meta_parts.append(f"词形映射：{len(self.passage['wordFormMap'])} 项")
            if self.passage.get("linkedWordIds"):
                meta_parts.append(f"关联词：{len(self.passage['linkedWordIds'])}")
            if self.passage.get("linkedExpressionIds"):
                meta_parts.append(f"关联表达：{len(self.passage['linkedExpressionIds'])}")
            meta = QLabel(" · ".join(meta_parts))
            meta.setStyleSheet(f"color: {pal['text_secondary']};")
            layout.addWidget(meta)
            for para_text in self.passage.get("paragraphs", []):
                para = QLabel(str(para_text))
                para.setWordWrap(True)
                para.setStyleSheet(f"color: {pal['text_secondary']};")
                layout.addWidget(para)
            return

        form = QFormLayout()
        form.setSpacing(6)

        self.title_edit = QLineEdit(str(self.passage.get("title") or ""))
        self.title_edit.setPlaceholderText("篇章标题")
        self.title_edit.textChanged.connect(self._on_title_changed)
        form.addRow("标题：", self.title_edit)

        self.diff_spin = QSpinBox()
        self.diff_spin.setRange(1, 5)
        self.diff_spin.setValue(int(self.passage.get("difficulty") or 1))
        self.diff_spin.valueChanged.connect(self._on_diff_changed)
        form.addRow("难度 (1-5)：", self.diff_spin)

        self.paras_edit = QTextEdit("\n\n".join(self.passage.get("paragraphs") or []))
        self.paras_edit.setMaximumHeight(140)
        self.paras_edit.setPlaceholderText("段落之间用空行分隔")
        self.paras_edit.textChanged.connect(self._on_paras_changed)
        form.addRow("正文段落：", self.paras_edit)

        img_row_host = QWidget()
        img_row = QHBoxLayout(img_row_host)
        img_row.setContentsMargins(0, 0, 0, 0)
        self.image_edit = QLineEdit(str(self.passage.get("imageAsset") or ""))
        self.image_edit.setPlaceholderText("media/story.svg 或 assets/images/...")
        self.image_edit.textChanged.connect(self._on_image_changed)
        self.pick_img_btn = QPushButton("选择插图")
        self.pick_img_btn.clicked.connect(self._on_pick_image)
        img_row.addWidget(self.image_edit, 1)
        img_row.addWidget(self.pick_img_btn)
        form.addRow("插图资源：", img_row_host)

        self.alt_edit = QLineEdit(str(self.passage.get("imageAlt") or ""))
        self.alt_edit.setPlaceholderText("无障碍插图说明（ADR 0072）")
        self.alt_edit.textChanged.connect(self._on_alt_changed)
        form.addRow("插图替代文本：", self.alt_edit)

        layout.addLayout(form)

        # wordFormMap table
        layout.addWidget(QLabel("词形映射（文中屈折词形 → 词库 ID）："))
        self.forms_table = QTableWidget(0, 2)
        self.forms_table.setHorizontalHeaderLabels(["文中词形", "词库 ID"])
        self.forms_table.horizontalHeader().setSectionResizeMode(
            QHeaderView.ResizeMode.Stretch
        )
        self.forms_table.setMaximumHeight(130)
        self.forms_table.cellChanged.connect(self._on_forms_cell_changed)
        layout.addWidget(self.forms_table)

        form_btns = QHBoxLayout()
        self.form_word_combo = QComboBox()
        for wid, label in self.adapter.vocab_options():
            self.form_word_combo.addItem(f"{label} ({wid})", wid)
        add_form_btn = QPushButton("+ 添加映射")
        add_form_btn.clicked.connect(self._on_add_form)
        del_form_btn = QPushButton("- 删除选中")
        del_form_btn.clicked.connect(self._on_del_form)
        form_btns.addWidget(self.form_word_combo, 1)
        form_btns.addWidget(add_form_btn)
        form_btns.addWidget(del_form_btn)
        layout.addLayout(form_btns)

        # linkedWordIds / linkedExpressionIds side-by-side check lists
        links_row = QHBoxLayout()
        self.linked_words_list = self._build_check_list(
            self.adapter.vocab_options(),
            set(self.passage.get("linkedWordIds") or []),
            self._on_linked_words_changed,
        )
        self.linked_exprs_list = self._build_check_list(
            self.adapter.expression_options(),
            set(self.passage.get("linkedExpressionIds") or []),
            self._on_linked_exprs_changed,
        )
        w_col = QVBoxLayout()
        w_col.addWidget(QLabel("关联词汇 (linkedWordIds)："))
        w_col.addWidget(self.linked_words_list)
        e_col = QVBoxLayout()
        e_col.addWidget(QLabel("关联表达 (linkedExpressionIds)："))
        e_col.addWidget(self.linked_exprs_list)
        links_row.addLayout(w_col)
        links_row.addLayout(e_col)
        layout.addLayout(links_row)

        self._refresh_forms_table()

    def _build_check_list(
        self,
        options: list[tuple[str, str]],
        checked: set[str],
        on_changed: Any,
    ) -> QListWidget:
        lw = QListWidget()
        lw.setMaximumHeight(110)
        lw.setSelectionMode(QListWidget.SelectionMode.NoSelection)
        for rid, label in options:
            item = QListWidgetItem(f"{label} ({rid})")
            item.setData(Qt.ItemDataRole.UserRole, rid)
            item.setFlags(item.flags() | Qt.ItemFlag.ItemIsUserCheckable)
            item.setCheckState(
                Qt.CheckState.Checked if rid in checked else Qt.CheckState.Unchecked
            )
            lw.addItem(item)
        lw.itemChanged.connect(on_changed)
        return lw

    def _refresh_forms_table(self) -> None:
        self.forms_table.blockSignals(True)
        items = list((self.passage.get("wordFormMap") or {}).items())
        self.forms_table.setRowCount(len(items))
        for row, (surface, word_id) in enumerate(items):
            self.forms_table.setItem(row, 0, QTableWidgetItem(str(surface)))
            self.forms_table.setItem(row, 1, QTableWidgetItem(str(word_id)))
        self.forms_table.blockSignals(False)

    def _sync_forms_from_table(self) -> None:
        result: dict[str, str] = {}
        for row in range(self.forms_table.rowCount()):
            s_item = self.forms_table.item(row, 0)
            w_item = self.forms_table.item(row, 1)
            surface = s_item.text().strip() if s_item else ""
            word_id = w_item.text().strip() if w_item else ""
            if surface and word_id:
                result[surface] = word_id
        self.passage["wordFormMap"] = result
        self.changed.emit()

    def _on_forms_cell_changed(self, _row: int, _col: int) -> None:
        self._sync_forms_from_table()

    def _on_add_form(self) -> None:
        wid = self.form_word_combo.currentData() or ""
        row = self.forms_table.rowCount()
        self.forms_table.blockSignals(True)
        self.forms_table.insertRow(row)
        self.forms_table.setItem(row, 0, QTableWidgetItem(""))
        self.forms_table.setItem(row, 1, QTableWidgetItem(str(wid)))
        self.forms_table.blockSignals(False)
        self.forms_table.setCurrentCell(row, 0)

    def _on_del_form(self) -> None:
        row = self.forms_table.currentRow()
        if 0 <= row < self.forms_table.rowCount():
            self.forms_table.removeRow(row)
            self._sync_forms_from_table()

    def _on_title_changed(self, text: str) -> None:
        self.passage["title"] = text
        self.changed.emit()

    def _on_diff_changed(self, val: int) -> None:
        self.passage["difficulty"] = val
        self.changed.emit()

    def _on_paras_changed(self) -> None:
        self.passage["paragraphs"] = [
            s.strip() for s in self.paras_edit.toPlainText().split("\n\n") if s.strip()
        ]
        self.changed.emit()

    def _on_image_changed(self, text: str) -> None:
        self.passage["imageAsset"] = text
        self.changed.emit()

    def _on_pick_image(self) -> None:
        course_dir = getattr(self.adapter, "course_dir", None)
        chosen = pick_course_media(self, course_dir, kind="image")
        if chosen:
            self.image_edit.setText(chosen)

    def _on_alt_changed(self, text: str) -> None:
        self.passage["imageAlt"] = text
        self.changed.emit()

    def _on_linked_words_changed(self, _item: QListWidgetItem) -> None:
        self.passage["linkedWordIds"] = [
            self.linked_words_list.item(i).data(Qt.ItemDataRole.UserRole)
            for i in range(self.linked_words_list.count())
            if self.linked_words_list.item(i).checkState() == Qt.CheckState.Checked
        ]
        self.changed.emit()

    def _on_linked_exprs_changed(self, _item: QListWidgetItem) -> None:
        self.passage["linkedExpressionIds"] = [
            self.linked_exprs_list.item(i).data(Qt.ItemDataRole.UserRole)
            for i in range(self.linked_exprs_list.count())
            if self.linked_exprs_list.item(i).checkState() == Qt.CheckState.Checked
        ]
        self.changed.emit()
