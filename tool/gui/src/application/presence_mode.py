"""P1/R4 intrusiveness ladder helpers (pure / host-light, never raises).

Centralizes normalize / immersive-enter confirm / demote-to-copilot /
sovereign multi-step enter / 300s demote cooldown.
"""
from __future__ import annotations

from time import time
from typing import Any

from src.backend.experience.policy import (
    COPILOT,
    IMMERSIVE,
    SOVEREIGN,
    normalize_experience_mode,
)
import logging
from src.application.experience_host import ExperienceHost
logger = logging.getLogger(__name__)

# Ctrl+Shift+D — Demote to copilot (documented in design + settings tooltip).
DEMOTE_SHORTCUT = "Ctrl+Shift+D"

# R4: after entering sovereign, demote is locked for this many seconds.
SOVEREIGN_DEMOTE_COOLDOWN_S = 300
# R4: sovereign enter requires this many Yes confirmations (headless: 1).
SOVEREIGN_ENTER_CONFIRM_STEPS = 2
SOVEREIGN_ENTER_STEP_GAP_S = 3.0

IMMERSIVE_WARN_TITLE = "切换到 Immersive 全权自治？"
IMMERSIVE_WARN_TEXT = (
    "Immersive 是高风险授权档：\n"
    "· AI 可不提示、跳过确认自动改课（仍入 Undo）；运行时默认不透明。\n"
    "· 含 Active 捆绑（Soft/心跳/Defer/战役）。\n"
    "· 禁区：出站 publish / git.push 等仍拒绝。\n"
    "· 随时可用 Ctrl+Shift+D 一键降档回 Copilot。\n\n"
    "确定切换到 Immersive？"
)

SOVEREIGN_WARN_TITLE = "切换到 Sovereign 强制共生模式？"
SOVEREIGN_WARN_TEXT = (
    "⚠️ Sovereign 是最高主权/高侵入模式：\n"
    "· AI 副光标跟随鼠标；job 时可锁定目标区输入。\n"
    "· 反悔抑制：手工 Undo AI 改动后，同类优化可能被再次施加（仍可再 Undo）。\n"
    "· 进入后 300 秒内禁止降档；降档不回滚已写树。\n"
    "· 禁区 B：出站 publish / git.push / 删课根仍拒绝。\n\n"
    "第 1/{steps} 步：确认移交控制权？"
).format(steps=SOVEREIGN_ENTER_CONFIRM_STEPS)

SOVEREIGN_WARN_TEXT_STEP2 = (
    "第 2/{steps} 步（最终确认）：\n"
    "· 你理解反悔抑制可能再次改树。\n"
    "· 你理解 300 秒内无法用 Ctrl+Shift+D 降档。\n"
    "· 绝对禁区（出站/密钥）仍不会静默执行。\n\n"
    "仍然切换到 Sovereign？"
).format(steps=SOVEREIGN_ENTER_CONFIRM_STEPS)


def should_confirm_immersive_enter(old_mode: Any, new_mode: Any) -> bool:
    """True when applying a transition into immersive from a non-immersive mode."""
    old = normalize_experience_mode(old_mode)
    new = normalize_experience_mode(new_mode)
    return new == IMMERSIVE and old != IMMERSIVE


def should_confirm_sovereign_enter(old_mode: Any, new_mode: Any) -> bool:
    """True when applying a transition into sovereign from a non-sovereign mode."""
    old = normalize_experience_mode(old_mode)
    new = normalize_experience_mode(new_mode)
    return new == SOVEREIGN and old != SOVEREIGN


def mark_sovereign_entered(host: ExperienceHost) -> None:
    """Record sovereign enter timestamp for demote cooldown. Never raises."""
    if host is None:
        return
    try:
        host._sovereign_entered_at = float(time())
    except Exception:
        logger.debug("application/presence_mode.py:mark_sovereign_entered best-effort step failed", exc_info=True)


def sovereign_demote_cooldown_remaining(host: ExperienceHost) -> float:
    """Seconds remaining before demote from sovereign is allowed (0 if free)."""
    if host is None:
        return 0.0
    try:
        mode = normalize_experience_mode(
            getattr(getattr(host, "_settings_obj", None), "experience_mode", COPILOT)
        )
        if mode != SOVEREIGN:
            return 0.0
        started = getattr(host, "_sovereign_entered_at", None)
        if started is None:
            return 0.0
        elapsed = float(time()) - float(started)
        rem = float(SOVEREIGN_DEMOTE_COOLDOWN_S) - elapsed
        return max(0.0, rem)
    except Exception:
        return 0.0


def demote_to_copilot(
    settings: Any,
    host: ExperienceHost = None,
    *,
    force: bool = False,
) -> bool:
    """Set ``settings.experience_mode`` to copilot if needed.

    Returns True when the mode actually changed. Never raises.
    Does not persist or roll back the course tree.

    R2: invalidates auto-apply tokens.
    R4: blocks demote while sovereign 300s cooldown active unless *force*.
    """
    try:
        from src.backend.experience.auto_apply import invalidate_auto_apply

        # Only invalidate when demote actually proceeds or force path.
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

        if current == SOVEREIGN and not force:
            rem = sovereign_demote_cooldown_remaining(host)
            if rem > 0:
                try:
                    if host is not None:
                        host._last_demote_blocked_s = rem
                        sb = getattr(host, "statusBar", None)
                        if callable(sb):
                            bar = sb()
                            if bar is not None and hasattr(bar, "showMessage"):
                                bar.showMessage(
                                    f"Sovereign 降档冷却中：还需 {int(rem)} 秒",
                                    4000,
                                )
                except Exception:
                    logger.debug("application/presence_mode.py:demote_to_copilot best-effort step failed", exc_info=True)
                return False

        settings.experience_mode = COPILOT
        if invalidate_auto_apply is not None:
            try:
                invalidate_auto_apply(host)
            except Exception:
                logger.debug("application/presence_mode.py:demote_to_copilot best-effort step failed", exc_info=True)
        try:
            if host is not None:
                host._sovereign_entered_at = None
        except Exception:
            logger.debug("application/presence_mode.py:demote_to_copilot best-effort step failed", exc_info=True)
        return True
    except Exception:
        return False


def confirm_sovereign_enter(parent: Any) -> bool:
    """Multi-step sovereign enter confirmation. Headless → single default_no.

    Returns True only when all steps accepted.
    """
    try:
        from src.application.ui_guard import is_headless_ui, safe_question

        if is_headless_ui():
            # Tests / CI: do not block forever; require explicit default path.
            return safe_question(
                parent,
                SOVEREIGN_WARN_TITLE,
                SOVEREIGN_WARN_TEXT,
                default_yes=False,
            )
        ok1 = safe_question(
            parent,
            SOVEREIGN_WARN_TITLE,
            SOVEREIGN_WARN_TEXT,
            default_yes=False,
        )
        if not ok1:
            return False
        # Brief gap (non-blocking if headless already returned).
        try:
            from time import sleep

            sleep(min(0.05, SOVEREIGN_ENTER_STEP_GAP_S))  # UI feels sequential; CI-fast
        except Exception:
            logger.debug("application/presence_mode.py:confirm_sovereign_enter best-effort step failed", exc_info=True)
        ok2 = safe_question(
            parent,
            SOVEREIGN_WARN_TITLE,
            SOVEREIGN_WARN_TEXT_STEP2,
            default_yes=False,
        )
        return bool(ok2)
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
