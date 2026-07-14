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
from typing import Any

from PySide6.QtCore import QObject, Signal
from PySide6.QtGui import QUndoCommand

from src.backend.lesson_content import (
    add_item,
    delete_item,
    move_item,
    move_stage,
    move_sub_lesson,
)


class _Signals(QObject):
    """Per-command signal emitter (QUndoCommand cannot itself be a QObject)."""
    changed = Signal()


def _make_changed() -> _Signals:
    return _Signals()


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
        self.item = dict(item)
        self.index = -1
        self.signals = _make_changed()

    def redo(self) -> None:
        items = self.stage.get("items", [])
        for i, it in enumerate(items):
            if it is not None and it.get("id") == self.item.get("id"):
                self.index = i
                del items[i]
                break
        self.signals.changed.emit()

    def undo(self) -> None:
        items = self.stage.setdefault("items", [])
        if 0 <= self.index <= len(items):
            items.insert(self.index, dict(self.item))
        else:
            items.append(dict(self.item))
        self.signals.changed.emit()


class MoveItemCommand(QUndoCommand):
    def __init__(self, stage: dict[str, Any], from_idx: int, to_idx: int) -> None:
        super().__init__("移动题目")
        self.stage = stage
        self.from_idx = from_idx
        self.to_idx = to_idx
        self.signals = _make_changed()

    def redo(self) -> None:
        move_item(self.stage, self.from_idx, self.to_idx)
        self.signals.changed.emit()

    def undo(self) -> None:
        move_item(self.stage, self.to_idx, self.from_idx)
        self.signals.changed.emit()


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


class MoveSubLessonCommand(QUndoCommand):
    def __init__(self, content: dict[str, Any], from_idx: int, to_idx: int) -> None:
        super().__init__("移动教学环节")
        self.content = content
        self.from_idx = from_idx
        self.to_idx = to_idx
        self.signals = _make_changed()

    def redo(self) -> None:
        move_sub_lesson(self.content, self.from_idx, self.to_idx)
        self.signals.changed.emit()

    def undo(self) -> None:
        move_sub_lesson(self.content, self.to_idx, self.from_idx)
        self.signals.changed.emit()


class MoveStageCommand(QUndoCommand):
    def __init__(self, sub_lesson: dict[str, Any], from_idx: int, to_idx: int) -> None:
        super().__init__("移动教学步骤")
        self.sub_lesson = sub_lesson
        self.from_idx = from_idx
        self.to_idx = to_idx
        self.signals = _make_changed()

    def redo(self) -> None:
        move_stage(self.sub_lesson, self.from_idx, self.to_idx)
        self.signals.changed.emit()

    def undo(self) -> None:
        move_stage(self.sub_lesson, self.to_idx, self.from_idx)
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


class ImportAiSectionCommand(QUndoCommand):
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

    def redo(self) -> None:
        sid = self.section_json.get("id", "")
        self.adapter.sections.append(deepcopy(self.section_json))
        self.adapter.merge_section_resources(self.section_json)
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
        self.signals.changed.emit()


class AiEditSectionCommand(QUndoCommand):
    """Replace an existing section with an AI-edited version. Undo restores."""

    def __init__(self, adapter, section_id: str, new_section: dict[str, Any]) -> None:
        super().__init__("AI 编辑 Section")
        self.adapter = adapter
        self.section_id = section_id
        self.new_section = deepcopy(new_section)
        self.old_section: dict[str, Any] | None = None
        self.signals = _make_changed()

    def redo(self) -> None:
        if self.old_section is None:
            self.old_section = deepcopy(self.adapter.find_section(self.section_id))
        self.adapter.replace_section(self.section_id, deepcopy(self.new_section))
        self.signals.changed.emit()

    def undo(self) -> None:
        if self.old_section is not None:
            self.adapter.replace_section(self.section_id, deepcopy(self.old_section))
        self.signals.changed.emit()


