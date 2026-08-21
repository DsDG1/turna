"""P2 listening gap suggestions."""
from __future__ import annotations
from typing import Any

def collect(ctx) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    if ctx.listening_gaps:
        gaps = list(ctx.listening_gaps)
        out.append(
            {
                "priority": 2,
                "title": f"补全 {len(gaps)} 处听力缺口",
                "action_id": "listening.fill_gaps",
                "scope": {
                    "gap_count": len(gaps),
                    "gaps": gaps[:20],
                    "section_id": str(gaps[0].get("section_id") or "") if gaps else "",
                },
            }
        )
    transcript_gaps = [
        g for g in (ctx.listening_gaps or []) if str(g.get("kind") or "") == "missing_transcript"
    ]
    if transcript_gaps:
        out.append(
            {
                "priority": 2,
                "title": f"补全 {len(transcript_gaps)} 处听力 transcript 缺口",
                "action_id": "listening.transcript_gap",
                "scope": {
                    "count": len(transcript_gaps),
                    "section_id": str(transcript_gaps[0].get("section_id") or ""),
                    "gaps": transcript_gaps[:20],
                },
            }
        )
    return out
