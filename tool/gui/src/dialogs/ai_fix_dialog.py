"""Dialog for AI-assisted correction of a course node.
"""
from __future__ import annotations

import json
from typing import Any

from PySide6.QtWidgets import (
    QDialog,
    QDialogButtonBox,
    QHBoxLayout,
    QLabel,
    QMessageBox,
    QPlainTextEdit,
    QProgressBar,
    QPushButton,
    QVBoxLayout,
)

from src.backend.ai_fixer import build_correction_prompt
from src.backend.ai_generator import request_correction
from src.dialogs.ai_error_analyzer import AiErrorAnalyzerDialog
from src.dialogs.ai_generator_dialog import AiRequestWorker
from src.infrastructure.telemetry import telemetry
from src.widgets.diff_view import SectionDiffView


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
    ) -> None:
        super().__init__(parent)
        self.setWindowTitle("AI 自动修正")
        self.resize(720, 560)
        self._problems = problems
        self._node_json = node_json
        self._course_context = course_context
        self._config = config
        self._corrected: dict[str, Any] | None = None
        self._worker: AiRequestWorker | None = None
        self._build_ui()
        self._run()

    def _build_ui(self) -> None:
        layout = QVBoxLayout(self)
        layout.setSpacing(12)
        layout.setContentsMargins(16, 16, 16, 16)

        self.status_label = QLabel("正在请求 AI 修正课程节点...")
        layout.addWidget(self.status_label)

        self.progress = QProgressBar()
        self.progress.setRange(0, 0)
        layout.addWidget(self.progress)

        self.detail = QPlainTextEdit()
        self.detail.setReadOnly(True)
        self.detail.setVisible(False)
        self.detail.setMaximumHeight(240)
        layout.addWidget(self.detail, 1)

        self.diff_btn = QPushButton("查看 diff")
        self.diff_btn.setToolTip("对比 AI 修正前后的结构差异")
        self.diff_btn.setVisible(False)
        self.diff_btn.clicked.connect(self._on_view_diff)

        self._button_box = QDialogButtonBox(
            QDialogButtonBox.StandardButton.Apply
            | QDialogButtonBox.StandardButton.Cancel
        )
        self._button_box.button(QDialogButtonBox.StandardButton.Apply).setText("应用")
        self._button_box.button(QDialogButtonBox.StandardButton.Apply).setEnabled(False)
        self._button_box.button(QDialogButtonBox.StandardButton.Cancel).setText("放弃")
        self._button_box.clicked.connect(self._on_button_clicked)

        btn_layout = QHBoxLayout()
        btn_layout.addWidget(self.diff_btn)
        btn_layout.addStretch()
        btn_layout.addWidget(self._button_box)
        layout.addLayout(btn_layout)

    def _run(self) -> None:
        prompt = build_correction_prompt(
            self._problems, self._node_json, self._course_context
        )
        telemetry.record_event(
            "ai.fix.start",
            payload={"node_kind": self._course_context.get("node_kind", "")},
        )
        kwargs = self._ai_generation_kwargs()
        self._worker = AiRequestWorker(
            request_correction,
            self._config,
            prompt,
            **kwargs,
        )
        self._worker.result_ready.connect(self._on_result)
        self._worker.error_occurred.connect(self._on_error)
        self._worker.completed.connect(self._on_completed)
        self._worker.start()

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

    def _on_result(self, result: object) -> None:
        if isinstance(result, dict):
            self._corrected = result
            self.status_label.setText("修正完成，请查看 diff 后决定是否应用。")
            self.detail.setVisible(True)
            self.detail.setPlainText(
                "AI 返回的修正结果已就绪。点击「查看 diff」可对比改动。"
            )
            self.diff_btn.setVisible(True)
            self._button_box.button(QDialogButtonBox.StandardButton.Apply).setEnabled(True)
            telemetry.record_event(
                "ai.fix.done",
                payload={"node_kind": self._course_context.get("node_kind", "")},
            )
        else:
            self._on_error("AI 返回了未知格式的结果。")

    def _on_error(self, message: str) -> None:
        self.status_label.setText(f"<font color='#E74C3C'>修正失败：{message}</font>")
        telemetry.record_event(
            "ai.fix.error",
            payload={
                "node_kind": self._course_context.get("node_kind", ""),
                "error": message,
            },
        )
        msg = QMessageBox(self)
        msg.setIcon(QMessageBox.Icon.Critical)
        msg.setWindowTitle("修正失败")
        msg.setText(message)
        msg.addButton("确定", QMessageBox.ButtonRole.AcceptRole)
        analyze_btn = msg.addButton("AI 分析原因", QMessageBox.ButtonRole.ActionRole)
        msg.exec()
        if msg.clickedButton() == analyze_btn:
            AiErrorAnalyzerDialog.analyze_exception(
                self,
                message,
                context={
                    "action": "ai.fix",
                    "node_kind": self._course_context.get("node_kind", ""),
                },
            ).exec()

    def _on_completed(self) -> None:
        self.progress.setVisible(False)
        self._worker = None

    def _on_button_clicked(self, button: QPushButton) -> None:
        role = self._button_box.buttonRole(button)
        if role == QDialogButtonBox.ButtonRole.ApplyRole:
            self.accept()
        elif role == QDialogButtonBox.ButtonRole.RejectRole:
            self.reject()

    def _on_view_diff(self) -> None:
        if self._corrected is None:
            return
        kind = self._course_context.get("node_kind", "section")
        if kind == "section":
            SectionDiffView(self._node_json, self._corrected, parent=self).exec()
        else:
            dlg = QDialog(self)
            dlg.setWindowTitle("修正前后对比")
            dlg.resize(900, 600)
            layout = QHBoxLayout(dlg)
            layout.setSpacing(8)
            before = QPlainTextEdit()
            before.setReadOnly(True)
            before.setPlainText(
                json.dumps(self._node_json, ensure_ascii=False, indent=2)
            )
            after = QPlainTextEdit()
            after.setReadOnly(True)
            after.setPlainText(
                json.dumps(self._corrected, ensure_ascii=False, indent=2)
            )
            layout.addWidget(before)
            layout.addWidget(after)
            dlg.exec()

    def corrected_node(self) -> dict[str, Any] | None:
        return self._corrected

    def closeEvent(self, event) -> None:  # noqa: N802
        if self._worker is not None and self._worker.isRunning():
            self._worker.cancel()
            self._worker.wait(2000)
        super().closeEvent(event)
