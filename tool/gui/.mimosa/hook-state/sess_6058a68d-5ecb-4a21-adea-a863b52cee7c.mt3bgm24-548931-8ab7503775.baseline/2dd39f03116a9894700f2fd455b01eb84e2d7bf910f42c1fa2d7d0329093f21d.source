"""Slim node-scoped AI edit dialog (M5).

Replaces the edit_mode path of the monolithic ``AiGeneratorDialog`` for tree
right-click / Experience AI edit. Uses ``generate_edit`` /
``regenerate_lesson_in_section`` / ``regenerate_unit_in_section`` with the same
undo/merge contract as before (caller applies the returned section).
"""
from __future__ import annotations

from typing import Any, Callable

from PySide6.QtCore import Qt
from PySide6.QtWidgets import (
    QDialog,
    QDialogButtonBox,
    QHBoxLayout,
    QLabel,
    QMessageBox,
    QPlainTextEdit,
    QPushButton,
    QVBoxLayout,
    QWidget,
)

from src.backend.ai_generator import (
    AiApiConfig,
    AiCourseSpec,
    generate_edit,
    regenerate_lesson_in_section,
    regenerate_unit_in_section,
)
from src.backend.ai_presets_ui import EDIT_PRESET_LABELS, EDIT_PRESETS
from src.dialogs.ai.worker import AiRequestWorker
from src.infrastructure.telemetry import telemetry
from src.widgets.json_editor import JsonEditor


