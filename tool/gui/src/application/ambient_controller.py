"""Ambient suggestion orchestration (E2.0 / A3 / P2 / F4).

Module-level functions duck-typing ``MainWindow`` via the
``ExperienceHost`` protocol (workshop_controller pattern). Extracted from
``experience_skills_mixin`` so the mixin keeps only policy/funnel glue and
thin ``_experience_*`` wrappers (ai_refactor_contract §1d).

Covers: ambient proposal refresh + silent drive + precognition refresh,
heartbeat pacing (orphan timer: ``_ambient_heartbeat`` has no creator in src;
kept for the retired-banner test fixtures), defer-store persistence, and the
accept / archive / mute banner reactions.
"""
from __future__ import annotations

import logging

from src.application.experience_host import ExperienceHost

logger = logging.getLogger(__name__)


def load_experience_mute_dict(host: ExperienceHost) -> dict:
    import json

    raw = getattr(host._settings_obj, "experience_mute_json", "") or ""
    if not raw.strip():
        return {}
    try:
        data = json.loads(raw)
        return data if isinstance(data, dict) else {}
    except json.JSONDecodeError:
        return {}


def save_experience_mute(host: ExperienceHost) -> None:
    import json

    host._settings_obj.experience_mute_json = json.dumps(
        host._ambient_mute.to_dict(), ensure_ascii=False
    )
    host._settings_obj.save_to_qsettings(host._settings)


def load_defer_store(host: ExperienceHost):
    """A3 ②: load DeferStore from ``experience_defer_json`` (never raises)."""
    import json

    from src.backend.experience.defer_store import DeferStore

    raw = getattr(host._settings_obj, "experience_defer_json", "") or ""
    if not raw.strip():
        return DeferStore()
    try:
        data = json.loads(raw)
        return DeferStore.from_dict(data if isinstance(data, dict) else {})
    except (json.JSONDecodeError, ValueError):
        return DeferStore()


def save_defer_store(host: ExperienceHost) -> None:
    import json

    store = getattr(host, "_defer_store", None)
    if store is None:
        return
    try:
        host._settings_obj.experience_defer_json = json.dumps(
            store.to_dict(), ensure_ascii=False
        )
        host._settings_obj.save_to_qsettings(host._settings)
    except Exception:
        logger.debug("application/ambient_controller.py:save_defer_store best-effort step failed", exc_info=True)


