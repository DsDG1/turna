"""Shared section-AI dialog engine + workshop generation facade.

This module hosts :class:`SectionAiDialog`, the single implementation of the
normal/wish generation UI **and** of node AI editing (edit_mode engine). Two
thin facades sit on top of it:

- :class:`AiGeneratorDialog` (bottom of this file) — workshop course
  generation UI; generation only, no ``edit_mode``.
- :class:`src.dialogs.ai.node_edit_dialog.NodeAiEditDialog` — production
  entry for course-tree AI editing (ai_refactor_contract §1f).

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
from src.backend.ai_generator import AiApiConfig, AiCourseSpec, ChatMessage
from src.application.ai_prompt_library import prompt_library
from src.dialogs.ai.chat_view import DEFAULT_PALETTE as _CHAT_PALETTE
from src.dialogs.ai.chat_expand_window import ChatExpandWindow
from src.dialogs.ai.result_window import ResultExpandWindow
from src.dialogs.ai.generator_chat_coordinator import GeneratorChatCoordinator, escape_html
from src.dialogs.ai.generator_flows import (
    apply_prompt_fields,
    confirm_structural_removal,
    current_json,
    make_edit_worker,
    on_accept,
    on_alignment_reply_ready,
    on_alignment_worker_done,
    on_explain_error,
    on_explain_ready,
    on_explain_worker_done,
    on_generate_normal,
    on_history_applied,
    on_normal_generation_ready,
    on_normal_worker_done,
    on_preview_node_activated,
    on_preview_validity,
    on_reset,
    on_send_message,
    on_template_applied,
    on_try_preview,
    on_validate_from_editor,
    on_validate_json,
    on_view_diff,
    on_wish_generate,
    on_wish_generation_completed,
    on_wish_generation_ready,
)
from src.dialogs.ai.generator_panels import (
    build_beta_banner,
    build_header_bar,
    build_normal_panel,
    build_result_group,
    build_spec_bar,
    build_template_selector,
    build_topic_panel,
    build_topic_row,
    build_ui,
    build_wish_panel,
    set_tab_order,
)
from src.dialogs.ai.generator_preview_coordinator import (
    GeneratorPreviewCoordinator,
    find_line_for_path,
)
from src.dialogs.ai.generator_wizard_panel import GeneratorWizardPanel
from src.dialogs.ai.generator_view_state import (
    ai_generation_kwargs,
    ai_retry_max,
    apply_edit_mode_ui,
    bar_in_slot,
    course_resource_summary,
    current_spec,
    current_topic_text,
    current_usage_label,
    ensure_api_configured,
    on_chunk_rendered,
    on_mode_changed,
    on_topic_text_changed,
    on_usage_updated,
    place_template_bar,
    reconnect,
    set_busy,
    set_stage_label,
    set_template_combo,
    sync_json_window_on_mode_switch,
    sync_template_from_genre_tags,
    update_api_status,
    update_input_placeholders,
    update_mode_ui,
)
from src.dialogs.ai.generator_worker_hub import GeneratorWorkerHub, record_cache_stats
from src.application.ai_request_worker import (
    AttachmentRecord as _AttachmentRecord,
    AiRequestWorker,
)

logger = logging.getLogger(__name__)

# Backward-compat aliases
_record_cache_stats = record_cache_stats
_escape_html = escape_html


class SectionAiDialog(QDialog):
    """Shared engine behind the generation and node-edit dialogs.

    On accept, ``section_json()`` returns the (possibly edited) section dict
    ready to be appended to ``adapter.sections`` and registered in the index.

    ``edit_mode`` is an internal engine switch (instruction rewrite + chat
    revision of an existing section); external callers must go through
    :class:`src.dialogs.ai.node_edit_dialog.NodeAiEditDialog` instead of
    passing it directly.
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
        build_ui(self)

    def _set_tab_order(self) -> None:
        set_tab_order(self)

    def _build_beta_banner(self) -> QWidget:
        return build_beta_banner(self)

    def _build_header_bar(self) -> QWidget:
        return build_header_bar(self)

    def _build_spec_bar(self) -> QWidget:
        return build_spec_bar(self)

    def _build_template_selector(self) -> QWidget:
        return build_template_selector(self)

    def _on_template_changed_value(self, template: str) -> None:
        self._update_input_placeholders()

    def _on_genre_toggled(self, enabled: bool) -> None:
        self._update_input_placeholders()
        self._sync_template_from_genre_tags()

    def _build_normal_panel(self) -> QWidget:
        return build_normal_panel(self)

    def _build_topic_panel(self) -> QWidget:
        return build_topic_panel(self)

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
        return build_topic_row(self)

    def _build_result_group(self) -> QGroupBox:
        return build_result_group(self)

    def _build_wish_panel(self) -> QWidget:
        return build_wish_panel(self)

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
        apply_edit_mode_ui(self)

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
        on_mode_changed(self, index)

    def _update_mode_ui(self) -> None:
        update_mode_ui(self)

    def _sync_json_window_on_mode_switch(self) -> None:
        sync_json_window_on_mode_switch(self)

    def _place_template_bar(self, is_normal: bool) -> None:
        place_template_bar(self, is_normal)

    @staticmethod
    def _bar_in_slot(slot, bar) -> bool:
        return bar_in_slot(slot, bar)

    def _current_topic_text(self) -> str:
        return current_topic_text(self)

    def _update_input_placeholders(self) -> None:
        update_input_placeholders(self)

    def _on_topic_text_changed(self, text: str) -> None:
        on_topic_text_changed(self, text)

    def _sync_template_from_genre_tags(self) -> None:
        sync_template_from_genre_tags(self)

    def _set_template_combo(self, template: str) -> None:
        set_template_combo(self, template)

    def _ensure_api_configured(self) -> bool:
        return ensure_api_configured(self)

    def _update_api_status(self) -> None:
        update_api_status(self)

    def _reconnect(self, btn, slot) -> None:
        reconnect(self, btn, slot)

    def _set_busy(self, busy: bool, normal: bool = False, stage: str = "") -> None:
        set_busy(self, busy, normal=normal, stage=stage)
    def _set_stage_label(self, stage: str) -> None:
        set_stage_label(self, stage)

    # --- Streaming chunk + usage display --------------------------------

    def _current_usage_label(self) -> QLabel:
        return current_usage_label(self)

    def _on_worker_chunk(self, fragment: str) -> None:
        self._worker_hub.on_worker_chunk(fragment)

    def _on_chunk_rendered(self, text: str, final: bool) -> None:
        on_chunk_rendered(self, text, final)

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
        on_usage_updated(self, line, usage_dict)

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
        return current_spec(self)

    def _course_resource_summary(self) -> dict[str, list] | None:
        return course_resource_summary(self)

    def _apply_prompt_fields(self, obj) -> None:
        apply_prompt_fields(self, obj)

    def _on_template_applied(self, obj: object) -> None:
        on_template_applied(self, obj)

    def _on_history_applied(self, entry: object) -> None:
        on_history_applied(self, entry)

    # --- Normal mode actions ---------------------------------------------

    def _ai_retry_max(self) -> int:
        return ai_retry_max(self)

    def _ai_generation_kwargs(self) -> dict[str, Any]:
        return ai_generation_kwargs(self)

    def _make_edit_worker(self, spec: AiCourseSpec, **kwargs: Any) -> AiRequestWorker:
        return make_edit_worker(self, spec, **kwargs)

    def _on_generate_normal(self) -> None:
        on_generate_normal(self)

    def _on_normal_generation_ready(self, parsed: object) -> None:
        on_normal_generation_ready(self, parsed)

    def _confirm_structural_removal(self, diff: dict[str, set[str]]) -> bool:
        return confirm_structural_removal(self, diff)

    def _on_normal_worker_done(self) -> None:
        on_normal_worker_done(self)

    def _on_preview_validity(self, ok: bool) -> None:
        on_preview_validity(self, ok)

    def _on_reset(self) -> None:
        on_reset(self)

    def _on_view_diff(self) -> None:
        on_view_diff(self)

    def _on_try_preview(self) -> None:
        on_try_preview(self)

    def _on_validate_json(self) -> None:
        on_validate_json(self)

    def _on_validate_from_editor(self) -> None:
        on_validate_from_editor(self)

    def _current_json(self) -> dict:
        return current_json(self)

    def _on_preview_node_activated(self, path: str) -> None:
        on_preview_node_activated(self, path)

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
        on_send_message(self)

    def _on_alignment_worker_done(self) -> None:
        on_alignment_worker_done(self)

    def _on_alignment_reply_ready(self, reply: object) -> None:
        on_alignment_reply_ready(self, reply)

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
        on_wish_generate(self)

    def _on_wish_generation_completed(self) -> None:
        on_wish_generation_completed(self)

    def _on_wish_generation_ready(self, parsed: object) -> None:
        on_wish_generation_ready(self, parsed)

    def _on_explain_worker_done(self) -> None:
        on_explain_worker_done(self)

    def _on_explain_ready(self, explanation: object) -> None:
        on_explain_ready(self, explanation)

    def _on_explain_error(self, message: str) -> None:
        on_explain_error(self, message)

    # --- Import / accept -------------------------------------------------

    def _on_accept(self) -> None:
        on_accept(self)

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


class AiGeneratorDialog(SectionAiDialog):
    """Workshop course-generation UI (LEGACY name kept for compatibility).

    Generation-only facade over :class:`SectionAiDialog`. Node AI editing has
    moved to :class:`src.dialogs.ai.node_edit_dialog.NodeAiEditDialog`; this
    class no longer accepts an ``edit_mode`` argument.
    """

    def __init__(self, adapter, parent: QWidget | None = None) -> None:
        super().__init__(adapter, parent, edit_mode=None)
