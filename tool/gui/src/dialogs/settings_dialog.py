"""Application settings dialog.

Provides a central place for appearance, AI provider, editor behaviour and
recent-repository history preferences. Changes are emitted through the
``settings_changed`` signal so the main window can re-apply themes and limits.
"""
from __future__ import annotations

import json
from typing import Any

from PySide6.QtCore import Qt, QTimer, Signal
from PySide6.QtWidgets import (
    QCheckBox,
    QComboBox,
    QDialog,
    QDialogButtonBox,
    QDoubleSpinBox,
    QFormLayout,
    QGroupBox,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QListWidget,
    QListWidgetItem,
    QMessageBox,
    QPlainTextEdit,
    QPushButton,
    QSpinBox,
    QTabWidget,
    QTextBrowser,
    QVBoxLayout,
    QWidget,
)

from src.application.settings import Settings
from src.backend import ai_presets
from src.backend.ai_generator import verify_connection
from src.backend.ai_prompt_library import AiPromptLibrary
from src.backend.knowledge_prompt import (
    KnowledgePromptTemplates,
    default_library,
    load_overrides_from,
)
from src.infrastructure.operations_log import operations
from src.infrastructure.telemetry import telemetry
from src.theme import current_palette


class SettingsDialog(QDialog):
    """Modal settings editor for the course editor."""

    settings_changed = Signal()

    def __init__(self, settings: Settings, parent: QWidget | None = None, *,
                 prompt_library: AiPromptLibrary | None = None) -> None:
        super().__init__(parent)
        self.setWindowTitle("设置")
        self.resize(720, 620)
        self._original = settings
        self._settings = settings.clone()
        self._prompt_library = prompt_library or AiPromptLibrary()

        self._build_ui()
        self._load_values()

    def _build_ui(self) -> None:
        layout = QVBoxLayout(self)
        layout.setSpacing(12)
        layout.setContentsMargins(16, 16, 16, 16)

        self.tabs = QTabWidget()
        self.tabs.addTab(self._build_appearance_tab(), "外观")
        self.tabs.addTab(self._build_ai_tab(), "AI 配置")
        self.tabs.addTab(self._build_ai_usage_tab(), "AI 用量")
        self.tabs.addTab(self._build_extraction_prompt_tab(), "提取 Prompt")
        self.tabs.addTab(self._build_editor_tab(), "编辑器")
        self.tabs.addTab(self._build_operation_log_tab(), "操作日志")
        layout.addWidget(self.tabs)

        self.buttons = QDialogButtonBox(
            QDialogButtonBox.StandardButton.Ok
            | QDialogButtonBox.StandardButton.Cancel
            | QDialogButtonBox.StandardButton.Apply
        )
        self.buttons.button(QDialogButtonBox.StandardButton.Ok).setText("确定")
        self.buttons.button(QDialogButtonBox.StandardButton.Cancel).setText("取消")
        self.buttons.button(QDialogButtonBox.StandardButton.Apply).setText("应用")
        self.buttons.accepted.connect(self._on_ok)
        self.buttons.rejected.connect(self.reject)
        self.buttons.clicked.connect(self._on_button_clicked)
        layout.addWidget(self.buttons)

    def _build_appearance_tab(self) -> QWidget:
        tab = QWidget()
        layout = QVBoxLayout(tab)
        layout.setSpacing(14)
        layout.setContentsMargins(12, 12, 12, 12)
        layout.setAlignment(Qt.AlignmentFlag.AlignTop)

        group = QGroupBox("外观")
        form = QFormLayout(group)
        form.setSpacing(10)

        self.theme_combo = QComboBox()
        self.theme_combo.addItem("深色", "dark")
        self.theme_combo.addItem("浅色", "light")
        form.addRow("主题:", self.theme_combo)

        self.scale_combo = QComboBox()
        for percent in range(80, 160, 10):
            self.scale_combo.addItem(f"{percent}%", percent)
        form.addRow("UI 字体缩放:", self.scale_combo)

        self.scale_hint = QLabel("调整全局字体大小。整体窗口缩放由系统 DPI 设置控制。")
        self.scale_hint.setObjectName("hintLabel")
        form.addRow(self.scale_hint)

        layout.addWidget(group)
        layout.addStretch(1)
        return tab

    def _build_ai_tab(self) -> QWidget:
        tab = QWidget()
        layout = QVBoxLayout(tab)
        layout.setSpacing(14)
        layout.setContentsMargins(12, 12, 12, 12)
        layout.setAlignment(Qt.AlignmentFlag.AlignTop)

        provider_group = QGroupBox("AI 服务提供商")
        provider_form = QFormLayout(provider_group)
        provider_form.setSpacing(10)

        self.ai_provider_combo = QComboBox()
        for name in ai_presets.provider_names():
            preset = ai_presets.preset_for_provider(name)
            self.ai_provider_combo.addItem(preset.label, name)
        self.ai_provider_combo.currentIndexChanged.connect(self._on_provider_changed)
        provider_form.addRow("提供商:", self.ai_provider_combo)

        self.ai_url_edit = QLineEdit()
        self.ai_url_edit.setPlaceholderText("https://api.example.com/v1")
        provider_form.addRow("Base URL:", self.ai_url_edit)

        self.ai_key_edit = QLineEdit()
        self.ai_key_edit.setEchoMode(QLineEdit.EchoMode.Password)
        self.ai_key_edit.setPlaceholderText("sk-...")
        provider_form.addRow("API Key:", self.ai_key_edit)

        self.ai_model_edit = QLineEdit()
        self.ai_model_edit.setPlaceholderText("模型名称，例如 gpt-4o")
        provider_form.addRow("模型:", self.ai_model_edit)

        self.ai_reasoning_check = QCheckBox("启用 reasoning / thinking 字段")
        self.ai_reasoning_check.setToolTip(
            "DeepSeek 等支持 reasoning 的端点需要发送 thinking/reasoning_effort 字段；"
            "其他 OpenAI 兼容端点通常会因未知字段报错。"
        )
        provider_form.addRow(self.ai_reasoning_check)

        hint = QLabel(
            "配置保存在本地 QSettings；API Key 仅在当前会话内存中保留，退出后清空。"
        )
        hint.setObjectName("hintLabel")
        hint.setWordWrap(True)
        provider_form.addRow(hint)

        layout.addWidget(provider_group)

        params_group = QGroupBox("生成参数")
        params_form = QFormLayout(params_group)
        params_form.setSpacing(10)

        self.ai_timeout_spin = QSpinBox()
        self.ai_timeout_spin.setRange(5, 600)
        self.ai_timeout_spin.setSuffix(" 秒")
        params_form.addRow("请求超时:", self.ai_timeout_spin)

        self.ai_temperature_spin = QDoubleSpinBox()
        self.ai_temperature_spin.setRange(0.0, 2.0)
        self.ai_temperature_spin.setSingleStep(0.1)
        self.ai_temperature_spin.setDecimals(1)
        params_form.addRow("生成温度:", self.ai_temperature_spin)

        self.ai_retry_spin = QSpinBox()
        self.ai_retry_spin.setRange(0, 5)
        self.ai_retry_spin.setToolTip(
            "生成 section 校验失败时，自动把错误回灌给 AI 重新生成的最大轮数。"
        )
        params_form.addRow("自动重试次数:", self.ai_retry_spin)

        layout.addWidget(params_group)

        test_group = QGroupBox("连接测试")
        test_layout = QVBoxLayout(test_group)
        test_layout.setSpacing(10)

        self.ai_connection_status = QLabel("点击「测试连接」验证当前配置。")
        self.ai_connection_status.setWordWrap(True)
        self.ai_connection_status.setObjectName("hintLabel")
        test_layout.addWidget(self.ai_connection_status)

        self.ai_test_btn = QPushButton("测试连接")
        self.ai_test_btn.setToolTip("发送一个 1-token 的最小请求验证配置是否正确。")
        self.ai_test_btn.clicked.connect(self._on_test_connection)
        test_layout.addWidget(self.ai_test_btn)

        layout.addWidget(test_group)
        layout.addStretch(1)
        return tab

    def _build_ai_usage_tab(self) -> QWidget:
        tab = QWidget()
        layout = QVBoxLayout(tab)
        layout.setSpacing(14)
        layout.setContentsMargins(12, 12, 12, 12)
        layout.setAlignment(Qt.AlignmentFlag.AlignTop)

        summary_group = QGroupBox("本地用量概览")
        summary_layout = QVBoxLayout(summary_group)
        summary_layout.setSpacing(10)

        self.ai_usage_label = QLabel("正在读取本地 telemetry 日志...")
        self.ai_usage_label.setWordWrap(True)
        summary_layout.addWidget(self.ai_usage_label)

        self.ai_usage_detail = QTextBrowser()
        self.ai_usage_detail.setMaximumHeight(220)
        summary_layout.addWidget(self.ai_usage_detail)

        buttons = QHBoxLayout()
        buttons.setSpacing(8)
        self.ai_usage_refresh_btn = QPushButton("刷新")
        self.ai_usage_refresh_btn.clicked.connect(self._refresh_ai_usage)
        buttons.addWidget(self.ai_usage_refresh_btn)

        self.ai_usage_open_dir_btn = QPushButton("打开日志目录")
        self.ai_usage_open_dir_btn.clicked.connect(self._on_open_telemetry_dir)
        buttons.addWidget(self.ai_usage_open_dir_btn)

        self.ai_usage_clear_btn = QPushButton("清空本地记录")
        self.ai_usage_clear_btn.setObjectName("dangerButton")
        self.ai_usage_clear_btn.clicked.connect(self._on_clear_telemetry)
        buttons.addWidget(self.ai_usage_clear_btn)
        buttons.addStretch(1)
        summary_layout.addLayout(buttons)

        layout.addWidget(summary_group)

        note = QLabel(
            "说明：token 与成本为本地估算，仅供参考，不作为计费依据。"
        )
        note.setObjectName("hintLabel")
        note.setWordWrap(True)
        layout.addWidget(note)
        layout.addStretch(1)
        return tab

    # --- Extraction prompt overrides (connectplan P1-3) -------------------

    _EXTRACTION_FIELDS = (
        ("system", "System prompt"),
        ("intro", "抽取引导语（intro）"),
        ("schema_block", "Schema 块（schema_block）"),
        ("rules_block", "规则块（rules_block）"),
        ("vocab_intro", "仅词汇引导语（vocab_intro）"),
        ("vocab_schema_block", "仅词汇 Schema（vocab_schema_block）"),
        ("vocab_rules_block", "仅词汇规则（vocab_rules_block）"),
    )

    def _build_extraction_prompt_tab(self) -> QWidget:
        from PySide6.QtWidgets import QScrollArea

        outer = QWidget()
        outer_layout = QVBoxLayout(outer)
        outer_layout.setContentsMargins(12, 12, 12, 12)

        pair_row = QHBoxLayout()
        self.extraction_lang_edit = QLineEdit("Turkish")
        self.extraction_lang_edit.setPlaceholderText("目标语言，如 Turkish")
        self.extraction_src_edit = QLineEdit("Chinese")
        self.extraction_src_edit.setPlaceholderText("讲解语言，如 Chinese")
        load_btn = QPushButton("载入")
        load_btn.clicked.connect(self._load_extraction_fields)
        pair_row.addWidget(QLabel("目标语言:"))
        pair_row.addWidget(self.extraction_lang_edit)
        pair_row.addWidget(QLabel("讲解语言:"))
        pair_row.addWidget(self.extraction_src_edit)
        pair_row.addWidget(load_btn)
        pair_row.addStretch(1)
        outer_layout.addLayout(pair_row)

        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        content = QWidget()
        form = QFormLayout(content)
        form.setSpacing(8)
        self._extraction_edits: dict[str, QPlainTextEdit] = {}
        for key, label in self._EXTRACTION_FIELDS:
            edit = QPlainTextEdit()
            edit.setPlaceholderText("留空则使用内置默认")
            edit.setMinimumHeight(60 if key in ("intro", "vocab_intro", "system") else 110)
            self._extraction_edits[key] = edit
            form.addRow(label, edit)
        scroll.setWidget(content)
        outer_layout.addWidget(scroll, 1)

        btn_row = QHBoxLayout()
        save_btn = QPushButton("保存覆盖")
        save_btn.clicked.connect(self._on_extraction_save)
        delete_btn = QPushButton("删除覆盖")
        delete_btn.setObjectName("dangerButton")
        delete_btn.clicked.connect(self._on_extraction_delete)
        reset_btn = QPushButton("重置为默认")
        reset_btn.clicked.connect(self._fill_extraction_defaults)
        btn_row.addWidget(save_btn)
        btn_row.addWidget(delete_btn)
        btn_row.addWidget(reset_btn)
        btn_row.addStretch(1)
        outer_layout.addLayout(btn_row)

        hint = QLabel(
            "按语言对覆盖教材知识点抽取的 Prompt 模板。保存后立即对新提取生效；"
            "删除覆盖后回落到内置默认。"
        )
        hint.setObjectName("hintLabel")
        hint.setWordWrap(True)
        outer_layout.addWidget(hint)

        self._load_extraction_fields()
        return outer

    def _extraction_pair(self) -> tuple[str, str]:
        return (
            self.extraction_lang_edit.text().strip() or "Turkish",
            self.extraction_src_edit.text().strip() or "Chinese",
        )

    def _current_extraction_templates(self) -> KnowledgePromptTemplates:
        language, source_language = self._extraction_pair()
        blocks = self._prompt_library.extraction_override(language, source_language)
        if blocks:
            return KnowledgePromptTemplates.from_dict(blocks)
        return KnowledgePromptTemplates()

    def _load_extraction_fields(self) -> None:
        tpl = self._current_extraction_templates()
        values = tpl.to_dict()
        for key, edit in self._extraction_edits.items():
            edit.setPlainText(values.get(key, ""))

    def _fill_extraction_defaults(self) -> None:
        values = KnowledgePromptTemplates().to_dict()
        for key, edit in self._extraction_edits.items():
            edit.setPlainText(values.get(key, ""))

    def _on_extraction_save(self) -> None:
        language, source_language = self._extraction_pair()
        blocks = {
            key: edit.toPlainText()
            for key, edit in self._extraction_edits.items()
        }
        self._prompt_library.save_extraction_override(
            language, source_language, blocks
        )
        # Refresh the in-memory default library so the next extraction uses it.
        load_overrides_from(self._prompt_library)
        QMessageBox.information(
            self, "提取 Prompt", f"已保存 {language} / {source_language} 的覆盖模板。"
        )

    def _on_extraction_delete(self) -> None:
        language, source_language = self._extraction_pair()
        if not self._prompt_library.delete_extraction_override(language, source_language):
            QMessageBox.information(self, "提取 Prompt", "该语言对没有已保存的覆盖。")
            return
        default_library().unregister_persisted(language, source_language)
        self._fill_extraction_defaults()
        QMessageBox.information(
            self, "提取 Prompt", f"已删除 {language} / {source_language} 的覆盖，回落到默认。"
        )

    def _build_editor_tab(self) -> QWidget:
        tab = QWidget()
        layout = QVBoxLayout(tab)
        layout.setSpacing(14)
        layout.setContentsMargins(12, 12, 12, 12)
        layout.setAlignment(Qt.AlignmentFlag.AlignTop)

        behaviour_group = QGroupBox("编辑器行为")
        behaviour_form = QFormLayout(behaviour_group)
        behaviour_form.setSpacing(10)

        self.auto_save_check = QCheckBox("关闭窗口时自动保存未保存的更改")
        behaviour_form.addRow(self.auto_save_check)

        self.undo_spin = QSpinBox()
        self.undo_spin.setRange(10, 500)
        behaviour_form.addRow("撤销步数上限:", self.undo_spin)

        layout.addWidget(behaviour_group)

        history_group = QGroupBox("最近仓库")
        history_layout = QVBoxLayout(history_group)
        history_layout.setSpacing(8)

        self.recent_list = QListWidget()
        history_layout.addWidget(self.recent_list)

        history_buttons = QHBoxLayout()
        history_buttons.setSpacing(8)
        self.remove_recent_btn = QPushButton("删除选中")
        self.remove_recent_btn.clicked.connect(self._on_remove_recent)
        self.clear_recent_btn = QPushButton("清空全部")
        self.clear_recent_btn.setObjectName("dangerButton")
        self.clear_recent_btn.clicked.connect(self._on_clear_recent)
        history_buttons.addWidget(self.remove_recent_btn)
        history_buttons.addWidget(self.clear_recent_btn)
        history_buttons.addStretch(1)
        history_layout.addLayout(history_buttons)

        layout.addWidget(history_group)
        return tab

    def _build_operation_log_tab(self) -> QWidget:
        """Detailed log of user actions, window durations, AI latency, errors."""
        tab = QWidget()
        layout = QVBoxLayout(tab)
        layout.setSpacing(10)
        layout.setContentsMargins(12, 12, 12, 12)

        # Filter row: event-type combo + search box + action buttons.
        filter_row = QHBoxLayout()
        filter_row.setSpacing(8)

        self.oplog_filter_combo = QComboBox()
        self.oplog_filter_combo.addItem("全部", "")
        self.oplog_filter_combo.addItem("点击 (ui.click)", "ui.click")
        self.oplog_filter_combo.addItem("输入 (ui.input)", "ui.input")
        self.oplog_filter_combo.addItem("窗口 (window.)", "window.")
        self.oplog_filter_combo.addItem("AI 耗时 (ai.)", "ai.")
        self.oplog_filter_combo.addItem("错误 (app.error)", "app.error")
        self.oplog_filter_combo.addItem("启动 (app.start)", "app.start")
        self.oplog_filter_combo.currentIndexChanged.connect(self._refresh_operation_log)
        filter_row.addWidget(QLabel("类别:"))
        filter_row.addWidget(self.oplog_filter_combo)

        self.oplog_search_edit = QLineEdit()
        self.oplog_search_edit.setPlaceholderText("搜索（子串，大小写不敏感）...")
        # Debounce: each refresh re-parses both log files; avoid doing that
        # per keystroke.
        self._oplog_search_timer = QTimer(self)
        self._oplog_search_timer.setSingleShot(True)
        self._oplog_search_timer.setInterval(300)
        self._oplog_search_timer.timeout.connect(self._refresh_operation_log)
        self.oplog_search_edit.textChanged.connect(self._oplog_search_timer.start)
        filter_row.addWidget(self.oplog_search_edit, 1)

        self.oplog_refresh_btn = QPushButton("刷新")
        self.oplog_refresh_btn.clicked.connect(self._refresh_operation_log)
        filter_row.addWidget(self.oplog_refresh_btn)
        self.oplog_open_dir_btn = QPushButton("打开日志目录")
        self.oplog_open_dir_btn.clicked.connect(self._on_open_telemetry_dir)
        filter_row.addWidget(self.oplog_open_dir_btn)
        self.oplog_clear_btn = QPushButton("清空操作日志")
        self.oplog_clear_btn.setObjectName("dangerButton")
        self.oplog_clear_btn.clicked.connect(self._on_clear_operation_log)
        filter_row.addWidget(self.oplog_clear_btn)
        layout.addLayout(filter_row)

        # Summary line.
        self.oplog_summary_label = QLabel("")
        self.oplog_summary_label.setObjectName("hintLabel")
        self.oplog_summary_label.setWordWrap(True)
        layout.addWidget(self.oplog_summary_label)

        # Read-only event view.
        self.oplog_view = QTextBrowser()
        self.oplog_view.setOpenExternalLinks(False)
        self.oplog_view.setLineWrapMode(QTextBrowser.LineWrapMode.NoWrap)
        font = self.oplog_view.font()
        font.setFamily("monospace")
        self.oplog_view.setFont(font)
        layout.addWidget(self.oplog_view, 1)

        note = QLabel(
            "记录最近 500 条操作（点击、输入、窗口运行时长、AI 回复耗时、启动时间、运行错误）。"
            "API Key 等敏感字段记为 <redacted>。日志位于 ~/.varnamala-gui/，按天轮转保留 7 天。"
        )
        note.setObjectName("hintLabel")
        note.setWordWrap(True)
        layout.addWidget(note)
        return tab

    def _refresh_operation_log(self) -> None:
        """Render the merged, filtered recent events into the log view."""
        try:
            from src.infrastructure.operations_log import operations as ops
            from src.infrastructure.telemetry import telemetry as tel

            prefix = self.oplog_filter_combo.currentData() or None
            search = self.oplog_search_edit.text().strip().lower()

            ops_events = ops.recent_events(500, event_prefix=prefix)
            tel_events = tel.recent_events(500, event_prefix=prefix)
            merged = sorted(
                ops_events + tel_events,
                key=lambda r: r.get("ts", ""),
            )

            if search:
                merged = [r for r in merged if search in json.dumps(r, ensure_ascii=False).lower()]

            self.oplog_view.setPlainText("\n".join(self._format_log_line(r) for r in merged))

            # Summary.
            counts: dict[str, int] = {}
            startup_ms: float | None = None
            ai_ms: float | None = None
            for r in merged:
                event = r.get("event", "")
                key = event.split(".")[0] if event else "?"
                counts[key] = counts.get(key, 0) + 1
                if event == "app.startup" and "duration_ms" in r:
                    startup_ms = r["duration_ms"]
                if event == "ai.generate" and "duration_ms" in r:
                    ai_ms = r["duration_ms"]
            parts = [f"共 {len(merged)} 条"]
            for key in sorted(counts):
                parts.append(f"{key}·{counts[key]}")
            if startup_ms is not None:
                parts.append(f"启动 {startup_ms:.0f}ms")
            if ai_ms is not None:
                parts.append(f"最近 AI {ai_ms:.0f}ms")
            self.oplog_summary_label.setText("　|　".join(parts))
        except Exception:
            self.oplog_view.setPlainText("（读取操作日志失败）")

    @staticmethod
    def _format_log_line(record: dict[str, Any]) -> str:
        ts = str(record.get("ts", ""))[11:19]  # time-of-day only
        event = record.get("event", "")
        payload = record.get("payload") or {}
        context = record.get("context") or {}
        target = payload.get("target") or payload.get("window") or ""
        window = context.get("window", "")
        dur = record.get("duration_ms")
        dur_text = f" [{dur:.0f}ms]" if dur is not None else ""
        text = payload.get("text", "")
        text_part = f" «{text}»" if text else ""
        return f"{ts} {event}{dur_text} {target}{text_part} @{window}".rstrip()

    def _on_clear_operation_log(self) -> None:
        reply = QMessageBox.question(
            self,
            "清空操作日志",
            "确定要清空 operations.log 吗？（仅清操作记录，保留 telemetry.log 的 AI 用量/错误/启动时间）此操作不可撤销。",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
            QMessageBox.StandardButton.No,
        )
        if reply == QMessageBox.StandardButton.Yes:
            operations.clear()
            self._refresh_operation_log()

    def _load_values(self) -> None:
        theme_index = self.theme_combo.findData(self._settings.theme)
        if theme_index >= 0:
            self.theme_combo.setCurrentIndex(theme_index)

        scale_index = self.scale_combo.findData(self._settings.ui_scale_percent)
        if scale_index >= 0:
            self.scale_combo.setCurrentIndex(scale_index)
        else:
            self.scale_combo.setCurrentIndex(self.scale_combo.findData(100))

        provider_index = self.ai_provider_combo.findData(self._settings.ai_provider)
        if provider_index >= 0:
            self.ai_provider_combo.setCurrentIndex(provider_index)

        self.ai_url_edit.setText(self._settings.ai_base_url)
        self.ai_key_edit.setText(self._settings.ai_api_key)
        self.ai_model_edit.setText(self._settings.ai_model)
        self.ai_reasoning_check.setChecked(self._settings.ai_supports_reasoning)

        self.ai_timeout_spin.setValue(int(self._settings.ai_timeout))
        self.ai_temperature_spin.setValue(self._settings.ai_temperature)
        self.ai_retry_spin.setValue(self._settings.ai_retry_max)

        self.auto_save_check.setChecked(self._settings.auto_save_on_close)
        self.undo_spin.setValue(self._settings.undo_limit)

        self._populate_recent_list()
        self._refresh_ai_usage()
        self._refresh_operation_log()

    def _populate_recent_list(self) -> None:
        self.recent_list.clear()
        for repo in self._settings.recent_repos:
            path = repo.get("path", "")
            item = QListWidgetItem(path)
            item.setData(Qt.ItemDataRole.UserRole, path)
            self.recent_list.addItem(item)

    def _sync_to_settings(self) -> None:
        self._settings.theme = self.theme_combo.currentData()
        self._settings.ui_scale_percent = self.scale_combo.currentData()

        self._settings.ai_provider = self.ai_provider_combo.currentData()
        self._settings.ai_base_url = self.ai_url_edit.text().strip()
        self._settings.ai_api_key = self.ai_key_edit.text().strip()
        self._settings.ai_model = self.ai_model_edit.text().strip()
        self._settings.ai_supports_reasoning = self.ai_reasoning_check.isChecked()

        self._settings.ai_timeout = float(self.ai_timeout_spin.value())
        self._settings.ai_temperature = self.ai_temperature_spin.value()
        self._settings.ai_retry_max = self.ai_retry_spin.value()

        self._settings.auto_save_on_close = self.auto_save_check.isChecked()
        self._settings.undo_limit = self.undo_spin.value()

    def _on_provider_changed(self, _index: int) -> None:
        """When a built-in provider is selected, fill its defaults.

        The ``custom`` preset leaves user input alone so manually entered
        endpoints are not overwritten.
        """
        name = self.ai_provider_combo.currentData()
        preset = ai_presets.preset_for_provider(name)
        if preset.name == "custom":
            return
        self.ai_url_edit.setText(preset.base_url)
        self.ai_model_edit.setText(preset.default_model)
        self.ai_reasoning_check.setChecked(preset.supports_reasoning)

    def _on_test_connection(self) -> None:
        from src.backend.ai_generator import AiApiConfig

        self._sync_to_settings()
        config = AiApiConfig(
            base_url=self._settings.ai_base_url,
            api_key=self._settings.ai_api_key,
            model=self._settings.ai_model,
            supports_reasoning=self._settings.ai_supports_reasoning,
        )
        if not config.is_complete:
            self.ai_connection_status.setText(
                f"<font color='{current_palette()['error']}'>"
                "请先填写 Base URL、API Key 和 Model。</font>"
            )
            return

        self.ai_test_btn.setEnabled(False)
        self.ai_test_btn.setText("测试中…")
        self.ai_connection_status.setText("正在发送 1-token 测试请求…")

        try:
            result = verify_connection(config, timeout=15.0)
        except Exception as exc:  # noqa: BLE001
            result = {"ok": False, "error": str(exc)}

        self.ai_test_btn.setEnabled(True)
        self.ai_test_btn.setText("测试连接")
        if result.get("ok"):
            model = result.get("model") or config.model
            self.ai_connection_status.setText(
                f"<font color='{current_palette()['success']}'>连接成功：{model}</font>"
            )
        else:
            error = result.get("error", "未知错误")
            self.ai_connection_status.setText(
                f"<font color='{current_palette()['error']}'>连接失败：{error}</font>"
            )

    def _refresh_ai_usage(self) -> None:
        summary = telemetry.usage_summary()
        today = summary.get("today", {})
        total = summary.get("total", {})

        today_text = self._format_usage_bucket(today)
        total_text = self._format_usage_bucket(total)
        self.ai_usage_label.setText(
            f"今日：{today_text}　|　累计：{total_text}"
        )

        lines: list[str] = []
        lines.append("<b>今日</b>")
        lines.append(self._usage_bucket_html(today))
        lines.append("<b>累计</b>")
        lines.append(self._usage_bucket_html(total))
        self.ai_usage_detail.setHtml("<br>".join(lines))

    @staticmethod
    def _format_usage_bucket(bucket: dict[str, Any]) -> str:
        tokens = bucket.get("total_tokens", 0)
        requests = bucket.get("requests", 0)
        cost = bucket.get("estimated_cost")
        currency = bucket.get("currency", "CNY")
        symbol = ai_presets.currency_symbol(currency)
        cost_text = f"{symbol}{cost:.2f}" if cost is not None else "—"
        return f"{tokens} tokens · {requests} 次请求 · 约 {cost_text}"

    @staticmethod
    def _usage_bucket_html(bucket: dict[str, Any]) -> str:
        ok = bucket.get("success", 0)
        failed = bucket.get("failure", 0)
        cost = bucket.get("estimated_cost")
        currency = bucket.get("currency", "CNY")
        symbol = ai_presets.currency_symbol(currency)
        cost_text = f"{symbol}{cost:.2f}" if cost is not None else "—"
        return (
            f"tokens: {bucket.get('total_tokens', 0)} "
            f"(in {bucket.get('prompt_tokens', 0)} / out {bucket.get('completion_tokens', 0)})<br>"
            f"请求: {bucket.get('requests', 0)}（成功 {ok} / 失败 {failed}）<br>"
            f"估算成本: {cost_text} ({currency})"
        )

    def _on_open_telemetry_dir(self) -> None:
        from pathlib import Path

        from PySide6.QtCore import QUrl
        from PySide6.QtGui import QDesktopServices

        QDesktopServices.openUrl(QUrl.fromLocalFile(str(Path.home() / ".varnamala-gui")))

    def _on_clear_telemetry(self) -> None:
        reply = QMessageBox.question(
            self,
            "清空本地 AI 用量记录",
            "确定要清空本地 telemetry 日志吗？此操作不可撤销。",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
            QMessageBox.StandardButton.No,
        )
        if reply == QMessageBox.StandardButton.Yes:
            telemetry.clear()
            self._refresh_ai_usage()

    def _on_remove_recent(self) -> None:
        item = self.recent_list.currentItem()
        if item is None:
            return
        path = item.data(Qt.ItemDataRole.UserRole)
        self._settings.remove_recent_repo(path)
        self._populate_recent_list()

    def _on_clear_recent(self) -> None:
        reply = QMessageBox.question(
            self,
            "清空历史",
            "确定要清空所有最近仓库历史吗？此操作不可撤销。",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
            QMessageBox.StandardButton.No,
        )
        if reply == QMessageBox.StandardButton.Yes:
            self._settings.clear_recent_repos()
            self._populate_recent_list()

    def _on_button_clicked(self, button) -> None:
        if self.buttons.buttonRole(button) == QDialogButtonBox.ButtonRole.ApplyRole:
            self._apply()

    def _on_ok(self) -> None:
        self._apply()
        self.accept()

    def _apply(self) -> None:
        self._sync_to_settings()
        self._original.theme = self._settings.theme
        self._original.ui_scale_percent = self._settings.ui_scale_percent
        self._original.ai_provider = self._settings.ai_provider
        self._original.ai_base_url = self._settings.ai_base_url
        self._original.ai_api_key = self._settings.ai_api_key
        self._original.ai_model = self._settings.ai_model
        self._original.ai_supports_reasoning = self._settings.ai_supports_reasoning
        self._original.ai_timeout = self._settings.ai_timeout
        self._original.ai_temperature = self._settings.ai_temperature
        self._original.ai_retry_max = self._settings.ai_retry_max
        self._original.auto_save_on_close = self._settings.auto_save_on_close
        self._original.undo_limit = self._settings.undo_limit
        self._original.recent_repos = [dict(r) for r in self._settings.recent_repos]
        self.settings_changed.emit()

    def current_settings(self) -> Settings:
        """Return the working settings object used by the dialog."""
        self._sync_to_settings()
        return self._settings
