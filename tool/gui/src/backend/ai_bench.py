"""Offline quality probes for AI-generated course sections (aiEnhance Phase 0).

Pure functions, no Qt / network. Used by unit tests and optional bench scripts
to measure parse hygiene, placeholder density, and grounded coverage without
calling a live LLM.
"""
from __future__ import annotations

from typing import Any

from src.backend.grounded_stats import draft_coverage

PLACEHOLDER = "[待补]"
_NEEDS_REVIEW = "needs-review"
_AUTO_FIX = "auto-fix"


def _iter_resource_entries(section: dict[str, Any]) -> list[tuple[str, dict[str, Any]]]:
    out: list[tuple[str, dict[str, Any]]] = []
    for key in ("words", "expressions", "grammarPoints"):
        for entry in section.get(key) or []:
            if isinstance(entry, dict):
                out.append((key, entry))
    return out


def _iter_items(section: dict[str, Any]):
    for unit in section.get("units") or []:
        if not isinstance(unit, dict):
            continue
        for lesson in unit.get("lessons") or []:
            if not isinstance(lesson, dict):
                continue
            content = lesson.get("content") or {}
            for stage in content.get("stages") or []:
                if isinstance(stage, dict):
                    for item in stage.get("items") or []:
                        if isinstance(item, dict):
                            yield lesson, item
            for sub in content.get("subLessons") or []:
                if not isinstance(sub, dict):
                    continue
                for stage in sub.get("stages") or []:
                    if isinstance(stage, dict):
                        for item in stage.get("items") or []:
                            if isinstance(item, dict):
                                yield lesson, item
            for phase in content.get("listeningPhases") or []:
                if isinstance(phase, dict):
                    for item in phase.get("items") or []:
                        if isinstance(item, dict):
                            yield lesson, item


def count_placeholders(section: dict[str, Any]) -> int:
    """Count resource fields equal to the ``[待补]`` placeholder."""
    n = 0
    for _key, entry in _iter_resource_entries(section):
        for field in ("term", "translation", "title", "explanation"):
            if entry.get(field) == PLACEHOLDER:
                n += 1
    return n


def count_needs_review(section: dict[str, Any]) -> int:
    """Count resource entries tagged needs-review or auto-fix."""
    n = 0
    for _key, entry in _iter_resource_entries(section):
        tags = {str(t).lower() for t in (entry.get("tags") or [])}
        if _NEEDS_REVIEW in tags or _AUTO_FIX in tags:
            n += 1
    return n


def count_empty_translations(section: dict[str, Any]) -> int:
    n = 0
    for key, entry in _iter_resource_entries(section):
        if key == "grammarPoints":
            if not (entry.get("explanation") or "").strip():
                n += 1
        else:
            if not (entry.get("translation") or "").strip():
                n += 1
    return n


def find_dangling_refs(section: dict[str, Any]) -> list[str]:
    """Return human-readable dangling wordId/expressionId/grammarPointId refs."""
    word_ids = {
        w.get("id")
        for w in (section.get("words") or [])
        if isinstance(w, dict) and w.get("id")
    }
    expr_ids = {
        e.get("id")
        for e in (section.get("expressions") or [])
        if isinstance(e, dict) and e.get("id")
    }
    grammar_ids = {
        g.get("id")
        for g in (section.get("grammarPoints") or [])
        if isinstance(g, dict) and g.get("id")
    }
    missing: list[str] = []
    for lesson, item in _iter_items(section):
        lid = lesson.get("id", "?")
        rt = item.get("runtimeType")
        if rt == "showWord":
            wid = item.get("wordId")
            if wid and wid not in word_ids:
                missing.append(f"lesson {lid}: wordId「{wid}」")
        eid = item.get("expressionId")
        if eid and eid not in expr_ids:
            missing.append(f"lesson {lid}: expressionId「{eid}」")
        gid = item.get("grammarPointId")
        if gid and gid not in grammar_ids:
            missing.append(f"lesson {lid}: grammarPointId「{gid}」")
    return missing


def count_mcq_duplicate_options(section: dict[str, Any]) -> int:
    """Count MCQ-like items whose options list has duplicates."""
    n = 0
    for _lesson, item in _iter_items(section):
        options = item.get("options")
        if not isinstance(options, list) or len(options) < 2:
            continue
        normalized = [str(o).strip() for o in options]
        if len(normalized) != len(set(normalized)):
            n += 1
    return n


def score_section_hygiene(
    section: dict[str, Any] | None,
    *,
    resource_pool: list[dict[str, Any]] | None = None,
    structural_errors: list[Any] | None = None,
) -> dict[str, Any]:
    """Aggregate hygiene metrics for a section draft.

    ``structural_errors`` is an optional list from a validator (Problem dicts
    or strings). Only error-level dicts count toward ``error_count``.
    """
    if not isinstance(section, dict):
        return {
            "ok": False,
            "has_units": False,
            "error_count": 1,
            "placeholder_count": 0,
            "needs_review_count": 0,
            "empty_translation_count": 0,
            "dangling_ref_count": 0,
            "mcq_dup_options": 0,
            "unit_count": 0,
            "lesson_count": 0,
            "word_count": 0,
            "coverage_ratio": 0.0,
            "in_pool": 0,
            "outside_pool": 0,
        }

    errors = 0
    for item in structural_errors or []:
        if isinstance(item, dict):
            level = item.get("level", "error")
            if level and level != "error":
                continue
            errors += 1
        elif item:
            errors += 1

    dangling = find_dangling_refs(section)
    units = [u for u in (section.get("units") or []) if isinstance(u, dict)]
    lessons = 0
    for u in units:
        lessons += sum(1 for l in (u.get("lessons") or []) if isinstance(l, dict))

    cov = draft_coverage(section, resource_pool)
    placeholder_count = count_placeholders(section)
    needs_review_count = count_needs_review(section)
    empty_translation_count = count_empty_translations(section)
    dangling_ref_count = len(dangling)

    return {
        "ok": bool(section.get("units") is not None) and errors == 0 and dangling_ref_count == 0,
        "has_units": "units" in section,
        "error_count": errors,
        "placeholder_count": placeholder_count,
        "needs_review_count": needs_review_count,
        "empty_translation_count": empty_translation_count,
        "dangling_ref_count": dangling_ref_count,
        "dangling_refs": dangling[:20],
        "mcq_dup_options": count_mcq_duplicate_options(section),
        "unit_count": len(units),
        "lesson_count": lessons,
        "word_count": len([w for w in (section.get("words") or []) if isinstance(w, dict)]),
        "coverage_ratio": float(cov.get("coverage_ratio") or 0.0),
        "in_pool": int(cov.get("in_pool") or 0),
        "outside_pool": int(cov.get("outside_pool") or 0),
    }


def format_hygiene_line(metrics: dict[str, Any]) -> str:
    """One-line summary for logs / status bar."""
    parts = [
        f"errors={metrics.get('error_count', 0)}",
        f"待补={metrics.get('placeholder_count', 0)}",
        f"needs-review={metrics.get('needs_review_count', 0)}",
        f"dangling={metrics.get('dangling_ref_count', 0)}",
        f"lessons={metrics.get('lesson_count', 0)}",
    ]
    if metrics.get("coverage_ratio"):
        parts.append(f"pool={int(round(float(metrics['coverage_ratio']) * 100))}%")
    return " · ".join(parts)
