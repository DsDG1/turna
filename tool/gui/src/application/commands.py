"""Undoable edit commands for the course editor (B2).

Each QUndoCommand mutates the in-memory course tree (via the pure helpers in
``lesson_content``) and emits a ``changed`` signal on redo/undo so the
teacher views re-render. The MainWindow owns the QUndoStack; detail widgets
push commands onto it instead of mutating dicts directly.

Commands are coarse-grained to cover the common error-prone edits: item
add/delete, item move, sub-lesson/stage delete, and field updates. Field
edits coalesce by tracking the previous value so a single "edit prompt"
produces one undoable step.

Tree-level commands (new/delete section/unit/lesson, AI import/edit) and
metadata commands (name/description/prerequisites) are also defined here so
the whole editor shares one undo stack.
"""
from __future__ import annotations

from copy import deepcopy
from typing import TYPE_CHECKING, Any

from PySide6.QtCore import QObject, Signal
from PySide6.QtGui import QUndoCommand

if TYPE_CHECKING:
    from src.backend.course_adapter import SectionMergePlan

from src.backend.lesson_content import (
    add_item,
    add_listening_phase,
    add_stage,
    add_sub_lesson,
    delete_item,
    delete_listening_phase,
    delete_stage,
    delete_sub_lesson,
    move_item,
    move_listening_phase,
    move_stage,
    move_sub_lesson,
)
from src.backend.course_adapter import CourseAdapter


class _Signals(QObject):
    """Per-command signal emitter (QUndoCommand cannot itself be a QObject)."""
    changed = Signal()


def _make_changed() -> _Signals:
    return _Signals()


def _remove_by_id(lst: list, target_id: str) -> int:
    """Delete the first item whose ``id`` equals ``target_id``; return its index (-1 if not found)."""
    for i, entry in enumerate(lst):
        if entry is not None and entry.get("id") == target_id:
            del lst[i]
            return i
    return -1


class AddItemCommand(QUndoCommand):
    def __init__(self, stage: dict[str, Any], runtime_type: str) -> None:
        super().__init__("添加题目")
        self.stage = stage
        self.runtime_type = runtime_type
        self.item: dict[str, Any] | None = None
        self.signals = _make_changed()

    def redo(self) -> None:
        self.item = add_item(self.stage, self.runtime_type)
        self.signals.changed.emit()

    def undo(self) -> None:
        if self.item is not None:
            delete_item(self.stage, self.item.get("id", ""))
        self.signals.changed.emit()


class DeleteItemCommand(QUndoCommand):
    def __init__(self, stage: dict[str, Any], item: dict[str, Any]) -> None:
        super().__init__("删除题目")
        self.stage = stage
        # Deep copy: the command's snapshot must not share nested lists
        # (options/hints) with the live item or with restored copies.
        self.item = deepcopy(item)
        self.index = -1
        self.signals = _make_changed()

    def redo(self) -> None:
        items = self.stage.get("items", [])
        self.index = _remove_by_id(items, self.item.get("id"))
        self.signals.changed.emit()

    def undo(self) -> None:
        items = self.stage.setdefault("items", [])
        if 0 <= self.index <= len(items):
            items.insert(self.index, deepcopy(self.item))
        else:
            items.append(deepcopy(self.item))
        self.signals.changed.emit()


class _MoveInContainerCommand(QUndoCommand):
    _label: str

    def __init__(self, container: dict[str, Any], from_idx: int, to_idx: int) -> None:
        super().__init__(self._label)
        self.container = container
        self.from_idx = from_idx
        self.to_idx = to_idx
        self.signals = _make_changed()

    def _move(self, container, from_idx, to_idx):
        raise NotImplementedError

    def redo(self) -> None:
        self._move(self.container, self.from_idx, self.to_idx)
        self.signals.changed.emit()

    def undo(self) -> None:
        self._move(self.container, self.to_idx, self.from_idx)
        self.signals.changed.emit()


