"""Course-level health audit + repair worklist (P0-1, Qt-free).

Read-only: this module inspects an in-memory course and produces

- :class:`Finding` — one concrete, human-readable problem, and
- :class:`RepairStep` — a grouped item that maps back onto an existing
  Experience ``ACTIONS`` id.

It never writes to disk, never calls an LLM, and never imports Qt. Judgment
logic is reused from :mod:`src.backend.content_quality` and
:mod:`src.backend.overview_stats`; this module only aggregates it at course
scope and assigns an action.

The UI is expected to treat the result as a *worklist*: executing a step goes
through the normal dispatcher, so each action keeps its own preview / confirm /
undo path. Nothing here bypasses those guards.
"""
from __future__ import annotations

import logging
from collections.abc import Sequence
from dataclasses import dataclass, field
from typing import Any

from src.backend.content_quality import (
    evaluate_reading_passage,
    evaluate_unit_spiral,
    score_section,
)
from src.backend.overview_stats import iter_lesson_refs, lesson_is_empty

logger = logging.getLogger(__name__)

SEVERITY_ERROR = "error"
SEVERITY_WARNING = "warning"
SEVERITY_INFO = "info"

_SEVERITY_RANK = {SEVERITY_ERROR: 0, SEVERITY_WARNING: 1, SEVERITY_INFO: 2}

#: Data-shape failures tolerated by the audit. Deliberately *not* bare
#: ``Exception``: a malformed course row should not kill the scan, but a
#: programming error should surface instead of being silently swallowed.
_DATA_ERRORS = (AttributeError, IndexError, KeyError, TypeError, ValueError)

#: Action order inside the repair plan: structural gaps first, then listening,
#: then quality/style, then resource hygiene. Lower runs first.
_ACTION_RANK: dict[str, int] = {
    "lesson.fill_empty": 10,
    "reading.passages_gen": 20,
    "unit.spiral_vocab": 30,
    "listening.fill_gaps": 40,
    "listening.transcript_gap": 50,
    "section.edit": 60,
    "resource.resolve_term_conflicts": 70,
    "resource.dedupe_suggest": 80,
}

_KIND_LABELS: dict[str, str] = {
    "empty_lesson": "空课",
    "low_quality": "低质节",
    "spiral_gap": "螺旋缺口",
    "reading_empty": "阅读空段",
    "listening_audio_gap": "听力缺音频",
    "listening_transcript_gap": "听力缺文本",
    "listening_empty_phase": "听力空阶段",
    "grammar_uncovered": "语法未覆盖",
    "duplicate_term": "重复词条",
    "term_conflict": "词条冲突",
    "prereq_invalid": "前置依赖异常",
}


@dataclass(frozen=True)
class Finding:
    """One audit result.

    ``action_id`` empty means the problem needs human judgment and has no
    existing skill to dispatch (it still appears in the worklist for triage).
    """

    finding_id: str
    kind: str
    severity: str
    title: str
    detail: str = ""
    section_id: str = ""
    unit_id: str = ""
    lesson_id: str = ""
    action_id: str = ""
    scope: dict[str, Any] = field(default_factory=dict)
    estimated_calls: int = 0

    @property
    def kind_label(self) -> str:
        return _KIND_LABELS.get(self.kind, self.kind)

    def to_dict(self) -> dict[str, Any]:
        return {
            "finding_id": self.finding_id,
            "kind": self.kind,
            "kind_label": self.kind_label,
            "severity": self.severity,
            "title": self.title,
            "detail": self.detail,
            "section_id": self.section_id,
            "unit_id": self.unit_id,
            "lesson_id": self.lesson_id,
            "action_id": self.action_id,
            "scope": dict(self.scope),
            "estimated_calls": int(self.estimated_calls),
        }


@dataclass(frozen=True)
class RepairStep:
    """A grouped, dispatchable repair item (one existing action id)."""

    step_id: str
    action_id: str
    title: str
    scope: dict[str, Any] = field(default_factory=dict)
    finding_ids: tuple[str, ...] = ()
    needs_confirm: bool = True
    estimated_calls: int = 0

    def to_dict(self) -> dict[str, Any]:
        return {
            "step_id": self.step_id,
            "action_id": self.action_id,
            "title": self.title,
            "scope": dict(self.scope),
            "finding_ids": list(self.finding_ids),
            "needs_confirm": bool(self.needs_confirm),
            "estimated_calls": int(self.estimated_calls),
        }


def _finding(
    kind: str,
    severity: str,
    *,
    section_id: str = "",
    unit_id: str = "",
    lesson_id: str = "",
    title: str,
    detail: str = "",
    action_id: str = "",
    scope: dict[str, Any] | None = None,
    estimated_calls: int = 0,
) -> Finding:
    fid = f"{kind}:{section_id}:{unit_id}:{lesson_id}"
    return Finding(
        finding_id=fid,
        kind=kind,
        severity=severity,
        title=title,
        detail=detail,
        section_id=section_id,
        unit_id=unit_id,
        lesson_id=lesson_id,
        action_id=action_id,
        scope=dict(scope or {}),
        estimated_calls=int(estimated_calls),
    )


