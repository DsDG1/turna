"""Merge preview dialog for AI-generated section imports.

Shows which units/lessons will be added or replaced and lets the user uncheck
individual replacements before applying the merge.
"""
from __future__ import annotations

from typing import Any

from PySide6.QtCore import Qt
from PySide6.QtWidgets import (
    QDialog,
    QDialogButtonBox,
    QLabel,
    QTreeWidget,
    QTreeWidgetItem,
    QVBoxLayout,
)

from src.backend.course_adapter import MergeAction, SectionMergePlan


class AiMergePreviewDialog(QDialog):
    """Preview and adjust a section merge plan."""

    def __init__(
        self,
        plan: SectionMergePlan,
        parent=None,
    ) -> None:
        super().__init__(parent)
        self.setWindowTitle("AI 导入合并预览")
        self.resize(560, 480)
        self._plan = plan
        self._item_to_action: dict[int, MergeAction] = {}
        self._build_ui()
        self._populate_tree()
        self._update_summary()

    def _build_ui(self) -> None:
        layout = QVBoxLayout(self)
        layout.setSpacing(12)
        layout.setContentsMargins(16, 16, 16, 16)

        layout.addWidget(
            QLabel(
                "AI 返回的 section 与现有课程存在 id 重叠。"
                "默认会覆盖重叠的 unit/lesson，您可取消勾选以跳过某项。"
            )
        )

        self.tree = QTreeWidget()
        self.tree.setHeaderLabels(["节点", "操作"])
        self.tree.setColumnWidth(0, 360)
        self.tree.itemChanged.connect(self._on_item_changed)
        layout.addWidget(self.tree, 1)

        self.summary_label = QLabel()
        self.summary_label.setWordWrap(True)
        layout.addWidget(self.summary_label)

        buttons = QDialogButtonBox(
            QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel
        )
        buttons.button(QDialogButtonBox.StandardButton.Ok).setText("应用")
        buttons.button(QDialogButtonBox.StandardButton.Cancel).setText("取消")
        buttons.accepted.connect(self.accept)
        buttons.rejected.connect(self.reject)
        layout.addWidget(buttons)

    def _populate_tree(self) -> None:
        incoming = self._plan.incoming_section
        sid = self._plan.target_section_id or incoming.get("id", "")
        section_name = incoming.get("name", sid)
        root = QTreeWidgetItem(self.tree, [f"Section: {section_name} ({sid})", ""])
        root.setFlags(root.flags() & ~Qt.ItemFlag.ItemIsSelectable)

        # Replaced units (existing ones that will be overwritten).
        for action in self._plan.replaced_units:
            unit = action.incoming
            uid = unit.get("id", "")
            name = unit.get("name", uid)
            item = QTreeWidgetItem(root, [f"Unit: {name} ({uid})", "覆盖"])
            item.setFlags(
                item.flags()
                | Qt.ItemFlag.ItemIsUserCheckable
                | Qt.ItemFlag.ItemIsEnabled
            )
            item.setCheckState(0, Qt.CheckState.Checked)
            self._item_to_action[id(item)] = action

            replaced_lessons = self._plan.replaced_lessons_by_unit.get(uid, [])
            added_lessons = self._plan.added_lessons_by_unit.get(uid, [])
            for lesson_action in replaced_lessons + added_lessons:
                lesson = lesson_action.incoming
                lid = lesson.get("id", "")
                lname = lesson.get("name", lid)
                if lesson_action.action == "replace":
                    child = QTreeWidgetItem(
                        item, [f"Lesson: {lname} ({lid})", "覆盖"]
                    )
                    child.setFlags(
                        child.flags()
                        | Qt.ItemFlag.ItemIsUserCheckable
                        | Qt.ItemFlag.ItemIsEnabled
                    )
                    child.setCheckState(0, Qt.CheckState.Checked)
                else:
                    child = QTreeWidgetItem(
                        item, [f"Lesson: {lname} ({lid})", "新增"]
                    )
                    child.setFlags(child.flags() & ~Qt.ItemFlag.ItemIsSelectable)
                self._item_to_action[id(child)] = lesson_action

        # Added units (new ones appended at the end).
        for action in self._plan.added_units:
            unit = action.incoming
            uid = unit.get("id", "")
            name = unit.get("name", uid)
            item = QTreeWidgetItem(root, [f"Unit: {name} ({uid})", "新增"])
            item.setFlags(item.flags() & ~Qt.ItemFlag.ItemIsSelectable)
            self._item_to_action[id(item)] = action

        root.setExpanded(True)

    def _on_item_changed(self, item: QTreeWidgetItem, column: int) -> None:
        if column != 0:
            return
        action = self._item_to_action.get(id(item))
        if action is None:
            return
        checked = item.checkState(0) == Qt.CheckState.Checked
        action.action = "replace" if checked else "skip"

        # If a unit is unchecked, skip its child lesson actions as well.
        if action.kind == "unit" and action.action == "skip":
            for i in range(item.childCount()):
                child = item.child(i)
                child_action = self._item_to_action.get(id(child))
                if child_action is not None:
                    child_action.action = "skip"
                    if child.flags() & Qt.ItemFlag.ItemIsUserCheckable:
                        child.setCheckState(0, Qt.CheckState.Unchecked)
        self._update_summary()

    def _update_summary(self) -> None:
        add_units = sum(1 for a in self._plan.added_units if a.action != "skip")
        replace_units = sum(
            1 for a in self._plan.replaced_units if a.action != "skip"
        )
        add_lessons = 0
        replace_lessons = 0
        for action in self._plan.replaced_units:
            if action.action == "skip":
                continue
            uid = action.incoming.get("id", "")
            for la in self._plan.added_lessons_by_unit.get(uid, []):
                if la.action != "skip":
                    add_lessons += 1
            for la in self._plan.replaced_lessons_by_unit.get(uid, []):
                if la.action != "skip":
                    replace_lessons += 1

        self.summary_label.setText(
            f"预计：新增 {add_units} 个 unit，覆盖 {replace_units} 个 unit；"
            f"新增 {add_lessons} 个 lesson，覆盖 {replace_lessons} 个 lesson。"
        )

    def plan(self) -> SectionMergePlan:
        """Return the plan with user-adjusted actions."""
        return self._plan
