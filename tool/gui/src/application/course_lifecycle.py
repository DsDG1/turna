"""Course open / switch / close Experience teardown (E5-C).

Single source of truth for clearing JobTray, ConflictGuard, FocusRing,
Timeline, metrics memory, and related UI when a course is closed or
replaced. MainWindow open paths call :func:`bind_loaded_course` after a
successful adapter.load so the three entry points share one tail.

Does not own adapter.load / file dialogs / SavePipeline.
Never raises to the caller (best-effort clears).
"""
from __future__ import annotations

from pathlib import Path
from typing import Any, Mapping
import logging
from src.application.experience_host import ExperienceHost
logger = logging.getLogger(__name__)

# Telemetry / flush reasons (aligned with C-15).
REASON_CLOSE_COURSE = "close_course"
REASON_COURSE_SWITCH = "course_switch"
REASON_APP_CLOSE = "app_close"


def clear_experience_session(
    host: ExperienceHost,
    *,
    reason: str = REASON_CLOSE_COURSE,
    flush_metrics: bool = True,
    null_adapter: bool = True,
    pause_workshop: bool = False,
) -> None:
    """Clear Experience OS session state for close or course switch.

    Parameters
    ----------
    reason:
        Metrics flush reason when ``flush_metrics`` is True.
    flush_metrics:
        When True, call ``host._flush_experience_metrics(reason)`` first.
    null_adapter:
        When True, ``experience.set_adapter(None)`` (also clears pins/selection
        inside the shell).
    pause_workshop:
        When True, interrupt+hide workshop without destroying it (switch path).
        App-exit destroy remains in closeEvent.
    """
    if flush_metrics:
        try:
            flush = getattr(host, "_flush_experience_metrics", None)
            if callable(flush):
                flush(reason)
        except Exception:
            logger.debug("application/course_lifecycle.py:clear_experience_session best-effort step failed", exc_info=True)

    if pause_workshop:
        _pause_workshop(host)

    if null_adapter:
        try:
            exp = getattr(host, "experience", None)
            if exp is not None:
                exp.set_adapter(None)
                # M-03 v4.42: clear the OCR Dock hint so a fresh course does
                # not carry a stale OCR suggestion (settings default off).
                if hasattr(exp, "set_ocr_enabled"):
                    exp.set_ocr_enabled(False)
        except Exception:
            logger.debug("application/course_lifecycle.py:clear_experience_session best-effort step failed", exc_info=True)
    else:
        # Keep adapter but still drop workshop draft (switch mid-flight).
        try:
            exp = getattr(host, "experience", None)
            if exp is not None and hasattr(exp, "set_workshop_draft"):
                exp.set_workshop_draft(None)
        except Exception:
            logger.debug("application/course_lifecycle.py:clear_experience_session best-effort step failed", exc_info=True)

    for attr, method in (
        ("experience_timeline", "clear"),
        ("experience_dock_widget", "clear"),
        ("job_tray", "clear"),
        ("conflict_guard", "clear"),
        ("focus_ring", "clear"),
        ("experience_metrics", "clear"),
        ("experience_memory", "clear_session"),  # C-13: session only
    ):
        _call_if(host, attr, method)

    # E3-A: drop Goal sandbox / last plan (never leaves staged drafts across courses).
    try:
        from src.application.goal_controller import clear_goal_state

        clear_goal_state(host)
    except Exception:
        logger.debug("application/course_lifecycle.py:clear_experience_session best-effort step failed", exc_info=True)

    try:
        keys = getattr(host, "_shown_suggestion_keys", None)
        if isinstance(keys, set):
            keys.clear()
    except Exception:
        logger.debug("application/course_lifecycle.py:clear_experience_session best-effort step failed", exc_info=True)

    # N3/F3: new course may re-run silent drive for the same action fingerprints.
    try:
        from src.application.presence_drive import clear_drive_seen

        clear_drive_seen(host)
    except Exception:
        logger.debug("application/course_lifecycle.py:clear_experience_session best-effort step failed", exc_info=True)

    # P2: allow campaign auto-offer again for the next course session.
    try:
        if hasattr(host, "_campaign_auto_offered_for"):
            host._campaign_auto_offered_for = None
    except Exception:
        logger.debug("application/course_lifecycle.py:clear_experience_session best-effort step failed", exc_info=True)

    try:
        archived = getattr(host, "_ambient_archived", None)
        if isinstance(archived, set):
            archived.clear()
    except Exception:
        logger.debug("application/course_lifecycle.py:clear_experience_session best-effort step failed", exc_info=True)

    try:
        tree = getattr(host, "tree", None)
        if tree is not None:
            if hasattr(tree, "apply_badges"):
                tree.apply_badges(None)
            if hasattr(tree, "apply_focus_ring"):
                try:
                    tree.apply_focus_ring({})
                except Exception:
                    logger.debug("application/course_lifecycle.py:clear_experience_session best-effort step failed", exc_info=True)
    except Exception:
        logger.debug("application/course_lifecycle.py:clear_experience_session best-effort step failed", exc_info=True)

    try:
        banner = getattr(host, "ambient_banner", None)
        if banner is not None and hasattr(banner, "clear"):
            banner.clear()
    except Exception:
        logger.debug("application/course_lifecycle.py:clear_experience_session best-effort step failed", exc_info=True)


