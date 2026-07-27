"""K-22 Textbook Experience handlers (v4.58)."""
from __future__ import annotations

from typing import Any

from src.application.ui_guard import safe_information, safe_question, safe_warning


def handle_open_workshop(host: Any, scope: dict | None = None) -> None:
    """Open / focus the course workshop window."""
    from src.application.workshop_controller import open_workshop

    try:
        open_workshop(host)
        host.experience_metrics.inc_suggestion("textbook.open_workshop", "applied")
    except Exception as exc:
        safe_warning(host, "课程工坊", f"无法打开工坊：{exc}")


def _workshop_draft_sections(host: Any) -> list[dict]:
    """Best-effort pull of design-panel draft section(s)."""
    win = getattr(host, "_workshop_window", None)
    if win is None:
        return []
    try:
        if hasattr(win, "experience_draft_sections"):
            secs = win.experience_draft_sections()
            if secs:
                return list(secs)
    except Exception:
        pass
    try:
        panel = getattr(win, "_design_panel", None)
        ctrl = getattr(panel, "_controller", None) if panel else None
        draft = getattr(ctrl, "draft", None) if ctrl else None
        if isinstance(draft, dict) and draft:
            return [draft]
    except Exception:
        pass
    return []


def handle_import_draft(host: Any, scope: dict | None = None) -> None:
    """Confirm then import workshop draft into the course (existing import path)."""
    from src.application.workshop_controller import on_textbook_sections

    if not getattr(host, "course_dir", None):
        safe_warning(host, "导入草稿", "请先打开课程目录。")
        return
    sections = _workshop_draft_sections(host)
    if not sections:
        # Try open workshop then re-check once.
        handle_open_workshop(host, scope)
        sections = _workshop_draft_sections(host)
    if not sections:
        try:
            host.statusBar().showMessage(
                "工坊尚无草稿。请先在课程工坊生成课节草稿。", 6000
            )
        except Exception:
            pass
        host.experience_metrics.inc_suggestion("textbook.import_draft", "rejected")
        return
    n = len(sections)
    if not safe_question(
        host,
        "导入工坊草稿",
        f"将把工坊中的 {n} 个草稿节导入当前课程（merge 策略，可 Undo 导入命令路径）。"
        "\n请确认已审阅草稿内容。",
        default_yes=False,
    ):
        host.experience_metrics.inc_suggestion("textbook.import_draft", "rejected")
        return
    try:
        on_textbook_sections(host, sections, "merge")
        host.experience_metrics.inc_suggestion("textbook.import_draft", "applied")
        host._record_experience_event(
            "textbook.import_draft",
            f"导入工坊草稿 {n} 节",
            action_id="textbook.import_draft",
            scope={"count": n},
        )
    except Exception as exc:
        safe_warning(host, "导入草稿", str(exc))


def handle_grounded_fill(host: Any, scope: dict | None = None) -> None:
    """Fill current/empty lesson with attachment-grounded instruction."""
    from src.backend.experience.textbook_skill import build_grounded_instruction

    if not getattr(host, "course_dir", None):
        safe_warning(host, "附件填充", "请先打开课程目录。")
        return
    deny = getattr(host, "_deny_ai_write_if_blocked", None)
    if callable(deny) and deny(label="附件填充"):
        return

    lesson_id = ""
    scope = scope or {}
    lesson_id = str(scope.get("lesson_id") or "").strip()
    if not lesson_id:
        ref = getattr(host, "_current_node_ref", None)
        if ref and ref[0] == "lesson":
            lesson_id = str(ref[1])
    if not lesson_id:
        try:
            ctx = host.experience.context
            els = list(getattr(ctx, "empty_lessons", None) or [])
            if els:
                lesson_id = str(els[0])
        except Exception:
            pass
    if not lesson_id:
        host.statusBar().showMessage("请先选中要填充的空课", 5000)
        return

    attachments = []
    try:
        ctx = host.experience.context
        attachments = list(getattr(ctx, "attachments", None) or [])
    except Exception:
        attachments = []
    if not attachments:
        host.statusBar().showMessage(
            "没有工坊附件。请先在工坊添加教材附件（可 OCR）。", 6000
        )
        return

    if not safe_question(
        host,
        "基于附件填充",
        f"将用 {len(attachments)} 个附件摘要约束，AI 填充课 {lesson_id}（预览+Undo）。",
        default_yes=False,
    ):
        host.experience_metrics.inc_suggestion("textbook.grounded_fill", "rejected")
        return

    lang = "Turkish"
    try:
        idx = getattr(host.adapter, "index", None) or {}
        lang = str(idx.get("displayName") or idx.get("language") or lang)
    except Exception:
        pass
    instruction = build_grounded_instruction(attachments, language=lang)

    try:
        section, _u, _l = host.adapter.find_lesson(lesson_id)
    except KeyError as exc:
        safe_warning(host, "附件填充", str(exc))
        return
    from src.application.experience_handlers.regenerate import _run_regen_flow

    _run_regen_flow(
        host,
        action_id="textbook.grounded_fill",
        kind="lesson",
        node_id=lesson_id,
        section=section,
        job_id=f"grounded-fill-{lesson_id}",
        job_label="附件填充",
        instruction=instruction,
        engine_kind="lesson",
    )
