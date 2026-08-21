"""P2 surface-aware resource suggestions (V-02).

First surface-aware collector: fires only when ``ctx.surface == "resources"``
and the whole multi-selection is resource entries (vocab / expressions).
Scope stays closed-set (count + entry ids, no term/原文, §14.5.3).
"""
from __future__ import annotations

from typing import Any

_RESOURCE_KINDS = ("vocab", "expressions")
_MAX_SCOPE_IDS = 20


def _ref_kind_id(ref: Any) -> tuple[str, str]:
    kind = getattr(ref, "kind", None)
    rid = getattr(ref, "id", None)
    if kind is None and isinstance(ref, (tuple, list)) and len(ref) >= 2:
        kind, rid = ref[0], ref[1]
    return str(kind or ""), str(rid or "")


def collect(ctx: Any) -> list[dict[str, Any]]:
    try:
        if str(getattr(ctx, "surface", "tree") or "tree") != "resources":
            return []
        multi = list(getattr(ctx, "multi_selection", None) or [])
        if not multi:
            return []
        pairs: list[tuple[str, str]] = []
        for ref in multi:
            kind, rid = _ref_kind_id(ref)
            if kind not in _RESOURCE_KINDS or not rid:
                return []  # 非纯资源多选不出建议
            if (kind, rid) not in pairs:
                pairs.append((kind, rid))
        if not pairs:
            return []
        return [
            {
                "priority": 2,
                "title": f"批量润色 {len(pairs)} 个选中词条",
                "action_id": "resource.batch_polish",
                "scope": {
                    "count": len(pairs),
                    "entry_ids": [f"{k}:{i}" for k, i in pairs[:_MAX_SCOPE_IDS]],
                },
            }
        ]
    except Exception:
        return []
