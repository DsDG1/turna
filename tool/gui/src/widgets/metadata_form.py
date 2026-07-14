"""Metadata form for Section / Unit / Lesson nodes.

id is read-only; name / description editable. prerequisite fields use a
checkable QListWidget populated from same-layer siblings (guiplan §9 M1.4).

Edits are pushed onto the shared ``QUndoStack`` (when set) as coarse-grained
metadata commands: one undoable step per focus-loss commit, not per keystroke.
"""
from __future__ import annotations

from typing import Any

from PySide6.QtCore import Qt, Signal
from PySide6.QtGui import QUndoStack
from PySide6.QtWidgets import (
    QFormLayout,
    QGroupBox,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QListWidget,
    QListWidgetItem,
    QTextEdit,
    QVBoxLayout,
    QWidget,
)

from src.application.commands import (
    UpdateLessonMetaCommand,
    UpdateLessonPrereqsCommand,
    UpdateSectionMetaCommand,
    UpdateSectionPrereqsCommand,
    UpdateUnitMetaCommand,
    UpdateUnitPrereqsCommand,
)
from src.backend.course_adapter import CourseAdapter


class _FocusTextEdit(QTextEdit):
    """QTextEdit that emits :attr:`focusLost` when it loses focus."""

    focusLost = Signal()

    def focusOutEvent(self, event) -> None:  # noqa: N802
        super().focusOutEvent(event)
        self.focusLost.emit()


class _FocusListWidget(QListWidget):
    """QListWidget that emits :attr:`focusLost` when it loses focus."""

    focusLost = Signal()

    def focusOutEvent(self, event) -> None:  # noqa: N802
        super().focusOutEvent(event)
        self.focusLost.emit()


