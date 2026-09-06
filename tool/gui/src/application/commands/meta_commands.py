"""Metadata (name/description/prerequisites) and experience patch undo commands."""

from __future__ import annotations

from copy import deepcopy
from typing import Any

from PySide6.QtGui import QUndoCommand

from src.application.commands._base import _make_changed


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


class UpdateLessonLinkedGrammarCommand(QUndoCommand):
    """Set ``content.linkedGrammarPointIds`` (app SRS registration reads it)."""

    def __init__(self, adapter, lesson_id: str, new_ids: list[str]) -> None:
        super().__init__("修改课时关联语法点")
        self.adapter = adapter
        self.lesson_id = lesson_id
        self.new_ids = list(new_ids)
        self.old_ids: list[str] = []
        self.signals = _make_changed()

    def redo(self) -> None:
        _s, _u, lesson = self.adapter.find_lesson(self.lesson_id)
        if not self.old_ids and not getattr(self, "_captured", False):
            self.old_ids = list(
                (lesson.get("content") or {}).get("linkedGrammarPointIds", [])
            )
            self._captured = True  # type: ignore[attr-defined]
        self.adapter.set_linked_grammar_points(self.lesson_id, self.new_ids)
        self.signals.changed.emit()

    def undo(self) -> None:
        self.adapter.set_linked_grammar_points(self.lesson_id, self.old_ids)
        self.signals.changed.emit()


class ApplyLessonPatchCommand(QUndoCommand):
    """Apply LessonPatch to replace lesson content with undo."""

    def __init__(self, adapter: Any, patch: Any, text: str = "应用课时补丁") -> None:
        super().__init__(text)
        self.adapter = adapter
        self.patch = patch
        self.signals = _make_changed()

    def redo(self) -> None:
        from src.backend.experience.patch import apply_lesson_patch

        lid = getattr(self.patch, "lesson_id", "")
        uid = getattr(self.patch, "unit_id", "")
        if uid:
            _s, unit = self.adapter.find_unit(uid)
        else:
            _s, unit, _l = self.adapter.find_lesson(lid)
        apply_lesson_patch(unit, self.patch)
        if hasattr(self.adapter, "invalidate_node_index"):
            self.adapter.invalidate_node_index()
        self.signals.changed.emit()

    def undo(self) -> None:
        from src.backend.experience.patch import revert_lesson_patch

        lid = getattr(self.patch, "lesson_id", "")
        uid = getattr(self.patch, "unit_id", "")
        if uid:
            _s, unit = self.adapter.find_unit(uid)
        else:
            _s, unit, _l = self.adapter.find_lesson(lid)
        revert_lesson_patch(unit, self.patch)
        if hasattr(self.adapter, "invalidate_node_index"):
            self.adapter.invalidate_node_index()
        self.signals.changed.emit()


class ApplyBatchPatchCommand(QUndoCommand):
    """Apply a batch of patches or resolved steps transactionally."""

    def __init__(
        self,
        steps: Any = None,
        adapter: Any = None,
        batch: Any = None,
        text: str = "应用批量补丁",
    ) -> None:
        super().__init__(text)
        self.adapter = adapter
        self.batch = batch
        self.steps = steps
        self._resolved_steps: list[Any] = []
        self.signals = _make_changed()

    def _resolve(self) -> list[Any]:
        if self.steps is not None:
            return list(self.steps)
        if self.batch is None or self.adapter is None:
            return []
        from src.backend.experience.patch import FieldPatch, ItemPatch, LessonPatch

        resolved = []
        for p in getattr(self.batch, "patches", []):
            if isinstance(p, LessonPatch):
                if p.unit_id:
                    _s, unit = self.adapter.find_unit(p.unit_id)
                else:
                    _s, unit, _l = self.adapter.find_lesson(p.lesson_id)
                resolved.append(("lesson", unit, p))
            elif isinstance(p, FieldPatch):
                target = None
                if p.target_kind in ("vocab", "expressions", "grammar_points"):
                    collection = getattr(self.adapter, p.target_kind, [])
                    for item in collection:
                        if str(item.get("id") or "") == p.target_id:
                            target = item
                            break
                if target is not None:
                    resolved.append(("field", target, p))
        return resolved

    def redo(self) -> None:
        from src.backend.experience.patch import apply_resolved_batch

        if not self._resolved_steps:
            self._resolved_steps = self._resolve()
        if self._resolved_steps:
            apply_resolved_batch(self._resolved_steps)
        if self.adapter and hasattr(self.adapter, "invalidate_node_index"):
            self.adapter.invalidate_node_index()
        self.signals.changed.emit()

    def undo(self) -> None:
        from src.backend.experience.patch import revert_resolved_batch

        if self._resolved_steps:
            revert_resolved_batch(self._resolved_steps)
        if self.adapter and hasattr(self.adapter, "invalidate_node_index"):
            self.adapter.invalidate_node_index()
        self.signals.changed.emit()


