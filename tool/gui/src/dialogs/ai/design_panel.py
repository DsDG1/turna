"""Embeddable design / chat panel for the workshop.

Layout compression (L1): generation params live on the middle **Orbit** bar.
This panel is the secondary surface — chat, attachments, prompt templates,
pipeline switches, and optional JSON. Emits ``sections_ready`` for import.

All state lives in ``DesignController``; the panel renders and forwards.
"""
from __future__ import annotations

import logging
logger = logging.getLogger(__name__)


import html
import tempfile
import uuid
from pathlib import Path
from typing import Any

from PySide6.QtCore import Qt, QTimer, Signal
from PySide6.QtWidgets import (
    QCheckBox,
    QComboBox,
    QFileDialog,
    QGroupBox,
    QHBoxLayout,
    QInputDialog,
    QLabel,
    QLineEdit,
    QMessageBox,
    QPushButton,
    QSpinBox,
    QSplitter,
    QTextBrowser,
    QVBoxLayout,
    QWidget,
)

from src.backend.ai_prompt_library import (
    AiPromptHistory,
    AiPromptTemplate,
    prompt_library,
)
from src.backend.ai_pipeline import (
    CHECKLIST_STEPS,
    STATUS_DONE,
    STATUS_FAILED,
    STATUS_RUNNING,
    STATUS_SKIPPED,
)
from src.backend.attachment_extractor import extract_attachment
from src.dialogs.ai.attachment_bar import AttachmentBar
from src.dialogs.ai.chat_view import ChatView
from src.dialogs.ai.design_controller import DesignController
from src.dialogs.ai.prompt_template_bar import PromptTemplateBar
from src.dialogs.ai.worker import AttachmentRecord
from src.widgets.json_editor import JsonEditor

_TEMPLATES = ("mixed", "intro", "practice", "review", "listening", "reading", "mastery")
_LEVELS = ("A1", "A2", "B1", "B2", "C1")

#: Chinese labels / status marks for the refine-pipeline checklist (Phase 5).
_STEP_LABELS = {
    "plan": "规划",
    "outline": "大纲",
    "generate": "生成",
    "validate": "校验",
    "quality": "质量",
    "fix": "修复",
    "explain": "解释",
}
_STEP_MARKS = {
    STATUS_RUNNING: "…",
    STATUS_DONE: "✓",
    STATUS_SKIPPED: "—",
    STATUS_FAILED: "✗",
}


