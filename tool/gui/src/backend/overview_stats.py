"""Pure-Python course overview statistics (no Qt dependency).

Computes the data shown in :class:`CourseOverviewWindow`:
- structural counts (sections / units / lessons / empty lessons)
- per-template lesson distribution
- per-section interaction (runtimeType) composition
- resource pool totals (vocab / expressions / grammar)
- coverage ratios (which pool entries are actually referenced by lessons)
- validation error / warning counts

All functions are unit-testable without a QApplication. The rendering layer
(``src/widgets/course_overview.py``) consumes the :class:`OverviewStats`
dataclass and never touches the adapter directly during render.
"""
from __future__ import annotations

from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Iterable, Iterator

from src.backend.lesson_content import (
    INTERACTION_LABELS,
    PRIMARY_CONTENT_KEY,
)


def iter_lesson_interactions(lesson: dict[str, Any]) -> Iterator[dict[str, Any]]:
    """Yield every interaction item dict inside a lesson's content.

    Covers all content shapes: ``subLessons[].stages[].items[]``,
    ``stages[].items[]``, ``listeningPhases[].items[]``. Reading passages
    contribute their ``linkedWordIds`` / ``linkedExpressionIds`` via
    :func:`iter_lesson_refs` (not here).
    """
    content = lesson.get("content") or {}
    for sub in content.get("subLessons", []) or []:
        for stage in sub.get("stages", []) or []:
            yield from stage.get("items", []) or []
    for stage in content.get("stages", []) or []:
        yield from stage.get("items", []) or []
    for phase in content.get("listeningPhases", []) or []:
        yield from phase.get("items", []) or []


def iter_lesson_refs(lesson: dict[str, Any]) -> Iterator[tuple[str, str]]:
    """Yield ``(kind, id)`` resource references inside a lesson.

    ``kind`` is one of ``word`` / ``expression`` / ``grammar``. Sources:
    - interaction ``wordId`` / ``expressionId`` / ``grammarPointId``
    - reading passage ``linkedWordIds`` / ``linkedExpressionIds``
    - lesson content ``linkedGrammarPointIds`` (app SRS registration list)
    """
    for item in iter_lesson_interactions(lesson):
        for key, kind in (
            ("wordId", "word"),
            ("expressionId", "expression"),
            ("grammarPointId", "grammar"),
        ):
            ref = item.get(key)
            if ref:
                yield kind, str(ref)
    content = lesson.get("content") or {}
    for gid in content.get("linkedGrammarPointIds", []) or []:
        if gid:
            yield "grammar", str(gid)
    passage = content.get("readingPassage") or {}
    for wid in passage.get("linkedWordIds", []) or []:
        if wid:
            yield "word", str(wid)
    for eid in passage.get("linkedExpressionIds", []) or []:
        if eid:
            yield "expression", str(eid)


def lesson_is_empty(lesson: dict[str, Any]) -> bool:
    """Return True if the lesson's primary content key has no items.

    A lesson is "empty" when its template's primary content slot
    (``PRIMARY_CONTENT_KEY``) exists but holds zero elements, or is missing
    entirely. Used to flag placeholder lessons (e.g. Sections 2–8).
    """
    tmpl = lesson.get("template", "legacy")
    primary = PRIMARY_CONTENT_KEY.get(tmpl, "stages")
    content = lesson.get("content") or {}
    if primary == "readingPassage":
        passage = content.get("readingPassage") or {}
        # Empty passage = no paragraphs and no linked resources.
        return not passage.get("paragraphs") and not (
            passage.get("linkedWordIds") or passage.get("linkedExpressionIds")
        )
    slot = content.get(primary)
    return not slot  # None or empty list


@dataclass(frozen=True)
class SectionStats:
    """Per-section rollup shown in the section card header."""

    section_id: str
    name: str
    level: str
    unit_count: int
    lesson_count: int
    empty_lesson_count: int
    template_counts: Counter[str] = field(default_factory=Counter)
    interaction_counts: Counter[str] = field(default_factory=Counter)
    # U2-2: advisory content quality (None when not computed).
    quality_mean: float | None = None
    quality_badge: str | None = None


@dataclass(frozen=True)
class OverviewStats:
    """Top-level overview data rendered by CourseOverviewWindow."""

    section_count: int = 0
    unit_count: int = 0
    lesson_count: int = 0
    empty_lesson_count: int = 0
    template_counts: Counter[str] = field(default_factory=Counter)
    interaction_counts: Counter[str] = field(default_factory=Counter)
    vocab_total: int = 0
    expression_total: int = 0
    grammar_total: int = 0
    vocab_referenced: int = 0
    expression_referenced: int = 0
    grammar_referenced: int = 0
    validation_errors: int = 0
    validation_warnings: int = 0
    sections: list[SectionStats] = field(default_factory=list)

    @property
    def vocab_coverage_pct(self) -> float:
        return _pct(self.vocab_referenced, self.vocab_total)

    @property
    def expression_coverage_pct(self) -> float:
        return _pct(self.expression_referenced, self.expression_total)

    @property
    def grammar_coverage_pct(self) -> float:
        return _pct(self.grammar_referenced, self.grammar_total)


