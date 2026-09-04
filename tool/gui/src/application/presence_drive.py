"""F3 immersive silent drive — auto-dispatch safe Ambient/precog skills.

When ``allow_full_auto_apply`` is on, evaluate proposals and dispatch a
closed allowlist of skills through the normal Experience funnel (AutoApplyToken
+ Undo). Never raises into the editor.

Red lines:
- observer / non-full-auto → no-op
- absolute deny B never dispatched
- each (action_id, scope fingerprint) at most once per host session
- max 1 silent dispatch per refresh call (avoid stampede)
"""
from __future__ import annotations

from typing import Any, Iterable, Mapping
import logging
from src.application.experience_host import ExperienceHost
logger = logging.getLogger(__name__)

# Closed set: local / low-risk write skills only (F3 v1).
SILENT_DRIVE_ALLOWLIST: frozenset[str] = frozenset(
    {
        "soft.preview_hygiene",
        "lesson.fill_empty",
        "resource.fill_stubs",
        "resource.fill_stubs_batch",
    }
)

# N3: allow soft + fill in the same ambient tick without stampeding.
_MAX_DISPATCH_PER_TICK = 2


def _scope_fp(action_id: str, scope: Mapping[str, Any] | None) -> str:
    try:
        from src.backend.experience.proactive import proposal_id_for

        return proposal_id_for(str(action_id or ""), dict(scope or {}))
    except Exception:
        try:
            return f"{action_id}:{sorted((scope or {}).items())}"
        except Exception:
            return str(action_id or "")


def _is_drive_enabled(policy: Any) -> bool:
    try:
        if policy is None:
            return False
        if getattr(policy, "is_observer", False):
            return False
        if not bool(getattr(policy, "allow_full_auto_apply", False)):
            return False
        return int(getattr(policy, "presence_level", 0) or 0) >= 3
    except Exception:
        return False


def is_experience_ai_busy(host: ExperienceHost) -> bool:
    """True when JobTray has AI-kind work (or host flag). Never raises."""
    if host is None:
        return False
    try:
        tray = getattr(host, "job_tray", None)
        if tray is not None and hasattr(tray, "is_busy_ai"):
            if bool(tray.is_busy_ai()):
                return True
    except Exception:
        logger.debug("application/presence_drive.py:is_experience_ai_busy best-effort step failed", exc_info=True)
    try:
        if bool(getattr(host, "_presence_ai_busy", False)):
            return True
    except Exception:
        logger.debug("application/presence_drive.py:is_experience_ai_busy best-effort step failed", exc_info=True)
    return False


# Heartbeat interval after AI becomes idle (ms).
HEARTBEAT_IDLE_INTERVAL_MS = 15_000


def is_silent_drive_action(action_id: str | None) -> bool:
    aid = str(action_id or "").strip()
    if not aid:
        return False
    if aid not in SILENT_DRIVE_ALLOWLIST:
        return False
    try:
        from src.backend.experience.auto_apply import is_denied_immersive

        if is_denied_immersive(aid):
            return False
    except Exception:
        logger.debug("application/presence_drive.py:is_silent_drive_action best-effort step failed", exc_info=True)
    return True


def _seen_set(host: ExperienceHost) -> set[str]:
    try:
        s = getattr(host, "_presence_drive_seen", None)
        if isinstance(s, set):
            return s
        s = set()
        host._presence_drive_seen = s
        return s
    except Exception:
        return set()


def _proposal_payload(prop: Any) -> tuple[str, dict, str]:
    """Return (action_id, scope, title) from AmbientProposal or dict."""
    try:
        if hasattr(prop, "action_id"):
            return (
                str(getattr(prop, "action_id", "") or ""),
                dict(getattr(prop, "scope", None) or {}),
                str(getattr(prop, "title", "") or ""),
            )
        if isinstance(prop, Mapping):
            return (
                str(prop.get("action_id") or ""),
                dict(prop.get("scope") or {}),
                str(prop.get("title") or ""),
            )
    except Exception:
        logger.debug("application/presence_drive.py:_proposal_payload best-effort step failed", exc_info=True)
    return "", {}, ""


