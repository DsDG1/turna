"""Item-level undo commands: items, sub-lessons, stages, listening phases."""

from __future__ import annotations

from copy import deepcopy
from typing import Any

from PySide6.QtGui import QUndoCommand

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

from src.application.commands._base import _make_changed, _remove_by_id


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

