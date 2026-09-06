"""Tree-level structural undo commands: sections, units, lessons, bulk ops."""

from __future__ import annotations

import logging
from copy import deepcopy
from typing import Any

from PySide6.QtGui import QUndoCommand

from src.backend.course_adapter import CourseAdapter

from src.application.commands._base import _make_changed, _remove_by_id

logger = logging.getLogger(__name__)


class NewUnitCommand(QUndoCommand):
    """Add a new unit to a section. Undo removes it."""

    def __init__(self, adapter, section_id: str, name: str = "New unit") -> None:
        super().__init__("新建 Unit")
        self.adapter = adapter
        self.section_id = section_id
        self._name = name
        self.unit_id: str | None = None
        self.signals = _make_changed()

    def redo(self) -> None:
        self.unit_id = self.adapter.new_unit(self.section_id, self._name)
        self.signals.changed.emit()

    def undo(self) -> None:
        if self.unit_id is not None:
            self.adapter.delete_unit(self.unit_id)
        self.signals.changed.emit()


class DeleteUnitCommand(QUndoCommand):
    """Delete a unit. Undo restores it to its original position."""

    def __init__(self, adapter, unit_id: str) -> None:
        super().__init__("删除 Unit")
        self.adapter = adapter
        self.unit_id = unit_id
        self.section_id: str | None = None
        self.index: int = -1
        self.snapshot: dict[str, Any] | None = None
        self.signals = _make_changed()

    def redo(self) -> None:
        section, unit = self.adapter.find_unit(self.unit_id)
        self.section_id = section.get("id", "")
        units = section.get("units", [])
        for i, u in enumerate(units):
            if u.get("id") == self.unit_id:
                self.index = i
                break
        self.snapshot = deepcopy(unit)
        self.adapter.delete_unit(self.unit_id)
        self.signals.changed.emit()

    def undo(self) -> None:
        if self.snapshot is None or self.section_id is None:
            return
        section = self.adapter.find_section(self.section_id)
        units = section.setdefault("units", [])
        if 0 <= self.index <= len(units):
            units.insert(self.index, deepcopy(self.snapshot))
        else:
            units.append(deepcopy(self.snapshot))
        self.signals.changed.emit()


class NewLessonCommand(QUndoCommand):
    """Add a new lesson (from a template) to a unit. Undo removes it."""

    def __init__(self, adapter, unit_id: str, template: str, name: str = "") -> None:
        super().__init__("新建 Lesson")
        self.adapter = adapter
        self.unit_id = unit_id
        self.template = template
        self._name = name
        self.lesson_id: str | None = None
        self.signals = _make_changed()

    def redo(self) -> None:
        self.lesson_id = self.adapter.new_lesson(self.unit_id, self.template)
        if self._name and self.lesson_id:
            _s, _u, lesson = self.adapter.find_lesson(self.lesson_id)
            lesson["name"] = self._name
        self.signals.changed.emit()

    def undo(self) -> None:
        if self.lesson_id is not None:
            self.adapter.delete_lesson(self.lesson_id)
        self.signals.changed.emit()


class AppendLessonCommand(QUndoCommand):
    """Append an externally-built lesson to a unit. Undo removes it."""

    def __init__(self, adapter, unit_id: str, lesson: dict[str, Any]) -> None:
        super().__init__("添加 Lesson")
        self.adapter = adapter
        self.unit_id = unit_id
        self.lesson = deepcopy(lesson)
        self.lesson_id: str = lesson.get("id", "")
        self.signals = _make_changed()

    def redo(self) -> None:
        _section, unit = self.adapter.find_unit(self.unit_id)
        unit.setdefault("lessons", []).append(deepcopy(self.lesson))
        self.signals.changed.emit()

    def undo(self) -> None:
        _section, unit = self.adapter.find_unit(self.unit_id)
        lessons = unit.get("lessons", [])
        _remove_by_id(lessons, self.lesson_id)
        self.signals.changed.emit()


class AppendUnitCommand(QUndoCommand):
    """Append an externally-built unit to a section. Undo removes it."""

    def __init__(self, adapter, section_id: str, unit: dict[str, Any]) -> None:
        super().__init__("添加 Unit")
        self.adapter = adapter
        self.section_id = section_id
        self.unit = deepcopy(unit)
        self.unit_id: str = unit.get("id", "")
        self.signals = _make_changed()

    def redo(self) -> None:
        section = self.adapter.find_section(self.section_id)
        section.setdefault("units", []).append(deepcopy(self.unit))
        self.signals.changed.emit()

    def undo(self) -> None:
        section = self.adapter.find_section(self.section_id)
        units = section.get("units", [])
        _remove_by_id(units, self.unit_id)
        self.signals.changed.emit()


