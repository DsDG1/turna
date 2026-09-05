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
import logging
import time
from pathlib import Path
from typing import Any

from PySide6.QtCore import Qt, QSize
from PySide6.QtGui import QDragEnterEvent, QDropEvent
from PySide6.QtWidgets import (
    QCheckBox,
    QComboBox,
    QDialog,
    QDialogButtonBox,
    QFileDialog,
    QFormLayout,
    QFrame,
    QGroupBox,
    QHBoxLayout,
    QInputDialog,
    QLabel,
    QLineEdit,
    QMessageBox,
    QProgressBar,
    QPushButton,
    QSpinBox,
    QSplitter,
    QTabWidget,
    QTextBrowser,
    QTextEdit,
    QVBoxLayout,
    QWidget,
)

from src.application.ai_runtime import runtime_from_host
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
    regenerate_lesson_in_section,
    regenerate_unit_in_section,
    request_alignment_reply,
    request_course_with_retry,
    structural_diff,
)
from src.backend.ai_genre import genre_tags_in_text
from src.backend.ai_prompt_library import AiPromptHistory, AiPromptTemplate, prompt_library
from src.backend.ai_usage import format_usage_line
from src.dialogs.ai.attachment_bar import AttachmentBar
from src.dialogs.ai.chat_expand_window import ChatExpandWindow
from src.dialogs.ai.chat_view import (
    DEFAULT_PALETTE as _CHAT_PALETTE,
    ChatView,
)
from src.dialogs.ai.generator_chat_coordinator import GeneratorChatCoordinator, escape_html
from src.dialogs.ai.generator_preview_coordinator import (
    GeneratorPreviewCoordinator,
    confirm_structural_removal,
    find_line_for_path,
    jump_editor_to_path,
    try_preview_lesson,
    view_section_diff,
)
from src.dialogs.ai.generator_wizard_panel import GeneratorWizardPanel
from src.dialogs.ai.generator_worker_hub import GeneratorWorkerHub, record_cache_stats
from src.dialogs.ai.prompt_template_bar import PromptTemplateBar
from src.dialogs.ai.result_window import ResultExpandWindow
from src.dialogs.ai.worker import (
    AttachmentRecord as _AttachmentRecord,
    AiRequestWorker,
    is_valid_http_url as _is_valid_http_url,
)
from src.infrastructure.telemetry import telemetry
from src.theme_tokens import BRAND_REED, BRAND_TEAL, BRAND_TEAL_DARK
from src.widgets.json_editor import JsonEditor
from src.widgets.result_preview import ResultPreviewWidget

logger = logging.getLogger(__name__)

# Backward-compat aliases
_record_cache_stats = record_cache_stats
_escape_html = escape_html