class AiEditUnitCommand(QUndoCommand):
    """Replace a single unit within a section with an AI-edited version."""

    def __init__(
        self, adapter, section_id: str, unit_id: str, new_unit: dict[str, Any]
    ) -> None:
        super().__init__("AI 编辑 Unit")
        self.adapter = adapter
        self.section_id = section_id
        self.unit_id = unit_id
        self.new_unit = deepcopy(new_unit)
        self.old_unit: dict[str, Any] | None = None
        self.signals = _make_changed()

    def redo(self) -> None:
        if self.old_unit is None:
            _section, unit = self.adapter.find_unit(self.unit_id)
            self.old_unit = deepcopy(unit)
        self.adapter.replace_unit(
            self.section_id, self.unit_id, deepcopy(self.new_unit)
        )
        self.signals.changed.emit()

    def undo(self) -> None:
        if self.old_unit is not None:
            self.adapter.replace_unit(
                self.section_id, self.unit_id, deepcopy(self.old_unit)
            )
        self.signals.changed.emit()


class AiEditLessonCommand(QUndoCommand):
    """Replace a single lesson with an AI-edited version."""

    def __init__(self, adapter, lesson_id: str, new_lesson: dict[str, Any]) -> None:
        super().__init__("AI 编辑 Lesson")
        self.adapter = adapter
        self.lesson_id = lesson_id
        self.new_lesson = deepcopy(new_lesson)
        self.old_lesson: dict[str, Any] | None = None
        self.signals = _make_changed()

    def redo(self) -> None:
        if self.old_lesson is None:
            _s, _u, lesson = self.adapter.find_lesson(self.lesson_id)
            self.old_lesson = deepcopy(lesson)
        self.adapter.replace_lesson(self.lesson_id, deepcopy(self.new_lesson))
        self.signals.changed.emit()

    def undo(self) -> None:
        if self.old_lesson is not None:
            self.adapter.replace_lesson(self.lesson_id, deepcopy(self.old_lesson))
        self.signals.changed.emit()


# --- Metadata commands ----------------------------------------------------


class UpdateSectionMetaCommand(QUndoCommand):
    """Update a section's name + description (and sync the index entry)."""

    def __init__(
        self, adapter, section_id: str, new_name: str, new_description: str
    ) -> None:
        super().__init__("修改 Section 属性")
        self.adapter = adapter
        self.section_id = section_id
        self.new_name = new_name
        self.new_description = new_description
        self.old_name: str = ""
        self.old_description: str = ""
        self.signals = _make_changed()

    def _apply(self, name: str, desc: str) -> None:
        section = self.adapter.find_section(self.section_id)
        section["name"] = name
        section["description"] = desc
        for entry in self.adapter.index.get("sections", []):
            if entry.get("id") == self.section_id:
                entry["name"] = name
                entry["description"] = desc
                break
        self.signals.changed.emit()

    def redo(self) -> None:
        if not self.old_name and not self.old_description:
            section = self.adapter.find_section(self.section_id)
            self.old_name = section.get("name", "")
            self.old_description = section.get("description", "")
        self._apply(self.new_name, self.new_description)

    def undo(self) -> None:
        self._apply(self.old_name, self.old_description)


class UpdateUnitMetaCommand(QUndoCommand):
    def __init__(
        self, adapter, unit_id: str, new_name: str, new_description: str
    ) -> None:
        super().__init__("修改 Unit 属性")
        self.adapter = adapter
        self.unit_id = unit_id
        self.new_name = new_name
        self.new_description = new_description
        self.old_name: str = ""
        self.old_description: str = ""
        self.signals = _make_changed()

    def _apply(self, name: str, desc: str) -> None:
        _section, unit = self.adapter.find_unit(self.unit_id)
        unit["name"] = name
        unit["description"] = desc
        self.signals.changed.emit()

    def redo(self) -> None:
        if not self.old_name and not self.old_description:
            _section, unit = self.adapter.find_unit(self.unit_id)
            self.old_name = unit.get("name", "")
            self.old_description = unit.get("description", "")
        self._apply(self.new_name, self.new_description)

    def undo(self) -> None:
        self._apply(self.old_name, self.old_description)


