"""O-10 local save brief — post-save structural summary (no LLM).

Pure Python, no Qt / network. Optional AI brief stays behind a future
callback; this module only builds a local, author-visible status line that
aligns Soft / yellow / structural counters after a successful save.

Hard rule (experienceai §6): brief construction **never** blocks save.
"""
from __future__ import annotations

from typing import Any, Mapping


def build_local_save_brief(
    *,
    lesson_count: int = 0,
    empty_lesson_count: int = 0,
    validate_error_count: int = 0,
    validate_warning_count: int = 0,
    placeholder_count: int = 0,
    soft_count: int = 0,
    yellow_summary: str | None = None,
) -> str:
    """Compact Chinese status snippet after save. Never raises; may return \"\"."""
    try:
        parts: list[str] = []
        if lesson_count:
            parts.append(f"{int(lesson_count)} 课")
        if empty_lesson_count:
            parts.append(f"空课 {int(empty_lesson_count)}")
        if validate_error_count:
            parts.append(f"错 {int(validate_error_count)}")
        if validate_warning_count:
            parts.append(f"警 {int(validate_warning_count)}")
        if placeholder_count:
            parts.append(f"待补 {int(placeholder_count)}")
        if soft_count:
            parts.append(f"规范化 {int(soft_count)}")
        yellow = (yellow_summary or "").strip()
        # Avoid duplicating a long yellow string if we already have counters.
        if yellow and not parts:
            return yellow
        if not parts and not yellow:
            return "课程已保存"
        line = " · ".join(parts) if parts else ""
        if yellow and line and yellow not in line:
            return f"{line} · {yellow}"
        return line or yellow or "课程已保存"
    except Exception:
        return ""


def build_local_save_brief_from_context(
    ctx: Any | None,
    *,
    soft_count: int = 0,
    yellow_summary: str | None = None,
) -> str:
    """Pull counters from an ExperienceContext-like object. Never raises."""
    if ctx is None:
        return build_local_save_brief(
            soft_count=soft_count, yellow_summary=yellow_summary
        )
    try:
        hygiene = getattr(ctx, "hygiene", None) or {}
        if not isinstance(hygiene, Mapping):
            hygiene = {}
        return build_local_save_brief(
            lesson_count=int(getattr(ctx, "lesson_count", 0) or 0),
            empty_lesson_count=int(getattr(ctx, "empty_lesson_count", 0) or 0),
            validate_error_count=int(getattr(ctx, "validate_error_count", 0) or 0),
            validate_warning_count=int(getattr(ctx, "validate_warning_count", 0) or 0),
            placeholder_count=int(hygiene.get("placeholder_count") or 0),
            soft_count=soft_count,
            yellow_summary=yellow_summary,
        )
    except Exception:
        return build_local_save_brief(
            soft_count=soft_count, yellow_summary=yellow_summary
        )
