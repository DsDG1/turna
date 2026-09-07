"""Application settings dialog.

Provides a central place for appearance, AI provider, editor behaviour and
recent-repository history preferences. Changes are emitted through the
``settings_changed`` signal so the main window can re-apply themes and limits.
"""
from __future__ import annotations

from typing import Any

from PySide6.QtCore import Qt, Signal
from PySide6.QtWidgets import (
    QDialog,
    QDialogButtonBox,
    QFormLayout,
    QGroupBox,
    QLineEdit,
    QTabWidget,
    QVBoxLayout,
    QWidget,
)

from src.application.settings import Settings
from src.application import credential_store
from src.application.ai_prompt_library import AiPromptLibrary
from src.backend.knowledge_prompt import KnowledgePromptTemplates
from src.dialogs.settings.ai_tab import (
    build_ai_advanced_group,
    build_ai_tab,
    on_provider_changed,
    on_test_connection,
)
from src.dialogs.settings.ai_usage_tab import (
    build_ai_usage_tab,
    format_usage_bucket,
    on_clear_telemetry,
    on_open_telemetry_dir,
    refresh_ai_usage,
    usage_bucket_html,
)
from src.dialogs.settings.appearance_tab import build_appearance_tab
from src.dialogs.settings.editor_tab import (
    build_editor_tab,
    on_clear_recent,
    on_remove_recent,
    populate_recent_list,
)
from src.dialogs.settings.extraction_prompt_tab import (
    build_extraction_prompt_tab,
    current_extraction_templates,
    extraction_pair,
    fill_extraction_defaults,
    load_extraction_fields,
    on_extraction_delete,
    on_extraction_save,
)
from src.dialogs.settings.experience_tab import build_experience_tab
from src.application.presence_mode import (
    IMMERSIVE_WARN_TEXT,
    IMMERSIVE_WARN_TITLE,
    should_confirm_immersive_enter,
)
from src.application.ui_guard import safe_question
from src.dialogs.settings.git_library_tab import (
    build_git_library_tab,
    edit_remote_dialog,
    on_add_remote,
    on_browse_assets_root_clicked,
    on_browse_clone_root_clicked,
    on_del_remote,
    on_del_token,
    on_edit_remote,
    on_set_token,
    pick_dir,
    pick_ssh_key,
    populate_remotes_table,
    refresh_keyring_status,
)
from src.dialogs.settings.operation_log_tab import (
    build_operation_log_tab,
    confirm_clear,
    format_log_line,
    on_clear_operation_log,
    refresh_operation_log,
)


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
        self.tabs.addTab(self._build_experience_tab(), "体验 OS")
        self.tabs.addTab(self._build_git_library_tab(), "Git 库")
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

    @staticmethod
    def _make_tab(spacing: int = 14) -> tuple[QWidget, QVBoxLayout]:
        """Standard tab scaffold: top-aligned QVBoxLayout with consistent margins."""
        tab = QWidget()
        layout = QVBoxLayout(tab)
        layout.setSpacing(spacing)
        layout.setContentsMargins(12, 12, 12, 12)
        layout.setAlignment(Qt.AlignmentFlag.AlignTop)
        return tab, layout

    def _build_appearance_tab(self) -> QWidget:
        return build_appearance_tab(self)
    def _build_ai_tab(self) -> QWidget:
        return build_ai_tab(self)
    def _build_ai_advanced_group(self) -> tuple[QGroupBox, QFormLayout]:
        return build_ai_advanced_group(self)
    def _build_ai_usage_tab(self) -> QWidget:
        return build_ai_usage_tab(self)

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
        return build_extraction_prompt_tab(self)
    def _extraction_pair(self) -> tuple[str, str]:
        return extraction_pair(self)
    def _current_extraction_templates(self) -> KnowledgePromptTemplates:
        return current_extraction_templates(self)
    def _load_extraction_fields(self) -> None:
        load_extraction_fields(self)

    def _fill_extraction_defaults(self) -> None:
        fill_extraction_defaults(self)

    def _on_extraction_save(self) -> None:
        on_extraction_save(self)

    def _on_extraction_delete(self) -> None:
        on_extraction_delete(self)

    def _build_editor_tab(self) -> QWidget:
        return build_editor_tab(self)
    def _build_experience_tab(self) -> QWidget:
        return build_experience_tab(self)
    def _build_git_library_tab(self) -> QWidget:
        return build_git_library_tab(self)
    def _on_browse_clone_root_clicked(self) -> None:
        on_browse_clone_root_clicked(self)
    def _on_browse_assets_root_clicked(self) -> None:
        on_browse_assets_root_clicked(self)
    def _pick_dir(self, line_edit: QLineEdit) -> None:
        pick_dir(self, line_edit)

    def _pick_ssh_key(self) -> None:
        pick_ssh_key(self)

    def _populate_remotes_table(self) -> None:
        populate_remotes_table(self)
    def _refresh_keyring_status(self) -> None:
        refresh_keyring_status(self)
    def _on_add_remote(self) -> None:
        on_add_remote(self)
    def _on_edit_remote(self) -> None:
        on_edit_remote(self)
    def _edit_remote_dialog(self, name: str) -> None:
        edit_remote_dialog(self, name)
    def _on_del_remote(self) -> None:
        on_del_remote(self)
    def _on_set_token(self) -> None:
        on_set_token(self)
    def _on_del_token(self) -> None:
        on_del_token(self)
    def _build_operation_log_tab(self) -> QWidget:
        return build_operation_log_tab(self)
    def _refresh_operation_log(self) -> None:
        refresh_operation_log(self)
    @staticmethod
    def _format_log_line(record: dict[str, Any]) -> str:
        return format_log_line(record)
    def _confirm_clear(self, title: str, message: str) -> bool:
        return confirm_clear(self, title, message)
    def _on_clear_operation_log(self) -> None:
        on_clear_operation_log(self)
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

        # 第三枪 批次①: advanced AI options
        self.ai_model_chat_edit.setText(self._settings.ai_model_chat)
        self.ai_model_json_edit.setText(self._settings.ai_model_json)
        strict_idx = self.ai_strict_schema_combo.findData(self._settings.ai_strict_schema)
        if strict_idx >= 0:
            self.ai_strict_schema_combo.setCurrentIndex(strict_idx)
        self.ai_cache_check.setChecked(self._settings.ai_cache_enabled)
        self.ai_fill_needs_review_check.setChecked(self._settings.ai_fill_needs_review)
        self.ai_max_parallel_lessons_spin.setValue(self._settings.ai_max_parallel_lessons)
        pipe_idx = self.ai_pipeline_default_mode_combo.findData(
            self._settings.ai_pipeline_default_mode
        )
        if pipe_idx >= 0:
            self.ai_pipeline_default_mode_combo.setCurrentIndex(pipe_idx)

        self.auto_save_check.setChecked(self._settings.auto_save_on_close)
        self.undo_spin.setValue(self._settings.undo_limit)

        # Experience OS tab
        mode_idx = self.experience_mode_combo.findData(self._settings.experience_mode)
        if mode_idx < 0:
            mode_idx = self.experience_mode_combo.findData("copilot")
        if mode_idx >= 0:
            self.experience_mode_combo.setCurrentIndex(mode_idx)
        self.experience_immersive_full_auto_check.setChecked(
            self._settings.experience_immersive_full_auto
        )
        self.experience_immersive_opaque_check.setChecked(
            self._settings.experience_immersive_opaque
        )
        self.experience_goal_check.setChecked(self._settings.experience_goal_enabled)
        self.experience_llm_intent_check.setChecked(self._settings.experience_llm_intent)
        self.experience_dangerous_check.setChecked(
            self._settings.experience_allow_dangerous_skills
        )
        self.experience_budget_spin.setValue(self._settings.experience_daily_ai_budget)

        # Git library tab
        self.git_clone_root_edit.setText(self._settings.git_clone_root)
        self.git_bin_edit.setText(self._settings.git_bin)
        self.default_lang_edit.setText(self._settings.default_lang_code)
        self.git_timeout_spin.setValue(self._settings.git_timeout)
        self.assets_repo_root_edit.setText(self._settings.assets_repo_root)
        self.lan_port_spin.setValue(self._settings.lan_default_port)
        lan_bind_idx = self.lan_bind_combo.findData(self._settings.lan_bind_address)
        if lan_bind_idx >= 0:
            self.lan_bind_combo.setCurrentIndex(lan_bind_idx)
        self.lan_token_edit.setText(self._settings.lan_token)
        self.ssh_key_edit.setText(credential_store.get_ssh_key_path())
        self._populate_remotes_table()
        self._refresh_keyring_status()

        self._populate_recent_list()
        self._refresh_ai_usage()
        self._refresh_operation_log()

    def _populate_recent_list(self) -> None:
        populate_recent_list(self)
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

        # 第三枪 批次①: advanced AI options
        self._settings.ai_model_chat = self.ai_model_chat_edit.text().strip()
        self._settings.ai_model_json = self.ai_model_json_edit.text().strip()
        self._settings.ai_strict_schema = self.ai_strict_schema_combo.currentData()
        self._settings.ai_cache_enabled = self.ai_cache_check.isChecked()
        self._settings.ai_fill_needs_review = self.ai_fill_needs_review_check.isChecked()
        self._settings.ai_max_parallel_lessons = self.ai_max_parallel_lessons_spin.value()
        self._settings.ai_pipeline_default_mode = self.ai_pipeline_default_mode_combo.currentData()

        self._settings.auto_save_on_close = self.auto_save_check.isChecked()
        self._settings.undo_limit = self.undo_spin.value()

        # Experience OS tab
        self._settings.experience_mode = self.experience_mode_combo.currentData()
        self._settings.experience_immersive_full_auto = (
            self.experience_immersive_full_auto_check.isChecked()
        )
        self._settings.experience_immersive_opaque = (
            self.experience_immersive_opaque_check.isChecked()
        )
        self._settings.experience_goal_enabled = self.experience_goal_check.isChecked()
        self._settings.experience_llm_intent = self.experience_llm_intent_check.isChecked()
        self._settings.experience_allow_dangerous_skills = (
            self.experience_dangerous_check.isChecked()
        )
        self._settings.experience_daily_ai_budget = self.experience_budget_spin.value()

        # Git library tab
        self._settings.git_clone_root = self.git_clone_root_edit.text().strip()
        self._settings.git_bin = self.git_bin_edit.text().strip()
        self._settings.default_lang_code = self.default_lang_edit.text().strip()
        self._settings.git_timeout = self.git_timeout_spin.value()
        self._settings.assets_repo_root = self.assets_repo_root_edit.text().strip()
        self._settings.lan_default_port = self.lan_port_spin.value()
        self._settings.lan_bind_address = self.lan_bind_combo.currentData()
        self._settings.lan_token = self.lan_token_edit.text().strip()
        credential_store.set_ssh_key_path(self.ssh_key_edit.text().strip())

    def _on_provider_changed(self, _index: int) -> None:
        on_provider_changed(self, _index)
    def _on_test_connection(self) -> None:
        on_test_connection(self)
    def _refresh_ai_usage(self) -> None:
        refresh_ai_usage(self)
    @staticmethod
    def _format_usage_bucket(bucket: dict[str, Any]) -> str:
        return format_usage_bucket(bucket)
    @staticmethod
    def _usage_bucket_html(bucket: dict[str, Any]) -> str:
        return usage_bucket_html(bucket)
    def _on_open_telemetry_dir(self) -> None:
        on_open_telemetry_dir(self)
    def _on_clear_telemetry(self) -> None:
        on_clear_telemetry(self)
    def _on_remove_recent(self) -> None:
        on_remove_recent(self)
    def _on_clear_recent(self) -> None:
        on_clear_recent(self)
    def _on_button_clicked(self, button) -> None:
        if self.buttons.buttonRole(button) == QDialogButtonBox.ButtonRole.ApplyRole:
            self._apply()

    def _on_ok(self) -> None:
        self._apply()
        self.accept()

    def _apply(self) -> None:
        self._confirm_experience_mode_change()
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
        self._original.git_clone_root = self._settings.git_clone_root
        self._original.git_bin = self._settings.git_bin
        self._original.default_lang_code = self._settings.default_lang_code
        self._original.lan_default_port = self._settings.lan_default_port
        self._original.lan_bind_address = self._settings.lan_bind_address
        self._original.lan_token = self._settings.lan_token
        self._original.git_timeout = self._settings.git_timeout
        self._original.assets_repo_root = self._settings.assets_repo_root
        # Experience OS tab（含既有缺口补齐：advanced AI 字段此前也不搬运）
        self._original.ai_model_chat = self._settings.ai_model_chat
        self._original.ai_model_json = self._settings.ai_model_json
        self._original.ai_strict_schema = self._settings.ai_strict_schema
        self._original.ai_cache_enabled = self._settings.ai_cache_enabled
        self._original.ai_fill_needs_review = self._settings.ai_fill_needs_review
        self._original.ai_max_parallel_lessons = self._settings.ai_max_parallel_lessons
        self._original.ai_pipeline_default_mode = self._settings.ai_pipeline_default_mode
        self._original.experience_mode = self._settings.experience_mode
        self._original.experience_immersive_full_auto = (
            self._settings.experience_immersive_full_auto
        )
        self._original.experience_immersive_opaque = self._settings.experience_immersive_opaque
        self._original.experience_goal_enabled = self._settings.experience_goal_enabled
        self._original.experience_llm_intent = self._settings.experience_llm_intent
        self._original.experience_allow_dangerous_skills = (
            self._settings.experience_allow_dangerous_skills
        )
        self._original.experience_daily_ai_budget = self._settings.experience_daily_ai_budget
        self.settings_changed.emit()

    def _confirm_experience_mode_change(self) -> bool:
        """Gate immersive entry; on decline, roll the combo back to the live mode.

        Headless/offscreen (tests/CI): safe_question returns ``default_yes``
        (False) without blocking, so immersive cannot be enabled silently.
        """
        new_mode = self.experience_mode_combo.currentData()
        if not should_confirm_immersive_enter(self._original.experience_mode, new_mode):
            return True
        ok = safe_question(self, IMMERSIVE_WARN_TITLE, IMMERSIVE_WARN_TEXT, default_yes=False)
        if ok:
            return True
        idx = self.experience_mode_combo.findData(self._original.experience_mode)
        if idx < 0:
            idx = self.experience_mode_combo.findData("copilot")
        if idx >= 0:
            self.experience_mode_combo.setCurrentIndex(idx)
        return False

    def current_settings(self) -> Settings:
        """Return the working settings object used by the dialog."""
        self._sync_to_settings()
        return self._settings
