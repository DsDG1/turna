"""Course overview host orchestration (S-10 / v4.55).

Duck-types MainWindow. Keeps open / locate / validation paths out of
``app.py`` while preserving signal wiring.
"""
from __future__ import annotations

import functools
from typing import Any
import logging
from src.application.experience_host import ExperienceHost
logger = logging.getLogger(__name__)

#: Failures tolerated by the health-panel callbacks. Narrow on purpose: an
#: unexpected exception should surface instead of being swallowed.
_UI_ERRORS = (AttributeError, ImportError, KeyError, RuntimeError, TypeError, ValueError)


def open_overview(host: ExperienceHost) -> None:
    """Open the overview: embedded view (shell) or floating window fallback."""
    from src.infrastructure.telemetry import telemetry
    from src.widgets.course_overview import CourseOverviewWindow

    telemetry.record_event("overview.open")
    # W2: when the shell's central stack exists, the overview is a view, not
    # a window (duck-typed so hosts without the shell keep the old path).
    set_view = getattr(host, "_set_view", None)
    if callable(set_view) and getattr(host, "_view_pages", None):
        set_view("overview")
        return
    if getattr(host, "_overview_window", None) is None:
        host._overview_window = CourseOverviewWindow(host.adapter, host)
        host._overview_window.lesson_selected.connect(
            host._on_overview_lesson_selected
        )
        host._overview_window.validation_requested.connect(
            host._on_overview_validation
        )
        host._overview_window.health_locate_requested.connect(
            functools.partial(on_overview_health_locate, host)
        )
        host._overview_window.health_action_requested.connect(
            functools.partial(on_overview_health_action, host)
        )
        host._overview_window.destroyed.connect(host._on_overview_destroyed)
    host._overview_window.refresh()
    host._overview_window.show()
    host._overview_window.raise_()
    host._overview_window.activateWindow()


def on_overview_lesson_selected(host: ExperienceHost, lesson_id: str) -> None:
    """Locate a lesson clicked in the overview inside the main tree."""
    try:
        host.showNormal()
        host.raise_()
        host.activateWindow()
    except Exception:
        logger.debug("application/overview_controller.py:on_overview_lesson_selected best-effort step failed", exc_info=True)
    # W2: locating replaces window-raising with surfacing the edit view.
    try:
        from src.application.shell_views import reveal_edit_view

        reveal_edit_view(host)
    except Exception:
        # Locating still works without the view swap — the next select_lesson
        # repaints the tree anyway, so this is a cosmetic degrade, not a fault.
        logger.debug("reveal_edit_view failed (overview locate)", exc_info=True)
    try:
        host.tree.select_lesson(lesson_id)
    except Exception:
        logger.debug("application/overview_controller.py:on_overview_lesson_selected best-effort step failed", exc_info=True)


def on_overview_validation(host: ExperienceHost, problems: list) -> None:
    """Open the existing validation report with problems from the overview."""
    try:
        host._show_validation_report(problems, title="课程结构总览 - 校验结果")
    except Exception:
        logger.debug("application/overview_controller.py:on_overview_validation best-effort step failed", exc_info=True)


def on_overview_health_locate(
    host: ExperienceHost, kind: str, node_id: str
) -> None:
    """Locate a finding from the inline health panel in the course tree."""
    if not node_id:
        return
    try:
        from src.application.shell_views import reveal_edit_view

        reveal_edit_view(host)
    except _UI_ERRORS:
        # Cosmetic only: the select_* below still locates the node.
        logger.debug(
            "application/overview_controller.py:health locate view swap failed",
            exc_info=True,
        )
    try:
        if kind == "unit":
            host.tree.select_unit(node_id)
        elif kind == "lesson":
            host.tree.select_lesson(node_id)
        else:
            host.tree.select_section(node_id)
    except _UI_ERRORS:
        logger.debug(
            "application/overview_controller.py:health locate select failed",
            exc_info=True,
        )


def on_overview_health_action(host: ExperienceHost, step: dict) -> None:
    """Dispatch one health repair step through the normal Experience funnel.

    Policy, preview, confirmation and undo stay inside the handler — the health
    panel never writes the course itself.
    """
    payload = dict(step or {})
    action_id = str(payload.get("action_id") or "")
    if not action_id:
        return
    scope = payload.get("scope")
    if not isinstance(scope, dict):
        scope = {}
    from src.application.experience_dispatch import dispatch_experience_action

    try:
        dispatch_experience_action(
            host,
            {
                "action_id": action_id,
                "scope": dict(scope),
                "title": str(payload.get("title") or action_id),
                "source": "course_health",
            },
        )
    except _UI_ERRORS:
        logger.warning(
            "application/overview_controller.py:health action dispatch failed",
            exc_info=True,
        )
        try:
            host.statusBar().showMessage("课程体检：执行失败，详见日志", 5000)
        except _UI_ERRORS:
            logger.debug(
                "application/overview_controller.py:health failure status failed",
                exc_info=True,
            )


def on_overview_destroyed(host: ExperienceHost, *_args: Any) -> None:
    host._overview_window = None
    # W2: the embedded view holds the same widget — clear it too or a later
    # ensure_overview_embedded() would return a destroyed wrapper.
    if getattr(host, "_overview_widget", None) is not None:
        host._overview_widget = None
