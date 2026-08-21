"""Narrow precognition cache for immersive (P5) — pure, never raises.

Caches local Soft hygiene fingerprints and empty/low-quality readiness.
Does not run network LLM generation. Budget gate is caller's responsibility.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Mapping


@dataclass
class PrecogCache:
    """Session cache; mark_stale clears all."""

    soft_fix_count: int | None = None
    empty_lesson_ids: tuple[str, ...] = ()
    weak_section_ids: tuple[str, ...] = ()
    fingerprint: str = ""
    hits: int = 0
    misses: int = 0
    skipped_budget: int = 0
    _stale: bool = True

    def mark_stale(self) -> None:
        self._stale = True
        self.soft_fix_count = None
        self.empty_lesson_ids = ()
        self.weak_section_ids = ()
        self.fingerprint = ""

    @property
    def is_stale(self) -> bool:
        return bool(self._stale)


def compute_fingerprint(
    *,
    empty_lessons: list[str] | None = None,
    quality_by_section: Mapping[str, float] | None = None,
    soft_count: int | None = None,
) -> str:
    try:
        empty = ",".join(sorted(str(x) for x in (empty_lessons or [])[:40]))
        weak = ",".join(
            sorted(
                sid
                for sid, m in (quality_by_section or {}).items()
                if m is not None and float(m) < 0.7
            )[:40]
        )
        return f"e={empty}|w={weak}|s={soft_count}"
    except Exception:
        return ""


def refresh_local_precog(
    cache: PrecogCache,
    *,
    adapter: Any = None,
    empty_lessons: list[str] | None = None,
    quality_by_section: Mapping[str, float] | None = None,
    budget_ok: bool = True,
) -> str:
    """Recompute local precog; returns 'hit'|'miss'|'skip_budget'|'error'."""
    if cache is None:
        return "error"
    if not budget_ok:
        cache.skipped_budget += 1
        return "skip_budget"
    try:
        soft_count = None
        if adapter is not None:
            try:
                from src.backend.experience.soft_autopilot import evaluate_soft_fixes

                batch = evaluate_soft_fixes(adapter)
                soft_count = len(getattr(batch, "fixes", None) or [])
            except Exception:
                soft_count = None
        empty = list(empty_lessons or [])
        quality = dict(quality_by_section or {})
        weak = tuple(
            sorted(
                sid
                for sid, m in quality.items()
                if m is not None and float(m) < 0.7
            )[:40]
        )
        fp = compute_fingerprint(
            empty_lessons=empty,
            quality_by_section=quality,
            soft_count=soft_count,
        )
        if not cache._stale and cache.fingerprint == fp:
            cache.hits += 1
            return "hit"
        cache.soft_fix_count = soft_count
        cache.empty_lesson_ids = tuple(str(x) for x in empty[:40])
        cache.weak_section_ids = weak
        cache.fingerprint = fp
        cache._stale = False
        cache.misses += 1
        return "miss"
    except Exception:
        return "error"


def get_or_create_precog(host: Any) -> PrecogCache:
    """Attach a PrecogCache on host if missing."""
    try:
        c = getattr(host, "_precog_cache", None)
        if isinstance(c, PrecogCache):
            return c
        c = PrecogCache()
        host._precog_cache = c
        return c
    except Exception:
        return PrecogCache()
