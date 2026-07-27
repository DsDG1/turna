"""P2 resource hygiene / soft / dedupe suggestions."""
from __future__ import annotations
from typing import Any

def collect(ctx, *, soft_fix_count: int | None = None) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    ph = int(ctx.hygiene.get("placeholder_count") or 0)
    nr = int(ctx.hygiene.get("needs_review_count") or 0)
    if ph > 0 or nr > 0:
        bits = []
        if ph:
            bits.append(f"{ph} 待补")
        if nr:
            bits.append(f"{nr} needs-review")
        out.append(
            {
                "priority": 2,
                "title": "清理资源：" + " / ".join(bits),
                "action_id": "resource.fill_stubs",
                "scope": {
                    "placeholder_count": ph,
                    "needs_review_count": nr,
                },
            }
        )
        out.append(
            {
                "priority": 2,
                "title": "打开资源 · 仅看待补",
                "action_id": "resource.open_hygiene",
                "scope": {
                    "placeholder_count": ph,
                    "needs_review_count": nr,
                    "filter": "待补",
                },
            }
        )
    try:
        soft_n = int(soft_fix_count) if soft_fix_count is not None else 0
    except Exception:
        soft_n = 0
    if soft_n > 0:
        out.append(
            {
                "priority": 2,
                "title": f"规则规范化 {soft_n} 项（可预览）",
                "action_id": "soft.preview_hygiene",
                "scope": {"soft_fix_count": soft_n},
            }
        )
    try:
        dup_n = int(ctx.hygiene.get("duplicate_count") or 0)
    except Exception:
        dup_n = 0
    if dup_n > 0:
        out.append(
            {
                "priority": 2,
                "title": f"查重：约 {dup_n} 组重复词条",
                "action_id": "resource.dedupe_suggest",
                "scope": {
                    "count": dup_n,
                    "filter": "重复",
                },
            }
        )
    # V-06: vocab↔expression term conflict (same term, different translation).
    try:
        conf_n = int(ctx.hygiene.get("conflict_count") or 0)
    except Exception:
        conf_n = 0
    if conf_n > 0:
        out.append(
            {
                "priority": 2,
                "title": f"统一 {conf_n} 处词条冲突",
                "action_id": "resource.resolve_term_conflicts",
                "scope": {"count": conf_n},
            }
        )
    return out