class NodeAiEditDialog(QDialog):
    """Edit one section / unit / lesson via AI; returns full section JSON."""

    def __init__(
        self,
        adapter: Any,
        edit_mode: dict[str, Any],
        parent: QWidget | None = None,
        *,
        ai_config: AiApiConfig | None = None,
        settings_fn: Callable[[], Any] | None = None,
    ) -> None:
        super().__init__(parent)
        self.adapter = adapter
        self._edit_mode = dict(edit_mode or {})
        self._config = ai_config or AiApiConfig()
        self._settings_fn = settings_fn
        self._result: dict[str, Any] | None = None
        self._worker: AiRequestWorker | None = None

        scope = str(self._edit_mode.get("scope") or "section")
        scope_id = str(self._edit_mode.get("scope_id") or "")
        self.setWindowTitle(f"AI 编辑 · {scope} {scope_id}".strip())
        self.resize(720, 560)
        self._build_ui(scope, scope_id)

    def _build_ui(self, scope: str, scope_id: str) -> None:
        lay = QVBoxLayout(self)
        lay.addWidget(
            QLabel(
                f"<b>范围</b>：{scope}"
                + (f" · <code>{scope_id}</code>" if scope_id else "")
                + "<br/>结果仅供参考，请审核后确认。将替换当前节草稿（经 Undo 可恢复）。"
            )
        )
        lay.addWidget(QLabel("编辑指令："))
        self.instruction = QPlainTextEdit()
        self.instruction.setPlaceholderText(
            "例如：降低难度；补充听力题；修正干扰项；保持 id 不变……"
        )
        self.instruction.setMinimumHeight(80)
        lay.addWidget(self.instruction)

        chips = QHBoxLayout()
        for i, full in enumerate(EDIT_PRESETS[:6]):
            short = (
                EDIT_PRESET_LABELS[i]
                if i < len(EDIT_PRESET_LABELS)
                else full[:12]
            )
            btn = QPushButton(short)
            btn.setFlat(True)
            btn.setToolTip(full)
            btn.clicked.connect(
                lambda _c=False, t=full: self.instruction.setPlainText(t)
            )
            chips.addWidget(btn)
        chips.addStretch(1)
        lay.addLayout(chips)

        self.status = QLabel("")
        lay.addWidget(self.status)

        self.editor = JsonEditor(self)
        lay.addWidget(self.editor, 1)

        row = QHBoxLayout()
        self.run_btn = QPushButton("生成修改")
        self.run_btn.clicked.connect(self._on_run)
        row.addWidget(self.run_btn)
        self.cancel_btn = QPushButton("取消请求")
        self.cancel_btn.setEnabled(False)
        self.cancel_btn.clicked.connect(self._on_cancel_worker)
        row.addWidget(self.cancel_btn)
        row.addStretch(1)
        lay.addLayout(row)

        buttons = QDialogButtonBox(
            QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel
        )
        buttons.accepted.connect(self._on_accept)
        buttons.rejected.connect(self.reject)
        self._ok = buttons.button(QDialogButtonBox.StandardButton.Ok)
        self._ok.setEnabled(False)
        lay.addWidget(buttons)

    def section_json(self) -> dict[str, Any]:
        if self._result is None:
            raise ValueError("尚未生成可应用的结果。")
        return self._result

    def _settings_kwargs(self) -> dict[str, Any]:
        try:
            s = self._settings_fn() if callable(self._settings_fn) else None
            if s is None:
                return {"timeout": 120.0, "temperature": 0.4}
            return {
                "timeout": float(getattr(s, "ai_timeout", 120.0)),
                "temperature": float(getattr(s, "ai_temperature", 0.4)),
            }
        except Exception:
            return {"timeout": 120.0, "temperature": 0.4}

    def _on_run(self) -> None:
        if not getattr(self._config, "is_complete", False):
            QMessageBox.warning(
                self,
                "配置不完整",
                "请先在设置中填写 Base URL / API Key / Model。",
            )
            return
        existing = self._edit_mode.get("existing_section")
        if not isinstance(existing, dict):
            QMessageBox.warning(self, "无法编辑", "缺少 existing_section。")
            return
        scope = str(self._edit_mode.get("scope") or "section")
        scope_id = str(self._edit_mode.get("scope_id") or "")
        instruction = self.instruction.toPlainText().strip() or None
        lang = ""
        try:
            lang = str((self.adapter.index or {}).get("language") or "")
        except Exception:
            lang = ""
        spec = AiCourseSpec(
            language=lang or "Turkish",
            source_language="Chinese",
            topic=str(existing.get("name") or existing.get("id") or "edit"),
            level=str(existing.get("level") or "A1"),
            extra_instructions=instruction or "",
        )
        kwargs = self._settings_kwargs()
        if scope == "lesson" and scope_id:
            target = regenerate_lesson_in_section
            args = (self._config, spec, existing, scope_id)
            wkwargs = {"instruction": instruction, **kwargs}
        elif scope == "unit" and scope_id:
            target = regenerate_unit_in_section
            args = (self._config, spec, existing, scope_id)
            wkwargs = {"instruction": instruction, **kwargs}
        else:
            if instruction:
                spec.extra_instructions = (
                    (spec.extra_instructions or "") + f"\n\n编辑指令：\n{instruction}"
                )
            target = generate_edit
            args = (self._config, spec, existing, scope, scope_id)
            wkwargs = dict(kwargs)

        telemetry.record_event(
            "ai.edit.start",
            payload={"scope": scope, "scope_id": scope_id},
        )
        self.run_btn.setEnabled(False)
        self.cancel_btn.setEnabled(True)
        self.status.setText("生成中…")
        self._worker = AiRequestWorker(target, *args, parent=self, **wkwargs)
        self._worker.result_ready.connect(self._on_result)
        self._worker.error_occurred.connect(self._on_error)
        self._worker.completed.connect(self._on_done)
        self._worker.start()

    def _on_cancel_worker(self) -> None:
        if self._worker is not None:
            self._worker.cancel()
            self.status.setText("正在取消…")

    def _on_result(self, result: object) -> None:
        if not isinstance(result, dict):
            self.status.setText("结果无效。")
            return
        self._result = result
        try:
            self.editor.set_json(result)
        except Exception:
            pass
        self._ok.setEnabled(True)
        self.status.setText("已生成，请审核后点「确定」应用。")
        telemetry.record_event("ai.edit.ready", payload={"ok": True})

    def _on_error(self, message: str) -> None:
        self.status.setText(f"失败：{message}")
        QMessageBox.warning(self, "AI 编辑失败", message)
        telemetry.record_event("ai.edit.error", payload={"message": str(message)[:200]})

    def _on_done(self) -> None:
        self.run_btn.setEnabled(True)
        self.cancel_btn.setEnabled(False)
        self._worker = None

    def _on_accept(self) -> None:
        if self._result is None:
            QMessageBox.information(self, "AI 编辑", "请先生成修改结果。")
            return
        # Prefer editor content if user tweaked JSON.
        try:
            edited = self.editor.to_json()
            if isinstance(edited, dict):
                self._result = edited
        except Exception:
            pass
        self.accept()
