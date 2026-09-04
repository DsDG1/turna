"""S-04 / S-12 pure helpers: scope target text + yellow quality hints.

No Qt, no network, no disk. Used by MainWindow for:

- S-04: low-confidence ⌘K write confirmation (human target + node_key)
- S-12: post-save yellow-quality proposal gate (non-blocking)

See ``experienceai.md`` §8.5 / §11 S-04 / S-12.
"""
from __future__ import annotations

from typing import Any, Mapping, Sequence

from src.backend.experience.conflict_guard import node_key
from src.backend.experience.context_bus import WEAK_SECTION_THRESHOLD
import logging
logger = logging.getLogger(__name__)


def infer_scope_node_key(
    scope: Mapping[str, Any] | None = None,
    selection: Any = None,
) -> str | None:
    """Best-effort ``kind:id`` for FocusRing / ConflictGuard from action scope.

    Priority: item → lesson → unit → section from *scope*, else selection.
    Returns None when nothing resolvable. Never raises.
    """
    try:
        scope = scope or {}
        pairs = (
            ("item_id", "item"),
            ("lesson_id", "lesson"),
            ("first_lesson_id", "lesson"),
            ("unit_id", "unit"),
            ("section_id", "section"),
        )
        for field, kind in pairs:
            raw = scope.get(field)
            if raw is None or raw == "":
                continue
            sid = str(raw).strip()
            if sid:
                return node_key(kind, sid)
        # selection: NodeRef or (kind, id)
        if selection is None:
            return None
        if hasattr(selection, "kind") and hasattr(selection, "id"):
            kind = str(getattr(selection, "kind") or "").strip()
            nid = str(getattr(selection, "id") or "").strip()
            if kind and nid:
                return node_key(kind, nid)
        if isinstance(selection, (tuple, list)) and len(selection) >= 2:
            kind = str(selection[0] or "").strip()
            nid = str(selection[1] or "").strip()
            if kind and nid:
                return node_key(kind, nid)
        return None
    except Exception:
        return None


def format_scope_target(
    action_id: str = "",
    scope: Mapping[str, Any] | None = None,
    selection: Any = None,
    *,
    fallback: str = "当前课程",
) -> str:
    """Human-readable target for S-04 scope confirmation.

    Prefers explicit scope ids, then selection, else *fallback*. Never raises.
    """
    try:
        scope = dict(scope or {})
        action_id = str(action_id or "").strip()

        # Prefer the most specific id present.
        for field, label in (
            ("item_id", "题"),
            ("lesson_id", "课"),
            ("first_lesson_id", "课"),
            ("unit_id", "单元"),
            ("section_id", "节"),
        ):
            raw = scope.get(field)
            if raw is None or raw == "":
                continue
            sid = str(raw).strip()
            if sid:
                extra = _scope_extras(scope, action_id)
                base = f"{label} {sid}"
                return f"{base}{extra}" if extra else base

        # Counts-only scopes (e.g. resource.fill_stubs with no section).
        if action_id == "resource.fill_stubs":
            ph = int(scope.get("placeholder_count") or 0)
            nr = int(scope.get("needs_review_count") or 0)
            bits = []
            if ph:
                bits.append(f"{ph} 待补")
            if nr:
                bits.append(f"{nr} needs-review")
            if bits:
                return "资源池（" + " / ".join(bits) + "）"

        if action_id == "validate.open_and_fix":
            n = scope.get("error_count")
            if n is not None and str(n) != "":
                return f"校验错误（{n}）"

        if action_id == "lesson.fill_empty":
            n = scope.get("empty_count")
            if n is not None and str(n) != "":
                return f"空课（{n}）"

        # Selection fallback
        if selection is not None:
            if hasattr(selection, "kind") and hasattr(selection, "id"):
                kind = str(getattr(selection, "kind") or "").strip()
                nid = str(getattr(selection, "id") or "").strip()
                label = str(getattr(selection, "label") or "").strip()
                if kind and nid:
                    if label:
                        return f"{kind} {nid}（{label}）"
                    return f"{kind} {nid}"
            if isinstance(selection, (tuple, list)) and len(selection) >= 2:
                kind = str(selection[0] or "").strip()
                nid = str(selection[1] or "").strip()
                if kind and nid:
                    return f"{kind} {nid}"

        return fallback or "当前课程"
    except Exception:
        return fallback or "当前课程"


