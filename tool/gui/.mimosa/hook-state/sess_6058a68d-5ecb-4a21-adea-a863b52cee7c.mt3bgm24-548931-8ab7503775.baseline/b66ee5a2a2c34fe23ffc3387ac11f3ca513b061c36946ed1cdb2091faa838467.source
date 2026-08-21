"""Pure helpers for grounded design pool focus and draft coverage (workshop P3).

No Qt dependency — unit-testable without QApplication.
"""
from __future__ import annotations

from typing import Any


def count_pool_kinds(entries: list[dict[str, Any]] | None) -> dict[str, int]:
    """Count word / expression / grammar entries in a resource pool list.

    Accepts either controller pool shape (``_kind`` field) or raw project
    pool entries without ``_kind`` (falls back to key presence).
    """
    words = exprs = grammar = 0
    for e in entries or []:
        if not isinstance(e, dict):
            continue
        kind = e.get("_kind") or e.get("resource_type") or ""
        if kind in ("word", "words"):
            words += 1
        elif kind in ("expression", "expressions"):
            exprs += 1
        elif kind in ("grammar", "grammarPoint", "grammarPoints"):
            grammar += 1
        elif e.get("term") is not None and "title" not in e:
            words += 1
        elif e.get("title"):
            grammar += 1
        else:
            words += 1
    return {"words": words, "expressions": exprs, "grammar": grammar}


def format_pool_summary(
    entries: list[dict[str, Any]] | None,
    *,
    focused: bool = False,
) -> str:
    """Human-readable summary for the AI orbit focus strip."""
    c = count_pool_kinds(entries)
    total = c["words"] + c["expressions"] + c["grammar"]
    if total == 0:
        return "资源池为空 — 自由生成（不强制从池中选词）"
    prefix = "聚焦" if focused else "将使用资源池"
    return (
        f"{prefix}：{c['words']} 词 · {c['expressions']} 表达 · "
        f"{c['grammar']} 语法点"
    )


def _entry_ids(entries: list[dict[str, Any]] | None) -> set[str]:
    ids: set[str] = set()
    for e in entries or []:
        if isinstance(e, dict) and e.get("id"):
            ids.add(str(e["id"]))
    return ids


def _has_new_tag(entry: dict[str, Any]) -> bool:
    tags = entry.get("tags") or []
    return any(str(t).lower() == "new" for t in tags)


def draft_coverage(
    draft: dict[str, Any] | None,
    pool_entries: list[dict[str, Any]] | None,
) -> dict[str, Any]:
    """Compare draft top-level resources against a grounded pool.

    Returns counts used by the review / orbit UI:
    - ``pool_size``: unique pool ids
    - ``draft_words`` / ``draft_expressions`` / ``draft_grammar``
    - ``in_pool``: draft entries whose id is in the pool
    - ``outside_pool``: draft entries not in the pool
    - ``new_tagged``: outside entries carrying a ``new`` tag
    - ``coverage_ratio``: in_pool / draft_total (0 when empty draft)
    """
    pool_ids = _entry_ids(pool_entries)
    if not isinstance(draft, dict):
        return {
            "pool_size": len(pool_ids),
            "draft_words": 0,
            "draft_expressions": 0,
            "draft_grammar": 0,
            "in_pool": 0,
            "outside_pool": 0,
            "new_tagged": 0,
            "coverage_ratio": 0.0,
        }

    buckets = (
        ("words", draft.get("words") or []),
        ("expressions", draft.get("expressions") or []),
        ("grammar", draft.get("grammarPoints") or []),
    )
    draft_words = draft_exprs = draft_grammar = 0
    in_pool = outside = new_tagged = 0
    for name, items in buckets:
        for e in items:
            if not isinstance(e, dict):
                continue
            if name == "words":
                draft_words += 1
            elif name == "expressions":
                draft_exprs += 1
            else:
                draft_grammar += 1
            eid = str(e.get("id") or "")
            if eid and eid in pool_ids:
                in_pool += 1
            else:
                outside += 1
                if _has_new_tag(e):
                    new_tagged += 1

    total = draft_words + draft_exprs + draft_grammar
    ratio = (in_pool / total) if total else 0.0
    return {
        "pool_size": len(pool_ids),
        "draft_words": draft_words,
        "draft_expressions": draft_exprs,
        "draft_grammar": draft_grammar,
        "in_pool": in_pool,
        "outside_pool": outside,
        "new_tagged": new_tagged,
        "coverage_ratio": ratio,
    }


def format_coverage_line(stats: dict[str, Any]) -> str:
    """One-line coverage summary for the review panel."""
    total = (
        int(stats.get("draft_words", 0))
        + int(stats.get("draft_expressions", 0))
        + int(stats.get("draft_grammar", 0))
    )
    if total == 0:
        return ""
    pool_size = int(stats.get("pool_size", 0))
    if pool_size == 0:
        return f"草稿资源 {total} 项（自由生成，无资源池约束）"
    in_pool = int(stats.get("in_pool", 0))
    outside = int(stats.get("outside_pool", 0))
    new_tagged = int(stats.get("new_tagged", 0))
    pct = int(round(float(stats.get("coverage_ratio", 0.0)) * 100))
    line = f"池内命中 {in_pool}/{total}（{pct}%）"
    if outside:
        line += f" · 池外 {outside}"
        if new_tagged:
            line += f"（含 new 标记 {new_tagged}）"
    return line
