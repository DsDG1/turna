"""Dialog for generating a course section with an AI (OpenAI-compatible) API.

Supports two modes:
- Normal mode: legacy form-based generation, JSON editor, then import.
- Wish mode: conversational alignment with multi-turn chat, file attachments
  (images, PDF, Word, text), and a final "I think it's ready" button that
  generates the course. After generation, the AI explains the course in plain
  language before the user imports it.

Beta warning: this feature consumes a lot of tokens and is intended for models
that support ~1M token context windows. Results are for reference only and must
be reviewed by the author.

API key / base URL / model are held only in memory for the current GUI session
and are never written to disk. Uploaded files are copied to temporary files and
deleted when the dialog closes.
"""
from __future__ import annotations

import json
import shutil
import tempfile
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import re

from PySide6.QtCore import Qt, QThread, QSize, Signal
from PySide6.QtGui import QDragEnterEvent, QDropEvent
from PySide6.QtWidgets import (
    QCheckBox,
    QComboBox,
    QDialog,
    QDialogButtonBox,
    QFileDialog,
    QFormLayout,
    QGroupBox,
    QHBoxLayout,
    QInputDialog,
    QLabel,
    QLineEdit,
    QMessageBox,
    QPlainTextEdit,
    QProgressBar,
    QPushButton,
    QSpinBox,
    QTextBrowser,
    QTextEdit,
    QVBoxLayout,
    QWidget,
)

from src.backend.ai_generator import (
    AiApiConfig,
    AiCourseSpec,
    ChatMessage,
    apply_genre_to_spec,
    detect_genre_from_spec,
    explain_course,
    generate_edit,
    generate_from_chat,
    genre_to_template,
    request_alignment_reply,
    request_course,
)
from src.backend.ai_genre import genre_tags_in_text
from src.backend.attachment_extractor import extract_attachment


@dataclass
class _AttachmentRecord:
    temp_path: Path
    original_name: str
    content: dict[str, Any]


class AiRequestWorker(QThread):
    """Run a synchronous AI call in a background thread.

    ``target`` is any callable; ``*args``/``**kwargs`` are forwarded to it.
    The result or exception is delivered via Qt signals.
    """

    result_ready = Signal(object)
    error_occurred = Signal(str)
    completed = Signal()

    def __init__(self, target, *args, parent: QWidget | None = None, **kwargs) -> None:
        super().__init__(parent)
        self._target = target
        self._args = args
        self._kwargs = kwargs

    def run(self) -> None:
        try:
            result = self._target(*self._args, **self._kwargs)
        except Exception as exc:  # noqa: BLE001
            self.error_occurred.emit(str(exc))
        else:
            self.result_ready.emit(result)
        finally:
            self.completed.emit()


