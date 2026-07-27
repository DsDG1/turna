"""Ambient / Dock local suggestions (M6).

Aggregates priority-ordered rule-based suggestion collectors. No LLM.
"""
from __future__ import annotations

from typing import TYPE_CHECKING, Any

from src.backend.experience.suggestions import p0_validate
from src.backend.experience.suggestions import p1_empty
from src.backend.experience.suggestions import p2_attachments
from src.backend.experience.suggestions import p2_hygiene
from src.backend.experience.suggestions import p2_listening
from src.backend.experience.suggestions import p2_resources
from src.backend.experience.suggestions import p2_textbook
from src.backend.experience.suggestions import p3_quality
from src.backend.experience.suggestions import p3_structure

if TYPE_CHECKING:
    from src.backend.experience.context_bus import ExperienceContext

WEAK_SECTION_THRESHOLD = 0.7


def local_suggestions(
    ctx: "ExperienceContext",
    *,
    limit: int = 3,
    soft_fix_count: int | None = None,
    ocr_enabled: bool = False,
) -> list[dict[str, Any]]:
    """Rule-based Ambient suggestions (P0–P3). No LLM.

    Priority aligns with ``experienceai.md`` §11.2. Returns at most ``limit``
    items shaped as ``{priority, title, action_id, scope?}``.
    """
    limit = max(0, int(limit))
    if limit == 0:
        return []

    out: list[dict[str, Any]] = []
    batches = [
        p0_validate.collect(ctx),
        p1_empty.collect(ctx),
        p2_hygiene.collect(ctx, soft_fix_count=soft_fix_count),
        p2_resources.collect(ctx),
        p2_listening.collect(ctx),
        p2_attachments.collect(ctx, ocr_enabled=ocr_enabled),
        p2_textbook.collect(ctx),
        p3_structure.collect(ctx),
        p3_quality.collect(ctx, weak_threshold=WEAK_SECTION_THRESHOLD),
    ]
    for batch in batches:
        for item in batch:
            if len(out) >= limit:
                break
            out.append(item)
        if len(out) >= limit:
            break

    out.sort(key=lambda s: int(s.get("priority", 99)))
    return out[:limit]