def maybe_silent_drive_proposals(
    host: ExperienceHost,
    props: Iterable[Any] | None,
    policy: Any,
) -> int:
    """Dispatch up to N allowlisted ambient proposals. Returns count."""
    if host is None or not _is_drive_enabled(policy):
        return 0
    if is_experience_ai_busy(host):
        return 0
    n = 0
    seen = _seen_set(host)
    try:
        from src.application.experience_dispatch import dispatch_experience_action
        from src.backend.experience.auto_apply import (
            ensure_audit_ring,
            record_audit,
        )
        from src.backend.experience import get_action

        for prop in props or []:
            if n >= _MAX_DISPATCH_PER_TICK:
                break
            action_id, scope, title = _proposal_payload(prop)
            if not is_silent_drive_action(action_id):
                continue
            spec = get_action(action_id)
            if spec is None or not getattr(spec, "implemented", True):
                continue
            fp = _scope_fp(action_id, scope)
            if fp in seen:
                continue
            seen.add(fp)
            try:
                record_audit(
                    ensure_audit_ring(host),
                    action_id,
                    count=1,
                    kind="silent_drive",
                )
            except Exception:
                logger.debug("application/presence_drive.py:maybe_silent_drive_proposals best-effort step failed", exc_info=True)
            try:
                metrics = getattr(host, "experience_metrics", None)
                if metrics is not None and hasattr(metrics, "inc_auto"):
                    metrics.inc_auto("scheduled")
            except Exception:
                logger.debug("application/presence_drive.py:maybe_silent_drive_proposals best-effort step failed", exc_info=True)
            try:
                dispatch_experience_action(
                    host,
                    {
                        "action_id": action_id,
                        "scope": scope,
                        "title": title or action_id,
                    },
                )
                n += 1
                _notify_silent_result(
                    host,
                    action_id=action_id,
                    title=title,
                    opaque=bool(getattr(policy, "runtime_opaque", False)),
                    ok=True,
                )
                _refresh_host_after_silent(host)
            except Exception:
                try:
                    record_audit(
                        ensure_audit_ring(host),
                        action_id,
                        count=1,
                        kind="silent_drive_failed",
                    )
                except Exception:
                    logger.debug("application/presence_drive.py:maybe_silent_drive_proposals best-effort step failed", exc_info=True)
                _notify_silent_result(
                    host,
                    action_id=action_id,
                    title=title,
                    opaque=bool(getattr(policy, "runtime_opaque", False)),
                    ok=False,
                )
    except Exception:
        return n
    return n


def _refresh_host_after_silent(host: ExperienceHost) -> None:
    """P0-b: best-effort tree/experience refresh after silent write."""
    try:
        fn = getattr(host, "_refresh_experience", None)
        if callable(fn):
            fn(immediate=False)
            return
    except Exception:
        logger.debug("application/presence_drive.py:_refresh_host_after_silent best-effort step failed", exc_info=True)
    try:
        tree = getattr(host, "tree", None)
        adapter = getattr(host, "adapter", None)
        if tree is not None and adapter is not None and hasattr(tree, "display"):
            tree.display(adapter)
    except Exception:
        logger.debug("application/presence_drive.py:_refresh_host_after_silent best-effort step failed", exc_info=True)


def maybe_silent_drive_precog(host: ExperienceHost, policy: Any) -> int:
    """From precog cache, enqueue fill/soft when full_auto. Returns count."""
    if host is None or not _is_drive_enabled(policy):
        return 0
    try:
        cache = getattr(host, "_precog_cache", None)
        if cache is None:
            return 0
        props: list[dict[str, Any]] = []
        empty = list(getattr(cache, "empty_lesson_ids", None) or [])
        if empty:
            lid = str(empty[0])
            props.append(
                {
                    "action_id": "lesson.fill_empty",
                    "scope": {
                        "first_lesson_id": lid,
                        "lesson_ids": [lid],
                        "empty_count": 1,
                    },
                    "title": f"填充空课 {lid}",
                }
            )
        soft_n = getattr(cache, "soft_fix_count", None)
        if soft_n is not None and int(soft_n) > 0:
            props.append(
                {
                    "action_id": "soft.preview_hygiene",
                    "scope": {},
                    "title": "规则规范化",
                }
            )
        return maybe_silent_drive_proposals(host, props, policy)
    except Exception:
        return 0


def clear_drive_seen(host: ExperienceHost) -> None:
    """Reset session throttle (e.g. on course switch)."""
    try:
        host._presence_drive_seen = set()
    except Exception:
        logger.debug("application/presence_drive.py:clear_drive_seen best-effort step failed", exc_info=True)


def _notify_silent_result(
    host: ExperienceHost,
    *,
    action_id: str,
    title: str = "",
    opaque: bool = False,
    ok: bool = True,
) -> None:
    """P1-a: unified silent-drive feedback (status + audit). Never raises."""
    try:
        from src.backend.experience.auto_apply import ensure_audit_ring, record_audit

        record_audit(
            ensure_audit_ring(host),
            action_id,
            count=1,
            kind="silent_ok" if ok else "silent_fail",
        )
    except Exception:
        logger.debug("application/presence_drive.py:_notify_silent_result best-effort step failed", exc_info=True)
    try:
        sb = getattr(host, "statusBar", None)
        if not callable(sb):
            return
        bar = sb()
        if bar is None or not hasattr(bar, "showMessage"):
            return
        if opaque:
            # Count only — no skill catalogue (opaque product rule).
            bar.showMessage("已自动 1 项" if ok else "自动项失败", 2500)
        else:
            label = (title or action_id or "操作").strip()[:40]
            if ok:
                bar.showMessage(f"已自动：{label}（Ctrl+Z 可撤）", 4000)
            else:
                bar.showMessage(f"自动失败：{label}", 4000)
    except Exception:
        logger.debug("application/presence_drive.py:_notify_silent_result best-effort step failed", exc_info=True)
