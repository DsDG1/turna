"""AI section merge planning and validation services.

Decoupled from CourseAdapter.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

from src.backend import api
from src.backend.lesson_content import all_lesson_ids, all_unit_ids


@dataclass
class MergeAction:
    """A single unit/lesson merge decision.

    ``action`` is one of "add", "replace" or "skip".
    ``target_index`` is the position of the existing unit/lesson in the target
    section/unit; it is ``None`` for additions.
    """

    kind: str
    action: str
    incoming: dict[str, Any]
    target_index: int | None = None


@dataclass
class SectionMergePlan:
    """Planned merge of an AI-generated section into an existing section."""

    target_section_id: str | None
    incoming_section: dict[str, Any]
    added_units: list[MergeAction] = field(default_factory=list)
    replaced_units: list[MergeAction] = field(default_factory=list)
    added_lessons_by_unit: dict[str, list[MergeAction]] = field(default_factory=dict)
    replaced_lessons_by_unit: dict[str, list[MergeAction]] = field(default_factory=dict)


class CourseSectionMergeService:
    """Service handling section JSON validation and AI merge planning."""

    @staticmethod
    def validate_section_json(
        adapter: Any,
        section_json: dict[str, Any],
        *,
        check_existing_ids: bool = True,
    ) -> list[dict[str, str]]:
        """Validate an AI-generated section dict before importing it.

        Returns a list of problem dicts with keys ``level``, ``message``,
        ``path``.  Empty list means the section can be imported.

        When ``check_existing_ids`` is ``False``, unit/lesson ids are only
        checked for local duplicates *within* ``section_json`` and for empty
        values, not for collisions with the rest of the course. This is what
        AI merge paths need: the AI reuses existing ids on purpose, and the
        importer decides whether to overwrite or append.
        """
        problems: list[dict[str, str]] = []
        if not isinstance(section_json, dict):
            return [
                {"level": "error", "message": "section 必须是 JSON 对象", "path": ""}
            ]

        sid = section_json.get("id", "")
        if not sid:
            problems.append(
                {"level": "error", "message": "section id 不能为空", "path": "id"}
            )
        if check_existing_ids:
            existing_section_ids = {s.get("id") for s in adapter.sections}
            existing_index_ids = {
                e.get("id") for e in adapter.index.get("sections", [])
            }
            if sid and (sid in existing_section_ids or sid in existing_index_ids):
                problems.append(
                    {
                        "level": "error",
                        "message": f"section id「{sid}」已存在",
                        "path": "id",
                    }
                )

        if not section_json.get("name"):
            problems.append(
                {"level": "error", "message": "section name 不能为空", "path": "name"}
            )

        units = section_json.get("units")
        if not isinstance(units, list) or not units:
            problems.append(
                {
                    "level": "error",
                    "message": "section 必须包含非空的 units 数组",
                    "path": "units",
                }
            )
            return problems

        if len(units) > api.MAX_UNITS_PER_SECTION:
            problems.append(
                {
                    "level": "error",
                    "message": (
                        f"section 包含 {len(units)} 个单元，"
                        f"超过上限 {api.MAX_UNITS_PER_SECTION}"
                    ),
                    "path": "units",
                }
            )

        vocab_ids = {w.get("id") for w in adapter.vocab}
        expression_ids = {e.get("id") for e in adapter.expressions}
        grammar_ids = {g.get("id") for g in adapter.grammar_points}
        for w in section_json.get("words") or []:
            if isinstance(w, dict):
                vocab_ids.add(w.get("id"))
        for e in section_json.get("expressions") or []:
            if isinstance(e, dict):
                expression_ids.add(e.get("id"))
        for g in section_json.get("grammarPoints") or []:
            if isinstance(g, dict):
                grammar_ids.add(g.get("id"))
        if check_existing_ids:
            existing_unit_ids = all_unit_ids(adapter.sections)
            existing_lesson_ids = all_lesson_ids(adapter.sections)
        else:
            existing_unit_ids: set[str] = set()
            existing_lesson_ids: set[str] = set()

        local_unit_ids: set[str] = set()
        for unit in units:
            uid = unit.get("id", "")
            if not uid:
                problems.append(
                    {
                        "level": "error",
                        "message": "unit id 不能为空",
                        "path": "units",
                    }
                )
            elif uid in local_unit_ids or (
                check_existing_ids and uid in existing_unit_ids
            ):
                problems.append(
                    {
                        "level": "error",
                        "message": f"unit id「{uid}」重复或已存在",
                        "path": f"unit:{uid}",
                    }
                )
            else:
                local_unit_ids.add(uid)

            lessons = unit.get("lessons", [])
            if len(lessons) > api.MAX_LESSONS_PER_UNIT:
                problems.append(
                    {
                        "level": "error",
                        "message": (
                            f"unit {uid} 包含 {len(lessons)} 个课时，"
                            f"超过上限 {api.MAX_LESSONS_PER_UNIT}"
                        ),
                        "path": f"unit:{uid}",
                    }
                )

            local_lesson_ids: set[str] = set()
            for lesson in lessons:
                lid = lesson.get("id", "")
                if not lid:
                    problems.append(
                        {
                            "level": "error",
                            "message": f"unit {uid} 中存在空 lesson id",
                            "path": f"unit:{uid}",
                        }
                    )
                elif lid in local_lesson_ids or (
                    check_existing_ids and lid in existing_lesson_ids
                ):
                    problems.append(
                        {
                            "level": "error",
                            "message": f"lesson id「{lid}」重复或已存在",
                            "path": f"unit:{uid}/lesson:{lid}",
                        }
                    )
                else:
                    local_lesson_ids.add(lid)

                lesson_problems = api.validate_lesson(
                    lesson, vocab_ids, expression_ids, grammar_ids
                )
                for p in lesson_problems:
                    problems.append(
                        {
                            "level": p.level,
                            "message": p.message,
                            "path": p.path or f"unit:{uid}/lesson:{lid}",
                        }
                    )

        return problems

    @classmethod
    def plan_section_merge(
        cls,
        adapter: Any,
        target_section_id: str | None,
        incoming_section: dict[str, Any],
    ) -> SectionMergePlan:
        """Compute a merge plan for importing an AI-generated section."""
        plan = SectionMergePlan(
            target_section_id=target_section_id,
            incoming_section=incoming_section,
        )
        incoming_units = incoming_section.get("units") or []
        if not isinstance(incoming_units, list):
            return plan

        if target_section_id is None:
            for unit in incoming_units:
                if not isinstance(unit, dict):
                    continue
                uid = unit.get("id", "")
                if not uid:
                    continue
                plan.added_units.append(
                    MergeAction(kind="unit", action="add", incoming=unit)
                )
            return plan

        try:
            target_section = adapter.find_section(target_section_id)
        except KeyError:
            return cls.plan_section_merge(adapter, None, incoming_section)

        target_unit_index: dict[str, int] = {
            u.get("id"): i
            for i, u in enumerate(target_section.get("units") or [])
            if isinstance(u, dict) and u.get("id")
        }

        for unit in incoming_units:
            if not isinstance(unit, dict):
                continue
            uid = unit.get("id", "")
            if not uid:
                continue
            if uid in target_unit_index:
                plan.replaced_units.append(
                    MergeAction(
                        kind="unit",
                        action="replace",
                        incoming=unit,
                        target_index=target_unit_index[uid],
                    )
                )
                cls.plan_lesson_merge(plan, uid, unit, target_section)
            else:
                plan.added_units.append(
                    MergeAction(kind="unit", action="add", incoming=unit)
                )

        return plan

    @staticmethod
    def plan_lesson_merge(
        plan: SectionMergePlan,
        unit_id: str,
        incoming_unit: dict[str, Any],
        target_section: dict[str, Any],
    ) -> None:
        """Classify lessons inside a unit that already exists in the target."""
        target_unit = None
        for u in target_section.get("units") or []:
            if isinstance(u, dict) and u.get("id") == unit_id:
                target_unit = u
                break
        if target_unit is None:
            return

        target_lesson_index: dict[str, int] = {
            l.get("id"): i
            for i, l in enumerate(target_unit.get("lessons") or [])
            if isinstance(l, dict) and l.get("id")
        }

        for lesson in incoming_unit.get("lessons") or []:
            if not isinstance(lesson, dict):
                continue
            lid = lesson.get("id", "")
            if not lid:
                continue
            if lid in target_lesson_index:
                plan.replaced_lessons_by_unit.setdefault(unit_id, []).append(
                    MergeAction(
                        kind="lesson",
                        action="replace",
                        incoming=lesson,
                        target_index=target_lesson_index[lid],
                    )
                )
            else:
                plan.added_lessons_by_unit.setdefault(unit_id, []).append(
                    MergeAction(
                        kind="lesson", action="add", incoming=lesson
                    )
                )
