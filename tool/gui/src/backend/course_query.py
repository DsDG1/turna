"""Pure query and extraction utilities for course tree and validation.

Standalone functions free of Qt, suitable for headless testing and domain queries.
"""
from __future__ import annotations

from pathlib import Path
from typing import Any


def validate_course_problems(course_dir: Path | str) -> list[dict[str, Any]]:
    """Validate a course dir and normalize problems to plain dicts.

    Shared by on-open async diagnose and interactive validate-and-fix.
    Raises on validation failure — callers decide how to surface errors.
    """
    from src.backend import api

    result = api.validate_course_dir(course_dir)
    problems: list[dict[str, Any]] = []
    raw = getattr(result, "problems", None)
    if raw is None:
        raw = getattr(result, "errors", None) or []
    for p in raw:
        if isinstance(p, dict):
            problems.append(p)
        else:
            problems.append(
                {
                    "level": getattr(p, "level", "error"),
                    "message": str(getattr(p, "message", p)),
                    "path": str(getattr(p, "path", "") or ""),
                }
            )
    return problems


def find_stage_and_item(
    lesson: dict[str, Any], item_id: str
) -> tuple[dict[str, Any] | None, dict[str, Any] | None]:
    """Locate the stage (or listeningPhase) holding ``item_id`` in lesson.

    Returns ``(stage, item)`` where ``stage`` is the live dict whose ``items``
    list contains the item (so commands mutate the adapter in place). Searches
    stages -> subLesson stages -> listeningPhases. Pure (no IO); returns
    ``(None, None)`` if not found.
    """
    iid = str(item_id or "")
    if not iid or not isinstance(lesson, dict):
        return None, None
    content = lesson.get("content") or {}
    if not isinstance(content, dict):
        return None, None
    containers: list[dict[str, Any]] = []
    for stage in content.get("stages") or []:
        if isinstance(stage, dict):
            containers.append(stage)
    for sub in content.get("subLessons") or []:
        if isinstance(sub, dict):
            for stage in sub.get("stages") or []:
                if isinstance(stage, dict):
                    containers.append(stage)
    for phase in content.get("listeningPhases") or []:
        if isinstance(phase, dict):
            containers.append(phase)
    for stage in containers:
        items = stage.get("items")
        if not isinstance(items, list):
            continue
        for it in items:
            if isinstance(it, dict) and str(it.get("id") or "") == iid:
                return stage, it
    return None, None