class MetadataForm(QGroupBox):
    """Form bound to a single node; writes edits back via undo commands."""

    metadata_changed = Signal()

    def __init__(self) -> None:
        super().__init__("属性")
        self.setStyleSheet("""
            QGroupBox {
                font-weight: 600;
                margin-top: 8px;
            }
            QGroupBox::title {
                color: #9CA3AF;
                left: 0px;
                top: 4px;
            }
        """)
        self._adapter: CourseAdapter | None = None
        self._kind: str = ""
        self._node_id: str = ""
        self.undo_stack: QUndoStack | None = None
        self._loading = False
        self._build_ui()

    def _build_ui(self) -> None:
        self.id_value = QLabel("(未选择)")
        self.id_value.setStyleSheet("color: #6B7280;")
        self.name_edit = QLineEdit()
        self.name_edit.setEnabled(False)
        self.desc_edit = _FocusTextEdit()
        self.desc_edit.setEnabled(False)
        self.desc_edit.setMaximumHeight(120)
        self.prereq_list = _FocusListWidget()
        self.prereq_list.setEnabled(False)
        self.prereq_list.setSelectionMode(QListWidget.SelectionMode.NoSelection)

        form = QFormLayout()
        form.setSpacing(12)
        form.setLabelAlignment(Qt.AlignmentFlag.AlignLeft)
        form.setFieldGrowthPolicy(QFormLayout.FieldGrowthPolicy.ExpandingFieldsGrow)
        form.addRow("ID（只读）", self.id_value)
        form.addRow("名称", self.name_edit)
        form.addRow("描述", self.desc_edit)
        form.addRow("先修", self.prereq_list)

        wrap = QVBoxLayout()
        wrap.setSpacing(16)
        wrap.addLayout(form)
        wrap.addStretch()
        outer = QHBoxLayout()
        outer.addLayout(wrap)
        self.setLayout(outer)

        # Commit on focus loss / enter so each edit = one undo step.
        self.name_edit.editingFinished.connect(self._commit_name_desc)
        self.desc_edit.focusLost.connect(self._commit_name_desc)
        self.prereq_list.focusLost.connect(self._commit_prereqs)

    def _fill_prereq(
        self,
        options: list[tuple[str, str]],
        current: list[str],
    ) -> None:
        self._loading = True
        self.prereq_list.blockSignals(True)
        self.prereq_list.clear()
        current_set = set(current)
        for rid, label in options:
            item = QListWidgetItem(label)
            item.setData(Qt.ItemDataRole.UserRole, rid)
            item.setFlags(item.flags() | Qt.ItemFlag.ItemIsUserCheckable)
            item.setCheckState(
                Qt.CheckState.Checked if rid in current_set else Qt.CheckState.Unchecked
            )
            self.prereq_list.addItem(item)
        self.prereq_list.blockSignals(False)
        self._loading = False

    def show_section(self, adapter: CourseAdapter, section: dict[str, Any]) -> None:
        self._bind(adapter, "section", section.get("id", ""))
        self._loading = True
        self.id_value.setText(section.get("id", ""))
        self.name_edit.setText(section.get("name", ""))
        self.desc_edit.setPlainText(section.get("description", ""))
        prereqs = section.get("prerequisiteSectionIds", [])
        self._fill_prereq(adapter.section_prereq_options(section.get("id", "")), prereqs)
        self._loading = False

    def show_unit(self, adapter: CourseAdapter, unit: dict[str, Any]) -> None:
        self._bind(adapter, "unit", unit.get("id", ""))
        self._loading = True
        self.id_value.setText(unit.get("id", ""))
        self.name_edit.setText(unit.get("name", ""))
        self.desc_edit.setPlainText(unit.get("description", ""))
        _section, _u = adapter.find_unit(unit.get("id", ""))
        prereqs = unit.get("prerequisiteUnitIds", [])
        self._fill_prereq(
            adapter.unit_prereq_options(_section.get("id", ""), unit.get("id", "")),
            prereqs,
        )
        self._loading = False

    def show_lesson(self, adapter: CourseAdapter, lesson: dict[str, Any]) -> None:
        self._bind(adapter, "lesson", lesson.get("id", ""))
        self._loading = True
        self.id_value.setText(lesson.get("id", ""))
        self.name_edit.setText(lesson.get("name", ""))
        self.desc_edit.setPlainText(lesson.get("description", ""))
        _s, _unit, _l = adapter.find_lesson(lesson.get("id", ""))
        prereqs = lesson.get("prerequisiteLessonIds", [])
        self._fill_prereq(
            adapter.lesson_prereq_options(_unit.get("id", ""), lesson.get("id", "")),
            prereqs,
        )
        self._loading = False

    def _bind(self, adapter: CourseAdapter | None, kind: str, node_id: str) -> None:
        self._adapter = adapter
        self._kind = kind
        self._node_id = node_id
        editable = kind in {"section", "unit", "lesson"}
        self.name_edit.setEnabled(editable)
        self.desc_edit.setEnabled(editable)
        self.prereq_list.setEnabled(editable)

    def _push(self, cmd) -> None:
        if self.undo_stack is not None:
            cmd.signals.changed.connect(self.metadata_changed.emit)
            self.undo_stack.push(cmd)
        else:
            cmd.redo()
            self.metadata_changed.emit()

    def _commit_name_desc(self) -> None:
        if self._loading or self._adapter is None or not self._node_id:
            return
        name = self.name_edit.text()
        desc = self.desc_edit.toPlainText()
        if self._kind == "section":
            self._push(UpdateSectionMetaCommand(self._adapter, self._node_id, name, desc))
        elif self._kind == "unit":
            self._push(UpdateUnitMetaCommand(self._adapter, self._node_id, name, desc))
        elif self._kind == "lesson":
            self._push(UpdateLessonMetaCommand(self._adapter, self._node_id, name, desc))

    def _commit_prereqs(self) -> None:
        if self._loading or self._adapter is None or not self._node_id:
            return
        checked = [
            self.prereq_list.item(i).data(Qt.ItemDataRole.UserRole)
            for i in range(self.prereq_list.count())
            if self.prereq_list.item(i).checkState() == Qt.CheckState.Checked
        ]
        if self._kind == "section":
            self._push(UpdateSectionPrereqsCommand(self._adapter, self._node_id, checked))
        elif self._kind == "unit":
            self._push(UpdateUnitPrereqsCommand(self._adapter, self._node_id, checked))
        elif self._kind == "lesson":
            self._push(UpdateLessonPrereqsCommand(self._adapter, self._node_id, checked))