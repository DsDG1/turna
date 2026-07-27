"""M-02 course.outline_shells handler (v4.63).

Zero-LLM deterministic outline → unit/lesson shells. The author pastes a
bullet outline; ``outline_skill`` parses it into an outline dict and builds a
shell section (via ``ai_phased.outline_to_section_shell``). The shells are
**appended** to the target section through ``plan_section_merge`` +
``SectionDiffView`` (human confirm) + ``MergeAiSectionCommand`` (Undo) —
existing content is never replaced. Default off via
``experience/outline_shell``; never raises (offscreen-safe statusBar paths).
"""
from __future__ import annotations

from typing import Any

from PySide6.QtWidgets import QDialog

from src.application.commands import MergeAiSectionCommand
from src.application.ui_guard import safe_information, safe_warning


def _resolve_target_section_id(host: Any, scope: dict) -> str:
    """Resolve the section to append shells into (scope > selection > first)."""
    sid = str((scope or {}).get("section_id") or "").strip()
    if sid:
        return sid
    ref = getattr(host, "_current_node_ref", None)
    if ref:
        kind, nid = str(ref[0]), str(ref[1])
        try:
            if kind == "section":
                return nid
            if kind == "unit":
                section, _u = host.adapter.find_unit(nid)
                return str(section.get("id") or "")
            if kind == "lesson":
                section, _u, _l = host.adapter.find_lesson(nid)
                return str(section.get("id") or "")
        except Exception:
            pass
    try:
        sections = getattr(host.adapter, "sections", None) or []
        if sections and isinstance(sections[0], dict):
            return str(sections[0].get("id") or "")
    except Exception:
        pass
    return ""


def handle_outline_shells(host: Any, scope: dict | None = None) -> None:
    """Paste bullet outline → append unit/lesson shells to a section (Undo)."""
    from src.backend.experience.outline_skill import (
        ACTION_ID,
        all_course_ids,
        is_outline_shell_enabled,
        outline_to_shell_section,
        parse_bullet_outline,
        shell_stats,
    )

    if not is_outline_shell_enabled(getattr(host, "_settings_obj", None)):
        host.statusBar().showMessage(
            "大纲生成课壳未开启（设置 ▸ 体验 OS 勾选「大纲生成课壳」）", 6000
        )
        return
    if not getattr(host, "course_dir", None):
        safe_warning(host, "大纲生成课壳", "请先打开课程目录。")
        return

    sid = _resolve_target_section_id(host, scope or {})
    if not sid:
        host.statusBar().showMessage("找不到目标 section", 4000)
        return
    try:
        target = host.adapter.find_section(sid)
    except KeyError as exc:
        safe_warning(host, "大纲生成课壳", str(exc))
        return

    # Paste outline (multi-line). headless / offscreen -> non-modal cancel.
    from src.application.ui_guard import is_headless_ui

    if is_headless_ui():
        host.statusBar().showMessage("大纲输入需要图形界面（当前 headless）", 4000)
        return
    from PySide6.QtWidgets import QInputDialog

    text, ok = QInputDialog.getMultiLineText(
        host,
        "大纲生成课壳",
        "粘贴大纲（缩进 / 连字符 / 数字序号分课；课后可跟 [listening]/[reading] 等课型）：\n"
        "示例：\n  问候\n    - 打招呼\n    - 自我介绍 [listening]",
        "",
    )
    if not ok or not str(text or "").strip():
        host.experience_metrics.inc_suggestion(ACTION_ID, "rejected")
        return

    outline = parse_bullet_outline(
        text, existing_ids=all_course_ids(host.adapter), section_id=sid
    )
    shell = outline_to_shell_section(outline, section_id=sid)
    stats = shell_stats(shell)
    if not stats["unit_count"]:
        safe_information(
            host, "大纲生成课壳", "未解析出任何单元/课。请检查大纲格式。"
        )
        host.experience_metrics.inc_suggestion(ACTION_ID, "rejected")
        return

    plan = host.adapter.plan_section_merge(sid, shell)
    if not plan.added_units and not any(plan.added_lessons_by_unit.values()):
        safe_information(
            host,
            "大纲生成课壳",
            "大纲中的单元/课均已存在，无新增内容。",
        )
        host.experience_metrics.inc_suggestion(ACTION_ID, "rejected")
        return

    # Preview the merge (SectionDiffView shows the incoming shell section).
    from src.widgets.diff_view import SectionDiffView

    dlg = SectionDiffView(
        target,
        shell,
        host,
        confirm=True,
        title=(
            f"大纲生成课壳预览 — 将追加 {stats['unit_count']} 单元 / "
            f"{stats['lesson_count']} 课到 {sid}（确认后应用，可 Undo）"
        ),
    )
    if dlg.exec() != QDialog.DialogCode.Accepted:
        host.experience_metrics.inc_suggestion(ACTION_ID, "rejected")
        return

    cmd = MergeAiSectionCommand(host.adapter, plan)
    if hasattr(cmd, "signals") and hasattr(host, "_on_ai_edit_applied"):
        try:
            cmd.signals.changed.connect(host._on_ai_edit_applied)
        except Exception:
            pass
    host.undo_stack.push(cmd)
    host.experience_metrics.inc_suggestion(ACTION_ID, "applied")
    host._record_experience_event(
        ACTION_ID,
        f"大纲生成课壳 {stats['unit_count']} 单元 / {stats['lesson_count']} 课",
        action_id=ACTION_ID,
        scope={
            "section_id": sid,
            "unit_count": stats["unit_count"],
            "lesson_count": stats["lesson_count"],
            "unit_ids": stats["unit_ids"],
            "lesson_ids": stats["lesson_ids"],
        },
    )
    host._refresh_validate_after_ai("大纲课壳已追加，记得保存")
