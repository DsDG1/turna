"""P1 empty lesson suggestions."""
from __future__ import annotations
from typing import Any

def collect(ctx) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    if ctx.empty_lesson_count > 0:
        first = ctx.empty_lessons[0] if ctx.empty_lessons else ""
        out.append(
            {
                "priority": 1,
                "title": f"填充 {ctx.empty_lesson_count} 节空课",
                "action_id": "lesson.fill_empty",
                "scope": {
                    "empty_count": ctx.empty_lesson_count,
                    "first_lesson_id": first,
                    "lesson_ids": list(ctx.empty_lessons[:20]),
                },
            }
        )
    return out
