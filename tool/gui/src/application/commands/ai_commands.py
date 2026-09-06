"""AI import/edit/merge undo commands with resource merge + rollback."""

from __future__ import annotations

import logging
from copy import deepcopy
from typing import TYPE_CHECKING, Any

from PySide6.QtGui import QUndoCommand

from src.application.commands._base import _make_changed, _remove_by_id

if TYPE_CHECKING:
    from src.backend.course_adapter import SectionMergePlan

logger = logging.getLogger(__name__)


class _ResourceMergeMixin:
    """Shared resource merge/rollback plumbing for AI import/edit commands.

    Tracks which vocab/expression/grammar ids a command added on redo so
    undo rolls back exactly those entries (earlier edits stay untouched).
    Expects ``self.adapter`` and calls ``_init_resource_tracking`` from
    ``__init__``.
    """

    def _init_resource_tracking(self) -> None:
        self.added_vocab_ids: set[str] = set()
        self.added_expression_ids: set[str] = set()
        self.added_grammar_ids: set[str] = set()

    def _snapshot_resource_ids(self) -> tuple[set[str], set[str], set[str]]:
        vocab_ids = {w.get("id", "") for w in self.adapter.vocab}
        expression_ids = {e.get("id", "") for e in self.adapter.expressions}
        grammar_ids = {g.get("id", "") for g in self.adapter.grammar_points}
        return vocab_ids, expression_ids, grammar_ids

    def _record_added_resources(self, old_ids: tuple[set[str], set[str], set[str]]) -> None:
        vocab_ids, expression_ids, grammar_ids = old_ids
        self.added_vocab_ids = {w.get("id", "") for w in self.adapter.vocab} - vocab_ids
        self.added_expression_ids = {
            e.get("id", "") for e in self.adapter.expressions
        } - expression_ids
        self.added_grammar_ids = {
            g.get("id", "") for g in self.adapter.grammar_points
        } - grammar_ids

    def _merge_resources_from(self, source_section: dict[str, Any]) -> None:
        # Snapshot before merging so undo can roll back exactly the entries
        # introduced here.
        old_ids = self._snapshot_resource_ids()
        self.adapter.merge_section_resources(source_section)
        self._record_added_resources(old_ids)

    def _rollback_resources(self) -> None:
        self.adapter.vocab = [
            w for w in self.adapter.vocab if w.get("id", "") not in self.added_vocab_ids
        ]
        self.adapter.expressions = [
            e
            for e in self.adapter.expressions
            if e.get("id", "") not in self.added_expression_ids
        ]
        self.adapter.grammar_points = [
            g
            for g in self.adapter.grammar_points
            if g.get("id", "") not in self.added_grammar_ids
        ]


class ImportAiSectionCommand(_ResourceMergeMixin, QUndoCommand):
    """Append an AI-generated section + merge its resources + add index entry.

    Undo removes the section and index entry; merged resources are NOT rolled
    back (consistent with the existing import behavior; validate-on-save will
    catch any dangling references).
    """

    def __init__(self, adapter, section_json: dict[str, Any]) -> None:
        super().__init__("AI 导入 Section")
        self.adapter = adapter
        self.section_json = deepcopy(section_json)
        self.section_id: str = section_json.get("id", "")
        self.signals = _make_changed()
        self._init_resource_tracking()

    def redo(self) -> None:
        sid = self.section_json.get("id", "")
        self.adapter.sections.append(deepcopy(self.section_json))
        self._merge_resources_from(self.section_json)
        self.adapter.index.setdefault("sections", []).append(
            {
                "id": sid,
                "name": self.section_json.get("name", sid),
                "description": self.section_json.get("description", ""),
                "level": self.section_json.get("level", ""),
                "prerequisiteSectionIds": self.section_json.get(
                    "prerequisiteSectionIds", []
                ),
                "file": f"sections/{sid}.json",
            }
        )
        self.signals.changed.emit()

    def undo(self) -> None:
        try:
            self.adapter.delete_section(self.section_id)
        except KeyError:
            logger.debug("application/commands.py:undo best-effort step failed", exc_info=True)
        self._rollback_resources()
        self.signals.changed.emit()


class AiEditSectionCommand(_ResourceMergeMixin, QUndoCommand):
    """Replace an existing section with an AI-edited version. Undo restores.

    If ``resource_section`` is provided, its top-level words/expressions/
    grammarPoints are merged into the course resources on redo and rolled back
    on undo.
    """

    def __init__(
        self,
        adapter,
        section_id: str,
        new_section: dict[str, Any],
        resource_section: dict[str, Any] | None = None,
    ) -> None:
        super().__init__("AI 编辑 Section")
        self.adapter = adapter
        self.section_id = section_id
        self.new_section = deepcopy(new_section)
        self.resource_section = deepcopy(resource_section) if resource_section else None
        self.old_section: dict[str, Any] | None = None
        self.signals = _make_changed()
        self._init_resource_tracking()

    def _merge_resources(self) -> None:
        if self.resource_section is not None:
            self._merge_resources_from(self.resource_section)

    def redo(self) -> None:
        if self.old_section is None:
            self.old_section = deepcopy(self.adapter.find_section(self.section_id))
        self._merge_resources()
        self.adapter.replace_section(self.section_id, deepcopy(self.new_section))
        self.signals.changed.emit()

    def undo(self) -> None:
        if self.old_section is not None:
            self.adapter.replace_section(self.section_id, deepcopy(self.old_section))
        self._rollback_resources()
        self.signals.changed.emit()


