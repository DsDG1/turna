"""Experience action dispatch registry (M4/M7 + R2 auto token).

Policy / telemetry / metrics stay here. Handler map lives in
``experience_handlers.registry`` so skill registration is separated from
MainWindow mixin dispatch (M7).

R2: immersive full-auto issues an :class:`AutoApplyToken` bound to a
generation counter. The token is stored on the host so async workers that
later call ``PreviewHost.offer`` still auto-apply; demote bumps generation
and clears the token.
"""
from __future__ import annotations

import logging
from typing import Any, Callable

from PySide6.QtWidgets import QMessageBox

from src.application.experience_handlers.registry import HANDLERS, register_all
from src.application.experience_host import ExperienceHost
from src.backend.experience import can_dispatch, get_action
from src.infrastructure.telemetry import telemetry

logger = logging.getLogger(__name__)

# Ensure map is populated (idempotent).
register_all()

Handler = Callable[[ExperienceHost, dict], None]

HANDLER_OPTIONAL_ACTIONS: frozenset[str] = frozenset(
    {
        "app.help",
        "app.pin",
        "app.save",
        "app.undo",
        "app.why",
        "help.fix",
        "help.tour",
    }
)


def register(action_id: str, handler: Handler) -> None:
    HANDLERS[action_id] = handler


def _record_auto_metric(host: ExperienceHost, stage: str, action_id: str = "") -> None:
    """Best-effort metrics for auto pipeline; never raises."""
    try:
        metrics = getattr(host, "experience_metrics", None)
        if metrics is None:
            return
        if hasattr(metrics, "inc_auto"):
            metrics.inc_auto(stage)
        elif hasattr(metrics, "inc_suggestion") and action_id:
            # Fall back onto suggestion stages when inc_auto absent.
            mapped = {
                "applied": "applied",
                "failed": "rejected",
                "scheduled": "accepted",
            }.get(stage)
            if mapped:
                metrics.inc_suggestion(action_id, mapped)
    except Exception:
        logger.warning("application/experience_dispatch.py:_record_auto_metric best-effort step failed", exc_info=True)


