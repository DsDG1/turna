"""Structured quality scoring for textbook knowledge extraction.

Pure Python, no LLM calls. Given the chopped chapters and the extracted
``KnowledgePoints``, produce an ``ExtractionQualityReport`` with coverage,
duplicate-rate, consistency and language-check dimensions. The report is used
by the GUI to paint red/yellow badges on the review page.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Any, Literal

from src.backend.knowledge_schema import KnowledgePoints
from src.backend.markdown_chopper import Chapter

IssueKind = Literal["coverage", "duplicate", "consistency", "lang_check"]
ResourceType = Literal["word", "expression", "grammarPoint"]
Badge = Literal["error", "warning", "ok"]

_CJK_RE = re.compile(r"[\u4e00-\u9fff]")


def _normalise(text: str) -> str:
    """Lower-case, strip whitespace/punctuation for fuzzy duplicate checks."""
    return re.sub(r"[^\w\s]", "", text.lower()).strip()


def _contains_cjk(text: str) -> bool:
    """True if text contains CJK unified ideographs."""
    return bool(_CJK_RE.search(text))


def _is_cjk_language(language: str) -> bool:
    """Languages where CJK characters are expected in the term/title."""
    return language.lower() in {
        "chinese",
        "mandarin",
        "cantonese",
        "japanese",
        "korean",
    }


@dataclass(frozen=True)
class QualityIssue:
    """One concrete quality problem attached to a chapter/resource/field."""

    level: Literal["error", "warning"]
    kind: IssueKind
    message: str
    chapter_index: int
    resource_type: ResourceType | None = None
    resource_index: int | None = None
    field: str | None = None


@dataclass
class ChapterQuality:
    """Quality result for a single chapter."""

    chapter_index: int
    scores: dict[str, float] = field(default_factory=dict)
    issues: list[QualityIssue] = field(default_factory=list)


@dataclass
class ExtractionQualityReport:
    """Aggregate quality report for all kept chapters."""

    chapters: list[ChapterQuality] = field(default_factory=list)

    @property
    def overall(self) -> dict[str, Any]:
        """Return averaged scores plus total issue count."""
        if not self.chapters:
            return {}
        keys = ["coverage", "duplicate_rate", "consistency", "lang_check"]
        out: dict[str, Any] = {}
        for key in keys:
            values = [c.scores.get(key, 0.0) for c in self.chapters if key in c.scores]
            if values:
                out[key] = round(sum(values) / len(values), 3)
        error_count = sum(
            1 for c in self.chapters for i in c.issues if i.level == "error"
        )
        warning_count = sum(
            1 for c in self.chapters for i in c.issues if i.level == "warning"
        )
        out["error_count"] = error_count
        out["warning_count"] = warning_count
        out["issue_count"] = error_count + warning_count
        return out

    def badge_for_chapter(self, chapter_index: int) -> Badge:
        """Return the most severe badge level for a chapter."""
        for cq in self.chapters:
            if cq.chapter_index == chapter_index:
                if any(i.level == "error" for i in cq.issues):
                    return "error"
                if any(i.level == "warning" for i in cq.issues):
                    return "warning"
                return "ok"
        return "ok"

    def chapter_quality(self, chapter_index: int) -> ChapterQuality | None:
        for cq in self.chapters:
            if cq.chapter_index == chapter_index:
                return cq
        return None


def _resource_key(resource_type: ResourceType, entry: dict[str, Any]) -> tuple:
    """Key for duplicate detection.

    For words/expressions we compare both term and translation; for grammar
    points the title is enough.
    """
    if resource_type == "grammarPoint":
        return (resource_type, _normalise(entry.get("title", "")))
    return (
        resource_type,
        _normalise(entry.get("term", "")),
        _normalise(entry.get("translation", "")),
    )


def _resource_id(entry: dict[str, Any]) -> str:
    return str(entry.get("id", "")).strip()


def _collect_project_resources(
    chapters: list[tuple[Chapter, KnowledgePoints | None]],
) -> list[tuple[int, ResourceType, int, dict[str, Any]]]:
    """Flatten all project resources across chapters."""
    out: list[tuple[int, ResourceType, int, dict[str, Any]]] = []
    for ci, (_ch, kp) in enumerate(chapters):
        if kp is None:
            continue
        for i, w in enumerate(kp.words):
            out.append((ci, "word", i, w))
        for i, e in enumerate(kp.expressions):
            out.append((ci, "expression", i, e))
        for i, g in enumerate(kp.grammarPoints):
            out.append((ci, "grammarPoint", i, g))
    return out


def _existing_resource_keys(adapter: Any) -> dict[ResourceType, set[tuple]]:
    """Build duplicate-check keys from the loaded course adapter, if any."""
    keys: dict[ResourceType, set[tuple]] = {
        "word": set(),
        "expression": set(),
        "grammarPoint": set(),
    }
    if adapter is None:
        return keys
    for w in getattr(adapter, "vocab", []) or []:
        keys["word"].add(_resource_key("word", w))
    for e in getattr(adapter, "expressions", []) or []:
        keys["expression"].add(_resource_key("expression", e))
    for g in getattr(adapter, "grammar_points", []) or []:
        keys["grammarPoint"].add(_resource_key("grammarPoint", g))
    return keys


def _existing_expression_ids(adapter: Any) -> set[str]:
    """Return ids of expressions already present in the course."""
    if adapter is None:
        return set()
    return {
        str(e.get("id", "")).strip()
        for e in getattr(adapter, "expressions", []) or []
        if e.get("id")
    }


def _coverage_score(chapter: Chapter, kp: KnowledgePoints) -> tuple[float, list[QualityIssue]]:
    """Estimate coverage and emit low-coverage issues."""
    issues: list[QualityIssue] = []
    count = len(kp.words) + len(kp.expressions) + len(kp.grammarPoints)
    markdown_len = len(chapter.markdown.strip())
    # Heuristic: expect roughly one resource per 200 characters of chapter text.
    expected = max(1, markdown_len // 200)
    score = min(1.0, round(count / expected, 3))

    if count == 0:
        issues.append(
            QualityIssue(
                level="error",
                kind="coverage",
                message="本章未提取到任何知识点。",
                chapter_index=chapter.idx - 1,
            )
        )
    elif score < 0.3:
        issues.append(
            QualityIssue(
                level="warning",
                kind="coverage",
                message=f"覆盖率偏低（{count} 个知识点 / 约 {expected} 个预期）。",
                chapter_index=chapter.idx - 1,
            )
        )
    return score, issues


def _duplicate_issues(
    project_resources: list[tuple[int, ResourceType, int, dict[str, Any]]],
    adapter: Any,
) -> tuple[float, list[QualityIssue]]:
    """Detect intra-project and project-vs-course duplicates.

    Returns a duplicate-rate score (1.0 = no duplicates) and the issue list.
    """
    issues: list[QualityIssue] = []
    key_counts: dict[tuple, list[tuple[int, ResourceType, int]]] = {}
    for ci, rtype, ri, entry in project_resources:
        key = _resource_key(rtype, entry)
        key_counts.setdefault(key, []).append((ci, rtype, ri))

    existing_keys = _existing_resource_keys(adapter)
    duplicate_count = 0

    for key, occurrences in key_counts.items():
        if len(occurrences) > 1:
            duplicate_count += len(occurrences) - 1
            # Flag every duplicate occurrence beyond the first.
            for ci, rtype, ri in occurrences[1:]:
                issues.append(
                    QualityIssue(
                        level="warning",
                        kind="duplicate",
                        message="与项目内其他章节存在重复条目。",
                        chapter_index=ci,
                        resource_type=rtype,
                        resource_index=ri,
                    )
                )
        # Cross-check with existing course resources (only once per key).
        if key in existing_keys.get(key[0], set()):
            for ci, rtype, ri in occurrences:
                issues.append(
                    QualityIssue(
                        level="warning",
                        kind="duplicate",
                        message="与现有课程资源重复。",
                        chapter_index=ci,
                        resource_type=rtype,
                        resource_index=ri,
                    )
                )
                duplicate_count += 1

    total = len(project_resources)
    score = 1.0 if total == 0 else round(max(0.0, 1.0 - duplicate_count / total), 3)
    return score, issues


def _consistency_issues(
    project_resources: list[tuple[int, ResourceType, int, dict[str, Any]]],
    adapter: Any,
) -> tuple[float, list[QualityIssue]]:
    """Check cross-resource references (grammar exampleExpressionIds)."""
    issues: list[QualityIssue] = []
    project_expr_ids = {
        _resource_id(entry)
        for _ci, rtype, _ri, entry in project_resources
        if rtype == "expression" and _resource_id(entry)
    }
    valid_expr_ids = project_expr_ids | _existing_expression_ids(adapter)

    bad_count = 0
    for ci, rtype, ri, entry in project_resources:
        if rtype != "grammarPoint":
            continue
        refs = entry.get("exampleExpressionIds") or []
        for ref in refs:
            ref_id = str(ref).strip()
            if ref_id and ref_id not in valid_expr_ids:
                issues.append(
                    QualityIssue(
                        level="warning",
                        kind="consistency",
                        message=f"exampleExpressionIds 引用了不存在的表达式 id：{ref_id}",
                        chapter_index=ci,
                        resource_type=rtype,
                        resource_index=ri,
                        field="exampleExpressionIds",
                    )
                )
                bad_count += 1

    total = sum(1 for _ci, rtype, _ri, _e in project_resources if rtype == "grammarPoint")
    score = 1.0 if total == 0 else round(max(0.0, 1.0 - bad_count / total), 3)
    return score, issues


def _lang_check_issues(
    project_resources: list[tuple[int, ResourceType, int, dict[str, Any]]],
    language: str,
    source_language: str,
) -> tuple[float, list[QualityIssue]]:
    """Detect empty fields and obvious target/source language mix-ups."""
    issues: list[QualityIssue] = []
    bad_count = 0
    target_is_cjk = _is_cjk_language(language)
    source_is_cjk = _is_cjk_language(source_language)

    for ci, rtype, ri, entry in project_resources:
        if rtype in ("word", "expression"):
            term = str(entry.get("term", "")).strip()
            translation = str(entry.get("translation", "")).strip()
            if not term:
                issues.append(
                    QualityIssue(
                        level="error",
                        kind="lang_check",
                        message="term 为空。",
                        chapter_index=ci,
                        resource_type=rtype,
                        resource_index=ri,
                        field="term",
                    )
                )
                bad_count += 1
            if not translation:
                issues.append(
                    QualityIssue(
                        level="warning",
                        kind="lang_check",
                        message="translation 为空。",
                        chapter_index=ci,
                        resource_type=rtype,
                        resource_index=ri,
                        field="translation",
                    )
                )
                bad_count += 1
            # If target language is not CJK but the term contains CJK, suspect
            # source-language characters leaked into the term field.
            if not target_is_cjk and _contains_cjk(term):
                issues.append(
                    QualityIssue(
                        level="warning",
                        kind="lang_check",
                        message=f"term 中可能混入了 {source_language} 字符。",
                        chapter_index=ci,
                        resource_type=rtype,
                        resource_index=ri,
                        field="term",
                    )
                )
                bad_count += 1
        else:  # grammarPoint
            title = str(entry.get("title", "")).strip()
            explanation = str(entry.get("explanation", "")).strip()
            if not title:
                issues.append(
                    QualityIssue(
                        level="error",
                        kind="lang_check",
                        message="title 为空。",
                        chapter_index=ci,
                        resource_type=rtype,
                        resource_index=ri,
                        field="title",
                    )
                )
                bad_count += 1
            if not explanation:
                issues.append(
                    QualityIssue(
                        level="warning",
                        kind="lang_check",
                        message="explanation 为空。",
                        chapter_index=ci,
                        resource_type=rtype,
                        resource_index=ri,
                        field="explanation",
                    )
                )
                bad_count += 1
            if not target_is_cjk and _contains_cjk(title):
                issues.append(
                    QualityIssue(
                        level="warning",
                        kind="lang_check",
                        message=f"title 中可能混入了 {source_language} 字符。",
                        chapter_index=ci,
                        resource_type=rtype,
                        resource_index=ri,
                        field="title",
                    )
                )
                bad_count += 1

    total = len(project_resources)
    score = 1.0 if total == 0 else round(max(0.0, 1.0 - bad_count / total), 3)
    return score, issues


def compute_quality_report(
    chapters: list[tuple[Chapter, KnowledgePoints | None]],
    *,
    adapter: Any | None = None,
    language: str = "Turkish",
    source_language: str = "Chinese",
) -> ExtractionQualityReport:
    """Compute a full quality report for the extracted knowledge.

    ``chapters`` is a list of ``(Chapter, KnowledgePoints | None)`` tuples. The
    ``chapter.idx`` is expected to be 1-based; internally we use
    ``chapter.idx - 1`` for zero-based indexing.
    """
    project_resources = _collect_project_resources(chapters)
    dup_score, dup_issues = _duplicate_issues(project_resources, adapter)
    cons_score, cons_issues = _consistency_issues(project_resources, adapter)
    lang_score, lang_issues = _lang_check_issues(
        project_resources, language, source_language
    )

    chapter_qualities: list[ChapterQuality] = []
    for chapter, kp in chapters:
        ci = chapter.idx - 1
        if kp is None:
            chapter_qualities.append(
                ChapterQuality(
                    chapter_index=ci,
                    scores={},
                    issues=[
                        QualityIssue(
                            level="error",
                            kind="coverage",
                            message="本章尚未抽取或抽取失败。",
                            chapter_index=ci,
                        )
                    ],
                )
            )
            continue

        cov_score, cov_issues = _coverage_score(chapter, kp)
        chapter_dup_issues = [i for i in dup_issues if i.chapter_index == ci]
        chapter_cons_issues = [i for i in cons_issues if i.chapter_index == ci]
        chapter_lang_issues = [i for i in lang_issues if i.chapter_index == ci]

        chapter_qualities.append(
            ChapterQuality(
                chapter_index=ci,
                scores={
                    "coverage": cov_score,
                    "duplicate_rate": dup_score,
                    "consistency": cons_score,
                    "lang_check": lang_score,
                },
                issues=[
                    *cov_issues,
                    *chapter_dup_issues,
                    *chapter_cons_issues,
                    *chapter_lang_issues,
                ],
            )
        )

    return ExtractionQualityReport(chapters=chapter_qualities)