def _iter_lessons(section: dict[str, Any]):
    """Yield ``(unit, lesson)`` for every dict-shaped lesson in *section*."""
    for unit in section.get("units") or []:
        if not isinstance(unit, dict):
            continue
        for lesson in unit.get("lessons") or []:
            if isinstance(lesson, dict):
                yield unit, lesson


def _safe_refs(lesson: dict[str, Any]):
    """Yield lesson refs, tolerating malformed nested content shapes."""
    try:
        yield from iter_lesson_refs(lesson)
    except _DATA_ERRORS:
        return


def _term_preview(items: Sequence[dict[str, Any]], limit: int = 5) -> str:
    terms: list[str] = []
    for item in items[:limit]:
        if not isinstance(item, dict):
            continue
        term = str(item.get("term") or item.get("word_id") or "").strip()
        if term:
            terms.append(term)
    if not terms:
        return ""
    more = len(items) - len(terms)
    suffix = f" 等 {len(items)} 个" if more > 0 and len(items) > len(terms) else ""
    return "、".join(terms) + suffix


def _listening_groups(report: Any) -> dict[str, list[dict[str, Any]]]:
    """Group ``audio_ready`` issues by ``gap_kind`` for dispatchable scopes."""
    groups: dict[str, list[dict[str, Any]]] = {}
    for issue in getattr(report, "issues", None) or []:
        if str(getattr(issue, "dimension", "")) != "audio_ready":
            continue
        gap_kind = str(getattr(issue, "gap_kind", "") or "")
        item_id = getattr(issue, "item_id", None)
        if not gap_kind:
            gap_kind = "missing_audio" if item_id else "empty_phase"
        groups.setdefault(gap_kind, []).append(
            {
                "kind": gap_kind,
                "item_id": str(item_id or ""),
                "lesson_id": str(getattr(issue, "lesson_id", "") or ""),
                "message": str(getattr(issue, "message", "") or ""),
            }
        )
    return groups


def _audit_section(
    section: dict[str, Any],
    *,
    default_level: str,
    quality_threshold: float,
) -> list[Finding]:
    """Audit one section; never raises."""
    sid = str(section.get("id") or "")
    if not sid:
        return []
    out: list[Finding] = []
    lessons = list(_iter_lessons(section))
    empty_count = 0

    for unit, lesson in lessons:
        uid = str(unit.get("id") or "")
        lid = str(lesson.get("id") or "")
        if not lid:
            continue
        if lesson_is_empty(lesson):
            empty_count += 1
            out.append(
                _finding(
                    "empty_lesson",
                    SEVERITY_WARNING,
                    section_id=sid,
                    unit_id=uid,
                    lesson_id=lid,
                    title=f"空课：{lesson.get('name') or lid}",
                    detail="该课没有任何题目。可用「填充空课」生成草稿，确认后再应用。",
                    action_id="lesson.fill_empty",
                    scope={"lesson_id": lid, "section_id": sid},
                    estimated_calls=1,
                )
            )

    report = None
    try:
        level = str(section.get("level") or default_level or "A1")
        report = score_section(section, level=level)
    except _DATA_ERRORS:
        logger.debug("course_health: score_section failed for %s", sid, exc_info=True)

    mean: float | None = None
    if report is not None:
        mean = float(report.mean)

    if (
        mean is not None
        and lessons
        and empty_count < len(lessons)
        and mean < quality_threshold
    ):
        out.append(
            _finding(
                "low_quality",
                SEVERITY_WARNING,
                section_id=sid,
                title=f"节质量偏低：{section.get('name') or sid}（{mean:.2f}）",
                detail=(
                    "规则质量分低于阈值。可打开该节的 AI 编辑，按质量维度定向修；"
                    "质量分不阻断保存。"
                ),
                action_id="section.edit",
                scope={"kind": "section", "id": sid},
                estimated_calls=1,
            )
        )

    spiral = evaluate_unit_spiral(section)
    unsurfaced = list(spiral.get("unsurfaced") or [])
    if unsurfaced:
        preview = _term_preview(unsurfaced)
        out.append(
            _finding(
                "spiral_gap",
                SEVERITY_WARNING,
                section_id=sid,
                title=f"词汇螺旋缺口：{len(unsurfaced)} 个词引入后未复现",
                detail=(
                    f"{preview}。补课时会追加复现题，不改已有题。"
                    if preview
                    else "补课时会追加复现题，不改已有题。"
                ),
                action_id="unit.spiral_vocab",
                scope={"section_id": sid},
                estimated_calls=1,
            )
        )

    for _unit, lesson in lessons:
        lid = str(lesson.get("id") or "")
        if not lid or str(lesson.get("template") or "") != "reading":
            continue
        passage = evaluate_reading_passage(lesson)
        if passage.get("empty"):
            reason = str(passage.get("reason") or "阅读段落为空")
            out.append(
                _finding(
                    "reading_empty",
                    SEVERITY_WARNING,
                    section_id=sid,
                    lesson_id=lid,
                    title=f"阅读空段：{lesson.get('name') or lid}",
                    detail=f"{reason}。可生成阅读段落，预览确认后应用。",
                    action_id="reading.passages_gen",
                    scope={"lesson_id": lid, "section_id": sid},
                    estimated_calls=1,
                )
            )

    if report is not None:
        groups = _listening_groups(report)
        missing_audio = groups.get("missing_audio") or []
        if missing_audio:
            out.append(
                _finding(
                    "listening_audio_gap",
                    SEVERITY_WARNING,
                    section_id=sid,
                    title=f"听力缺口：{len(missing_audio)} 题缺音频与文本",
                    detail="可补全 audioAsset / transcript；生成走 diff 预览与确认。",
                    action_id="listening.fill_gaps",
                    scope={"section_id": sid, "gaps": missing_audio},
                    estimated_calls=1,
                )
            )
        missing_transcript = groups.get("missing_transcript") or []
        if missing_transcript:
            out.append(
                _finding(
                    "listening_transcript_gap",
                    SEVERITY_WARNING,
                    section_id=sid,
                    title=f"听力文本缺口：{len(missing_transcript)} 题缺 transcript",
                    detail="保留已有音频，只补 transcript；生成走 diff 预览与确认。",
                    action_id="listening.transcript_gap",
                    scope={"section_id": sid, "gaps": missing_transcript},
                    estimated_calls=1,
                )
            )
        empty_phases = groups.get("empty_phase") or []
        if empty_phases:
            out.append(
                _finding(
                    "listening_empty_phase",
                    SEVERITY_INFO,
                    section_id=sid,
                    title=f"听力空阶段：{len(empty_phases)} 个阶段没有题目",
                    detail="P0 只提示；可在教师模式或 AI 编辑中补题。",
                )
            )
    return out


