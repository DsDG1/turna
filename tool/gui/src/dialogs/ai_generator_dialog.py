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
import time
import uuid
from pathlib import Path
from typing import Any

from PySide6.QtCore import Qt, QSize, QTimer
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
    QListWidget,
    QListWidgetItem,
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

from src.app import current_ai_config, current_settings
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
from src.backend.attachment_extractor import extract_attachment
from src.dialogs.ai.attachment_bar import AttachmentBar
from src.dialogs.ai.worker import (
    AttachmentRecord as _AttachmentRecord,
    AiRequestWorker,
    is_valid_http_url as _is_valid_http_url,
)
from src.dialogs.ai.chat_view import (
    DEFAULT_PALETTE as _CHAT_PALETTE,
    ChatView,
    escape_html as _escape_html,
)
from src.dialogs.ai.prompt_template_bar import PromptTemplateBar
from src.infrastructure.telemetry import telemetry
from src.theme_tokens import BRAND_REED, BRAND_TEAL, BRAND_TEAL_DARK
from src.widgets.json_editor import JsonEditor


def _record_cache_stats() -> None:
    """第三枪 批次① Step 9: record AI cache stats to telemetry after each request.

    Records ``ai.cache.stats`` with hits/misses/entries so cache effectiveness
    is visible in the telemetry log. No-op when no default cache is configured.
    """
    from src.backend.ai_cache import get_default_cache

    cache = get_default_cache()
    if cache is not None:
        telemetry.record_event("ai.cache.stats", payload=cache.stats().as_dict())


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
    ) -> None:
        super().__init__(parent)
        self.adapter = adapter
        self._edit_mode = edit_mode
        self.setWindowTitle("AI 编辑" if edit_mode is not None else "AI 生成课程")
        self.resize(1180, 860)
        self.setMinimumSize(QSize(900, 640))
        self.setAcceptDrops(True)
        # API config is managed centrally in the Settings panel and held in
        # memory by MainWindow. Dialogs must not maintain their own input fields.
        self._config = current_ai_config()
        self._generated: dict | None = None
        self._mode = "normal"
        self._normal_tab = "topic"

        self._messages: list[ChatMessage] = []
        self._attachments: list[_AttachmentRecord] = []
        self._prompt_library = prompt_library()
        self._draft_json: dict | None = None
        self._current_worker: AiRequestWorker | None = None
        self._busy_normal = False
        self._busy_wish = False
        self._chat_expand: QWidget | None = None
        self._json_window: QWidget | None = None
        # Set True during reject()/closeEvent() so worker slots can bail out
        # instead of touching destroyed widgets. (B6)
        self._closing = False
        # ``_request_start`` is reset to a fresh perf_counter() before each
        # worker starts and cleared to ``None`` after it finishes (B7 fix),
        # so duration measurements never inherit a stale timestamp.
        self._request_start: float | None = None
        # Streaming scratch state: ``_stream_buffer`` accumulates fragments,
        # ``_stream_target`` is "alignment" / "explain" / "json" so the chunk
        # handler knows where to render. View updates are throttled via
        # ``_stream_flush_timer`` (per-chunk full-document rewrites are O(n^2)).
        self._stream_buffer = ""
        self._stream_target: str | None = None
        self._stream_dirty = False
        self._stream_flush_timer = QTimer(self)
        self._stream_flush_timer.setSingleShot(True)
        self._stream_flush_timer.setInterval(120)
        self._stream_flush_timer.timeout.connect(self._flush_stream_view)

        self._build_ui()
        self._update_api_status()
        self._apply_edit_mode_ui()

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

        # Build the single shared template bar once (B8); it is reparented
        # into the active panel by _update_mode_ui.
        self._build_template_selector()
        self._template_bar.set_library(self._prompt_library)
        self._template_bar.template_applied.connect(self._on_template_applied)
        self._template_bar.history_applied.connect(self._on_history_applied)
        # Wire topic/extra text changes to genre-tag sync.
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
        """Keyboard tab order for the wish-mode input cluster (P5.6)."""
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
        """Return the single shared template/genre selector (B8 fix).

        Created once and cached on ``self._template_bar``; subsequent calls
        (from the wish panel) return the same instance. Reparenting happens in
        ``_update_mode_ui`` so the bar lives in whichever panel is visible —
        it is never rebuilt, so template/genre state stays global and unique.
        """
        if getattr(self, "_template_bar", None) is not None:
            return self._template_bar
        bar = PromptTemplateBar()
        bar.template_changed.connect(self._on_template_changed_value)
        bar.genre_toggled.connect(self._on_genre_toggled)
        self._template_bar = bar
        # Backwards-compat attributes used elsewhere in this class.
        self.template_combo = bar.template_combo
        self._template_cards = bar._template_cards
        self.genre_switch = bar.genre_switch
        return bar

    def _on_template_changed_value(self, template: str) -> None:
        """React to a template change from the shared bar (replaces combo index)."""
        self._update_input_placeholders()

    def _on_genre_toggled(self, enabled: bool) -> None:
        """React to the genre-batch toggle from the shared bar."""
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
        # Change 1: 2-column layout — input tabs on the left, result preview +
        # JSON on the right (JSON can further pop out into its own window).
        self._normal_splitter = QSplitter(Qt.Horizontal)
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
        # The template bar slot is filled by _update_mode_ui (single shared
        # instance reparented between panels — B8 fix).
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
        """Guided lesson creation that does not consume AI tokens."""
        from PySide6.QtCore import Qt

        widget = QWidget()
        layout = QVBoxLayout(widget)
        layout.setSpacing(12)
        layout.setContentsMargins(0, 0, 0, 0)

        layout.addWidget(QLabel("<b>向导生成：从词库选题自动生成 intro 课程</b>"))

        form = QFormLayout()
        self.wizard_name_edit = QLineEdit()
        self.wizard_name_edit.setPlaceholderText("如：问候语")
        self.wizard_desc_edit = QLineEdit()
        self.wizard_desc_edit.setPlaceholderText("一句话说明这节课学什么")
        form.addRow("名称:", self.wizard_name_edit)
        form.addRow("描述:", self.wizard_desc_edit)
        layout.addLayout(form)

        layout.addWidget(QLabel("选择要教学的词："))
        self.wizard_word_list = QListWidget()
        for wid, label in self.adapter.vocab_options():
            item = QListWidgetItem(label)
            item.setData(Qt.ItemDataRole.UserRole, wid)
            item.setFlags(item.flags() | Qt.ItemFlag.ItemIsUserCheckable)
            item.setCheckState(Qt.CheckState.Unchecked)
            self.wizard_word_list.addItem(item)
        layout.addWidget(self.wizard_word_list)

        self.wizard_summary = QLabel("已选 0 个词")
        self.wizard_summary.setStyleSheet(
            f"color: {self._pal('text_secondary', '#9CA3AF')};"
        )
        layout.addWidget(self.wizard_summary)
        self.wizard_word_list.itemChanged.connect(self._update_wizard_summary)

        self.wizard_generate_btn = QPushButton("生成课程")
        self.wizard_generate_btn.clicked.connect(self._on_wizard_generate)
        layout.addWidget(self.wizard_generate_btn)
        layout.addStretch()
        return widget

    def _update_wizard_summary(self, _item: "QListWidgetItem") -> None:
        n = sum(
            1
            for i in range(self.wizard_word_list.count())
            if self.wizard_word_list.item(i).checkState() == Qt.CheckState.Checked
        )
        self.wizard_summary.setText(f"已选 {n} 个词，将生成 {n} 个教学环节")

    def _selected_wizard_words(self) -> list[dict[str, Any]]:
        ids = {
            self.wizard_word_list.item(i).data(Qt.ItemDataRole.UserRole)
            for i in range(self.wizard_word_list.count())
            if self.wizard_word_list.item(i).checkState() == Qt.CheckState.Checked
        }
        return [w for w in self.adapter.vocab if w.get("id") in ids]

    def _on_wizard_generate(self) -> None:
        from src.backend.lesson_content import build_intro_lesson

        words = self._selected_wizard_words()
        if not words:
            self.wizard_summary.setText("⚠️ 请至少选择 1 个词")
            self.wizard_summary.setStyleSheet(f"color: {self._pal('error', '#E74C3C')};")
            return
        lesson = build_intro_lesson(
            self.wizard_name_edit.text().strip(),
            self.wizard_desc_edit.text().strip(),
            words,
        )
        # Wrap the lesson in a single-unit section so the dialog's import path
        # can treat wizard output the same as AI-generated output.
        section = {
            "id": f"wizard-{lesson.get('id', 'lesson')}",
            "name": lesson.get("name", "向导课程"),
            "description": lesson.get("description", ""),
            "prerequisiteSectionIds": [],
            "words": [],
            "expressions": [],
            "grammarPoints": [],
            "units": [
                {
                    "id": f"wizard-{lesson.get('id', 'lesson')}-u1",
                    "name": "Unit 1",
                    "description": "",
                    "prerequisiteUnitIds": [],
                    "lessons": [lesson],
                }
            ],
        }
        self._generated = section
        self.json_edit.setPlainText(json.dumps(section, ensure_ascii=False, indent=2))
        self.reset_btn.setEnabled(False)
        self.result_preview.show_section(section)
        self.result_preview.setVisible(True)
        self._update_mode_ui()
        telemetry.record_event("ai.wizard.generate", payload={"lesson_id": lesson.get("id", "")})

    def _on_normal_tab_changed(self, index: int) -> None:
        self._normal_tab = "topic" if index == 0 else "wizard"

    def _build_topic_row(self) -> QWidget:
        widget = QWidget()
        layout = QHBoxLayout(widget)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(8)

        self.topic_edit = QLineEdit()
        self.topic_edit.setPlaceholderText("例如：旅行词汇 [intro]")
        # textChanged is wired once in __init__ (together with extra_edit).
        layout.addWidget(QLabel("主题:"))
        layout.addWidget(self.topic_edit, 1)

        self.generate_btn = QPushButton("生成课程")
        self.generate_btn.setToolTip("按主题和规格直接生成 JSON")
        self.generate_btn.clicked.connect(self._on_generate_normal)
        layout.addWidget(self.generate_btn)
        return widget

    def _build_result_group(self) -> QGroupBox:
        from src.widgets.result_preview import ResultPreviewWidget

        grp = QGroupBox("生成结果（可编辑 JSON）")
        layout = QVBoxLayout(grp)
        layout.setSpacing(8)
        self.result_preview = ResultPreviewWidget(self.adapter, grp)
        self.result_preview.setVisible(False)
        self.result_preview.validity_changed.connect(self._on_preview_validity)
        # Override the preview's validate button so it validates the JSON
        # currently in the editor (which the user may have edited), not a
        # stale cached copy.
        self.result_preview.validate_btn.clicked.disconnect()
        self.result_preview.validate_btn.clicked.connect(self._on_validate_from_editor)
        layout.addWidget(self.result_preview)
        self.json_edit = JsonEditor()
        self.json_edit.restyle(self._chat_palette())
        self.result_preview.node_activated.connect(self._on_preview_node_activated)
        # JSON editor lives in a dedicated host slot so it can be reparented
        # into the independent ResultExpandWindow (Change 1) without disturbing
        # the surrounding layout.
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

        # Template bar slot filled by _update_mode_ui (shared single instance).
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

        # --- progress row (sits above the chat, slim) -------------------
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

        # --- collapsible result summary (one-screen, P5.3) --------------
        # A frame whose collapsed state shows a single summary line and whose
        # expanded state reveals the structured preview + plain-language
        # explanation. Default collapsed so chat + input fit one screen.
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

        from src.widgets.result_preview import ResultPreviewWidget

        self.wish_result_preview = ResultPreviewWidget(self.adapter, widget)
        self.wish_result_preview.setVisible(False)
        self.wish_result_preview.validity_changed.connect(self._on_preview_validity)
        self.wish_result_preview.validate_btn.clicked.disconnect()
        self.wish_result_preview.validate_btn.clicked.connect(self._on_validate_from_editor)
        self.wish_result_preview.node_activated.connect(self._on_preview_node_activated)
        result_v.addWidget(self.wish_result_preview)

        # Wish-side JSON editor (P3.3 / B1): the single source of truth for the
        # imported JSON in wish mode. ``_current_json`` reads this, not _generated.
        # It lives in a dedicated host slot so it can be reparented into the
        # independent ResultExpandWindow (Change 1).
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

        # Wrap input row + attachment strip in one fixed-height container.
        input_stack = QWidget()
        input_stack_layout = QVBoxLayout(input_stack)
        input_stack_layout.setContentsMargins(0, 0, 0, 0)
        input_stack_layout.setSpacing(4)
        input_stack_layout.addWidget(self._attachment_bar)
        input_stack_layout.addWidget(input_widget)

        # --- left column: chat (grows) + input (fixed) -------------------
        left_col = QSplitter(Qt.Vertical)
        left_col.setContentsMargins(0, 0, 0, 0)
        left_col.addWidget(chat_container)
        left_col.addWidget(input_stack)
        left_col.setStretchFactor(0, 1)   # chat grows
        left_col.setStretchFactor(1, 0)   # input: fixed
        left_col.setCollapsible(0, False)
        left_col.setCollapsible(1, False)
        left_col.setSizes([520, 150])

        # --- 2-column horizontal splitter: chat+input | result -----------
        # Change 1: split the wish panel into two columns so the result preview
        # + explanation no longer crush the chat. The JSON editor itself lives
        # in the independent ResultExpandWindow (opened after generation).
        self.wish_splitter = QSplitter(Qt.Horizontal)
        self.wish_splitter.setContentsMargins(0, 0, 0, 0)
        self.wish_splitter.addWidget(left_col)
        self.wish_splitter.addWidget(self._result_frame)
        self.wish_splitter.setStretchFactor(0, 3)   # chat+input column grows
        self.wish_splitter.setStretchFactor(1, 2)   # result column
        self.wish_splitter.setCollapsible(0, False)
        self.wish_splitter.setCollapsible(1, False)
        self.wish_splitter.setSizes([620, 420])
        self._wish_left_col = left_col

        layout.addLayout(progress_row)
        layout.addWidget(self.wish_splitter, 1)

        return widget

    def _on_result_toggle(self, expanded: bool) -> None:
        """Expand/collapse the wish result preview + explanation (P5.3)."""
        self._result_toggle.setText("收起" if expanded else "展开")
        self.wish_result_preview.setVisible(expanded)
        # The explain group is shown only when there is an explanation AND expanded.
        self.explain_group.setVisible(expanded and bool(self.explain_group.property("_has_text")))
        # The JSON editor lives in its own host slot / independent window, so
        # the expanded sizes no longer need to reserve 300px for JSON — keep
        # the preview/explanation compact and leave room for the chat.
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
        from src.dialogs.ai.result_window import ResultExpandWindow

        # Keep both toggle buttons in sync (only the visible one is clickable,
        # but stay consistent on mode switch).
        for btn in (self._json_window_btn, self._wish_json_window_btn):
            btn.blockSignals(True)
            btn.setChecked(checked)
            btn.blockSignals(False)

        editor = self._active_json_editor()
        if checked:
            if self._json_window is None:
                self._json_window = ResultExpandWindow(self)
                self._json_window.finished.connect(self._on_json_window_closed)
            self._json_window.host_editor(editor)
            editor.setVisible(True)
            self._json_window.show()
            self._json_window.raise_()
            self._json_window.activateWindow()
        else:
            # Close the window; _on_json_window_closed reparents the editor back.
            self._close_json_window()

    def _return_json_editor_to_host(self) -> None:
        """Reparent the JSON editor back into its in-dialog host slot."""
        win = self._json_window
        if win is None:
            return
        editor = win.release_editor()
        if editor is not None:
            self._active_json_host().addWidget(editor)
            editor.setVisible(True)

    def _on_json_window_closed(self) -> None:
        """Window closed by the user → editor returns to the dialog, toggles reset."""
        self._return_json_editor_to_host()
        self._json_window = None
        for btn in (self._json_window_btn, self._wish_json_window_btn):
            btn.blockSignals(True)
            btn.setChecked(False)
            btn.blockSignals(False)

    def _open_json_window(self) -> None:
        """Programmatically open the JSON window (used after generation)."""
        btn = self._active_json_window_btn()
        if not btn.isChecked():
            btn.setChecked(True)  # triggers _on_json_window_toggled

    def _close_json_window(self) -> None:
        win = self._json_window
        if win is not None:
            self._return_json_editor_to_host()
            win.close()
            self._json_window = None

    def _result_summary_text(self, section: dict) -> str:
        """One-line collapsed summary: ✓ 已生成 · N 单元 · M 课时 · K 词."""
        units = section.get("units") or []
        n_units = len(units)
        n_lessons = sum(len(u.get("lessons") or []) for u in units if isinstance(u, dict))
        n_words = len(section.get("words") or [])
        return f"✓ 已生成 · {n_units} 单元 · {n_lessons} 课时 · {n_words} 词"

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
        # Wizard generation does not make sense in edit mode; hide the tab.
        if hasattr(self, "normal_tabs") and hasattr(self, "_wizard_panel"):
            wizard_idx = self.normal_tabs.indexOf(self._wizard_panel)
            if wizard_idx >= 0:
                self.normal_tabs.setTabVisible(wizard_idx, False)

    # --- Wish expand / restore -------------------------------------------

    def _on_expand_toggled(self, expanded: bool) -> None:
        """Open/close the enlarged chat sub-window (P5.5).

        The sub-window is a separate non-modal top-level with its own ChatView
        driven by the same ``_messages`` list; geometry is persisted to
        QSettings so restore is exact.
        """
        if expanded:
            self._open_chat_expand()
            self.expand_btn.setText("↕ 还原")
        else:
            self._close_chat_expand()
            self.expand_btn.setText("↕ 放大聊天")

    def _open_chat_expand(self) -> None:
        from src.dialogs.ai.chat_expand_window import ChatExpandWindow

        if getattr(self, "_chat_expand", None) is None:
            self._chat_expand = ChatExpandWindow(self._chat_palette(), self)
            self._chat_expand.send_requested.connect(self._on_expand_send)
            self._chat_expand.finished.connect(self._on_chat_expand_closed)
            self._load_chat_expand_geometry()
        win = self._chat_expand
        win.render(self._messages)
        win.show()
        win.raise_()
        win.activateWindow()

    def _close_chat_expand(self) -> None:
        win = getattr(self, "_chat_expand", None)
        if win is not None:
            self._save_chat_expand_geometry(win)
            win.close()

    def _on_chat_expand_closed(self) -> None:
        self._save_chat_expand_geometry(self._chat_expand)
        self.expand_btn.blockSignals(True)
        self.expand_btn.setChecked(False)
        self.expand_btn.setText("↕ 放大聊天")
        self.expand_btn.blockSignals(False)

    def _on_expand_send(self) -> None:
        """Mirror the expand window's input into the panel, then send."""
        win = getattr(self, "_chat_expand", None)
        if win is None:
            return
        text = win.input_text().strip()
        if not text:
            return
        self.input_edit.setPlainText(text)
        win.clear_input()
        self._on_send_message()

    def _load_chat_expand_geometry(self) -> None:
        from PySide6.QtCore import QSettings

        win = getattr(self, "_chat_expand", None)
        if win is None:
            return
        qs = QSettings("Turna", "CourseEditor")
        geo = qs.value("ai_chat_expand/geometry")
        if geo is not None:
            win.restoreGeometry(geo)
        if qs.value("ai_chat_expand/maximized", False) in (True, "true", "1"):
            win.showMaximized()

    def _save_chat_expand_geometry(self, win) -> None:
        from PySide6.QtCore import QSettings

        qs = QSettings("Turna", "CourseEditor")
        qs.setValue("ai_chat_expand/geometry", win.saveGeometry())
        qs.setValue("ai_chat_expand/maximized", win.isMaximized())

    def config(self) -> AiApiConfig:
        """Return the current API config sourced from the Settings panel."""
        return self._config

    def _on_mode_changed(self, index: int) -> None:
        self._mode = self.mode_combo.itemData(index) or "normal"
        self._update_mode_ui()

    def _update_mode_ui(self) -> None:
        is_normal = self._mode == "normal"
        self._normal_panel.setVisible(is_normal)
        self._wish_panel.setVisible(not is_normal)
        # Reparent the single shared template bar into the visible panel (B8).
        self._place_template_bar(is_normal)
        # Change 1: the JSON independent window hosts whichever editor is
        # active. On a mode switch, reparent the editor in the window (if open)
        # to the new active editor, and sync the in-panel toggle buttons.
        self._sync_json_window_on_mode_switch()
        self._button_box.button(QDialogButtonBox.StandardButton.Ok).setEnabled(
            self._generated is not None
        )
        self._button_box.button(QDialogButtonBox.StandardButton.Ok).setText("导入到课程")

    def _sync_json_window_on_mode_switch(self) -> None:
        """If the JSON window is open, host the now-active editor in it."""
        if self._json_window is None:
            return
        # Return the previous editor to its host, then host the active one.
        prev = self._json_window.release_editor()
        if prev is not None:
            # Figure out which host the previous editor belongs to.
            if prev is self.wish_json_edit:
                self._wish_json_host.addWidget(prev)
            else:
                self._normal_json_host.addWidget(prev)
            prev.setVisible(True)
        active = self._active_json_editor()
        if active is not None:
            self._json_window.host_editor(active)
            active.setVisible(True)

    def _place_template_bar(self, is_normal: bool) -> None:
        bar = getattr(self, "_template_bar", None)
        if bar is None:
            return
        target = self._normal_template_slot if is_normal else self._wish_template_slot
        # Remove the bar from whichever slot currently holds it, then add to
        # the target. addWidget reparents the bar into the target panel.
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
        """Topic source by mode — fixes the wish-mode stale-topic read.

        Normal mode reads the topic line edit; wish mode derives the topic
        from the last user message in the conversation (the spec_bar topic
        edit is normal-only and orphaned when the bar is reparented to wish).
        """
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
        """Detect genre tags in normal mode topic/extra input."""
        if not self.genre_switch.isChecked():
            return
        self._sync_template_from_genre_tags()

    def _sync_template_from_genre_tags(self) -> None:
        """Set the template combo to the default fallback based on detected genre tag."""
        if not self.genre_switch.isChecked():
            return
        combined = f"{self._current_topic_text()} {self.extra_edit.text()}"
        tags = genre_tags_in_text(combined)
        self._template_bar.set_template_by_tags(tags, genre_to_template)

    def _set_template_combo(self, template: str) -> None:
        self._template_bar.select_template(template)

    def _ensure_api_configured(self) -> bool:
        """Ensure the centrally-managed API config is complete.

        If incomplete, prompt the user to open the Settings panel. No connection
        test is performed here; the Settings panel is the single place to manage
        API configuration.
        """
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
        """Reconnect a button's clicked signal to ``slot`` (ignore 'no such signal')."""
        try:
            btn.clicked.disconnect()
        except RuntimeError:
            pass
        btn.clicked.connect(slot)

    def _set_busy(self, busy: bool, normal: bool = False, stage: str = "") -> None:
        """Enable/disable UI while an AI request is running.

        When ``busy`` is True the primary action button is repurposed as a
        ``取消生成`` button that cancels the in-flight worker; when it returns
        to idle the original action is restored. ``stage`` sets the staged
        progress label text (e.g. ``对齐中…``).
        """
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
        win = getattr(self, "_chat_expand", None)
        if win is not None and win.isVisible():
            win.set_busy(busy and not normal)

    def _set_stage_label(self, stage: str) -> None:
        if hasattr(self, "stage_label"):
            self.stage_label.setText(stage)
            self.stage_label.setVisible(bool(stage))
        if hasattr(self, "wish_stage_label"):
            self.wish_stage_label.setText(stage)
            self.wish_stage_label.setVisible(bool(stage))
        win = getattr(self, "_chat_expand", None)
        if win is not None and win.isVisible():
            win.set_stage(stage)

    # --- Streaming chunk + usage display --------------------------------

    def _current_usage_label(self) -> QLabel:
        """Return the usage label for the active mode."""
        return self.wish_usage_label if self._mode == "wish" else self.usage_label

    def _on_worker_chunk(self, fragment: str) -> None:
        """Accumulate a streaming fragment; views refresh on a throttle timer.

        For alignment/explain (free text) the flush appends into the chat /
        explain bubble so the teacher sees tokens arrive in near real time.
        For normal-mode JSON generation the flush keeps a running preview in
        the JSON editor so the teacher can watch the model write. Buffering +
        throttled flush avoids a full-document rewrite per SSE chunk (O(n^2)).
        """
        if not fragment:
            return
        self._stream_buffer = (getattr(self, "_stream_buffer", "") or "") + fragment
        self._stream_dirty = True
        self._stream_flush_timer.start()

    def _flush_stream_view(self) -> None:
        """Render the accumulated stream buffer once per throttle interval."""
        if not self._stream_dirty:
            return
        self._stream_dirty = False
        if self._mode == "wish":
            if self._stream_target == "explain":
                self.explain_label.setHtml(_escape_html(self._stream_buffer))
                self.explain_group.setProperty("_has_text", True)
                self.explain_group.setVisible(self._result_toggle.isChecked())
            elif self._stream_target == "alignment":
                self._render_streaming_chat(self._stream_buffer)
        else:
            # Normal-mode JSON generation: running preview in the JSON editor
            # so the teacher can watch the model write.
            self.json_edit.setPlainText(self._stream_buffer)

    def _render_streaming_chat(self, partial_text: str) -> None:
        """Re-render the chat with the in-flight assistant turn appended."""
        self.chat_view.render_streaming(self._messages, partial_text, self._chat_palette())
        win = getattr(self, "_chat_expand", None)
        if win is not None and win.isVisible():
            win.render_streaming(self._messages, partial_text)

    def _sync_expand_chat(self) -> None:
        """Re-render the expand sub-window's chat to match the panel (P5.5)."""
        win = getattr(self, "_chat_expand", None)
        if win is not None and win.isVisible():
            win.render(self._messages)

    def _on_worker_usage(self, usage: object) -> None:
        """Update the usage/cost label and record the token count."""
        try:
            usage_dict = dict(usage) if isinstance(usage, dict) else {}
        except Exception:  # noqa: BLE001
            usage_dict = {}
        model = self._config.model if self._config is not None else ""
        line = format_usage_line(usage_dict, model)
        label = self._current_usage_label()
        label.setText(line)
        label.setVisible(bool(line) and line != "≈ 0 tokens")
        win = getattr(self, "_chat_expand", None)
        if win is not None and win.isVisible():
            win.set_usage(line)
        try:
            telemetry.record_event(
                "ai.usage",
                payload={
                    "model": model,
                    "prompt_tokens": usage_dict.get("prompt_tokens", 0),
                    "completion_tokens": usage_dict.get("completion_tokens", 0),
                    "total_tokens": usage_dict.get("total_tokens", 0),
                },
            )
        except Exception:  # noqa: BLE001 — telemetry must not crash the UI
            pass

    def _begin_stream(self, target: str) -> None:
        """Reset the streaming scratch buffer for a new worker."""
        self._stream_flush_timer.stop()
        self._stream_dirty = False
        self._stream_buffer = ""
        self._stream_target = target

    def _finish_stream(self) -> None:
        """Clear the streaming scratch state (call after result/error)."""
        # Flush whatever accumulated but was not rendered yet, so the view
        # ends up showing the complete streamed text before we reset.
        if self._stream_dirty:
            self._flush_stream_view()
        self._stream_flush_timer.stop()
        self._stream_buffer = ""
        self._stream_target = None

    def _duration_since_request_start(self) -> float:
        """Milliseconds since the current request started (B7-safe).

        ``_request_start`` is reset to a fresh ``time.perf_counter()`` before
        each worker is started and cleared to ``None`` afterward. If a ready/
        error handler fires without a live timestamp (e.g. a stray signal), we
        fall back to 0 rather than computing against a stale or None value.
        """
        start = getattr(self, "_request_start", None)
        if start is None:
            return 0.0
        return (time.perf_counter() - start) * 1000

    def _cancel_current_worker(self) -> None:
        worker = self._current_worker
        if worker is not None and worker.isRunning():
            worker.cancel()
            self._set_stage_label("正在取消…")

    def _disconnect_worker_signals(self, worker: AiRequestWorker | None) -> None:
        """Disconnect all dialog-side slots from a worker's signals.

        Called from ``reject``/``closeEvent`` so a worker that is still
        finishing its HTTP read cannot emit ``result_ready`` /
        ``error_occurred`` into a dialog whose C++ side is being torn down
        (which would either crash Qt or invoke a slot on a deleted
        QObject). The worker itself is kept alive by ``_LIVE_WORKERS``
        until its ``finished`` signal fires, so this is purely about
        silencing the UI-bound signals. (B6)
        """
        if worker is None:
            return
        for sig_name in ("result_ready", "error_occurred", "completed", "chunk_ready", "usage_ready", "finished"):
            try:
                sig = getattr(worker, sig_name, None)
                if sig is not None:
                    sig.disconnect()
            except (TypeError, RuntimeError):
                # No connections or already disconnected — safe.
                pass

    def _register_worker(self, worker: AiRequestWorker) -> None:
        """Remember the active worker and clear the reference when it finishes.

        Without the ``finished`` hook, a completed worker lingered in
        ``_current_worker`` (harmless, since callers check ``isRunning()``,
        but it pinned a QThread in memory). The finished signal fires after
        ``completed``/``error_occurred`` regardless of success or cancel.
        """
        self._current_worker = worker
        worker.finished.connect(self._forget_worker)

    def _forget_worker(self) -> None:
        # Only clear if the finished worker is still the one we registered —
        # a newer worker may already have replaced it.
        worker = self.sender()
        if worker is self._current_worker:
            self._current_worker = None

    def _on_worker_error(self, message: str) -> None:
        if self._closing:
            return
        duration_ms = self._duration_since_request_start()
        cancelled = "取消" in message or "cancelled" in message.lower()
        telemetry.record_duration(
            "ai.generate",
            duration_ms,
            payload={
                "mode": self._mode,
                "success": False,
                "cancelled": cancelled,
                "error": message if not cancelled else "cancelled",
            },
        )
        _record_cache_stats()
        self._set_busy(False, normal=self._busy_normal)
        self._set_stage_label("")
        # Treat cancellation quietly (the user already knows they cancelled).
        if cancelled:
            self.statusMessage = message  # noqa: F841 — keep a trace for debugging
            return
        self._offer_error_analysis(
            message, context={"action": "ai.generate", "mode": self._mode}
        )

    def _offer_error_analysis(self, message: str, context: dict[str, Any]) -> None:
        """Show a failure dialog with an optional "AI 分析原因" button (C12)."""
        from src.dialogs.ai_error_analyzer import offer_ai_analysis
        if offer_ai_analysis(self, "请求失败", message):
            import traceback

            from src.dialogs.ai_error_analyzer import AiErrorAnalyzerDialog

            AiErrorAnalyzerDialog(
                traceback.format_exc(),
                context=context,
                parent=self,
            ).exec()

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
        """Trimmed snapshot of existing course resources for the prompt (P0-5).

        Returns None when the course has no resources yet — the prompt then
        stays byte-identical to the pre-P0-5 behaviour.
        """
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
        """Copy the shared prompt fields (topic/level/unit/lessons/template/genre/extra)."""
        self.topic_edit.setText(obj.topic)
        self.level_combo.setCurrentText(obj.level)
        self.unit_spin.setValue(obj.unit_count)
        self.lessons_spin.setValue(obj.lessons_per_unit)
        self._template_bar.select_template(obj.template)
        self._template_bar.set_genre_enabled(obj.use_genre_batch)
        self.extra_edit.setText(obj.extra_instructions)

    def _on_template_applied(self, obj: object) -> None:
        """Apply a saved template or handle a save request from the template bar."""
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
        """Max validation-retry rounds for normal-mode generation (C3).

        Sourced from Settings (``ai_retry_max``, clamped 0-5); falls back to 1
        when no MainWindow/Settings is available (sandbox-safe).
        """
        try:
            s = current_settings()
            return max(0, min(5, getattr(s, "ai_retry_max", 1)))
        except Exception:
            return 1

    def _ai_generation_kwargs(self) -> dict[str, Any]:
        """Return timeout and temperature from Settings for AI workers."""
        try:
            s = current_settings()
            timeout = float(getattr(s, "ai_timeout", 120.0))
            temperature = float(getattr(s, "ai_temperature", 0.7))
        except Exception:
            timeout = 120.0
            temperature = 0.7
        return {"timeout": timeout, "temperature": temperature}

    def _make_edit_worker(self, spec: AiCourseSpec, **kwargs: Any) -> "AiRequestWorker":
        """Build the edit-mode worker, dispatching by scope (C5/B3).

        - ``lesson``: regenerate only that lesson in place (local regen, few
          tokens) and splice it back into the section.
        - ``unit``: regenerate each lesson in the unit in place.
        - ``section`` (default): full-section edit via ``generate_edit``; the
          structural-conservation check (B3) runs after the result lands.
        """
        scope = self._edit_mode.get("scope", "section")
        scope_id = self._edit_mode.get("scope_id", "")
        existing = self._edit_mode["existing_section"]

        instruction = None
        if hasattr(self, "edit_instruction_input"):
            instruction = self.edit_instruction_input.toPlainText().strip() or None

        if scope == "lesson" and scope_id:
            return AiRequestWorker(
                regenerate_lesson_in_section,
                self._config,
                spec,
                existing,
                scope_id,
                instruction=instruction,
                **kwargs,
            )
        if scope == "unit" and scope_id:
            return AiRequestWorker(
                regenerate_unit_in_section,
                self._config,
                spec,
                existing,
                scope_id,
                instruction=instruction,
                **kwargs,
            )

        if instruction:
            spec.extra_instructions = (spec.extra_instructions or "") + f"\n\n编辑指令：\n{instruction}"

        return AiRequestWorker(
            generate_edit,
            self._config,
            spec,
            existing,
            scope,
            scope_id,
            **kwargs,
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
            # Plain generation: ground the model on existing course resources
            # so it reuses ids instead of re-creating duplicates (P0-5).
            spec.course_resources = self._course_resource_summary()
        self._template_bar.record_history(spec)
        kwargs = self._ai_generation_kwargs()
        if self._edit_mode is not None:
            worker = self._make_edit_worker(spec, **kwargs)
        else:
            # Normal mode: generate with validate-and-retry self-healing (C3).
            # The real validator returns Problem dicts; request_course_with_retry
            # coerces them to error strings and re-prompts up to N rounds.
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
        # Structural conservation guard (B3 / U1-4): if the model silently
        # dropped units/lessons/words (any edit scope), confirm before accepting.
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
                # Teacher rejected the removals: keep the current state intact.
                self._set_busy(False, normal=True, stage="")
                self._finish_stream()
                self._request_start = None
                return
        self._generated = parsed
        # Replace the streamed partial preview with the finalized parsed JSON.
        self.json_edit.set_json(parsed)
        self.reset_btn.setEnabled(True)
        if isinstance(parsed, dict):
            self.result_preview.show_section(parsed)
            self.result_preview.setVisible(True)
        # P3.4/P3.5: surface the diff + try-preview buttons when there is a result.
        self.try_btn.setVisible(isinstance(parsed, dict))
        self.diff_btn.setVisible(
            isinstance(parsed, dict)
            and self._edit_mode is not None
            and isinstance(self._edit_mode.get("existing_section"), dict)
        )
        self._update_mode_ui()

    def _confirm_structural_removal(self, diff: dict[str, set[str]]) -> bool:
        """Ask the teacher to accept AI-removed units/lessons/words (B3).

        Returns True to accept the edited section as-is, False to discard it
        and keep the existing state. Only deletions prompt (additions/renames
        are not surfaced here, per guiplan2 §6).
        """
        parts: list[str] = []
        labels = [
            ("removed_units", "单元"),
            ("removed_lessons", "课时"),
            ("removed_words", "词汇"),
            ("removed_expressions", "表达"),
            ("removed_grammar", "语法点"),
        ]
        for key, label in labels:
            ids = diff.get(key) or set()
            if ids:
                preview = ", ".join(sorted(ids)[:8])
                more = f" 等 {len(ids)} 个" if len(ids) > 8 else ""
                parts.append(f"{label}：{preview}{more}")
        if not parts:
            return True
        msg = (
            "AI 在编辑中删除了以下内容（结构保护）。\n"
            "若只想改一两题，请改用教师模式「AI 改这题」或工坊局部重生成。\n\n"
            + "\n".join(parts)
            + "\n\n是否仍接受这些删除？"
        )
        btn = QMessageBox.question(
            self,
            "AI 删除了内容",
            msg,
            QMessageBox.Yes | QMessageBox.No,
            QMessageBox.No,
        )
        return btn == QMessageBox.Yes

    def _on_normal_worker_done(self) -> None:
        """Finalize the normal-mode worker: clear busy + streaming state.

        ``_request_start`` is reset here too (defensive fix for B7) so the next
        request's duration never inherits a stale timestamp.
        """
        if self._closing:
            return
        self._set_busy(False, normal=True, stage="")
        self._finish_stream()
        self._request_start = None

    def _on_preview_validity(self, ok: bool) -> None:
        """Enable/disable the import (Ok) button based on preview validation."""
        if self._generated is not None:
            self._button_box.button(QDialogButtonBox.StandardButton.Ok).setEnabled(ok)

    def _on_reset(self) -> None:
        if self._generated is not None:
            self._active_json_editor().set_json(self._generated)

    def _on_view_diff(self) -> None:
        """Show the structural diff between the existing section and the current
        generated/edited JSON (P3.4)."""
        from src.widgets.diff_view import SectionDiffView

        if self._edit_mode is None or not isinstance(self._edit_mode.get("existing_section"), dict):
            return
        try:
            generated = self._current_json()
        except ValueError:
            return
        SectionDiffView(self._edit_mode["existing_section"], generated, self).exec()

    def _on_try_preview(self) -> None:
        """Pick a lesson from the current section and try it (P3.5).

        Uses a vocab override built from the section's own ``words`` so word
        cards resolve before the section is imported into the adapter.
        """
        from src.teacher.preview_window import LessonPreviewDialog

        try:
            section = self._current_json()
        except ValueError as exc:
            QMessageBox.warning(self, "无法试做", str(exc))
            return
        lessons: list[tuple[str, dict]] = []
        for unit in section.get("units") or []:
            if not isinstance(unit, dict):
                continue
            for lesson in unit.get("lessons") or []:
                if isinstance(lesson, dict) and lesson.get("id"):
                    label = f"{unit.get('name', unit.get('id', '?'))} › {lesson.get('name', lesson['id'])}"
                    lessons.append((label, lesson))
        if not lessons:
            QMessageBox.information(self, "无可试做课时", "当前课程没有课时可试做。")
            return
        if len(lessons) == 1:
            lesson = lessons[0][1]
        else:
            items = [lbl for lbl, _ in lessons]
            choice, ok = QInputDialog.getItem(
                self, "选择课时试做", "课时：", items, 0, False
            )
            if not ok:
                return
            lesson = next(l for lbl, l in lessons if lbl == choice)
        vocab_override = {w.get("id"): w for w in (section.get("words") or []) if isinstance(w, dict) and w.get("id")}
        LessonPreviewDialog(self.adapter, lesson, self, vocab_override=vocab_override).exec()

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
        """Validate the current (possibly edited) JSON via the preview widget.

        Parses the editor text in normal mode (or the cached generated dict in
        wish mode), refreshes the preview overview cards, then runs validation.
        """
        try:
            data = self._current_json()
        except ValueError as exc:
            QMessageBox.warning(self, "JSON 无效", str(exc))
            return
        preview = self.wish_result_preview if self._mode == "wish" else self.result_preview
        preview.show_section(data)
        preview._on_validate()  # noqa: SLF001 — reuse the widget's validate path

    def _current_json(self) -> dict:
        # Single JSON truth source (B1 fix, §4.5): always read from the editor
        # of the active mode. ``_generated`` is only a restore snapshot now.
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
        """Jump the active JSON editor to the line matching the tree path (P3.1)."""
        editor = self._active_json_editor()
        text = editor.toPlainText()
        if not text or not path:
            return
        # Locate by id segment if present, else by structural heuristic: find the
        # first line whose key matches the deepest id in the path.
        from PySide6.QtGui import QTextCursor

        line_no = self._find_line_for_path(text, path)
        if line_no is None:
            return
        cursor = editor.textCursor()
        cursor.movePosition(QTextCursor.MoveOperation.Start)
        for _ in range(line_no - 1):
            cursor.movePosition(QTextCursor.MoveOperation.Down)
        editor.setTextCursor(cursor)
        editor.setFocus()

    def _find_line_for_path(self, text: str, path: str) -> int | None:
        """Return the 1-based line whose content contains the id in an
        ``id:<id>`` path payload. Returns None for structural-only paths.

        Uses ``str.find`` + a newline count up to the match offset instead of
        materializing the whole ``splitlines()`` list on every click — for a
        5000-line generated course this is O(match_offset) string scans vs
        the old O(total_lines) full-list allocation per click. (P9)
        """
        if not path.startswith("id:"):
            return None
        target = f'"{path[3:]}"'
        idx = text.find(target)
        if idx < 0:
            return None
        # 1-based line number = number of '\n' before idx + 1.
        return text.count("\n", 0, idx) + 1

    # --- Wish mode actions -----------------------------------------------

    def _chat_palette(self) -> dict[str, str]:
        """Return the palette for chat rendering (theme-aware once P5.4 lands)."""
        try:
            from src.theme import current_palette

            return current_palette()
        except Exception:
            return _CHAT_PALETTE

    def _pal(self, key: str, fallback: str) -> str:
        """Theme-aware color lookup for build-time stylesheets (P5.4)."""
        try:
            from src.theme import current_palette

            return current_palette().get(key, fallback)
        except Exception:
            return fallback

    def _render_chat(self) -> None:
        self.chat_view.render(self._messages, self._chat_palette())
        self._sync_expand_chat()

    def _input_key_press(self, event) -> None:
        key = event.key()
        mods = event.modifiers()
        if key in (Qt.Key.Key_Return, Qt.Key.Key_Enter):
            if mods == Qt.KeyboardModifier.ControlModifier:
                self._on_send_message()
                return
            if mods == Qt.KeyboardModifier.NoModifier and self._enter_to_send.isChecked():
                self._on_send_message()
                return
        QTextEdit.keyPressEvent(self.input_edit, event)

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
        """Finalize the alignment worker (clear busy + streaming state)."""
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
        for path in paths:
            temp_name = f"turna_wish_{uuid.uuid4().hex[:8]}_{path.name}"
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
            self._attachment_bar.add_attachment(
                _AttachmentRecord(
                    temp_path=temp_path,
                    original_name=path.name,
                    content=result.content or {},
                )
            )

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

    def _on_attachments_changed(self) -> None:
        """Sync the internal list with the AttachmentBar widget."""
        self._attachments = list(self._attachment_bar.attachments())

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
        # Populate the wish JSON editor (P3.3 / B1): the editor is the single
        # source of truth the import reads, so write the AI output into it.
        self.wish_json_edit.set_json(parsed)
        self.wish_json_edit.setVisible(True)
        # Surface the one-line summary + collapsible frame (collapsed by default
        # so chat + input stay on one screen — P5.3).
        self._result_frame.setVisible(True)
        self._result_summary.setText(self._result_summary_text(parsed))
        # Make the JSON-window toggle available now that there is content.
        self._wish_json_window_btn.setVisible(True)
        # Change 1: instead of expanding the in-pane result to 300px (which
        # crammed JSON + preview + explanation into the chat area), pop the
        # JSON editor into its own independent window so the chat stays
        # readable. Keep the result frame collapsed to its summary line.
        self._result_toggle.setChecked(False)
        self._open_json_window()

        # B2 fix: clear the generation worker's streaming state and reset the
        # request timer before starting the explain worker, so the cancel
        # button + duration measurement point at the explain request, not the
        # (already-finished) generation request.
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
        """Finalize the explain worker (clear busy + streaming state)."""
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
        # Auto-expand the result panel so the explanation is surfaced (preserves
        # the pre-P5.3 behaviour where the explanation always appeared).
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
        """Handle explain-course failure without masking it (B11)."""
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
            # Allow user to edit id if conflict (normal mode imports a new section).
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

        # Use format-only validation: AI outputs intentionally reuse existing
        # unit/lesson ids. The importer (app.py) decides overwrite vs append.
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
        for att in self._attachments:
            try:
                att.temp_path.unlink(missing_ok=True)
            except OSError:
                pass
        self._attachment_bar.clear_attachments()
        self._attachments.clear()
        win = getattr(self, "_chat_expand", None)
        if win is not None:
            try:
                self._save_chat_expand_geometry(win)
            except Exception:  # noqa: BLE001
                pass
            win.close()
            self._chat_expand = None

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