def refresh_ambient(host: ExperienceHost) -> None:
    """E2.0 + A3 ①: evaluate up to 3 Ambient proposals (local, no LLM)."""
    from src.backend.experience.proactive import evaluate_ambient_batch

    if not hasattr(host, "ambient_banner"):
        return
    from src.backend.experience import resolve_policy

    policy = resolve_policy(getattr(host, "_settings_obj", None))
    if policy.is_observer:
        host.ambient_banner.clear()
        return
    ctx = host.experience.context
    # A3 ② + P2: defer via policy effective flag (active bundle ORs setting).
    defer_on = bool(getattr(policy, "allow_defer_resurface", False))
    defer_store = host._defer_store if defer_on else None
    props = evaluate_ambient_batch(
        ctx,
        mute=host._ambient_mute,
        archived_ids=host._ambient_archived,
        suggestions=host.experience.suggestions,
        limit=3,
        defer_store=defer_store,
    )
    # A3 ②: drop defers whose issue has resolved (best-effort, never raises).
    if defer_store is not None:
        try:
            from src.backend.experience.proactive import proposal_id_for

            current_ids = {
                proposal_id_for(str(s.get("action_id") or ""), dict(s.get("scope") or {}))
                for s in (host.experience.suggestions or [])
                if isinstance(s, dict) and s.get("action_id")
            }
            defer_store.purge_resolved(current_ids)
        except Exception:
            logger.debug("application/ambient_controller.py:refresh_ambient best-effort step failed", exc_info=True)
    if not props:
        host.ambient_banner.clear()
    elif getattr(policy, "runtime_opaque", False):
        # P4/F4: opaque — hide explanatory ambient text but still count
        # evaluation (silent presence). Heartbeat must keep refreshing.
        host.ambient_banner.clear()
        host.experience_metrics.inc_ambient("shown")
        try:
            sb = getattr(host, "statusBar", None)
            if callable(sb) and props:
                bar = sb()
                if bar is not None and hasattr(bar, "showMessage"):
                    bar.showMessage("…", 800)
        except Exception:
            logger.debug("application/ambient_controller.py:refresh_ambient best-effort step failed", exc_info=True)
    else:
        host.ambient_banner.show_proposals(props)
        host.experience_metrics.inc_ambient("shown")
        # A3 ②: count resurfaced proposals separately (no-op when defer_store
        # is None - no deferred_resurface source is produced).
        for _p in props:
            if getattr(_p, "source", "") == "deferred_resurface":
                host.experience_metrics.inc_ambient("resurfaced")
    # F3: immersive full-auto silent drive of allowlisted ambient props.
    try:
        from src.application.presence_drive import maybe_silent_drive_proposals

        if getattr(policy, "allow_full_auto_apply", False):
            maybe_silent_drive_proposals(host, props, policy)
    except Exception:
        logger.debug("application/ambient_controller.py:refresh_ambient best-effort step failed", exc_info=True)
    # P2: once-per-course campaign auto surface (writes still confirm).
    try:
        from src.application.presence_mode import maybe_auto_enqueue_campaign

        maybe_auto_enqueue_campaign(host)
    except Exception:
        logger.debug("application/ambient_controller.py:refresh_ambient best-effort step failed", exc_info=True)
    # P5: local precognition refresh (soft/empty/weak fingerprints).
    try:
        from src.backend.experience.precognition import (
            get_or_create_precog,
            refresh_local_precog,
        )

        if getattr(policy, "allow_full_auto_apply", False) or getattr(
            policy, "is_active_bundle", False
        ):
            cache = get_or_create_precog(host)
            ctx = host.experience.context
            budget_ok = bool(getattr(policy, "allow_ai_skill", True))
            refresh_local_precog(
                cache,
                adapter=getattr(host, "adapter", None),
                empty_lessons=list(getattr(ctx, "empty_lessons", None) or [])
                if ctx
                else [],
                quality_by_section=dict(
                    getattr(ctx, "quality_by_section", None) or {}
                )
                if ctx
                else {},
                budget_ok=budget_ok,
            )
            # F3: after precog miss/hit, try soft/fill silent drive once.
            if getattr(policy, "allow_full_auto_apply", False):
                try:
                    from src.application.presence_drive import (
                        maybe_silent_drive_precog,
                    )

                    maybe_silent_drive_precog(host, policy)
                except Exception:
                    logger.debug("application/ambient_controller.py:refresh_ambient best-effort step failed", exc_info=True)
    except Exception:
        logger.debug("application/ambient_controller.py:refresh_ambient best-effort step failed", exc_info=True)


def on_ambient_heartbeat(host: ExperienceHost) -> None:
    """A3 ③ + F4 + P2: re-evaluate only when AI is idle.

    Interval is full ``HEARTBEAT_IDLE_INTERVAL_MS`` after each successful
    tick **or** after AI jobs finish (timer restarts from idle moment).
    While AI is busy the timer is stopped so the interval does not count.
    """
    if not hasattr(host, "ambient_banner") or host.course_dir is None:
        return
    from src.backend.experience import resolve_policy
    from src.application.presence_drive import is_experience_ai_busy

    policy = resolve_policy(getattr(host, "_settings_obj", None))
    if policy.is_observer:
        return
    live = bool(getattr(policy, "allow_ambient_live", False))
    defer = bool(getattr(policy, "allow_defer_resurface", False))
    if not (live or defer):
        return
    try:
        if hasattr(host, "isActiveWindow") and not host.isActiveWindow():
            return
    except Exception:
        logger.debug("application/ambient_controller.py:on_ambient_heartbeat best-effort step failed", exc_info=True)
    # P2: do not refresh/drive while AI is still answering.
    if is_experience_ai_busy(host):
        pause_heartbeat_until_idle(host)
        return
    if live and getattr(host.experience, "_content_stale", False):
        host.experience.invalidate(immediate=False)
    else:
        refresh_ambient(host)


def pause_heartbeat_until_idle(host: ExperienceHost) -> None:
    """Stop interval clock; resume full interval when AI goes idle."""
    try:
        host._heartbeat_wait_idle = True
        hb = getattr(host, "_ambient_heartbeat", None)
        if hb is not None and hb.isActive():
            hb.stop()
    except Exception:
        logger.debug("application/ambient_controller.py:pause_heartbeat_until_idle best-effort step failed", exc_info=True)