def audit_course(
    sections: Sequence[dict[str, Any]],
    *,
    vocab: Sequence[dict[str, Any]] | None = None,
    expressions: Sequence[dict[str, Any]] | None = None,
    grammar_points: Sequence[dict[str, Any]] | None = None,
    default_level: str = "A1",
    quality_threshold: float = 0.7,
    duplicates: Sequence[dict[str, Any]] | None = None,
    term_conflicts: dict[str, Any] | None = None,
    max_findings: int = 400,
) -> list[Finding]:
    """Scan a whole course and return findings ordered for triage.

    The function is failure-safe: a malformed section is skipped, never raised.
    It performs no I/O and no network calls.
    """
    findings: list[Finding] = []
    clean_sections = [s for s in (sections or []) if isinstance(s, dict)]

    for section in clean_sections:
        try:
            findings.extend(
                _audit_section(
                    section,
                    default_level=default_level,
                    quality_threshold=quality_threshold,
                )
            )
        except _DATA_ERRORS:
            logger.debug(
                "course_health: section audit skipped for %s",
                section.get("id", "?"),
                exc_info=True,
            )

    # Grammar coverage is a course-level signal, not per-section. Both the
    # global resource pool and section-embedded grammar points count: a draft
    # section may carry its own list before the import merge.
    grammar_pool: dict[str, dict[str, Any]] = {}
    for entry in grammar_points or []:
        if isinstance(entry, dict) and entry.get("id"):
            grammar_pool.setdefault(str(entry["id"]), entry)
    for section in clean_sections:
        for entry in section.get("grammarPoints") or []:
            if isinstance(entry, dict) and entry.get("id"):
                grammar_pool.setdefault(str(entry["id"]), entry)
    referenced: set[str] = set()
    for section in clean_sections:
        for _unit, lesson in _iter_lessons(section):
            for kind, ref_id in _safe_refs(lesson):
                if kind == "grammar":
                    referenced.add(ref_id)
    uncovered = [
        entry for gid, entry in grammar_pool.items() if gid not in referenced
    ]
    if uncovered:
        names = [
            str(g.get("title") or g.get("name") or g.get("id") or "")
            for g in uncovered[:8]
        ]
        names = [n for n in names if n]
        findings.append(
            _finding(
                "grammar_uncovered",
                SEVERITY_INFO,
                title=f"语法点未覆盖：{len(uncovered)} 个没有任何课时引用",
                detail=(
                    "、".join(names) + ("…" if len(uncovered) > len(names) else "")
                    if names
                    else "可在课程规划或 AI 编辑中补课。"
                ),
            )
        )

    # Prerequisite sanity (missing / self / cross-section).
    lesson_section: dict[str, str] = {}
    lessons_by_id: dict[str, dict[str, Any]] = {}
    for section in clean_sections:
        sid = str(section.get("id") or "")
        for _unit, lesson in _iter_lessons(section):
            lid = str(lesson.get("id") or "")
            if lid:
                lesson_section[lid] = sid
                lessons_by_id[lid] = lesson
    for lid, lesson in lessons_by_id.items():
        raw = lesson.get("prerequisiteLessonIds") or []
        if not isinstance(raw, list):
            continue
        bad = sorted(
            {
                str(p)
                for p in raw
                if str(p) == lid or str(p) not in lesson_section
            }
        )
        cross = sorted(
            {
                str(p)
                for p in raw
                if str(p) in lesson_section
                and lesson_section[str(p)] != lesson_section[lid]
            }
        )
        if bad or cross:
            parts = []
            if bad:
                parts.append("指向不存在或自身：" + "、".join(bad[:5]))
            if cross:
                parts.append("跨 section：" + "、".join(cross[:5]))
            findings.append(
                _finding(
                    "prereq_invalid",
                    SEVERITY_INFO,
                    section_id=lesson_section[lid],
                    lesson_id=lid,
                    title=f"前置依赖异常：{lesson.get('name') or lid}",
                    detail="；".join(parts),
                )
            )

    if duplicates:
        findings.append(
            _finding(
                "duplicate_term",
                SEVERITY_INFO,
                title=f"重复词条：{len(duplicates)} 条",
                detail="跨 vocab / expressions 的重复 term；可在资源编辑器查看并合并。",
                action_id="resource.dedupe_suggest",
                scope={"count": len(duplicates)},
            )
        )

    conflict_count = int((term_conflicts or {}).get("count") or 0)
    if conflict_count:
        findings.append(
            _finding(
                "term_conflict",
                SEVERITY_INFO,
                title=f"词条释义冲突：{conflict_count} 对",
                detail="同一 term 在 vocab 与 expressions 中释义不同；可二选一统一。",
                action_id="resource.resolve_term_conflicts",
                scope={"count": conflict_count},
            )
        )

    findings.sort(
        key=lambda f: (
            _SEVERITY_RANK.get(f.severity, 9),
            _ACTION_RANK.get(f.action_id, 90),
            f.section_id,
            f.lesson_id,
            f.kind,
        )
    )
    if max_findings > 0 and len(findings) > max_findings:
        findings = findings[:max_findings]
    return findings


