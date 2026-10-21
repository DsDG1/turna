"""Application facade for course planning (P0-2).

The plan window lives in ``src/widgets`` and must not import ``src.backend``
directly (``ui_backend`` is a ratchet). This service is the seam: it owns the
store and the pure plan module, and exposes only plain data / dataclasses to
the UI.
"""
from __future__ import annotations

import logging
from datetime import datetime
from typing import Any

from src.backend.ai.course_plan import (
    CEFR_LEVELS,
    CoursePlan,
    CoursePlanSpec,
    generate_course_plan,
    plan_section_to_spec,
    validate_plan,
)
from src.backend.ai.facade import generate_course
from src.backend.course_plan_store import CoursePlanStore

logger = logging.getLogger(__name__)

#: Re-exported so the planner window can populate its level combos without
#: importing the backend module.
PLAN_LEVELS: tuple[str, ...] = CEFR_LEVELS


def next_level(level: str) -> str:
    """Return the next CEFR level, capped at C2."""
    try:
        index = CEFR_LEVELS.index(str(level).upper())
    except ValueError:
        return "A2"
    return CEFR_LEVELS[min(index + 1, len(CEFR_LEVELS) - 1)]


class CoursePlanService:
    """Course-plan generation + persistence seam for the planner window."""

    def __init__(
        self,
        adapter: Any,
        store: CoursePlanStore | None = None,
    ) -> None:
        self._adapter = adapter
        self._store = store or CoursePlanStore()

    # --- defaults -------------------------------------------------------

    def default_spec(self) -> CoursePlanSpec:
        index = getattr(self._adapter, "index", None) or {}
        language = str(
            index.get("displayName")
            or index.get("language")
            or "Turkish"
        )
        level = str(index.get("level") or "A1").upper()
        if level not in CEFR_LEVELS:
            level = "A1"
        return CoursePlanSpec(
            language=language,
            source_language="Chinese",
            topic="",
            level_from=level,
            level_to=next_level(level),
            section_count=6,
            lessons_per_section=9,
            word_budget=240,
        )

    def build_spec(
        self,
        *,
        language: str,
        source_language: str,
        topic: str,
        level_from: str,
        level_to: str,
        section_count: int,
        lessons_per_section: int,
        word_budget: int,
        can_do: list[str],
        constraints: str,
    ) -> CoursePlanSpec:
        """Build a spec from plain form values (window → service seam)."""
        return CoursePlanSpec(
            language=str(language or "Turkish"),
            source_language=str(source_language or "Chinese"),
            topic=str(topic or ""),
            level_from=str(level_from or "A1"),
            level_to=str(level_to or "A2"),
            section_count=int(section_count),
            lessons_per_section=int(lessons_per_section),
            word_budget=int(word_budget),
            can_do=[str(x) for x in can_do],
            constraints=str(constraints or ""),
        )

    # --- generation -----------------------------------------------------

    def generate(
        self,
        config: Any,
        spec: CoursePlanSpec,
        *,
        course_dir: str = "",
        timeout: float = 120.0,
        temperature: float = 0.4,
        max_retries: int = 1,
        cancel_check: Any = None,
        on_chunk: Any = None,
        usage_callback: Any = None,
    ) -> CoursePlan:
        return generate_course_plan(
            config,
            spec,
            course_dir=course_dir,
            timeout=timeout,
            temperature=temperature,
            max_retries=max_retries,
            cancel_check=cancel_check,
            on_chunk=on_chunk,
            usage_callback=usage_callback,
        )

    def validate(self, plan: CoursePlan) -> list[str]:
        return validate_plan(plan)

    # --- per-section generation (P0-3) ---------------------------------

    def generate_section(
        self,
        config: Any,
        plan: CoursePlan,
        section_id: str,
        *,
        mode: str = "fast",
        timeout: float = 120.0,
        temperature: float = 0.4,
        max_retries: int = 1,
        cancel_check: Any = None,
        on_chunk: Any = None,
        usage_callback: Any = None,
    ) -> dict[str, Any]:
        """Generate one section draft through the single facade entry.

        Returns the section dict; never imports or writes the course.
        """
        spec = self.section_spec(plan, section_id)
        validator = getattr(self._adapter, "validate_section_json", None)
        if callable(validator):
            def _validate(draft: dict[str, Any]) -> list:
                return validator(draft, check_existing_ids=False)
        else:
            def _validate(_draft: dict[str, Any]) -> list:
                return []

        result = generate_course(
            config,
            spec,
            mode=mode,
            validator=_validate,
            timeout=timeout,
            temperature=temperature,
            max_retries=max_retries,
            cancel_check=cancel_check,
            on_chunk=on_chunk,
            usage_callback=usage_callback,
        )
        draft = getattr(result, "draft", None)
        if not isinstance(draft, dict):
            raise RuntimeError(
                getattr(result, "error", "") or "模型没有返回可用的 section 草稿。"
            )
        return draft

    # --- persistence ----------------------------------------------------

    def save(self, plan: CoursePlan) -> str:
        return self._store.save_plan(plan)

    def load(self, plan_id: str) -> CoursePlan | None:
        return self._store.load_plan(plan_id)

    def summaries(self) -> list[dict[str, Any]]:
        return self._store.list_summaries()

    def delete(self, plan_id: str) -> bool:
        return self._store.delete_plan(plan_id)

    def save_draft(
        self, plan: CoursePlan, section_id: str, draft: dict[str, Any]
    ) -> str:
        """Persist the plan (progress included) and its section draft."""
        plan_id = self._store.save_plan(plan)
        self._store.save_draft(plan_id, section_id, draft)
        return plan_id

    def load_draft(
        self, plan: CoursePlan, section_id: str
    ) -> dict[str, Any] | None:
        if not plan.plan_id:
            return None
        return self._store.load_draft(plan.plan_id, section_id)

    def delete_draft(self, plan: CoursePlan, section_id: str) -> bool:
        if not plan.plan_id:
            return False
        return self._store.delete_draft(plan.plan_id, section_id)

    def mark_progress(
        self,
        plan: CoursePlan,
        section_id: str,
        *,
        status: str,
        usage: int = 0,
        final_section_id: str = "",
    ) -> None:
        """Update one section's runtime status on the plan (caller saves)."""
        entry = dict(plan.progress.get(section_id) or {})
        entry["status"] = str(status)
        entry["updated_at"] = datetime.now().isoformat(timespec="seconds")
        if usage:
            entry["usage"] = int(usage)
            plan.usage_total = int(plan.usage_total) + int(usage)
        if final_section_id:
            entry["final_section_id"] = str(final_section_id)
        plan.progress[section_id] = entry

    # --- per-section spec (P0-3 entry point) ----------------------------

    def section_spec(self, plan: CoursePlan, section_id: str):
        existing = {
            "vocab": list(getattr(self._adapter, "vocab", None) or []),
            "expressions": list(
                getattr(self._adapter, "expressions", None) or []
            ),
            "grammarPoints": list(
                getattr(self._adapter, "grammar_points", None) or []
            ),
        }
        return plan_section_to_spec(
            plan, section_id, existing_resources=existing
        )
