"""Immersive full-auto apply policy (P3/R2) — pure Python, no Qt, never raises.

Defines absolute deny set B and helpers for whether an action may skip
confirm under ``allow_full_auto_apply``. Does **not** write the course tree;
handlers still push Undo commands when they apply.

R2: :class:`AutoApplyToken` + generation counter so async handlers can still
auto-apply after the sync dispatch frame ends, and demote invalidates pending
tokens without relying solely on a ContextVar scope.
"""
from __future__ import annotations

from collections import deque
from dataclasses import dataclass
from threading import Lock
from time import time
from typing import Any, Deque, Mapping

from src.backend.experience.actions import DANGEROUS_ACTION_IDS, is_dangerous
import logging
logger = logging.getLogger(__name__)


# B — never auto, often never do (prefixes or exact ids)
IMMERSIVE_ABSOLUTE_DENY_ACTIONS: frozenset[str] = frozenset(
    {
        "publish.outbound",
        "publish.store",
        "git.push",
        "fs.delete_course_root",
        "secrets.write",
    }
)
IMMERSIVE_ABSOLUTE_DENY_PREFIXES: tuple[str, ...] = (
    "publish.outbound",
    "git.push",
    "fs.delete_",
    "secrets.",
)

# C — dangerous subset allowed to skip confirm under immersive full-auto.
# Closed set; a strict subset of ``DANGEROUS_ACTION_IDS``. dangerous actions
# NOT in C fall through to the confirm path (handler self-manages confirm)
# instead of auto-applying. ``course.outline_shells`` is dangerous but
# deliberately excluded — it creates new section/unit/lesson shells (largest
# structural blast radius) and always confirms, even under immersive.
AUTO_APPLY_DANGEROUS_WHEN_IMMERSIVE: frozenset[str] = frozenset(
    {
        "lesson.regenerate",
        "lesson.batch_regenerate",
        "unit.regenerate",
        "unit.batch_regenerate",
        "lesson.batch_set_template",
    }
)

AUDIT_RING_CAP = 50

# Module-wide generation: demote / mode change bumps it → all old tokens die.
_generation: int = 0
_generation_lock = Lock()


def get_auto_apply_generation() -> int:
    """Current auto-apply generation (monotonic). Never raises."""
    try:
        return int(_generation)
    except Exception:
        return 0


def bump_auto_apply_generation() -> int:
    """Invalidate all outstanding :class:`AutoApplyToken` instances.

    Call on demote-to-copilot and experience_mode changes that leave full-auto.
    Returns the new generation. Never raises.
    """
    global _generation
    try:
        with _generation_lock:
            _generation = int(_generation) + 1
            return int(_generation)
    except Exception:
        try:
            _generation = int(_generation or 0) + 1
            return int(_generation)
        except Exception:
            return 0


@dataclass(frozen=True)
class AutoApplyToken:
    """Capability token issued at dispatch for immersive full-auto.

    Survives the sync handler frame so async workers that later call
    ``PreviewHost.offer`` can still auto-apply iff ``still_valid()``.
    """

    generation: int
    action_id: str
    opaque: bool = True

    def still_valid(self) -> bool:
        """True when demote/mode change has not bumped generation."""
        try:
            return int(self.generation) == get_auto_apply_generation()
        except Exception:
            return False


def issue_auto_apply_token(
    action_id: str | None,
    *,
    opaque: bool = True,
) -> AutoApplyToken:
    """Mint a token bound to the current generation. Never raises."""
    try:
        return AutoApplyToken(
            generation=get_auto_apply_generation(),
            action_id=str(action_id or "")[:80],
            opaque=bool(opaque),
        )
    except Exception:
        return AutoApplyToken(generation=0, action_id="", opaque=True)


def bind_auto_apply_token(host: Any, token: AutoApplyToken | None) -> None:
    """Attach token to host for async PreviewHost lookup. Never raises."""
    if host is None:
        return
    try:
        host._auto_apply_token = token
    except Exception:
        logger.debug("backend/experience/auto_apply.py:bind_auto_apply_token best-effort step failed", exc_info=True)


def clear_auto_apply_token(host: Any) -> None:
    """Drop host token (e.g. after demote). Never raises."""
    bind_auto_apply_token(host, None)


