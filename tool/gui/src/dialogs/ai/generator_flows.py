"""Generation / validation / import flows for SectionAiDialog.

Extracted from ``ai_generator_dialog.py``; every function takes the dialog
(``dlg``) as context. The dialog keeps same-name delegating methods, so the
public API (and the ``mock.patch`` surfaces used by tests) are unchanged.
``AiRequestWorker`` is imported lazily inside the flows that construct it —
mirroring the experience handlers — so tests can patch
``src.application.ai_request_worker.AiRequestWorker``.
"""
from __future__ import annotations

import json
import logging
import time
from typing import Any

from PySide6.QtWidgets import QDialogButtonBox, QInputDialog, QMessageBox

from src.backend.ai import (
    AiCourseSpec,
    ChatMessage,
    detect_genre_from_spec,
    explain_course,
    generate_edit,
    generate_from_chat,
    request_alignment_reply,
    request_course_with_retry,
    structural_diff,
)
from src.backend.ai_genre import genre_to_template
from src.application.ai_prompt_library import AiPromptHistory, AiPromptTemplate
from src.dialogs.ai.generator_chat_coordinator import escape_html as _escape_html
from src.dialogs.ai.generator_preview_coordinator import (
    confirm_structural_removal as _confirm_removal_ui,
    jump_editor_to_path,
    try_preview_lesson,
    view_section_diff,
)
from src.dialogs.ai.generator_worker_hub import record_cache_stats
from src.infrastructure.telemetry import telemetry

logger = logging.getLogger(__name__)

# Backward-compat alias (was an alias in the dialog module).
_record_cache_stats = record_cache_stats


def apply_prompt_fields(dlg, obj) -> None:
    dlg.topic_edit.setText(obj.topic)
    dlg.level_combo.setCurrentText(obj.level)
    dlg.unit_spin.setValue(obj.unit_count)
    dlg.lessons_spin.setValue(obj.lessons_per_unit)
    dlg._template_bar.select_template(obj.template)
    dlg._template_bar.set_genre_enabled(obj.use_genre_batch)
    dlg.extra_edit.setText(obj.extra_instructions)


def on_template_applied(dlg, obj: object) -> None:
    if isinstance(obj, dict) and obj.get("action") == "save_request":
        name = obj.get("name", "")
        if name:
            dlg._template_bar.save_current_template(dlg._current_spec())
        return
    if isinstance(obj, AiPromptTemplate):
        dlg._apply_prompt_fields(obj)


def on_history_applied(dlg, entry: object) -> None:
    if isinstance(entry, AiPromptHistory):
        dlg._apply_prompt_fields(entry)


def make_edit_worker(dlg, spec: AiCourseSpec, **kwargs: Any) -> AiRequestWorker:
    instruction = None
    if hasattr(dlg, "edit_instruction_input"):
        instruction = dlg.edit_instruction_input.toPlainText().strip() or None
    return dlg._worker_hub.make_edit_worker(
        dlg._config, spec, dlg._edit_mode, instruction=instruction, **kwargs
    )


def on_generate_normal(dlg) -> None:
    from src.application.ai_request_worker import AiRequestWorker

    topic = dlg.topic_edit.text().strip()
    if not topic:
        QMessageBox.warning(dlg, "缺少主题", "请先填写课程主题。")
        return
    if not dlg._ensure_api_configured():
        return
    if dlg._current_worker is not None and dlg._current_worker.isRunning():
        return

    dlg._request_start = time.perf_counter()
    telemetry.record_event("ai.generate.start", payload={"mode": "normal", "edit_mode": dlg._edit_mode is not None})
    spec = dlg._current_spec()
    if dlg._edit_mode is None:
        spec.course_resources = dlg._course_resource_summary()
    dlg._template_bar.record_history(spec)
    kwargs = dlg._ai_generation_kwargs()
    if dlg._edit_mode is not None:
        worker = dlg._make_edit_worker(spec, **kwargs)
    else:
        validator = dlg.adapter.validate_section_json
        worker = AiRequestWorker(
            request_course_with_retry,
            dlg._config,
            spec,
            validator,
            max_retries=dlg._ai_retry_max(),
            **kwargs,
        )
    worker.result_ready.connect(dlg._on_normal_generation_ready)
    worker.error_occurred.connect(dlg._on_worker_error)
    worker.chunk_ready.connect(dlg._on_worker_chunk)
    worker.usage_ready.connect(dlg._on_worker_usage)
    worker.completed.connect(dlg._on_normal_worker_done)
    dlg._begin_stream("json")
    dlg._register_worker(worker)
    dlg._set_busy(True, normal=True, stage="生成中（流式）…")
    worker.start()