def _pct(numerator: int, denominator: int) -> float:
    return (numerator / denominator * 100.0) if denominator else 0.0


def compute_overview_stats(
    adapter: Any,
    course_dir: Path | None = None,
    include_validation: bool = True,
    include_quality: bool = True,
) -> OverviewStats:
    """Compute the full overview stats for an adapter.

    ``course_dir`` defaults to ``adapter.course_dir``. When
    ``include_validation`` is True (and ``course_dir`` is set), validation and
    lint problems are counted; this is the only potentially slow step (spawns
    the CLI). Rendering the window without validation first keeps it snappy.

    When ``include_quality`` is True, each section gets an advisory content
    quality mean/badge from ``content_quality.score_section`` (pure rules, no
    network). Empty sections stay low; failures are ignored per section.
    """
    sections = list(adapter.sections or [])
    section_stats: list[SectionStats] = []
    tmpl_total: Counter[str] = Counter()
    interaction_total: Counter[str] = Counter()
    unit_count = 0
    lesson_count = 0
    empty_lesson_count = 0

    referenced_words: set[str] = set()
    referenced_expressions: set[str] = set()
    referenced_grammar: set[str] = set()

    for section in sections:
        s_units = section.get("units", []) or []
        unit_count += len(s_units)
        s_lessons = 0
        s_empty = 0
        s_tmpl: Counter[str] = Counter()
        s_inter: Counter[str] = Counter()
        for unit in s_units:
            for lesson in unit.get("lessons", []) or []:
                s_lessons += 1
                tmpl = lesson.get("template", "legacy")
                s_tmpl[tmpl] += 1
                if lesson_is_empty(lesson):
                    s_empty += 1
                for item in iter_lesson_interactions(lesson):
                    rt = item.get("runtimeType") or ""
                    if rt:
                        s_inter[rt] += 1
                for kind, rid in iter_lesson_refs(lesson):
                    if kind == "word":
                        referenced_words.add(rid)
                    elif kind == "expression":
                        referenced_expressions.add(rid)
                    else:
                        referenced_grammar.add(rid)
        q_mean: float | None = None
        q_badge: str | None = None
        if include_quality:
            try:
                from src.backend.content_quality import score_section

                level = str(
                    section.get("level")
                    or getattr(adapter, "index", {}).get("level")
                    or "A1"
                )
                report = score_section(section, level=level)
                q_mean = report.mean
                q_badge = report.badge()
            except Exception:
                q_mean = None
                q_badge = None
        section_stats.append(
            SectionStats(
                section_id=str(section.get("id", "")),
                name=str(section.get("name", section.get("id", ""))),
                level=str(section.get("level", "")),
                unit_count=len(s_units),
                lesson_count=s_lessons,
                empty_lesson_count=s_empty,
                template_counts=s_tmpl,
                interaction_counts=s_inter,
                quality_mean=q_mean,
                quality_badge=q_badge,
            )
        )
        tmpl_total += s_tmpl
        interaction_total += s_inter
        lesson_count += s_lessons
        empty_lesson_count += s_empty

    vocab_total = len(adapter.vocab or [])
    expr_total = len(adapter.expressions or [])
    grammar_total = len(adapter.grammar_points or [])

    errors = warnings = 0
    if include_validation:
        dir_ = course_dir if course_dir is not None else getattr(adapter, "course_dir", None)
        if dir_ is not None:
            try:
                from src.backend import api

                result = api.validate_course_dir(Path(dir_))
                errors = result.error_count
                warnings = sum(
                    1 for p in api.lint_course_dir(Path(dir_)) if p.level == "warning"
                )
            except Exception:
                # Validation is best-effort in the overview; the publish
                # dialog is the authoritative source.
                errors = warnings = 0

    return OverviewStats(
        section_count=len(sections),
        unit_count=unit_count,
        lesson_count=lesson_count,
        empty_lesson_count=empty_lesson_count,
        template_counts=tmpl_total,
        interaction_counts=interaction_total,
        vocab_total=vocab_total,
        expression_total=expr_total,
        grammar_total=grammar_total,
        vocab_referenced=len(referenced_words),
        expression_referenced=len(referenced_expressions),
        grammar_referenced=len(referenced_grammar),
        validation_errors=errors,
        validation_warnings=warnings,
        sections=section_stats,
    )


