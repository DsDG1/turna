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
        sync_experience_memory(host)
        sync_experience_attachments(host)
        sync_usage_today(host)
        if focus_only:
            host.experience.invalidate_focus()
        else:
            if immediate:
                host.experience.rebuild_now()
            else:
                host.experience.invalidate()


def sync_experience_memory(host) -> None:
    """C-13: push ExperienceMemory context fields into the Shell.

    ``recent_intents`` / ``author_profile`` land on the next Context rebuild;
    ``session.last_surface`` mirrors the Shell's current surface so memory
    consumers can see where the user was working. Never raises.
    """
    mem = getattr(host, "experience_memory", None)
    exp = getattr(host, "experience", None)
    if mem is None or exp is None:
        return
    try:
        fields = mem.context_fields()
        exp.set_recent_intents(fields.get("recent_intents"))
        exp.set_author_profile(fields.get("author_profile"))
        session = getattr(mem, "session", None)
        if session is not None:
            session.set_last_surface(getattr(exp, "surface", "") or "")
    except Exception:
        logger.debug(
            "experience_window_bridge.py:sync_experience_memory best-effort step failed",
            exc_info=True,
        )


def sync_experience_attachments(host) -> None:
    """M-01: snapshot workshop attachment bar into the Shell (closed shape).

    Only metadata (name/kind/char_count/hash) enters the Context — raw text
    and base64 payloads stay in the bar. Never raises.
    """
    exp = getattr(host, "experience", None)
    if exp is None:
        return
    try:
        from src.backend.experience.attachments import build_attachment_snapshot

        win = getattr(host, "_workshop_window", None)
        records = []
        if win is not None:
            getter = getattr(win, "attachment_records", None)
            if callable(getter):
                records = getter() or []
        exp.set_attachments(build_attachment_snapshot(records, source="workshop"))
    except Exception:
        logger.debug(
            "experience_window_bridge.py:sync_experience_attachments best-effort step failed",
            exc_info=True,
        )


def sync_usage_today(host) -> None:
    """M-08: feed telemetry today's AI-usage bucket into the Shell."""
    exp = getattr(host, "experience", None)
    if exp is None:
        return
    try:
        from src.backend.experience.metrics import usage_today_from_summary

        exp.set_usage_today(usage_today_from_summary(telemetry.usage_summary()))
    except Exception:
        logger.debug(
            "experience_window_bridge.py:sync_usage_today best-effort step failed",
            exc_info=True,
        )


def apply_experience_memory_settings(host) -> None:
    """Wire ``memory_persist_*`` settings into the ExperienceMemory layers."""
    mem = getattr(host, "experience_memory", None)
    if mem is None:
        return
    try:
        settings = getattr(host, "_settings_obj", None)
        mem.configure_project_persist(
            enabled=bool(
                getattr(settings, "experience_memory_persist_project", False)
            )
        )
        mem.configure_author_persist(
            enabled=bool(
                getattr(settings, "experience_memory_persist_author", False)
            )
        )
    except Exception:
        logger.debug(
            "experience_window_bridge.py:apply_experience_memory_settings best-effort step failed",
            exc_info=True,
        )


def record_experience_intent(
    host, action_id: str, *, label: str = "", scope: Any = None, source: str = ""
) -> None:
    """C-13: record a dispatched skill into session memory, then re-sync."""
    mem = getattr(host, "experience_memory", None)
    if mem is None:
        return
    try:
        mem.record_intent(action_id, label=label, scope=scope, source=source)
        sync_experience_memory(host)
        exp = getattr(host, "experience", None)
        if exp is not None:
            exp.invalidate()
    except Exception:
        logger.debug(
            "experience_window_bridge.py:record_experience_intent best-effort step failed",
            exc_info=True,
        )


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
