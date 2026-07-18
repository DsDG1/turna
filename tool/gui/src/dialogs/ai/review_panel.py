"""Review stage panel for the workshop (merge overhaul Phase C).

Read-side companion of the design stage: it renders the current draft from
the ``DesignPanel``'s JSON editor (the single source of truth, B1) through
the structured ``ResultPreviewWidget``, and offers the shared review
actions — lesson preview (试做), diff against the existing course section,
AI fix, and import. The draft itself is edited on the design page; this
panel never forks the truth.
"""
from __future__ import annotations

from typing import Any

from PySide6.QtWidgets import (
    QHBoxLayout,
    QLabel,
    QMessageBox,
    QPushButton,
    QVBoxLayout,
    QWidget,
)

from src.theme import current_palette
from src.widgets.result_preview import ResultPreviewWidget


class ReviewPanel(QWidget):
    """Structured review of the design draft before import."""

    def __init__(
        self,
        design_panel: Any,
        adapter: Any,
        parent: QWidget | None = None,
    ) -> None:
        super().__init__(parent)
        self._design_panel = design_panel
        self.adapter = adapter

        lay = QVBoxLayout(self)
        lay.setContentsMargins(8, 8, 8, 8)
        lay.setSpacing(6)

        self._preview = ResultPreviewWidget(adapter, self)
        lay.addWidget(self._preview, 1)

        self._hint_label = QLabel("")
        self._hint_label.setStyleSheet(
            f"color: {current_palette()['text_secondary']};"
        )
        lay.addWidget(self._hint_label)

        row = QHBoxLayout()
        self._try_btn = QPushButton("试做")
        self._try_btn.setToolTip("用播放器试做草稿中的某一课时")
        self._try_btn.clicked.connect(self._on_try)
        row.addWidget(self._try_btn)
        self._diff_btn = QPushButton("与现有课程对比 (diff)")
        self._diff_btn.clicked.connect(self._on_diff)
        row.addWidget(self._diff_btn)
        self._fix_btn = QPushButton("AI 修复")
        self._fix_btn.setToolTip("让 AI 修复校验发现的问题")
        self._fix_btn.clicked.connect(self._on_fix)
        row.addWidget(self._fix_btn)
        row.addStretch(1)
        self._import_btn = QPushButton("导入到课程 ↗")
        self._import_btn.setDefault(True)
        self._import_btn.clicked.connect(self._on_import)
        row.addWidget(self._import_btn)
        lay.addLayout(row)

        self.refresh()

    # ------------------------------------------------------------------ state
    def _draft(self) -> dict | None:
        """Current editor truth from the design panel (None when empty)."""
        return self._design_panel._current_editor_json_silent()

    def refresh(self) -> None:
        """Re-render from the design panel's current draft."""
        draft = self._draft()
        has = draft is not None
        if has:
            self._preview.show_section(draft)
            units = draft.get("units", [])
            lessons = sum(len(u.get("lessons", [])) for u in units)
            self._hint_label.setText(
                f"草稿「{draft.get('name', draft.get('id', ''))}」："
                f"{len(units)} 单元 · {lessons} 课时 · {len(draft.get('words', []))} 词"
            )
        else:
            self._hint_label.setText("还没有草稿 — 请先在「设计」阶段生成。")
        for btn in (self._try_btn, self._diff_btn, self._fix_btn, self._import_btn):
            btn.setEnabled(has)

    # ------------------------------------------------------------------ actions
    def _on_try(self) -> None:
        self._design_panel._on_try_lesson()
        self.refresh()

    def _on_diff(self) -> None:
        draft = self._draft()
        if draft is None:
            return
        if self.adapter is None:
            QMessageBox.information(self, "对比", "未加载课程，无法对比。")
            return
        try:
            existing = self.adapter.find_section(draft.get("id", ""))
        except KeyError:
            QMessageBox.information(
                self, "对比", "当前课程中没有同 id 的 section — 导入将是全新内容。"
            )
            return
        from src.widgets.diff_view import SectionDiffView

        SectionDiffView(existing, draft, self).exec()

    def _on_fix(self) -> None:
        draft = self._draft()
        if draft is None:
            return
        if self.adapter is None:
            QMessageBox.information(self, "AI 修复", "未加载课程，无法校验与修复。")
            return
        problems = self.adapter.validate_section_json(draft, check_existing_ids=False)
        if not problems:
            QMessageBox.information(self, "AI 修复", "校验没有发现问题，无需修复。")
            return
        course_context = {
            "node_kind": "section",
            "node_id": draft.get("id", ""),
            "language": self.adapter.index.get("language", "en"),
            "existing_resource_ids": {
                "vocab": [w.get("id") for w in self.adapter.vocab if w.get("id")],
                "expressions": [
                    e.get("id") for e in self.adapter.expressions if e.get("id")
                ],
                "grammar_points": [
                    g.get("id") for g in self.adapter.grammar_points if g.get("id")
                ],
            },
        }
        from src.app import current_ai_config
        from src.dialogs.ai_fix_dialog import AiFixDialog

        dlg = AiFixDialog(problems, draft, course_context, current_ai_config(), parent=self)
        from PySide6.QtWidgets import QDialog

        if dlg.exec() != QDialog.DialogCode.Accepted:
            return
        corrected = dlg.corrected_node()
        if corrected is None:
            return
        # Apply back into the single truth: the design page's JSON editor.
        self._design_panel._json_editor.set_json(corrected)
        self._design_panel._controller.set_draft(corrected)
        self.refresh()

    def _on_import(self) -> None:
        # Validation + emit lives on the design panel (single truth path).
        self._design_panel._on_import()