class DesignPanel(QWidget):
    """Grounded course-design widget (params + chat → draft → import)."""

    #: (list[dict], strategy) — one draft section ready for import.
    sections_ready = Signal(list, str)
    #: A full draft landed in the JSON editor (generation finished).
    draft_ready = Signal()
    #: (busy, stage text) — for the workshop's unified bottom bar.
    busy_changed = Signal(bool, str)
    #: Formatted usage line — for the workshop's unified bottom bar.
    usage_changed = Signal(str)
    #: (temp_path, original_name, unlink_after) — requested OCR
    ocr_requested = Signal(str, str, bool)

    def __init__(
        self,
        adapter: Any,
        parent: QWidget | None = None,
        *,
        controller: DesignController | None = None,
    ) -> None:
        super().__init__(parent)
        self.adapter = adapter
        self._project = None
        self._store = None
        self._stream_buffer = ""
        self._chat_stream_buffer = ""
        self._explain_stream_buffer = ""
        self._last_raw_output = ""
        # Streaming throttle: chunks only append to Python buffers; the views
        # are re-rendered at most once per interval instead of per SSE chunk
        # (full-document setPlainText/setHtml per chunk is O(n^2) overall).
        self._stream_dirty: set[str] = set()
        self._stream_flush_timer = QTimer(self)
        self._stream_flush_timer.setSingleShot(True)
        self._stream_flush_timer.setInterval(120)
        self._stream_flush_timer.timeout.connect(self._flush_stream_views)
        # P2: skip full JSON setPlainText while generating large drafts.
        self._STREAM_JSON_LIVE_LIMIT = 8_192
        # Same guard for the plain-text explanation stream (setHtml of a huge
        # escaped document every flush re-lays-out the whole QTextBrowser).
        self._STREAM_EXPLAIN_LIVE_LIMIT = 8_192
        self._generating = False
        # P2: throttle disk autosave (especially around design_changed bursts).
        self._autosave_timer = QTimer(self)
        self._autosave_timer.setSingleShot(True)
        self._autosave_timer.setInterval(2_000)
        self._autosave_timer.timeout.connect(self._autosave_now)
        self._autosave_dirty = False
        self.setAcceptDrops(True)

        if controller is None:
            from src.application.ai_runtime import runtime_from_host

            runtime = runtime_from_host(self)
            controller = DesignController(
                ai_config_fn=runtime.config,
                settings_fn=runtime.settings,
                validator=(
                    adapter.validate_section_json if adapter is not None else None
                ),
            )
        self._controller = controller
        self._wire_controller()
        self._build_ui()
        self._refresh_pool_summary()
        self._refresh_chat()

    # ------------------------------------------------------------------ wiring
    def _wire_controller(self) -> None:
        c = self._controller
        c._on_chat_updated = self._refresh_chat
        c._on_chat_stream_chunk = self._on_chat_chunk
        c._on_draft_ready = self._on_draft_ready
        c._on_stream_chunk = self._on_draft_chunk
        c._on_error = self._on_error
        c._on_busy_changed = self._on_busy_changed
        c._on_usage_update = self._on_usage_update
        c._on_design_changed = self._autosave
        c._on_explanation = self._on_explanation
        c._on_explanation_chunk = self._on_explanation_chunk
        c._on_explanation_error = self._on_explanation_error
        c._on_pipeline_step = self._on_pipeline_step

    # ------------------------------------------------------------------ UI
    def _build_ui(self) -> None:
        layout = QVBoxLayout(self)
        layout.setContentsMargins(8, 8, 8, 8)
        layout.setSpacing(6)

        self._pool_label = QLabel("")
        self._pool_label.setStyleSheet("font-weight: 600;")
        layout.addWidget(self._pool_label)

        self._param_hint = QLabel(
            "主参数（主题 / 等级 / 规模 / 生成模式）在中间「AI 轨道」设置。"
        )
        self._param_hint.setWordWrap(True)
        self._param_hint.setStyleSheet("font-size: 11px; opacity: 0.85;")
        layout.addWidget(self._param_hint)

        # Hidden mirrors kept for tests / set_project restore; not shown.
        # Primary editing surface is Orbit when embedded in the workshop.
        self._topic_edit = QLineEdit()
        self._topic_edit.setVisible(False)
        self._level_combo = QComboBox()
        self._level_combo.addItems(_LEVELS)
        self._level_combo.setVisible(False)
        self._units_spin = QSpinBox()
        self._units_spin.setRange(1, 5)
        self._units_spin.setVisible(False)
        self._lessons_spin = QSpinBox()
        self._lessons_spin.setRange(1, 5)
        self._lessons_spin.setValue(3)
        self._lessons_spin.setVisible(False)
        self._template_combo = QComboBox()
        self._template_combo.addItems(_TEMPLATES)
        self._template_combo.setVisible(False)
        self._gen_mode_combo = QComboBox()
        self._gen_mode_combo.addItem("快速（整节）", "fast")
        self._gen_mode_combo.addItem("精修（流水线）", "phased")
        self._gen_mode_combo.setVisible(False)
        self._gen_mode_combo.currentIndexChanged.connect(self._on_gen_mode_changed)
        self._level_combo.currentTextChanged.connect(
            lambda _t: self._refresh_pedagogy_badge()
        )
        for w in (
            self._topic_edit,
            self._level_combo,
            self._units_spin,
            self._lessons_spin,
            self._template_combo,
            self._gen_mode_combo,
        ):
            layout.addWidget(w)

        # --- Chat (primary content of this panel) ---
        self._chat_view = ChatView()
        layout.addWidget(self._chat_view, 1)

        self._ocr_enabled = False
        self._attachment_bar = AttachmentBar(self)
        self._attachment_bar.ocr_requested.connect(self.ocr_requested.emit)
        layout.addWidget(self._attachment_bar)

        chat_row = QHBoxLayout()
        self._attach_btn = QPushButton("附件")
        self._attach_btn.setToolTip("添加图片 / PDF / Word / 文本文件作为参考")
        self._attach_btn.clicked.connect(self._on_attach_files)
        chat_row.addWidget(self._attach_btn)
        self._chat_input = QLineEdit()
        self._chat_input.setPlaceholderText("与 AI 讨论课程设计…（回车发送）")
        self._chat_input.returnPressed.connect(self._on_send_chat)
        chat_row.addWidget(self._chat_input, 1)
        self._send_btn = QPushButton("发送")
        self._send_btn.clicked.connect(self._on_send_chat)
        chat_row.addWidget(self._send_btn)
        layout.addLayout(chat_row)

        gen_row = QHBoxLayout()
        self._generate_btn = QPushButton("按对话再生成")
        self._generate_btn.setToolTip(
            "用当前聊天记录 + 中栏轨道参数生成/改写课程（无对话时等同中栏生成）"
        )
        self._generate_btn.clicked.connect(self._on_generate)
        gen_row.addWidget(self._generate_btn)
        self._stage_label = QLabel("")
        gen_row.addWidget(self._stage_label)
        gen_row.addStretch(1)
        self._usage_label = QLabel("")
        gen_row.addWidget(self._usage_label)
        layout.addLayout(gen_row)

        self._checklist_widget = QWidget()
        checklist_row = QHBoxLayout(self._checklist_widget)
        checklist_row.setContentsMargins(0, 0, 0, 0)
        checklist_row.setSpacing(8)
        self._checklist_labels: dict[str, QLabel] = {}
        for step in CHECKLIST_STEPS:
            label = QLabel()
            label.setStyleSheet("color: gray;")
            self._checklist_labels[step] = label
            checklist_row.addWidget(label)
        checklist_row.addStretch(1)
        self._render_pipeline_checklist({})
        self._checklist_widget.setVisible(False)
        layout.addWidget(self._checklist_widget)

        self._fast_progress_label = QLabel("")
        self._fast_progress_label.setStyleSheet("color: gray; font-size: 11px;")
        self._fast_progress_label.setVisible(False)
        layout.addWidget(self._fast_progress_label)

        # --- Advanced (collapsed): intent, extras, templates, pipeline skips ---
        self._advanced_group = QGroupBox("高级：模板 · 意图 · 精修选项")
        self._advanced_group.setCheckable(True)
        self._advanced_group.setChecked(False)
        self._advanced_group.setFlat(False)
        adv_lay = QVBoxLayout(self._advanced_group)
        adv_lay.setSpacing(6)

        self._pedagogy_badge = QLabel("")
        self._pedagogy_badge.setStyleSheet(
            "color: #0f766e; font-size: 11px; font-weight: 600;"
        )
        adv_lay.addWidget(self._pedagogy_badge)
        self._refresh_pedagogy_badge()

        skip_row = QHBoxLayout()
        self._skip_fix_check = QCheckBox("跳过修复")
        self._skip_fix_check.setToolTip("精修流水线跳过 Fix 步")
        self._skip_explain_check = QCheckBox("跳过解释")
        self._skip_explain_check.setToolTip("精修流水线跳过 Explain 步")
        skip_row.addWidget(self._skip_fix_check)
        skip_row.addWidget(self._skip_explain_check)
        skip_row.addStretch(1)
        adv_lay.addLayout(skip_row)

        brief_row = QHBoxLayout()
        brief_row.addWidget(QLabel("编排意图:"))
        self._brief_edit = QLineEdit()
        self._brief_edit.setPlaceholderText("可选，如：前两章 intro，语法单独 review")
        brief_row.addWidget(self._brief_edit, 1)
        adv_lay.addLayout(brief_row)

        extra_row = QHBoxLayout()
        extra_row.addWidget(QLabel("额外指令:"))
        self._extra_edit = QLineEdit()
        self._extra_edit.setPlaceholderText("可选；开启 [genre] 后可插入 [intro] 等")
        extra_row.addWidget(self._extra_edit, 1)
        adv_lay.addLayout(extra_row)

        self._template_bar = PromptTemplateBar(self)
        self._template_bar.set_library(prompt_library())
        self._template_bar.template_applied.connect(self._on_template_applied)
        self._template_bar.history_applied.connect(self._on_history_applied)
        self._template_bar.template_changed.connect(self._on_bar_template_changed)
        self._template_bar.genre_toggled.connect(self._on_genre_toggled)
        self._template_combo.currentTextChanged.connect(self._on_combo_template_changed)
        adv_lay.addWidget(self._template_bar)

        layout.addWidget(self._advanced_group)

        # --- JSON (collapsed by default) ---
        self._json_group = QGroupBox("高级：草稿 JSON")
        self._json_group.setCheckable(True)
        self._json_group.setChecked(False)
        json_outer = QVBoxLayout(self._json_group)
        self._json_editor = JsonEditor()
        self._json_editor.setMinimumHeight(120)
        json_outer.addWidget(self._json_editor, 1)
        action_row = QHBoxLayout()
        self._validate_btn = QPushButton("校验")
        self._validate_btn.clicked.connect(self._on_validate)
        action_row.addWidget(self._validate_btn)
        self._try_btn = QPushButton("试做")
        self._try_btn.clicked.connect(self._on_try_lesson)
        action_row.addWidget(self._try_btn)
        self._restore_raw_btn = QPushButton("恢复原始输出")
        self._restore_raw_btn.setToolTip("放弃手动修改，回到 AI 刚生成的内容")
        self._restore_raw_btn.clicked.connect(self._on_restore_raw)
        action_row.addWidget(self._restore_raw_btn)
        action_row.addStretch(1)
        self._import_btn = QPushButton("导入到课程 ↗")
        self._import_btn.clicked.connect(self._on_import)
        action_row.addWidget(self._import_btn)
        json_outer.addLayout(action_row)
        self._validate_label = QLabel("")
        json_outer.addWidget(self._validate_label)
        layout.addWidget(self._json_group)

        self._explain_group = QGroupBox("AI 通俗解释")
        self._explain_group.setCheckable(True)
        self._explain_group.setChecked(False)
        self._explain_group.setVisible(False)
        explain_lay = QVBoxLayout(self._explain_group)
        self._explain_browser = QTextBrowser()
        self._explain_browser.setMaximumHeight(120)
        explain_lay.addWidget(self._explain_browser)
        layout.addWidget(self._explain_group)

        for btn in (self._validate_btn, self._try_btn, self._import_btn):
            btn.setEnabled(False)
        self._restore_raw_btn.setEnabled(False)
        self._on_gen_mode_changed(self._gen_mode_combo.currentIndex())

    # ------------------------------------------------------------------ project binding
    def has_draft(self) -> bool:
        """True once a draft exists (generated or restored from the project)."""
        return self._controller.draft is not None

    def set_status_widgets_visible(self, visible: bool) -> None:
        """Show/hide the inline stage/usage labels (hidden inside the
        workshop, which renders the same state in its unified bottom bar)."""
        self._stage_label.setVisible(visible)
        self._usage_label.setVisible(visible)

    @staticmethod
    def _pool_entries(resource_pool: dict) -> list[dict]:
        pool = []
        for e in resource_pool.get("words", []):
            pool.append({**e, "_kind": "word"})
        for e in resource_pool.get("expressions", []):
            pool.append({**e, "_kind": "expression"})
        for e in resource_pool.get("grammarPoints", []):
            pool.append({**e, "_kind": "grammar"})
        return pool

    def apply_orbit_params(self, params: dict[str, Any]) -> None:
        """Mirror orbit params into hidden widgets (chat path / tests)."""
        self._topic_edit.setText(params.get("topic", "") or "")
        self._level_combo.setCurrentText(params.get("level", "A1") or "A1")
        self._units_spin.setValue(int(params.get("unit_count", 1) or 1))
        self._lessons_spin.setValue(int(params.get("lessons_per_unit", 3) or 3))
        tmpl = params.get("template", "mixed") or "mixed"
        if tmpl in _TEMPLATES:
            self._template_combo.setCurrentText(tmpl)
        mode = str(params.get("generation_mode") or "fast")
        idx = self._gen_mode_combo.findData(mode)
        if idx < 0 and mode == "refine":
            idx = self._gen_mode_combo.findData("phased")
        self._gen_mode_combo.setCurrentIndex(idx if idx >= 0 else 0)
        if "extra_instructions" in params:
            self._extra_edit.setText(params.get("extra_instructions") or "")
        self._refresh_pedagogy_badge()

    def set_project(self, project: Any, store: Any) -> None:
        """Bind to a textbook project: pool grounding + design persistence."""
        self._project = project
        self._store = store
        self._pool_fp: tuple | None = None
        self._controller.set_languages(project.language, project.source_language)
        self.refresh_pool_from_project()
        self._controller.apply_design_dict(project.design)
        # Restore params into mirrors + advanced fields.
        params = self._controller.params
        self.apply_orbit_params(params)
        self._brief_edit.setText(params.get("design_brief", ""))
        self._extra_edit.setText(params.get("extra_instructions", ""))
        self._template_bar.select_template(params.get("template", "mixed"), emit=False)
        self._template_bar.set_genre_enabled(bool(params.get("use_genre_batch", False)))
        self._skip_fix_check.setChecked(bool(params.get("pipeline_skip_fix", False)))
        self._skip_explain_check.setChecked(bool(params.get("pipeline_skip_explain", False)))
        self._on_gen_mode_changed(self._gen_mode_combo.currentIndex())
        self._refresh_chat()
        self._render_explanation(self._controller.explanation)
        # Expand JSON group if a draft already exists.
        if self._controller.draft is not None:
            self._json_group.setChecked(True)
            self._json_editor.set_json(self._controller.draft)
            for btn in (self._validate_btn, self._try_btn, self._import_btn):
                btn.setEnabled(True)

    def refresh_pool_from_project(self) -> bool:
        """Re-read the project's resource pool (knowledge stage may have
        edited it). Returns True when the pool fingerprint changed."""
        if self._project is None:
            return False
        rp = self._project.resource_pool or {}
        fingerprint = (
            len(rp.get("words", [])),
            len(rp.get("expressions", [])),
            len(rp.get("grammarPoints", [])),
            rp.get("updated_at", ""),
        )
        if fingerprint == self._pool_fp:
            return False
        self._pool_fp = fingerprint
        self._controller.set_resource_pool(self._pool_entries(rp))
        self._refresh_pool_summary()
        return True

    def notice_pool_updated(self) -> None:
        """Tell the user the pool changed under an existing draft (§2.2)."""
        if self._controller.draft is not None:
            self._pool_label.setText(
                self._pool_label.text() + "（资源池已更新，建议重新生成）"
            )

    def _autosave(self) -> None:
        """Schedule a throttled project write (P2); coalesce while generating."""
        if self._project is None or self._store is None:
            return
        self._autosave_dirty = True
        if self._generating:
            # draft_ready / flush_autosave will force-write; skip timer chatter.
            return
        self._autosave_timer.start()

    def _autosave_now(self) -> None:
        if self._project is None or self._store is None:
            return
        self._autosave_dirty = False
        try:
            self._project.design = self._controller.to_design_dict()
            self._store.save_project(self._project)
        except Exception:
            logger.debug("dialogs/ai/design_panel.py:473 best-effort step failed", exc_info=True)

    def flush_autosave(self) -> None:
        """Persist any pending design state immediately (workshop interrupt)."""
        self._autosave_timer.stop()
        if self._project is None or self._store is None:
            return
        self._autosave_now()

    # ------------------------------------------------------------------ rendering
    def _refresh_pool_summary(self) -> None:
        pool = self._controller.resource_pool
        if not pool:
            self._pool_label.setText("资源池为空 — 自由生成模式（可先从教材提取知识点）")
            return
        words = sum(1 for e in pool if e.get("_kind") == "word")
        exprs = sum(1 for e in pool if e.get("_kind") == "expression")
        grammar = sum(1 for e in pool if e.get("_kind") == "grammar")
        self._pool_label.setText(
            f"资源池：{words} 词 · {exprs} 表达 · {grammar} 语法点（AI 将从池中选词编排）"
        )

    def _refresh_chat(self) -> None:
        self._cancel_stream_flush()
        self._chat_view.render(self._controller.chat)

    def _on_chat_chunk(self, text: str) -> None:
        self._chat_stream_buffer += text
        self._mark_stream_dirty("chat")

    def _mark_stream_dirty(self, kind: str) -> None:
        """Schedule a throttled re-render of the streamed views."""
        self._stream_dirty.add(kind)
        self._stream_flush_timer.start()

    def _cancel_stream_flush(self) -> None:
        """Drop pending flushes (a finalizing render owns the view now)."""
        self._stream_flush_timer.stop()
        self._stream_dirty.clear()

    def _flush_stream_views(self) -> None:
        """Render pending streamed text (runs at most once per interval)."""
        dirty, self._stream_dirty = self._stream_dirty, set()
        if "chat" in dirty and self._chat_stream_buffer:
            self._chat_view.render_streaming(
                self._controller.chat, self._chat_stream_buffer
            )
        if "draft" in dirty and self._stream_buffer:
            n = len(self._stream_buffer)
            # P2: avoid O(n) full-document setPlainText for large streams.
            # Small buffers still stream into the editor; large ones only update a summary.
            if self._generating and n > self._STREAM_JSON_LIVE_LIMIT:
                self._validate_label.setText(f"生成中… 已接收约 {n} 字符")
            else:
                self._json_editor.setPlainText(self._stream_buffer)
                if self._generating:
                    self._validate_label.setText(f"生成中… 已接收约 {n} 字符")
        if "explain" in dirty and self._explain_stream_buffer:
            n_explain = len(self._explain_stream_buffer)
            if n_explain > self._STREAM_EXPLAIN_LIVE_LIMIT:
                # Final full text lands via _on_explanation (separate entry).
                self._render_explanation(
                    f"（解释生成中… 已接收约 {n_explain} 字符）"
                )
            else:
                self._render_explanation(self._explain_stream_buffer)

    def _on_draft_ready(self, section: dict) -> None:
        self._cancel_stream_flush()
        self._last_raw_output = self._stream_buffer
        self._stream_buffer = ""
        self._generating = False
        self._json_editor.set_json(section)
        # Keep JSON folded by default — outline is the primary result surface.
        if not self._json_group.isChecked():
            pass  # leave collapsed; user can expand for raw JSON
        cache_note = " · 缓存✓" if self._controller.last_cache_hit else ""
        self._validate_label.setText(
            f"✓ 已生成 · {len(section.get('units', []))} 单元 · "
            f"{len(section.get('words', []))} 词{cache_note} — 请看「结构大纲」摘要"
        )
        self._set_fast_progress("done")
        for btn in (self._validate_btn, self._try_btn, self._import_btn):
            btn.setEnabled(True)
        self._restore_raw_btn.setEnabled(bool(self._last_raw_output))
        self.draft_ready.emit()
        # Persist draft promptly after generation (bypass busy skip).
        self.flush_autosave()
        # Refresh status line with cache flag.
        self._on_usage_update(self._controller.usage)

    def _on_draft_chunk(self, text: str) -> None:
        self._stream_buffer += text
        self._mark_stream_dirty("draft")

    def _on_error(self, message: str) -> None:
        QMessageBox.warning(self, "AI 设计", message)

    def _on_busy_changed(self, busy: bool, stage: str) -> None:
        self._generate_btn.setText("取消生成" if busy else "生成课程 ▶")
        self._stage_label.setText(stage)
        self._send_btn.setEnabled(not busy)
        self._attach_btn.setEnabled(not busy)
        # Treat "生成" / "重生" stages as generation for stream-summary mode.
        # "重生课时…" / "重生育元…" (local regenerate) also stream large JSON.
        if busy and ("生成" in (stage or "") or "重生" in (stage or "")):
            self._generating = True
        elif not busy:
            self._generating = False
        if busy:
            self._cancel_stream_flush()
            self._stream_buffer = ""
            self._chat_stream_buffer = ""
            if self._generating:
                self._validate_label.setText("生成中…")
            if self._gen_mode_combo.currentData() != "phased":
                self._set_fast_progress("生成")
            else:
                self._fast_progress_label.setVisible(False)
        self.busy_changed.emit(busy, stage)

    def _on_usage_update(self, usage: dict) -> None:
        from src.backend.ai_summary import format_ai_status_line

        cfg = self._controller.ai_config()
        model_json = (
            getattr(cfg, "model_json", None) or getattr(cfg, "model", "") or ""
        )
        model_chat = (
            getattr(cfg, "model_chat", None) or getattr(cfg, "model", "") or ""
        )
        mode = str(self._controller.params.get("generation_mode") or "fast")
        text = format_ai_status_line(
            model_json=str(model_json),
            model_chat=str(model_chat),
            cache_hit=self._controller.last_cache_hit if not self._controller.is_busy else None,
            usage=usage if isinstance(usage, dict) else None,
            mode=mode,
        )
        if not text:
            from src.backend.ai_usage import format_usage_line

            text = format_usage_line(usage, model_json)
        self._usage_label.setText(text)
        self.usage_changed.emit(text)

    # ------------------------------------------------------------------ explanation
    def _render_explanation(self, text: str) -> None:
        if not text:
            self._explain_group.setVisible(False)
            return
        self._explain_browser.setHtml(
            f"<div style='line-height:1.5'>{html.escape(text).replace(chr(10), '<br>')}</div>"
        )
        self._explain_group.setVisible(True)
        self._explain_group.setChecked(True)

    def _on_explanation(self, text: str) -> None:
        self._cancel_stream_flush()
        self._explain_stream_buffer = ""
        self._render_explanation(text)

    def _on_explanation_chunk(self, text: str) -> None:
        self._explain_stream_buffer += text
        self._mark_stream_dirty("explain")

    def _on_explanation_error(self, message: str) -> None:
        self._explain_browser.setHtml(
            f"<span style='color:#dc2626'>解释生成失败：{html.escape(message)}</span>"
        )
        self._explain_group.setVisible(True)

    # ------------------------------------------------------------------ pipeline checklist
    def _on_gen_mode_changed(self, _index: int) -> None:
        """Refine-only controls (skip switches, checklist) follow the mode."""
        refine = self._gen_mode_combo.currentData() == "phased"
        self._skip_fix_check.setEnabled(refine)
        self._skip_explain_check.setEnabled(refine)
        if not refine:
            self._checklist_widget.setVisible(False)
        self._refresh_pedagogy_badge()

    def _refresh_pedagogy_badge(self) -> None:
        """U0-5: show that CEFR/language pedagogy constraints are injected."""
        level = self._level_combo.currentText() if hasattr(self, "_level_combo") else "A1"
        lang = getattr(self._controller, "_language", None) or "Turkish"
        # Short language code hint for badge.
        code = "tr" if "turk" in str(lang).lower() or lang == "tr" else str(lang)[:8]
        self._pedagogy_badge.setText(f"已注入 {code}·{level} 教学约束")
        self._pedagogy_badge.setToolTip(
            "生成 prompt 会注入 CEFR 软约束、干扰项规则与语言包（如 Turkish 元音和谐/敬语）。"
        )

    def _render_pipeline_checklist(self, statuses: dict[str, str]) -> None:
        for step, label in self._checklist_labels.items():
            status = statuses.get(step, "pending")
            mark = _STEP_MARKS.get(status, "○")
            label.setText(f"{mark}{_STEP_LABELS.get(step, step)}")
            if status == STATUS_FAILED:
                label.setStyleSheet("color: #dc2626; font-weight: 700;")
                label.setToolTip(f"{_STEP_LABELS.get(step, step)} 失败")
            elif status == STATUS_DONE:
                label.setStyleSheet("color: #16a34a;")
                label.setToolTip(f"{_STEP_LABELS.get(step, step)} 完成")
            elif status == STATUS_RUNNING:
                label.setStyleSheet("color: #d97706; font-weight: 700;")
                label.setToolTip(f"{_STEP_LABELS.get(step, step)} 进行中…")
            elif status == STATUS_SKIPPED:
                label.setStyleSheet("color: gray;")
                label.setToolTip(f"{_STEP_LABELS.get(step, step)} 已跳过")
            else:
                label.setStyleSheet("color: gray;")
                label.setToolTip(f"{_STEP_LABELS.get(step, step)} 等待")

    def _on_pipeline_step(self, statuses: dict[str, str]) -> None:
        """Controller push: render step statuses (pending/running/done/...)."""
        if self._gen_mode_combo.currentData() == "phased":
            self._checklist_widget.setVisible(True)
            self._fast_progress_label.setVisible(False)
        self._render_pipeline_checklist(statuses)

    def _set_fast_progress(self, phase: str) -> None:
        """Mini three-state story for fast mode: 生成 / 校验 / 质量."""
        order = ("生成", "校验", "质量")
        if phase != "done" and phase not in order:
            self._fast_progress_label.setVisible(False)
            return
        parts = []
        if phase == "done":
            parts = [f"✓{step}" for step in order]
        else:
            idx = order.index(phase)
            for i, step in enumerate(order):
                if i < idx:
                    parts.append(f"✓{step}")
                elif i == idx:
                    parts.append(f"…{step}")
                else:
                    parts.append(f"○{step}")
        self._fast_progress_label.setText(" · ".join(parts))
        self._fast_progress_label.setVisible(
            self._gen_mode_combo.currentData() != "phased"
        )

    # ------------------------------------------------------------------ template bar
    def _on_bar_template_changed(self, template: str) -> None:
        if template in _TEMPLATES:
            self._template_combo.blockSignals(True)
            self._template_combo.setCurrentText(template)
            self._template_combo.blockSignals(False)

    def _on_combo_template_changed(self, template: str) -> None:
        self._template_bar.select_template(template, emit=False)

    def _on_genre_toggled(self, _enabled: bool) -> None:
        self._template_bar.update_placeholders(self._topic_edit, self._extra_edit)

    def _on_template_applied(self, obj: object) -> None:
        """Apply a saved template or handle a save request from the bar."""
        if isinstance(obj, dict) and obj.get("action") == "save_request":
            if obj.get("name"):
                self._sync_params()
                self._template_bar.save_current_template(
                    self._controller.build_spec()
                )
            return
        if isinstance(obj, AiPromptTemplate):
            self._topic_edit.setText(obj.topic)
            self._level_combo.setCurrentText(obj.level)
            self._units_spin.setValue(obj.unit_count)
            self._lessons_spin.setValue(obj.lessons_per_unit)
            self._template_bar.select_template(obj.template)
            self._template_bar.set_genre_enabled(obj.use_genre_batch)
            self._extra_edit.setText(obj.extra_instructions)

    def _on_history_applied(self, entry: object) -> None:
        if isinstance(entry, AiPromptHistory):
            self._topic_edit.setText(entry.topic)
            self._level_combo.setCurrentText(entry.level)
            self._units_spin.setValue(entry.unit_count)
            self._lessons_spin.setValue(entry.lessons_per_unit)

    # ------------------------------------------------------------------ attachments
    def _on_attach_files(self) -> None:
        paths, _ = QFileDialog.getOpenFileNames(
            self,
            "选择附件",
            "",
            "参考文件 (*.png *.jpg *.jpeg *.gif *.webp *.pdf *.docx *.txt *.md *.csv *.json);;所有文件 (*)",
        )
        if paths:
            self._add_attachment_paths([Path(p) for p in paths])

    def set_ocr_enabled(self, enabled: bool) -> None:
        self._ocr_enabled = bool(enabled)
        if hasattr(self, "_attachment_bar") and self._attachment_bar is not None:
            self._attachment_bar.set_ocr_enabled(self._ocr_enabled)

    def _add_attachment_paths(self, paths: list[Path]) -> None:
        """Copy to temp + extract text/image content, then add to the bar.

        Ported from the legacy dialog (ai_generator_dialog.py:1906-1931);
        temp files are owned by this panel and deleted after send / on close
        (the legacy dialog leaked sent attachments' temp files).
        """
        for path in paths:
            if not path.exists():
                continue
            temp_path = (
                Path(tempfile.gettempdir())
                / f"turna_design_{uuid.uuid4().hex[:8]}_{path.name}"
            )
            try:
                temp_path.write_bytes(path.read_bytes())
            except OSError:
                continue
            result = extract_attachment(temp_path)
            if not result.ok or result.content is None:
                err_msg = str(result.error or "")
                if getattr(self, "_ocr_enabled", False) and ("扫描件" in err_msg or "图片 PDF" in err_msg):
                    from src.backend.experience.ocr_skill import ocr_available

                    avail, _ = ocr_available()
                    if avail:
                        reply = QMessageBox.question(
                            self,
                            "OCR 识别",
                            f"{path.name} 可能是扫描件或图片 PDF，是否使用 OCR 识别文字？",
                            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
                        )
                        if reply == QMessageBox.StandardButton.Yes:
                            self.ocr_requested.emit(
                                temp_path.as_posix()
                                if hasattr(temp_path, "as_posix")
                                else str(temp_path).replace("\\", "/"),
                                path.name,
                                True,
                            )
                            continue
                try:
                    temp_path.unlink()
                except OSError:
                    logger.debug("dialogs/ai/design_panel.py:815 best-effort step failed", exc_info=True)
                QMessageBox.warning(
                    self, "附件无法读取", f"{path.name}：{result.error or '未知错误'}"
                )
                continue
            self._attachment_bar.add_attachment(
                AttachmentRecord(
                    temp_path=temp_path,
                    original_name=path.name,
                    content=result.content,
                )
            )

    @staticmethod
    def _delete_temp_files(records: list[AttachmentRecord]) -> None:
        for record in records:
            try:
                record.temp_path.unlink()
            except OSError:
                logger.debug("dialogs/ai/design_panel.py:834 best-effort step failed", exc_info=True)

    def cleanup_attachments(self) -> None:
        """Delete remaining temp files and clear the bar (interrupt/close)."""
        self._delete_temp_files(self._attachment_bar.attachments())
        self._attachment_bar.clear_attachments()

    def dragEnterEvent(self, event: Any) -> None:  # noqa: N802
        if event.mimeData().hasUrls():
            event.acceptProposedAction()

    def dropEvent(self, event: Any) -> None:  # noqa: N802
        paths = [
            Path(url.toLocalFile())
            for url in event.mimeData().urls()
            if url.isLocalFile()
        ]
        if paths:
            self._add_attachment_paths(paths)
            event.acceptProposedAction()

    # ------------------------------------------------------------------ actions
    def _sync_params(self) -> None:
        mode = self._gen_mode_combo.currentData()
        if mode is None:
            mode = "fast"
        self._controller.set_params(
            topic=self._topic_edit.text().strip(),
            level=self._level_combo.currentText(),
            unit_count=self._units_spin.value(),
            lessons_per_unit=self._lessons_spin.value(),
            template=self._template_combo.currentText(),
            use_genre_batch=self._template_bar.is_genre_enabled(),
            extra_instructions=self._extra_edit.text().strip(),
            design_brief=self._brief_edit.text().strip(),
            generation_mode=str(mode),
            pipeline_skip_fix=self._skip_fix_check.isChecked(),
            pipeline_skip_explain=self._skip_explain_check.isChecked(),
        )

    def _on_send_chat(self) -> None:
        text = self._chat_input.text().strip()
        if not text:
            return
        self._sync_params()
        attachments = self._attachment_bar.attachments()
        if self._controller.send_chat(text, attachments):
            self._chat_input.clear()
            # Sent attachments belong to the message now — clear the bar and
            # delete their temp files (legacy leaked them to the OS temp dir).
            self._attachment_bar.clear_attachments()
            self._delete_temp_files(attachments)

    def _on_generate(self) -> None:
        if self._controller.is_busy:
            self._controller.cancel()
            return
        self._sync_params()
        self._controller.generate()

    def _current_editor_json(self) -> dict | None:
        """The editor text is the single source of truth for the draft (B1)."""
        try:
            data = self._json_editor.to_json()
        except ValueError as exc:
            QMessageBox.warning(self, "JSON 错误", str(exc))
            return None
        if not isinstance(data, dict):
            QMessageBox.warning(self, "JSON 错误", "顶层必须是 JSON 对象。")
            return None
        self._controller.set_draft(data)
        return data

    def _current_editor_json_silent(self) -> dict | None:
        """Popup-free variant of ``_current_editor_json`` for the review page."""
        try:
            data = self._json_editor.to_json()
        except ValueError:
            return None
        if not isinstance(data, dict):
            return None
        self._controller.set_draft(data)
        return data

    def _on_validate(self) -> None:
        data = self._current_editor_json()
        if data is None:
            return
        if self.adapter is None:
            self._validate_label.setText("（未加载课程，跳过校验）")
            return
        problems = self.adapter.validate_section_json(data, check_existing_ids=False)
        errors = [p for p in problems if p.get("level") == "error"]
        warnings = [p for p in problems if p.get("level") == "warning"]
        if errors:
            self._validate_label.setText(
                f"✗ {len(errors)} 个错误：{errors[0].get('message', '')}"
            )
        elif warnings:
            self._validate_label.setText(f"⚠ {len(warnings)} 个警告，可导入")
        else:
            self._validate_label.setText("✓ 校验通过")

    def _on_restore_raw(self) -> None:
        if not self._last_raw_output:
            return
        self._json_editor.setPlainText(self._last_raw_output)
        self._validate_label.setText("已恢复 AI 原始输出")

    def _on_try_lesson(self) -> None:
        data = self._current_editor_json()
        if data is None:
            return
        # Lesson picker across all units (ported from the legacy dialog).
        choices: list[tuple[str, dict]] = []
        for unit in data.get("units", []) or []:
            for lesson in unit.get("lessons", []) or []:
                if lesson.get("id"):
                    label = f"{unit.get('name', unit.get('id', ''))} / {lesson.get('name', lesson.get('id', ''))}"
                    choices.append((label, lesson))
        if not choices:
            QMessageBox.information(self, "试做", "草稿里还没有课时。")
            return
        lesson = choices[0][1]
        if len(choices) > 1:
            # Resolve by row index, not label text: duplicate labels would
            # otherwise silently pick the wrong lesson. Suffix duplicates.
            counts: dict[str, int] = {}
            for lbl, _ in choices:
                counts[lbl] = counts.get(lbl, 0) + 1
            seen: dict[str, int] = {}
            labels: list[str] = []
            for lbl, _ in choices:
                seen[lbl] = seen.get(lbl, 0) + 1
                labels.append(f"{lbl}（{seen[lbl]}）" if counts[lbl] > 1 else lbl)
            label, ok = QInputDialog.getItem(
                self, "试做", "选择课时：", labels, 0, False
            )
            if not ok:
                return
            lesson = choices[labels.index(label)][1]
        from src.teacher.preview_window import LessonPreviewDialog

        vocab_override = {w["id"]: w for w in data.get("words", []) if w.get("id")}
        LessonPreviewDialog(
            self.adapter, lesson, self, vocab_override=vocab_override
        ).exec()

    def _on_import(self) -> None:
        data = self._current_editor_json()
        if data is None:
            return
        if self.adapter is not None:
            problems = self.adapter.validate_section_json(data, check_existing_ids=False)
            errors = [p for p in problems if p.get("level") == "error"]
            if errors:
                detail = "\n".join(p.get("message", "") for p in errors[:5])
                QMessageBox.warning(self, "校验失败", f"请先修正：\n{detail}")
                return
        # Ask where to import: new section, into an existing section (as new
        # units), or into an existing unit (as new lessons). The choice is
        # encoded into the strategy string so the existing sections_ready
        # signal chain carries it to MainWindow._on_textbook_sections.
        from src.dialogs.import_target_dialog import ImportTargetDialog

        target = ImportTargetDialog(self.adapter, parent=self).select()
        if target is None:
            return  # cancelled
        if target.mode == "into_section":
            self.sections_ready.emit([data], f"into_section:{target.section_id}")
        elif target.mode == "into_unit":
            self.sections_ready.emit([data], f"into_unit:{target.unit_id}")
        else:
            self.sections_ready.emit([data], "merge")