def prepare_course_switch(host: ExperienceHost, old_dir: Path | None) -> None:
    """Flush metrics for the outgoing course, then full session clear.

    Call **before** assigning ``host.course_dir`` to the new path.
    No-op when ``old_dir`` is None (first open).
    """
    if old_dir is None:
        return
    try:
        flush = getattr(host, "_flush_experience_metrics", None)
        if callable(flush):
            flush(REASON_COURSE_SWITCH, course_dir=old_dir)
    except Exception:
        logger.debug("application/course_lifecycle.py:prepare_course_switch best-effort step failed", exc_info=True)
    clear_experience_session(
        host,
        reason=REASON_COURSE_SWITCH,
        flush_metrics=False,  # already flushed with old course_dir
        null_adapter=True,
        pause_workshop=True,
    )


def bind_loaded_course(
    host: ExperienceHost,
    path: Path,
    *,
    status_message: str | None = None,
    telemetry_event: str = "repo.open",
    telemetry_payload: Mapping[str, Any] | None = None,
) -> None:
    """Shared post-load tail: switch clear → bind UI → diagnose.

    Assumes ``host.adapter`` already holds the loaded course for ``path``.
    """
    path = Path(path)
    old = getattr(host, "course_dir", None)
    if old is not None and Path(old) != path:
        prepare_course_switch(host, Path(old))

    host.course_dir = path
    try:
        host.tree.display(host.adapter)
    except Exception:
        logger.debug("application/course_lifecycle.py:bind_loaded_course best-effort step failed", exc_info=True)
    try:
        host.undo_stack.clear()
        # setUndoLimit only takes effect on an empty stack; re-apply the
        # configured limit now so a runtime change to undo_limit lands here.
        apply = getattr(host, "_apply_undo_limit", None)
        if callable(apply):
            apply()
    except Exception:
        logger.debug("application/course_lifecycle.py:bind_loaded_course best-effort step failed", exc_info=True)
    try:
        enable = getattr(host, "_enable_editor_actions", None)
        if callable(enable):
            enable()
    except Exception:
        logger.debug("application/course_lifecycle.py:bind_loaded_course best-effort step failed", exc_info=True)
    try:
        add_recent = getattr(host, "_add_recent_repo", None)
        if callable(add_recent):
            add_recent(path)
    except Exception:
        logger.debug("application/course_lifecycle.py:bind_loaded_course best-effort step failed", exc_info=True)

    # C-13: bind project memory bucket to this course (session already cleared).
    try:
        mem = getattr(host, "experience_memory", None)
        if mem is not None and hasattr(mem, "bind_course"):
            mem.bind_course(path)
    except Exception:
        logger.debug("application/course_lifecycle.py:bind_loaded_course best-effort step failed", exc_info=True)

    try:
        from src.infrastructure.telemetry import telemetry

        payload = dict(telemetry_payload or {})
        if "path" not in payload and "course_dir" not in payload:
            payload["path"] = str(path)
        telemetry.record_event(telemetry_event, payload=payload)
    except Exception:
        logger.debug("application/course_lifecycle.py:bind_loaded_course best-effort step failed", exc_info=True)

    msg = status_message if status_message is not None else f"已加载: {path}"
    try:
        host.statusBar().showMessage(msg, 4000 if "已加载" in msg else 5000)
    except Exception:
        logger.debug("application/course_lifecycle.py:bind_loaded_course best-effort step failed", exc_info=True)

    try:
        host._current_node_ref = None
    except Exception:
        logger.debug("application/course_lifecycle.py:bind_loaded_course best-effort step failed", exc_info=True)

    try:
        from src.application.presence_drive import clear_drive_seen

        clear_drive_seen(host)
    except Exception:
        logger.debug("application/course_lifecycle.py:bind_loaded_course best-effort step failed", exc_info=True)

    try:
        host._refresh_experience(immediate=True)
    except Exception:
        logger.debug("application/course_lifecycle.py:bind_loaded_course best-effort step failed", exc_info=True)
    try:
        start = getattr(host, "_start_experience_diagnose", None)
        if callable(start):
            start()
    except Exception:
        logger.debug("application/course_lifecycle.py:bind_loaded_course best-effort step failed", exc_info=True)


def _pause_workshop(host: ExperienceHost) -> None:
    """Interrupt in-flight work and hide workshop (keep instance for restore)."""
    win = getattr(host, "_workshop_window", None)
    if win is None:
        return
    try:
        if hasattr(win, "interrupt_and_save"):
            win.interrupt_and_save()
    except Exception:
        logger.debug("application/course_lifecycle.py:_pause_workshop best-effort step failed", exc_info=True)
    try:
        win.hide()
    except Exception:
        logger.debug("application/course_lifecycle.py:_pause_workshop best-effort step failed", exc_info=True)


def _call_if(host: ExperienceHost, attr: str, method: str) -> None:
    try:
        obj = getattr(host, attr, None)
        if obj is None:
            return
        fn = getattr(obj, method, None)
        if callable(fn):
            fn()
    except Exception:
        logger.debug("application/course_lifecycle.py:_call_if best-effort step failed", exc_info=True)
