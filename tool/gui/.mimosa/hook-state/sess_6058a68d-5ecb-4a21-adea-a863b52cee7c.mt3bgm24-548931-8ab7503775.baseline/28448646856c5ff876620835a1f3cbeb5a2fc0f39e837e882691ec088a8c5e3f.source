"""E3-B2 sandbox lesson generation helpers (pure Python, no Qt).

Provides local stub content for empty lessons and payload validation so
Goal merge can apply :class:`LessonPatch` without inventing pedagogy in
the controller. AI generation still lives in ``ai_generator``; this module
only shapes / extracts / validates sandbox-safe lesson dicts.
"""
from __future__ import annotations

import copy
from typing import Any, Mapping


def build_stub_lesson(
    base: Mapping[str, Any] | None,
    *,
    lesson_id: str,
    word_id: str = "w_stub",
) -> dict[str, Any]:
    """Build a minimal filled lesson shell preserving *lesson_id*.

    Never raises. Forces ``id`` to *lesson_id*. Suitable for offline Goal
    merge demos and tests — not production pedagogy.
    """
    lid = str(lesson_id or "").strip() or "lesson"
    try:
        body = copy.deepcopy(dict(base or {}))
    except Exception:
        body = {}
    body["id"] = lid
    if not body.get("name"):
        body["name"] = f"Stub {lid}"
    if not body.get("template"):
        body["template"] = "intro"
    sub_id = f"{lid}-sub-stub"
    stage_id = f"{lid}-st-stub"
    item_id = f"{lid}-i-stub"
    body["content"] = {
        "subLessons": [
            {
                "id": sub_id,
                "stages": [
                    {
                        "id": stage_id,
                        "items": [
                            {
                                "id": item_id,
                                "runtimeType": "showWord",
                                "wordId": str(word_id or "w_stub"),
                            }
                        ],
                    }
                ],
            }
        ]
    }
    meta = dict(body.get("meta") or {}) if isinstance(body.get("meta"), dict) else {}
    meta["sandbox_stub_fill"] = True
    meta["sandbox_staged_fill"] = True
    body["meta"] = meta
    return body


def is_lesson_payload_mergeable(payload: Mapping[str, Any] | None) -> bool:
    """True when payload looks like a full lesson dict safe to LessonPatch."""
    if not payload or not isinstance(payload, Mapping):
        return False
    lid = str(payload.get("id") or "").strip()
    if not lid:
        return False
    content = payload.get("content")
    if not isinstance(content, Mapping):
        # flag-only placeholder from E3-A is NOT mergeable as full lesson
        if payload.get("sandbox_staged_fill") and len(payload) <= 3:
            return False
        return False
    subs = content.get("subLessons")
    if not isinstance(subs, list) or not subs:
        return False
    return True


def force_lesson_id(lesson: Mapping[str, Any], lesson_id: str) -> dict[str, Any]:
    """Deep-copy lesson and force top-level id. Never raises."""
    lid = str(lesson_id or "").strip()
    try:
        body = copy.deepcopy(dict(lesson))
    except Exception:
        body = {"id": lid}
    if lid:
        body["id"] = lid
    return body


def extract_lesson_from_section(
    section: Mapping[str, Any] | None,
    lesson_id: str,
) -> dict[str, Any] | None:
    """Find lesson dict in a section tree; return deep copy or None."""
    lid = str(lesson_id or "").strip()
    if not lid or not section:
        return None
    try:
        for unit in section.get("units") or []:
            if not isinstance(unit, Mapping):
                continue
            for les in unit.get("lessons") or []:
                if isinstance(les, Mapping) and str(les.get("id") or "") == lid:
                    return copy.deepcopy(dict(les))
    except Exception:
        return None
    return None


def payload_summary(payload: Mapping[str, Any] | None) -> str:
    """Short author-visible line for checklist."""
    if not is_lesson_payload_mergeable(payload):
        return "（待 skill 调度）"
    try:
        name = str(payload.get("name") or payload.get("id") or "")
        meta = payload.get("meta") if isinstance(payload.get("meta"), Mapping) else {}
        stub = bool(meta.get("sandbox_stub_fill"))
        content = payload.get("content") or {}
        n_sub = len(content.get("subLessons") or []) if isinstance(content, Mapping) else 0
        kind = "stub" if stub else "生成"
        return f"已预生成[{kind}] {name} · {n_sub} sub"
    except Exception:
        return "已预生成"
