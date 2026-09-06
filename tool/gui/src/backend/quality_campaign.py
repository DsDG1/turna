"""Quality campaign target ranking (E2.0 / K-16), Qt-free.

Extracted from ``src/dialogs/quality_campaign_dialog.py`` so the application
layer can rank campaign targets without importing a dialogs UI module.
"""
from __future__ import annotations

from typing import Any


def build_campaign_items(
    *,
    quality_by_section: dict[str, float] | None = None,
    empty_lessons: list[str] | None = None,
    sections: list[dict[str, Any]] | None = None,
    worst_n: int = 3,
    quality_threshold: float = 0.7,
) -> list[dict[str, Any]]:
    """Pure helper: rank campaign targets (no Qt).

    Each item: {kind, id, title, score?, reason}
    """
    items: list[dict[str, Any]] = []
    empty_set = set(empty_lessons or [])

    # Empty lessons first (actionable fill).
    for lid in list(empty_lessons or [])[: max(worst_n * 2, 1)]:
        items.append(
            {
                "kind": "lesson",
                "id": lid,
                "title": f"空课 {lid}",
                "reason": "empty",
                "score": 0.0,
            }
        )

    weak = [
        (sid, float(mean))
        for sid, mean in (quality_by_section or {}).items()
        if mean is not None and float(mean) < quality_threshold
    ]
    weak.sort(key=lambda x: x[1])
    for sid, mean in weak[:worst_n]:
        name = sid
        for sec in sections or []:
            if isinstance(sec, dict) and sec.get("id") == sid:
                name = str(sec.get("name") or sid)
                break
        items.append(
            {
                "kind": "section",
                "id": sid,
                "title": f"低质节 {name}（{mean:.2f}）",
                "reason": "low_quality",
                "score": mean,
            }
        )

    # Dedupe by kind+id, keep order, cap.
    seen: set[tuple[str, str]] = set()
    out: list[dict[str, Any]] = []
    for it in items:
        key = (it["kind"], it["id"])
        if key in seen:
            continue
        seen.add(key)
        out.append(it)
        if len(out) >= worst_n + len(empty_set):
            # Prefer worst_n + empties but hard-cap 12.
            if len(out) >= 12:
                break
    return out[:12]
