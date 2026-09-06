"""Extraction pipeline, worker creation, and usage tracking for textbook import."""
from __future__ import annotations

import time
from typing import Any, Callable

from src.backend.knowledge_extractor import (
    extract_knowledge_points_windowed,
    reextract_knowledge_targeted,
)
from src.backend.knowledge_schema import KnowledgePoints
from src.backend.markdown_chopper import Chapter
from src.backend.textbook_presets import TextbookPreset

UsageDict = dict[str, int]
_ZERO_USAGE: UsageDict = {"prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0}


def make_extraction_worker(
    worker_factory: Callable[..., Any],
    ai_config: Any,
    language: str,
    source_language: str,
    chapter: Chapter,
    preset: TextbookPreset,
    strategy: str,
    idx: int,
) -> Any:
    """Create and configure an extraction worker for chapter ``idx``."""
    worker = worker_factory(
        extract_knowledge_points_windowed,
        ai_config,
        language,
        source_language,
        chapter,
        strategy=strategy,
        temperature=preset.temperature,
        max_tokens=preset.max_tokens,
        max_chapter_chars=preset.max_chapter_chars,
        max_window_chars=preset.window_chars,
        overlap_chars=preset.overlap_chars,
        max_retries=1,
    )
    worker._chapter_idx = idx
    worker._extract_strategy = strategy
    worker._worker_kind = "extract"
    return worker


def make_targeted_reextract_worker(
    worker_factory: Callable[..., Any],
    ai_config: Any,
    language: str,
    source_language: str,
    chapter: Chapter,
    knowledge: KnowledgePoints,
    issues: list[str],
    preset: TextbookPreset,
    idx: int,
) -> Any:
    """Create and configure a targeted re-extraction worker for chapter ``idx``."""
    worker = worker_factory(
        reextract_knowledge_targeted,
        ai_config,
        language,
        source_language,
        chapter,
        knowledge,
        issues,
        temperature=preset.temperature,
        max_tokens=preset.max_tokens,
        max_retries=1,
    )
    return worker


def accumulate_usage(
    usage_by_chapter: dict[int, UsageDict],
    idx: int,
    usage: UsageDict,
) -> tuple[UsageDict, UsageDict]:
    """Accumulate per-chapter and total project token usage."""
    if not isinstance(usage, dict):
        return dict(usage_by_chapter.get(idx, _ZERO_USAGE)), {
            k: sum(c.get(k, 0) for c in usage_by_chapter.values())
            for k in ("prompt_tokens", "completion_tokens", "total_tokens")
        }
    cur = usage_by_chapter.get(idx, _ZERO_USAGE)
    merged: UsageDict = {
        k: int(cur.get(k, 0)) + int(usage.get(k, 0) or 0)
        for k in ("prompt_tokens", "completion_tokens", "total_tokens")
    }
    usage_by_chapter[idx] = merged
    project_usage: UsageDict = {
        k: sum(c.get(k, 0) for c in usage_by_chapter.values())
        for k in ("prompt_tokens", "completion_tokens", "total_tokens")
    }
    return merged, project_usage


def estimate_remaining_seconds(
    start_time: float | None,
    completed: int,
    total: int,
) -> int | None:
    """Linear estimate of remaining extraction time, or None if unknown."""
    if start_time is None or completed <= 0:
        return None
    elapsed = time.monotonic() - start_time
    per_chapter = elapsed / completed
    remaining = total - completed
    return max(1, int(round(per_chapter * remaining)))


def apply_reviewed_rows(
    chapters: list[Any],
    rows: list[tuple[int, str, dict[str, Any]]],
) -> None:
    """Replace each chapter's knowledge with curated review rows."""
    for cr in chapters:
        if cr.knowledge is not None:
            cr.knowledge.words = []
            cr.knowledge.expressions = []
            cr.knowledge.grammarPoints = []
    for ci, rtype, entry in rows:
        if not (0 <= ci < len(chapters)):
            continue
        cr = chapters[ci]
        if cr.knowledge is None:
            cr.knowledge = KnowledgePoints()
        if rtype == "word":
            cr.knowledge.words.append(entry)
        elif rtype == "expression":
            cr.knowledge.expressions.append(entry)
        elif rtype == "grammarPoint":
            cr.knowledge.grammarPoints.append(entry)