class AiGeneratorDialog(QDialog):
    """AI course generator dialog with normal and wish modes.

    On accept, ``section_json()`` returns the (possibly edited) section dict
    ready to be appended to ``adapter.sections`` and registered in the index.
    """

    _STREAM_TEXT_LIVE_LIMIT = 8192

    def __init__(
        self,
        adapter,
        parent: QWidget | None = None,
        edit_mode: dict[str, Any] | None = None,
    ) -> None:
        super().__init__(parent)
        self.adapter = adapter
        self._edit_mode = edit_mode
        self.setWindowTitle("AI 编辑" if edit_mode is not None else "AI 生成课程")
        self.resize(1180, 860)
        self.setMinimumSize(QSize(900, 640))
        self.setAcceptDrops(True)

        self._runtime = runtime_from_host(parent)
        self._config = self._runtime.config()
        self._generated: dict | None = None
        self._mode = "normal"
        self._normal_tab = "topic"

        # Specialized sub-coordinators
        self._worker_hub = GeneratorWorkerHub(self)
        self._preview_coord = GeneratorPreviewCoordinator(self)
        self._chat_coord = GeneratorChatCoordinator(self)

        self._worker_hub.chunk_rendered.connect(self._on_chunk_rendered)
        self._worker_hub.usage_updated.connect(self._on_usage_updated)
        self._worker_hub.stage_changed.connect(self._set_stage_label)

        self._prompt_library = prompt_library()
        self._draft_json: dict | None = None
        self._busy_normal = False
        self._busy_wish = False
        self._closing = False

        self._build_ui()
        self._update_api_status()
        self._apply_edit_mode_ui()

    # --- Property Forwarding (100% Backward Compatibility) ---------------

    @property
    def _messages(self) -> list[ChatMessage]:
        return self._chat_coord.messages

    @_messages.setter
    def _messages(self, val: list[ChatMessage]) -> None:
        self._chat_coord.messages = val

    @property
    def _attachments(self) -> list[_AttachmentRecord]:
        return self._chat_coord.attachments

    @_attachments.setter
    def _attachments(self, val: list[_AttachmentRecord]) -> None:
        self._chat_coord.attachments = val

    @property
    def _current_worker(self) -> AiRequestWorker | None:
        return self._worker_hub.current_worker

    @_current_worker.setter
    def _current_worker(self, val: AiRequestWorker | None) -> None:
        self._worker_hub._current_worker = val

    @property
    def _request_start(self) -> float | None:
        return self._worker_hub.request_start

    @_request_start.setter
    def _request_start(self, val: float | None) -> None:
        self._worker_hub.request_start = val

    @property
    def _stream_buffer(self) -> str:
        return self._worker_hub.stream_buffer

    @_stream_buffer.setter
    def _stream_buffer(self, val: str) -> None:
        self._worker_hub._stream_buffer = val

    @property
    def _stream_target(self) -> str | None:
        return self._worker_hub.stream_target

    @_stream_target.setter
    def _stream_target(self, val: str | None) -> None:
        self._worker_hub._stream_target = val

    @property
    def _stream_dirty(self) -> bool:
        return self._worker_hub._stream_dirty

    @_stream_dirty.setter
    def _stream_dirty(self, val: bool) -> None:
        self._worker_hub._stream_dirty = val

    @property
    def _stream_flush_timer(self):
        return self._worker_hub._stream_flush_timer

    @property
    def _json_window(self) -> ResultExpandWindow | None:
        return self._preview_coord.json_window

    @_json_window.setter
    def _json_window(self, win: ResultExpandWindow | None) -> None:
        self._preview_coord.json_window = win

    @property
    def _chat_expand(self) -> ChatExpandWindow | None:
        return self._chat_coord.chat_expand_window

    @_chat_expand.setter
    def _chat_expand(self, win: ChatExpandWindow | None) -> None:
        self._chat_coord.chat_expand_window = win

    # --- UI construction -------------------------------------------------

    def _build_ui(self) -> None:
        root = QVBoxLayout(self)
        root.setSpacing(14)
        root.setContentsMargins(16, 16, 16, 16)

        self._beta_banner = self._build_beta_banner()
        self._header_bar = self._build_header_bar()
        self._spec_bar = self._build_spec_bar()
        root.addWidget(self._beta_banner)
        root.addWidget(self._header_bar)
        root.addWidget(self._spec_bar)

        self._stack = QVBoxLayout()
        self._stack.setSpacing(0)
        self._stack.setContentsMargins(0, 0, 0, 0)
        self._normal_panel = self._build_normal_panel()
        self._wish_panel = self._build_wish_panel()
        self._stack.addWidget(self._normal_panel)
        self._stack.addWidget(self._wish_panel)
        root.addLayout(self._stack, 1)

        self._build_template_selector()
        self._template_bar.set_library(self._prompt_library)
        self._template_bar.template_applied.connect(self._on_template_applied)
        self._template_bar.history_applied.connect(self._on_history_applied)
        self.topic_edit.textChanged.connect(self._on_topic_text_changed)
        self.extra_edit.textChanged.connect(self._on_topic_text_changed)

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
        self._set_tab_order()

    def _set_tab_order(self) -> None:
        """Keyboard tab order for the wish-mode input cluster."""
        from PySide6.QtWidgets import QWidget as _W

        _W.setTabOrder(self.input_edit, self.attach_btn)
        _W.setTabOrder(self.attach_btn, self.send_btn)
        _W.setTabOrder(self.send_btn, self.wish_btn)
        _W.setTabOrder(self.wish_btn, self._enter_to_send)
        _W.setTabOrder(self._enter_to_send, self.expand_btn)

    def _build_beta_banner(self) -> QWidget:
        widget = QWidget()
        layout = QHBoxLayout(widget)
        layout.setContentsMargins(10, 8, 10, 8)
        layout.setSpacing(8)
        widget.setStyleSheet(
            f"background-color: {self._pal('ai_beta_bg', '#664400')}; "
            f"color: {self._pal('ai_beta_text', '#FFD93D')}; border-radius: 6px;"
        )
        label = QLabel(
            "AI 生成结果仅供参考，请人工校验。本功能会消耗大量 token，"
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

        self.api_status = QLabel(f"<font color='{self._pal('error', '#E74C3C')}'>未配置</font>")
        self.api_status.setStyleSheet("font-size: 12px;")
        layout.addWidget(self.api_status)

        self.api_hint = QLabel("AI 配置请在工具栏「设置」中管理。")
        self.api_hint.setObjectName("hintLabel")
        layout.addWidget(self.api_hint)
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
        if getattr(self, "_template_bar", None) is not None:
            return self._template_bar
        bar = PromptTemplateBar()
        bar.template_changed.connect(self._on_template_changed_value)
        bar.genre_toggled.connect(self._on_genre_toggled)
        self._template_bar = bar
        self.template_combo = bar.template_combo
        self._template_cards = bar._template_cards
        self.genre_switch = bar.genre_switch
        return bar

    def _on_template_changed_value(self, template: str) -> None:
        self._update_input_placeholders()

    def _on_genre_toggled(self, enabled: bool) -> None:
        self._update_input_placeholders()
        self._sync_template_from_genre_tags()

    def _build_normal_panel(self) -> QWidget:
        widget = QWidget()
        layout = QVBoxLayout(widget)
        layout.setSpacing(12)
        layout.setContentsMargins(0, 0, 0, 0)

        self.normal_tabs = QTabWidget()
        self._topic_panel = self._build_topic_panel()
        self._wizard_panel = self._build_wizard_panel()
        self.normal_tabs.addTab(self._topic_panel, "主题生成")
        self.normal_tabs.addTab(self._wizard_panel, "向导生成")
        self.normal_tabs.currentChanged.connect(self._on_normal_tab_changed)
        result_group = self._build_result_group()

        self._normal_splitter = QSplitter(Qt.Orientation.Horizontal)
        self._normal_splitter.setContentsMargins(0, 0, 0, 0)
        self._normal_splitter.addWidget(self.normal_tabs)
        self._normal_splitter.addWidget(result_group)
        self._normal_splitter.setStretchFactor(0, 2)
        self._normal_splitter.setStretchFactor(1, 3)
        self._normal_splitter.setCollapsible(0, False)
        self._normal_splitter.setCollapsible(1, False)
        self._normal_splitter.setSizes([460, 580])
        layout.addWidget(self._normal_splitter, 1)
        return widget

    def _build_topic_panel(self) -> QWidget:
        widget = QWidget()
        layout = QVBoxLayout(widget)
        layout.setSpacing(12)
        layout.setContentsMargins(0, 0, 0, 0)

        self._normal_template_slot = QVBoxLayout()
        self._normal_template_slot.setContentsMargins(0, 0, 0, 0)
        layout.addLayout(self._normal_template_slot)

        if self._edit_mode is not None:
            from PySide6.QtWidgets import QPlainTextEdit
            scope = self._edit_mode.get("scope", "section")
            scope_id = self._edit_mode.get("scope_id", "")

            info_lbl = QLabel(f"<b>正在编辑 {scope.upper()} : {scope_id}</b>")
            from src.theme import current_palette as _cp
            info_lbl.setStyleSheet(f"color: {_cp()['info']};")
            layout.addWidget(info_lbl)

            layout.addWidget(QLabel("修改要求/指令 (例如：增加两个练习题，补充单词Merhaba)："))
            self.edit_instruction_input = QPlainTextEdit()
            self.edit_instruction_input.setPlaceholderText("你想对该节点做出什么具体的改变？AI 将根据此指令进行精确重写。")
            self.edit_instruction_input.setMaximumHeight(80)
            layout.addWidget(self.edit_instruction_input)

        layout.addWidget(self._build_topic_row())
        return widget

    def _build_wizard_panel(self) -> QWidget:
        """Guided lesson creation panel delegating to GeneratorWizardPanel."""
        panel = GeneratorWizardPanel(self.adapter, palette=self._chat_palette(), parent=self)
        self.wizard_name_edit = panel.name_edit
        self.wizard_desc_edit = panel.desc_edit
        self.wizard_word_list = panel.word_list
        self.wizard_summary = panel.summary_label
        self.wizard_generate_btn = panel.generate_btn
        panel.generated_ready.connect(self._on_wizard_generated_ready)
        return panel

    def _update_wizard_summary(self, item: Any = None) -> None:
        self._wizard_panel.update_summary(item)

    def _selected_wizard_words(self) -> list[dict[str, Any]]:
        return self._wizard_panel.selected_words()

    def _on_wizard_generate(self) -> None:
        self._wizard_panel.generate()

    def _on_wizard_generated_ready(self, section: dict[str, Any]) -> None:
        self._generated = section
        self.json_edit.setPlainText(json.dumps(section, ensure_ascii=False, indent=2))
        self.reset_btn.setEnabled(False)
        self.result_preview.show_section(section)
        self.result_preview.setVisible(True)
        self._update_mode_ui()

    def _on_normal_tab_changed(self, index: int) -> None:
        self._normal_tab = "topic" if index == 0 else "wizard"

    def _build_topic_row(self) -> QWidget:
        widget = QWidget()
        layout = QHBoxLayout(widget)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(8)

        self.topic_edit = QLineEdit()
        self.topic_edit.setPlaceholderText("例如：旅行词汇 [intro]")
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
        self.result_preview = ResultPreviewWidget(self.adapter, grp)
        self.result_preview.setVisible(False)
        self.result_preview.validity_changed.connect(self._on_preview_validity)
        self.result_preview.validate_btn.clicked.disconnect()
        self.result_preview.validate_btn.clicked.connect(self._on_validate_from_editor)
        layout.addWidget(self.result_preview)
        self.json_edit = JsonEditor()
        self.json_edit.restyle(self._chat_palette())
        self.result_preview.node_activated.connect(self._on_preview_node_activated)

        self._normal_json_host = QVBoxLayout()
        self._normal_json_host.setContentsMargins(0, 0, 0, 0)
        self._normal_json_host.addWidget(self.json_edit)
        layout.addLayout(self._normal_json_host, 1)
        self._json_window_btn = QPushButton("↗ JSON 独立窗口")
        self._json_window_btn.setToolTip("把 JSON 编辑器弹到独立窗口，腾出空间")
        self._json_window_btn.setCheckable(True)
        self._json_window_btn.toggled.connect(self._on_json_window_toggled)
        layout.addWidget(self._json_window_btn)

        row = QHBoxLayout()
        row.setSpacing(8)
        self.reset_btn = QPushButton("恢复 AI 原始输出")
        self.reset_btn.clicked.connect(self._on_reset)
        self.reset_btn.setEnabled(False)
        row.addWidget(self.reset_btn)
        self.validate_btn = QPushButton("校验 JSON")
        self.validate_btn.clicked.connect(self._on_validate_json)
        row.addWidget(self.validate_btn)
        self.diff_btn = QPushButton("查看 diff")
        self.diff_btn.setToolTip("对比编辑前后的单元/课时/资源增删改")
        self.diff_btn.clicked.connect(self._on_view_diff)
        self.diff_btn.setVisible(False)
        row.addWidget(self.diff_btn)
        self.try_btn = QPushButton("试做")
        self.try_btn.setToolTip("挑一节课试做，检查题目与答案是否正确")
        self.try_btn.clicked.connect(self._on_try_preview)
        self.try_btn.setVisible(False)
        row.addWidget(self.try_btn)
        row.addStretch()
        layout.addLayout(row)

        self.progress = QProgressBar()
        self.progress.setRange(0, 0)
        self.progress.setVisible(False)
        progress_row = QHBoxLayout()
        progress_row.setSpacing(8)
        progress_row.addWidget(self.progress)
        self.stage_label = QLabel("")
        self.stage_label.setStyleSheet(
            f"color: {self._pal('ai_accent', BRAND_REED)}; font-size: 12px;"
        )
        self.stage_label.setVisible(False)
        progress_row.addWidget(self.stage_label)
        progress_row.addStretch()
        self.usage_label = QLabel("")
        self.usage_label.setStyleSheet(
            f"color: {self._pal('text_secondary', '#9CA3AF')}; font-size: 11px;"
        )
        self.usage_label.setVisible(False)
        progress_row.addWidget(self.usage_label)
        layout.addLayout(progress_row)
        return grp

    def _build_wish_panel(self) -> QWidget:
        widget = QWidget()
        layout = QVBoxLayout(widget)
        layout.setSpacing(12)
        layout.setContentsMargins(0, 0, 0, 0)

        hint_row = QHBoxLayout()
        hint_row.setContentsMargins(0, 0, 0, 0)
        hint_row.setSpacing(8)
        hint = QLabel(
            "许愿模式：像聊天一样描述课程需求，把图片、PDF、Word 或文本文件直接拖入窗口作为参考。"
        )
        hint.setWordWrap(True)
        hint.setStyleSheet(
            f"color: {self._pal('text_secondary', '#9CA3AF')}; font-size: 12px;"
        )
        hint_row.addWidget(hint, 1)
        self.expand_btn = QPushButton("↕ 放大聊天")
        self.expand_btn.setToolTip("把聊天区放大成独立可缩放窗口（再次点击还原）")
        self.expand_btn.setCursor(Qt.CursorShape.PointingHandCursor)
        self.expand_btn.setStyleSheet(
            "QPushButton {"
            f"  background-color: {self._pal('ai_card_bg', '#1F232C')};"
            f"  color: {self._pal('ai_accent', BRAND_REED)};"
            f"  border: 1px solid {self._pal('ai_bubble_bg', '#2C313C')};"
            "  border-radius: 6px;"
            "  padding: 4px 10px;"
            "  font-size: 12px;"
            "}"
            f"QPushButton:hover {{ border: 1px solid {self._pal('ai_accent_border', BRAND_TEAL)}; }}"
        )
        self.expand_btn.setCheckable(True)
        self.expand_btn.toggled.connect(self._on_expand_toggled)
        hint_row.addWidget(self.expand_btn)
        layout.addLayout(hint_row)

        self._wish_template_slot = QVBoxLayout()
        self._wish_template_slot.setContentsMargins(0, 0, 0, 0)
        layout.addLayout(self._wish_template_slot)

        chat_container = QWidget()
        chat_container.setStyleSheet(
            f"background-color: {self._pal('ai_chat_bg', '#1A1D23')}; "
            f"border: 1px solid {self._pal('ai_bubble_bg', '#2C313C')}; border-radius: 8px;"
        )
        chat_layout = QVBoxLayout(chat_container)
        chat_layout.setSpacing(0)
        chat_layout.setContentsMargins(0, 0, 0, 0)

        self.chat_view = ChatView()
        self.chat_view.setPlaceholderText("对话记录会显示在这里...")
        self.chat_view.restyle(self._chat_palette())
        chat_layout.addWidget(self.chat_view)

        self.wish_progress = QProgressBar()
        self.wish_progress.setRange(0, 0)
        self.wish_progress.setVisible(False)
        self.wish_stage_label = QLabel("")
        self.wish_stage_label.setStyleSheet(
            f"color: {self._pal('ai_accent', BRAND_REED)}; font-size: 12px;"
        )
        self.wish_stage_label.setVisible(False)
        self.wish_usage_label = QLabel("")
        self.wish_usage_label.setStyleSheet(
            f"color: {self._pal('text_secondary', '#9CA3AF')}; font-size: 11px;"
        )
        self.wish_usage_label.setVisible(False)
        progress_row = QHBoxLayout()
        progress_row.setSpacing(8)
        progress_row.setContentsMargins(0, 0, 0, 0)
        progress_row.addWidget(self.wish_progress)
        progress_row.addWidget(self.wish_stage_label)
        progress_row.addStretch()
        progress_row.addWidget(self.wish_usage_label)

        self._result_frame = QFrame()
        self._result_frame.setStyleSheet(
            f"QFrame {{ border: 1px solid {self._pal('ai_bubble_bg', '#2C313C')}; "
            f"border-radius: 6px; background-color: {self._pal('ai_card_bg', '#1F232C')}; }}"
        )
        result_v = QVBoxLayout(self._result_frame)
        result_v.setContentsMargins(8, 6, 8, 6)
        result_v.setSpacing(6)
        result_header = QHBoxLayout()
        result_header.setSpacing(8)
        self._result_summary = QLabel("生成后这里显示课程概要")
        self._result_summary.setStyleSheet(
            f"color: {self._pal('text_secondary', '#9CA3AF')}; font-size: 12px;"
        )
        result_header.addWidget(self._result_summary, 1)
        self._result_toggle = QPushButton("展开")
        self._result_toggle.setToolTip("展开/收起课程预览")
        self._result_toggle.setCursor(Qt.CursorShape.PointingHandCursor)
        self._result_toggle.setCheckable(True)
        self._result_toggle.toggled.connect(self._on_result_toggle)
        result_header.addWidget(self._result_toggle)
        result_v.addLayout(result_header)

        self.wish_result_preview = ResultPreviewWidget(self.adapter, widget)
        self.wish_result_preview.setVisible(False)
        self.wish_result_preview.validity_changed.connect(self._on_preview_validity)
        self.wish_result_preview.validate_btn.clicked.disconnect()
        self.wish_result_preview.validate_btn.clicked.connect(self._on_validate_from_editor)
        self.wish_result_preview.node_activated.connect(self._on_preview_node_activated)
        result_v.addWidget(self.wish_result_preview)

        self.wish_json_edit = JsonEditor()
        self.wish_json_edit.restyle(self._chat_palette())
        self.wish_json_edit.setVisible(False)
        self._wish_json_host = QVBoxLayout()
        self._wish_json_host.setContentsMargins(0, 0, 0, 0)
        self._wish_json_host.addWidget(self.wish_json_edit)
        result_v.addLayout(self._wish_json_host, 1)
        self._wish_json_window_btn = QPushButton("↗ JSON 独立窗口")
        self._wish_json_window_btn.setToolTip("把 JSON 编辑器弹到独立窗口，腾出空间")
        self._wish_json_window_btn.setCheckable(True)
        self._wish_json_window_btn.toggled.connect(self._on_json_window_toggled)
        self._wish_json_window_btn.setVisible(False)
        result_v.addWidget(self._wish_json_window_btn)

        self.explain_group = QGroupBox("AI 通俗解释")
        explain_layout = QVBoxLayout(self.explain_group)
        explain_layout.setContentsMargins(8, 8, 8, 8)
        explain_layout.setSpacing(4)
        self.explain_label = QTextBrowser()
        self.explain_label.setOpenExternalLinks(True)
        self.explain_label.setStyleSheet(
            "QTextBrowser {"
            "  border: none;"
            f"  background-color: {self._pal('ai_card_bg', '#1F232C')};"
            f"  color: {self._pal('ai_accent', BRAND_REED)};"
            "  font-family: system-ui, sans-serif;"
            "  font-size: 13px;"
            "  padding: 8px;"
            "}"
        )
        self.explain_label.setPlaceholderText("生成课程后，AI 会在这里用通俗语言解释课程设计。")
        self.explain_label.setMaximumHeight(180)
        explain_layout.addWidget(self.explain_label)
        self.explain_group.setVisible(False)
        result_v.addWidget(self.explain_group)

        self._result_frame.setVisible(False)

        self._attachment_bar = AttachmentBar()
        self._attachment_bar.attachments_changed.connect(self._on_attachments_changed)

        input_row = QHBoxLayout()
        input_row.setSpacing(10)
        self.input_edit = QTextEdit()
        self.input_edit.setPlaceholderText("输入你想说的，Ctrl+Enter 发送...")
        self.input_edit.setMaximumHeight(80)
        self.input_edit.setStyleSheet(
            "QTextEdit {"
            f"  border: 1px solid {self._pal('ai_bubble_bg', '#2C313C')};"
            "  border-radius: 8px;"
            f"  background-color: {self._pal('ai_card_bg', '#1F232C')};"
            "  font-family: system-ui, sans-serif;"
            "  font-size: 14px;"
            "  padding: 8px;"
            "}"
        )
        self.input_edit.keyPressEvent = self._input_key_press  # type: ignore[method-assign]
        input_row.addWidget(self.input_edit, 1)

        action_layout = QVBoxLayout()
        action_layout.setSpacing(8)
        self.attach_btn = QPushButton("附件")
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
            f"  background-color: {self._pal('ai_user_bubble', BRAND_TEAL_DARK)};"
            "  color: #FFFFFF;"
            "  border: none;"
            "  border-radius: 6px;"
            "  padding: 6px 12px;"
            "}"
            f"QPushButton:hover {{ background-color: {self._pal('ai_accent_border', BRAND_TEAL)}; }}"
        )
        self.wish_btn.clicked.connect(self._on_wish_generate)
        action_layout.addWidget(self.wish_btn)
        self._enter_to_send = QCheckBox("Enter 发送")
        self._enter_to_send.setChecked(True)
        self._enter_to_send.setToolTip("勾选后按 Enter 直接发送（Shift+Enter 换行）；Ctrl+Enter 始终发送")
        action_layout.addWidget(self._enter_to_send)
        action_layout.addStretch()
        input_row.addLayout(action_layout)

        input_widget = QWidget()
        input_widget.setLayout(input_row)
        self._wish_input_widget = input_widget

        input_stack = QWidget()
        input_stack_layout = QVBoxLayout(input_stack)
        input_stack_layout.setContentsMargins(0, 0, 0, 0)
        input_stack_layout.setSpacing(4)
        input_stack_layout.addWidget(self._attachment_bar)
        input_stack_layout.addWidget(input_widget)

        left_col = QSplitter(Qt.Orientation.Vertical)
        left_col.setContentsMargins(0, 0, 0, 0)
        left_col.addWidget(chat_container)
        left_col.addWidget(input_stack)
        left_col.setStretchFactor(0, 1)
        left_col.setStretchFactor(1, 0)
        left_col.setCollapsible(0, False)
        left_col.setCollapsible(1, False)
        left_col.setSizes([520, 150])

        self.wish_splitter = QSplitter(Qt.Orientation.Horizontal)
        self.wish_splitter.setContentsMargins(0, 0, 0, 0)
        self.wish_splitter.addWidget(left_col)
        self.wish_splitter.addWidget(self._result_frame)
        self.wish_splitter.setStretchFactor(0, 3)
        self.wish_splitter.setStretchFactor(1, 2)
        self.wish_splitter.setCollapsible(0, False)
        self.wish_splitter.setCollapsible(1, False)
        self.wish_splitter.setSizes([620, 420])
        self._wish_left_col = left_col

        layout.addLayout(progress_row)
        layout.addWidget(self.wish_splitter, 1)
        return widget

    def _on_result_toggle(self, expanded: bool) -> None:
        self._result_toggle.setText("收起" if expanded else "展开")
        self.wish_result_preview.setVisible(expanded)
        self.explain_group.setVisible(expanded and bool(self.explain_group.property("_has_text")))
        if expanded:
            self.wish_splitter.setSizes([520, 520])
        else:
            self.wish_splitter.setSizes([620, 420])

    # --- JSON independent window (Change 1) ------------------------------

    def _active_json_editor(self):
        return self.wish_json_edit if self._mode == "wish" else self.json_edit

    def _active_json_host(self):
        return self._wish_json_host if self._mode == "wish" else self._normal_json_host

    def _active_json_window_btn(self):
        return self._wish_json_window_btn if self._mode == "wish" else self._json_window_btn

    def _on_json_window_toggled(self, checked: bool) -> None:
        """Pop the active JSON editor into a non-modal independent window."""
        self._preview_coord.on_json_window_toggled(
            checked,
            self._active_json_editor(),
            self._active_json_host(),
            [self._json_window_btn, self._wish_json_window_btn],
            self._on_json_window_closed,
        )

    def _return_json_editor_to_host(self) -> None:
        self._preview_coord.return_json_editor_to_host(self._active_json_host())

    def _on_json_window_closed(self) -> None:
        self._preview_coord.close_json_window(self._active_json_host())
        for btn in (self._json_window_btn, self._wish_json_window_btn):
            btn.blockSignals(True)
            btn.setChecked(False)
            btn.blockSignals(False)

    def _open_json_window(self) -> None:
        btn = self._active_json_window_btn()
        if not btn.isChecked():
            btn.setChecked(True)

    def _close_json_window(self) -> None:
        self._preview_coord.close_json_window(self._active_json_host())

    def _result_summary_text(self, section: dict) -> str:
        units = section.get("units") or []
        n_units = len(units)
        n_lessons = sum(len(u.get("lessons") or []) for u in units if isinstance(u, dict))
        n_words = len(section.get("words") or [])
        return f"✓ 已生成 · {n_units} 单元 · {n_lessons} 课时 · {n_words} 词"

    # --- Mode switching ---------------------------------------------------

    def _apply_edit_mode_ui(self) -> None:
        if self._edit_mode is None:
            return
        scope = self._edit_mode.get("scope", "section")
        label = {
            "section": "应用编辑（Section）",
            "unit": "应用编辑（Unit）",
            "lesson": "应用编辑（Lesson）",
        }.get(scope, "应用编辑")
        self._button_box.button(QDialogButtonBox.StandardButton.Ok).setText(label)
        if hasattr(self, "normal_tabs") and hasattr(self, "_wizard_panel"):
            wizard_idx = self.normal_tabs.indexOf(self._wizard_panel)
            if wizard_idx >= 0:
                self.normal_tabs.setTabVisible(wizard_idx, False)

    # --- Wish expand / restore -------------------------------------------

    def _on_expand_toggled(self, expanded: bool) -> None:
        if expanded:
            self._open_chat_expand()
            self.expand_btn.setText("↕ 还原")
        else:
            self._close_chat_expand()
            self.expand_btn.setText("↕ 放大聊天")

    def _open_chat_expand(self) -> None:
        self._chat_coord.open_chat_expand(
            self,
            self._chat_palette(),
            self._on_expand_send,
            self._on_chat_expand_closed,
        )

    def _close_chat_expand(self) -> None:
        self._chat_coord.close_chat_expand()

    def _on_chat_expand_closed(self) -> None:
        self._chat_coord.on_chat_expand_closed(self.expand_btn)

    def _on_expand_send(self) -> None:
        win = self._chat_coord.chat_expand_window
        if win is None:
            return
        text = win.input_text().strip()
        if not text:
            return
        self.input_edit.setPlainText(text)
        win.clear_input()
        self._on_send_message()

    def _load_chat_expand_geometry(self) -> None:
        if self._chat_coord.chat_expand_window is not None:
            self._chat_coord._load_chat_expand_geometry(self._chat_coord.chat_expand_window)

    def _save_chat_expand_geometry(self, win: Any) -> None:
        self._chat_coord._save_chat_expand_geometry(win)

    def config(self) -> AiApiConfig:
        return self._config

    def _on_mode_changed(self, index: int) -> None:
        self._mode = self.mode_combo.itemData(index) or "normal"
        self._update_mode_ui()

    def _update_mode_ui(self) -> None:
        is_normal = self._mode == "normal"
        self._normal_panel.setVisible(is_normal)
        self._wish_panel.setVisible(not is_normal)
        self._place_template_bar(is_normal)
        self._sync_json_window_on_mode_switch()
        self._button_box.button(QDialogButtonBox.StandardButton.Ok).setEnabled(
            self._generated is not None
        )
        self._button_box.button(QDialogButtonBox.StandardButton.Ok).setText("导入到课程")

    def _sync_json_window_on_mode_switch(self) -> None:
        win = self._preview_coord.json_window
        if win is None:
            return
        prev = win.release_editor()
        if prev is not None:
            if prev is self.wish_json_edit:
                self._wish_json_host.addWidget(prev)
            else:
                self._normal_json_host.addWidget(prev)
            prev.setVisible(True)
        active = self._active_json_editor()
        if active is not None:
            win.host_editor(active)
            active.setVisible(True)

    def _place_template_bar(self, is_normal: bool) -> None:
        bar = getattr(self, "_template_bar", None)
        if bar is None:
            return
        target = self._normal_template_slot if is_normal else self._wish_template_slot
        for slot in (self._normal_template_slot, self._wish_template_slot):
            if slot is target:
                continue
            for i in range(slot.count()):
                if slot.itemAt(i).widget() is bar:
                    slot.takeAt(i)
                    break
        if not self._bar_in_slot(target, bar):
            target.addWidget(bar)

    @staticmethod
    def _bar_in_slot(slot, bar) -> bool:
        for i in range(slot.count()):
            if slot.itemAt(i).widget() is bar:
                return True
        return False

    def _current_topic_text(self) -> str:
        if self._mode == "normal":
            return self.topic_edit.text()
        for msg in reversed(self._messages):
            if msg.role == "user":
                content = msg.content
                if isinstance(content, str):
                    return content
                if isinstance(content, list):
                    return " ".join(
                        str(p.get("text", ""))
                        for p in content
                        if isinstance(p, dict) and p.get("type") == "text"
                    )
        return ""

    def _update_input_placeholders(self) -> None:
        self._template_bar.update_placeholders(
            topic_edit=getattr(self, "topic_edit", None),
            input_edit=getattr(self, "input_edit", None),
        )

    def _on_topic_text_changed(self, text: str) -> None:
        if not self.genre_switch.isChecked():
            return
        self._sync_template_from_genre_tags()

    def _sync_template_from_genre_tags(self) -> None:
        if not self.genre_switch.isChecked():
            return
        combined = f"{self._current_topic_text()} {self.extra_edit.text()}"
        tags = genre_tags_in_text(combined)
        self._template_bar.set_template_by_tags(tags, genre_to_template)

    def _set_template_combo(self, template: str) -> None:
        self._template_bar.select_template(template)

    def _ensure_api_configured(self) -> bool:
        if self._config.is_complete and _is_valid_http_url(self._config.base_url):
            return True
        QMessageBox.warning(
            self,
            "API 未配置",
            "请先点击工具栏「设置」，在「AI 配置」中填写 Base URL、API Key 和 Model，"
            "然后再使用 AI 功能。",
        )
        return False

    def _update_api_status(self) -> None:
        ok_color = self._pal("success", "#27AE60")
        err_color = self._pal("error", "#E74C3C")
        if self._config.is_complete and _is_valid_http_url(self._config.base_url):
            self.api_status.setText(f"<font color='{ok_color}'>已配置: {self._config.model}</font>")
        elif self._config.base_url or self._config.api_key or self._config.model:
            self.api_status.setText(f"<font color='{err_color}'>配置不完整</font>")
        else:
            self.api_status.setText(f"<font color='{err_color}'>未配置</font>")

    def _reconnect(self, btn, slot) -> None:
        try:
            btn.clicked.disconnect()
        except RuntimeError:
            logger.debug("dialogs/ai_generator_dialog.py:reconnect best-effort step failed", exc_info=True)
        btn.clicked.connect(slot)

    def _set_busy(self, busy: bool, normal: bool = False, stage: str = "") -> None:
        if stage:
            self._set_stage_label(stage)
        if normal:
            self._busy_normal = busy
            if busy:
                self.generate_btn.setText("取消生成")
                self.generate_btn.setToolTip("中断当前生成请求")
                self._reconnect(self.generate_btn, self._cancel_current_worker)
                self.progress.setVisible(True)
            else:
                self.generate_btn.setText("生成课程")
                self.generate_btn.setToolTip("按主题和规格直接生成 JSON")
                self._reconnect(self.generate_btn, self._on_generate_normal)
                self.progress.setVisible(False)
            self.validate_btn.setEnabled(not busy)
            self.reset_btn.setEnabled(not busy and self._generated is not None)
        else:
            self._busy_wish = busy
            if busy:
                self.send_btn.setText("取消")
                self.send_btn.setToolTip("中断当前请求")
                self._reconnect(self.send_btn, self._cancel_current_worker)
                self.wish_btn.setEnabled(False)
                self.attach_btn.setEnabled(False)
                self.wish_progress.setVisible(True)
            else:
                self.send_btn.setText("发送")
                self.send_btn.setToolTip("Ctrl+Enter 快捷发送")
                self._reconnect(self.send_btn, self._on_send_message)
                self.wish_btn.setEnabled(True)
                self.attach_btn.setEnabled(True)
                self.wish_progress.setVisible(False)
            self.input_edit.setEnabled(not busy)
        win = self._chat_coord.chat_expand_window
        if win is not None and win.isVisible():
            win.set_busy(busy and not normal)

    def _set_stage_label(self, stage: str) -> None:
        if hasattr(self, "stage_label"):
            self.stage_label.setText(stage)
            self.stage_label.setVisible(bool(stage))
        if hasattr(self, "wish_stage_label"):
            self.wish_stage_label.setText(stage)
            self.wish_stage_label.setVisible(bool(stage))
        win = self._chat_coord.chat_expand_window
        if win is not None and win.isVisible():
            win.set_stage(stage)

    # --- Streaming chunk + usage display --------------------------------

    def _current_usage_label(self) -> QLabel:
        return self.wish_usage_label if self._mode == "wish" else self.usage_label

    def _on_worker_chunk(self, fragment: str) -> None:
        self._worker_hub.on_worker_chunk(fragment)

    def _on_chunk_rendered(self, text: str, final: bool) -> None:
        n = len(text)
        if self._mode == "wish":
            if self._stream_target == "explain":
                if not final and n > self._STREAM_TEXT_LIVE_LIMIT:
                    self.explain_label.setPlainText(f"解释生成中… 已接收约 {n} 字符")
                else:
                    self.explain_label.setHtml(_escape_html(text))
                self.explain_group.setProperty("_has_text", True)
                self.explain_group.setVisible(self._result_toggle.isChecked())
            elif self._stream_target == "alignment":
                self._render_streaming_chat(text)
        else:
            if not final and n > self._STREAM_TEXT_LIVE_LIMIT:
                self.stage_label.setText(f"生成中… 已接收约 {n} 字符")
                self.stage_label.setVisible(True)
            else:
                self.json_edit.setPlainText(text)

    def _flush_stream_view(self, final: bool = False) -> None:
        self._worker_hub._flush_stream_view(final=final)

    def _render_streaming_chat(self, partial_text: str) -> None:
        self.chat_view.render_streaming(self._messages, partial_text, self._chat_palette())
        self._chat_coord.render_streaming_expand_chat(partial_text)

    def _sync_expand_chat(self) -> None:
        self._chat_coord.sync_expand_chat()

    def _on_worker_usage(self, usage: object) -> None:
        model = self._config.model if self._config is not None else ""
        self._worker_hub.on_worker_usage(usage, model)

    def _on_usage_updated(self, line: str, usage_dict: dict) -> None:
        label = self._current_usage_label()
        label.setText(line)
        label.setVisible(bool(line) and line != "≈ 0 tokens")
        win = self._chat_coord.chat_expand_window
        if win is not None and win.isVisible():
            win.set_usage(line)

    def _begin_stream(self, target: str) -> None:
        self._worker_hub.begin_stream(target)

    def _finish_stream(self) -> None:
        self._worker_hub.finish_stream()

    def _duration_since_request_start(self) -> float:
        return self._worker_hub.duration_since_request_start()

    def _cancel_current_worker(self) -> None:
        self._worker_hub.cancel_current_worker()

    def _disconnect_worker_signals(self, worker: AiRequestWorker | None) -> None:
        self._worker_hub.disconnect_worker_signals(worker)

    def _register_worker(self, worker: AiRequestWorker) -> None:
        self._worker_hub.register_worker(worker)

    def _forget_worker(self) -> None:
        self._worker_hub._forget_worker()

    def _on_worker_error(self, message: str) -> None:
        if self._closing:
            return
        self._set_busy(False, normal=self._busy_normal)
        self._set_stage_label("")
        cancelled = self._worker_hub.handle_worker_error(message, self._mode, self)
        if cancelled:
            self.statusMessage = message

    def _offer_error_analysis(self, message: str, context: dict[str, Any]) -> None:
        self._worker_hub.offer_error_analysis(self, message, context)

    def _current_spec(self) -> AiCourseSpec:
        spec = AiCourseSpec(
            language=self.language_edit.text().strip() or "Turkish",
            source_language=self.source_language_edit.text().strip() or "Chinese",
            topic=self._current_topic_text().strip(),
            level=self.level_combo.currentText(),
            unit_count=self.unit_spin.value(),
            lessons_per_unit=self.lessons_spin.value(),
            template=self._template_bar.selected_template(),
            use_genre_batch=self._template_bar.is_genre_enabled(),
            extra_instructions=self.extra_edit.text().strip(),
        )
        if spec.use_genre_batch:
            spec = apply_genre_to_spec(spec)
        return spec

    def _course_resource_summary(self) -> dict[str, list] | None:
        if self.adapter is None:
            return None
        summary = {
            "words": [
                w for w in (self.adapter.vocab or []) if isinstance(w, dict)
            ][:200],
            "expressions": [
                e for e in (self.adapter.expressions or []) if isinstance(e, dict)
            ][:100],
            "grammarPoints": [
                g for g in (self.adapter.grammar_points or []) if isinstance(g, dict)
            ][:50],
        }
        if not any(summary.values()):
            return None
        return summary

    def _apply_prompt_fields(self, obj) -> None:
        self.topic_edit.setText(obj.topic)
        self.level_combo.setCurrentText(obj.level)
        self.unit_spin.setValue(obj.unit_count)
        self.lessons_spin.setValue(obj.lessons_per_unit)
        self._template_bar.select_template(obj.template)
        self._template_bar.set_genre_enabled(obj.use_genre_batch)
        self.extra_edit.setText(obj.extra_instructions)

    def _on_template_applied(self, obj: object) -> None:
        if isinstance(obj, dict) and obj.get("action") == "save_request":
            name = obj.get("name", "")
            if name:
                self._template_bar.save_current_template(self._current_spec())
            return
        if isinstance(obj, AiPromptTemplate):
            self._apply_prompt_fields(obj)

    def _on_history_applied(self, entry: object) -> None:
        if isinstance(entry, AiPromptHistory):
            self._apply_prompt_fields(entry)

    # --- Normal mode actions ---------------------------------------------

    def _ai_retry_max(self) -> int:
        try:
            s = self._runtime.settings()
            return max(0, min(5, getattr(s, "ai_retry_max", 1)))
        except Exception:
            return 1

    def _ai_generation_kwargs(self) -> dict[str, Any]:
        try:
            s = self._runtime.settings()
            timeout = float(getattr(s, "ai_timeout", 120.0))
            temperature = float(getattr(s, "ai_temperature", 0.7))
        except Exception:
            timeout = 120.0
            temperature = 0.7
        return {"timeout": timeout, "temperature": temperature}

    def _make_edit_worker(self, spec: AiCourseSpec, **kwargs: Any) -> AiRequestWorker:
        instruction = None
        if hasattr(self, "edit_instruction_input"):
            instruction = self.edit_instruction_input.toPlainText().strip() or None
        return self._worker_hub.make_edit_worker(
            self._config, spec, self._edit_mode, instruction=instruction, **kwargs
        )

    def _on_generate_normal(self) -> None:
        topic = self.topic_edit.text().strip()
        if not topic:
            QMessageBox.warning(self, "缺少主题", "请先填写课程主题。")
            return
        if not self._ensure_api_configured():
            return
        if self._current_worker is not None and self._current_worker.isRunning():
            return

        self._request_start = time.perf_counter()
        telemetry.record_event("ai.generate.start", payload={"mode": "normal", "edit_mode": self._edit_mode is not None})
        spec = self._current_spec()
        if self._edit_mode is None:
            spec.course_resources = self._course_resource_summary()
        self._template_bar.record_history(spec)
        kwargs = self._ai_generation_kwargs()
        if self._edit_mode is not None:
            worker = self._make_edit_worker(spec, **kwargs)
        else:
            validator = self.adapter.validate_section_json
            worker = AiRequestWorker(
                request_course_with_retry,
                self._config,
                spec,
                validator,
                max_retries=self._ai_retry_max(),
                **kwargs,
            )
        worker.result_ready.connect(self._on_normal_generation_ready)
        worker.error_occurred.connect(self._on_worker_error)
        worker.chunk_ready.connect(self._on_worker_chunk)
        worker.usage_ready.connect(self._on_worker_usage)
        worker.completed.connect(self._on_normal_worker_done)
        self._begin_stream("json")
        self._register_worker(worker)
        self._set_busy(True, normal=True, stage="生成中（流式）…")
        worker.start()

    def _on_normal_generation_ready(self, parsed: object) -> None:
        if self._closing:
            return
        duration_ms = self._duration_since_request_start()
        telemetry.record_duration(
            "ai.generate",
            duration_ms,
            payload={"mode": "normal", "success": True, "edit_mode": self._edit_mode is not None},
        )
        _record_cache_stats()
        if (
            self._edit_mode is not None
            and isinstance(parsed, dict)
            and isinstance(self._edit_mode.get("existing_section"), dict)
        ):
            diff = structural_diff(self._edit_mode["existing_section"], parsed)
            removed_only = {
                k: v
                for k, v in diff.items()
                if k.startswith("removed_") and v
            }
            if removed_only and not self._confirm_structural_removal(diff):
                self._set_busy(False, normal=True, stage="")
                self._finish_stream()
                self._request_start = None
                return
        self._generated = parsed
        self.json_edit.set_json(parsed)
        self.reset_btn.setEnabled(True)
        if isinstance(parsed, dict):
            self.result_preview.show_section(parsed)
            self.result_preview.setVisible(True)
        self.try_btn.setVisible(isinstance(parsed, dict))
        self.diff_btn.setVisible(
            isinstance(parsed, dict)
            and self._edit_mode is not None
            and isinstance(self._edit_mode.get("existing_section"), dict)
        )
        self._update_mode_ui()

    def _confirm_structural_removal(self, diff: dict[str, set[str]]) -> bool:
        return confirm_structural_removal(self, diff)

    def _on_normal_worker_done(self) -> None:
        if self._closing:
            return
        self._set_busy(False, normal=True, stage="")
        self._finish_stream()
        self._request_start = None

    def _on_preview_validity(self, ok: bool) -> None:
        if self._generated is not None:
            self._button_box.button(QDialogButtonBox.StandardButton.Ok).setEnabled(ok)

    def _on_reset(self) -> None:
        if self._generated is not None:
            self._active_json_editor().set_json(self._generated)

    def _on_view_diff(self) -> None:
        if self._edit_mode is None or not isinstance(self._edit_mode.get("existing_section"), dict):
            return
        try:
            generated = self._current_json()
        except ValueError:
            return
        view_section_diff(self, self._edit_mode["existing_section"], generated)

    def _on_try_preview(self) -> None:
        try:
            section = self._current_json()
        except ValueError as exc:
            QMessageBox.warning(self, "无法试做", str(exc))
            return
        try_preview_lesson(self, self.adapter, section)

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

    def _on_validate_from_editor(self) -> None:
        try:
            data = self._current_json()
        except ValueError as exc:
            QMessageBox.warning(self, "JSON 无效", str(exc))
            return
        preview = self.wish_result_preview if self._mode == "wish" else self.result_preview
        preview.show_section(data)
        preview._on_validate()

    def _current_json(self) -> dict:
        editor = self.wish_json_edit if self._mode == "wish" else self.json_edit
        raw = editor.toPlainText().strip()
        if not raw:
            raise ValueError("尚未生成课程。" if self._mode == "wish" else "JSON 为空。")
        try:
            data = json.loads(raw)
        except json.JSONDecodeError as exc:
            editor.mark_error(getattr(exc, "lineno", 1) or 1, str(exc))
            raise ValueError(f"JSON 解析失败: {exc}") from exc
        if not isinstance(data, dict) or "units" not in data:
            raise ValueError("JSON 必须是包含 'units' 数组的对象。")
        return data

    def _on_preview_node_activated(self, path: str) -> None:
        jump_editor_to_path(self._active_json_editor(), path)

    def _find_line_for_path(self, text: str, path: str) -> int | None:
        return find_line_for_path(text, path)

    # --- Wish mode actions -----------------------------------------------

    def _chat_palette(self) -> dict[str, str]:
        try:
            from src.theme import current_palette
            return current_palette()
        except Exception:
            return _CHAT_PALETTE

    def _pal(self, key: str, fallback: str) -> str:
        try:
            from src.theme import current_palette
            return current_palette().get(key, fallback)
        except Exception:
            return fallback

    def _render_chat(self) -> None:
        self.chat_view.render(self._messages, self._chat_palette())
        self._sync_expand_chat()

    def _input_key_press(self, event: Any) -> None:
        self._chat_coord.handle_input_key_press(
            event, self.input_edit, self._on_send_message, self._enter_to_send.isChecked()
        )

    def _on_send_message(self) -> None:
        text = self.input_edit.toPlainText().strip()
        if not text and not self._attachments:
            return
        if not self._ensure_api_configured():
            return
        if self._current_worker is not None and self._current_worker.isRunning():
            return

        self._request_start = time.perf_counter()
        telemetry.record_event("ai.alignment.send", payload={"attachment_count": len(self._attachments)})
        if self.genre_switch.isChecked():
            tags = detect_genre_from_spec(
                AiCourseSpec(topic=text, extra_instructions="", use_genre_batch=True)
            )
            if tags:
                self._set_template_combo(genre_to_template(tags[0]))

        user_content: list[dict[str, Any]] = [{"type": "text", "text": text}]
        for att in self._attachments:
            user_content.append(att.content)
        self._messages.append(ChatMessage(role="user", content=user_content))
        self.input_edit.clear()
        self._attachment_bar.clear_attachments()
        self._render_chat()

        kwargs = self._ai_generation_kwargs()
        worker = AiRequestWorker(
            request_alignment_reply,
            self._config,
            self._current_spec(),
            self._messages,
            **kwargs,
        )
        worker.result_ready.connect(self._on_alignment_reply_ready)
        worker.error_occurred.connect(self._on_worker_error)
        worker.chunk_ready.connect(self._on_worker_chunk)
        worker.usage_ready.connect(self._on_worker_usage)
        worker.completed.connect(self._on_alignment_worker_done)
        self._begin_stream("alignment")
        self._register_worker(worker)
        self._set_busy(True, stage="对齐中…")
        worker.start()

    def _on_alignment_worker_done(self) -> None:
        if self._closing:
            return
        self._set_busy(False, stage="")
        self._finish_stream()
        self._request_start = None

    def _on_alignment_reply_ready(self, reply: object) -> None:
        if self._closing:
            return
        duration_ms = self._duration_since_request_start()
        telemetry.record_duration(
            "ai.alignment",
            duration_ms,
            payload={"success": True},
        )
        self._messages.append(ChatMessage(role="assistant", content=str(reply)))
        self._render_chat()

    def _add_attachment_paths(self, paths: list[Path]) -> None:
        self._chat_coord.add_attachment_paths(paths, self._attachment_bar, self)

    def _on_attach_files(self) -> None:
        paths, _filter = QFileDialog.getOpenFileNames(
            self,
            "选择附件",
            "",
            "支持的文件 (*.png *.jpg *.jpeg *.gif *.webp *.pdf *.doc *.docx *.txt *.md *.csv *.json *.yaml *.yml);;所有文件 (*)",
        )
        if paths:
            self._add_attachment_paths([Path(p) for p in paths])

    def _on_attachments_changed(self) -> None:
        self._chat_coord.sync_attachments(self._attachment_bar)

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

        self._request_start = time.perf_counter()
        telemetry.record_event("ai.generate.start", payload={"mode": "wish", "edit_mode": self._edit_mode is not None})
        spec = self._current_spec()
        self._template_bar.record_history(spec)
        kwargs = self._ai_generation_kwargs()
        if self._edit_mode is not None:
            worker = AiRequestWorker(
                generate_edit,
                self._config,
                spec,
                self._edit_mode["existing_section"],
                self._edit_mode.get("scope", "section"),
                self._edit_mode.get("scope_id", ""),
                self._messages,
                self._draft_json,
                **kwargs,
            )
        else:
            worker = AiRequestWorker(
                generate_from_chat,
                self._config,
                spec,
                self._messages,
                draft_json=self._draft_json,
                **kwargs,
            )
        worker.result_ready.connect(self._on_wish_generation_ready)
        worker.error_occurred.connect(self._on_worker_error)
        worker.chunk_ready.connect(self._on_worker_chunk)
        worker.usage_ready.connect(self._on_worker_usage)
        worker.completed.connect(lambda: None)
        self._begin_stream("json")
        self._register_worker(worker)
        self._set_busy(True, stage="生成中（流式）…")
        worker.start()

    def _on_wish_generation_ready(self, parsed: object) -> None:
        if self._closing:
            return
        duration_ms = self._duration_since_request_start()
        telemetry.record_duration(
            "ai.generate",
            duration_ms,
            payload={"mode": "wish", "success": isinstance(parsed, dict), "edit_mode": self._edit_mode is not None},
        )
        _record_cache_stats()
        self._generated = parsed
        self._draft_json = parsed

        if not isinstance(parsed, dict):
            self._set_busy(False)
            QMessageBox.critical(self, "生成失败", "模型返回了非预期的数据类型。")
            return

        self.wish_result_preview.show_section(parsed)
        self.wish_result_preview.setVisible(self._result_toggle.isChecked())
        self.wish_json_edit.set_json(parsed)
        self.wish_json_edit.setVisible(True)
        self._result_frame.setVisible(True)
        self._result_summary.setText(self._result_summary_text(parsed))
        self._wish_json_window_btn.setVisible(True)
        self._result_toggle.setChecked(False)
        self._open_json_window()

        self._finish_stream()
        self._request_start = time.perf_counter()
        kwargs = self._ai_generation_kwargs()
        worker = AiRequestWorker(
            explain_course, self._config, self._current_spec(), parsed, **kwargs
        )
        worker.result_ready.connect(self._on_explain_ready)
        worker.error_occurred.connect(self._on_explain_error)
        worker.chunk_ready.connect(self._on_worker_chunk)
        worker.usage_ready.connect(self._on_worker_usage)
        worker.completed.connect(self._on_explain_worker_done)
        self._begin_stream("explain")
        self._register_worker(worker)
        self._set_busy(True, stage="通俗解释中…")
        worker.start()

    def _on_explain_worker_done(self) -> None:
        if self._closing:
            return
        self._set_busy(False, stage="")
        self._finish_stream()
        self._request_start = None

    def _on_explain_ready(self, explanation: object) -> None:
        if self._closing:
            return
        telemetry.record_event("ai.explain.done", payload={"mode": "wish"})
        text = str(explanation)
        safe = _escape_html(text)
        self.explain_label.setHtml(safe)
        self.explain_group.setProperty("_has_text", True)
        if not self._result_toggle.isChecked():
            self._result_toggle.setChecked(True)
        else:
            self.explain_group.setVisible(True)
        self._update_mode_ui()

        QMessageBox.information(
            self,
            "生成完成",
            "课程已生成。点击「导入到课程」将其加入左侧课程树，或继续对话修改。",
        )

    def _on_explain_error(self, message: str) -> None:
        if self._closing:
            return
        telemetry.record_event(
            "ai.explain.error",
            payload={"mode": "wish", "error": message},
        )
        self._set_busy(False)
        self._set_stage_label("")
        self.explain_group.setProperty("_has_text", False)
        self.explain_label.setHtml(
            f"<font color='#E74C3C'>解释生成失败：{message}</font>"
        )
        msg = QMessageBox(self)
        msg.setIcon(QMessageBox.Icon.Warning)
        msg.setWindowTitle("解释失败")
        msg.setText(
            "课程 JSON 已生成，但 AI 解释未能生成。\n\n"
            f"错误：{message}\n\n"
            "您可以直接导入课程，或重试生成解释。"
        )
        retry_btn = msg.addButton("重试解释", QMessageBox.ButtonRole.ActionRole)
        analyze_btn = msg.addButton("AI 分析原因", QMessageBox.ButtonRole.ActionRole)
        msg.addButton("关闭", QMessageBox.ButtonRole.RejectRole)
        msg.exec()
        clicked = msg.clickedButton()
        if clicked == retry_btn:
            self._on_wish_generate()
        elif clicked == analyze_btn:
            self._offer_error_analysis(
                message, context={"action": "ai.explain", "mode": "wish"}
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
        else:
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

        problems = self.adapter.validate_section_json(
            data, check_existing_ids=False
        )
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
        self._chat_coord.cleanup_attachments(self._attachment_bar)
        self._chat_coord.close_chat_expand()
        self._chat_coord.chat_expand_window = None

    def reject(self) -> None:
        self._closing = True
        self._cancel_current_worker()
        self._disconnect_worker_signals(self._current_worker)
        self._close_json_window()
        self._cleanup_attachments()
        super().reject()

    def accept(self) -> None:
        self._closing = True
        self._cancel_current_worker()
        self._disconnect_worker_signals(self._current_worker)
        self._close_json_window()
        self._cleanup_attachments()
        super().accept()

    def closeEvent(self, event) -> None:  # noqa: N802
        self._closing = True
        self._cancel_current_worker()
        self._disconnect_worker_signals(self._current_worker)
        self._close_json_window()
        self._cleanup_attachments()
        super().closeEvent(event)

    # --- Public accessors ------------------------------------------------

    def section_json(self) -> dict:
        """Return the (possibly edited) section dict to import."""
        return self._current_json()