class MoveItemCommand(_MoveInContainerCommand):
    _label = "移动题目"

    def _move(self, container, from_idx, to_idx):
        move_item(container, from_idx, to_idx)


class UpdateFieldCommand(QUndoCommand):
    """Set a single field on a dict (item / stage / sub-lesson metadata)."""

    def __init__(self, target: dict[str, Any], field: str, new_value: Any) -> None:
        super().__init__(f"修改 {field}")
        self.target = target
        self.field = field
        self.new_value = new_value
        self.old_value = target.get(field)
        self.signals = _make_changed()

    def redo(self) -> None:
        self.target[self.field] = self.new_value
        self.signals.changed.emit()

    def undo(self) -> None:
        self.target[self.field] = self.old_value
        self.signals.changed.emit()


class MoveSubLessonCommand(_MoveInContainerCommand):
    _label = "移动教学环节"

    def _move(self, container, from_idx, to_idx):
        move_sub_lesson(container, from_idx, to_idx)


class MoveStageCommand(_MoveInContainerCommand):
    _label = "移动教学步骤"

    def _move(self, container, from_idx, to_idx):
        move_stage(container, from_idx, to_idx)


class AddListeningPhaseCommand(QUndoCommand):
    def __init__(self, lesson: dict[str, Any], phase_type: str = "wordPairing", name: str = "新阶段") -> None:
        super().__init__("添加听力阶段")
        self.lesson = lesson
        self.phase_type = phase_type
        self.name = name
        self.phase: dict[str, Any] | None = None
        self.signals = _make_changed()

    def redo(self) -> None:
        self.phase = add_listening_phase(self.lesson, self.phase_type, self.name)
        self.signals.changed.emit()

    def undo(self) -> None:
        if self.phase is not None:
            delete_listening_phase(self.lesson, self.phase.get("id", ""))
        self.signals.changed.emit()


class DeleteListeningPhaseCommand(QUndoCommand):
    def __init__(self, lesson: dict[str, Any], phase: dict[str, Any]) -> None:
        super().__init__("删除听力阶段")
        self.lesson = lesson
        self.phase = deepcopy(phase)
        self.index = -1
        self.signals = _make_changed()

    def redo(self) -> None:
        phases = self.lesson.get("content", {}).get("listeningPhases", [])
        self.index = _remove_by_id(phases, self.phase.get("id"))
        self.signals.changed.emit()

    def undo(self) -> None:
        phases = self.lesson.setdefault("content", {}).setdefault("listeningPhases", [])
        if 0 <= self.index <= len(phases):
            phases.insert(self.index, deepcopy(self.phase))
        else:
            phases.append(deepcopy(self.phase))
        self.signals.changed.emit()


class MoveListeningPhaseCommand(_MoveInContainerCommand):
    _label = "移动听力阶段"

    def _move(self, container, from_idx, to_idx):
        move_listening_phase(container, from_idx, to_idx)


class RenameListeningPhaseCommand(UpdateFieldCommand):
    """Rename a listening phase (reuses UpdateFieldCommand)."""

    def __init__(self, phase: dict[str, Any], new_name: str) -> None:
        super().__init__(phase, "name", new_name)
        self.setText("重命名听力阶段")


class AddSubLessonCommand(QUndoCommand):
    def __init__(self, content: dict[str, Any], name: str = "新环节") -> None:
        super().__init__("添加教学环节")
        self.content = content
        self.name = name
        self.sub_lesson: dict[str, Any] | None = None
        self.signals = _make_changed()

    def redo(self) -> None:
        self.sub_lesson = add_sub_lesson(self.content, self.name)
        self.signals.changed.emit()

    def undo(self) -> None:
        if self.sub_lesson is not None:
            delete_sub_lesson(self.content, self.sub_lesson.get("id", ""))
        self.signals.changed.emit()


