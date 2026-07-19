"""Dialog for one-click AI analysis of an error.

The dialog shows the traceback, reads recent telemetry log lines, and sends a
concise prompt to the configured OpenAI-compatible endpoint. The model returns a
Chinese explanation of the likely cause and suggested next steps.
"""
from __future__ import annotations

from typing import Any

from PySide6.QtWidgets import (
    QDialog,
    QDialogButtonBox,
    QLabel,
    QMessageBox,
    QPlainTextEdit,
    QProgressBar,
    QPushButton,
    QTextBrowser,
    QVBoxLayout,
    QWidget,
)

from src.app import current_ai_config
from src.backend.ai_generator import request_chat
from src.dialogs.ai_generator_dialog import AiRequestWorker
from src.infrastructure.telemetry import telemetry


def offer_ai_analysis(
    parent,
    title: str,
    message: str,
    *,
    informative_text: str | None = None,
    default_to_analyze: bool = False,
) -> bool:
    """Show a critical dialog with 确定 + 'AI 分析原因'; return True if analyze was clicked."""
    msg = QMessageBox(parent)
    msg.setIcon(QMessageBox.Icon.Critical)
    msg.setWindowTitle(title)
    msg.setText(message)
    if informative_text:
        msg.setInformativeText(informative_text)
    msg.addButton("确定", QMessageBox.ButtonRole.AcceptRole)
    analyze_btn = msg.addButton("AI 分析原因", QMessageBox.ButtonRole.ActionRole)
    if default_to_analyze:
        msg.setDefaultButton(analyze_btn)
    msg.exec()
    return msg.clickedButton() is analyze_btn


