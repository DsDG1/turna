"""Course overview host orchestration (S-10 / v4.55).

Duck-types MainWindow. Keeps open / locate / validation paths out of
``app.py`` while preserving signal wiring.
"""
from __future__ import annotations

from typing import Any
import logging
from src.application.experience_host import ExperienceHost
logger = logging.getLogger(__name__)


def open_overview(host: ExperienceHost) -> None:
    """Open or raise the course structure overview window."""
    from src.infrastructure.telemetry import telemetry
    from src.widgets.course_overview import CourseOverviewWindow

    telemetry.record_event("overview.open")
    if getattr(host, "_overview_window", None) is None:
        host._overview_window = CourseOverviewWindow(host.adapter, host)
        host._overview_window.lesson_selected.connect(
            host._on_overview_lesson_selected
        )
        host._overview_window.validation_requested.connect(
            host._on_overview_validation
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


def on_overview_destroyed(host: ExperienceHost, *_args: Any) -> None:
    host._overview_window = None