def _scope_key(finding: Finding) -> str:
    if finding.lesson_id:
        return f"lesson:{finding.lesson_id}"
    if finding.unit_id:
        return f"unit:{finding.unit_id}"
    if finding.section_id:
        return f"section:{finding.section_id}"
    return "global"


def build_repair_plan(
    findings: Sequence[Finding],
    *,
    limit: int = 20,
) -> list[RepairStep]:
    """Group dispatchable findings into ordered :class:`RepairStep` items.

    Findings without an ``action_id`` stay in the audit table but are not
    planned. Same action + same node collapses into one step; the step keeps
    the first finding's title/scope and every contributing finding id.
    """
    grouped: dict[tuple[str, str], list[Finding]] = {}
    for finding in findings:
        if not finding.action_id:
            continue
        key = (finding.action_id, _scope_key(finding))
        grouped.setdefault(key, []).append(finding)

    steps: list[RepairStep] = []
    for (action_id, _scope), items in grouped.items():
        items.sort(key=lambda f: (_SEVERITY_RANK.get(f.severity, 9), f.finding_id))
        first = items[0]
        steps.append(
            RepairStep(
                step_id="",
                action_id=action_id,
                title=first.title,
                scope=dict(first.scope),
                finding_ids=tuple(f.finding_id for f in items),
                needs_confirm=True,
                estimated_calls=max(int(f.estimated_calls) for f in items),
            )
        )

    steps.sort(
        key=lambda s: (
            _ACTION_RANK.get(s.action_id, 90),
            s.scope.get("section_id", ""),
            s.scope.get("lesson_id", ""),
            s.action_id,
        )
    )
    steps = steps[: max(0, int(limit))]
    return [
        RepairStep(
            step_id=f"step-{i:02d}",
            action_id=s.action_id,
            title=s.title,
            scope=s.scope,
            finding_ids=s.finding_ids,
            needs_confirm=s.needs_confirm,
            estimated_calls=s.estimated_calls,
        )
        for i, s in enumerate(steps, start=1)
    ]


__all__ = [
    "SEVERITY_ERROR",
    "SEVERITY_INFO",
    "SEVERITY_WARNING",
    "Finding",
    "RepairStep",
    "audit_course",
    "build_repair_plan",
]