class DeleteLessonCommand(QUndoCommand):
    """Delete a lesson. Undo restores it to its original position."""

    def __init__(self, adapter, lesson_id: str) -> None:
        super().__init__("删除 Lesson")
        self.adapter = adapter
        self.lesson_id = lesson_id
        self.section_id: str | None = None
        self.unit_id: str | None = None
        self.index: int = -1
        self.snapshot: dict[str, Any] | None = None
        self.signals = _make_changed()

    def redo(self) -> None:
        section, unit, lesson = self.adapter.find_lesson(self.lesson_id)
        self.section_id = section.get("id", "")
        self.unit_id = unit.get("id", "")
        lessons = unit.get("lessons", [])
        for i, l in enumerate(lessons):
            if l.get("id") == self.lesson_id:
                self.index = i
                break
        self.snapshot = deepcopy(lesson)
        self.adapter.delete_lesson(self.lesson_id)
        self.signals.changed.emit()

    def undo(self) -> None:
        if self.snapshot is None or self.unit_id is None:
            return
        _section, unit = self.adapter.find_unit(self.unit_id)
        lessons = unit.setdefault("lessons", [])
        if 0 <= self.index <= len(lessons):
            lessons.insert(self.index, deepcopy(self.snapshot))
        else:
            lessons.append(deepcopy(self.snapshot))
        self.signals.changed.emit()


class DeleteSectionCommand(QUndoCommand):
    """Delete a section (and its index entry). Undo restores both.

    Caller is responsible for checking prerequisite references before pushing.
    """

    def __init__(self, adapter, section_id: str) -> None:
        super().__init__("删除 Section")
        self.adapter = adapter
        self.section_id = section_id
        self.section_snapshot: dict[str, Any] | None = None
        self.index_snapshot: dict[str, Any] | None = None
        self.section_index: int = -1
        self.entry_index: int = -1
        self.signals = _make_changed()

    def redo(self) -> None:
        for i, section in enumerate(self.adapter.sections):
            if section.get("id") == self.section_id:
                self.section_index = i
                self.section_snapshot = deepcopy(section)
                break
        entries = self.adapter.index.get("sections", [])
        for i, entry in enumerate(entries):
            if entry.get("id") == self.section_id:
                self.entry_index = i
                self.index_snapshot = deepcopy(entry)
                break
        self.adapter.delete_section(self.section_id)
        self.signals.changed.emit()

    def undo(self) -> None:
        if self.section_snapshot is not None:
            idx = (
                self.section_index
                if 0 <= self.section_index <= len(self.adapter.sections)
                else len(self.adapter.sections)
            )
            self.adapter.sections.insert(idx, deepcopy(self.section_snapshot))
        if self.index_snapshot is not None:
            entries = self.adapter.index.setdefault("sections", [])
            eidx = (
                self.entry_index
                if 0 <= self.entry_index <= len(entries)
                else len(entries)
            )
            entries.insert(eidx, deepcopy(self.index_snapshot))
        self.signals.changed.emit()


class MoveSectionCommand(QUndoCommand):
    """Reorder a section among its siblings (top-level list). Hierarchy is
    preserved because the move stays within ``adapter.sections`` — no
    reparenting. Undo reverses the swap."""

    def __init__(self, adapter, from_idx: int, to_idx: int) -> None:
        super().__init__("上移/下移 Section")
        self.adapter = adapter
        self.from_idx = from_idx
        self.to_idx = to_idx
        self.signals = _make_changed()

    def redo(self) -> None:
        CourseAdapter.move_within(self.adapter.sections, self.from_idx, self.to_idx)
        self.signals.changed.emit()

    def undo(self) -> None:
        CourseAdapter.move_within(self.adapter.sections, self.to_idx, self.from_idx)
        self.signals.changed.emit()