class _ApiConfigWorker(QThread):
    """Background worker to test an API config with a tiny request."""

    result_ready = Signal(bool, str)

    def __init__(self, config: AiApiConfig, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self._config = config

    def run(self) -> None:
        try:
            from src.backend.ai_generator import request_chat

            body = request_chat(
                self._config,
                messages=[
                    {
                        "role": "user",
                        "content": "ping",
                    }
                ],
                temperature=0.0,
                timeout=20.0,
            )
            choices = body.get("choices") or []
            ok = bool(choices)
            msg = "连接成功，模型可用。" if ok else "API 返回 choices 为空，请检查模型名。"
            self.result_ready.emit(ok, msg)
        except Exception as exc:  # noqa: BLE001
            self.result_ready.emit(False, str(exc))


def _is_valid_http_url(url: str) -> bool:
    if not url:
        return False
    return bool(re.match(r"^https?://[^\s]+$", url, re.IGNORECASE))


class ApiConfigDialog(QDialog):
    """Small dialog to set API config (Base URL, Key, Model) with validation.

    The configuration can only be saved (accepted) after a connection test
    has passed for the current values. Editing any field invalidates the
    previous test result, forcing the user to re-test before saving.
    """

    def __init__(self, config: AiApiConfig, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.setWindowTitle("API 设置")
        self.resize(480, 300)
        self._config = config
        self._worker: _ApiConfigWorker | None = None
        self._tested_config: AiApiConfig | None = None
        self._build_ui()

    def _build_ui(self) -> None:
        layout = QVBoxLayout(self)
        layout.setSpacing(12)
        layout.setContentsMargins(16, 16, 16, 16)

        form = QFormLayout()
        self.base_url_edit = QLineEdit(self._config.base_url)
        self.base_url_edit.setPlaceholderText("https://api.deepseek.com")
        self.base_url_edit.textChanged.connect(self._on_field_changed)
        form.addRow("Base URL:", self.base_url_edit)

        self.api_key_edit = QLineEdit(self._config.api_key)
        self.api_key_edit.setEchoMode(QLineEdit.EchoMode.Password)
        self.api_key_edit.setPlaceholderText("sk-...")
        self.api_key_edit.textChanged.connect(self._on_field_changed)
        form.addRow("API Key:", self.api_key_edit)

        self.model_edit = QLineEdit(self._config.model)
        self.model_edit.setPlaceholderText("deepseek-v4-flash")
        self.model_edit.textChanged.connect(self._on_field_changed)
        form.addRow("Model:", self.model_edit)
        layout.addLayout(form)

        self.test_btn = QPushButton("测试连接")
        self.test_btn.clicked.connect(self._on_test_connection)
        layout.addWidget(self.test_btn)

        self.test_result_label = QLabel(
            '<font color="#9CA3AF">尚未测试，请先点击「测试连接」。</font>'
        )
        self.test_result_label.setWordWrap(True)
        self.test_result_label.setStyleSheet("font-size: 12px;")
        layout.addWidget(self.test_result_label)

        hint = QLabel(
            "默认使用 DeepSeek（https://api.deepseek.com，模型 deepseek-v4-flash）。"
            "也兼容 OpenAI / Moonshot / 本地 Ollama 等 OpenAI 兼容接口。"
            "密钥仅在内存中，关闭程序后不保留。必须测试连接通过后才能保存。"
        )
        hint.setWordWrap(True)
        hint.setStyleSheet("color: gray; font-size: 11px;")
        layout.addWidget(hint)

        buttons = QDialogButtonBox(
            QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel
        )
        buttons.accepted.connect(self._on_accept)
        buttons.rejected.connect(self.reject)
        layout.addWidget(buttons)
        self._update_test_btn_state()

    def _on_field_changed(self) -> None:
        """Any edit invalidates the last successful test result."""
        self._tested_config = None
        if not self.test_result_label.text().startswith(
            '<font color="#9CA3AF">测试中'
        ):
            self.test_result_label.setText(
                '<font color="#9CA3AF">配置已修改，请重新测试连接。</font>'
            )
        self._update_test_btn_state()

    def _current_fields_complete(self) -> bool:
        return (
            bool(self.base_url_edit.text().strip())
            and bool(self.api_key_edit.text().strip())
            and bool(self.model_edit.text().strip())
        )

    def _update_test_btn_state(self) -> None:
        self.test_btn.setEnabled(
            self._current_fields_complete() and self._worker is None
        )

    def _on_test_connection(self) -> None:
        config = self.config()
        if not _is_valid_http_url(config.base_url):
            self.test_result_label.setText(
                '<font color="#E74C3C">Base URL 必须以 http:// 或 https:// 开头。</font>'
            )
            return
        self.test_result_label.setText('<font color="#9CA3AF">测试中...</font>')
        self._worker = _ApiConfigWorker(config, self)
        self._worker.result_ready.connect(self._on_test_done)
        self._worker.start()
        self._update_test_btn_state()

    def _on_test_done(self, ok: bool, message: str) -> None:
        self._worker = None
        color = "#27AE60" if ok else "#E74C3C"
        self.test_result_label.setText(f"<font color='{color}'>{message}</font>")
        if ok:
            self._tested_config = self.config()
        else:
            self._tested_config = None
        self._update_test_btn_state()

    def _on_accept(self) -> None:
        config = self.config()
        if not _is_valid_http_url(config.base_url):
            QMessageBox.warning(self, "配置无效", "Base URL 必须以 http:// 或 https:// 开头。")
            return
        if not config.api_key:
            QMessageBox.warning(self, "配置无效", "API Key 不能为空。")
            return
        if not config.model:
            QMessageBox.warning(self, "配置无效", "Model 不能为空。")
            return
        if self._tested_config is None:
            QMessageBox.warning(
                self,
                "未测试连接",
                "请先点击「测试连接」并确认通过后，再保存配置。",
            )
            return
        if self._tested_config != config:
            QMessageBox.warning(
                self,
                "配置已修改",
                "配置在上次测试后被修改，请重新点击「测试连接」后再保存。",
            )
            return
        self.accept()

    def config(self) -> AiApiConfig:
        return AiApiConfig(
            base_url=self.base_url_edit.text().strip(),
            api_key=self.api_key_edit.text().strip(),
            model=self.model_edit.text().strip(),
        )


class AiGeneratorDialog(QDialog):
    """AI course generator dialog with normal and wish modes.

    On accept, ``section_json()`` returns the (possibly edited) section dict
    ready to be appended to ``adapter.sections`` and registered in the index.
    """

    def __init__(
        self,
        adapter,
        parent: QWidget | None = None,
        edit_mode: dict[str, Any] | None = None,
        initial_config: AiApiConfig | None = None,
    ) -> None:
        super().__init__(parent)
        self.adapter = adapter
        self._edit_mode = edit_mode
        if edit_mode is not None:
            self.setWindowTitle("AI 编辑（Beta）")
        else:
            self.setWindowTitle("AI 生成课程（Beta）")
        self.resize(1180, 860)
        self.setMinimumSize(QSize(900, 640))
        self.setAcceptDrops(True)
        self._config = (
            initial_config if initial_config is not None else AiApiConfig()
        )
        self._verified_config: AiApiConfig | None = None
        # Carry over a previously-verified config so the user doesn't re-test
        # every time the dialog is reopened from the main window.
        if initial_config is not None and initial_config.is_complete:
            # Only treat as verified if caller passes one already verified;
            # MainWindow keeps a separate verified flag and may set it after.
            pass
        self._generated: dict | None = None
        self._mode = "normal"

        self._messages: list[ChatMessage] = []
        self._attachments: list[_AttachmentRecord] = []
        self._draft_json: dict | None = None
        self._current_worker: AiRequestWorker | None = None

        self._build_ui()
        self._update_api_status()
        self._apply_edit_mode_ui()

    # --- UI construction -------------------------------------------------

    def _build_ui(self) -> None:
        root = QVBoxLayout(self)
        root.setSpacing(14)
        root.setContentsMargins(16, 16, 16, 16)

        root.addWidget(self._build_beta_banner())
        root.addWidget(self._build_header_bar())
        root.addWidget(self._build_spec_bar())

        self._stack = QVBoxLayout()
        self._stack.setSpacing(0)
        self._stack.setContentsMargins(0, 0, 0, 0)
        self._normal_panel = self._build_normal_panel()
        self._wish_panel = self._build_wish_panel()
        self._stack.addWidget(self._normal_panel)
        self._stack.addWidget(self._wish_panel)
        root.addLayout(self._stack, 1)

        buttons = QDialogButtonBox(
            QDialogButtonBox.StandardButton.Ok
            | QDialogButtonBox.StandardButton.Cancel
        )
        buttons.button(QDialogButtonBox.StandardButton.Ok).setText("导入到课程")
        buttons.accepted.connect(self._on_accept)
        buttons.rejected.connect(self.reject)
        self._button_box = buttons
        root.addWidget(buttons)

        self._update_mode_ui()

    def _build_beta_banner(self) -> QWidget:
        widget = QWidget()
        layout = QHBoxLayout(widget)
        layout.setContentsMargins(10, 8, 10, 8)
        layout.setSpacing(8)
        widget.setStyleSheet(
            "background-color: #664400; color: #FFD93D; border-radius: 6px;"
        )
        label = QLabel(
            "Beta：AI 生成结果仅供参考，请人工校验。本功能会消耗大量 token，"
            "且建议模型支持 1M 上下文窗口。"
        )
        label.setWordWrap(True)
        layout.addWidget(label)
        return widget

    def _build_header_bar(self) -> QWidget:
        widget = QWidget()
        layout = QHBoxLayout(widget)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(12)

        mode_label = QLabel("<b>生成模式</b>")
        layout.addWidget(mode_label)

        self.mode_combo = QComboBox()
        self.mode_combo.addItem("普通模式", "normal")
        self.mode_combo.addItem("许愿模式", "wish")
        self.mode_combo.currentIndexChanged.connect(self._on_mode_changed)
        layout.addWidget(self.mode_combo)

        layout.addStretch()

        self.api_btn = QPushButton("API 设置")
        self.api_btn.setToolTip("设置 Base URL / API Key / Model")
        self.api_btn.clicked.connect(self._on_api_settings)
        layout.addWidget(self.api_btn)

        self.api_status = QLabel("<font color='#E74C3C'>未配置</font>")
        self.api_status.setStyleSheet("font-size: 12px;")
        layout.addWidget(self.api_status)
        return widget

    def _build_spec_bar(self) -> QWidget:
        widget = QWidget()
        layout = QHBoxLayout(widget)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(12)

        form = QFormLayout()
        form.setContentsMargins(0, 0, 0, 0)
        form.setSpacing(6)

        self.language_edit = QLineEdit("Turkish")
        self.language_edit.setMaximumWidth(120)
        form.addRow("目标语言:", self.language_edit)

        self.source_language_edit = QLineEdit("Chinese")
        self.source_language_edit.setMaximumWidth(120)
        form.addRow("源语言:", self.source_language_edit)

        self.level_combo = QComboBox()
        for lvl in ("A1", "A2", "B1", "B2", "C1"):
            self.level_combo.addItem(lvl)
        form.addRow("等级:", self.level_combo)
        layout.addLayout(form)

        row = QHBoxLayout()
        row.setSpacing(8)
        self.unit_spin = QSpinBox()
        self.unit_spin.setRange(1, 5)
        self.unit_spin.setValue(1)
        row.addWidget(QLabel("单元数:"))
        row.addWidget(self.unit_spin)
        self.lessons_spin = QSpinBox()
        self.lessons_spin.setRange(1, 5)
        self.lessons_spin.setValue(3)
        row.addWidget(QLabel("课时:"))
        row.addWidget(self.lessons_spin)
        layout.addLayout(row)

        layout.addStretch()

        self.extra_edit = QLineEdit()
        self.extra_edit.setPlaceholderText("可选：额外指令")
        self.extra_edit.setMaximumWidth(220)
        layout.addWidget(QLabel("额外:"))
        layout.addWidget(self.extra_edit)
        return widget

    def _build_template_selector(self) -> QWidget:
        """Reusable widget with template combo + genre batch switch."""
        widget = QWidget()
        layout = QHBoxLayout(widget)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(8)

        self.template_combo = QComboBox()
        self.template_combo.addItem("混合", "mixed")
        self.template_combo.addItem("认识新词", "intro")
        self.template_combo.addItem("巩固练习", "practice")
        self.template_combo.addItem("复习", "review")
        self.template_combo.addItem("听力训练", "listening")
        self.template_combo.addItem("阅读理解", "reading")
        self.template_combo.addItem("综合测验", "mastery")
        self.template_combo.currentIndexChanged.connect(self._on_template_changed)
        layout.addWidget(QLabel("课程类型:"))
        layout.addWidget(self.template_combo)

        self.genre_switch = QCheckBox("启用 [genre] 多模板批量生成（Beta）")
        self.genre_switch.setChecked(False)
        self.genre_switch.setToolTip(
            "开启后，可在主题或额外指令中插入 [intro]、[listening] 等标签，"
            "让 AI 批量生成多种模板的课程。会显著增加 token 消耗。"
        )
        self.genre_switch.stateChanged.connect(self._on_genre_switch_changed)
        layout.addWidget(self.genre_switch)

        layout.addStretch()
        return widget

    def _build_normal_panel(self) -> QWidget:
        widget = QWidget()
        layout = QVBoxLayout(widget)
        layout.setSpacing(12)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.addWidget(self._build_template_selector())
        layout.addWidget(self._build_topic_row())
        layout.addWidget(self._build_result_group())
        return widget

    def _build_topic_row(self) -> QWidget:
        widget = QWidget()
        layout = QHBoxLayout(widget)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(8)

        self.topic_edit = QLineEdit()
        self.topic_edit.setPlaceholderText("例如：旅行词汇 [intro]")
        self.topic_edit.textChanged.connect(self._on_topic_text_changed)
        layout.addWidget(QLabel("主题:"))
        layout.addWidget(self.topic_edit, 1)

        self.generate_btn = QPushButton("生成课程")
        self.generate_btn.setToolTip("按主题和规格直接生成 JSON")
        self.generate_btn.clicked.connect(self._on_generate_normal)
        layout.addWidget(self.generate_btn)
        return widget

    def _build_result_group(self) -> QGroupBox:
        grp = QGroupBox("生成结果（可编辑 JSON）")
        layout = QVBoxLayout(grp)
        layout.setSpacing(8)
        self.json_edit = QPlainTextEdit()
        self.json_edit.setPlaceholderText("点击「生成课程」后，JSON 会显示在这里供你检查与修改。")
        self.json_edit.setStyleSheet("font-family: Consolas, monospace; font-size: 12px;")
        layout.addWidget(self.json_edit)

        row = QHBoxLayout()
        row.setSpacing(8)
        self.reset_btn = QPushButton("恢复 AI 原始输出")
        self.reset_btn.clicked.connect(self._on_reset)
        self.reset_btn.setEnabled(False)
        row.addWidget(self.reset_btn)
        self.validate_btn = QPushButton("校验 JSON")
        self.validate_btn.clicked.connect(self._on_validate_json)
        row.addWidget(self.validate_btn)
        row.addStretch()
        layout.addLayout(row)

        self.progress = QProgressBar()
        self.progress.setRange(0, 0)
        self.progress.setVisible(False)
        layout.addWidget(self.progress)
        return grp

    def _build_wish_panel(self) -> QWidget:
        widget = QWidget()
        layout = QVBoxLayout(widget)
        layout.setSpacing(12)
        layout.setContentsMargins(0, 0, 0, 0)

        hint = QLabel(
            "许愿模式：像聊天一样描述课程需求，把图片、PDF、Word 或文本文件直接拖入窗口作为参考。"
        )
        hint.setWordWrap(True)
        hint.setStyleSheet("color: #9CA3AF; font-size: 12px;")
        layout.addWidget(hint)

        layout.addWidget(self._build_template_selector())

        chat_container = QWidget()
        chat_container.setStyleSheet("background-color: #1A1D23; border: 1px solid #2C313C; border-radius: 8px;")
        chat_layout = QVBoxLayout(chat_container)
        chat_layout.setSpacing(0)
        chat_layout.setContentsMargins(0, 0, 0, 0)

        self.chat_view = QTextBrowser()
        self.chat_view.setPlaceholderText("对话记录会显示在这里...")
        self.chat_view.setStyleSheet(
            "QTextBrowser {"
            "  border: none;"
            "  background-color: #1A1D23;"
            "  font-family: system-ui, sans-serif;"
            "  font-size: 14px;"
            "  padding: 12px;"
            "}"
        )
        chat_layout.addWidget(self.chat_view)
        layout.addWidget(chat_container, 1)

        self.wish_progress = QProgressBar()
        self.wish_progress.setRange(0, 0)
        self.wish_progress.setVisible(False)
        layout.addWidget(self.wish_progress)

        self.explain_group = QGroupBox("AI 通俗解释")
        explain_layout = QVBoxLayout(self.explain_group)
        explain_layout.setContentsMargins(8, 8, 8, 8)
        explain_layout.setSpacing(4)
        self.explain_label = QTextBrowser()
        self.explain_label.setOpenExternalLinks(True)
        self.explain_label.setStyleSheet(
            "QTextBrowser {"
            "  border: none;"
            "  background-color: #1F232C;"
            "  color: #46D1BF;"
            "  font-family: system-ui, sans-serif;"
            "  font-size: 13px;"
            "  padding: 8px;"
            "}"
        )
        self.explain_label.setPlaceholderText("生成课程后，AI 会在这里用通俗语言解释课程设计。")
        self.explain_label.setMaximumHeight(180)
        explain_layout.addWidget(self.explain_label)
        self.explain_group.setVisible(False)
        layout.addWidget(self.explain_group)

        self.file_list_widget = QWidget()
        self.file_list_layout = QHBoxLayout(self.file_list_widget)
        self.file_list_layout.setContentsMargins(0, 0, 0, 0)
        self.file_list_layout.setSpacing(6)
        self.file_list_layout.addStretch()
        layout.addWidget(self.file_list_widget)

        input_row = QHBoxLayout()
        input_row.setSpacing(10)
        self.input_edit = QTextEdit()
        self.input_edit.setPlaceholderText("输入你想说的，Ctrl+Enter 发送...")
        self.input_edit.setMaximumHeight(80)
        self.input_edit.setStyleSheet(
            "QTextEdit {"
            "  border: 1px solid #2C313C;"
            "  border-radius: 8px;"
            "  background-color: #1F232C;"
            "  font-family: system-ui, sans-serif;"
            "  font-size: 14px;"
            "  padding: 8px;"
            "}"
        )
        self.input_edit.keyPressEvent = self._input_key_press  # type: ignore[method-assign]
        input_row.addWidget(self.input_edit, 1)

        action_layout = QVBoxLayout()
        action_layout.setSpacing(8)
        self.attach_btn = QPushButton("📎 附件")
        self.attach_btn.setToolTip("上传图片 / PDF / Word / 文本文件")
        self.attach_btn.clicked.connect(self._on_attach_files)
        action_layout.addWidget(self.attach_btn)

        self.send_btn = QPushButton("发送")
        self.send_btn.setToolTip("Ctrl+Enter 快捷发送")
        self.send_btn.clicked.connect(self._on_send_message)
        action_layout.addWidget(self.send_btn)

        self.wish_btn = QPushButton("我感觉差不多了")
        self.wish_btn.setToolTip("让 AI 根据对话生成课程")
        self.wish_btn.setStyleSheet(
            "QPushButton {"
            "  background-color: #145A64;"
            "  color: #FFFFFF;"
            "  border: none;"
            "  border-radius: 6px;"
            "  padding: 6px 12px;"
            "}"
            "QPushButton:hover { background-color: #1F727E; }"
        )
        self.wish_btn.clicked.connect(self._on_wish_generate)
        action_layout.addWidget(self.wish_btn)
        action_layout.addStretch()
        input_row.addLayout(action_layout)
        layout.addLayout(input_row)

        return widget

    # --- Mode switching ---------------------------------------------------

    def _apply_edit_mode_ui(self) -> None:
        """Adjust button labels when opened in edit mode."""
        if self._edit_mode is None:
            return
        scope = self._edit_mode.get("scope", "section")
        label = {
            "section": "应用编辑（Section）",
            "unit": "应用编辑（Unit）",
            "lesson": "应用编辑（Lesson）",
        }.get(scope, "应用编辑")
        self._button_box.button(QDialogButtonBox.StandardButton.Ok).setText(label)

    def config(self) -> AiApiConfig:
        """Return the current (possibly verified) API config."""
        return self._config

    def set_verified_config(self, verified: AiApiConfig | None) -> None:
        """Allow the caller to seed a previously-verified config."""
        if verified is not None and verified == self._config:
            self._verified_config = verified
            self._update_api_status()

    def _on_mode_changed(self, index: int) -> None:
        self._mode = self.mode_combo.itemData(index) or "normal"
        self._update_mode_ui()

    def _update_mode_ui(self) -> None:
        is_normal = self._mode == "normal"
        self._normal_panel.setVisible(is_normal)
        self._wish_panel.setVisible(not is_normal)
        self._button_box.button(QDialogButtonBox.StandardButton.Ok).setEnabled(
            self._generated is not None
        )
        self._button_box.button(QDialogButtonBox.StandardButton.Ok).setText("导入到课程")

    def _on_template_changed(self, index: int) -> None:
        """Placeholder for template selection side effects."""
        self._update_input_placeholders()

    def _on_genre_switch_changed(self, state: int) -> None:
        """When genre batch switch toggles, update placeholder and template label."""
        enabled = state == Qt.CheckState.Checked.value
        if enabled:
            self.template_combo.setItemText(0, "默认回退")
        else:
            self.template_combo.setItemText(0, "混合")
        self._update_input_placeholders()
        self._sync_template_from_genre_tags()

    def _update_input_placeholders(self) -> None:
        if self.genre_switch.isChecked():
            self.topic_edit.setPlaceholderText("例如：旅行词汇 [intro] [practice]")
            self.input_edit.setPlaceholderText("输入你想说的，可插入 [intro]、[listening] 等 genre 标签；Ctrl+Enter 发送...")
        else:
            self.topic_edit.setPlaceholderText("例如：旅行词汇")
            self.input_edit.setPlaceholderText("输入你想说的，Ctrl+Enter 发送...")

    def _on_topic_text_changed(self, text: str) -> None:
        """Detect genre tags in normal mode topic/extra input."""
        if not self.genre_switch.isChecked():
            return
        self._sync_template_from_genre_tags()

    def _sync_template_from_genre_tags(self) -> None:
        """Set the template combo to the default fallback based on detected genre tag."""
        if not self.genre_switch.isChecked():
            return
        combined = f"{self.topic_edit.text()} {self.extra_edit.text()}"
        tags = genre_tags_in_text(combined)
        if tags:
            template = genre_to_template(tags[0])
            self._set_template_combo(template)
            self.template_combo.setItemText(0, "默认回退")
        else:
            self.template_combo.setItemText(0, "默认回退")

    def _set_template_combo(self, template: str) -> None:
        for i in range(self.template_combo.count()):
            if self.template_combo.itemData(i) == template:
                self.template_combo.setCurrentIndex(i)
                return
        self.template_combo.setCurrentIndex(0)

    def _on_api_settings(self) -> None:
        dlg = ApiConfigDialog(self._config, self)
        if dlg.exec() == QDialog.DialogCode.Accepted:
            self._config = dlg.config()
            # ApiConfigDialog only accepts after a successful connection test,
            # so the saved config is guaranteed to be verified.
            self._verified_config = AiApiConfig(
                base_url=self._config.base_url,
                api_key=self._config.api_key,
                model=self._config.model,
            )
            self._update_api_status()

    def _ensure_api_configured(self) -> bool:
        """Validate API config; if not verified, prompt the user to open settings.

        Returns True only when the current config has passed a connection test.
        """
        if (
            self._verified_config is not None
            and self._verified_config == self._config
        ):
            return True
        reason = "未配置" if self._verified_config is None else "配置已修改，尚未重新测试"
        QMessageBox.warning(
            self,
            f"API {reason}",
            "请先点击右上角「API 设置」并完成「测试连接」通过后，再使用 AI 功能。",
        )
        self._on_api_settings()
        return (
            self._verified_config is not None
            and self._verified_config == self._config
        )

    def _update_api_status(self) -> None:
        if self._verified_config is not None and self._verified_config == self._config:
            self.api_status.setText(f"<font color='#27AE60'>已验证: {self._config.model}</font>")
        elif self._config.is_complete and _is_valid_http_url(self._config.base_url):
            self.api_status.setText("<font color='#FF9F43'>已配置未验证</font>")
        elif self._config.base_url or self._config.api_key or self._config.model:
            self.api_status.setText("<font color='#E74C3C'>配置不完整</font>")
        else:
            self.api_status.setText("<font color='#E74C3C'>未配置</font>")

    def _sync_config(self) -> None:
        # Config is already kept in self._config via the settings dialog.
        pass

    def _set_busy(self, busy: bool, normal: bool = False) -> None:
        """Enable/disable UI while an AI request is running."""
        if normal:
            self.generate_btn.setEnabled(not busy)
            self.progress.setVisible(busy)
        else:
            self.send_btn.setEnabled(not busy)
            self.wish_btn.setEnabled(not busy)
            self.attach_btn.setEnabled(not busy)
            self.wish_progress.setVisible(busy)

    def _on_worker_error(self, message: str) -> None:
        self._set_busy(False)
        QMessageBox.critical(self, "请求失败", message)

    def _current_spec(self) -> AiCourseSpec:
        spec = AiCourseSpec(
            language=self.language_edit.text().strip() or "Turkish",
            source_language=self.source_language_edit.text().strip() or "Chinese",
            topic=self.topic_edit.text().strip(),
            level=self.level_combo.currentText(),
            unit_count=self.unit_spin.value(),
            lessons_per_unit=self.lessons_spin.value(),
            template=self.template_combo.currentData() or "mixed",
            use_genre_batch=self.genre_switch.isChecked(),
            extra_instructions=self.extra_edit.text().strip(),
        )
        if spec.use_genre_batch:
            spec = apply_genre_to_spec(spec)
        return spec

    # --- Normal mode actions ---------------------------------------------

    def _on_generate_normal(self) -> None:
        topic = self.topic_edit.text().strip()
        if not topic:
            QMessageBox.warning(self, "缺少主题", "请先填写课程主题。")
            return
        if not self._ensure_api_configured():
            return
        if self._current_worker is not None and self._current_worker.isRunning():
            return

        spec = self._current_spec()
        if self._edit_mode is not None:
            worker = AiRequestWorker(
                generate_edit,
                self._config,
                spec,
                self._edit_mode["existing_section"],
                self._edit_mode.get("scope", "section"),
                self._edit_mode.get("scope_id", ""),
            )
        else:
            worker = AiRequestWorker(generate_from_chat, self._config, spec, [])
        worker.result_ready.connect(self._on_normal_generation_ready)
        worker.error_occurred.connect(self._on_worker_error)
        worker.completed.connect(lambda: self._set_busy(False, normal=True))
        self._current_worker = worker
        self._set_busy(True, normal=True)
        worker.start()

    def _on_normal_generation_ready(self, parsed: object) -> None:
        self._generated = parsed
        self.json_edit.setPlainText(json.dumps(parsed, ensure_ascii=False, indent=2))
        self.reset_btn.setEnabled(True)
        self._update_mode_ui()

    def _on_reset(self) -> None:
        if self._generated is not None:
            self.json_edit.setPlainText(
                json.dumps(self._generated, ensure_ascii=False, indent=2)
            )

    def _on_validate_json(self) -> None:
        try:
            data = self._current_json()
        except ValueError as exc:
            QMessageBox.warning(self, "JSON 无效", str(exc))
            return
        QMessageBox.information(
            self,
            "JSON 有效",
            f"JSON 解析成功：{len(data.get('units', []))} 个单元。",
        )

    def _current_json(self) -> dict:
        if self._mode == "wish":
            if self._generated is None:
                raise ValueError("尚未生成课程。")
            return self._generated
        raw = self.json_edit.toPlainText().strip()
        if not raw:
            raise ValueError("JSON 为空。")
        try:
            data = json.loads(raw)
        except json.JSONDecodeError as exc:
            raise ValueError(f"JSON 解析失败: {exc}") from exc
        if not isinstance(data, dict) or "units" not in data:
            raise ValueError("JSON 必须是包含 'units' 数组的对象。")
        return data

    # --- Wish mode actions -----------------------------------------------

    def _input_key_press(self, event) -> None:
        if event.key() in (Qt.Key.Key_Return, Qt.Key.Key_Enter) and event.modifiers() == Qt.KeyboardModifier.ControlModifier:
            self._on_send_message()
        else:
            QTextEdit.keyPressEvent(self.input_edit, event)

    def _render_chat(self) -> None:
        html_parts: list[str] = []
        html_parts.append(
            '<div style="font-family: system-ui, sans-serif; font-size: 14px; padding: 8px;">'
        )
        if not self._messages:
            html_parts.append(
                '<div style="color: #6B7280; text-align: center; padding: 32px 16px;">'
                '👋 欢迎使用许愿模式！告诉我你想做什么课程，我会一步步帮你设计。<br>'
                '你可以直接拖拽图片、PDF、Word 或文本到窗口作为参考。'
                '</div>'
            )
        for msg in self._messages:
            if msg.role == "user":
                html_parts.append(self._user_bubble_html(msg.content, msg.timestamp))
            elif msg.role == "assistant":
                html_parts.append(self._ai_bubble_html(msg.content, msg.timestamp))
        html_parts.append("</div>")
        self.chat_view.setHtml("\n".join(html_parts))
        scrollbar = self.chat_view.verticalScrollBar()
        scrollbar.setValue(scrollbar.maximum())

    def _user_bubble_html(self, content: str | list[dict[str, Any]], ts: str = "") -> str:
        text = self._format_message_content(content)
        ts_html = f'<div style="font-size: 10px; color: #6B7280; text-align: right; margin-bottom: 2px;">{self._escape_html(ts)}</div>' if ts else ""
        return (
            '<div style="display: flex; justify-content: flex-end; margin: 12px 0;">'
            '<div style="max-width: 75%;">'
            f'{ts_html}'
            '<div style="display: inline-block; background-color: #145A64; color: #FFFFFF; padding: 10px 14px; border-radius: 12px 12px 2px 12px; text-align: left; line-height: 1.6;">'
            f'{self._escape_html(text)}</div>'
            "</div></div>"
        )

    def _ai_bubble_html(self, content: str | list[dict[str, Any]], ts: str = "") -> str:
        text = self._format_message_content(content)
        ts_html = f'<div style="font-size: 10px; color: #6B7280; margin-bottom: 2px;">AI · {self._escape_html(ts)}</div>' if ts else ""
        return (
            '<div style="display: flex; justify-content: flex-start; margin: 12px 0;">'
            '<div style="max-width: 80%;">'
            f'{ts_html}'
            '<div style="display: inline-block; background-color: #2C313C; color: #E8EAF0; padding: 10px 14px; border-radius: 12px 12px 12px 2px; text-align: left; line-height: 1.6;">'
            f'{self._escape_html(text)}</div>'
            "</div></div>"
        )

    @staticmethod
    def _format_message_content(content: str | list[dict[str, Any]]) -> str:
        if isinstance(content, str):
            return content
        parts: list[str] = []
        for piece in content:
            if isinstance(piece, dict):
                if piece.get("type") == "text":
                    parts.append(str(piece.get("text", "")))
                elif piece.get("type") == "image_url":
                    parts.append("[图片]")
        return "\n".join(parts)

    @staticmethod
    def _escape_html(text: str) -> str:
        return (
            text.replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace(">", "&gt;")
            .replace("\n", "<br>")
        )

    def _on_send_message(self) -> None:
        text = self.input_edit.toPlainText().strip()
        if not text and not self._attachments:
            return
        if not self._ensure_api_configured():
            return
        if self._current_worker is not None and self._current_worker.isRunning():
            return

        if self.genre_switch.isChecked():
            tag = detect_genre_from_spec(
                AiCourseSpec(topic=text, extra_instructions="", use_genre_batch=True)
            )
            if tag:
                self._set_template_combo(genre_to_template(tag))

        user_content: list[dict[str, Any]] = [{"type": "text", "text": text}]
        for att in self._attachments:
            user_content.append(att.content)
        self._messages.append(ChatMessage(role="user", content=user_content))
        self.input_edit.clear()
        self._attachments.clear()
        self._refresh_attachment_list()
        self._render_chat()

        worker = AiRequestWorker(
            request_alignment_reply, self._config, self._current_spec(), self._messages
        )
        worker.result_ready.connect(self._on_alignment_reply_ready)
        worker.error_occurred.connect(self._on_worker_error)
        worker.completed.connect(lambda: self._set_busy(False))
        self._current_worker = worker
        self._set_busy(True)
        worker.start()

    def _on_alignment_reply_ready(self, reply: object) -> None:
        self._messages.append(ChatMessage(role="assistant", content=str(reply)))
        self._render_chat()

    def _add_attachment_paths(self, paths: list[Path]) -> None:
        for path in paths:
            temp_name = f"varnamala_wish_{uuid.uuid4().hex[:8]}_{path.name}"
            temp_path = Path(tempfile.gettempdir()) / temp_name
            try:
                shutil.copy(str(path), str(temp_path))
            except OSError as exc:
                QMessageBox.warning(self, "添加失败", f"无法复制文件 {path.name}: {exc}")
                continue
            result = extract_attachment(temp_path)
            if not result.ok:
                QMessageBox.warning(
                    self, "提取失败", f"{path.name}: {result.error}"
                )
                try:
                    temp_path.unlink(missing_ok=True)
                except OSError:
                    pass
                continue
            self._attachments.append(
                _AttachmentRecord(
                    temp_path=temp_path,
                    original_name=path.name,
                    content=result.content or {},
                )
            )
        self._refresh_attachment_list()

    def _on_attach_files(self) -> None:
        paths, _filter = QFileDialog.getOpenFileNames(
            self,
            "选择附件",
            "",
            "支持的文件 (*.png *.jpg *.jpeg *.gif *.webp *.pdf *.doc *.docx *.txt *.md *.csv *.json *.yaml *.yml);;所有文件 (*)",
        )
        if not paths:
            return
        self._add_attachment_paths([Path(p) for p in paths])

    def _remove_attachment(self, index: int) -> None:
        if 0 <= index < len(self._attachments):
            att = self._attachments.pop(index)
            try:
                att.temp_path.unlink(missing_ok=True)
            except OSError:
                pass
            self._refresh_attachment_list()

    def _refresh_attachment_list(self) -> None:
        while self.file_list_layout.count():
            child = self.file_list_layout.takeAt(0)
            if child.widget():
                child.widget().setParent(None)
                child.widget().deleteLater()
        for idx, att in enumerate(self._attachments):
            chip = QWidget()
            chip.setStyleSheet(
                "background-color: #1F232C; border-radius: 6px;"
            )
            chip_layout = QHBoxLayout(chip)
            chip_layout.setContentsMargins(8, 4, 4, 4)
            chip_layout.setSpacing(6)
            label = QLabel(f"📎 {att.original_name}")
            label.setStyleSheet("color: #E8EAF0; font-size: 12px; border: none;")
            chip_layout.addWidget(label)
            del_btn = QPushButton("×")
            del_btn.setFixedSize(18, 18)
            del_btn.setToolTip("移除附件")
            del_btn.setStyleSheet(
                "QPushButton {"
                "  border: none;"
                "  color: #9CA3AF;"
                "  font-size: 14px;"
                "  background: transparent;"
                "}"
                "QPushButton:hover { color: #E74C3C; }"
            )
            del_btn.clicked.connect(lambda _checked=False, i=idx: self._remove_attachment(i))
            chip_layout.addWidget(del_btn)
            self.file_list_layout.addWidget(chip)
        self.file_list_layout.addStretch()

    def _on_wish_generate(self) -> None:
        if not self._ensure_api_configured():
            return
        if not self._messages:
            QMessageBox.warning(
                self, "对话为空", "请先和 AI 聊几句，告诉它你想做什么课程。"
            )
            return
        if self._current_worker is not None and self._current_worker.isRunning():
            return

        if self._edit_mode is not None:
            worker = AiRequestWorker(
                generate_edit,
                self._config,
                self._current_spec(),
                self._edit_mode["existing_section"],
                self._edit_mode.get("scope", "section"),
                self._edit_mode.get("scope_id", ""),
                self._messages,
                self._draft_json,
            )
        else:
            worker = AiRequestWorker(
                generate_from_chat,
                self._config,
                self._current_spec(),
                self._messages,
                draft_json=self._draft_json,
            )
        worker.result_ready.connect(self._on_wish_generation_ready)
        worker.error_occurred.connect(self._on_worker_error)
        worker.completed.connect(lambda: None)
        self._current_worker = worker
        self._set_busy(True)
        worker.start()

    def _on_wish_generation_ready(self, parsed: object) -> None:
        self._generated = parsed
        self._draft_json = parsed

        if not isinstance(parsed, dict):
            self._set_busy(False)
            QMessageBox.critical(self, "生成失败", "模型返回了非预期的数据类型。")
            return

        worker = AiRequestWorker(
            explain_course, self._config, self._current_spec(), parsed
        )
        worker.result_ready.connect(self._on_explain_ready)
        worker.error_occurred.connect(self._on_worker_error)
        worker.completed.connect(lambda: self._set_busy(False))
        self._current_worker = worker
        worker.start()

    def _on_explain_ready(self, explanation: object) -> None:
        text = str(explanation)
        safe = self._escape_html(text)
        self.explain_label.setHtml(safe)
        self.explain_group.setVisible(True)
        self._update_mode_ui()

        QMessageBox.information(
            self,
            "生成完成",
            "课程已生成。点击「导入到课程」将其加入左侧课程树，或继续对话修改。",
        )

    # --- Import / accept -------------------------------------------------

    def _on_accept(self) -> None:
        try:
            data = self._current_json()
        except ValueError as exc:
            QMessageBox.warning(self, "无法导入", str(exc))
            return

        sid = data.get("id") or ""
        if not sid:
            QMessageBox.warning(self, "缺少 section id", "生成的 JSON 缺少顶层 id 字段。")
            return

        if self._edit_mode is not None:
            existing_id = self._edit_mode["existing_section"].get("id", "")
            if existing_id and sid != existing_id:
                data["id"] = existing_id
                sid = existing_id
            problems = self.adapter.validate_section_json(data)
            # In edit mode the section id already exists in the course; the
            # validator flags it as a duplicate. Drop that single error so we
            # can still surface genuine structural problems.
            problems = [
                p
                for p in problems
                if not (
                    p.get("level") == "error"
                    and "已存在" in p.get("message", "")
                    and p.get("path") == "id"
                )
            ]
            errors = [p for p in problems if p["level"] == "error"]
            warnings = [p for p in problems if p["level"] == "warning"]
            if errors:
                detail = "\n".join(f"[{p['level']}] {p['message']}" for p in errors)
                QMessageBox.warning(self, "校验失败，无法应用", detail)
                return
            if warnings:
                detail = "\n".join(f"[{p['level']}] {p['message']}" for p in warnings)
                QMessageBox.information(
                    self, "应用警告", f"存在警告，但仍可应用：\n\n{detail}"
                )
            self._generated = data
            self.accept()
            return

        # Allow user to edit id if conflict.
        existing_ids = {s.get("id") for s in self.adapter.sections}
        existing_index_ids = {
            e.get("id") for e in self.adapter.index.get("sections", [])
        }
        while sid in existing_ids or sid in existing_index_ids:
            new_sid, ok = QInputDialog.getText(
                self,
                "ID 冲突",
                f"section id「{sid}」已存在，请修改：",
                text=sid,
            )
            if not ok or not new_sid:
                return
            sid = new_sid
        data["id"] = sid

        problems = self.adapter.validate_section_json(data)
        errors = [p for p in problems if p["level"] == "error"]
        warnings = [p for p in problems if p["level"] == "warning"]
        if errors:
            detail = "\n".join(f"[{p['level']}] {p['message']}" for p in errors)
            QMessageBox.warning(self, "校验失败，无法导入", detail)
            return
        if warnings:
            detail = "\n".join(f"[{p['level']}] {p['message']}" for p in warnings)
            QMessageBox.information(
                self, "导入警告", f"存在警告，但仍可导入：\n\n{detail}"
            )

        self._generated = data
        self.accept()

    # --- Drag and drop ---------------------------------------------------

    def dragEnterEvent(self, event: QDragEnterEvent) -> None:  # noqa: N802
        if event.mimeData().hasUrls():
            event.acceptProposedAction()
        else:
            super().dragEnterEvent(event)

    def dragMoveEvent(self, event) -> None:  # noqa: N802
        if event.mimeData().hasUrls():
            event.acceptProposedAction()
        else:
            super().dragMoveEvent(event)

    def dropEvent(self, event: QDropEvent) -> None:  # noqa: N802
        urls = event.mimeData().urls()
        paths = [Path(u.toLocalFile()) for u in urls if u.isLocalFile()]
        if paths:
            self._add_attachment_paths(paths)
        event.acceptProposedAction()

    # --- Cleanup ---------------------------------------------------------

    def _cleanup_attachments(self) -> None:
        for att in self._attachments:
            try:
                att.temp_path.unlink(missing_ok=True)
            except OSError:
                pass
        self._attachments.clear()

    def reject(self) -> None:
        self._cleanup_attachments()
        super().reject()

    def accept(self) -> None:
        self._cleanup_attachments()
        super().accept()

    def closeEvent(self, event) -> None:  # noqa: N802
        self._cleanup_attachments()
        super().closeEvent(event)

    # --- Public accessors ------------------------------------------------

    def section_json(self) -> dict:
        """Return the (possibly edited) section dict to import."""
        return self._current_json()


def QApplication_safe_process_events() -> None:
    """Keep the UI responsive during the blocking network call."""
    from PySide6.QtWidgets import QApplication

    QApplication.processEvents()