def _scope_extras(scope: Mapping[str, Any], action_id: str) -> str:
    """Optional trailing detail for known actions."""
    try:
        if action_id == "quality.campaign_worst_n":
            mean = scope.get("mean")
            if mean is not None:
                try:
                    return f"（均分 {float(mean):.2f}）"
                except Exception:
                    logger.debug("backend/experience/scope_format.py:_scope_extras best-effort step failed", exc_info=True)
        if action_id == "listening.fill_gaps":
            n = scope.get("gap_count")
            if n is not None:
                return f"（{n} 处缺口）"
        if action_id == "lesson.fill_empty":
            n = scope.get("empty_count")
            if n is not None:
                return f"（共 {n} 空课）"
    except Exception:
        return ""
    return ""


def yellow_quality_summary(ctx: Any = None) -> dict[str, Any]:
    """Summarize non-blocking (yellow) quality issues after a successful save.

    Returns a dict::

        {
          "has_hints": bool,
          "parts": list[str],   # short Chinese fragments
          "message": str,      # status-bar line (empty when no hints)
          "warning_count": int,
          "empty_lesson_count": int,
          "weak_section_count": int,
          "placeholder_count": int,
          "needs_review_count": int,
        }

    Never raises. Does **not** treat structural validate errors as yellow
    (save already blocks those).
    """
    empty = {
        "has_hints": False,
        "parts": [],
        "message": "",
        "warning_count": 0,
        "empty_lesson_count": 0,
        "weak_section_count": 0,
        "placeholder_count": 0,
        "needs_review_count": 0,
    }
    try:
        if ctx is None:
            return empty

        def _get(name: str, default: Any = 0) -> Any:
            if isinstance(ctx, Mapping):
                return ctx.get(name, default)
            return getattr(ctx, name, default)

        warn = int(_get("validate_warning_count") or 0)
        empty_n = int(_get("empty_lesson_count") or 0)
        hygiene = _get("hygiene") or {}
        if not isinstance(hygiene, Mapping):
            hygiene = {}
        ph = int(hygiene.get("placeholder_count") or 0)
        nr = int(hygiene.get("needs_review_count") or 0)
        quality = _get("quality_by_section") or {}
        if not isinstance(quality, Mapping):
            quality = {}
        weak = 0
        for mean in quality.values():
            try:
                if mean is not None and float(mean) < WEAK_SECTION_THRESHOLD:
                    weak += 1
            except Exception:
                continue

        parts: list[str] = []
        if warn:
            parts.append(f"警告 {warn}")
        if empty_n:
            parts.append(f"空课 {empty_n}")
        if weak:
            parts.append(f"低质节 {weak}")
        if ph:
            parts.append(f"待补 {ph}")
        if nr:
            parts.append(f"审 {nr}")

        has = bool(parts)
        msg = ""
        if has:
            msg = "已保存 · 仍有可改善：" + " · ".join(parts)

        return {
            "has_hints": has,
            "parts": parts,
            "message": msg,
            "warning_count": warn,
            "empty_lesson_count": empty_n,
            "weak_section_count": weak,
            "placeholder_count": ph,
            "needs_review_count": nr,
        }
    except Exception:
        return empty


def has_yellow_quality_hints(ctx: Any = None) -> bool:
    """True when post-save yellow quality hints should surface. Never raises."""
    try:
        return bool(yellow_quality_summary(ctx).get("has_hints"))
    except Exception:
        return False