class MergeAiSectionCommand(_ResourceMergeMixin, QUndoCommand):
    """Merge an AI-generated section into an existing section with user control.

    The ``plan`` describes which units/lessons to replace, add, or skip.
    Top-level words/expressions/grammarPoints from the incoming section are
    merged into the course resources. Undo restores the old section and rolls
    back any resources introduced by this merge.
    """

    def __init__(
        self,
        adapter,
        plan: "SectionMergePlan",
    ) -> None:
        super().__init__("AI 合并 Section")
        self.adapter = adapter
        self.plan = plan
        self.incoming_section = deepcopy(plan.incoming_section)
        self.section_id: str = plan.target_section_id or ""
        self.signals = _make_changed()
        self.old_section: dict[str, Any] | None = None
        self._init_resource_tracking()

    def _merge_resources(self) -> None:
        self._merge_resources_from(self.incoming_section)

    def _apply_plan(self) -> None:
        target = self.adapter.find_section(self.section_id)
        target_units = target.setdefault("units", [])

        # Replace existing units lesson-by-lesson so the user can uncheck
        # individual lessons in the preview. Unit-level metadata is updated
        # from the incoming unit, but lessons that are not listed in the plan
        # are left untouched (no deletion).
        for action in self.plan.replaced_units:
            if action.action == "skip":
                continue
            idx = action.target_index
            if idx is None or not (0 <= idx < len(target_units)):
                continue
            incoming_unit = action.incoming
            target_unit = target_units[idx]
            target_unit["name"] = incoming_unit.get("name", target_unit.get("name", ""))
            target_unit["description"] = incoming_unit.get(
                "description", target_unit.get("description", "")
            )
            unit_id = incoming_unit.get("id", "")
            lessons = target_unit.setdefault("lessons", [])

            for lesson_action in self.plan.replaced_lessons_by_unit.get(unit_id, []):
                if lesson_action.action == "skip":
                    continue
                lidx = lesson_action.target_index
                if lidx is None or not (0 <= lidx < len(lessons)):
                    continue
                lessons[lidx] = deepcopy(lesson_action.incoming)
            for lesson_action in self.plan.added_lessons_by_unit.get(unit_id, []):
                if lesson_action.action == "skip":
                    continue
                lessons.append(deepcopy(lesson_action.incoming))

        # Add new units (their lessons are included in the unit dict).
        for action in self.plan.added_units:
            if action.action == "skip":
                continue
            target_units.append(deepcopy(action.incoming))

    def redo(self) -> None:
        if self.old_section is None:
            self.old_section = deepcopy(self.adapter.find_section(self.section_id))
        self._merge_resources()
        self._apply_plan()
        # Sync section metadata to the index entry.
        for entry in self.adapter.index.setdefault("sections", []):
            if entry.get("id") == self.section_id:
                entry["name"] = self.incoming_section.get("name", entry.get("name", ""))
                entry["description"] = self.incoming_section.get(
                    "description", entry.get("description", "")
                )
                entry["level"] = self.incoming_section.get("level", entry.get("level", ""))
                entry["prerequisiteSectionIds"] = self.incoming_section.get(
                    "prerequisiteSectionIds", entry.get("prerequisiteSectionIds", [])
                )
                break
        self.signals.changed.emit()

    def undo(self) -> None:
        if self.old_section is not None:
            self.adapter.replace_section(self.section_id, deepcopy(self.old_section))
        self._rollback_resources()
        self.signals.changed.emit()


class AiEditUnitCommand(_ResourceMergeMixin, QUndoCommand):
    """Replace a single unit within a section with an AI-edited version.

    If ``resource_section`` is provided, its top-level words/expressions/
    grammarPoints are merged into the course resources on redo and rolled back
    on undo.
    """

    def __init__(
        self,
        adapter,
        section_id: str,
        unit_id: str,
        new_unit: dict[str, Any],
        resource_section: dict[str, Any] | None = None,
    ) -> None:
        super().__init__("AI 编辑 Unit")
        self.adapter = adapter
        self.section_id = section_id
        self.unit_id = unit_id
        self.new_unit = deepcopy(new_unit)
        self.resource_section = deepcopy(resource_section) if resource_section else None
        self.old_unit: dict[str, Any] | None = None
        self.signals = _make_changed()
        self._init_resource_tracking()

    def _merge_resources(self) -> None:
        if self.resource_section is not None:
            self._merge_resources_from(self.resource_section)

    def redo(self) -> None:
        if self.old_unit is None:
            _section, unit = self.adapter.find_unit(self.unit_id)
            self.old_unit = deepcopy(unit)
        self._merge_resources()
        self.adapter.replace_unit(
            self.section_id, self.unit_id, deepcopy(self.new_unit)
        )
        self.signals.changed.emit()

    def undo(self) -> None:
        if self.old_unit is not None:
            self.adapter.replace_unit(
                self.section_id, self.unit_id, deepcopy(self.old_unit)
            )
        self._rollback_resources()
        self.signals.changed.emit()


