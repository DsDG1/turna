"""Mode-switching / busy / streaming view state for SectionAiDialog.

Extracted from ``ai_generator_dialog.py``; every function takes the dialog
(``dlg``) as context. The dialog keeps same-name delegating methods.
"""
from __future__ import annotations

import logging
from typing import Any

from PySide6.QtWidgets import QDialogButtonBox, QLabel, QMessageBox

from src.backend.ai import (
    AiCourseSpec,
    apply_genre_to_spec,
)
from src.backend.ai_genre import genre_tags_in_text, genre_to_template
from src.application.ai_request_worker import is_valid_http_url as _is_valid_http_url
from src.dialogs.ai.generator_chat_coordinator import escape_html as _escape_html

logger = logging.getLogger(__name__)


def apply_edit_mode_ui(dlg) -> None:
    if dlg._edit_mode is None:
        return
    scope = dlg._edit_mode.get("scope", "section")
    label = {
        "section": "应用编辑（Section）",
        "unit": "应用编辑（Unit）",
        "lesson": "应用编辑（Lesson）",
    }.get(scope, "应用编辑")
    dlg._button_box.button(QDialogButtonBox.StandardButton.Ok).setText(label)
    if hasattr(dlg, "normal_tabs") and hasattr(dlg, "_wizard_panel"):
        wizard_idx = dlg.normal_tabs.indexOf(dlg._wizard_panel)
        if wizard_idx >= 0:
            dlg.normal_tabs.setTabVisible(wizard_idx, False)


def on_mode_changed(dlg, index: int) -> None:
    dlg._mode = dlg.mode_combo.itemData(index) or "normal"
    dlg._update_mode_ui()


def update_mode_ui(dlg) -> None:
    is_normal = dlg._mode == "normal"
    dlg._normal_panel.setVisible(is_normal)
    dlg._wish_panel.setVisible(not is_normal)
    dlg._place_template_bar(is_normal)
    dlg._sync_json_window_on_mode_switch()
    dlg._button_box.button(QDialogButtonBox.StandardButton.Ok).setEnabled(
        dlg._generated is not None
    )
    dlg._button_box.button(QDialogButtonBox.StandardButton.Ok).setText("导入到课程")


def sync_json_window_on_mode_switch(dlg) -> None:
    win = dlg._preview_coord.json_window
    if win is None:
        return
    prev = win.release_editor()
    if prev is not None:
        if prev is dlg.wish_json_edit:
            dlg._wish_json_host.addWidget(prev)
        else:
            dlg._normal_json_host.addWidget(prev)
        prev.setVisible(True)
    active = dlg._active_json_editor()
    if active is not None:
        win.host_editor(active)
        active.setVisible(True)


def place_template_bar(dlg, is_normal: bool) -> None:
    bar = getattr(dlg, "_template_bar", None)
    if bar is None:
        return
    target = dlg._normal_template_slot if is_normal else dlg._wish_template_slot
    for slot in (dlg._normal_template_slot, dlg._wish_template_slot):
        if slot is target:
            continue
        for i in range(slot.count()):
            if slot.itemAt(i).widget() is bar:
                slot.takeAt(i)
                break
    if not dlg._bar_in_slot(target, bar):
        target.addWidget(bar)


def bar_in_slot(slot, bar) -> bool:
    for i in range(slot.count()):
        if slot.itemAt(i).widget() is bar:
            return True
    return False


def current_topic_text(dlg) -> str:
    if dlg._mode == "normal":
        return dlg.topic_edit.text()
    for msg in reversed(dlg._messages):
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


def update_input_placeholders(dlg) -> None:
    dlg._template_bar.update_placeholders(
        topic_edit=getattr(dlg, "topic_edit", None),
        input_edit=getattr(dlg, "input_edit", None),
    )


def on_topic_text_changed(dlg, text: str) -> None:
    if not dlg.genre_switch.isChecked():
        return
    dlg._sync_template_from_genre_tags()


def sync_template_from_genre_tags(dlg) -> None:
    if not dlg.genre_switch.isChecked():
        return
    combined = f"{dlg._current_topic_text()} {dlg.extra_edit.text()}"
    tags = genre_tags_in_text(combined)
    dlg._template_bar.set_template_by_tags(tags, genre_to_template)


def set_template_combo(dlg, template: str) -> None:
    dlg._template_bar.select_template(template)


def ensure_api_configured(dlg) -> bool:
    if dlg._config.is_complete and _is_valid_http_url(dlg._config.base_url):
        return True
    QMessageBox.warning(
        dlg,
        "API 未配置",
        "请先点击工具栏「设置」，在「AI 配置」中填写 Base URL、API Key 和 Model，"
        "然后再使用 AI 功能。",
    )
    return False


def update_api_status(dlg) -> None:
    ok_color = dlg._pal("success", "#27AE60")
    err_color = dlg._pal("error", "#E74C3C")
    if dlg._config.is_complete and _is_valid_http_url(dlg._config.base_url):
        dlg.api_status.setText(f"<font color='{ok_color}'>已配置: {dlg._config.model}</font>")
    elif dlg._config.base_url or dlg._config.api_key or dlg._config.model:
        dlg.api_status.setText(f"<font color='{err_color}'>配置不完整</font>")
    else:
        dlg.api_status.setText(f"<font color='{err_color}'>未配置</font>")


def reconnect(dlg, btn, slot) -> None:
    try:
        btn.clicked.disconnect()
    except RuntimeError:
        logger.debug("dialogs/ai_generator_dialog.py:reconnect best-effort step failed", exc_info=True)
    btn.clicked.connect(slot)


