"""Workshop / textbook-import host orchestration (S-10 / v4.46).

Duck-types MainWindow. Keeps open / OCR / import / draft-append paths out of
``app.py`` while preserving Command + undo behaviour.
"""
from __future__ import annotations

from typing import Any
import logging
from src.application.experience_host import ExperienceHost
logger = logging.getLogger(__name__)


def open_workshop(host: ExperienceHost) -> None:
    """Open or raise the workshop window (beta warning + signal wiring)."""
    from src.dialogs.workshop_window import WorkshopWindow
    from src.infrastructure.telemetry import telemetry

    telemetry.record_event("workshop.open")
    show_beta_warning_once(
        host,
        "workshop_beta_warning_shown",
        "课程工坊",
        "课程工坊：从教材到课程一站式创作，AI 生成结果请自行审核。\n\n"
        "知识点提取与 AI 生成都可能消耗大量 token，建议模型支持 1M 上下文窗口。\n\n"
        "点击「确定」继续。",
    )

    if getattr(host, "_workshop_window", None) is None:
        host._workshop_window = WorkshopWindow(host.adapter, host)
        host._workshop_window.sections_ready.connect(host._on_textbook_sections)
        host._workshop_window.locate_requested.connect(host._on_workshop_locate)
        # Older WorkshopWindow revisions lack the attachment/OCR signals.
        if hasattr(host._workshop_window, "attachments_changed"):
            host._workshop_window.attachments_changed.connect(
                host._on_workshop_attachments_changed
            )
        if hasattr(host._workshop_window, "ocr_requested"):
            host._workshop_window.ocr_requested.connect(
                host._on_workshop_ocr_requested
            )
        host._workshop_window.restore_last_session()
    sync_workshop_ocr_enabled(host)
    host._workshop_window.show()
    host._workshop_window.raise_()
    host._workshop_window.activateWindow()
    try:
        host._refresh_experience(immediate=False, focus_only=True)
    except Exception:
        logger.debug("application/workshop_controller.py:open_workshop best-effort step failed", exc_info=True)


def show_beta_warning_once(host: ExperienceHost, key: str, title: str, message: str) -> None:
    """One-shot beta warning; headless skips modal but marks shown."""
    from src.application.ui_guard import safe_information

    settings = getattr(host, "_settings", None)
    if settings is None:
        return
    if not settings.value(key, False):
        safe_information(host, title, message)
        settings.setValue(key, True)


def on_workshop_attachments_changed(host: ExperienceHost) -> None:
    try:
        host._sync_experience_attachments()
        host.experience.invalidate()
    except Exception:
        logger.debug("application/workshop_controller.py:on_workshop_attachments_changed best-effort step failed", exc_info=True)


def sync_workshop_ocr_enabled(host: ExperienceHost) -> None:
    try:
        from src.backend.experience.ocr_skill import is_ocr_enabled

        enabled = is_ocr_enabled(getattr(host, "_settings_obj", None))
        win = getattr(host, "_workshop_window", None)
        if win is not None and hasattr(win, "set_ocr_enabled"):
            win.set_ocr_enabled(enabled)
        exp = getattr(host, "experience", None)
        if exp is not None and hasattr(exp, "set_ocr_enabled"):
            exp.set_ocr_enabled(enabled)
    except Exception:
        logger.debug("application/workshop_controller.py:sync_workshop_ocr_enabled best-effort step failed", exc_info=True)


def on_workshop_ocr_requested(
    host: ExperienceHost, temp_path: str, original_name: str, unlink_after: bool
) -> None:
    try:
        from pathlib import Path

        from src.application.ai_request_worker import AttachmentRecord

        rec = AttachmentRecord(
            temp_path=Path(temp_path),
            original_name=original_name,
            content={"type": "text", "text": ""},
        )
        host._experience_ocr(records=[rec], unlink_after=unlink_after)
    except Exception:
        try:
            host.statusBar().showMessage("OCR 触发失败", 5000)
        except Exception:
            logger.debug("application/workshop_controller.py:on_workshop_ocr_requested best-effort step failed", exc_info=True)


def on_workshop_locate(host: ExperienceHost, section_id: str) -> None:
    host.showNormal()
    host.raise_()
    host.activateWindow()
    host.tree.select_section(section_id)


def on_textbook_sections(host: ExperienceHost, sections: list, strategy: str) -> None:
    from src.application.ui_guard import safe_information, safe_warning

    if not host.course_dir:
        safe_warning(host, "未加载课程目录", "请先打开课程目录。")
        return
    if strategy.startswith("into_section:"):
        import_draft_into_section(host, sections[0], strategy.split(":", 1)[1])
        return
    if strategy.startswith("into_unit:"):
        import_draft_into_unit(host, sections[0], strategy.split(":", 1)[1])
        return
    results, counts = host._import_service.import_bulk(sections, strategy=strategy)
    successful = [
        (
            (r.details or {}).get("source_id", ""),
            (r.details or {}).get("section_id", ""),
        )
        for r in results
        if (r.details or {}).get("outcome") in ("imported", "merged", "replaced")
    ]
    summary = (
        f"导入完成：新增 {counts['imported']} 个，"
        f"合并 {counts['merged']} 个，"
        f"覆盖 {counts['replaced']} 个，"
        f"跳过 {counts['skipped']} 个，"
        f"失败 {counts['blocked']} 个。"
    )
    project = (
        host._workshop_window.current_project()
        if host._workshop_window is not None
        else None
    )
    if project is not None and successful:
        from src.backend.textbook_project_store import record_imported_sections

        added = record_imported_sections(
            project,
            [final for _, final in successful],
            id_pairs=[(src, final) for src, final in successful if src],
        )
        if added:
            summary += "\n项目已记录导入状态。"
    if successful:
        host._last_imported_section_id = successful[-1][1]
        if host._workshop_window is not None:
            host._workshop_window.on_import_finished(host._last_imported_section_id)
    safe_information(host, "导入教材", summary)
    if successful:
        offer_open_teacher_after_import(host, host._last_imported_section_id)