class AiEditLessonCommand(_ResourceMergeMixin, QUndoCommand):
    """Replace a single lesson with an AI-edited version.

    If ``resource_section`` is provided, its top-level words/expressions/
    grammarPoints are merged into the course resources on redo and rolled back
    on undo.
    """

    def __init__(
        self,
        adapter,
        lesson_id: str,
        new_lesson: dict[str, Any],
        resource_section: dict[str, Any] | None = None,
    ) -> None:
        super().__init__("AI 编辑 Lesson")
        self.adapter = adapter
        self.lesson_id = lesson_id
        self.new_lesson = deepcopy(new_lesson)
        self.resource_section = deepcopy(resource_section) if resource_section else None
        self.old_lesson: dict[str, Any] | None = None
        self.signals = _make_changed()
        self._init_resource_tracking()

    def _merge_resources(self) -> None:
        if self.resource_section is not None:
            self._merge_resources_from(self.resource_section)

    def redo(self) -> None:
        if self.old_lesson is None:
            _s, _u, lesson = self.adapter.find_lesson(self.lesson_id)
            self.old_lesson = deepcopy(lesson)
        self._merge_resources()
        self.adapter.replace_lesson(self.lesson_id, deepcopy(self.new_lesson))
        self.signals.changed.emit()

    def undo(self) -> None:
        if self.old_lesson is not None:
            self.adapter.replace_lesson(self.lesson_id, deepcopy(self.old_lesson))
        self._rollback_resources()
        self.signals.changed.emit()


class AppendUnitsToSectionCommand(_ResourceMergeMixin, QUndoCommand):
    """Append several fresh-id units to a section + merge draft resources.

    Used by the workshop "import into existing section" path: each unit has
    already been cloned with fresh ids by the caller, so it cannot collide
    with the existing course. The draft's top-level words/expressions/
    grammarPoints are merged on redo and rolled back on undo.
    """

    def __init__(
        self,
        adapter,
        section_id: str,
        units: list[dict[str, Any]],
        resource_section: dict[str, Any] | None = None,
    ) -> None:
        super().__init__("添加 Unit（工坊导入）")
        self.adapter = adapter
        self.section_id = section_id
        self.units = [deepcopy(u) for u in units]
        self.resource_section = deepcopy(resource_section) if resource_section else None
        self.appended_ids: list[str] = []
        self.signals = _make_changed()
        self._init_resource_tracking()

    def redo(self) -> None:
        if self.resource_section is not None:
            self._merge_resources_from(self.resource_section)
        section = self.adapter.find_section(self.section_id)
        target = section.setdefault("units", [])
        self.appended_ids = []
        for unit in self.units:
            target.append(deepcopy(unit))
            self.appended_ids.append(unit.get("id", ""))
        self.signals.changed.emit()

    def undo(self) -> None:
        section = self.adapter.find_section(self.section_id)
        units = section.get("units", [])
        for uid in self.appended_ids:
            _remove_by_id(units, uid)
        self._rollback_resources()
        self.signals.changed.emit()


class AppendLessonsToUnitCommand(_ResourceMergeMixin, QUndoCommand):
    """Append several fresh-id lessons to a unit + merge draft resources.

    Used by the workshop "import into existing unit" path: each lesson has
    already been cloned with fresh ids by the caller. The draft's top-level
    words/expressions/grammarPoints are merged on redo and rolled back on
    undo.
    """

    def __init__(
        self,
        adapter,
        unit_id: str,
        lessons: list[dict[str, Any]],
        resource_section: dict[str, Any] | None = None,
    ) -> None:
        super().__init__("添加 Lesson（工坊导入）")
        self.adapter = adapter
        self.unit_id = unit_id
        self.lessons = [deepcopy(l) for l in lessons]
        self.resource_section = deepcopy(resource_section) if resource_section else None
        self.appended_ids: list[str] = []
        self.signals = _make_changed()
        self._init_resource_tracking()

    def redo(self) -> None:
        if self.resource_section is not None:
            self._merge_resources_from(self.resource_section)
        _s, unit = self.adapter.find_unit(self.unit_id)
        target = unit.setdefault("lessons", [])
        self.appended_ids = []
        for lesson in self.lessons:
            target.append(deepcopy(lesson))
            self.appended_ids.append(lesson.get("id", ""))
        self.signals.changed.emit()

    def undo(self) -> None:
        _s, unit = self.adapter.find_unit(self.unit_id)
        lessons = unit.get("lessons", [])
        for lid in self.appended_ids:
            _remove_by_id(lessons, lid)
        self._rollback_resources()
        self.signals.changed.emit()