def on_normal_generation_ready(dlg, parsed: object) -> None:
    if dlg._closing:
        return
    duration_ms = dlg._duration_since_request_start()
    telemetry.record_duration(
        "ai.generate",
        duration_ms,
        payload={"mode": "normal", "success": True, "edit_mode": dlg._edit_mode is not None},
    )
    _record_cache_stats()
    if (
        dlg._edit_mode is not None
        and isinstance(parsed, dict)
        and isinstance(dlg._edit_mode.get("existing_section"), dict)
    ):
        diff = structural_diff(dlg._edit_mode["existing_section"], parsed)
        removed_only = {
            k: v
            for k, v in diff.items()
            if k.startswith("removed_") and v
        }
        if removed_only and not dlg._confirm_structural_removal(diff):
            dlg._set_busy(False, normal=True, stage="")
            dlg._finish_stream()
            dlg._request_start = None
            return
    dlg._generated = parsed
    dlg.json_edit.set_json(parsed)
    dlg.reset_btn.setEnabled(True)
    if isinstance(parsed, dict):
        dlg.result_preview.show_section(parsed)
        dlg.result_preview.setVisible(True)
    dlg.try_btn.setVisible(isinstance(parsed, dict))
    dlg.diff_btn.setVisible(
        isinstance(parsed, dict)
        and dlg._edit_mode is not None
        and isinstance(dlg._edit_mode.get("existing_section"), dict)
    )
    dlg._update_mode_ui()


def confirm_structural_removal(dlg, diff: dict[str, set[str]]) -> bool:
    return confirm_structural_removal(dlg, diff)


def on_normal_worker_done(dlg) -> None:
    if dlg._closing:
        return
    dlg._set_busy(False, normal=True, stage="")
    dlg._finish_stream()
    dlg._request_start = None


def on_preview_validity(dlg, ok: bool) -> None:
    if dlg._generated is not None:
        dlg._button_box.button(QDialogButtonBox.StandardButton.Ok).setEnabled(ok)


def on_reset(dlg) -> None:
    if dlg._generated is not None:
        dlg._active_json_editor().set_json(dlg._generated)


def on_view_diff(dlg) -> None:
    if dlg._edit_mode is None or not isinstance(dlg._edit_mode.get("existing_section"), dict):
        return
    try:
        generated = dlg._current_json()
    except ValueError:
        return
    view_section_diff(dlg, dlg._edit_mode["existing_section"], generated)


def on_try_preview(dlg) -> None:
    try:
        section = dlg._current_json()
    except ValueError as exc:
        QMessageBox.warning(dlg, "无法试做", str(exc))
        return
    try_preview_lesson(dlg, dlg.adapter, section)


def on_validate_json(dlg) -> None:
    try:
        data = dlg._current_json()
    except ValueError as exc:
        QMessageBox.warning(dlg, "JSON 无效", str(exc))
        return
    QMessageBox.information(
        dlg,
        "JSON 有效",
        f"JSON 解析成功：{len(data.get('units', []))} 个单元。",
    )


def on_validate_from_editor(dlg) -> None:
    try:
        data = dlg._current_json()
    except ValueError as exc:
        QMessageBox.warning(dlg, "JSON 无效", str(exc))
        return
    preview = dlg.wish_result_preview if dlg._mode == "wish" else dlg.result_preview
    preview.show_section(data)
    preview._on_validate()


def current_json(dlg) -> dict:
    editor = dlg.wish_json_edit if dlg._mode == "wish" else dlg.json_edit
    raw = editor.toPlainText().strip()
    if not raw:
        raise ValueError("尚未生成课程。" if dlg._mode == "wish" else "JSON 为空。")
    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        editor.mark_error(getattr(exc, "lineno", 1) or 1, str(exc))
        raise ValueError(f"JSON 解析失败: {exc}") from exc
    if not isinstance(data, dict) or "units" not in data:
        raise ValueError("JSON 必须是包含 'units' 数组的对象。")
    return data


def on_preview_node_activated(dlg, path: str) -> None:
    jump_editor_to_path(dlg._active_json_editor(), path)