def offer_open_teacher_after_import(host: ExperienceHost, section_id: str | None) -> None:
    from src.application.ui_guard import is_headless_ui, safe_question

    if not section_id:
        return
    if not host.isVisible() or is_headless_ui():
        return
    if not safe_question(
        host,
        "导入完成",
        "要切换到教师模式并在课程树中定位该章节吗？",
        default_yes=False,
    ):
        return
    if not host.teacher_mode:
        host.mode_action.setChecked(True)
        if not host.teacher_mode:
            host._on_mode_toggled(True)
    on_workshop_locate(host, section_id)
    try:
        section = host.adapter.find_section(section_id)
    except Exception:
        return
    for unit in section.get("units") or []:
        for lesson in unit.get("lessons") or []:
            lid = lesson.get("id")
            if lid:
                host.tree.select_lesson(lid)
                return


def import_draft_into_section(host: ExperienceHost, draft: dict, section_id: str) -> None:
    from src.application.commands import AppendUnitsToSectionCommand
    from src.application.ui_guard import safe_information, safe_warning
    from src.backend.lesson_content import clone_unit_with_fresh_ids

    try:
        section = host.adapter.find_section(section_id)
    except KeyError:
        safe_warning(host, "找不到目标", f"目标 Section「{section_id}」不存在。")
        return
    units = [u for u in draft.get("units") or [] if isinstance(u, dict)]
    if not units:
        safe_information(host, "无可导入内容", "草稿中没有 Unit。")
        return
    fresh_units = [
        clone_unit_with_fresh_ids(u, name=u.get("name", "新 Unit")) for u in units
    ]
    cmd = AppendUnitsToSectionCommand(
        host.adapter, section_id, fresh_units, resource_section=draft
    )
    cmd.signals.changed.connect(host._on_ai_edit_applied)
    host.undo_stack.push(cmd)
    host.tree.refresh_incremental()
    host.adapter.notify_resources_changed()
    host.statusBar().showMessage(
        f"已把 {len(fresh_units)} 个 Unit 追加到「{section.get('name', section_id)}」，记得保存",
        8000,
    )
    record_draft_import(host, draft, section_id)
    if host._workshop_window is not None:
        host._workshop_window.on_import_finished(section_id)
    offer_open_teacher_after_import(host, section_id)


def record_draft_import(host: ExperienceHost, draft: dict, section_id: str | None) -> None:
    if not section_id:
        return
    project = (
        host._workshop_window.current_project()
        if host._workshop_window is not None
        else None
    )
    if project is None:
        return
    from src.backend.textbook_project_store import record_imported_sections

    source_id = draft.get("id", "") if isinstance(draft, dict) else ""
    record_imported_sections(
        project,
        [section_id],
        id_pairs=[(source_id, section_id)] if source_id else None,
    )


def import_draft_into_unit(host: ExperienceHost, draft: dict, unit_id: str) -> None:
    from src.application.commands import AppendLessonsToUnitCommand
    from src.application.ui_guard import safe_information, safe_warning
    from src.backend.lesson_content import clone_lesson_with_fresh_ids

    try:
        _s, unit = host.adapter.find_unit(unit_id)
    except KeyError:
        safe_warning(host, "找不到目标", f"目标 Unit「{unit_id}」不存在。")
        return
    lessons = [
        lesson
        for u in draft.get("units") or []
        if isinstance(u, dict)
        for lesson in u.get("lessons") or []
        if isinstance(lesson, dict)
    ]
    if not lessons:
        safe_information(host, "无可导入内容", "草稿中没有 Lesson。")
        return
    fresh_lessons = [
        clone_lesson_with_fresh_ids(lesson, name=lesson.get("name", "新 Lesson"))
        for lesson in lessons
    ]
    for lesson in fresh_lessons:
        lesson["prerequisiteLessonIds"] = []
    cmd = AppendLessonsToUnitCommand(
        host.adapter, unit_id, fresh_lessons, resource_section=draft
    )
    cmd.signals.changed.connect(host._on_ai_edit_applied)
    host.undo_stack.push(cmd)
    host.tree.refresh_incremental()
    host.adapter.notify_resources_changed()
    host.statusBar().showMessage(
        f"已把 {len(fresh_lessons)} 个 Lesson 追加到「{unit.get('name', unit_id)}」，记得保存",
        8000,
    )
    section_id = _s.get("id") if isinstance(_s, dict) else None
    record_draft_import(host, draft, section_id)
    if section_id and host._workshop_window is not None:
        host._workshop_window.on_import_finished(section_id)
    if section_id:
        offer_open_teacher_after_import(host, section_id)
