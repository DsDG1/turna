"""Embeddable grounded-design panel for the workshop (connectplan §4.2 / P3-3).

Left: resource-pool summary + orchestration params + wish chat. Right: the
generated draft (JSON editor as the single source of truth, B1) with
validate / preview / import actions. All state lives in ``DesignController``;
the panel only renders and forwards. Emits ``sections_ready`` so the host can
push drafts through the shared ``SectionImportService`` pipeline.
"""
from __future__ import annotations

from typing import Any

from PySide6.QtCore import Qt, Signal
from PySide6.QtWidgets import (
    QComboBox,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QMessageBox,
    QPushButton,
    QSpinBox,
    QSplitter,
    QVBoxLayout,
    QWidget,
)

from src.dialogs.ai.chat_view import ChatView
from src.dialogs.ai.design_controller import DesignController
from src.widgets.json_editor import JsonEditor

_TEMPLATES = ("mixed", "intro", "practice", "review", "listening", "reading", "mastery")
_LEVELS = ("A1", "A2", "B1", "B2", "C1")


class DesignPanel(QWidget):
    """Grounded course-design widget (params + chat → draft → import)."""

    #: (list[dict], strategy) — one draft section ready for import.
    sections_ready = Signal(list, str)

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

        if controller is None:
            from src.app import current_ai_config

            controller = DesignController(
                ai_config_fn=current_ai_config,
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

    # ------------------------------------------------------------------ UI
    def _build_ui(self) -> None:
        layout = QVBoxLayout(self)
        layout.setContentsMargins(8, 8, 8, 8)
        layout.setSpacing(6)

        self._pool_label = QLabel("")
        self._pool_label.setStyleSheet("font-weight: 600;")
        layout.addWidget(self._pool_label)

        splitter = QSplitter(Qt.Orientation.Horizontal)

        # Left: params + chat.
        left = QWidget()
        left_lay = QVBoxLayout(left)
        left_lay.setContentsMargins(0, 0, 0, 0)

        row1 = QHBoxLayout()
        row1.addWidget(QLabel("主题:"))
        self._topic_edit = QLineEdit()
        self._topic_edit.setPlaceholderText("如：日常问候与自我介绍")
        row1.addWidget(self._topic_edit, 1)
        left_lay.addLayout(row1)

        row2 = QHBoxLayout()
        row2.addWidget(QLabel("级别:"))
        self._level_combo = QComboBox()
        self._level_combo.addItems(_LEVELS)
        row2.addWidget(self._level_combo)
        row2.addWidget(QLabel("单元:"))
        self._units_spin = QSpinBox()
        self._units_spin.setRange(1, 5)
        row2.addWidget(self._units_spin)
        row2.addWidget(QLabel("课时/单元:"))
        self._lessons_spin = QSpinBox()
        self._lessons_spin.setRange(1, 5)
        self._lessons_spin.setValue(3)
        row2.addWidget(self._lessons_spin)
        row2.addWidget(QLabel("模板:"))
        self._template_combo = QComboBox()
        self._template_combo.addItems(_TEMPLATES)
        row2.addWidget(self._template_combo)
        row2.addStretch(1)
        left_lay.addLayout(row2)

        row3 = QHBoxLayout()
        row3.addWidget(QLabel("编排意图:"))
        self._brief_edit = QLineEdit()
        self._brief_edit.setPlaceholderText("可选，如：前两章做 intro，语法点单独一个 review 单元")
        row3.addWidget(self._brief_edit, 1)
        left_lay.addLayout(row3)

        self._chat_view = ChatView()
        left_lay.addWidget(self._chat_view, 1)

        chat_row = QHBoxLayout()
        self._chat_input = QLineEdit()
        self._chat_input.setPlaceholderText("与 AI 讨论课程设计…（回车发送）")
        self._chat_input.returnPressed.connect(self._on_send_chat)
        chat_row.addWidget(self._chat_input, 1)
        self._send_btn = QPushButton("发送")
        self._send_btn.clicked.connect(self._on_send_chat)
        chat_row.addWidget(self._send_btn)
        left_lay.addLayout(chat_row)

        gen_row = QHBoxLayout()
        self._generate_btn = QPushButton("生成课程 ▶")
        self._generate_btn.clicked.connect(self._on_generate)
        gen_row.addWidget(self._generate_btn)
        self._stage_label = QLabel("")
        gen_row.addWidget(self._stage_label)
        gen_row.addStretch(1)
        self._usage_label = QLabel("")
        gen_row.addWidget(self._usage_label)
        left_lay.addLayout(gen_row)

        splitter.addWidget(left)

        # Right: draft JSON + actions.
        right = QWidget()
        right_lay = QVBoxLayout(right)
        right_lay.setContentsMargins(0, 0, 0, 0)
        right_lay.addWidget(QLabel("草稿 JSON（可手动修改，导入以编辑器内容为准）："))
        self._json_editor = JsonEditor()
        right_lay.addWidget(self._json_editor, 1)

        action_row = QHBoxLayout()
        self._validate_btn = QPushButton("校验")
        self._validate_btn.clicked.connect(self._on_validate)
        action_row.addWidget(self._validate_btn)
        self._try_btn = QPushButton("试做")
        self._try_btn.clicked.connect(self._on_try_lesson)
        action_row.addWidget(self._try_btn)
        action_row.addStretch(1)
        self._import_btn = QPushButton("导入到课程 ↗")
        self._import_btn.clicked.connect(self._on_import)
        action_row.addWidget(self._import_btn)
        right_lay.addLayout(action_row)
        self._validate_label = QLabel("")
        right_lay.addWidget(self._validate_label)

        splitter.addWidget(right)
        splitter.setStretchFactor(0, 1)
        splitter.setStretchFactor(1, 1)
        layout.addWidget(splitter, 1)

        for btn in (self._validate_btn, self._try_btn, self._import_btn):
            btn.setEnabled(False)

    # ------------------------------------------------------------------ project binding
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

    def set_project(self, project: Any, store: Any) -> None:
        """Bind to a textbook project: pool grounding + design persistence."""
        self._project = project
        self._store = store
        self._pool_fp: tuple | None = None
        self._controller.set_languages(project.language, project.source_language)
        self.refresh_pool_from_project()
        self._controller.apply_design_dict(project.design)
        # Restore params into widgets.
        params = self._controller.params
        self._topic_edit.setText(params.get("topic", ""))
        self._brief_edit.setText(params.get("design_brief", ""))
        self._units_spin.setValue(int(params.get("unit_count", 1)))
        self._lessons_spin.setValue(int(params.get("lessons_per_unit", 3)))
        self._level_combo.setCurrentText(params.get("level", "A1"))
        self._template_combo.setCurrentText(params.get("template", "mixed"))
        self._refresh_chat()

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
        if self._project is None or self._store is None:
            return
        try:
            self._project.design = self._controller.to_design_dict()
            self._store.save_project(self._project)
        except Exception:
            pass  # autosave must never break the flow

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
        self._chat_view.render(self._controller.chat)

    def _on_chat_chunk(self, text: str) -> None:
        self._chat_stream_buffer += text
        self._chat_view.render_streaming(
            self._controller.chat, self._chat_stream_buffer
        )

    def _on_draft_ready(self, section: dict) -> None:
        self._stream_buffer = ""
        self._json_editor.set_json(section)
        self._validate_label.setText(
            f"✓ 已生成 · {len(section.get('units', []))} 单元 · "
            f"{len(section.get('words', []))} 词"
        )
        for btn in (self._validate_btn, self._try_btn, self._import_btn):
            btn.setEnabled(True)

    def _on_draft_chunk(self, text: str) -> None:
        self._stream_buffer += text
        self._json_editor.setPlainText(self._stream_buffer)

    def _on_error(self, message: str) -> None:
        QMessageBox.warning(self, "AI 设计", message)

    def _on_busy_changed(self, busy: bool, stage: str) -> None:
        self._generate_btn.setText("取消生成" if busy else "生成课程 ▶")
        self._stage_label.setText(stage)
        self._send_btn.setEnabled(not busy)
        if busy:
            self._stream_buffer = ""
            self._chat_stream_buffer = ""

    def _on_usage_update(self, usage: dict) -> None:
        from src.backend.ai_usage import format_usage_line
        from src.app import current_ai_config

        model = getattr(current_ai_config(), "model", "")
        self._usage_label.setText(format_usage_line(usage, model))

    # ------------------------------------------------------------------ actions
    def _sync_params(self) -> None:
        self._controller.set_params(
            topic=self._topic_edit.text().strip(),
            level=self._level_combo.currentText(),
            unit_count=self._units_spin.value(),
            lessons_per_unit=self._lessons_spin.value(),
            template=self._template_combo.currentText(),
            design_brief=self._brief_edit.text().strip(),
        )

    def _on_send_chat(self) -> None:
        text = self._chat_input.text().strip()
        if not text:
            return
        self._sync_params()
        if self._controller.send_chat(text):
            self._chat_input.clear()

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

    def _on_try_lesson(self) -> None:
        data = self._current_editor_json()
        if data is None:
            return
        units = data.get("units") or []
        lessons = units[0].get("lessons") if units else []
        if not lessons:
            QMessageBox.information(self, "试做", "草稿里还没有课时。")
            return
        from src.teacher.preview_window import LessonPreviewDialog

        LessonPreviewDialog(self.adapter, lessons[0], self).exec()

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
        self.sections_ready.emit([data], "merge")
