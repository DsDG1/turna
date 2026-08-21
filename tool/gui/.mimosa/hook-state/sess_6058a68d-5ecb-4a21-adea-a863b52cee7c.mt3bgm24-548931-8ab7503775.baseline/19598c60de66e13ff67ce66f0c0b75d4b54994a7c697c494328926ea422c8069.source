"""K-03: local section-vs-section compare (difficulty / term overlap).

Pure Python, no Qt / network. Read-only metrics for authors choosing two
sections — never mutates the course tree.
"""
from __future__ import annotations

from collections import Counter
from dataclasses import dataclass, field
from typing import Any, Mapping, Sequence


@dataclass(frozen=True)
class SectionSnapshot:
    """Local stats for one section."""

    section_id: str
    name: str = ""
    level: str = ""
    lesson_count: int = 0
    empty_lesson_count: int = 0
    terms: frozenset[str] = field(default_factory=frozenset)
    runtime_types: Mapping[str, int] = field(default_factory=dict)

    @property
    def term_count(self) -> int:
        return len(self.terms)


@dataclass(frozen=True)
class SectionCompareResult:
    """Pairwise compare output (always returned; error set on failure)."""

    a: SectionSnapshot | None
    b: SectionSnapshot | None
    overlap_terms: frozenset[str] = field(default_factory=frozenset)
    only_a: frozenset[str] = field(default_factory=frozenset)
    only_b: frozenset[str] = field(default_factory=frozenset)
    overlap_ratio: float = 0.0
    error: str | None = None

    @property
    def ok(self) -> bool:
        return self.error is None and self.a is not None and self.b is not None


def compare_sections(
    adapter: Any,
    section_id_a: str,
    section_id_b: str,
) -> SectionCompareResult:
    """Compare two sections by id. Never raises; missing ids → error result."""
    id_a = str(section_id_a or "").strip()
    id_b = str(section_id_b or "").strip()
    if not id_a or not id_b:
        return SectionCompareResult(
            a=None, b=None, error="需要两个 section id"
        )
    if id_a == id_b:
        return SectionCompareResult(
            a=None, b=None, error="请选择两个不同的 section"
        )

    sec_a = _find_section(adapter, id_a)
    sec_b = _find_section(adapter, id_b)
    if sec_a is None and sec_b is None:
        return SectionCompareResult(
            a=None, b=None, error=f"未找到 section：{id_a}、{id_b}"
        )
    if sec_a is None:
        return SectionCompareResult(
            a=None, b=None, error=f"未找到 section：{id_a}"
        )
    if sec_b is None:
        return SectionCompareResult(
            a=None, b=None, error=f"未找到 section：{id_b}"
        )

    snap_a = snapshot_section(sec_a)
    snap_b = snapshot_section(sec_b)
    inter = snap_a.terms & snap_b.terms
    only_a = snap_a.terms - snap_b.terms
    only_b = snap_b.terms - snap_a.terms
    union = snap_a.terms | snap_b.terms
    ratio = (len(inter) / len(union)) if union else 0.0
    return SectionCompareResult(
        a=snap_a,
        b=snap_b,
        overlap_terms=frozenset(inter),
        only_a=frozenset(only_a),
        only_b=frozenset(only_b),
        overlap_ratio=round(ratio, 4),
        error=None,
    )


def snapshot_section(section: Mapping[str, Any]) -> SectionSnapshot:
    """Build a local snapshot from one section dict."""
    from src.backend.overview_stats import lesson_is_empty

    sid = str(section.get("id") or "")
    name = str(section.get("name") or section.get("title") or sid)
    level = str(section.get("level") or "")
    lessons = list(_iter_lessons(section))
    empty_n = sum(1 for les in lessons if lesson_is_empty(les))
    terms = _collect_terms(section, lessons)
    types = Counter()
    for les in lessons:
        for rt in _lesson_runtime_types(les):
            types[rt] += 1
    return SectionSnapshot(
        section_id=sid,
        name=name,
        level=level,
        lesson_count=len(lessons),
        empty_lesson_count=empty_n,
        terms=frozenset(terms),
        runtime_types=dict(sorted(types.items())),
    )


def format_compare_report(
    result: SectionCompareResult,
    *,
    sample_limit: int = 12,
) -> str:
    """Human-readable Chinese summary for dialogs / statusBar."""
    if not result.ok:
        return result.error or "对比失败"
    assert result.a is not None and result.b is not None
    a, b = result.a, result.b
    lines = [
        f"对比：{a.name}（{a.section_id}） vs {b.name}（{b.section_id}）",
        f"级别：{a.level or '—'}  vs  {b.level or '—'}",
        (
            f"课时：{a.lesson_count}（空 {a.empty_lesson_count}）"
            f"  vs  {b.lesson_count}（空 {b.empty_lesson_count}）"
        ),
        (
            f"词条：{a.term_count}  vs  {b.term_count}；"
            f"重叠 {len(result.overlap_terms)}（"
            f"Jaccard {result.overlap_ratio:.0%}）"
        ),
        f"仅 A：{len(result.only_a)}　仅 B：{len(result.only_b)}",
    ]
    if result.overlap_terms:
        sample = _sample_sorted(result.overlap_terms, sample_limit)
        lines.append(f"重叠样例：{', '.join(sample)}")
    if result.only_a:
        sample = _sample_sorted(result.only_a, sample_limit)
        lines.append(f"仅 A 样例：{', '.join(sample)}")
    if result.only_b:
        sample = _sample_sorted(result.only_b, sample_limit)
        lines.append(f"仅 B 样例：{', '.join(sample)}")
    if a.runtime_types or b.runtime_types:
        lines.append(
            f"题型 A：{_fmt_types(a.runtime_types)}　|　"
            f"B：{_fmt_types(b.runtime_types)}"
        )
    return "\n".join(lines)