class _MoveNodeCommand(QUndoCommand):
    """Reorder a node among its siblings within its parent. Hierarchy preserved
    (no cross-parent move). Undo reverses the swap."""

    _label: str

    def __init__(self, adapter, container_id: str, from_idx: int, to_idx: int) -> None:
        super().__init__(self._label)
        self.adapter = adapter
        self.container_id = container_id
        self.from_idx = from_idx
        self.to_idx = to_idx
        self.signals = _make_changed()

    def _list(self):
        raise NotImplementedError

    def redo(self) -> None:
        CourseAdapter.move_within(self._list(), self.from_idx, self.to_idx)
        self.signals.changed.emit()

    def undo(self) -> None:
        CourseAdapter.move_within(self._list(), self.to_idx, self.from_idx)
        self.signals.changed.emit()


class MoveUnitCommand(_MoveNodeCommand):
    _label = "上移/下移 Unit"

    def _list(self):
        return self.adapter.find_section(self.container_id).setdefault("units", [])


class MoveLessonCommand(_MoveNodeCommand):
    _label = "上移/下移 Lesson"

    def _list(self):
        _, unit = self.adapter.find_unit(self.container_id)
        return unit.setdefault("lessons", [])


class ReparentLessonCommand(QUndoCommand):
    """Move a lesson into a different unit (possibly in another section).

    Cross-tree reorder: the lesson leaves its current unit and is inserted
    at ``new_index`` inside ``new_unit_id``. ``new_index`` is clamped to the
    target unit's lesson count. Reference ids (wordId/expressionId/...) are
    preserved - only the lesson's location changes. Snapshot+remove+insert
    mirrors ``BulkMoveLessonsCommand`` so undo restores the exact old spot.
    """

    def __init__(self, adapter, lesson_id: str, new_unit_id: str, new_index: int) -> None:
        super().__init__("移动 Lesson 到其他 Unit")
        self.adapter = adapter
        self.lesson_id = lesson_id
        self.new_unit_id = new_unit_id
        self.new_index = new_index
        self.old_unit_id: str | None = None
        self.old_index: int = -1
        self._snapshot: dict[str, Any] | None = None
        self.signals = _make_changed()

    def redo(self) -> None:
        _section, unit, lesson = self.adapter.find_lesson(self.lesson_id)
        self.old_unit_id = unit.get("id", "")
        lessons = unit.get("lessons", [])
        self.old_index = next(
            (i for i, l in enumerate(lessons) if l.get("id") == self.lesson_id), -1
        )
        self._snapshot = deepcopy(lesson)
        self.adapter.delete_lesson(self.lesson_id)
        _s, new_unit = self.adapter.find_unit(self.new_unit_id)
        target = new_unit.setdefault("lessons", [])
        idx = self.new_index if 0 <= self.new_index <= len(target) else len(target)
        target.insert(idx, deepcopy(self._snapshot))
        self.signals.changed.emit()

    def undo(self) -> None:
        if self._snapshot is None or self.old_unit_id is None:
            return
        _s, new_unit = self.adapter.find_unit(self.new_unit_id)
        new_lessons = new_unit.get("lessons", [])
        for i, l in enumerate(new_lessons):
            if l.get("id") == self.lesson_id:
                del new_lessons[i]
                break
        _s, old_unit = self.adapter.find_unit(self.old_unit_id)
        old_lessons = old_unit.setdefault("lessons", [])
        idx = self.old_index if 0 <= self.old_index <= len(old_lessons) else len(old_lessons)
        old_lessons.insert(idx, deepcopy(self._snapshot))
        self.signals.changed.emit()


class ReparentUnitCommand(QUndoCommand):
    """Move a unit into a different section.

    Cross-tree reorder: the unit leaves its current section and is inserted
    at ``new_index`` inside ``new_section_id``. ``new_index`` is clamped to
    the target section's unit count. Snapshot+remove+insert mirrors
    ``ReparentLessonCommand`` so undo restores the exact old spot.
    """

    def __init__(self, adapter, unit_id: str, new_section_id: str, new_index: int) -> None:
        super().__init__("移动 Unit 到其他 Section")
        self.adapter = adapter
        self.unit_id = unit_id
        self.new_section_id = new_section_id
        self.new_index = new_index
        self.old_section_id: str | None = None
        self.old_index: int = -1
        self._snapshot: dict[str, Any] | None = None
        self.signals = _make_changed()

    def redo(self) -> None:
        section, unit = self.adapter.find_unit(self.unit_id)
        self.old_section_id = section.get("id", "")
        units = section.get("units", [])
        self.old_index = next(
            (i for i, u in enumerate(units) if u.get("id") == self.unit_id), -1
        )
        self._snapshot = deepcopy(unit)
        self.adapter.delete_unit(self.unit_id)
        target_section = self.adapter.find_section(self.new_section_id)
        target = target_section.setdefault("units", [])
        idx = self.new_index if 0 <= self.new_index <= len(target) else len(target)
        target.insert(idx, deepcopy(self._snapshot))
        self.signals.changed.emit()

    def undo(self) -> None:
        if self._snapshot is None or self.old_section_id is None:
            return
        target_section = self.adapter.find_section(self.new_section_id)
        target_units = target_section.get("units", [])
        for i, u in enumerate(target_units):
            if u.get("id") == self.unit_id:
                del target_units[i]
                break
        old_section = self.adapter.find_section(self.old_section_id)
        old_units = old_section.setdefault("units", [])
        idx = self.old_index if 0 <= self.old_index <= len(old_units) else len(old_units)
        old_units.insert(idx, deepcopy(self._snapshot))
        self.signals.changed.emit()