def set_busy(dlg, busy: bool, normal: bool = False, stage: str = "") -> None:
    if stage:
        dlg._set_stage_label(stage)
    if normal:
        dlg._busy_normal = busy
        if busy:
            dlg.generate_btn.setText("取消生成")
            dlg.generate_btn.setToolTip("中断当前生成请求")
            dlg._reconnect(dlg.generate_btn, dlg._cancel_current_worker)
            dlg.progress.setVisible(True)
        else:
            dlg.generate_btn.setText("生成课程")
            dlg.generate_btn.setToolTip("按主题和规格直接生成 JSON")
            dlg._reconnect(dlg.generate_btn, dlg._on_generate_normal)
            dlg.progress.setVisible(False)
        dlg.validate_btn.setEnabled(not busy)
        dlg.reset_btn.setEnabled(not busy and dlg._generated is not None)
    else:
        dlg._busy_wish = busy
        if busy:
            dlg.send_btn.setText("取消")
            dlg.send_btn.setToolTip("中断当前请求")
            dlg._reconnect(dlg.send_btn, dlg._cancel_current_worker)
            dlg.wish_btn.setEnabled(False)
            dlg.attach_btn.setEnabled(False)
            dlg.wish_progress.setVisible(True)
        else:
            dlg.send_btn.setText("发送")
            dlg.send_btn.setToolTip("Ctrl+Enter 快捷发送")
            dlg._reconnect(dlg.send_btn, dlg._on_send_message)
            dlg.wish_btn.setEnabled(True)
            dlg.attach_btn.setEnabled(True)
            dlg.wish_progress.setVisible(False)
        dlg.input_edit.setEnabled(not busy)
    win = dlg._chat_coord.chat_expand_window
    if win is not None and win.isVisible():
        win.set_busy(busy and not normal)



def set_stage_label(dlg, stage: str) -> None:
    if hasattr(dlg, "stage_label"):
        dlg.stage_label.setText(stage)
        dlg.stage_label.setVisible(bool(stage))
    if hasattr(dlg, "wish_stage_label"):
        dlg.wish_stage_label.setText(stage)
        dlg.wish_stage_label.setVisible(bool(stage))
    win = dlg._chat_coord.chat_expand_window
    if win is not None and win.isVisible():
        win.set_stage(stage)


def current_usage_label(dlg) -> QLabel:
    return dlg.wish_usage_label if dlg._mode == "wish" else dlg.usage_label


def on_chunk_rendered(dlg, text: str, final: bool) -> None:
    n = len(text)
    if dlg._mode == "wish":
        if dlg._stream_target == "explain":
            if not final and n > dlg._STREAM_TEXT_LIVE_LIMIT:
                dlg.explain_label.setPlainText(f"解释生成中… 已接收约 {n} 字符")
            else:
                dlg.explain_label.setHtml(_escape_html(text))
            dlg.explain_group.setProperty("_has_text", True)
            dlg.explain_group.setVisible(dlg._result_toggle.isChecked())
        elif dlg._stream_target == "alignment":
            dlg._render_streaming_chat(text)
    else:
        if not final and n > dlg._STREAM_TEXT_LIVE_LIMIT:
            dlg.stage_label.setText(f"生成中… 已接收约 {n} 字符")
            dlg.stage_label.setVisible(True)
        else:
            dlg.json_edit.setPlainText(text)


def on_usage_updated(dlg, line: str, usage_dict: dict) -> None:
    label = dlg._current_usage_label()
    label.setText(line)
    label.setVisible(bool(line) and line != "≈ 0 tokens")
    win = dlg._chat_coord.chat_expand_window
    if win is not None and win.isVisible():
        win.set_usage(line)


def current_spec(dlg) -> AiCourseSpec:
    spec = AiCourseSpec(
        language=dlg.language_edit.text().strip() or "Turkish",
        source_language=dlg.source_language_edit.text().strip() or "Chinese",
        topic=dlg._current_topic_text().strip(),
        level=dlg.level_combo.currentText(),
        unit_count=dlg.unit_spin.value(),
        lessons_per_unit=dlg.lessons_spin.value(),
        template=dlg._template_bar.selected_template(),
        use_genre_batch=dlg._template_bar.is_genre_enabled(),
        extra_instructions=dlg.extra_edit.text().strip(),
    )
    if spec.use_genre_batch:
        spec = apply_genre_to_spec(spec)
    return spec


def course_resource_summary(dlg) -> dict[str, list] | None:
    if dlg.adapter is None:
        return None
    summary = {
        "words": [
            w for w in (dlg.adapter.vocab or []) if isinstance(w, dict)
        ][:200],
        "expressions": [
            e for e in (dlg.adapter.expressions or []) if isinstance(e, dict)
        ][:100],
        "grammarPoints": [
            g for g in (dlg.adapter.grammar_points or []) if isinstance(g, dict)
        ][:50],
    }
    if not any(summary.values()):
        return None
    return summary


def ai_retry_max(dlg) -> int:
    try:
        s = dlg._runtime.settings()
        return max(0, min(5, getattr(s, "ai_retry_max", 1)))
    except Exception:
        return 1


def ai_generation_kwargs(dlg) -> dict[str, Any]:
    try:
        s = dlg._runtime.settings()
        timeout = float(getattr(s, "ai_timeout", 120.0))
        temperature = float(getattr(s, "ai_temperature", 0.7))
    except Exception:
        timeout = 120.0
        temperature = 0.7
    return {"timeout": timeout, "temperature": temperature}
