"""P3 structure / balance / spiral / reading / POS suggestions."""
from __future__ import annotations
from typing import Any
import logging
logger = logging.getLogger(__name__)

def collect(ctx) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    if ctx.imbalanced_lessons:
        imb = list(ctx.imbalanced_lessons)
        first = imb[0]
        out.append(
            {
                "priority": 3,
                "title": f"调整 {len(imb)} 节课题型配比",
                "action_id": "lesson.balance",
                "scope": {
                    "lesson_id": str(first.get("lesson_id") or ""),
                    "section_id": str(first.get("section_id") or ""),
                    "count": len(imb),
                },
            }
        )
    if ctx.unsurfaced_words:
        uw = list(ctx.unsurfaced_words)
        first = uw[0]
        out.append(
            {
                "priority": 3,
                "title": f"为 {len(uw)} 个未复现词补充螺旋题",
                "action_id": "unit.spiral_vocab",
                "scope": {
                    "count": len(uw),
                    "section_id": str(first.get("section_id") or ""),
                    "word_ids": [str(w.get("word_id") or "") for w in uw[:20]],
                    "intro_lesson_ids": [
                        str(w.get("intro_lesson_id") or "") for w in uw[:20]
                    ],
                },
            }
        )
    if ctx.empty_reading_passages:
        rp = list(ctx.empty_reading_passages)
        first = rp[0]
        out.append(
            {
                "priority": 3,
                "title": f"为 {len(rp)} 节阅读课生成段落",
                "action_id": "reading.passages_gen",
                "scope": {
                    "count": len(rp),
                    "lesson_id": str(first.get("lesson_id") or ""),
                    "section_id": str(first.get("section_id") or ""),
                },
            }
        )
    if ctx.misaligned_pos_count:
        out.append(
            {
                "priority": 3,
                "title": f"对齐 {ctx.misaligned_pos_count} 个词条词性（POS）",
                "action_id": "resource.align_pos_tags",
                "scope": {"count": ctx.misaligned_pos_count},
            }
        )
    # v4.61 K-05: when tree focus is section/unit/lesson, offer AI edit.
    try:
        sel = getattr(ctx, "selection", None)
        kind = str(getattr(sel, "kind", "") or "")
        nid = str(getattr(sel, "id", "") or "")
        if kind in ("section", "unit", "lesson") and nid:
            labels = {"section": "节", "unit": "单元", "lesson": "课"}
            out.append(
                {
                    "priority": 3,
                    "title": f"AI 编辑当前{labels.get(kind, '节点')}",
                    "action_id": f"{kind}.edit",
                    "scope": {"kind": kind, "id": nid},
                }
            )
    except Exception:
        logger.debug("backend/experience/suggestions/p3_structure.py:collect best-effort step failed", exc_info=True)
    return out
