"""P2 attachment / OCR suggestions."""
from __future__ import annotations
from typing import Any, Mapping

def collect(ctx, *, ocr_enabled: bool = False) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    if ctx.attachments:
        atts = list(ctx.attachments)
        ref_ids = [
            str(a.get("ref_id") or "")
            for a in atts
            if isinstance(a, Mapping) and a.get("ref_id")
        ]
        out.append(
            {
                "priority": 2,
                "title": f"{len(atts)} 个附件可用于生成",
                "action_id": "attachment.open_in_workshop",
                "scope": {
                    "count": len(atts),
                    "ref_ids": ref_ids[:20],
                },
            }
        )
    if ocr_enabled and ctx.attachments:
        ocr_able = [
            a
            for a in ctx.attachments
            if isinstance(a, Mapping) and a.get("kind") == "image"
        ]
        if ocr_able:
            out.append(
                {
                    "priority": 2,
                    "title": f"OCR {len(ocr_able)} 个图片附件转文本",
                    "action_id": "textbook.ocr_suggest",
                    "scope": {"count": len(ocr_able)},
                }
            )
    return out
