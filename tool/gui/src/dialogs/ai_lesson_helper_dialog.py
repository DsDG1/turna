"""Lightweight AI helper dialog for the teacher view.

Operates on a single lesson or a single item: the teacher types an instruction
(e.g. "make this easier", "add 3 more exercises") and the dialog calls the
LLM in the background. The result is returned to the caller, which applies it
through the undo stack.
"""
from __future__ import annotations

import time
from typing import Any

from PySide6.QtCore import QSize
from PySide6.QtWidgets import (
    QDialog,
    QDialogButtonBox,
    QHBoxLayout,
    QLabel,
    QMessageBox,
    QPlainTextEdit,
    QProgressBar,
    QPushButton,
    QTextBrowser,
    QVBoxLayout,
    QWidget,
)

from src.app import current_ai_config, current_settings
from src.backend.ai_generator import (
    AiApiConfig,
    request_item_transform,
    request_lesson_transform,
)
from src.backend.course_adapter import CourseAdapter
from src.dialogs.ai_error_analyzer import AiErrorAnalyzerDialog, offer_ai_analysis
from src.dialogs.ai_generator_dialog import AiRequestWorker
from src.infrastructure.telemetry import telemetry


class AiLessonHelperDialog(QDialog):
    """AI rewrite/generate helper for a single lesson or item.

    Call ``result()`` after the dialog is accepted to get the transformed
    lesson dict (mode == "lesson") or item dict (mode == "item").
    """

    def __init__(
        self,
        adapter: CourseAdapter,
        target: dict[str, Any],
        mode: str,
        parent: QWidget | None = None,
    ) -> None:
        super().__init__(parent)
        self.adapter = adapter
        self.target = target
        self.mode = mode
        if mode == "lesson":
            self.setWindowTitle("AI 改写课程")
        else:
            self.setWindowTitle("AI 改写题目")
        self.resize(640, 520)
        self.setMinimumSize(QSize(520, 400))

        # API config is managed centrally in the Settings panel.
        self._config = current_ai_config()
        self._result: dict[str, Any] | None = None
        self._worker: AiRequestWorker | None = None

        self._build_ui()

    def _build_ui(self) -> None:
        layout = QVBoxLayout(self)
        layout.setSpacing(12)
        layout.setContentsMargins(16, 16, 16, 16)

        layout.addWidget(QLabel("<b>你想让 AI 做什么？</b>"))

        self.instruction_edit = QPlainTextEdit()
        self.instruction_edit.setPlaceholderText(
            "例如：生成 3 道相似练习题；降低难度；把选择题改成填空题……"
        )
        self.instruction_edit.setMinimumHeight(80)
        layout.addWidget(self.instruction_edit)

        chips = QWidget()
        chips_layout = QHBoxLayout(chips)
        chips_layout.setContentsMargins(0, 0, 0, 0)
        chips_layout.setSpacing(8)
        for text in (
            "生成 3 道练习题",
            "降低难度",
            "增加干扰项",
            "改成听力题型",
            "润色题干",
        ):
            btn = QPushButton(text)
            btn.setFlat(True)
            btn.clicked.connect(lambda _c=False, t=text: self._append_instruction(t))
            chips_layout.addWidget(btn)
        chips_layout.addStretch()
        layout.addWidget(chips)

        self.api_hint = QLabel("AI 配置请在工具栏「设置」中管理。API Key 仅在当前会话内存中保留。")
        self.api_hint.setObjectName("hintLabel")
        layout.addWidget(self.api_hint)

        self.status_label = QLabel("输入指令后点击「开始生成」")
        self.status_label.setWordWrap(True)
        layout.addWidget(self.status_label)

        self.progress = QProgressBar()
        self.progress.setRange(0, 0)
        self.progress.setVisible(False)
        layout.addWidget(self.progress)

        self.preview = QTextBrowser()
        self.preview.setVisible(False)
        self.preview.setMaximumHeight(160)
        layout.addWidget(self.preview)

        self._button_box = QDialogButtonBox(
            QDialogButtonBox.StandardButton.Apply
            | QDialogButtonBox.StandardButton.Cancel
        )
        self._button_box.button(QDialogButtonBox.StandardButton.Apply).setText("应用")
        self._button_box.button(QDialogButtonBox.StandardButton.Apply).setEnabled(False)
        self._button_box.button(QDialogButtonBox.StandardButton.Cancel).setText("关闭")
        self._button_box.clicked.connect(self._on_button_clicked)
        layout.addWidget(self._button_box)

        self.run_btn = QPushButton("开始生成")
        self.run_btn.setDefault(True)
        self.run_btn.clicked.connect(self._on_run)
        layout.addWidget(self.run_btn)

    def _append_instruction(self, text: str) -> None:
        current = self.instruction_edit.toPlainText().strip()
        if current:
            self.instruction_edit.setPlainText(f"{current}；{text}")
        else:
            self.instruction_edit.setPlainText(text)

    def _on_button_clicked(self, button: QPushButton) -> None:
        role = self._button_box.buttonRole(button)
        if role == QDialogButtonBox.ButtonRole.ApplyRole and self._result is not None:
            self.accept()
        elif role == QDialogButtonBox.ButtonRole.RejectRole:
            if self._worker is not None and self._worker.isRunning():
                self._cancel_if_running()
            else:
                self.reject()

    def _cancel_if_running(self) -> None:
        # Cancel only; the worker keep-alive registry keeps the thread alive
        # until it finishes (see worker.py), so no blocking wait is needed.
        if self._worker is not None and self._worker.isRunning():
            self._worker.cancel()

    def _set_running_ui(self, running: bool) -> None:
        cancel_btn = self._button_box.button(QDialogButtonBox.StandardButton.Cancel)
        if running:
            cancel_btn.setText("取消")
            self.run_btn.setEnabled(False)
            self.run_btn.setText("生成中…")
            self.progress.setVisible(True)
        else:
            cancel_btn.setText("关闭")
            self.run_btn.setEnabled(True)
            self.run_btn.setText("重新生成")
            self.progress.setVisible(False)

    def _on_run(self) -> None:
        instruction = self.instruction_edit.toPlainText().strip()
        if not instruction:
            QMessageBox.warning(self, "指令为空", "请输入你想让 AI 执行的指令。")
            return
        if not self._config.is_complete:
            QMessageBox.warning(
                self,
                "配置不完整",
                "请先点击工具栏「设置」，在「AI 配置」中填写 Base URL、API Key 和 Model。",
            )
            return

        self._result = None
        self.preview.setVisible(False)
        self._button_box.button(QDialogButtonBox.StandardButton.Apply).setEnabled(False)
        self._set_running_ui(True)
        self.status_label.setText("正在请求 AI，请稍候…")
        self._request_start = time.perf_counter()
        telemetry.record_event("ai.helper.start", payload={"mode": self.mode})

        kwargs = self._ai_generation_kwargs()
        if self.mode == "lesson":
            self._worker = AiRequestWorker(
                request_lesson_transform,
                self._config,
                self.target,
                instruction,
                **kwargs,
            )
        else:
            vocab_ids = {w.get("id", "") for w in self.adapter.vocab}
            expression_ids = {e.get("id", "") for e in self.adapter.expressions}
            grammar_ids = {g.get("id", "") for g in self.adapter.grammar_points}
            self._worker = AiRequestWorker(
                request_item_transform,
                self._config,
                self.target,
                instruction,
                vocab_ids,
                expression_ids,
                grammar_ids,
                **kwargs,
            )

        self._worker.result_ready.connect(self._on_result)
        self._worker.error_occurred.connect(self._on_error)
        self._worker.completed.connect(self._on_completed)
        self._worker.start()

    def _ai_generation_kwargs(self) -> dict[str, Any]:
        """Read timeout and temperature from central Settings."""
        try:
            s = current_settings()
            return {
                "timeout": float(getattr(s, "ai_timeout", 120.0)),
                "temperature": float(getattr(s, "ai_temperature", 0.7)),
            }
        except Exception:
            return {"timeout": 120.0, "temperature": 0.7}

    def _on_result(self, result: object) -> None:
        duration_ms = (time.perf_counter() - getattr(self, "_request_start", time.perf_counter())) * 1000
        telemetry.record_duration(
            "ai.helper",
            duration_ms,
            payload={"mode": self.mode, "success": isinstance(result, dict)},
        )
        if isinstance(result, dict):
            self._result = result
            self.status_label.setText("生成成功，点击「应用」即可替换当前内容。")
            self.preview.setVisible(True)
            self.preview.setPlainText(
                "生成结果预览（仅显示顶层结构）：\n"
                + self._preview_text(result)
            )
            self._button_box.button(QDialogButtonBox.StandardButton.Apply).setEnabled(True)
        else:
            self._on_error("AI 返回了未知格式的结果。")

    def _on_error(self, message: str) -> None:
        duration_ms = (time.perf_counter() - getattr(self, "_request_start", time.perf_counter())) * 1000
        telemetry.record_duration(
            "ai.helper",
            duration_ms,
            payload={"mode": self.mode, "success": False, "error": message},
        )
        self.status_label.setText(f"<font color='#E74C3C'>生成失败：{message}</font>")
        if offer_ai_analysis(self, "生成失败", message):
            AiErrorAnalyzerDialog.analyze_exception(
                self,
                message,
                context={"action": "ai.helper", "mode": self.mode},
            ).exec()

    def _on_completed(self) -> None:
        self._set_running_ui(False)
        self._worker = None

    def _preview_text(self, result: dict[str, Any]) -> str:
        if self.mode == "lesson":
            subs = result.get("content", {}).get("subLessons", [])
            stages = result.get("content", {}).get("stages", [])
            phases = result.get("content", {}).get("listeningPhases", [])
            count = len(subs) + len(stages) + len(phases)
            return f"模板：{result.get('template', '')}\n包含 {count} 个主要节点"
        return f"题型：{result.get('runtimeType', '')}\n{result.get('prompt', result.get('sentence', ''))}"

    def result(self) -> dict[str, Any] | None:
        return self._result

    def config(self) -> AiApiConfig:
        return self._config

    def closeEvent(self, event) -> None:
        self._cancel_if_running()
        super().closeEvent(event)
