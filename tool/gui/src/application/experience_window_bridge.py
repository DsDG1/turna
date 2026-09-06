"""MainWindow <-> ExperienceShell bridge (focus ring, refresh, metrics).

Extracted from ``src/app.py`` (P2 slim-down); every function takes the
MainWindow (``host``) as context. The window keeps same-name delegating
methods so tests and signal wiring are unchanged.
"""
from __future__ import annotations

import logging
from typing import Any

from src.application.course_lifecycle import clear_experience_session, REASON_CLOSE_COURSE
from src.application.experience_shell import format_health_status_line
from src.infrastructure.telemetry import telemetry

logger = logging.getLogger(__name__)


def sync_focus_ring(host) -> None:
    if not hasattr(host, "focus_ring") or host.focus_ring is None:
        return
    host.focus_ring.clear_roles("selected", "pinned")
    if host._current_node_ref:
        kind, nid = host._current_node_ref
        host.focus_ring.set(f"{kind}:{nid}", "selected")
    if hasattr(host, "experience") and host.experience is not None:
        for pref in getattr(host.experience, "pinned_refs", []):
            if isinstance(pref, tuple) and len(pref) == 2:
                host.focus_ring.set(f"{pref[0]}:{pref[1]}", "pinned")


def on_experience_context_changed(host, ctx) -> None:
    if hasattr(host, "experience_dock_widget") and host.experience_dock_widget is not None:
        sugs = getattr(host.experience, "suggestions", []) if hasattr(host, "experience") else []
        host.experience_dock_widget.apply_context_and_suggestions(ctx, sugs)
    if hasattr(host, "_refresh_ambient"):
        host._refresh_ambient()


def on_experience_pin_toggled(host) -> None:
    if hasattr(host, "experience") and host.experience is not None:
        host.experience.toggle_pin_selection()
        host._sync_focus_ring()
        host._refresh_experience(immediate=False, focus_only=True)


def refresh_experience(host, *, immediate: bool = False, focus_only: bool = False) -> None:
    if host.course_dir is None:
        clear_experience_session(host, reason=REASON_CLOSE_COURSE)
        if hasattr(host, "_health_status_label"):
            host._health_status_label.setText(format_health_status_line(None))
        return

    if hasattr(host, "experience") and host.experience is not None:
        host.experience.set_adapter(host.adapter)
        if hasattr(host, "job_tray") and host.job_tray is not None:
            host.experience.set_active_jobs(host.job_tray.active_jobs())
        if hasattr(host, "_current_node_ref"):
            host.experience.set_selection(host._current_node_ref)
        if focus_only:
            host.experience.invalidate_focus()
        else:
            if immediate:
                host.experience.rebuild_now()
            else:
                host.experience.invalidate()


def on_experience_resources_changed(host) -> None:
    if hasattr(host, "experience") and host.experience is not None:
        host.experience.mark_stale()


def flush_experience_metrics(host, reason: str = "", *, course_dir: Any = None) -> None:
    metrics = getattr(host, "experience_metrics", None)
    if metrics is not None and hasattr(metrics, "snapshot"):
        snap = metrics.snapshot()
        telemetry.record_event(
            "experience.metrics_flush",
            reason=reason,
            course_dir=str(course_dir or host.course_dir or ""),
            **snap,
        )


def record_experience_event(host, event_name: str, label: str = "", **payload) -> None:
    try:
        telemetry.record_event(event_name, label=label, **payload)
    except Exception:
        logger.debug("MainWindow._record_experience_event best-effort failed", exc_info=True)
