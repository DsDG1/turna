"""Review stage panel for the workshop (merge overhaul Phase C + P1 fluency).

Read-side companion of the design stage: it renders the current draft from
the ``DesignPanel``'s JSON editor (the single source of truth, B1) through
the structured ``ResultPreviewWidget``, and offers the shared review
actions — lesson preview (试做), diff against the existing course section,
AI fix (with confirm-diff), and import.
"""
from __future__ import annotations

from typing import Any

from PySide6.QtWidgets import (
    QDialog,
    QHBoxLayout,
    QLabel,
    QMessageBox,
    QPushButton,
    QVBoxLayout,
    QWidget,
)

from src.backend.grounded_stats import draft_coverage, format_coverage_line
from src.theme import current_palette
from src.widgets.result_preview import ResultPreviewWidget

_EMPTY_HINT = (
    "还没有草稿 — 在中间 AI 轨道点「开始设计课程」，"
    "或打开「设计与草稿」对话生成。"
)


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
        self._preview.regenerate_requested.connect(self._on_regenerate_requested)
        lay.addWidget(self._preview, 1)

        self._hint_label = QLabel("")
        self._hint_label.setStyleSheet(
            f"color: {current_palette()['text_secondary']};"
        )
        lay.addWidget(self._hint_label)

        self._coverage_label = QLabel("")
        self._coverage_label.setWordWrap(True)
        self._coverage_label.setStyleSheet(
            f"color: {current_palette()['text_secondary']}; font-size: 11px;"
        )
        self._coverage_label.setVisible(False)
        lay.addWidget(self._coverage_label)

        row = QHBoxLayout()
        self._try_btn = QPushButton("试做")
        self._try_btn.setToolTip("用播放器试做草稿中的某一课时")
        self._try_btn.clicked.connect(self._on_try)
        row.addWidget(self._try_btn)
        self._diff_btn = QPushButton("与现有课程对比 (diff)")
        self._diff_btn.clicked.connect(self._on_diff)
        row.addWidget(self._diff_btn)
        self._fix_btn = QPushButton("AI 修复")
        self._fix_btn.setToolTip("让 AI 修复校验发现的问题（应用前可查看 diff）")
        self._fix_btn.clicked.connect(self._on_fix)
        row.addWidget(self._fix_btn)
        self._restore_btn = QPushButton("恢复上一版草稿")
        self._restore_btn.setToolTip("恢复生成/局部重生成前的草稿检查点")
        self._restore_btn.clicked.connect(self._on_restore_checkpoint)
        row.addWidget(self._restore_btn)
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
            pool = self._design_panel._controller.resource_pool
            cov = draft_coverage(draft, pool)
            cov_line = format_coverage_line(cov)
            self._coverage_label.setText(cov_line)
            self._coverage_label.setVisible(bool(cov_line))
            self._silent_validate(draft)
        else:
            self._hint_label.setText(_EMPTY_HINT)
            self._coverage_label.setText("")
            self._coverage_label.setVisible(False)
        for btn in (self._try_btn, self._diff_btn, self._fix_btn, self._import_btn):
            btn.setEnabled(has)
        can_restore = bool(
            getattr(self._design_panel._controller, "_draft_checkpoint", None)
        )
        self._restore_btn.setEnabled(can_restore)

    def _silent_validate(self, draft: dict) -> None:
        """Run validate when adapter is available; no dialogs."""
        if self.adapter is None:
            return
        try:
            problems = self.adapter.validate_section_json(
                draft, check_existing_ids=False
            )
        except TypeError:
            # Some adapters only accept section without kwargs.
            try:
                problems = self.adapter.validate_section_json(draft)
            except Exception:
                return
        except Exception:
            return
        self._preview.apply_validation(problems)

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

    def _confirm_apply_fix(self, original: dict, corrected: dict) -> bool:
        """Show structural diff; return True if user accepts the fix."""
        from src.widgets.diff_view import SectionDiffView

        dlg = SectionDiffView(
            original,
            corrected,
            self,
            confirm=True,
            title="AI 修复预览 — 确认后应用",
        )
        return dlg.exec() == QDialog.DialogCode.Accepted

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

        if dlg.exec() != QDialog.DialogCode.Accepted:
            return
        corrected = dlg.corrected_node()
        if corrected is None:
            return
        if not self._confirm_apply_fix(draft, corrected):
            return
        # Apply back into the single truth: the design page's JSON editor.
        self._design_panel._json_editor.set_json(corrected)
        self._design_panel._controller.set_draft(corrected)
        self.refresh()

    def _on_import(self) -> None:
        # Validation + emit lives on the design panel (single truth path).
        self._design_panel._on_import()

    def _on_restore_checkpoint(self) -> None:
        controller = self._design_panel._controller
        if not controller.restore_draft_checkpoint():
            QMessageBox.information(self, "恢复草稿", "没有可恢复的上一版草稿。")
            return
        # Push restored draft into the editor (controller only holds the model).
        if controller.draft is not None:
            self._design_panel._json_editor.set_json(controller.draft)
        self.refresh()

    def _on_regenerate_requested(self, kind: str, node_id: str) -> None:
        controller = self._design_panel._controller
        if controller.is_busy:
            QMessageBox.information(self, "局部重生成", "当前有任务进行中，请稍候。")
            return
        label = "课时" if kind == "lesson" else "单元"
        reply = QMessageBox.question(
            self,
            "局部重生成",
            f"用 AI 重写该{label}（{node_id}）？生成前会自动保存当前草稿以便恢复。",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
            QMessageBox.StandardButton.Yes,
        )
        if reply != QMessageBox.StandardButton.Yes:
            return
        if kind == "lesson":
            controller.regenerate_lesson(node_id)
        else:
            controller.regenerate_unit(node_id)