def format_stats_line(stats: OverviewStats) -> str:
    """Multi-line stats summary for the overview header.

    Line 1: structural counts + empty + validation.
    Line 2: resource pool + coverage ratios.
    Line 3: template distribution.
    """
    line1 = (
        f"Sections: {stats.section_count}   ·   "
        f"Units: {stats.unit_count}   ·   "
        f"Lessons: {stats.lesson_count}"
    )
    if stats.empty_lesson_count:
        line1 += f"   ·   空课时: {stats.empty_lesson_count}"
    if stats.validation_errors or stats.validation_warnings:
        line1 += (
            f"   ·   校验: {stats.validation_errors} 错 / {stats.validation_warnings} 警"
        )

    line2 = (
        f"词汇: {stats.vocab_referenced}/{stats.vocab_total} "
        f"({stats.vocab_coverage_pct:.0f}%)   ·   "
        f"表达: {stats.expression_referenced}/{stats.expression_total} "
        f"({stats.expression_coverage_pct:.0f}%)   ·   "
        f"语法: {stats.grammar_referenced}/{stats.grammar_total} "
        f"({stats.grammar_coverage_pct:.0f}%)"
    )

    if stats.template_counts:
        from src.backend.lesson_content import TEMPLATE_LABELS

        line3 = "课型分布: " + "   ".join(
            f"{TEMPLATE_LABELS.get(t, t)} {n}"
            for t, n in stats.template_counts.most_common()
        )
    else:
        line3 = ""

    return "\n".join(part for part in (line1, line2, line3) if part)


def format_interaction_line(counts: Counter[str]) -> str:
    """Inline interaction composition for a section card header."""
    if not counts:
        return ""
    return "   ".join(
        f"{INTERACTION_LABELS.get(rt, rt)} {n}"
        for rt, n in counts.most_common()
    )


def filter_lessons(
    sections: Iterable[dict[str, Any]],
    *,
    text: str = "",
    template: str | None = None,
) -> list[tuple[dict[str, Any], dict[str, Any], dict[str, Any]]]:
    """Return ``(section, unit, lesson)`` triples matching the filters.

    ``text`` matches case-insensitively against lesson name or id.
    ``template`` matches the lesson's template exactly (None = all).
    """
    needle = (text or "").strip().lower()
    out: list[tuple[dict[str, Any], dict[str, Any], dict[str, Any]]] = []
    for section in sections:
        for unit in section.get("units", []) or []:
            for lesson in unit.get("lessons", []) or []:
                if template and lesson.get("template", "legacy") != template:
                    continue
                if needle:
                    name = str(lesson.get("name", "")).lower()
                    lid = str(lesson.get("id", "")).lower()
                    if needle not in name and needle not in lid:
                        continue
                out.append((section, unit, lesson))
    return out


def export_markdown(
    stats: OverviewStats,
    sections: Iterable[dict[str, Any]],
    *,
    text: str = "",
    template: str | None = None,
) -> str:
    """Render the (optionally filtered) overview as Markdown.

    Suitable for pasting into ADRs or ``docs/content_inventory_current.md``.
    """
    from src.backend.lesson_content import TEMPLATE_LABELS

    lines: list[str] = ["# 课程结构总览", ""]
    lines.append(format_stats_line(stats))
    lines.append("")
    if text or template:
        note = "（过滤后）"
        if text:
            note += f" 关键字：{text}"
        if template:
            note += f"  课型：{TEMPLATE_LABELS.get(template, template)}"
        lines.append(f"> {note}")
        lines.append("")

    triples = filter_lessons(sections, text=text, template=template)
    if not triples:
        lines.append("_(无匹配课时)_")
        return "\n".join(lines)

    # Group by section (preserve adapter order).
    by_section: dict[str, list[tuple[dict[str, Any], dict[str, Any], dict[str, Any]]]] = {}
    section_order: list[str] = []
    for s, u, l in triples:
        sid = str(s.get("id", ""))
        if sid not in by_section:
            by_section[sid] = []
            section_order.append(sid)
        by_section[sid].append((s, u, l))

    for sid in section_order:
        group = by_section[sid]
        section = group[0][0]
        title = section.get("name", sid)
        level = section.get("level", "")
        lines.append(f"## {title} ({level})" if level else f"## {title}")
        lines.append("")
        # Unit sub-headings inside the section.
        current_unit: str | None = None
        for s, u, l in group:
            uid = str(u.get("id", ""))
            if uid != current_unit:
                current_unit = uid
                lines.append(f"### {u.get('name', uid)}")
                lines.append("")
            tmpl = l.get("template", "legacy")
            label = TEMPLATE_LABELS.get(tmpl, tmpl)
            name = l.get("name", l.get("id", ""))
            empty = "  ·  _空_" if lesson_is_empty(l) else ""
            lines.append(f"- **{name}** · {label}{empty}")
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"