def dispatch_experience_action(host: ExperienceHost, suggestion: dict) -> None:
    """Single funnel: Dock / Ambient / palette → policy → handler."""
    action = str(suggestion.get("action_id") or "")
    scope = suggestion.get("scope") or {}
    if not isinstance(scope, dict):
        scope = {}

    telemetry.record_event(
        "experience.suggestion",
        payload={"action_id": action},
    )
    metrics = getattr(host, "experience_metrics", None)
    if metrics is not None and hasattr(metrics, "inc_suggestion"):
        metrics.inc_suggestion(action, "accepted")

    spec = get_action(action)
    if spec is None:
        host.statusBar().showMessage(f"建议已记录：{action or 'unknown'}", 3000)
        return
    if not spec.implemented:
        host.statusBar().showMessage(
            f"已记录（「{spec.title}」skill 将在后续阶段接入）", 5000
        )
        return

    resolve = getattr(host, "_resolve_experience_policy", None)
    if callable(resolve):
        policy = resolve(action_id=action)
    else:
        from src.backend.experience import resolve_policy

        policy = resolve_policy(
            getattr(host, "_settings_obj", None), action_id=action
        )
    allowed, deny_reason = can_dispatch(spec, policy)
    if not allowed:
        try:
            opaque = bool(getattr(policy, "runtime_opaque", False))
        except Exception:
            opaque = False
        if not opaque:
            host.statusBar().showMessage(f"{deny_reason}：{spec.title}", 6000)
            if spec.dangerous and not policy.allow_dangerous:
                QMessageBox.information(
                    host,
                    "危险技能已锁定",
                    f"「{spec.title}」属于危险技能（删 id / 跨节改写 / Hard import），默认关闭。\n"
                    "请在 设置 ▸ 体验 OS ▸ 允许危险技能 中开启后再试。",
                )
        return

    handler = HANDLERS.get(action)
    if handler is None:
        host.statusBar().showMessage(f"建议已记录：{action}", 3000)
        return
    # Let handlers that wrap multi-kind actions (e.g. *.edit) see action_id.
    try:
        host._dispatch_action_id = action
    except Exception:
        logger.warning("application/experience_dispatch.py:dispatch_experience_action best-effort step failed", exc_info=True)

    def _run() -> None:
        handler(host, scope)

    try:
        from src.backend.experience.auto_apply import (
            bind_auto_apply_token,
            ensure_audit_ring,
            is_auto_apply_allowed,
            issue_auto_apply_token,
            record_audit,
        )
        from src.application.ui_guard import auto_confirm_scope
        from src.backend.experience.circuit_breaker import get_circuit_breaker

        auto = is_auto_apply_allowed(action, policy)
        cb = get_circuit_breaker()
        if auto:
            cb_allowed, cb_reason = cb.can_auto_dispatch(action)
            if not cb_allowed:
                auto = False
                logger.warning(
                    "Circuit breaker intercepted auto-apply for %s: %s",
                    action,
                    cb_reason,
                )
                opaque_candidate = bool(getattr(policy, "runtime_opaque", False))
                if not opaque_candidate:
                    try:
                        host.statusBar().showMessage(cb_reason[:240], 6000)
                    except Exception:
                        logger.warning("application/experience_dispatch.py: cb status failed", exc_info=True)

        opaque = bool(getattr(policy, "runtime_opaque", False)) and auto
        if auto:
            cb.record_dispatch(action)
            token = issue_auto_apply_token(action, opaque=opaque)
            bind_auto_apply_token(host, token)
            try:
                ring = ensure_audit_ring(host)
                record_audit(ring, action, count=1, kind="auto_scheduled")
            except Exception:
                logger.warning("application/experience_dispatch.py:dispatch_experience_action best-effort step failed", exc_info=True)
            _record_auto_metric(host, "scheduled", action)
            # Keep host token after scope ends so async offer can still auto.
            with auto_confirm_scope(opaque=opaque, token=token):
                try:
                    _run()
                    cb.record_success(action)
                except Exception as exc:
                    cb.record_failure(action, str(exc))
                    _record_auto_metric(host, "failed", action)
                    try:
                        ring = ensure_audit_ring(host)
                        record_audit(ring, action, count=1, kind="auto_failed")
                    except Exception:
                        logger.warning("application/experience_dispatch.py:dispatch_experience_action best-effort step failed", exc_info=True)
                    if not opaque:
                        try:
                            host.statusBar().showMessage(
                                f"自动应用失败：{spec.title}（{exc}）"[:240],
                                6000,
                            )
                        except Exception:
                            logger.warning("application/experience_dispatch.py:dispatch_experience_action best-effort step failed", exc_info=True)
        else:
            # Leaving full-auto path: do not leave a stale token from prior run.
            # (Only clear if current token belongs to a different non-auto action.)
            try:
                from src.backend.experience.auto_apply import host_auto_apply_token

                existing = host_auto_apply_token(host)
                if existing is not None and existing.action_id == action:
                    bind_auto_apply_token(host, None)
            except Exception:
                logger.warning("application/experience_dispatch.py:dispatch_experience_action best-effort step failed", exc_info=True)
            _run()
    except Exception as exc:
        # Last-resort: run once without swallowing silently when auto setup failed.
        try:
            _run()
        except Exception as exc2:
            _record_auto_metric(host, "failed", action)
            try:
                host.statusBar().showMessage(
                    f"执行失败：{action}（{exc2 or exc}）"[:240], 6000
                )
            except Exception:
                logger.warning("application/experience_dispatch.py:dispatch_experience_action best-effort step failed", exc_info=True)
    finally:
        try:
            if getattr(host, "_dispatch_action_id", None) == action:
                host._dispatch_action_id = ""
        except Exception:
            logger.warning("application/experience_dispatch.py:dispatch_experience_action best-effort step failed", exc_info=True)