def _dedupe_preserve_order(ids: list[str]) -> list[str]:
    """De-duplicate an id list while preserving first-seen order."""
    return list(dict.fromkeys(ids))


class DuplicateLessonCommand(QUndoCommand):
    """Duplicate a lesson into the same unit with fresh ids. Undo removes it."""

    def __init__(self, adapter, lesson_id: str) -> None:
        super().__init__("复制 Lesson")
        self.adapter = adapter
        self.src_lesson_id = lesson_id
        self.new_lesson_id: str | None = None
        self.signals = _make_changed()

    def redo(self) -> None:
        self.new_lesson_id = self.adapter.duplicate_lesson(self.src_lesson_id)
        self.signals.changed.emit()

    def undo(self) -> None:
        if self.new_lesson_id is not None:
            try:
                self.adapter.delete_lesson(self.new_lesson_id)
            except KeyError:
                logger.debug("application/commands.py:undo best-effort step failed", exc_info=True)
        self.signals.changed.emit()


class BulkDeleteLessonsCommand(QUndoCommand):
    """Delete multiple lessons at once. Undo restores each to its original spot.

    Snapshots capture (unit_id, index, lesson) at redo time; undo re-inserts
    in ascending (unit_id, index) order so multiple deletes within one unit
    restore to their original positions.
    """

    def __init__(self, adapter, lesson_ids: list[str]) -> None:
        super().__init__("批量删除 Lesson")
        self.adapter = adapter
        self.lesson_ids = _dedupe_preserve_order(lesson_ids)
        self.snapshots: list[dict[str, Any]] = []
        self.signals = _make_changed()

    def redo(self) -> None:
        # First pass: capture original (unit_id, index, lesson) before any
        # deletion shifts indices. Then delete in a second pass.
        self.snapshots = []
        for lid in self.lesson_ids:
            try:
                _section, unit, lesson = self.adapter.find_lesson(lid)
            except KeyError:
                continue
            lessons = unit.get("lessons", [])
            idx = next((i for i, l in enumerate(lessons) if l.get("id") == lid), -1)
            self.snapshots.append(
                {
                    "unit_id": unit.get("id", ""),
                    "index": idx,
                    "lesson": deepcopy(lesson),
                }
            )
        for lid in self.lesson_ids:
            try:
                self.adapter.delete_lesson(lid)
            except KeyError:
                logger.debug("application/commands.py:redo best-effort step failed", exc_info=True)
        self.signals.changed.emit()

    def undo(self) -> None:
        for snap in sorted(self.snapshots, key=lambda s: (s["unit_id"], s["index"])):
            try:
                _section, unit = self.adapter.find_unit(snap["unit_id"])
            except KeyError:
                continue
            lessons = unit.setdefault("lessons", [])
            idx = snap["index"]
            if 0 <= idx <= len(lessons):
                lessons.insert(idx, deepcopy(snap["lesson"]))
            else:
                lessons.append(deepcopy(snap["lesson"]))
        self.signals.changed.emit()


class BulkDuplicateLessonsCommand(QUndoCommand):
    """Duplicate multiple lessons (each into its own unit). Undo removes copies."""

    def __init__(self, adapter, lesson_ids: list[str]) -> None:
        super().__init__("批量复制 Lesson")
        self.adapter = adapter
        self.lesson_ids = _dedupe_preserve_order(lesson_ids)
        self.new_ids: list[str] = []
        self.signals = _make_changed()

    def redo(self) -> None:
        self.new_ids = [self.adapter.duplicate_lesson(lid) for lid in self.lesson_ids]
        self.signals.changed.emit()

    def undo(self) -> None:
        for nid in self.new_ids:
            try:
                self.adapter.delete_lesson(nid)
            except KeyError:
                logger.debug("application/commands.py:undo best-effort step failed", exc_info=True)
        self.new_ids = []
        self.signals.changed.emit()


