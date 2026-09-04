"""Rule-based content quality scoring for AI-generated course section drafts.

Pure Python, no Qt / network. Complements structural validation (course_cli /
CourseAdapter) with pedagogy-oriented probes: vocab coverage in exercises,
template/runtimeType balance, MCQ distractor hygiene, level fit heuristics,
listening readiness, and resource hygiene (delegates to ``ai_bench``).

Scores are advisory only — they must not gate save/import.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Literal

from src.backend.ai_bench import (
    count_empty_translations,
    count_mcq_duplicate_options,
    count_needs_review,
    count_placeholders,
    find_dangling_refs,
    score_section_hygiene,
)

Dimension = Literal[
    "coverage",
    "balance",
    "distractor",
    "level_fit",
    "audio_ready",
    "resource_hygiene",
]

Badge = Literal["error", "warning", "ok"]

_DIMENSIONS: tuple[Dimension, ...] = (
    "coverage",
    "balance",
    "distractor",
    "level_fit",
    "audio_ready",
    "resource_hygiene",
)

# Soft CEFR caps (prompt-aligned with ai_pedagogy; not hard validators).
_LEVEL_WORD_CAP: dict[str, int] = {
    "A1": 10,
    "A2": 14,
    "B1": 18,
    "B2": 24,
}
_LEVEL_SENTENCE_WORDS: dict[str, int] = {
    "A1": 12,
    "A2": 16,
    "B1": 22,
    "B2": 30,
}

_MCQ_TYPES = frozenset(
    {
        "multipleChoice",
        "listenAndPick",
        "multiSelect",
        "trueFalse",
    }
)
_PRACTICE_TYPES = frozenset(
    {
        "multipleChoice",
        "translateSentence",
        "fillBlank",
        "reorderSentence",
        "listenAndPick",
        "typeTheWord",
        "multiSelect",
        "trueFalse",
        "shortAnswer",
        "matchWords",
    }
)
_TEMPLATE_HINTS: dict[str, frozenset[str]] = {
    "intro": frozenset({"showWord", "multipleChoice", "listenAndPick", "translateSentence"}),
    "practice": frozenset({"multipleChoice", "fillBlank", "translateSentence", "reorderSentence"}),
    "review": frozenset({"multipleChoice", "translateSentence", "fillBlank", "matchWords"}),
    "listening": frozenset({"listenAndPick", "typeTheWord", "multipleChoice"}),
    "reading": frozenset({"multipleChoice", "trueFalse", "shortAnswer"}),
    "mastery": frozenset(
        {
            "multipleChoice",
            "fillBlank",
            "translateSentence",
            "listenAndPick",
            "multiSelect",
        }
    ),
}


@dataclass(frozen=True)
class ContentQualityIssue:
    """One concrete content-quality finding."""

    level: Literal["error", "warning"]
    dimension: Dimension
    message: str
    path: str = ""
    lesson_id: str | None = None
    item_id: str | None = None
    gap_kind: str = ""


@dataclass
class ContentQualityReport:
    """Aggregate quality scores + issues for a section draft."""

    scores: dict[str, float] = field(default_factory=dict)
    issues: list[ContentQualityIssue] = field(default_factory=list)
    hygiene: dict[str, Any] = field(default_factory=dict)

    @property
    def mean(self) -> float:
        if not self.scores:
            return 0.0
        vals = [float(self.scores[d]) for d in _DIMENSIONS if d in self.scores]
        if not vals:
            return 0.0
        return round(sum(vals) / len(vals), 3)

    @property
    def error_count(self) -> int:
        return sum(1 for i in self.issues if i.level == "error")

    @property
    def warning_count(self) -> int:
        return sum(1 for i in self.issues if i.level == "warning")

    def badge(self) -> Badge:
        if self.error_count:
            return "error"
        if self.warning_count or self.mean < 0.65:
            return "warning"
        return "ok"

    def low_dimensions(self, threshold: float = 0.7) -> list[str]:
        """Dimensions scoring strictly below ``threshold``, lowest first."""
        ranked = sorted(
            ((d, float(self.scores.get(d, 0.0))) for d in _DIMENSIONS),
            key=lambda t: t[1],
        )
        return [d for d, s in ranked if s < threshold]

    def to_problem_dicts(
        self,
        *,
        dimensions: list[str] | None = None,
        max_issues: int = 40,
    ) -> list[dict[str, Any]]:
        """Map issues to validator-like problem dicts for AI fix prompts."""
        allow = set(dimensions) if dimensions else None
        out: list[dict[str, Any]] = []
        for issue in self.issues:
            if allow is not None and issue.dimension not in allow:
                continue
            out.append(
                {
                    "level": issue.level,
                    "path": issue.path or f"quality.{issue.dimension}",
                    "message": f"[{issue.dimension}] {issue.message}",
                    "dimension": issue.dimension,
                }
            )
            if len(out) >= max_issues:
                break
        if not out and self.low_dimensions():
            for dim in self.low_dimensions()[:6]:
                score = self.scores.get(dim, 0.0)
                out.append(
                    {
                        "level": "warning",
                        "path": f"quality.{dim}",
                        "message": f"[{dim}] 内容质量分偏低 ({score:.2f})，请按该维度改进草稿。",
                        "dimension": dim,
                    }
                )
        return out


def _normalize_level(level: str) -> str:
    raw = (level or "A1").strip().upper()
    for key in ("A1", "A2", "B1", "B2"):
        if raw.startswith(key):
            return key
    return "A1"


def _iter_lessons(section: dict[str, Any]):
    for unit in section.get("units") or []:
        if not isinstance(unit, dict):
            continue
        for lesson in unit.get("lessons") or []:
            if isinstance(lesson, dict):
                yield unit, lesson


def _iter_items_with_path(section: dict[str, Any]):
    for unit, lesson in _iter_lessons(section):
        lid = str(lesson.get("id") or "?")
        content = lesson.get("content") or {}
        if not isinstance(content, dict):
            continue
        for stage in content.get("stages") or []:
            if not isinstance(stage, dict):
                continue
            for item in stage.get("items") or []:
                if isinstance(item, dict):
                    yield lesson, item, f"lessons/{lid}/stages"
        for sub in content.get("subLessons") or []:
            if not isinstance(sub, dict):
                continue
            for stage in sub.get("stages") or []:
                if not isinstance(stage, dict):
                    continue
                for item in stage.get("items") or []:
                    if isinstance(item, dict):
                        yield lesson, item, f"lessons/{lid}/subLessons"
        for phase in content.get("listeningPhases") or []:
            if not isinstance(phase, dict):
                continue
            pid = str(phase.get("id") or "?")
            for item in phase.get("items") or []:
                if isinstance(item, dict):
                    yield lesson, item, f"lessons/{lid}/listeningPhases/{pid}"


def _word_ids(section: dict[str, Any]) -> set[str]:
    return {
        str(w.get("id"))
        for w in (section.get("words") or [])
        if isinstance(w, dict) and w.get("id")
    }


def _count_practice_hits_for_words(section: dict[str, Any]) -> dict[str, int]:
    """How many non-showWord practice items reference each word id."""
    hits: dict[str, int] = {wid: 0 for wid in _word_ids(section)}
    for _lesson, item, _path in _iter_items_with_path(section):
        rt = str(item.get("runtimeType") or "")
        if rt == "showWord":
            continue
        if rt not in _PRACTICE_TYPES and rt != "showWord":
            # still count explicit wordId on other interactive types
            pass
        candidates: list[str] = []
        if item.get("wordId"):
            candidates.append(str(item["wordId"]))
        for key in ("wordIds", "correctWordIds"):
            vals = item.get(key)
            if isinstance(vals, list):
                candidates.extend(str(v) for v in vals if v)
        # options / expected may equal term — soft credit via term match later
        for cid in candidates:
            if cid in hits:
                hits[cid] += 1
        # Term echo in options / expected / source
        options = item.get("options") if isinstance(item.get("options"), list) else []
        blob = " ".join(
            [
                str(item.get("expected") or ""),
                str(item.get("source") or ""),
                str(item.get("prompt") or ""),
                *[str(o) for o in options],
            ]
        ).lower()
        for w in section.get("words") or []:
            if not isinstance(w, dict):
                continue
            wid = str(w.get("id") or "")
            term = str(w.get("term") or "").strip()
            if wid in hits and term and term.lower() in blob and rt != "showWord":
                hits[wid] += 1
    return hits


def _score_coverage(section: dict[str, Any], issues: list[ContentQualityIssue]) -> float:
    words = [w for w in (section.get("words") or []) if isinstance(w, dict) and w.get("id")]
    if not words:
        return 1.0
    hits = _count_practice_hits_for_words(section)
    covered = sum(1 for wid, n in hits.items() if n > 0)
    ratio = covered / max(len(words), 1)
    for w in words:
        wid = str(w.get("id"))
        if hits.get(wid, 0) == 0:
            term = w.get("term") or wid
            issues.append(
                ContentQualityIssue(
                    level="warning",
                    dimension="coverage",
                    message=f"词「{term}」未在练习中复现（仅 showWord 或未引用）",
                    path=f"words/{wid}",
                )
            )
    return round(ratio, 3)


def _lesson_runtime_types(lesson: dict[str, Any]) -> list[str]:
    types: list[str] = []
    content = lesson.get("content") or {}
    if not isinstance(content, dict):
        return types
    for stage in content.get("stages") or []:
        if isinstance(stage, dict):
            for item in stage.get("items") or []:
                if isinstance(item, dict) and item.get("runtimeType"):
                    types.append(str(item["runtimeType"]))
    for sub in content.get("subLessons") or []:
        if not isinstance(sub, dict):
            continue
        for stage in sub.get("stages") or []:
            if isinstance(stage, dict):
                for item in stage.get("items") or []:
                    if isinstance(item, dict) and item.get("runtimeType"):
                        types.append(str(item["runtimeType"]))
    for phase in content.get("listeningPhases") or []:
        if not isinstance(phase, dict):
            continue
        for item in phase.get("items") or []:
            if isinstance(item, dict) and item.get("runtimeType"):
                types.append(str(item["runtimeType"]))
    return types


def _score_balance(section: dict[str, Any], issues: list[ContentQualityIssue]) -> float:
    lessons = [lesson for _u, lesson in _iter_lessons(section)]
    if not lessons:
        issues.append(
            ContentQualityIssue(
                level="error",
                dimension="balance",
                message="草稿没有课时",
                path="units",
            )
        )
        return 0.0

    scores: list[float] = []
    for lesson in lessons:
        lid = str(lesson.get("id") or "?")
        template = str(lesson.get("template") or "mixed").strip() or "mixed"
        types = _lesson_runtime_types(lesson)
        if not types:
            issues.append(
                ContentQualityIssue(
                    level="warning",
                    dimension="balance",
                    message=f"课时 {lid} 没有任何题目",
                    path=f"lessons/{lid}",
                    lesson_id=lid,
                )
            )
            scores.append(0.2)
            continue
        unique = set(types)
        diversity = min(1.0, len(unique) / 3.0)
        hints = _TEMPLATE_HINTS.get(template)
        hit = 1.0
        if hints:
            if unique & hints:
                hit = 1.0
            else:
                hit = 0.45
                issues.append(
                    ContentQualityIssue(
                        level="warning",
                        dimension="balance",
                        message=(
                            f"课时 {lid}（template={template}）题型 "
                            f"{sorted(unique)} 与建议题型交集为空"
                        ),
                        path=f"lessons/{lid}/template",
                        lesson_id=lid,
                    )
                )
        # Listening template: prefer listeningPhases present
        content = lesson.get("content") or {}
        if template == "listening":
            phases = content.get("listeningPhases") if isinstance(content, dict) else None
            if not phases:
                hit = min(hit, 0.4)
                issues.append(
                    ContentQualityIssue(
                        level="warning",
                        dimension="balance",
                        message=f"listening 课时 {lid} 缺少 listeningPhases",
                        path=f"lessons/{lid}/listeningPhases",
                        lesson_id=lid,
                    )
                )
        scores.append(round(0.55 * diversity + 0.45 * hit, 3))
    return round(sum(scores) / len(scores), 3)


def _score_distractor(section: dict[str, Any], issues: list[ContentQualityIssue]) -> float:
    mcq_items: list[tuple[dict[str, Any], dict[str, Any], str]] = []
    for lesson, item, path in _iter_items_with_path(section):
        rt = str(item.get("runtimeType") or "")
        if rt in _MCQ_TYPES or isinstance(item.get("options"), list):
            if isinstance(item.get("options"), list) and len(item["options"]) >= 2:
                mcq_items.append((lesson, item, path))

    if not mcq_items:
        return 1.0

    penalties = 0
    for lesson, item, path in mcq_items:
        lid = str(lesson.get("id") or "?")
        iid = str(item.get("id") or "?")
        options = [str(o).strip() for o in item.get("options") or []]
        if len(options) != len(set(options)):
            penalties += 1
            issues.append(
                ContentQualityIssue(
                    level="error",
                    dimension="distractor",
                    message="选择题 options 存在重复项",
                    path=f"{path}/items/{iid}/options",
                    lesson_id=lid,
                    item_id=iid,
                )
            )
        nonempty = [o for o in options if o]
        if len(nonempty) < 2:
            penalties += 1
            issues.append(
                ContentQualityIssue(
                    level="warning",
                    dimension="distractor",
                    message="选择题有效选项过少",
                    path=f"{path}/items/{iid}/options",
                    lesson_id=lid,
                    item_id=iid,
                )
            )
        # Length variance: very short vs very long outlier
        lengths = [len(o) for o in nonempty]
        if lengths and max(lengths) >= 3 * max(1, min(lengths)) and max(lengths) >= 12:
            penalties += 0.5
            issues.append(
                ContentQualityIssue(
                    level="warning",
                    dimension="distractor",
                    message="选项长度差异过大，干扰项可能不像同质选择",
                    path=f"{path}/items/{iid}/options",
                    lesson_id=lid,
                    item_id=iid,
                )
            )
        ci = item.get("correctIndex")
        if isinstance(ci, int) and (ci < 0 or ci >= len(options)):
            penalties += 1
            issues.append(
                ContentQualityIssue(
                    level="error",
                    dimension="distractor",
                    message=f"correctIndex={ci} 越界",
                    path=f"{path}/items/{iid}/correctIndex",
                    lesson_id=lid,
                    item_id=iid,
                )
            )

    dup_count = count_mcq_duplicate_options(section)
    # score: 1 - penalties / n, floor 0
    n = max(len(mcq_items), 1)
    score = max(0.0, 1.0 - (penalties / n))
    if dup_count and score > 0.5:
        score = min(score, 0.5)
    return round(score, 3)


def _estimate_sentence_words(text: str) -> int:
    t = (text or "").strip()
    if not t:
        return 0
    # Prefer whitespace tokenization; CJK-ish fallback by char groups
    parts = t.split()
    if len(parts) >= 2:
        return len(parts)
    return max(1, min(len(t), 40))


def _score_level_fit(
    section: dict[str, Any],
    *,
    level: str,
    issues: list[ContentQualityIssue],
) -> float:
    lvl = _normalize_level(level)
    cap = _LEVEL_WORD_CAP[lvl]
    sent_cap = _LEVEL_SENTENCE_WORDS[lvl]
    words = [w for w in (section.get("words") or []) if isinstance(w, dict)]
    lessons = list(_iter_lessons(section))
    lesson_count = max(len(lessons), 1)
    words_per_lesson = len(words) / lesson_count

    score = 1.0
    if words_per_lesson > cap:
        score -= 0.35
        issues.append(
            ContentQualityIssue(
                level="warning",
                dimension="level_fit",
                message=(
                    f"{lvl} 平均每课词量约 {words_per_lesson:.1f}，"
                    f"超过建议上限 {cap}"
                ),
                path="words",
            )
        )

    long_hits = 0
    checked = 0
    for lesson, item, path in _iter_items_with_path(section):
        for field in ("prompt", "source", "expected", "sentence", "text"):
            val = item.get(field)
            if not isinstance(val, str) or not val.strip():
                continue
            checked += 1
            n = _estimate_sentence_words(val)
            if n > sent_cap:
                long_hits += 1
                if long_hits <= 5:
                    iid = str(item.get("id") or "?")
                    issues.append(
                        ContentQualityIssue(
                            level="warning",
                            dimension="level_fit",
                            message=f"文本约 {n} 词，偏长于 {lvl} 建议（≤{sent_cap}）",
                            path=f"{path}/items/{iid}/{field}",
                            lesson_id=str(lesson.get("id") or "?"),
                            item_id=iid,
                        )
                    )
    if checked:
        ratio_long = long_hits / checked
        score -= min(0.5, ratio_long * 0.8)
    return round(max(0.0, min(1.0, score)), 3)


def _score_audio_ready(
    section: dict[str, Any],
    issues: list[ContentQualityIssue],
) -> float:
    listening_lessons = 0
    phase_count = 0
    item_count = 0
    missing_audio = 0
    empty_phases = 0

    for lesson, item, path in _iter_items_with_path(section):
        rt = str(item.get("runtimeType") or "")
        if rt in ("listenAndPick", "typeTheWord") or "listen" in rt.lower():
            item_count += 1
            audio = item.get("audioAsset")
            transcript = item.get("transcript") or item.get("text")
            has_audio = isinstance(audio, str) and audio.strip()
            has_transcript = isinstance(transcript, str) and transcript.strip()
            if not has_audio and not has_transcript:
                missing_audio += 1
                iid = str(item.get("id") or "?")
                lid = str(lesson.get("id") or "?")
                issues.append(
                    ContentQualityIssue(
                        level="warning",
                        dimension="audio_ready",
                        message="听力题缺少 audioAsset / transcript",
                        path=f"{path}/items/{iid}",
                        lesson_id=lid,
                        item_id=iid,
                        gap_kind="missing_audio",
                    )
                )
            elif has_audio and not has_transcript:
                iid = str(item.get("id") or "?")
                lid = str(lesson.get("id") or "?")
                issues.append(
                    ContentQualityIssue(
                        level="warning",
                        dimension="audio_ready",
                        message="听力题有音频但缺少 transcript",
                        path=f"{path}/items/{iid}",
                        lesson_id=lid,
                        item_id=iid,
                        gap_kind="missing_transcript",
                    )
                )

    for _unit, lesson in _iter_lessons(section):
        template = str(lesson.get("template") or "")
        content = lesson.get("content") or {}
        phases = []
        if isinstance(content, dict):
            phases = [p for p in (content.get("listeningPhases") or []) if isinstance(p, dict)]
        types = _lesson_runtime_types(lesson)
        has_listen_items = any(
            t in ("listenAndPick", "typeTheWord") or "listen" in t.lower()
            for t in types
        )
        if template == "listening" or phases or has_listen_items:
            listening_lessons += 1
            phase_count += len(phases)
            for phase in phases:
                items = phase.get("items") or []
                if not items:
                    empty_phases += 1
                    pid = str(phase.get("id") or "?")
                    lid = str(lesson.get("id") or "?")
                    issues.append(
                        ContentQualityIssue(
                            level="warning",
                            dimension="audio_ready",
                            message=f"listening 阶段 {pid} 无题目",
                            path=f"lessons/{lid}/listeningPhases/{pid}",
                            lesson_id=lid,
                            gap_kind="empty_phase",
                        )
                    )

    if listening_lessons == 0 and item_count == 0:
        return 1.0  # N/A → full score (not a listening draft)

    score = 1.0
    if empty_phases:
        score -= min(0.4, 0.15 * empty_phases)
    if item_count:
        score -= min(0.6, 0.5 * (missing_audio / item_count))
    elif listening_lessons and phase_count and empty_phases == phase_count:
        score = 0.25
    return round(max(0.0, min(1.0, score)), 3)


def _score_resource_hygiene(
    section: dict[str, Any],
    *,
    resource_pool: list[dict[str, Any]] | None,
    structural_errors: list[Any] | None,
    issues: list[ContentQualityIssue],
) -> tuple[float, dict[str, Any]]:
    hygiene = score_section_hygiene(
        section,
        resource_pool=resource_pool,
        structural_errors=structural_errors,
    )
    placeholder = int(hygiene.get("placeholder_count") or 0)
    needs_review = int(hygiene.get("needs_review_count") or 0)
    empty_tr = int(hygiene.get("empty_translation_count") or 0)
    dangling = int(hygiene.get("dangling_ref_count") or 0)
    word_count = max(int(hygiene.get("word_count") or 0), 1)

    for ref in hygiene.get("dangling_refs") or []:
        issues.append(
            ContentQualityIssue(
                level="error",
                dimension="resource_hygiene",
                message=f"悬空引用：{ref}",
                path="resources",
            )
        )
    if placeholder:
        issues.append(
            ContentQualityIssue(
                level="warning",
                dimension="resource_hygiene",
                message=f"{placeholder} 个字段仍为 [待补]",
                path="resources",
            )
        )
    if needs_review:
        issues.append(
            ContentQualityIssue(
                level="warning",
                dimension="resource_hygiene",
                message=f"{needs_review} 条资源带 needs-review/auto-fix 标签",
                path="resources",
            )
        )
    if empty_tr:
        issues.append(
            ContentQualityIssue(
                level="warning",
                dimension="resource_hygiene",
                message=f"{empty_tr} 条资源 translation/explanation 为空",
                path="resources",
            )
        )

    # Composite: start 1.0, subtract weighted defects
    score = 1.0
    score -= min(0.5, dangling * 0.25)
    score -= min(0.35, (placeholder / word_count) * 0.5)
    score -= min(0.25, (needs_review / word_count) * 0.4)
    score -= min(0.2, (empty_tr / word_count) * 0.3)
    if structural_errors:
        err_n = sum(
            1
            for e in structural_errors
            if not isinstance(e, dict) or e.get("level", "error") == "error"
        )
        score -= min(0.4, err_n * 0.1)
    return round(max(0.0, min(1.0, score)), 3), hygiene


def score_section(
    section: dict[str, Any] | None,
    *,
    level: str = "A1",
    resource_pool: list[dict[str, Any]] | None = None,
    structural_errors: list[Any] | None = None,
) -> ContentQualityReport:
    """Score a section draft across pedagogy / hygiene dimensions."""
    if not isinstance(section, dict):
        return ContentQualityReport(
            scores={d: 0.0 for d in _DIMENSIONS},
            issues=[
                ContentQualityIssue(
                    level="error",
                    dimension="balance",
                    message="草稿不是有效的 section 对象",
                    path="",
                )
            ],
            hygiene=score_section_hygiene(None),
        )

    issues: list[ContentQualityIssue] = []
    scores: dict[str, float] = {}
    scores["coverage"] = _score_coverage(section, issues)
    scores["balance"] = _score_balance(section, issues)
    scores["distractor"] = _score_distractor(section, issues)
    scores["level_fit"] = _score_level_fit(section, level=level, issues=issues)
    scores["audio_ready"] = _score_audio_ready(section, issues)
    hygiene_score, hygiene = _score_resource_hygiene(
        section,
        resource_pool=resource_pool,
        structural_errors=structural_errors,
        issues=issues,
    )
    scores["resource_hygiene"] = hygiene_score

    return ContentQualityReport(scores=scores, issues=issues, hygiene=hygiene)


def format_quality_line(report: ContentQualityReport) -> str:
    """One-line summary for status / chips header."""
    parts = [f"质量={report.mean:.2f}", f"badge={report.badge()}"]
    for d in _DIMENSIONS:
        if d in report.scores:
            parts.append(f"{d[0:3]}={report.scores[d]:.2f}")
    if report.error_count or report.warning_count:
        parts.append(f"issues={report.error_count}e/{report.warning_count}w")
    return " · ".join(parts)


def build_quality_fix_hint(report: ContentQualityReport) -> str:
    """User hint for AiFixDialog focused on lowest quality dimensions."""
    lows = report.low_dimensions(0.75)
    if not lows:
        lows = sorted(report.scores, key=lambda k: report.scores[k])[:2]
    lines = [
        "请优先提升以下内容质量维度（保持全部 id 不变）：",
    ]
    for dim in lows[:4]:
        lines.append(f"- {dim}（当前 {report.scores.get(dim, 0):.2f}）")
    for issue in report.issues[:12]:
        lines.append(f"- {issue.message}")
    return "\n".join(lines)


def issues_for_dimension(
    report: ContentQualityReport,
    dimension: str,
) -> list[ContentQualityIssue]:
    """Return issues belonging to a single quality dimension."""
    dim = (dimension or "").strip()
    return [i for i in report.issues if i.dimension == dim]


def build_quality_fix_hint_for_dimension(
    report: ContentQualityReport,
    dimension: str,
) -> str:
    """User hint for AiFixDialog focused on one quality dimension."""
    dim = (dimension or "").strip() or "coverage"
    score = float(report.scores.get(dim, 0.0))
    lines = [
        f"请优先提升内容质量维度「{dim}」（当前 {score:.2f}；保持全部 id 不变）：",
    ]
    issues = issues_for_dimension(report, dim)
    if issues:
        for issue in issues[:16]:
            path = f" @ {issue.path}" if issue.path else ""
            lines.append(f"- {issue.message}{path}")
    else:
        lines.append(f"- 该维度分数偏低，请按「{dim}」相关教学法规则整体改进草稿。")
    return "\n".join(lines)


def evaluate_unit_spiral(section: dict[str, Any]) -> dict[str, Any]:
    """Evaluate spiral vocabulary gaps in a section (Phase 3 Route A / K08)."""
    if not isinstance(section, dict):
        return {
            "section_id": "",
            "total_introduced": 0,
            "surfaced_count": 0,
            "unsurfaced_count": 0,
            "unsurfaced": [],
        }

    sid = str(section.get("id") or "")
    words = section.get("words") or []
    word_map = {
        str(w.get("id")): w
        for w in words
        if isinstance(w, dict) and w.get("id")
    }

    introduced: set[str] = set()
    practiced: set[str] = set()

    for unit in section.get("units") or []:
        if not isinstance(unit, dict):
            continue
        for lesson in unit.get("lessons") or []:
            if not isinstance(lesson, dict):
                continue
            content = lesson.get("content") or {}
            for stage in content.get("stages") or []:
                if not isinstance(stage, dict):
                    continue
                for item in stage.get("items") or []:
                    if not isinstance(item, dict):
                        continue
                    wid = str(item.get("wordId") or "").strip()
                    rtype = str(item.get("runtimeType") or "")
                    if wid in word_map:
                        introduced.add(wid)
                        if rtype != "showWord":
                            practiced.add(wid)
            for sub in content.get("subLessons") or []:
                if not isinstance(sub, dict):
                    continue
                for stage in sub.get("stages") or []:
                    if not isinstance(stage, dict):
                        continue
                    for item in stage.get("items") or []:
                        if not isinstance(item, dict):
                            continue
                        wid = str(item.get("wordId") or "").strip()
                        rtype = str(item.get("runtimeType") or "")
                        if wid in word_map:
                            introduced.add(wid)
                            if rtype != "showWord":
                                practiced.add(wid)

    unsurfaced = []
    for wid in introduced:
        if wid not in practiced:
            w = word_map[wid]
            unsurfaced.append(
                {
                    "word_id": wid,
                    "id": wid,
                    "term": str(w.get("term") or w.get("word") or ""),
                }
            )

    return {
        "section_id": sid,
        "total_introduced": len(introduced),
        "surfaced_count": len(practiced),
        "unsurfaced_count": len(unsurfaced),
        "unsurfaced": unsurfaced,
    }


def _iter_lessons(section: dict[str, Any]):
    """Yield (unit, lesson) pairs in a section."""
    if not isinstance(section, dict):
        return
    for unit in section.get("units") or []:
        if not isinstance(unit, dict):
            continue
        for lesson in unit.get("lessons") or []:
            if isinstance(lesson, dict):
                yield unit, lesson


def evaluate_reading_passage(lesson: dict[str, Any]) -> dict[str, Any]:
    """Evaluate reading passage completeness for a lesson (K-18)."""
    if not isinstance(lesson, dict):
        return {"empty": False, "lesson_id": "", "reason": ""}
    lid = str(lesson.get("id") or "")
    if lesson.get("template") != "reading":
        return {"empty": False, "lesson_id": lid, "reason": ""}
    content = lesson.get("content")
    if not isinstance(content, dict):
        return {"empty": True, "lesson_id": lid, "reason": "缺少 content"}
    rp = content.get("readingPassage")
    if not isinstance(rp, dict):
        return {"empty": True, "lesson_id": lid, "reason": "缺少 readingPassage"}
    title = str(rp.get("title") or "").strip()
    if not title:
        return {"empty": True, "lesson_id": lid, "reason": "缺少标题"}
    paragraphs = rp.get("paragraphs")
    if not isinstance(paragraphs, list) or not paragraphs:
        return {"empty": True, "lesson_id": lid, "reason": "段落为空"}
    clean_paras = [str(p or "").strip() for p in paragraphs if str(p or "").strip()]
    if not clean_paras:
        return {"empty": True, "lesson_id": lid, "reason": "段落为空"}
    placeholders = {"…", "...", "tbd", "todo", "[待补]", "待补", "placeholder"}
    if all(p.lower() in placeholders for p in clean_paras):
        return {"empty": True, "lesson_id": lid, "reason": "包含占位文本"}
    return {"empty": False, "lesson_id": lid, "reason": ""}


# Re-export hygiene counters for callers that only need counts.
__all__ = [
    "ContentQualityIssue",
    "ContentQualityReport",
    "score_section",
    "format_quality_line",
    "build_quality_fix_hint",
    "issues_for_dimension",
    "build_quality_fix_hint_for_dimension",
    "count_placeholders",
    "count_needs_review",
    "count_empty_translations",
    "find_dangling_refs",
    "evaluate_unit_spiral",
    "evaluate_reading_passage",
    "_iter_lessons",
]