class AiErrorAnalyzerDialog(QDialog):
    """Analyze an exception with an LLM.

    ``config`` is the current AI API config (possibly unverified). If it is
    incomplete, the dialog prompts the user to configure and test the endpoint
    before analysis.
    """

    def __init__(
        self,
        traceback_text: str,
        context: dict[str, Any] | None = None,
        parent: QWidget | None = None,
    ) -> None:
        super().__init__(parent)
        self.setWindowTitle("AI 错误分析")
        self.resize(760, 620)
        self._traceback = traceback_text
        self._context = context or {}
        # API config is managed centrally in the Settings panel.
        self._config = current_ai_config()
        self._worker: AiRequestWorker | None = None
        self._build_ui()

    @classmethod
    def analyze_exception(
        cls,
        parent: QWidget | None,
        exc: BaseException | str,
        context: dict[str, Any] | None = None,
    ) -> "AiErrorAnalyzerDialog":
        """Factory that builds the dialog from an exception or message."""
        import traceback

        if isinstance(exc, str):
            tb_text = exc
        else:
            tb_text = "".join(traceback.format_exception(type(exc), exc, exc.__traceback__))
        dlg = cls(tb_text, context=context, parent=parent)
        return dlg

    def _build_ui(self) -> None:
        layout = QVBoxLayout(self)
        layout.setSpacing(12)
        layout.setContentsMargins(16, 16, 16, 16)

        layout.addWidget(QLabel("<b>错误堆栈</b>"))
        self.trace_edit = QPlainTextEdit(self._traceback)
        self.trace_edit.setReadOnly(True)
        self.trace_edit.setMaximumHeight(180)
        self.trace_edit.setStyleSheet("font-family: Consolas, monospace; font-size: 12px;")
        layout.addWidget(self.trace_edit)

        hint = QLabel(
            "点击「AI 分析原因」将把堆栈和最近日志发送到模型端。"
            "日志中可能包含文件路径，请确认后再继续。"
        )
        hint.setWordWrap(True)
        hint.setStyleSheet("color: #9CA3AF; font-size: 11px;")
        layout.addWidget(hint)

        self.api_status = QLabel(self._api_status_text())
        self.api_status.setStyleSheet("font-size: 12px;")
        layout.addWidget(self.api_status)

        self.api_hint = QLabel("AI 配置请在工具栏「设置」中管理。")
        self.api_hint.setObjectName("hintLabel")
        layout.addWidget(self.api_hint)

        self.analyze_btn = QPushButton("AI 分析原因")
        self.analyze_btn.setDefault(True)
        self.analyze_btn.setStyleSheet(
            "QPushButton { background-color: #145A64; color: #FFFFFF; border: none; border-radius: 6px; padding: 6px 12px; }"
            "QPushButton:hover { background-color: #1F727E; }"
        )
        self.analyze_btn.clicked.connect(self._on_analyze)
        layout.addWidget(self.analyze_btn)

        self.progress = QProgressBar()
        self.progress.setRange(0, 0)
        self.progress.setVisible(False)
        layout.addWidget(self.progress)

        layout.addWidget(QLabel("<b>分析结果</b>"))
        self.result_view = QTextBrowser()
        self.result_view.setStyleSheet(
            "QTextBrowser { border: 1px solid #2C313C; background-color: #1F232C; padding: 10px; }"
        )
        self.result_view.setPlaceholderText("分析结果将显示在这里...")
        layout.addWidget(self.result_view, 1)

        buttons = QDialogButtonBox(QDialogButtonBox.StandardButton.Close)
        buttons.rejected.connect(self.reject)
        layout.addWidget(buttons)

    def _api_status_text(self) -> str:
        if self._config.is_complete:
            return f"<font color='#27AE60'>已配置: {self._config.model}</font>"
        return "<font color='#E74C3C'>未配置 AI API，需先设置</font>"

    def _on_analyze(self) -> None:
        if not self._config.is_complete:
            QMessageBox.warning(
                self,
                "未配置 API",
                "请先点击工具栏「设置」，在「AI 配置」中填写 Base URL、API Key 和 Model。",
            )
            return

        self.analyze_btn.setEnabled(False)
        self.progress.setVisible(True)
        self.result_view.clear()

        prompt = self._build_prompt()
        self._worker = AiRequestWorker(
            request_chat,
            self._config,
            messages=[
                {
                    "role": "system",
                    "content": (
                        "你是一位资深的 Python/Qt 桌面应用开发者，正在帮用户分析课程编辑器崩溃原因。"
                        "请用中文给出：1) 最可能的原因；2) 修复步骤；3) 用户可以立即尝试的操作。"
                        "保持简洁，不超过 400 字。"
                    ),
                },
                {"role": "user", "content": prompt},
            ],
            temperature=0.2,
        )
        self._worker.result_ready.connect(self._on_result)
        self._worker.error_occurred.connect(self._on_error)
        self._worker.completed.connect(self._on_completed)
        self._worker.start()

    def _build_prompt(self) -> str:
        lines = ["应用程序发生未捕获异常，请分析原因。"]
        lines.append("")
        lines.append("## 当前操作上下文")
        for key, value in self._context.items():
            lines.append(f"- {key}: {value}")
        lines.append("")
        lines.append("## 异常堆栈")
        lines.append(self._traceback)
        lines.append("")
        recent = telemetry.recent_lines(80)
        if recent:
            lines.append("## 最近 telemetry 日志")
            lines.extend(line.rstrip("\n") for line in recent)
        return "\n".join(lines)

    def _on_result(self, body: object) -> None:
        try:
            if isinstance(body, dict):
                choices = body.get("choices") or []
                if choices and isinstance(choices[0], dict):
                    message = choices[0].get("message", {})
                    text = message.get("content", "") if isinstance(message, dict) else ""
                else:
                    text = str(body)
            else:
                text = str(body)
        except Exception as exc:
            text = f"解析模型返回失败: {exc}"
        self.result_view.setPlainText(text)

    def _on_error(self, message: str) -> None:
        self.result_view.setPlainText(f"分析失败：{message}")
        QMessageBox.critical(self, "分析失败", message)

    def _on_completed(self) -> None:
        self.progress.setVisible(False)
        self.analyze_btn.setEnabled(True)
        self._worker = None

    def closeEvent(self, event) -> None:  # noqa: N802
        # Cancel only; the worker keep-alive registry keeps the thread alive
        # until it finishes (see worker.py), so no blocking wait is needed.
        if self._worker is not None and self._worker.isRunning():
            self._worker.cancel()
        super().closeEvent(event)