class UpdateLessonMetaCommand(QUndoCommand):
    def __init__(
        self, adapter, lesson_id: str, new_name: str, new_description: str
    ) -> None:
        super().__init__("修改 Lesson 属性")
        self.adapter = adapter
        self.lesson_id = lesson_id
        self.new_name = new_name
        self.new_description = new_description
        self.old_name: str = ""
        self.old_description: str = ""
        self.signals = _make_changed()

    def _apply(self, name: str, desc: str) -> None:
        _s, _u, lesson = self.adapter.find_lesson(self.lesson_id)
        lesson["name"] = name
        lesson["description"] = desc
        self.signals.changed.emit()

    def redo(self) -> None:
        if not self.old_name and not self.old_description:
            _s, _u, lesson = self.adapter.find_lesson(self.lesson_id)
            self.old_name = lesson.get("name", "")
            self.old_description = lesson.get("description", "")
        self._apply(self.new_name, self.new_description)

    def undo(self) -> None:
        self._apply(self.old_name, self.old_description)


class UpdateSectionPrereqsCommand(QUndoCommand):
    def __init__(self, adapter, section_id: str, new_prereqs: list[str]) -> None:
        super().__init__("修改 Section 先修")
        self.adapter = adapter
        self.section_id = section_id
        self.new_prereqs = list(new_prereqs)
        self.old_prereqs: list[str] = []
        self.signals = _make_changed()

    def redo(self) -> None:
        section = self.adapter.find_section(self.section_id)
        if not self.old_prereqs and not getattr(self, "_captured", False):
            self.old_prereqs = list(section.get("prerequisiteSectionIds", []))
            self._captured = True  # type: ignore[attr-defined]
        section["prerequisiteSectionIds"] = [p for p in self.new_prereqs if p != self.section_id]
        self.signals.changed.emit()

    def undo(self) -> None:
        section = self.adapter.find_section(self.section_id)
        section["prerequisiteSectionIds"] = list(self.old_prereqs)
        self.signals.changed.emit()


class UpdateUnitPrereqsCommand(QUndoCommand):
    def __init__(self, adapter, unit_id: str, new_prereqs: list[str]) -> None:
        super().__init__("修改 Unit 先修")
        self.adapter = adapter
        self.unit_id = unit_id
        self.new_prereqs = list(new_prereqs)
        self.old_prereqs: list[str] = []
        self.signals = _make_changed()

    def redo(self) -> None:
        _section, unit = self.adapter.find_unit(self.unit_id)
        if not self.old_prereqs and not getattr(self, "_captured", False):
            self.old_prereqs = list(unit.get("prerequisiteUnitIds", []))
            self._captured = True  # type: ignore[attr-defined]
        unit["prerequisiteUnitIds"] = [p for p in self.new_prereqs if p != self.unit_id]
        self.signals.changed.emit()

    def undo(self) -> None:
        _section, unit = self.adapter.find_unit(self.unit_id)
        unit["prerequisiteUnitIds"] = list(self.old_prereqs)
        self.signals.changed.emit()


class UpdateLessonPrereqsCommand(QUndoCommand):
    def __init__(self, adapter, lesson_id: str, new_prereqs: list[str]) -> None:
        super().__init__("修改 Lesson 先修")
        self.adapter = adapter
        self.lesson_id = lesson_id
        self.new_prereqs = list(new_prereqs)
        self.old_prereqs: list[str] = []
        self.signals = _make_changed()

    def redo(self) -> None:
        _s, _u, lesson = self.adapter.find_lesson(self.lesson_id)
        if not self.old_prereqs and not getattr(self, "_captured", False):
            self.old_prereqs = list(lesson.get("prerequisiteLessonIds", []))
            self._captured = True  # type: ignore[attr-defined]
        lesson["prerequisiteLessonIds"] = [p for p in self.new_prereqs if p != self.lesson_id]
        self.signals.changed.emit()

    def undo(self) -> None:
        _s, _u, lesson = self.adapter.find_lesson(self.lesson_id)
        lesson["prerequisiteLessonIds"] = list(self.old_prereqs)
        self.signals.changed.emit()