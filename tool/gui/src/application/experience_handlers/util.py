"""Shared pure helpers for experience handlers (M7)."""
from __future__ import annotations

from typing import Any

def _validate_course_problems(course_dir) -> list[dict]:
    """Validate a course dir and normalize problems to plain dicts.

    Shared by on-open async diagnose and interactive validate-and-fix.
    Raises on validation failure — callers decide how to surface errors.
    """
    from src.backend import api

    result = api.validate_course_dir(course_dir)
    problems: list[dict] = []
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

def _find_stage_and_item(
    lesson: dict, item_id: str
) -> tuple[dict | None, dict | None]:
    """Locate the stage (or listeningPhase) holding ``item_id`` in lesson.

    Module-level helper (v4.39 K-13) so it is callable from both the mixin
    (``MainWindow`` subclass) and tests with a plain ``QWidget`` host. Returns
    ``(stage, item)`` where ``stage`` is the live dict whose ``items`` list
    contains the item (so ``ApplyItemPatchCommand`` mutates the adapter in
    place). Searches stages → subLesson stages → listeningPhases. Pure-ish
    (no IO); returns ``(None, None)`` if not found.
    """
    iid = str(item_id or "")
    if not iid or not isinstance(lesson, dict):
        return None, None
    content = lesson.get("content") or {}
    if not isinstance(content, dict):
        return None, None
    containers: list[dict] = []
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

