"""Course overview host orchestration (S-10 / v4.55).

Duck-types MainWindow. Keeps open / heat / locate / validation paths out of
``app.py`` while preserving O-01 heat injection and signal wiring.
"""
from __future__ import annotations

from typing import Any, Mapping, Sequence


def lesson_error_counts_from_problems(
    problems: Sequence[Any] | None,
) -> dict[str, int]:
    """O-01: map validate problems → ``{lesson_id: error_count}``.

    Pure: no Qt, never raises. Only ``level`` in {error, err}; lesson id taken
    from path segments shaped like ``lesson:<id>``.
    """
    counts: dict[str, int] = {}
    try:
        for p in problems or []:
            if not isinstance(p, Mapping):
                continue
            if str(p.get("level") or "").lower() not in {"error", "err"}:
                continue
            path = str(p.get("path") or "")
            lid = ""
            for part in path.replace("\\", "/").split("/"):
                part = part.strip()
                if part.startswith("lesson:"):
                    lid = part.split(":", 1)[1].strip()
            if not lid:
                continue
            counts[lid] = counts.get(lid, 0) + 1
    except Exception:
        return {}
    return counts


def open_overview(host: Any) -> None:
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
    sync_overview_heat_errors(host)
    host._overview_window.refresh()
    host._overview_window.show()
    host._overview_window.raise_()
    host._overview_window.activateWindow()


def sync_overview_heat_errors(host: Any) -> None:
    """O-01: push per-lesson validate error counts into the overview (if open)."""
    win = getattr(host, "_overview_window", None)
    if win is None:
        return
    counts: dict[str, int] = {}
    try:
        problems = None
        exp = getattr(host, "experience", None)
        if exp is not None:
            problems = getattr(exp, "_validate_problems", None)
            ctx = getattr(exp, "context", None)
            if ctx is not None and getattr(ctx, "validate_problems", None):
                problems = ctx.validate_problems
        counts = lesson_error_counts_from_problems(problems)
    except Exception:
        counts = {}
    try:
        win.set_lesson_error_counts(counts)
    except Exception:
        pass


def on_overview_lesson_selected(host: Any, lesson_id: str) -> None:
    """Locate a lesson clicked in the overview inside the main tree."""
    try:
        host.showNormal()
        host.raise_()
        host.activateWindow()
    except Exception:
        pass
    try:
        host.tree.select_lesson(lesson_id)
    except Exception:
        pass


def on_overview_validation(host: Any, problems: list) -> None:
    """Open the existing validation report with problems from the overview."""
    try:
        host._show_validation_report(problems, title="课程结构总览 - 校验结果")
    except Exception:
        pass


def on_overview_destroyed(host: Any, *_args: Any) -> None:
    host._overview_window = None