def on_send_message(dlg) -> None:
    from src.application.ai_request_worker import AiRequestWorker

    text = dlg.input_edit.toPlainText().strip()
    if not text and not dlg._attachments:
        return
    if not dlg._ensure_api_configured():
        return
    if dlg._current_worker is not None and dlg._current_worker.isRunning():
        return

    dlg._request_start = time.perf_counter()
    telemetry.record_event("ai.alignment.send", payload={"attachment_count": len(dlg._attachments)})
    if dlg.genre_switch.isChecked():
        tags = detect_genre_from_spec(
            AiCourseSpec(topic=text, extra_instructions="", use_genre_batch=True)
        )
        if tags:
            dlg._set_template_combo(genre_to_template(tags[0]))

    user_content: list[dict[str, Any]] = [{"type": "text", "text": text}]
    for att in dlg._attachments:
        user_content.append(att.content)
    dlg._messages.append(ChatMessage(role="user", content=user_content))
    dlg.input_edit.clear()
    dlg._attachment_bar.clear_attachments()
    dlg._render_chat()

    kwargs = dlg._ai_generation_kwargs()
    worker = AiRequestWorker(
        request_alignment_reply,
        dlg._config,
        dlg._current_spec(),
        dlg._messages,
        **kwargs,
    )
    worker.result_ready.connect(dlg._on_alignment_reply_ready)
    worker.error_occurred.connect(dlg._on_worker_error)
    worker.chunk_ready.connect(dlg._on_worker_chunk)
    worker.usage_ready.connect(dlg._on_worker_usage)
    worker.completed.connect(dlg._on_alignment_worker_done)
    dlg._begin_stream("alignment")
    dlg._register_worker(worker)
    dlg._set_busy(True, stage="对齐中…")
    worker.start()


def on_alignment_worker_done(dlg) -> None:
    if dlg._closing:
        return
    dlg._set_busy(False, stage="")
    dlg._finish_stream()
    dlg._request_start = None


def on_alignment_reply_ready(dlg, reply: object) -> None:
    if dlg._closing:
        return
    duration_ms = dlg._duration_since_request_start()
    telemetry.record_duration(
        "ai.alignment",
        duration_ms,
        payload={"success": True},
    )
    dlg._messages.append(ChatMessage(role="assistant", content=str(reply)))
    dlg._render_chat()


def on_wish_generate(dlg) -> None:
    from src.application.ai_request_worker import AiRequestWorker

    if not dlg._ensure_api_configured():
        return
    if not dlg._messages:
        QMessageBox.warning(
            dlg, "对话为空", "请先和 AI 聊几句，告诉它你想做什么课程。"
        )
        return
    if dlg._current_worker is not None and dlg._current_worker.isRunning():
        return

    dlg._request_start = time.perf_counter()
    telemetry.record_event("ai.generate.start", payload={"mode": "wish", "edit_mode": dlg._edit_mode is not None})
    spec = dlg._current_spec()
    dlg._template_bar.record_history(spec)
    kwargs = dlg._ai_generation_kwargs()
    if dlg._edit_mode is not None:
        worker = AiRequestWorker(
            generate_edit,
            dlg._config,
            spec,
            dlg._edit_mode["existing_section"],
            dlg._edit_mode.get("scope", "section"),
            dlg._edit_mode.get("scope_id", ""),
            dlg._messages,
            dlg._draft_json,
            **kwargs,
        )
    else:
        worker = AiRequestWorker(
            generate_from_chat,
            dlg._config,
            spec,
            dlg._messages,
            draft_json=dlg._draft_json,
            **kwargs,
        )
    worker.result_ready.connect(dlg._on_wish_generation_ready)
    worker.error_occurred.connect(dlg._on_worker_error)
    worker.chunk_ready.connect(dlg._on_worker_chunk)
    worker.usage_ready.connect(dlg._on_worker_usage)
    worker.completed.connect(dlg._on_wish_generation_completed)
    dlg._begin_stream("json")
    dlg._register_worker(worker)
    dlg._set_busy(True, stage="生成中（流式）…")
    worker.start()


def on_wish_generation_completed(dlg) -> None:
    """No-op completion hook for wish worker; explain worker follows on ready."""
    pass


