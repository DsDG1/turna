"""Visual reviewer & editor for Phase Two ``media_manifest.json`` and ``audio_manifest.json``.

All backend I/O routes through ``src.application.lesson_edit_service`` so zero
direct UI -> backend imports are introduced.
"""
from __future__ import annotations

from pathlib import Path
from typing import Any

from PySide6.QtCore import Qt
from PySide6.QtWidgets import (
    QDialog,
    QHBoxLayout,
    QHeaderView,
    QLabel,
    QMessageBox,
    QPushButton,
    QTableWidget,
    QTableWidgetItem,
    QTabWidget,
    QVBoxLayout,
    QWidget,
)

from src.application.lesson_edit_service import (
    audit_media_manifest,
    load_audio_manifest_doc,
    load_media_manifest,
    register_missing_media_entries,
    resolve_asset_on_disk,
    save_audio_manifest_doc,
    save_media_manifest,
)
from src.teacher.preview_media import PreviewAudioBar, PreviewImageWidget
from src.theme import current_palette


class ManifestDialog(QDialog):
    """Tabbed dialog to inspect and edit ``media_manifest.json`` and ``audio_manifest.json``."""

    def __init__(self, adapter: Any, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.adapter = adapter
        self.course_dir: Path | None = (
            Path(adapter.course_dir) if getattr(adapter, "course_dir", None) else None
        )
        self.media_doc = load_media_manifest(self.course_dir)
        self.audio_doc = load_audio_manifest_doc(self.course_dir)
        self.setWindowTitle("媒体与音频清单审校")
        self.resize(860, 600)
        self._build_ui()

    def _build_ui(self) -> None:
        layout = QVBoxLayout(self)
        tabs = QTabWidget()
        tabs.addTab(self._build_media_tab(), "图片清单 (media_manifest.json)")
        tabs.addTab(self._build_audio_tab(), "音频清单 (audio_manifest.json)")
        layout.addWidget(tabs, 1)

        footer = QHBoxLayout()
        footer.addStretch()
        save_btn = QPushButton("保存清单")
        save_btn.clicked.connect(self._on_save)
        close_btn = QPushButton("关闭")
        close_btn.clicked.connect(self.accept)
        footer.addWidget(save_btn)
        footer.addWidget(close_btn)
        layout.addLayout(footer)

    # --- media tab --------------------------------------------------------

    def _build_media_tab(self) -> QWidget:
        page = QWidget()
        layout = QVBoxLayout(page)

        self.media_summary_lbl = QLabel("")
        self.media_summary_lbl.setWordWrap(True)
        self.media_summary_lbl.setStyleSheet(
            f"color: {current_palette()['text_secondary']};"
        )
        layout.addWidget(self.media_summary_lbl)

        self.media_table = QTableWidget(0, 6)
        self.media_table.setHorizontalHeaderLabels(
            ["asset", "alt", "source", "generatedBy", "reviewStatus", "文件状态"]
        )
        self.media_table.horizontalHeader().setSectionResizeMode(
            QHeaderView.ResizeMode.Stretch
        )
        self.media_table.cellChanged.connect(self._on_media_cell_changed)
        self.media_table.currentCellChanged.connect(self._on_media_row_selected)
        layout.addWidget(self.media_table, 1)

        self.media_preview_host = QWidget()
        self.media_preview_layout = QVBoxLayout(self.media_preview_host)
        self.media_preview_layout.setContentsMargins(0, 4, 0, 4)
        layout.addWidget(self.media_preview_host)

        bar = QHBoxLayout()
        sync_btn = QPushButton("补登记未入表图片引用")
        sync_btn.clicked.connect(self._on_register_missing_media)
        bar.addWidget(sync_btn)
        bar.addStretch()
        layout.addLayout(bar)

        self._refresh_media_tab()
        return page

    def _refresh_media_tab(self) -> None:
        summary = audit_media_manifest(self.adapter)
        self.media_summary_lbl.setText(
            f"已登记 {summary.registered_count} 项 · "
            f"缺失文件 {len(summary.missing_files)} · "
            f"未登记引用 {len(summary.unregistered_refs)} · "
            f"待审校 {summary.pending_review_count}"
        )
        assets = self.media_doc.setdefault("assets", [])
        self.media_table.blockSignals(True)
        self.media_table.setRowCount(len(assets))
        for r, entry in enumerate(assets):
            asset_ref = str(entry.get("asset") or "")
            exists = resolve_asset_on_disk(self.course_dir, asset_ref) is not None
            cols = (
                asset_ref,
                str(entry.get("alt") or ""),
                str(entry.get("source") or ""),
                str(entry.get("generatedBy") or ""),
                str(entry.get("reviewStatus") or "pending"),
                "✓ 存在" if exists else "✗ 缺失",
            )
            for c, val in enumerate(cols):
                item = QTableWidgetItem(val)
                if c in (0, 5):
                    item.setFlags(item.flags() & ~Qt.ItemFlag.ItemIsEditable)
                self.media_table.setItem(r, c, item)
        self.media_table.blockSignals(False)

    def _on_media_cell_changed(self, row: int, col: int) -> None:
        keys = ("asset", "alt", "source", "generatedBy", "reviewStatus")
        assets = self.media_doc.get("assets") or []
        if 0 <= row < len(assets) and 1 <= col < len(keys):
            assets[row][keys[col]] = self.media_table.item(row, col).text().strip()

    def _on_media_row_selected(self, row: int, _col: int, _pr: int, _pc: int) -> None:
        while self.media_preview_layout.count():
            child = self.media_preview_layout.takeAt(0)
            w = child.widget()
            if w is not None:
                w.setParent(None)
                w.deleteLater()
        assets = self.media_doc.get("assets") or []
        if 0 <= row < len(assets):
            entry = assets[row]
            self.media_preview_layout.addWidget(
                PreviewImageWidget(
                    self.course_dir,
                    str(entry.get("asset") or ""),
                    alt_text=str(entry.get("alt") or ""),
                    max_width=240,
                    max_height=140,
                )
            )

    def _on_register_missing_media(self) -> None:
        added = register_missing_media_entries(self.adapter, self.media_doc)
        self._refresh_media_tab()
        QMessageBox.information(
            self,
            "补登记完成",
            f"已补登记 {added} 条课内图片引用（记得点击「保存清单」落盘）。"
            if added
            else "所有课内图片引用均已在清单中。",
        )

    # --- audio tab --------------------------------------------------------

    def _build_audio_tab(self) -> QWidget:
        page = QWidget()
        layout = QVBoxLayout(page)

        self.audio_table = QTableWidget(0, 6)
        self.audio_table.setHorizontalHeaderLabels(
            ["asset", "lessonId", "speakers", "speed", "reviewStatus", "text"]
        )
        self.audio_table.horizontalHeader().setSectionResizeMode(
            QHeaderView.ResizeMode.Stretch
        )
        self.audio_table.cellChanged.connect(self._on_audio_cell_changed)
        self.audio_table.currentCellChanged.connect(self._on_audio_row_selected)
        layout.addWidget(self.audio_table, 1)

        self.audio_preview_host = QWidget()
        self.audio_preview_layout = QVBoxLayout(self.audio_preview_host)
        self.audio_preview_layout.setContentsMargins(0, 4, 0, 4)
        layout.addWidget(self.audio_preview_host)

        self._refresh_audio_tab()
        return page

    def _refresh_audio_tab(self) -> None:
        assets = self.audio_doc.setdefault("assets", [])
        self.audio_table.blockSignals(True)
        self.audio_table.setRowCount(len(assets))
        for r, entry in enumerate(assets):
            speakers = entry.get("speakers") or []
            cols = (
                str(entry.get("asset") or ""),
                str(entry.get("lessonId") or ""),
                ", ".join(str(s) for s in speakers) if isinstance(speakers, list) else str(speakers),
                str(entry.get("speed") if entry.get("speed") is not None else ""),
                str(entry.get("reviewStatus") or "pending"),
                str(entry.get("text") or ""),
            )
            for c, val in enumerate(cols):
                item = QTableWidgetItem(val)
                if c in (0, 1):
                    item.setFlags(item.flags() & ~Qt.ItemFlag.ItemIsEditable)
                self.audio_table.setItem(r, c, item)
        self.audio_table.blockSignals(False)

    def _on_audio_cell_changed(self, row: int, col: int) -> None:
        assets = self.audio_doc.get("assets") or []
        if not (0 <= row < len(assets)):
            return
        val = self.audio_table.item(row, col).text().strip()
        if col == 2:
            assets[row]["speakers"] = [p.strip() for p in val.split(",") if p.strip()]
        elif col == 3:
            try:
                assets[row]["speed"] = float(val) if val else None
            except ValueError:
                return
        elif col == 4:
            assets[row]["reviewStatus"] = val or "pending"
        elif col == 5:
            assets[row]["text"] = val

    def _on_audio_row_selected(self, row: int, _col: int, _pr: int, _pc: int) -> None:
        while self.audio_preview_layout.count():
            child = self.audio_preview_layout.takeAt(0)
            w = child.widget()
            if w is not None:
                w.setParent(None)
                w.deleteLater()
        assets = self.audio_doc.get("assets") or []
        if 0 <= row < len(assets):
            asset = str(assets[row].get("asset") or "")
            if asset:
                self.audio_preview_layout.addWidget(
                    PreviewAudioBar(self.course_dir, asset, label="音频")
                )

    def _on_save(self) -> None:
        if self.course_dir is None:
            QMessageBox.warning(self, "保存清单", "当前未打开课程目录，无法保存清单。")
            return
        save_media_manifest(self.course_dir, self.media_doc)
        if self.audio_doc.get("assets"):
            save_audio_manifest_doc(self.course_dir, self.audio_doc)
        self._refresh_media_tab()
        QMessageBox.information(self, "保存清单", "清单已保存。")