class DeleteSubLessonCommand(QUndoCommand):
    def __init__(self, content: dict[str, Any], sub_lesson: dict[str, Any]) -> None:
        super().__init__("删除教学环节")
        self.content = content
        self.sub_lesson = deepcopy(sub_lesson)
        self.index = -1
        self.signals = _make_changed()

    def redo(self) -> None:
        subs = self.content.get("subLessons", [])
        self.index = _remove_by_id(subs, self.sub_lesson.get("id"))
        self.signals.changed.emit()

    def undo(self) -> None:
        subs = self.content.setdefault("subLessons", [])
        if 0 <= self.index <= len(subs):
            subs.insert(self.index, deepcopy(self.sub_lesson))
        else:
            subs.append(deepcopy(self.sub_lesson))
        self.signals.changed.emit()


class AddStageCommand(QUndoCommand):
    def __init__(self, sub_lesson: dict[str, Any], name: str = "新步骤") -> None:
        super().__init__("添加教学步骤")
        self.sub_lesson = sub_lesson
        self.name = name
        self.stage: dict[str, Any] | None = None
        self.signals = _make_changed()

    def redo(self) -> None:
        self.stage = add_stage(self.sub_lesson, self.name)
        self.signals.changed.emit()

    def undo(self) -> None:
        if self.stage is not None:
            delete_stage(self.sub_lesson, self.stage.get("id", ""))
        self.signals.changed.emit()


class DeleteStageCommand(QUndoCommand):
    def __init__(self, sub_lesson: dict[str, Any], stage: dict[str, Any]) -> None:
        super().__init__("删除教学步骤")
        self.sub_lesson = sub_lesson
        self.stage = deepcopy(stage)
        self.index = -1
        self.signals = _make_changed()

    def redo(self) -> None:
        stages = self.sub_lesson.get("stages", [])
        self.index = _remove_by_id(stages, self.stage.get("id"))
        self.signals.changed.emit()

    def undo(self) -> None:
        stages = self.sub_lesson.setdefault("stages", [])
        if 0 <= self.index <= len(stages):
            stages.insert(self.index, deepcopy(self.stage))
        else:
            stages.append(deepcopy(self.stage))
        self.signals.changed.emit()


class RenameSubLessonCommand(UpdateFieldCommand):
    """Rename a sub-lesson (reuses UpdateFieldCommand)."""

    def __init__(self, sub_lesson: dict[str, Any], new_name: str) -> None:
        super().__init__(sub_lesson, "name", new_name)
        self.setText("重命名教学环节")


class RenameStageCommand(UpdateFieldCommand):
    """Rename a stage (reuses UpdateFieldCommand)."""

    def __init__(self, stage: dict[str, Any], new_name: str) -> None:
        super().__init__(stage, "name", new_name)
        self.setText("重命名教学步骤")


class ReplaceItemCommand(QUndoCommand):
    """Replace a single item in a stage while preserving its position."""

    def __init__(
        self,
        stage: dict[str, Any],
        item_id: str,
        new_item: dict[str, Any],
    ) -> None:
        super().__init__("改写题目")
        self.stage = stage
        self.item_id = item_id
        self.new_item = deepcopy(new_item)
        self.old_item: dict[str, Any] | None = None
        self.index = -1
        self.signals = _make_changed()

    def redo(self) -> None:
        items = self.stage.get("items", [])
        for i, it in enumerate(items):
            if it.get("id") == self.item_id:
                self.index = i
                self.old_item = deepcopy(it)
                items[i] = deepcopy(self.new_item)
                break
        self.signals.changed.emit()

    def undo(self) -> None:
        if self.old_item is None or self.index < 0:
            return
        items = self.stage.get("items", [])
        if 0 <= self.index < len(items):
            items[self.index] = deepcopy(self.old_item)
        self.signals.changed.emit()


# --- Tree-level structural commands ---------------------------------------


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
                pass
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
                pass
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
                pass
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
            pass
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