class ApplySectionPatchCommand(QUndoCommand):
    """Apply SectionPatch to replace whole section body + merge resources."""

    def __init__(self, adapter: Any, patch: Any, text: str = "应用节补丁") -> None:
        super().__init__(text)
        self.adapter = adapter
        self.patch = patch
        self.old_section = deepcopy(patch.old_section)
        self.new_section = deepcopy(patch.new_section)
        self.section_id = patch.section_id
        self._vocab_snapshot = None
        self.signals = _make_changed()

    def redo(self) -> None:
        if hasattr(self.adapter, "vocab"):
            self._vocab_snapshot = deepcopy(self.adapter.vocab)
        self.adapter.replace_section(self.section_id, deepcopy(self.new_section))
        if hasattr(self.adapter, "merge_section_resources"):
            self.adapter.merge_section_resources(self.new_section)
        if hasattr(self.adapter, "invalidate_node_index"):
            self.adapter.invalidate_node_index()
        self.signals.changed.emit()

    def undo(self) -> None:
        self.adapter.replace_section(self.section_id, deepcopy(self.old_section))
        if self._vocab_snapshot is not None and hasattr(self.adapter, "vocab"):
            self.adapter.vocab = deepcopy(self._vocab_snapshot)
        if hasattr(self.adapter, "invalidate_node_index"):
            self.adapter.invalidate_node_index()
        self.signals.changed.emit()


class SoftHygieneCommand(QUndoCommand):
    """Soft Autopilot hygiene fixes undo command."""

    def __init__(self, adapter: Any, batch: Any, text: str = "规则规范化") -> None:
        super().__init__(text)
        self.adapter = adapter
        self.batch = batch
        self.snapshot: dict[str, Any] | None = None
        self.signals = _make_changed()

    def redo(self) -> None:
        from src.backend.experience.soft_autopilot import (
            apply_soft_fixes,
            snapshot_resources,
        )

        self.snapshot = snapshot_resources(self.adapter)
        apply_soft_fixes(self.adapter, self.batch)
        self.signals.changed.emit()

    def undo(self) -> None:
        from src.backend.experience.soft_autopilot import restore_resources

        if self.snapshot is not None:
            restore_resources(self.adapter, self.snapshot)
        self.signals.changed.emit()


class ReplaceItemCommand(QUndoCommand):
    """Replace one item inside stage['items'], preserving the original item id."""

    def __init__(
        self,
        stage: dict[str, Any],
        item_id: str,
        new_item: dict[str, Any],
        text: str = "替换题目",
    ) -> None:
        super().__init__(text)
        self.stage = stage
        self.item_id = item_id
        self.new_item = deepcopy(new_item)
        self.new_item["id"] = item_id  # Guard: forces id to remain unchanged
        self.old_item: dict[str, Any] | None = None
        self.index: int = -1
        self.signals = _make_changed()

    def redo(self) -> None:
        items = self.stage.get("items", [])
        for i, it in enumerate(items):
            if isinstance(it, dict) and it.get("id") == self.item_id:
                if self.old_item is None:
                    self.old_item = deepcopy(it)
                    self.index = i
                items[i] = deepcopy(self.new_item)
                break
        self.signals.changed.emit()

    def undo(self) -> None:
        if self.old_item is not None and 0 <= self.index < len(
            self.stage.get("items", [])
        ):
            self.stage["items"][self.index] = deepcopy(self.old_item)
        self.signals.changed.emit()


class ApplyItemPatchCommand(QUndoCommand):
    """Apply an ItemPatch inside a stage with undo."""

    def __init__(
        self, stage: dict[str, Any], patch: Any, text: str = "修改题目"
    ) -> None:
        super().__init__(text)
        self.stage = stage
        self.patch = patch
        self.signals = _make_changed()

    def redo(self) -> None:
        from src.backend.experience.patch import apply_item_patch

        apply_item_patch(self.stage, self.patch)
        self.signals.changed.emit()

    def undo(self) -> None:
        from src.backend.experience.patch import revert_item_patch

        revert_item_patch(self.stage, self.patch)
        self.signals.changed.emit()


class ApplyFieldPatchCommand(QUndoCommand):
    """Apply FieldPatch to target dict with undo."""

    def __init__(
        self, target: dict[str, Any], patch: Any, text: str = "修改字段"
    ) -> None:
        super().__init__(text)
        self.target = target
        self.patch = patch
        self.signals = _make_changed()

    def redo(self) -> None:
        from src.backend.experience.patch import apply_field_patch

        apply_field_patch(self.target, self.patch)
        self.signals.changed.emit()

    def undo(self) -> None:
        from src.backend.experience.patch import revert_field_patch

        revert_field_patch(self.target, self.patch)
        self.signals.changed.emit()