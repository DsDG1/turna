"""Dialog for AI-assisted correction of a course node.
"""
from __future__ import annotations

import json
from typing import Any

from PySide6.QtCore import Qt, QPoint
from PySide6.QtGui import QColor
from PySide6.QtWidgets import (
    QDialog,
    QDialogButtonBox,
    QHBoxLayout,
    QLabel,
    QPlainTextEdit,
    QProgressBar,
    QPushButton,
    QVBoxLayout,
    QWidget,
    QListWidget,
    QListWidgetItem,
    QSplitter,
    QStackedWidget,
    QLineEdit,
    QTreeWidget,
    QTreeWidgetItem,
    QMessageBox,
)

from src.backend.ai_fixer import build_correction_prompt
from src.backend.ai_generator import request_correction
from src.dialogs.ai_error_analyzer import AiErrorAnalyzerDialog, offer_ai_analysis
from src.dialogs.ai_generator_dialog import AiRequestWorker
from src.infrastructure.telemetry import telemetry
from src.theme import current_palette


class AiFixDialog(QDialog):
    """Run AI correction on a single course node.

    On success, ``corrected_node()`` returns the dict returned by the model.
    The caller is responsible for validating and applying it through the undo
    stack.
    """

    def __init__(
        self,
        problems: list[dict[str, Any]],
        node_json: dict[str, Any],
        course_context: dict[str, Any],
        config,
        parent=None,
        *,
        initial_hint: str | None = None,
        window_title: str | None = None,
    ) -> None:
        super().__init__(parent)
        self.setWindowTitle(window_title or "AI 自动修正")
        self.resize(960, 640)
        self._problems = problems
        self._node_json = node_json
        self._course_context = course_context
        self._config = config
        self._corrected: dict[str, Any] | None = None
        self._worker: AiRequestWorker | None = None
        self._last_error_message: str = ""
        self._initial_hint = (initial_hint or "").strip()
        self._build_ui()
        if self._initial_hint:
            self.fix_hint_edit.setText(self._initial_hint)
        self._run()

    def _build_ui(self) -> None:
        layout = QVBoxLayout(self)
        layout.setSpacing(12)
        layout.setContentsMargins(16, 16, 16, 16)

        # 1. Main Horizontal Splitter
        splitter = QSplitter(Qt.Orientation.Horizontal, self)

        # --- Left Column: Problem checklist
        left_w = QWidget()
        left_lay = QVBoxLayout(left_w)
        left_lay.setContentsMargins(0, 0, 4, 0)
        left_lay.addWidget(QLabel("<b>选择要修复的校验问题：</b>"))

        self.problems_list = QListWidget()
        for p in self._problems:
            level = p.get("level", "error")
            path = p.get("path", "")
            message = p.get("message", "")
            item = QListWidgetItem(f"[{level.upper()}] {path}: {message}")
            item.setFlags(item.flags() | Qt.ItemFlag.ItemIsUserCheckable)
            item.setCheckState(Qt.CheckState.Checked)
            item.setData(Qt.ItemDataRole.UserRole, p)
            self.problems_list.addItem(item)
        left_lay.addWidget(self.problems_list, 1)
        splitter.addWidget(left_w)

        # --- Right Column: Stacked results/details
        self.right_stack = QStackedWidget()

        # Page 0: Working / Progress
        page_working = QWidget()
        work_lay = QVBoxLayout(page_working)
        self.status_label = QLabel("正在请求 AI 自动修正课程节点...")
        self.status_label.setWordWrap(True)
        self.progress = QProgressBar()
        self.progress.setRange(0, 0)
        work_lay.addStretch()
        work_lay.addWidget(self.status_label)
        work_lay.addWidget(self.progress)
        work_lay.addStretch()
        self.right_stack.addWidget(page_working)

        # Page 1: Success / Embedded Diff
        self.page_success = QWidget()
        self.success_lay = QVBoxLayout(self.page_success)
        self.success_lay.setContentsMargins(0, 0, 0, 0)
        self.success_lay.addWidget(QLabel("<b>修正已就绪。对比结果如下：</b>"))
        
        self.preview_container = QWidget()
        self.preview_lay = QVBoxLayout(self.preview_container)
        self.preview_lay.setContentsMargins(0, 0, 0, 0)
        self.success_lay.addWidget(self.preview_container, 1)
        self.right_stack.addWidget(self.page_success)

        # Page 2: Error
        page_error = QWidget()
        err_lay = QVBoxLayout(page_error)
        err_lay.addWidget(QLabel("<b>修正失败原因：</b>"))
        self.error_label = QLabel()
        self.error_label.setWordWrap(True)
        self.error_label.setStyleSheet(f"color: {current_palette()['error']}; font-weight: bold;")
        err_lay.addWidget(self.error_label)

        self.analyzer_btn = QPushButton("诊断错误原因...")
        self.analyzer_btn.clicked.connect(self._on_diagnose_error)
        err_lay.addWidget(self.analyzer_btn)
        err_lay.addStretch()
        self.right_stack.addWidget(page_error)

        splitter.addWidget(self.right_stack)
        layout.addWidget(splitter, 1)

        # Set splitter proportions (1 left : 2 right)
        splitter.setStretchFactor(0, 1)
        splitter.setStretchFactor(1, 2)

        # 2. Bottom custom instruction field
        bottom_box = QHBoxLayout()
        bottom_box.setSpacing(8)
        bottom_box.addWidget(QLabel("修正指示线索 (可选)："))
        self.fix_hint_edit = QLineEdit()
        self.fix_hint_edit.setPlaceholderText("给 AI 提供指导，如：‘忽略 wordId w-2，把翻译改为早安’")
        self.fix_hint_edit.returnPressed.connect(self._run)
        bottom_box.addWidget(self.fix_hint_edit, 1)

        self.retry_btn = QPushButton("重新修正 ▶")
        self.retry_btn.clicked.connect(self._run)
        bottom_box.addWidget(self.retry_btn)
        layout.addLayout(bottom_box)

        # 3. Action Buttons
        self._button_box = QDialogButtonBox(
            QDialogButtonBox.StandardButton.Apply
            | QDialogButtonBox.StandardButton.Cancel
        )
        self._button_box.button(QDialogButtonBox.StandardButton.Apply).setText("应用")
        self._button_box.button(QDialogButtonBox.StandardButton.Apply).setEnabled(False)
        self._button_box.button(QDialogButtonBox.StandardButton.Cancel).setText("放弃")
        self._button_box.clicked.connect(self._on_button_clicked)
        layout.addWidget(self._button_box)

    def _run(self) -> None:
        if self._worker is not None and self._worker.isRunning():
            self._worker.cancel()

        # Gather checked problems
        checked_problems = []
        for i in range(self.problems_list.count()):
            item = self.problems_list.item(i)
            if item.checkState() == Qt.CheckState.Checked:
                checked_problems.append(item.data(Qt.ItemDataRole.UserRole))

        if not checked_problems:
            QMessageBox.warning(self, "没有选择问题", "请至少勾选一个需要修正的问题。")
            return

        user_hint = self.fix_hint_edit.text().strip()
        prompt = build_correction_prompt(
            checked_problems, self._node_json, self._course_context, user_hint=user_hint
        )

        # Update Visuals to Busy
        self._corrected = None
        self.status_label.setText("正在请求 AI 自动修正课程节点...")
        self.right_stack.setCurrentIndex(0)
        self.progress.setVisible(True)
        self.retry_btn.setEnabled(False)
        self._button_box.button(QDialogButtonBox.StandardButton.Apply).setEnabled(False)

        telemetry.record_event(
            "ai.fix.start",
            payload={"node_kind": self._course_context.get("node_kind", "")},
        )
        kwargs = self._ai_generation_kwargs()
        worker = AiRequestWorker(
            request_correction,
            self._config,
            prompt,
            **kwargs,
        )
        self._worker = worker
        # Identity guard: a cancelled worker may still emit result/error before
        # terminating; ignore signals from any worker that is no longer current.
        worker.result_ready.connect(lambda r, w=worker: self._on_result(w, r))
        worker.error_occurred.connect(lambda m, w=worker: self._on_error(w, m))
        worker.completed.connect(lambda w=worker: self._on_completed(w))
        worker.start()

    def _ai_generation_kwargs(self) -> dict[str, Any]:
        """Read timeout and temperature from central Settings."""
        from src.app import current_settings

        try:
            s = current_settings()
            return {
                "timeout": float(getattr(s, "ai_timeout", 120.0)),
                "temperature": float(getattr(s, "ai_temperature", 0.2)),
            }
        except Exception:
            return {"timeout": 120.0, "temperature": 0.2}

    def _on_result(self, worker: AiRequestWorker, result: object) -> None:
        if worker is not self._worker:
            return  # stale signal from a superseded (cancelled) worker
        if isinstance(result, dict):
            self._corrected = result

            # Clear old preview widgets
            for i in reversed(range(self.preview_lay.count())):
                w = self.preview_lay.itemAt(i).widget()
                if w is not None:
                    w.deleteLater()

            # Render Diff / side-by-side preview inline
            kind = self._course_context.get("node_kind", "section")
            if kind == "section":
                from src.widgets.diff_view import _pal, _CATEGORY_LABELS
                from src.backend.ai_generator import full_section_diff

                diff = full_section_diff(self._node_json, self._corrected)
                any_change = any(
                    diff[cat][k]
                    for cat in diff
                    for k in ("added", "removed", "changed")
                )
                if not any_change:
                    self.preview_lay.addWidget(QLabel("✓ 无结构差异（仅内容可能微调）。"))
                else:
                    pal = _pal()
                    added_c = QColor(pal.get("success", "#27AE60"))
                    removed_c = QColor(pal.get("error", "#E74C3C"))
                    changed_c = QColor(pal.get("warning", "#FF9F43"))

                    hint = QLabel("绿=新增  红=删除  黄=修改")
                    hint.setStyleSheet(f"color: {pal.get('text_secondary', '#9CA3AF')}; font-size: 11px;")
                    self.preview_lay.addWidget(hint)

                    tree = QTreeWidget()
                    tree.setHeaderHidden(True)
                    for category, kinds in diff.items():
                        total = len(kinds["added"]) + len(kinds["removed"]) + len(kinds["changed"])
                        if total == 0:
                            continue
                        cat_node = QTreeWidgetItem([f"{_CATEGORY_LABELS.get(category, category)} ({total})"])
                        tree.addTopLevelItem(cat_node)
                        for label, items, color, prefix in (
                            ("新增", kinds["added"], added_c, "+"),
                            ("删除", kinds["removed"], removed_c, "-"),
                            ("修改", kinds["changed"], changed_c, "~"),
                        ):
                            if not items:
                                continue
                            kind_node = QTreeWidgetItem([f"{label} ({len(items)})"])
                            kind_node.setForeground(0, color)
                            cat_node.addChild(kind_node)
                            for item_id in items:
                                leaf = QTreeWidgetItem([f"{prefix} {item_id}"])
                                leaf.setForeground(0, color)
                                kind_node.addChild(leaf)
                        cat_node.setExpanded(True)
                    self.preview_lay.addWidget(tree, 1)
            else:
                # Side-by-side JSON comparison
                container = QWidget()
                hb = QHBoxLayout(container)
                hb.setContentsMargins(0, 0, 0, 0)

                left_box = QVBoxLayout()
                left_box.addWidget(QLabel("修正前 (Original)："))
                before = QPlainTextEdit()
                before.setReadOnly(True)
                before.setPlainText(json.dumps(self._node_json, ensure_ascii=False, indent=2))
                left_box.addWidget(before)
                hb.addLayout(left_box)

                right_box = QVBoxLayout()
                right_box.addWidget(QLabel("修正后 (Corrected)："))
                after = QPlainTextEdit()
                after.setReadOnly(True)
                after.setPlainText(json.dumps(self._corrected, ensure_ascii=False, indent=2))
                right_box.addWidget(after)
                hb.addLayout(right_box)

                self.preview_lay.addWidget(container, 1)

            self.right_stack.setCurrentIndex(1)
            self._button_box.button(QDialogButtonBox.StandardButton.Apply).setEnabled(True)
            telemetry.record_event(
                "ai.fix.done",
                payload={"node_kind": self._course_context.get("node_kind", "")},
            )
        else:
            self._on_error(worker, "AI 返回了未知格式的结果。")

    def _on_error(self, worker: AiRequestWorker, message: str) -> None:
        if worker is not self._worker:
            return  # stale signal from a superseded (cancelled) worker
        self._last_error_message = message
        self.error_label.setText(message)
        self.right_stack.setCurrentIndex(2)
        telemetry.record_event(
            "ai.fix.error",
            payload={
                "node_kind": self._course_context.get("node_kind", ""),
                "error": message,
            },
        )

    def _on_diagnose_error(self) -> None:
        if self._last_error_message:
            if offer_ai_analysis(self, "修正失败", self._last_error_message):
                AiErrorAnalyzerDialog.analyze_exception(
                    self,
                    self._last_error_message,
                    context={
                        "action": "ai.fix",
                        "node_kind": self._course_context.get("node_kind", ""),
                    },
                ).exec()

    def _on_completed(self, worker: AiRequestWorker) -> None:
        if worker is not self._worker:
            return  # stale signal from a superseded (cancelled) worker
        self.progress.setVisible(False)
        self.retry_btn.setEnabled(True)
        self._worker = None

    def _on_button_clicked(self, button: QPushButton) -> None:
        role = self._button_box.buttonRole(button)
        if role == QDialogButtonBox.ButtonRole.ApplyRole:
            self.accept()
        elif role == QDialogButtonBox.ButtonRole.RejectRole:
            self.reject()

    def corrected_node(self) -> dict[str, Any] | None:
        return self._corrected

    def closeEvent(self, event) -> None:  # noqa: N802
        if self._worker is not None and self._worker.isRunning():
            self._worker.cancel()
        super().closeEvent(event)
