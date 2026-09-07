"""P1/R4 intrusiveness ladder helpers (pure / host-light, never raises).

Centralizes normalize / immersive-enter confirm / demote-to-copilot.
"""
from __future__ import annotations

from typing import Any

from src.backend.experience.policy import (
    COPILOT,
    IMMERSIVE,
    normalize_experience_mode,
)
import logging
from src.application.experience_host import ExperienceHost
logger = logging.getLogger(__name__)

# Ctrl+Shift+D — Demote to copilot (documented in design + settings tooltip).
DEMOTE_SHORTCUT = "Ctrl+Shift+D"

IMMERSIVE_WARN_TITLE = "切换到 Immersive 全权自治？"
IMMERSIVE_WARN_TEXT = (
    "Immersive 是高风险授权档：\n"
    "· AI 可不提示、跳过确认自动改课（仍入 Undo）；运行时默认不透明。\n"
    "· 含 Active 捆绑（Soft/心跳/Defer/战役）。\n"
    "· 禁区：出站 publish / git.push 等仍拒绝。\n"
    "· 随时可用 Ctrl+Shift+D 一键降档回 Copilot。\n\n"
    "确定切换到 Immersive？"
)


def should_confirm_immersive_enter(old_mode: Any, new_mode: Any) -> bool:
    """True when applying a transition into immersive from a non-immersive mode."""
    old = normalize_experience_mode(old_mode)
    new = normalize_experience_mode(new_mode)
    return new == IMMERSIVE and old != IMMERSIVE


def demote_to_copilot(
    settings: Any,
    host: ExperienceHost = None,
) -> bool:
    """Set ``settings.experience_mode`` to copilot if needed.

    Returns True when the mode actually changed. Never raises.
    Does not persist or roll back the course tree.

    R2: invalidates auto-apply tokens.
    """
    try:
        from src.backend.experience.auto_apply import invalidate_auto_apply

        # Only invalidate when demote actually proceeds.
    except Exception:
        invalidate_auto_apply = None  # type: ignore[assignment]

    if settings is None:
        return False
    try:
        current = normalize_experience_mode(
            getattr(settings, "experience_mode", COPILOT)
        )
        if current == COPILOT:
            if invalidate_auto_apply is not None:
                try:
                    invalidate_auto_apply(host)
                except Exception:
                    logger.debug("application/presence_mode.py:demote_to_copilot best-effort step failed", exc_info=True)
            return False

        settings.experience_mode = COPILOT
        if invalidate_auto_apply is not None:
            try:
                invalidate_auto_apply(host)
            except Exception:
                logger.debug("application/presence_mode.py:demote_to_copilot best-effort step failed", exc_info=True)
        return True
    except Exception:
        return False


def campaign_items_for_host(host: ExperienceHost) -> list[dict[str, Any]]:
    """Build campaign targets from host Context; never raises."""
    try:
        from src.backend.quality_campaign import build_campaign_items

        exp = getattr(host, "experience", None)
        ctx = getattr(exp, "context", None) if exp is not None else None
        quality = dict(getattr(ctx, "quality_by_section", None) or {}) if ctx else {}
        empty = list(getattr(ctx, "empty_lessons", None) or []) if ctx else []
        adapter = getattr(host, "adapter", None)
        sections = getattr(adapter, "sections", None) or []
        return build_campaign_items(
            quality_by_section=quality,
            empty_lessons=empty,
            sections=sections,
            worst_n=3,
        )
    except Exception:
        return []


def maybe_auto_enqueue_campaign(host: ExperienceHost) -> bool:
    """P2: once per course session, surface quality campaign when active bundle.

    - Requires ``resolve_policy(...).allow_campaign_auto``.
    - Skips when no items or already offered for this ``course_dir``.
    - Headless/offscreen: no modal; marks offered + optional statusBar.
    - Interactive: opens existing ``handle_quality_campaign`` (writes still confirm).
    Never raises. Returns True when an offer was recorded this call.
    """
    if host is None:
        return False
    try:
        from src.backend.experience.policy import resolve_policy

        settings = getattr(host, "_settings_obj", None)
        policy = resolve_policy(settings)
        if not getattr(policy, "allow_campaign_auto", False):
            return False
        course_key = str(getattr(host, "course_dir", None) or "")
        if not course_key:
            return False
        if getattr(host, "_campaign_auto_offered_for", None) == course_key:
            return False
        items = campaign_items_for_host(host)
        if not items:
            return False
        # Mark before open so a crash/reject still won't spam re-open.
        host._campaign_auto_offered_for = course_key
        try:
            from src.application.ui_guard import is_headless_ui

            if is_headless_ui():
                try:
                    sb = getattr(host, "statusBar", None)
                    if callable(sb):
                        bar = sb()
                        if bar is not None and hasattr(bar, "showMessage"):
                            bar.showMessage(
                                f"Active 档：战役队列就绪（{len(items)} 项，Ctrl+K /战役）",
                                5000,
                            )
                except Exception:
                    logger.debug("application/presence_mode.py:maybe_auto_enqueue_campaign best-effort step failed", exc_info=True)
                try:
                    metrics = getattr(host, "experience_metrics", None)
                    if metrics is not None:
                        metrics.inc_ambient("shown")
                except Exception:
                    logger.debug("application/presence_mode.py:maybe_auto_enqueue_campaign best-effort step failed", exc_info=True)
                return True
        except Exception:
            logger.debug("application/presence_mode.py:maybe_auto_enqueue_campaign best-effort step failed", exc_info=True)
        try:
            from src.application.experience_handlers.quality import (
                handle_quality_campaign,
            )

            handle_quality_campaign(host, {})
        except Exception:
            logger.debug("application/presence_mode.py:maybe_auto_enqueue_campaign best-effort step failed", exc_info=True)
        return True
    except Exception:
        return False