# --- Metadata commands ----------------------------------------------------


class _UpdateMetaBase(QUndoCommand):
    """Update a node's name + description. Section subclass also syncs the index entry."""

    _label: str

    def __init__(
        self, adapter, node_id: str, new_name: str, new_description: str
    ) -> None:
        super().__init__(self._label)
        self.adapter = adapter
        self.node_id = node_id
        self.new_name = new_name
        self.new_description = new_description
        self.old_name: str = ""
        self.old_description: str = ""
        self.signals = _make_changed()

    def _find(self, adapter, node_id):
        raise NotImplementedError

    def _sync_index(self, name: str, desc: str) -> None:
        pass

    def _apply(self, name: str, desc: str) -> None:
        node = self._find(self.adapter, self.node_id)
        node["name"] = name
        node["description"] = desc
        self._sync_index(name, desc)
        self.signals.changed.emit()

    def redo(self) -> None:
        if not getattr(self, "_captured", False):
            node = self._find(self.adapter, self.node_id)
            self.old_name = node.get("name", "")
            self.old_description = node.get("description", "")
            self._captured = True  # type: ignore[attr-defined]
        self._apply(self.new_name, self.new_description)

    def undo(self) -> None:
        self._apply(self.old_name, self.old_description)


class UpdateSectionMetaCommand(_UpdateMetaBase):
    _label = "修改 Section 属性"

    def _find(self, adapter, node_id):
        return adapter.find_section(node_id)

    def _sync_index(self, name: str, desc: str) -> None:
        for entry in self.adapter.index.get("sections", []):
            if entry.get("id") == self.node_id:
                entry["name"] = name
                entry["description"] = desc
                break


class UpdateUnitMetaCommand(_UpdateMetaBase):
    _label = "修改 Unit 属性"

    def _find(self, adapter, node_id):
        _section, unit = adapter.find_unit(node_id)
        return unit


class UpdateLessonMetaCommand(_UpdateMetaBase):
    _label = "修改 Lesson 属性"

    def _find(self, adapter, node_id):
        _s, _u, lesson = adapter.find_lesson(node_id)
        return lesson


class _UpdatePrereqsBase(QUndoCommand):
    _field: str
    _label: str

    def __init__(self, adapter, node_id: str, new_prereqs: list[str]) -> None:
        super().__init__(self._label)
        self.adapter = adapter
        self.node_id = node_id
        self.new_prereqs = list(new_prereqs)
        self.old_prereqs: list[str] = []
        self.signals = _make_changed()

    def _find(self, adapter, node_id):
        raise NotImplementedError

    def redo(self) -> None:
        node = self._find(self.adapter, self.node_id)
        if not self.old_prereqs and not getattr(self, "_captured", False):
            self.old_prereqs = list(node.get(self._field, []))
            self._captured = True  # type: ignore[attr-defined]
        node[self._field] = [p for p in self.new_prereqs if p != self.node_id]
        self.signals.changed.emit()

    def undo(self) -> None:
        node = self._find(self.adapter, self.node_id)
        node[self._field] = list(self.old_prereqs)
        self.signals.changed.emit()


class UpdateSectionPrereqsCommand(_UpdatePrereqsBase):
    _field = "prerequisiteSectionIds"
    _label = "修改 Section 先修"

    def _find(self, adapter, node_id):
        return adapter.find_section(node_id)


class UpdateUnitPrereqsCommand(_UpdatePrereqsBase):
    _field = "prerequisiteUnitIds"
    _label = "修改 Unit 先修"

    def _find(self, adapter, node_id):
        _section, unit = adapter.find_unit(node_id)
        return unit


class UpdateLessonPrereqsCommand(_UpdatePrereqsBase):
    _field = "prerequisiteLessonIds"
    _label = "修改 Lesson 先修"

    def _find(self, adapter, node_id):
        _s, _u, lesson = adapter.find_lesson(node_id)
        return lesson