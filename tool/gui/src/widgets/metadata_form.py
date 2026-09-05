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
    UpdateLessonLinkedGrammarCommand,
    UpdateLessonMetaCommand,
    UpdateLessonPrereqsCommand,
    UpdateSectionMetaCommand,
    UpdateSectionPrereqsCommand,
    UpdateUnitMetaCommand,
    UpdateUnitPrereqsCommand,
)
from src.backend.course_adapter import CourseAdapter
from src.theme import current_palette


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
        palette = current_palette()
        self.setStyleSheet(f"""
            QGroupBox {{
                font-weight: 600;
                margin-top: 8px;
            }}
            QGroupBox::title {{
                color: {palette["text_secondary"]};
                left: 0px;
                top: 4px;
            }}
        """)
        self._adapter: CourseAdapter | None = None
        self._kind: str = ""
        self._node_id: str = ""
        self.undo_stack: QUndoStack | None = None
        self._loading = False
        self._build_ui()

    def _build_ui(self) -> None:
        self.id_value = QLabel("(未选择)")
        self.id_value.setStyleSheet(f"color: {current_palette()['text_disabled']};")
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

        # Lesson-only: content.linkedGrammarPointIds multi-select (G5). The
        # app registers these grammar points into SRS when the course opens.
        self.grammar_link_list = _FocusListWidget()
        self.grammar_link_list.setEnabled(False)
        self.grammar_link_list.setSelectionMode(QListWidget.SelectionMode.NoSelection)
        self.grammar_link_row = QWidget()
        gl_layout = QVBoxLayout(self.grammar_link_row)
        gl_layout.setContentsMargins(0, 0, 0, 0)
        gl_layout.setSpacing(2)
        gl_layout.addWidget(QLabel("关联语法点（开课时注册语法 SRS）"))
        gl_layout.addWidget(self.grammar_link_list)
        form.addRow(self.grammar_link_row)
        self.grammar_link_row.setVisible(False)

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
        self.grammar_link_list.focusLost.connect(self._commit_linked_grammar)

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
        linked = (lesson.get("content") or {}).get("linkedGrammarPointIds", []) or []
        self._fill_grammar_links(adapter.linked_grammar_options(), linked)
        self._loading = False

    def _fill_grammar_links(
        self,
        options: list[tuple[str, str]],
        current: list[str],
    ) -> None:
        """Populate the linked-grammar multi-select; hide it when the course
        has no grammar points to offer and none are linked."""
        if not options and not current:
            self.grammar_link_row.setVisible(False)
            return
        self.grammar_link_row.setVisible(True)
        self._loading = True
        self.grammar_link_list.blockSignals(True)
        self.grammar_link_list.clear()
        current_set = set(current)
        for rid, label in options:
            item = QListWidgetItem(label)
            item.setData(Qt.ItemDataRole.UserRole, rid)
            item.setFlags(item.flags() | Qt.ItemFlag.ItemIsUserCheckable)
            item.setCheckState(
                Qt.CheckState.Checked if rid in current_set else Qt.CheckState.Unchecked
            )
            self.grammar_link_list.addItem(item)
        self.grammar_link_list.blockSignals(False)
        self._loading = False

    def _bind(self, adapter: CourseAdapter | None, kind: str, node_id: str) -> None:
        self._adapter = adapter
        self._kind = kind
        self._node_id = node_id
        editable = kind in {"section", "unit", "lesson"}
        self.name_edit.setEnabled(editable)
        self.desc_edit.setEnabled(editable)
        self.prereq_list.setEnabled(editable)
        # Linked grammar points are a lesson-content concept only.
        if kind != "lesson":
            self.grammar_link_row.setVisible(False)
            self.grammar_link_list.setEnabled(False)

    def focus_name(self) -> None:
        """Focus and select the name field (F2 rename hook)."""
        self.name_edit.setFocus()
        self.name_edit.selectAll()

    def _push(self, cmd) -> None:
        if self.undo_stack is not None:
            cmd.signals.changed.connect(self.metadata_changed.emit)
            self.undo_stack.push(cmd)
        else:
            cmd.redo()
            self.metadata_changed.emit()

    def _current_node(self) -> dict[str, Any] | None:
        if self._adapter is None or not self._node_id:
            return None
        try:
            if self._kind == "section":
                return self._adapter.find_section(self._node_id)
            if self._kind == "unit":
                _s, unit = self._adapter.find_unit(self._node_id)
                return unit
            if self._kind == "lesson":
                _s, _u, lesson = self._adapter.find_lesson(self._node_id)
                return lesson
        except Exception:
            return None
        return None

    def is_in_sync(self) -> bool:
        """Return True if form inputs match the current model node state."""
        if self._adapter is None or not self._node_id:
            return True
        node = self._current_node()
        if node is None:
            return False
        if self.name_edit.text() != (node.get("name") or ""):
            return False
        if self.desc_edit.toPlainText() != (node.get("description") or ""):
            return False
        prereq_key = {
            "section": "prerequisiteSectionIds",
            "unit": "prerequisiteUnitIds",
            "lesson": "prerequisiteLessonIds",
        }.get(self._kind)
        if prereq_key:
            model_prereqs = list(node.get(prereq_key) or [])
            ui_prereqs = [
                self.prereq_list.item(i).data(Qt.ItemDataRole.UserRole)
                for i in range(self.prereq_list.count())
                if self.prereq_list.item(i).checkState() == Qt.CheckState.Checked
            ]
            if set(ui_prereqs) != set(model_prereqs):
                return False
        if self._kind == "lesson" and self.grammar_link_row.isVisible():
            model_grammar = list((node.get("content") or {}).get("linkedGrammarPointIds") or [])
            ui_grammar = [
                self.grammar_link_list.item(i).data(Qt.ItemDataRole.UserRole)
                for i in range(self.grammar_link_list.count())
                if self.grammar_link_list.item(i).checkState() == Qt.CheckState.Checked
            ]
            if set(ui_grammar) != set(model_grammar):
                return False
        return True

    def _commit_name_desc(self) -> None:
        if self._loading or self._adapter is None or not self._node_id:
            return
        node = self._current_node()
        if node is None:
            return
        name = self.name_edit.text()
        desc = self.desc_edit.toPlainText()
        if name == (node.get("name") or "") and desc == (node.get("description") or ""):
            return
        if self._kind == "section":
            self._push(UpdateSectionMetaCommand(self._adapter, self._node_id, name, desc))
        elif self._kind == "unit":
            self._push(UpdateUnitMetaCommand(self._adapter, self._node_id, name, desc))
        elif self._kind == "lesson":
            self._push(UpdateLessonMetaCommand(self._adapter, self._node_id, name, desc))

    def _commit_prereqs(self) -> None:
        if self._loading or self._adapter is None or not self._node_id:
            return
        node = self._current_node()
        if node is None:
            return
        prereq_key = {
            "section": "prerequisiteSectionIds",
            "unit": "prerequisiteUnitIds",
            "lesson": "prerequisiteLessonIds",
        }.get(self._kind)
        if not prereq_key:
            return
        checked = [
            self.prereq_list.item(i).data(Qt.ItemDataRole.UserRole)
            for i in range(self.prereq_list.count())
            if self.prereq_list.item(i).checkState() == Qt.CheckState.Checked
        ]
        model_prereqs = list(node.get(prereq_key) or [])
        if checked == model_prereqs or (not checked and not model_prereqs):
            return
        if self._kind == "section":
            self._push(UpdateSectionPrereqsCommand(self._adapter, self._node_id, checked))
        elif self._kind == "unit":
            self._push(UpdateUnitPrereqsCommand(self._adapter, self._node_id, checked))
        elif self._kind == "lesson":
            self._push(UpdateLessonPrereqsCommand(self._adapter, self._node_id, checked))

    def _commit_linked_grammar(self) -> None:
        if self._loading or self._adapter is None or not self._node_id:
            return
        if self._kind != "lesson" or not self.grammar_link_row.isVisible():
            return
        node = self._current_node()
        if node is None:
            return
        checked = [
            self.grammar_link_list.item(i).data(Qt.ItemDataRole.UserRole)
            for i in range(self.grammar_link_list.count())
            if self.grammar_link_list.item(i).checkState() == Qt.CheckState.Checked
        ]
        model_grammar = list((node.get("content") or {}).get("linkedGrammarPointIds") or [])
        if checked == model_grammar or (not checked and not model_grammar):
            return
        self._push(
            UpdateLessonLinkedGrammarCommand(self._adapter, self._node_id, checked)
        )