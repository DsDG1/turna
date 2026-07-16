"""Three-level course tree: Section -> Unit -> Lesson with context menu."""
from __future__ import annotations

from PySide6.QtCore import Qt, Signal
from PySide6.QtGui import QAction, QColor, QUndoStack
from PySide6.QtWidgets import (
    QHBoxLayout,
    QLabel,
    QMenu,
    QStyle,
    QToolButton,
    QTreeWidget,
    QTreeWidgetItem,
    QVBoxLayout,
    QWidget,
)
from typing import Any

from src.application.commands import (
    DeleteLessonCommand,
    DeleteSectionCommand,
    DeleteUnitCommand,
    MoveLessonCommand,
    MoveSectionCommand,
    MoveUnitCommand,
    NewLessonCommand,
    NewUnitCommand,
)
from src.backend.course_adapter import CourseAdapter
from src.theme import current_palette


class CourseTreeWidget(QTreeWidget):
    """Left-pane tree showing Section / Unit / Lesson hierarchy."""

    node_selected = Signal(tuple)  # (kind, id)
    tree_changed = Signal()
    ai_edit_requested = Signal(str, str)  # (kind, id)
    ai_fix_requested = Signal(str, str)  # (kind, id)

    def __init__(self) -> None:
        super().__init__()
        self.adapter: CourseAdapter | None = None
        self.undo_stack: QUndoStack | None = None
        self.setHeaderLabels(["课程结构", "类型"])
        self.setColumnWidth(0, 280)
        self.setIndentation(20)
        self.setUniformRowHeights(True)
        self.setAlternatingRowColors(False)
        self.itemClicked.connect(self._on_clicked)
        self.setContextMenuPolicy(Qt.ContextMenuPolicy.CustomContextMenu)
        self.customContextMenuRequested.connect(self._on_context_menu)

    def display(self, adapter: CourseAdapter) -> None:
        self.adapter = adapter
        self.clear()
        self._populate(adapter)
        self.expandToDepth(1)

    def _populate(self, adapter: CourseAdapter) -> None:
        """Build all tree items from the adapter. Called after clear()."""
        style = self.style()
        secondary = QColor(current_palette()["text_secondary"])
        section_icon = style.standardIcon(QStyle.StandardPixmap.SP_DirHomeIcon)
        unit_icon = style.standardIcon(QStyle.StandardPixmap.SP_FileDialogContentsView)
        lesson_icon = style.standardIcon(QStyle.StandardPixmap.SP_FileIcon)
        for section in adapter.sections:
            sid = section.get("id", "")
            s_item = QTreeWidgetItem([section.get('name', sid), "section"])
            s_item.setData(0, 0x0100, ("section", sid))
            s_item.setIcon(0, section_icon)
            s_item.setForeground(1, secondary)
            self.addTopLevelItem(s_item)
            for unit in section.get("units", []):
                uid = unit.get("id", "")
                u_item = QTreeWidgetItem([unit.get('name', uid), "unit"])
                u_item.setData(0, 0x0100, ("unit", uid))
                u_item.setIcon(0, unit_icon)
                u_item.setForeground(1, secondary)
                s_item.addChild(u_item)
                for lesson in unit.get("lessons", []):
                    lid = lesson.get("id", "")
                    tmpl = lesson.get("template", "")
                    label = lesson.get("name", lid)
                    l_item = QTreeWidgetItem([label, f"lesson ({tmpl})"])
                    l_item.setData(0, 0x0100, ("lesson", lid))
                    l_item.setIcon(0, lesson_icon)
                    l_item.setForeground(1, secondary)
                    u_item.addChild(l_item)

    def _capture_state(self) -> dict[str, Any]:
        """Snapshot expand/selection/scroll state keyed by node id.

        Returns a dict with:
          expanded_section_ids: set[str]
          expanded_unit_ids: set[str]
          selected_ref: tuple[str, str] | None
          scroll_value: int
        """
        expanded_sections: set[str] = set()
        expanded_units: set[str] = set()
        for top_idx in range(self.topLevelItemCount()):
            section_item = self.topLevelItem(top_idx)
            if section_item is None:
                continue
            ref = section_item.data(0, 0x0100)
            if ref is None or ref[0] != "section":
                continue
            if section_item.isExpanded():
                expanded_sections.add(ref[1])
            for i in range(section_item.childCount()):
                unit_item = section_item.child(i)
                if unit_item is None:
                    continue
                uref = unit_item.data(0, 0x0100)
                if uref is None or uref[0] != "unit":
                    continue
                if unit_item.isExpanded():
                    expanded_units.add(uref[1])

        current = self.currentItem()
        selected_ref: tuple[str, str] | None = None
        selected_parent_ref: tuple[str, str] | None = None
        if current is not None:
            selected_ref = current.data(0, 0x0100)
            parent_item = current.parent()
            if parent_item is not None:
                selected_parent_ref = parent_item.data(0, 0x0100)

        scroll_value = self.verticalScrollBar().value() if self.verticalScrollBar() else 0
        return {
            "expanded_section_ids": expanded_sections,
            "expanded_unit_ids": expanded_units,
            "selected_ref": selected_ref,
            "selected_parent_ref": selected_parent_ref,
            "scroll_value": scroll_value,
        }

    def _restore_state(self, state: dict[str, Any]) -> None:
        """Restore expand/selection/scroll state captured by _capture_state.

        If the previously selected node no longer exists, walk up to its
        parent unit / section and select that; otherwise clear selection.
        """
        expanded_sections: set[str] = state.get("expanded_section_ids", set())
        expanded_units: set[str] = state.get("expanded_unit_ids", set())
        selected_ref = state.get("selected_ref")
        scroll_value = state.get("scroll_value", 0)

        item_by_ref: dict[tuple[str, str], QTreeWidgetItem] = {}
        parent_ref_by_ref: dict[tuple[str, str], tuple[str, str] | None] = {}
        for top_idx in range(self.topLevelItemCount()):
            section_item = self.topLevelItem(top_idx)
            if section_item is None:
                continue
            sref = section_item.data(0, 0x0100)
            if sref is None:
                continue
            item_by_ref[sref] = section_item
            parent_ref_by_ref[sref] = None
            if sref[0] == "section" and sref[1] in expanded_sections:
                section_item.setExpanded(True)
            for i in range(section_item.childCount()):
                unit_item = section_item.child(i)
                if unit_item is None:
                    continue
                uref = unit_item.data(0, 0x0100)
                if uref is None:
                    continue
                item_by_ref[uref] = unit_item
                parent_ref_by_ref[uref] = sref
                if uref[0] == "unit" and uref[1] in expanded_units:
                    unit_item.setExpanded(True)
                for j in range(unit_item.childCount()):
                    lesson_item = unit_item.child(j)
                    if lesson_item is None:
                        continue
                    lref = lesson_item.data(0, 0x0100)
                    if lref is None:
                        continue
                    item_by_ref[lref] = lesson_item
                    parent_ref_by_ref[lref] = uref

        target_item: QTreeWidgetItem | None = None
        if selected_ref is not None:
            target_item = item_by_ref.get(selected_ref)
            if target_item is None:
                # If the removed node was a lesson, fall back to its captured
                # parent unit (which usually still exists). For units/sections
                # we keep the previous behavior of walking the parent chain or
                # clearing selection.
                captured_parent = state.get("selected_parent_ref")
                if (
                    selected_ref[0] == "lesson"
                    and captured_parent is not None
                ):
                    target_item = item_by_ref.get(captured_parent)
                if target_item is None:
                    parent_ref = parent_ref_by_ref.get(selected_ref)
                    while parent_ref is not None:
                        candidate = item_by_ref.get(parent_ref)
                        if candidate is not None:
                            target_item = candidate
                            break
                        parent_ref = parent_ref_by_ref.get(parent_ref)

        if target_item is not None:
            self.setCurrentItem(target_item)
        else:
            self.setCurrentItem(None)

        sb = self.verticalScrollBar()
        if sb is not None:
            sb.setValue(scroll_value)

    def refresh_incremental(self) -> None:
        """Rebuild the tree while preserving expand/selection/scroll state.

        Falls back to full display() on first load (no adapter set) or when
        the adapter is None. Use this instead of refresh() during edits to
        avoid losing the user's expand/selection state on every mutation.
        """
        if self.adapter is None:
            return
        state = self._capture_state()
        self.clear()
        self._populate(self.adapter)
        self._restore_state(state)

    def refresh(self) -> None:
        """Incremental refresh by default; full display() is reserved for
        first load (see display()). Override point for subclasses that need
        full rebuild semantics."""
        if self.adapter is not None:
            self.refresh_incremental()

    def select_lesson(self, lesson_id: str) -> None:
        """Find and select the lesson item across all sections, emitting node_selected."""
        for top_idx in range(self.topLevelItemCount()):
            section = self.topLevelItem(top_idx)
            for i in range(section.childCount()):
                unit = section.child(i)
                for j in range(unit.childCount()):
                    lesson = unit.child(j)
                    ref = lesson.data(0, 0x0100)
                    if ref and ref[0] == "lesson" and ref[1] == lesson_id:
                        self.setCurrentItem(lesson)
                        self.node_selected.emit(ref)
                        return

    def select_section(self, section_id: str) -> None:
        """Find and select the section item, emitting node_selected."""
        for top_idx in range(self.topLevelItemCount()):
            section = self.topLevelItem(top_idx)
            ref = section.data(0, 0x0100)
            if ref and ref[0] == "section" and ref[1] == section_id:
                self.setCurrentItem(section)
                self.node_selected.emit(ref)
                return

    def _on_clicked(self, item: QTreeWidgetItem) -> None:
        ref = item.data(0, 0x0100)
        if ref is not None:
            self.node_selected.emit(ref)

    def _on_context_menu(self, pos) -> None:
        item = self.itemAt(pos)
        if item is None or self.adapter is None:
            return
        ref = item.data(0, 0x0100)
        if ref is None:
            return
        kind, node_id = ref
        menu = QMenu(self)
        if kind == "unit":
            act_new_lesson = QAction("新建 Lesson", self)
            act_new_lesson.triggered.connect(lambda: self._new_lesson(node_id))
            menu.addAction(act_new_lesson)
            act_del_unit = QAction("删除 Unit", self)
            act_del_unit.triggered.connect(lambda: self._delete_unit(node_id))
            menu.addAction(act_del_unit)
            menu.addSeparator()
            act_ai_edit = QAction("AI 编辑此 Unit", self)
            act_ai_edit.triggered.connect(
                lambda: self.ai_edit_requested.emit("unit", node_id)
            )
            menu.addAction(act_ai_edit)
            act_ai_fix = QAction("AI 修正此 Unit", self)
            act_ai_fix.triggered.connect(
                lambda: self.ai_fix_requested.emit("unit", node_id)
            )
            menu.addAction(act_ai_fix)
        elif kind == "section":
            act_new_unit = QAction("新建 Unit", self)
            act_new_unit.triggered.connect(lambda: self._new_unit(node_id))
            menu.addAction(act_new_unit)
            act_del_section = QAction("删除 Section", self)
            act_del_section.triggered.connect(lambda: self._delete_section(node_id))
            menu.addAction(act_del_section)
            menu.addSeparator()
            act_ai_edit = QAction("AI 编辑此 Section", self)
            act_ai_edit.triggered.connect(
                lambda: self.ai_edit_requested.emit("section", node_id)
            )
            menu.addAction(act_ai_edit)
            act_ai_fix = QAction("AI 修正此 Section", self)
            act_ai_fix.triggered.connect(
                lambda: self.ai_fix_requested.emit("section", node_id)
            )
            menu.addAction(act_ai_fix)
        elif kind == "lesson":
            act_del_lesson = QAction("删除 Lesson", self)
            act_del_lesson.triggered.connect(lambda: self._delete_lesson(node_id))
            menu.addAction(act_del_lesson)
            menu.addSeparator()
            act_ai_edit = QAction("AI 编辑此 Lesson", self)
            act_ai_edit.triggered.connect(
                lambda: self.ai_edit_requested.emit("lesson", node_id)
            )
            menu.addAction(act_ai_edit)
            act_ai_fix = QAction("AI 修正此 Lesson", self)
            act_ai_fix.triggered.connect(
                lambda: self.ai_fix_requested.emit("lesson", node_id)
            )
            menu.addAction(act_ai_fix)
        if not menu.isEmpty():
            menu.exec(self.viewport().mapToGlobal(pos))

    def _push(self, cmd) -> None:
        """Push a command onto the undo stack if available, else run redo once."""
        if self.undo_stack is not None:
            self.undo_stack.push(cmd)
        else:
            cmd.redo()
            self.refresh_incremental()
            self.tree_changed.emit()

    def _new_lesson(self, unit_id: str) -> None:
        from src.dialogs.new_lesson_dialog import NewLessonDialog
        dlg = NewLessonDialog(self)
        if dlg.exec():
            template = dlg.template()
            name = dlg.lesson_name()
            cmd = NewLessonCommand(self.adapter, unit_id, template, name)
            cmd.signals.changed.connect(self._on_command_changed)
            self._push(cmd)

    def _new_unit(self, section_id: str) -> None:
        cmd = NewUnitCommand(self.adapter, section_id)
        cmd.signals.changed.connect(self._on_command_changed)
        self._push(cmd)

    def _delete_lesson(self, lesson_id: str) -> None:
        from PySide6.QtWidgets import QMessageBox
        reply = QMessageBox.question(
            self, "删除 Lesson", "确认删除该 Lesson？保存时 validate 会校验。",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
        )
        if reply == QMessageBox.StandardButton.Yes:
            cmd = DeleteLessonCommand(self.adapter, lesson_id)
            cmd.signals.changed.connect(self._on_command_changed)
            self._push(cmd)

    def _delete_unit(self, unit_id: str) -> None:
        from PySide6.QtWidgets import QMessageBox
        reply = QMessageBox.question(
            self, "删除 Unit", "确认删除该 Unit 及其所有 Lesson？保存时 validate 会校验。",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
        )
        if reply == QMessageBox.StandardButton.Yes:
            cmd = DeleteUnitCommand(self.adapter, unit_id)
            cmd.signals.changed.connect(self._on_command_changed)
            self._push(cmd)

    def _delete_section(self, section_id: str) -> None:
        from PySide6.QtWidgets import QMessageBox
        refs = self.adapter.section_is_referenced(section_id)
        if refs:
            QMessageBox.warning(
                self,
                "无法删除 Section",
                "以下 Section 的先修依赖引用了该 Section，请先解除依赖再删除：\n"
                + ", ".join(refs),
            )
            return
        reply = QMessageBox.question(
            self,
            "删除 Section",
            "确认删除该 Section 及其所有 Unit / Lesson？保存时 validate 会校验。",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
        )
        if reply == QMessageBox.StandardButton.Yes:
            cmd = DeleteSectionCommand(self.adapter, section_id)
            cmd.signals.changed.connect(self._on_command_changed)
            self._push(cmd)

    def _on_command_changed(self) -> None:
        """Refresh the tree and notify listeners after any structural command."""
        self.refresh_incremental()
        self.tree_changed.emit()

    # --- sibling reorder (up/down arrow buttons) ------------------------

    def wrap_with_move_toolbar(self) -> QWidget:
        """Wrap this tree in a container with ↑/↓ toolbar buttons above it.

        The returned container owns the toolbar; this widget is re-parented
        into it. Callers add the container to their layout and keep using
        ``self.tree`` (this widget) directly for selection/refresh APIs.
        """
        container = QWidget()
        layout = QVBoxLayout(container)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(4)

        bar = QHBoxLayout()
        bar.setContentsMargins(2, 2, 2, 2)
        bar.setSpacing(4)
        bar.addWidget(QLabel("上下移动:"))
        self._move_up_btn = QToolButton()
        self._move_up_btn.setText("↑")
        self._move_up_btn.setToolTip("上移（仅同级，不改变层级）")
        self._move_up_btn.setEnabled(False)
        self._move_up_btn.clicked.connect(lambda: self._move_current(-1))
        bar.addWidget(self._move_up_btn)
        self._move_down_btn = QToolButton()
        self._move_down_btn.setText("↓")
        self._move_down_btn.setToolTip("下移（仅同级，不改变层级）")
        self._move_down_btn.setEnabled(False)
        self._move_down_btn.clicked.connect(lambda: self._move_current(1))
        bar.addWidget(self._move_down_btn)
        bar.addStretch()
        layout.addLayout(bar)

        self.setParent(container)
        layout.addWidget(self)
        # Keep selection-driven enable/disable in sync.
        self.currentItemChanged.connect(self._update_move_buttons)
        return container

    def _sibling_index(self, ref: tuple[str, str]) -> tuple[list[Any], int, dict[str, Any] | None] | None:
        """Return (sibling_list, current_index, parent_node) for a ref.

        parent_node is the section dict (for units) or unit dict (for
        lessons); None for sections. Returns None if the ref cannot be
        located (e.g. adapter not set or stale id).
        """
        if self.adapter is None or ref is None:
            return None
        kind, node_id = ref
        if kind == "section":
            for i, s in enumerate(self.adapter.sections):
                if s.get("id") == node_id:
                    return self.adapter.sections, i, None
        elif kind == "unit":
            try:
                section, _unit = self.adapter.find_unit(node_id)
            except KeyError:
                return None
            units = section.get("units", [])
            for i, u in enumerate(units):
                if u.get("id") == node_id:
                    return units, i, section
        elif kind == "lesson":
            try:
                _s, unit, _l = self.adapter.find_lesson(node_id)
            except KeyError:
                return None
            lessons = unit.get("lessons", [])
            for i, l in enumerate(lessons):
                if l.get("id") == node_id:
                    return lessons, i, unit
        return None

    def _update_move_buttons(self, *_args) -> None:
        """Enable ↑/↓ based on whether the current item can move in-sibling."""
        if not hasattr(self, "_move_up_btn"):
            return
        current = self.currentItem()
        ref = current.data(0, 0x0100) if current is not None else None
        info = self._sibling_index(ref) if ref is not None else None
        if info is None:
            self._move_up_btn.setEnabled(False)
            self._move_down_btn.setEnabled(False)
            return
        siblings, idx, _parent = info
        self._move_up_btn.setEnabled(idx > 0)
        self._move_down_btn.setEnabled(idx < len(siblings) - 1)

    def _move_current(self, direction: int) -> None:
        """Move the current item up (direction=-1) or down (+1) within its
        sibling list. No-op at bounds or when nothing is selected — this
        guarantees same-level-only reorder (hierarchy never changes)."""
        if self.adapter is None:
            return
        current = self.currentItem()
        if current is None:
            return
        ref = current.data(0, 0x0100)
        info = self._sibling_index(ref)
        if info is None:
            return
        siblings, idx, parent = info
        to_idx = idx + direction
        if not (0 <= to_idx < len(siblings)):
            return  # bounds — no-op, no command pushed
        kind, node_id = ref
        if kind == "section":
            cmd: Any = MoveSectionCommand(self.adapter, idx, to_idx)
        elif kind == "unit":
            cmd = MoveUnitCommand(self.adapter, parent.get("id", ""), idx, to_idx)
        elif kind == "lesson":
            cmd = MoveLessonCommand(self.adapter, parent.get("id", ""), idx, to_idx)
        else:
            return
        cmd.signals.changed.connect(self._on_command_changed)
        self._push(cmd)