class BulkMoveLessonsCommand(QUndoCommand):
    """Move multiple lessons into a target unit. Undo restores original positions.

    Lessons already in the target unit are skipped (no-op) to avoid dropping
    them during the remove/append cycle.
    """

    def __init__(self, adapter, lesson_ids: list[str], target_unit_id: str) -> None:
        super().__init__("批量移动 Lesson")
        self.adapter = adapter
        self.target_unit_id = target_unit_id
        self.lesson_ids = _dedupe_preserve_order(lesson_ids)
        self.snapshots: list[dict[str, Any]] = []
        self.signals = _make_changed()

    def redo(self) -> None:
        # First pass: capture original (unit_id, index, lesson) before any
        # deletion shifts indices; skip lessons already in the target unit.
        self.snapshots = []
        for lid in self.lesson_ids:
            try:
                _section, unit, lesson = self.adapter.find_lesson(lid)
            except KeyError:
                continue
            if unit.get("id") == self.target_unit_id:
                continue  # already in target - skip
            lessons = unit.get("lessons", [])
            idx = next((i for i, l in enumerate(lessons) if l.get("id") == lid), -1)
            self.snapshots.append(
                {
                    "unit_id": unit.get("id", ""),
                    "index": idx,
                    "lesson": deepcopy(lesson),
                }
            )
        for snap in self.snapshots:
            self.adapter.delete_lesson(snap["lesson"].get("id", ""))
        _s, target_unit = self.adapter.find_unit(self.target_unit_id)
        target_lessons = target_unit.setdefault("lessons", [])
        for snap in self.snapshots:
            target_lessons.append(deepcopy(snap["lesson"]))
        self.signals.changed.emit()

    def undo(self) -> None:
        moved_ids = {s["lesson"].get("id") for s in self.snapshots}
        try:
            _s, target_unit = self.adapter.find_unit(self.target_unit_id)
        except KeyError:
            target_unit = None
        if target_unit is not None:
            target_lessons = target_unit.get("lessons", [])
            target_unit["lessons"] = [
                l for l in target_lessons if l.get("id") not in moved_ids
            ]
        for snap in sorted(self.snapshots, key=lambda s: (s["unit_id"], s["index"])):
            try:
                _section, unit = self.adapter.find_unit(snap["unit_id"])
            except KeyError:
                continue
            lessons = unit.setdefault("lessons", [])
            idx = snap["index"]
            if 0 <= idx <= len(lessons):
                lessons.insert(idx, deepcopy(snap["lesson"]))
            else:
                lessons.append(deepcopy(snap["lesson"]))
        self.signals.changed.emit()


class BulkApplyPresetCommand(QUndoCommand):
    """Apply a functional preset to multiple lessons (replace template + content,
    keep id/name/description/prerequisites). Undo restores the original content."""

    def __init__(self, adapter, lesson_ids: list[str], preset_id: str) -> None:
        super().__init__("批量套用预设")
        self.adapter = adapter
        self.lesson_ids = _dedupe_preserve_order(lesson_ids)
        self.preset_id = preset_id
        self.snapshots: list[dict[str, Any]] = []
        self.signals = _make_changed()

    def redo(self) -> None:
        from src.backend.lesson_presets import apply_preset_to_lesson

        self.snapshots = []
        for lid in self.lesson_ids:
            try:
                _s, _u, lesson = self.adapter.find_lesson(lid)
            except KeyError:
                continue
            self.snapshots.append(
                {
                    "lesson_id": lid,
                    "template": lesson.get("template"),
                    "type": lesson.get("type"),
                    "content": deepcopy(lesson.get("content", {})),
                }
            )
            apply_preset_to_lesson(lesson, self.preset_id)
        self.signals.changed.emit()

    def undo(self) -> None:
        for snap in self.snapshots:
            try:
                _s, _u, lesson = self.adapter.find_lesson(snap["lesson_id"])
            except KeyError:
                continue
            lesson["template"] = snap["template"]
            lesson["type"] = snap["type"]
            lesson["content"] = deepcopy(snap["content"])
        self.signals.changed.emit()