def on_wish_generation_ready(dlg, parsed: object) -> None:
    from src.application.ai_request_worker import AiRequestWorker

    if dlg._closing:
        return
    duration_ms = dlg._duration_since_request_start()
    telemetry.record_duration(
        "ai.generate",
        duration_ms,
        payload={"mode": "wish", "success": isinstance(parsed, dict), "edit_mode": dlg._edit_mode is not None},
    )
    _record_cache_stats()
    dlg._generated = parsed
    dlg._draft_json = parsed

    if not isinstance(parsed, dict):
        dlg._set_busy(False)
        QMessageBox.critical(dlg, "生成失败", "模型返回了非预期的数据类型。")
        return

    dlg.wish_result_preview.show_section(parsed)
    dlg.wish_result_preview.setVisible(dlg._result_toggle.isChecked())
    dlg.wish_json_edit.set_json(parsed)
    dlg.wish_json_edit.setVisible(True)
    dlg._result_frame.setVisible(True)
    dlg._result_summary.setText(dlg._result_summary_text(parsed))
    dlg._wish_json_window_btn.setVisible(True)
    dlg._result_toggle.setChecked(False)
    dlg._open_json_window()

    dlg._finish_stream()
    dlg._request_start = time.perf_counter()
    kwargs = dlg._ai_generation_kwargs()
    worker = AiRequestWorker(
        explain_course, dlg._config, dlg._current_spec(), parsed, **kwargs
    )
    worker.result_ready.connect(dlg._on_explain_ready)
    worker.error_occurred.connect(dlg._on_explain_error)
    worker.chunk_ready.connect(dlg._on_worker_chunk)
    worker.usage_ready.connect(dlg._on_worker_usage)
    worker.completed.connect(dlg._on_explain_worker_done)
    dlg._begin_stream("explain")
    dlg._register_worker(worker)
    dlg._set_busy(True, stage="通俗解释中…")
    worker.start()


def on_explain_worker_done(dlg) -> None:
    if dlg._closing:
        return
    dlg._set_busy(False, stage="")
    dlg._finish_stream()
    dlg._request_start = None


def on_explain_ready(dlg, explanation: object) -> None:
    if dlg._closing:
        return
    telemetry.record_event("ai.explain.done", payload={"mode": "wish"})
    text = str(explanation)
    safe = _escape_html(text)
    dlg.explain_label.setHtml(safe)
    dlg.explain_group.setProperty("_has_text", True)
    if not dlg._result_toggle.isChecked():
        dlg._result_toggle.setChecked(True)
    else:
        dlg.explain_group.setVisible(True)
    dlg._update_mode_ui()

    QMessageBox.information(
        dlg,
        "生成完成",
        "课程已生成。点击「导入到课程」将其加入左侧课程树，或继续对话修改。",
    )


def on_explain_error(dlg, message: str) -> None:
    if dlg._closing:
        return
    telemetry.record_event(
        "ai.explain.error",
        payload={"mode": "wish", "error": message},
    )
    dlg._set_busy(False)
    dlg._set_stage_label("")
    dlg.explain_group.setProperty("_has_text", False)
    dlg.explain_label.setHtml(
        f"<font color='#E74C3C'>解释生成失败：{message}</font>"
    )
    msg = QMessageBox(dlg)
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
        dlg._on_wish_generate()
    elif clicked == analyze_btn:
        dlg._offer_error_analysis(
            message, context={"action": "ai.explain", "mode": "wish"}
        )


def on_accept(dlg) -> None:
    try:
        data = dlg._current_json()
    except ValueError as exc:
        QMessageBox.warning(dlg, "无法导入", str(exc))
        return

    sid = data.get("id") or ""
    if not sid:
        QMessageBox.warning(dlg, "缺少 section id", "生成的 JSON 缺少顶层 id 字段。")
        return

    if dlg._edit_mode is not None:
        existing_id = dlg._edit_mode["existing_section"].get("id", "")
        if existing_id and sid != existing_id:
            data["id"] = existing_id
            sid = existing_id
    else:
        existing_ids = {s.get("id") for s in dlg.adapter.sections}
        existing_index_ids = {
            e.get("id") for e in dlg.adapter.index.get("sections", [])
        }
        while sid in existing_ids or sid in existing_index_ids:
            new_sid, ok = QInputDialog.getText(
                dlg,
                "ID 冲突",
                f"section id「{sid}」已存在，请修改：",
                text=sid,
            )
            if not ok or not new_sid:
                return
            sid = new_sid
        data["id"] = sid

    problems = dlg.adapter.validate_section_json(
        data, check_existing_ids=False
    )
    errors = [p for p in problems if p["level"] == "error"]
    warnings = [p for p in problems if p["level"] == "warning"]
    if errors:
        detail = "\n".join(f"[{p['level']}] {p['message']}" for p in errors)
        QMessageBox.warning(dlg, "校验失败，无法导入", detail)
        return
    if warnings:
        detail = "\n".join(f"[{p['level']}] {p['message']}" for p in warnings)
        QMessageBox.information(
            dlg, "导入警告", f"存在警告，但仍可导入：\n\n{detail}"
        )

    dlg._generated = data
    dlg.accept()
