"""Entry point for the standalone course-planning window (P0-2).

The window is a ``src.widgets`` module, not ``src.dialogs``: opening it from
the app menu would otherwise add one more ``application → dialogs`` import and
trip the guard ratchet. Composition still lives here (application layer), and
the window only talks to ``src.application.course_plan_service``.
"""
from __future__ import annotations

import logging
from typing import Any

from src.application.experience_host import ExperienceHost
from src.application.ui_guard import safe_warning

logger = logging.getLogger(__name__)


def import_section_draft(
    host: ExperienceHost, draft: dict[str, Any]
) -> tuple[str, str, str]:
    """Import one generated plan draft as a fresh section.

    Returns ``(outcome, final_section_id, message)`` where ``outcome`` is the
    command-level ``imported`` / ``merged`` / ``replaced`` / ``skipped`` /
    ``blocked`` value. Uses ``APPEND_AS_NEW`` so a plan id colliding with an
    existing section is rewritten instead of overwriting it.
    """
    service = getattr(host, "_import_service", None)
    if service is None:
        return "blocked", "", "当前窗口没有可用的导入服务。"
    from src.backend.import_strategy import ImportStrategy

    result = service.import_section(
        draft, strategy=ImportStrategy.APPEND_AS_NEW.value
    )
    details = dict(getattr(result, "details", None) or {})
    outcome = str(details.get("outcome") or getattr(result, "outcome", ""))
    section_id = str(details.get("section_id") or "")
    message = str(getattr(result, "message", "") or "")
    return outcome, section_id, message


def open_course_plan(host: ExperienceHost) -> None:
    """Open (or raise) the course-planning window for the loaded course."""
    if not getattr(host, "course_dir", ""):
        safe_warning(host, "整门课程规划", "请先打开课程目录，再生成课程大纲。")
        return

    from src.widgets.course_plan_window import CoursePlanWindow

    existing = host.findChild(CoursePlanWindow)
    if existing is not None:
        existing.show()
        existing.raise_()
        existing.activateWindow()
        return

    window = CoursePlanWindow(
        host.adapter,
        host,
        config_fn=lambda: getattr(host, "_ai_config", None),
        settings_fn=lambda: getattr(host, "_settings_obj", None),
        import_fn=lambda draft: import_section_draft(host, draft),
    )
    window.show()
    window.raise_()
    window.activateWindow()