def host_auto_apply_token(host: Any) -> AutoApplyToken | None:
    """Return host token if still valid; else None. Never raises."""
    if host is None:
        return None
    try:
        token = getattr(host, "_auto_apply_token", None)
        if token is None:
            return None
        if hasattr(token, "still_valid") and token.still_valid():
            return token  # type: ignore[return-value]
        return None
    except Exception:
        return None


def invalidate_auto_apply(host: Any = None) -> int:
    """Bump generation and clear host token. Returns new generation."""
    gen = bump_auto_apply_generation()
    if host is not None:
        clear_auto_apply_token(host)
    return gen


def is_denied_immersive(action_id: str | None) -> bool:
    """True when action is in absolute deny set B."""
    aid = str(action_id or "").strip()
    if not aid:
        return False
    if aid in IMMERSIVE_ABSOLUTE_DENY_ACTIONS:
        return True
    for p in IMMERSIVE_ABSOLUTE_DENY_PREFIXES:
        if aid == p or aid.startswith(p):
            return True
    return False


def is_in_set_c(action_id: str | None) -> bool:
    """True when action is in set C (dangerous-but-auto-allowed under immersive)."""
    return str(action_id or "").strip() in AUTO_APPLY_DANGEROUS_WHEN_IMMERSIVE


def is_auto_apply_allowed(action_id: str | None, policy: Any) -> bool:
    """True when immersive full-auto may skip confirm for this action.

    Observer / non-full-auto / deny-B → False. Never raises.
    Set C partitioning (v4.69): a dangerous action NOT in C → False (falls
    through to the confirm path); a dangerous action IN C → auto; a non-dangerous
    action → auto (unchanged). Non-dangerous is never blocked here — set C only
    refines which dangerous writes may auto-apply.
    """
    try:
        if policy is None:
            return False
        if getattr(policy, "is_observer", False):
            return False
        if not bool(getattr(policy, "allow_full_auto_apply", False)):
            return False
        if is_denied_immersive(action_id):
            return False
        if is_dangerous(action_id) and not is_in_set_c(action_id):
            return False
        return True
    except Exception:
        return False


@dataclass(frozen=True)
class AuditEntry:
    ts: float
    action_id: str
    count: int
    kind: str


def make_audit_ring() -> Deque[AuditEntry]:
    return deque(maxlen=AUDIT_RING_CAP)


def record_audit(
    ring: Deque[AuditEntry] | None,
    action_id: str,
    *,
    count: int = 1,
    kind: str = "auto",
) -> AuditEntry | None:
    """Append closed-set audit entry; never stores free text body."""
    if ring is None:
        return None
    try:
        entry = AuditEntry(
            ts=float(time()),
            action_id=str(action_id or "")[:80],
            count=max(0, int(count)),
            kind=str(kind or "auto")[:24],
        )
        ring.append(entry)
        return entry
    except Exception:
        return None


def ensure_audit_ring(host: Any) -> Deque[AuditEntry] | None:
    """Get or create host audit ring. Never raises."""
    if host is None:
        return None
    try:
        ring = getattr(host, "_immersive_audit_ring", None)
        if ring is None:
            ring = make_audit_ring()
            host._immersive_audit_ring = ring
        return ring
    except Exception:
        return None


def format_audit_lines(ring: Any, *, limit: int = 20) -> list[str]:
    """Human lines for optional audit drawer; closed-set only."""
    out: list[str] = []
    try:
        items = list(ring or [])[-max(1, int(limit)) :]
        for e in reversed(items):
            aid = getattr(e, "action_id", None) or (
                e.get("action_id") if isinstance(e, Mapping) else ""
            )
            cnt = getattr(e, "count", None)
            if cnt is None and isinstance(e, Mapping):
                cnt = e.get("count", 1)
            kind = getattr(e, "kind", None) or (
                e.get("kind") if isinstance(e, Mapping) else "auto"
            )
            out.append(f"{aid} ×{cnt} [{kind}]")
    except Exception:
        return []
    return out


def deny_and_auto_disjoint() -> bool:
    """G17': B ∩ C = ∅ and C ⊆ DANGEROUS_ACTION_IDS (real structural check)."""
    try:
        return (
            IMMERSIVE_ABSOLUTE_DENY_ACTIONS.isdisjoint(AUTO_APPLY_DANGEROUS_WHEN_IMMERSIVE)
            and AUTO_APPLY_DANGEROUS_WHEN_IMMERSIVE <= DANGEROUS_ACTION_IDS
        )
    except Exception:
        return False