def resolve_compare_pair(
    scope: Mapping[str, Any] | None = None,
    *,
    selection: Any = None,
    multi_selection: Sequence[Any] | None = None,
    pinned_refs: Sequence[Any] | None = None,
) -> tuple[str, str] | None:
    """Resolve two section ids for compare (priority order).

    1. ``scope.section_ids`` (≥2)
    2. multi_selection kind=section (≥2)
    3. selection section + different pin section
    4. scope.section_id_a / section_id_b
    """
    scope = dict(scope or {})
    raw_list = scope.get("section_ids")
    if isinstance(raw_list, (list, tuple)):
        ids = [str(x).strip() for x in raw_list if str(x).strip()]
        if len(ids) >= 2 and ids[0] != ids[1]:
            return ids[0], ids[1]

    a = str(scope.get("section_id_a") or scope.get("id_a") or "").strip()
    b = str(scope.get("section_id_b") or scope.get("id_b") or "").strip()
    if a and b and a != b:
        return a, b

    multi_ids = _section_ids_from_refs(multi_selection)
    if len(multi_ids) >= 2 and multi_ids[0] != multi_ids[1]:
        return multi_ids[0], multi_ids[1]

    sel_id = _section_id_from_ref(selection)
    pin_ids = _section_ids_from_refs(pinned_refs)
    for pid in pin_ids:
        if sel_id and pid and pid != sel_id:
            return sel_id, pid
    return None


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------


def _find_section(adapter: Any, section_id: str) -> dict[str, Any] | None:
    sections = getattr(adapter, "sections", None) or []
    for sec in sections:
        if isinstance(sec, dict) and str(sec.get("id") or "") == section_id:
            return sec
    return None


def _iter_lessons(section: Mapping[str, Any]) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for unit in section.get("units") or []:
        if not isinstance(unit, dict):
            continue
        for lesson in unit.get("lessons") or []:
            if isinstance(lesson, dict):
                out.append(lesson)
    return out


def _collect_terms(
    section: Mapping[str, Any], lessons: Sequence[Mapping[str, Any]]
) -> set[str]:
    terms: set[str] = set()
    for w in section.get("words") or []:
        if not isinstance(w, dict):
            continue
        t = _norm_term(w.get("term") or w.get("word") or w.get("id"))
        if t:
            terms.add(t)
    for expr in section.get("expressions") or []:
        if not isinstance(expr, dict):
            continue
        t = _norm_term(expr.get("expression") or expr.get("term") or expr.get("id"))
        if t:
            terms.add(t)
    for lesson in lessons:
        content = lesson.get("content") or {}
        if not isinstance(content, dict):
            continue
        for item in _iter_items(content):
            rt = str(item.get("runtimeType") or "")
            if rt in ("showWord", "typeTheWord", "listenAndPick"):
                t = _norm_term(
                    item.get("word")
                    or item.get("term")
                    or item.get("target")
                    or item.get("prompt")
                )
                if t:
                    terms.add(t)
            # wordId-style refs: keep id string as weak term signal
            for key in ("wordId", "vocabId", "expressionId"):
                wid = item.get(key)
                if wid:
                    terms.add(f"id:{wid}")
    return terms


def _iter_items(content: Mapping[str, Any]) -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []
    for stage in content.get("stages") or []:
        if isinstance(stage, dict):
            for item in stage.get("items") or []:
                if isinstance(item, dict):
                    items.append(item)
    for sub in content.get("subLessons") or []:
        if not isinstance(sub, dict):
            continue
        for stage in sub.get("stages") or []:
            if isinstance(stage, dict):
                for item in stage.get("items") or []:
                    if isinstance(item, dict):
                        items.append(item)
    for phase in content.get("listeningPhases") or []:
        if not isinstance(phase, dict):
            continue
        for item in phase.get("items") or []:
            if isinstance(item, dict):
                items.append(item)
    return items


def _lesson_runtime_types(lesson: Mapping[str, Any]) -> list[str]:
    try:
        from src.backend.content_quality import _lesson_runtime_types as _lrt

        return list(_lrt(dict(lesson)))
    except Exception:
        content = lesson.get("content") or {}
        if not isinstance(content, dict):
            return []
        return [
            str(i.get("runtimeType"))
            for i in _iter_items(content)
            if i.get("runtimeType")
        ]


def _norm_term(value: Any) -> str:
    s = str(value or "").strip().lower()
    return s


def _sample_sorted(terms: frozenset[str] | set[str], limit: int) -> list[str]:
    return sorted(terms)[: max(0, int(limit))]


def _fmt_types(types: Mapping[str, int]) -> str:
    if not types:
        return "—"
    parts = [f"{k}×{v}" for k, v in sorted(types.items(), key=lambda kv: (-kv[1], kv[0]))]
    return ", ".join(parts[:8])


def _section_id_from_ref(ref: Any) -> str | None:
    if ref is None:
        return None
    kind = getattr(ref, "kind", None)
    rid = getattr(ref, "id", None)
    if kind is None and isinstance(ref, (tuple, list)) and len(ref) >= 2:
        kind, rid = ref[0], ref[1]
    if str(kind or "") == "section" and rid:
        return str(rid)
    return None


def _section_ids_from_refs(refs: Sequence[Any] | None) -> list[str]:
    out: list[str] = []
    seen: set[str] = set()
    for ref in refs or []:
        sid = _section_id_from_ref(ref)
        if sid and sid not in seen:
            seen.add(sid)
            out.append(sid)
    return out