def on_job_tray_ai_busy_changed(host: ExperienceHost, busy: bool) -> None:
    """P2: AI job started → pause heartbeat; all done → start full interval."""
    try:
        host._presence_ai_busy = bool(busy)
    except Exception:
        logger.debug("application/ambient_controller.py:on_job_tray_ai_busy_changed best-effort step failed", exc_info=True)
    if busy:
        pause_heartbeat_until_idle(host)
        return
    # Became idle: start counting the full interval only now.
    try:
        hb = getattr(host, "_ambient_heartbeat", None)
        if hb is None:
            return
        from src.backend.experience import resolve_policy
        from src.application.presence_drive import HEARTBEAT_IDLE_INTERVAL_MS

        policy = resolve_policy(getattr(host, "_settings_obj", None))
        live = bool(getattr(policy, "allow_ambient_live", False))
        defer = bool(getattr(policy, "allow_defer_resurface", False))
        if policy.is_observer or not (live or defer):
            return
        if host.course_dir is None:
            return
        hb.setInterval(int(HEARTBEAT_IDLE_INTERVAL_MS))
        if not hb.isActive():
            hb.start()
        host._heartbeat_wait_idle = False
    except Exception:
        logger.debug("application/ambient_controller.py:on_job_tray_ai_busy_changed best-effort step failed", exc_info=True)


def on_ambient_accepted(host: ExperienceHost, proposal) -> None:
    from src.backend.experience.proactive import AmbientProposal

    if isinstance(proposal, AmbientProposal):
        payload = {
            "action_id": proposal.action_id,
            "scope": dict(proposal.scope),
            "title": proposal.title,
        }
        pid = proposal.id
    else:
        payload = {
            "action_id": str(proposal.get("action_id") or ""),
            "scope": dict(proposal.get("scope") or {}),
            "title": str(proposal.get("title") or ""),
        }
        pid = str(proposal.get("id") or "")
    if pid:
        host._ambient_archived.add(pid)
    # A3 ①: promote the next proposal instead of hiding the banner.
    refresh_ambient(host)
    host.experience_metrics.inc_ambient("accepted")
    host._record_experience_event(
        "ambient.accept",
        payload.get("title") or payload["action_id"],
        action_id=payload["action_id"],
        scope=payload.get("scope"),
    )
    host._on_experience_suggestion(payload)


def on_ambient_archived(host: ExperienceHost, proposal_id: str) -> None:
    pid = str(proposal_id or "")
    if not pid:
        return
    from src.backend.experience import resolve_policy

    defer_on = bool(
        getattr(
            resolve_policy(getattr(host, "_settings_obj", None)),
            "allow_defer_resurface",
            False,
        )
    )
    # Look up the proposal in the current queue to capture action_id.
    prop = None
    for p in host.ambient_banner.proposals():
        if getattr(p, "id", "") == pid:
            prop = p
            break
    if defer_on and prop is not None:
        # A3 ②: defer with escalating cooldown (15->30->60min->permanent).
        record = host._defer_store.add(
            pid, getattr(prop, "action_id", "") or ""
        )
        if not record.re_surface_after_iso:
            # Escalated to permanent -> session-level archive, no resurface.
            host._ambient_archived.add(pid)
            host.experience_metrics.inc_ambient("dismissed")
        else:
            save_defer_store(host)
            host.experience_metrics.inc_ambient("deferred")
    else:
        # Legacy: session-only archive (no resurface).
        host._ambient_archived.add(pid)
        host.experience_metrics.inc_ambient("dismissed")
    host.statusBar().showMessage("已归档本条主动建议", 3000)
    refresh_ambient(host)


def on_ambient_mute_changed(host: ExperienceHost, level: str) -> None:
    from src.backend.experience.proactive import make_mute

    host._ambient_mute = make_mute(level)
    save_experience_mute(host)
    host.ambient_banner.clear()
    host.experience_metrics.inc_ambient("muted")
    labels = {
        "hours4": "4 小时",
        "today": "今日",
        "permanent": "永久",
    }
    host.statusBar().showMessage(
        f"主动建议已静音（{labels.get(level, level)}）", 5000
    )
    host._record_experience_event(
        "ambient.mute", f"静音 {level}", action_id="app.mute"
    )
