"""P3 low quality section campaign suggestions."""
from __future__ import annotations
from typing import Any

def collect(ctx, *, weak_threshold: float = 0.7) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    if not ctx.quality_by_section:
        return out
    weak = [
        (sid, mean)
        for sid, mean in ctx.quality_by_section.items()
        if mean is not None and mean < weak_threshold
    ]
    weak.sort(key=lambda x: x[1])
    if weak:
        sid, mean = weak[0]
        out.append(
            {
                "priority": 3,
                "title": f"改善低质课 {sid}（{mean:.2f}）",
                "action_id": "quality.campaign_worst_n",
                "scope": {
                    "section_id": sid,
                    "mean": mean,
                    "weak_count": len(weak),
                },
            }
        )
    return out
