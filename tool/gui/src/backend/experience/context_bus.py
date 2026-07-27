"""Experience Context Bus — L-local course health snapshot (Wave 0).

Pure Python, no Qt / network. Builds an :class:`ExperienceContext` from a
:class:`~src.backend.course_adapter.CourseAdapter` (or any object with the same
attributes) plus optional selection and precomputed validate problems.

Reuses:

- ``overview_stats.lesson_is_empty`` for empty-lesson detection
- ``ai_bench`` hygiene counters for global resource-pool hygiene
- ``content_quality.score_section`` for per-section quality means (optional)

Validate is **not** run by default (CLI is relatively slow). Callers pass
cached ``validate_problems`` or set ``refresh_validate=True``.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Mapping, Sequence


# Per-section quality mean below this → ``weak`` tree badge (T-01).
WEAK_SECTION_THRESHOLD = 0.7


# ---------------------------------------------------------------------------
# Types
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class NodeRef:
    """A selected / pinned course node.

    ``kind`` is typically ``section`` / ``unit`` / ``lesson`` / ``item`` /
    ``resource`` / ``problem``. ``label`` is optional display text.
    """

    kind: str
    id: str
    label: str = ""


@dataclass
class ExperienceContext:
    """Global experience snapshot for Dock / Ambient / Intent Router.

    Field set mirrors ``experienceai.md`` §6.2 plus convenience counters for
    the health dashboard.
    """

    # Course identity
    course_dir: str | None = None
    language: str = ""
    cefr_hint: str = ""

    # Focus
    selection: NodeRef | None = None
    multi_selection: list[NodeRef] = field(default_factory=list)
    pinned_refs: list[NodeRef] = field(default_factory=list)
    surface: str = "tree"  # teacher|tree|resources|overview|...

    # Health
    validate_problems: list[dict[str, Any]] = field(default_factory=list)
    validate_error_count: int = 0
    validate_warning_count: int = 0
    quality_by_section: dict[str, float] = field(default_factory=dict)
    empty_lessons: list[str] = field(default_factory=list)
    empty_lesson_count: int = 0
    hygiene: dict[str, int] = field(default_factory=dict)
    # E2.1: listening gaps detected by content_quality._score_audio_ready
    # (audio_ready dimension issues). Each dict: {lesson_id, item_id?, kind,
    # section_id}. Surfaces as a local_suggestions entry + /listening route.
    listening_gaps: list[dict[str, Any]] = field(default_factory=list)
    # v4.16 K-07: non-empty lessons with balance-dimension quality issues
    # (建议题型交集空 / 缺 listeningPhases)。每项 {lesson_id, section_id,
    # message}；Dock P3「调整题型配比」建议数据源。
    imbalanced_lessons: list[dict[str, Any]] = field(default_factory=list)
    # v4.37 K-08: words introduced via showWord but never re-surfaced in any
    # later lesson's non-showWord practice (spiral gap). 闭集 {word_id, term,
    # intro_lesson_id, section_id}；Dock P3「补充词汇螺旋复现」建议数据源。
    unsurfaced_words: list[dict[str, Any]] = field(default_factory=list)
    # v4.39 K-18: reading-template lessons whose readingPassage is empty/stub.
    # 闭集 {lesson_id, section_id, reason}（无段落原文）；Dock P3「生成阅读段落」建议源。
    empty_reading_passages: list[dict[str, Any]] = field(default_factory=list)
    # K-21 v4.43: POS misalignment across the global vocab pool. 闭集
    # {count}（无 term/原文，§14.5.3）；Dock P3「对齐词条词性」建议源。
    misaligned_pos_count: int = 0
    # v4.17 K-02: per-issue content_quality problems bridged via
    # ``ContentQualityReport.to_problem_dicts()`` — {level, path, message,
    # dimension}. Lets ``why_explain`` cover the 6 quality dimensions and
    # gives K-15 a per-issue fix handle. Capped (cap 100) to stay affordable
    # on large courses. Distinct from ``validate_problems`` (structural CLI
    # output) — never merged into it.
    quality_issues: list[dict[str, Any]] = field(default_factory=list)

    # E2.1++ / T-01: per-node tree badges. Maps node id -> {kind: count}.
    # Robust sources only (no free-text message parsing):
    #   - ``empty`` per lesson (from empty_lessons)
    #   - ``weak`` per section (quality_by_section mean below threshold)
    #   - ``errors`` per node (validate level=error via problem_to_node_ref)
    node_badges: dict[str, dict[str, int]] = field(default_factory=dict)

    # Draft / jobs — active_jobs via JobTray (S-07); workshop_draft via Shell (M3/v4.28)
    workshop_draft: dict[str, Any] | None = None
    active_jobs: list[Any] = field(default_factory=list)
    # C-14: ExperienceMetrics.snapshot() injected by Shell (alongside
    # active_jobs). None when no metrics wired; Dock omits the metrics line.
    metrics: dict[str, Any] | None = None

    # Memory / cost / multimodal — C-13: recent_intents + author_profile via Shell
    author_profile: dict[str, Any] | None = None
    recent_intents: list[Any] = field(default_factory=list)
    usage_today: dict[str, int] = field(default_factory=dict)
    budget_remaining: int | None = None
    attachments: list[Any] = field(default_factory=list)

    # Dashboard convenience
    section_count: int = 0
    unit_count: int = 0
    lesson_count: int = 0
    healthy: bool = False


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


def _busy_ids_from_jobs(active_jobs: Sequence[Any] | None) -> set[str]:
    """P6 v4.62: extract node ids from job node_key like ``lesson:l1``."""
    out: set[str] = set()
    try:
        for job in active_jobs or []:
            key = ""
            if isinstance(job, Mapping):
                key = str(job.get("node_key") or job.get("nodeKey") or "")
            else:
                key = str(getattr(job, "node_key", None) or "")
            key = key.strip()
            if not key or ":" not in key:
                continue
            _kind, nid = key.split(":", 1)
            nid = str(nid or "").strip()
            if nid:
                out.add(nid)
    except Exception:
        return set()
    return out


def _build_node_badges(
    empty_lessons: list[str],
    quality_by_section: dict[str, float],
    validate_problems: Sequence[Mapping[str, Any]] | None = None,
    sections: Sequence[Any] | None = None,
    active_jobs: Sequence[Any] | None = None,
) -> dict[str, dict[str, int]]:
    """T-01: per-node tree badges from robust sources only.

    - ``empty`` badge on each empty lesson (count=1).
    - ``weak`` badge on each section whose quality mean is below threshold.
    - ``errors`` count per node from validate problems with level=error
      and a resolvable path (via ``problem_to_node_ref``). No free-text
      message parsing.
    - ``busy`` (v4.62 P6): node_key on active AI jobs.
    """
    badges: dict[str, dict[str, int]] = {}
    for lid in empty_lessons:
        if lid:
            badges.setdefault(lid, {})["empty"] = badges.get(lid, {}).get("empty", 0) + 1
    for sid, mean in quality_by_section.items():
        if sid and mean is not None and mean < WEAK_SECTION_THRESHOLD:
            badges.setdefault(sid, {})["weak"] = 1
    for nid in _busy_ids_from_jobs(active_jobs):
        badges.setdefault(nid, {})["busy"] = 1
    if validate_problems:
        try:
            from src.teacher.error_mapper import problem_to_node_ref

            secs = list(sections or [])
            for problem in validate_problems:
                if not isinstance(problem, Mapping):
                    continue
                level = str(problem.get("level") or "").lower()
                # Only structural errors become ·错; warnings/info never badge.
                if level in ("warning", "warn", "info", "note", "hint"):
                    continue
                if level and level not in ("error", "err"):
                    continue
                if not level and not problem.get("path"):
                    continue
                ref = problem_to_node_ref(dict(problem), secs)
                if ref is None:
                    continue
                _kind, nid = ref
                nid = str(nid or "").strip()
                if not nid:
                    continue
                cur = badges.setdefault(nid, {})
                cur["errors"] = int(cur.get("errors") or 0) + 1
        except Exception:
            pass
    return badges


def empty_lessons_among(
    selected_lesson_ids: Sequence[str] | None,
    empty_lessons: Sequence[str] | None,
) -> list[str]:
    """T-02 multi-select helper: selected lesson ids that are empty (order preserved).

    Pure, never raises.
    """
    try:
        empty = {str(x) for x in (empty_lessons or []) if x}
        out: list[str] = []
        for lid in selected_lesson_ids or []:
            s = str(lid or "").strip()
            if s and s in empty and s not in out:
                out.append(s)
        return out
    except Exception:
        return []


def build_experience_context(
    adapter: Any,
    *,
    selection: NodeRef | tuple[str, str] | None = None,
    multi_selection: Sequence[NodeRef | tuple[str, str]] | None = None,
    pinned_refs: Sequence[NodeRef | tuple[str, str]] | None = None,
    surface: str = "tree",
    validate_problems: Sequence[Mapping[str, Any]] | None = None,
    include_quality: bool = True,
    include_hygiene: bool = True,
    refresh_validate: bool = False,
    workshop_draft: dict[str, Any] | None = None,
    active_jobs: Sequence[Any] | None = None,
    metrics: Mapping[str, Any] | None = None,
    usage_today: Mapping[str, int] | None = None,
    recent_intents: Sequence[Any] | None = None,
    author_profile: Mapping[str, Any] | None = None,
    attachments: Sequence[Any] | None = None,
) -> ExperienceContext:
    """Assemble an :class:`ExperienceContext` from adapter + focus state.

    Parameters
    ----------
    adapter:
        Course adapter (or stub) exposing ``sections``, ``vocab``,
        ``expressions``, ``grammar_points``, ``index``, ``course_dir``.
    selection / multi_selection / pinned_refs:
        Focus nodes; tuples ``(kind, id)`` are accepted and normalized.
    validate_problems:
        Precomputed problem dicts (``level``, ``message``, …). Used when
        ``refresh_validate`` is False.
    include_quality:
        When True, score each section via ``content_quality`` (local rules).
    include_hygiene:
        When True, count placeholders / needs-review on the global pool.
    refresh_validate:
        When True and ``adapter.course_dir`` is set, call
        ``api.validate_course_dir`` (may be slow). Default False.
    """
    course_dir = _course_dir_str(getattr(adapter, "course_dir", None))
    index = getattr(adapter, "index", None) or {}
    sections = list(getattr(adapter, "sections", None) or [])

    language = str(index.get("language") or index.get("lang") or "")
    cefr_hint = _cefr_hint(index, sections)

    empty_ids, section_count, unit_count, lesson_count = _scan_structure(sections)

    quality_by_section: dict[str, float] = {}
    listening_gaps: list[dict[str, Any]] = []
    imbalanced_lessons: list[dict[str, Any]] = []
    unsurfaced_words: list[dict[str, Any]] = []
    empty_reading_passages: list[dict[str, Any]] = []
    quality_issues: list[dict[str, Any]] = []
    if include_quality and sections:
        quality_by_section, listening_gaps, imbalanced_lessons, unsurfaced_words, empty_reading_passages, quality_issues = (
            _quality_by_section(sections, language=language, index=index)
        )

    hygiene: dict[str, int] = {}
    if include_hygiene:
        hygiene = _course_hygiene(adapter)

    # K-21: global vocab-pool POS misalignment count (local detector, never raises).
    misaligned_pos_count = 0
    if include_hygiene:
        try:
            from src.backend.experience.pos_skill import evaluate_pos_alignment

            misaligned_pos_count = int(evaluate_pos_alignment(adapter).get("count") or 0)
        except Exception:
            misaligned_pos_count = 0

    problems, err_count, warn_count = _resolve_validate(
        adapter,
        validate_problems=validate_problems,
        refresh_validate=refresh_validate,
        course_dir=course_dir,
    )

    sel = _normalize_node(selection, adapter)
    multi = [_normalize_node(n, adapter) for n in (multi_selection or [])]
    multi = [n for n in multi if n is not None]
    pinned = [_normalize_node(n, adapter) for n in (pinned_refs or [])]
    pinned = [n for n in pinned if n is not None]

    healthy = (
        err_count == 0
        and len(empty_ids) == 0
        and int(hygiene.get("placeholder_count") or 0) == 0
        and int(hygiene.get("needs_review_count") or 0) == 0
        and lesson_count > 0
    )

    node_badges = _build_node_badges(
        empty_ids,
        quality_by_section,
        validate_problems=problems,
        sections=sections,
        active_jobs=active_jobs,
    )

    # E4/M-01: closed-shape attachment summaries (raw content never enters).
    from src.backend.experience.attachments import normalize_attachments

    return ExperienceContext(
        course_dir=course_dir,
        language=language,
        cefr_hint=cefr_hint,
        selection=sel,
        multi_selection=multi,
        pinned_refs=pinned,
        surface=surface or "tree",
        validate_problems=list(problems),
        validate_error_count=err_count,
        validate_warning_count=warn_count,
        quality_by_section=quality_by_section,
        empty_lessons=empty_ids,
        empty_lesson_count=len(empty_ids),
        hygiene=hygiene,
        listening_gaps=listening_gaps,
        imbalanced_lessons=imbalanced_lessons,
        unsurfaced_words=unsurfaced_words,
        empty_reading_passages=empty_reading_passages,
        misaligned_pos_count=misaligned_pos_count,
        quality_issues=quality_issues,
        workshop_draft=workshop_draft,
        active_jobs=list(active_jobs or []),
        metrics=dict(metrics) if metrics else None,
        usage_today=dict(usage_today or {}),
        recent_intents=list(recent_intents or []),
        author_profile=dict(author_profile) if author_profile else None,
        attachments=normalize_attachments(attachments),
        section_count=section_count,
        unit_count=unit_count,
        lesson_count=lesson_count,
        healthy=healthy,
        node_badges=node_badges,
    )


# local_suggestions lives in experience.suggestions (M6); re-export for stable imports.
from src.backend.experience.suggestions import local_suggestions  # noqa: E402

def _course_dir_str(course_dir: Any) -> str | None:
    if course_dir is None:
        return None
    return str(course_dir)


def _cefr_hint(index: Mapping[str, Any], sections: list[dict[str, Any]]) -> str:
    for key in ("level", "cefr", "cefrLevel"):
        val = index.get(key)
        if val:
            return str(val)
    for section in sections:
        level = section.get("level")
        if level:
            return str(level)
    return ""


def _scan_structure(
    sections: list[dict[str, Any]],
) -> tuple[list[str], int, int, int]:
    from src.backend.overview_stats import lesson_is_empty

    empty_ids: list[str] = []
    unit_count = 0
    lesson_count = 0
    for section in sections:
        if not isinstance(section, dict):
            continue
        for unit in section.get("units") or []:
            if not isinstance(unit, dict):
                continue
            unit_count += 1
            for lesson in unit.get("lessons") or []:
                if not isinstance(lesson, dict):
                    continue
                lesson_count += 1
                if lesson_is_empty(lesson):
                    lid = str(lesson.get("id") or "")
                    if lid:
                        empty_ids.append(lid)
                    else:
                        empty_ids.append(f"?@{lesson_count}")
    return empty_ids, len(sections), unit_count, lesson_count


def _quality_by_section(
    sections: list[dict[str, Any]],
    *,
    language: str,
    index: Mapping[str, Any],
) -> tuple[dict[str, float], list[dict[str, Any]], list[dict[str, Any]], list[dict[str, Any]], list[dict[str, Any]], list[dict[str, Any]]]:
    """Score sections; also collect listening gaps, imbalanced lessons, K-08
    unsurfaced vocab, K-18 empty reading passages, and per-issue quality problems.

    Returns ``(section_id -> mean, listening_gaps, imbalanced_lessons,
    unsurfaced_words, empty_reading_passages, quality_issues)``. Listening gaps
    derive from ``audio_ready`` issues; imbalanced lessons from ``balance``
    issues (K-07, v4.16); unsurfaced words from ``evaluate_unit_spiral`` (K-08,
    v4.37); empty reading passages from ``evaluate_reading_passage`` (K-18,
    v4.39); ``quality_issues`` are the bridged ``to_problem_dicts()`` output
    across all dimensions (K-02, v4.17) for ``why_explain`` + per-error fix.
    Section-level fingerprint caching (C-18) covers all six so unchanged sections
    skip the scorer. Cache tuple grew 4→5 (K-07), 5→6 (K-08), 6→7 (K-18);
    <7-tuple stale entries are treated as misses for backward compatibility.
    """
    out: dict[str, float] = {}
    gaps: list[dict[str, Any]] = []
    imbalanced: list[dict[str, Any]] = []
    unsurfaced: list[dict[str, Any]] = []
    empty_passages: list[dict[str, Any]] = []
    quality_issues: list[dict[str, Any]] = []
    try:
        from src.backend.content_quality import (
            _iter_lessons,
            evaluate_reading_passage,
            evaluate_unit_spiral,
            score_section,
        )
    except Exception:
        return out, gaps, imbalanced, unsurfaced, empty_passages, quality_issues

    default_level = str(index.get("level") or "A1")
    for section in sections:
        if not isinstance(section, dict):
            continue
        sid = str(section.get("id") or "")
        if not sid:
            continue
        # Section-level memoization: unchanged sections skip the scorer so
        # quality stays affordable on large courses (C-18).
        fingerprint = _section_fingerprint(section)
        cached = _QUALITY_CACHE.get(sid)
        if (
            fingerprint
            and cached is not None
            and cached[0] == fingerprint
            and len(cached) >= 7
        ):
            out[sid] = cached[1]
            gaps.extend(cached[2])
            imbalanced.extend(cached[3])
            unsurfaced.extend(cached[4])
            empty_passages.extend(cached[5])
            quality_issues.extend(cached[6])
            continue
        try:
            level = str(section.get("level") or default_level)
            report = score_section(section, level=level)
            mean = float(report.mean)
            out[sid] = mean
            section_gaps = _listening_gaps_from_report(report, section_id=sid)
            section_imb = _imbalance_from_report(report, section_id=sid)
            spiral = evaluate_unit_spiral(section)
            section_unsurf = list(spiral.get("unsurfaced") or [])
            section_passages: list[dict[str, Any]] = []
            for _unit, lesson in _iter_lessons(section):
                if not isinstance(lesson, dict):
                    continue
                rp = evaluate_reading_passage(lesson)
                if rp.get("empty"):
                    section_passages.append(
                        {
                            "lesson_id": str(rp.get("lesson_id") or ""),
                            "section_id": sid,
                            "reason": str(rp.get("reason") or ""),
                        }
                    )
            section_issues = report.to_problem_dicts(max_issues=40)
            gaps.extend(section_gaps)
            imbalanced.extend(section_imb)
            unsurfaced.extend(section_unsurf)
            empty_passages.extend(section_passages)
            quality_issues.extend(section_issues)
            if fingerprint:
                _QUALITY_CACHE[sid] = (
                    fingerprint,
                    mean,
                    section_gaps,
                    section_imb,
                    section_unsurf,
                    section_passages,
                    section_issues,
                )
        except Exception:
            continue
    # Cap to keep large courses affordable (K-02 why surface + K-15 fix list).
    if len(quality_issues) > 100:
        quality_issues = quality_issues[:100]
    return out, gaps, imbalanced, unsurfaced, empty_passages, quality_issues


def _listening_gaps_from_report(
    report: Any,
    *,
    section_id: str,
) -> list[dict[str, Any]]:
    """Extract audio_ready issues into actionable listening-gap dicts.

    Kinds: ``missing_audio`` (item lacks audioAsset+transcript),
    ``missing_transcript`` (v4.39 K-17: item has audio but lacks transcript),
    ``empty_phase`` (listening phase has no items). The kind is read from the
    issue's ``gap_kind`` (set since v4.39); empty → legacy inference from
    ``item_id`` presence (``missing_audio`` / ``empty_phase``).
    """
    out: list[dict[str, Any]] = []
    issues = getattr(report, "issues", None) or []
    for issue in issues:
        if str(getattr(issue, "dimension", "")) != "audio_ready":
            continue
        message = str(getattr(issue, "message", "") or "")
        item_id = getattr(issue, "item_id", None)
        gap_kind = str(getattr(issue, "gap_kind", "") or "")
        if not gap_kind:
            gap_kind = "missing_audio" if item_id else "empty_phase"
        out.append(
            {
                "lesson_id": str(getattr(issue, "lesson_id", "") or ""),
                "item_id": str(item_id) if item_id else "",
                "kind": gap_kind,
                "section_id": section_id,
                "message": message,
            }
        )
    return out


def _imbalance_from_report(
    report: Any,
    *,
    section_id: str,
) -> list[dict[str, Any]]:
    """K-07 (v4.16): balance-dimension issues → actionable lesson refs.

    Skips the empty-lesson finding (「没有任何题目」is lesson.fill_empty's
    domain, P1) and dedupes per lesson (first message kept).
    """
    out: list[dict[str, Any]] = []
    seen: set[str] = set()
    issues = getattr(report, "issues", None) or []
    for issue in issues:
        if str(getattr(issue, "dimension", "")) != "balance":
            continue
        lid = str(getattr(issue, "lesson_id", "") or "")
        message = str(getattr(issue, "message", "") or "")
        if not lid or lid in seen or "没有任何题目" in message:
            continue
        seen.add(lid)
        out.append(
            {"lesson_id": lid, "section_id": section_id, "message": message}
        )
    return out


_QUALITY_CACHE: dict[
    str, tuple[str, float, list[dict[str, Any]], list[dict[str, Any]], list[dict[str, Any]], list[dict[str, Any]], list[dict[str, Any]]]
] = {}


def _section_fingerprint(section: dict[str, Any]) -> str:
    """Stable content fingerprint for the quality cache ('' on failure)."""
    import hashlib
    import json

    try:
        blob = json.dumps(section, sort_keys=True, ensure_ascii=False, default=str)
    except Exception:
        return ""
    return hashlib.sha1(blob.encode("utf-8")).hexdigest()


def _course_hygiene(adapter: Any) -> dict[str, int]:
    """Aggregate hygiene over the adapter's global resource pools.

    Builds a synthetic section-shaped dict so ``ai_bench`` counters apply
    without duplicating placeholder / needs-review rules.
    """
    from src.backend.ai_bench import (
        count_empty_translations,
        count_needs_review,
        count_placeholders,
    )

    pseudo = {
        "words": list(getattr(adapter, "vocab", None) or []),
        "expressions": list(getattr(adapter, "expressions", None) or []),
        "grammarPoints": list(getattr(adapter, "grammar_points", None) or []),
    }
    out = {
        "placeholder_count": int(count_placeholders(pseudo)),
        "needs_review_count": int(count_needs_review(pseudo)),
        "empty_translation_count": int(count_empty_translations(pseudo)),
        "vocab_count": len(pseudo["words"]),
        "expression_count": len(pseudo["expressions"]),
        "grammar_count": len(pseudo["grammarPoints"]),
        "duplicate_count": 0,
    }
    # K-20: local duplicate term count (never raises).
    try:
        detect = getattr(adapter, "detect_duplicates", None)
        if callable(detect):
            dupes = detect() or []
            out["duplicate_count"] = int(len(dupes))
            if dupes and isinstance(dupes[0], dict):
                sample = str(dupes[0].get("term") or "")
                if sample:
                    # Stash as non-int marker for suggestions (hygiene is int-heavy;
                    # sample lives on suggestion scope instead — keep count only).
                    out["duplicate_sample_hash"] = hash(sample) % 10_000_000
    except Exception:
        pass
    # V-06: local vocab↔expression term conflict count (never raises).
    try:
        from src.backend.experience.term_conflict_skill import (
            evaluate_term_conflicts,
        )

        out["conflict_count"] = int(
            evaluate_term_conflicts(adapter).get("count") or 0
        )
    except Exception:
        pass
    return out


def _resolve_validate(
    adapter: Any,
    *,
    validate_problems: Sequence[Mapping[str, Any]] | None,
    refresh_validate: bool,
    course_dir: str | None,
) -> tuple[list[dict[str, Any]], int, int]:
    problems: list[dict[str, Any]] = []

    if refresh_validate and course_dir:
        try:
            from src.backend import api

            result = api.validate_course_dir(Path(course_dir))
            # ValidateResult may expose .problems or be iterable-like.
            raw = getattr(result, "problems", None)
            if raw is None:
                raw = getattr(result, "errors", None) or []
            for p in raw:
                if isinstance(p, Mapping):
                    problems.append(dict(p))
                else:
                    # Problem objects with attributes
                    level = getattr(p, "level", "error")
                    problems.append(
                        {
                            "level": level,
                            "message": str(getattr(p, "message", p)),
                            "path": str(getattr(p, "path", "") or ""),
                        }
                    )
            # Also fold lint warnings if cheap enough — best-effort.
            try:
                for p in api.lint_course_dir(Path(course_dir)):
                    level = getattr(p, "level", None) or (
                        p.get("level") if isinstance(p, Mapping) else "warning"
                    )
                    if str(level).lower() != "warning":
                        continue
                    if isinstance(p, Mapping):
                        problems.append(dict(p))
                    else:
                        problems.append(
                            {
                                "level": "warning",
                                "message": str(getattr(p, "message", p)),
                                "path": str(getattr(p, "path", "") or ""),
                            }
                        )
            except Exception:
                pass
        except Exception:
            problems = []
    elif validate_problems is not None:
        problems = [dict(p) for p in validate_problems if isinstance(p, Mapping)]

    err = sum(1 for p in problems if _problem_level(p) == "error")
    warn = sum(1 for p in problems if _problem_level(p) == "warning")
    return problems, err, warn


def _problem_level(p: Mapping[str, Any]) -> str:
    level = str(p.get("level") or p.get("severity") or "error").lower()
    if level in ("warn", "warning"):
        return "warning"
    if level in ("info", "hint", "note"):
        return "info"
    return "error"


def _normalize_node(
    node: NodeRef | tuple[str, str] | None,
    adapter: Any,
) -> NodeRef | None:
    if node is None:
        return None
    if isinstance(node, NodeRef):
        if node.label:
            return node
        label = _lookup_label(adapter, node.kind, node.id)
        if label and label != node.label:
            return NodeRef(kind=node.kind, id=node.id, label=label)
        return node
    if isinstance(node, tuple) and len(node) >= 2:
        kind, nid = str(node[0]), str(node[1])
        label = _lookup_label(adapter, kind, nid)
        return NodeRef(kind=kind, id=nid, label=label)
    return None


# Public alias for Shell's focus-only fast path (C-03). Keeps the private name
# for in-module callers; exposes a stable import surface for application code.
normalize_node = _normalize_node


def _lookup_label(adapter: Any, kind: str, node_id: str) -> str:
    """Best-effort display name from in-memory course tree."""
    if not node_id:
        return ""
    kind = (kind or "").lower()
    sections = list(getattr(adapter, "sections", None) or [])

    if kind == "section":
        for section in sections:
            if isinstance(section, dict) and str(section.get("id")) == node_id:
                return str(section.get("name") or section.get("title") or node_id)
        return node_id

    if kind == "unit":
        for section in sections:
            if not isinstance(section, dict):
                continue
            for unit in section.get("units") or []:
                if isinstance(unit, dict) and str(unit.get("id")) == node_id:
                    return str(unit.get("name") or unit.get("title") or node_id)
        return node_id

    if kind == "lesson":
        for section in sections:
            if not isinstance(section, dict):
                continue
            for unit in section.get("units") or []:
                if not isinstance(unit, dict):
                    continue
                for lesson in unit.get("lessons") or []:
                    if isinstance(lesson, dict) and str(lesson.get("id")) == node_id:
                        return str(
                            lesson.get("name")
                            or lesson.get("title")
                            or lesson.get("id")
                            or node_id
                        )
        return node_id

    if kind == "item":
        # R-01: interaction items live deep inside lesson content; walk the
        # tree and show a short prompt snippet when found.
        for section in sections:
            found = _lookup_item_label(section, node_id)
            if found:
                return found
        return node_id

    return node_id


def _lookup_item_label(node: Any, node_id: str, depth: int = 0) -> str:
    """Find an interaction item by id; return a ≤20-char display label."""
    if depth > 8:
        return ""
    if isinstance(node, dict):
        if str(node.get("id")) == node_id and (
            "runtimeType" in node or "prompt" in node or "sentence" in node
        ):
            label = str(
                node.get("prompt")
                or node.get("sentence")
                or node.get("word")
                or node.get("id")
                or ""
            )
            return label[:20]
        for value in node.values():
            found = _lookup_item_label(value, node_id, depth + 1)
            if found:
                return found
    elif isinstance(node, list):
        for value in node:
            found = _lookup_item_label(value, node_id, depth + 1)
            if found:
                return found
    return ""
