"""Three-level course tree: Section -> Unit -> Lesson with context menu."""
from __future__ import annotations

from PySide6.QtCore import Qt, Signal
from PySide6.QtGui import QAction
from PySide6.QtWidgets import QMenu, QTreeWidget, QTreeWidgetItem

from src.backend.course_adapter import CourseAdapter


class CourseTreeWidget(QTreeWidget):
    """Left-pane tree showing Section / Unit / Lesson hierarchy."""

    node_selected = Signal(tuple)  # (kind, id)
    tree_changed = Signal()

    def __init__(self) -> None:
        super().__init__()
        self.adapter: CourseAdapter | None = None
        self.setHeaderLabels(["课程结构", "类型"])
        self.setColumnWidth(0, 280)
        self.setIndentation(18)
        self.setUniformRowHeights(True)
        self.setAlternatingRowColors(False)
        self.itemClicked.connect(self._on_clicked)
        self.setContextMenuPolicy(Qt.ContextMenuPolicy.CustomContextMenu)
        self.customContextMenuRequested.connect(self._on_context_menu)

    def display(self, adapter: CourseAdapter) -> None:
        self.adapter = adapter
        self.clear()
        for section in adapter.sections:
            sid = section.get("id", "")
            s_item = QTreeWidgetItem([f"📁 {section.get('name', sid)}", "section"])
            s_item.setData(0, 0x0100, ("section", sid))
            self.addTopLevelItem(s_item)
            for unit in section.get("units", []):
                uid = unit.get("id", "")
                u_item = QTreeWidgetItem([f"📂 {unit.get('name', uid)}", "unit"])
                u_item.setData(0, 0x0100, ("unit", uid))
                s_item.addChild(u_item)
                for lesson in unit.get("lessons", []):
                    lid = lesson.get("id", "")
                    tmpl = lesson.get("template", "")
                    label = lesson.get("name", lid)
                    l_item = QTreeWidgetItem([f"📝 {label}", f"lesson ({tmpl})"])
                    l_item.setData(0, 0x0100, ("lesson", lid))
                    u_item.addChild(l_item)
        self.expandToDepth(1)

    def refresh(self) -> None:
        if self.adapter is not None:
            self.display(self.adapter)

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
        elif kind == "section":
            act_new_unit = QAction("新建 Unit", self)
            act_new_unit.triggered.connect(lambda: self._new_unit(node_id))
            menu.addAction(act_new_unit)
        elif kind == "lesson":
            act_del_lesson = QAction("删除 Lesson", self)
            act_del_lesson.triggered.connect(lambda: self._delete_lesson(node_id))
            menu.addAction(act_del_lesson)
        if not menu.isEmpty():
            menu.exec(self.viewport().mapToGlobal(pos))

    def _new_lesson(self, unit_id: str) -> None:
        from src.dialogs.new_lesson_dialog import NewLessonDialog
        dlg = NewLessonDialog(self)
        if dlg.exec():
            template = dlg.template()
            name = dlg.lesson_name()
            lid = self.adapter.new_lesson(unit_id, template)
            if name:
                _s, _u, lesson = self.adapter.find_lesson(lid)
                lesson["name"] = name
            self.refresh()
            self.tree_changed.emit()

    def _new_unit(self, section_id: str) -> None:
        self.adapter.new_unit(section_id)
        self.refresh()
        self.tree_changed.emit()

    def _delete_lesson(self, lesson_id: str) -> None:
        from PySide6.QtWidgets import QMessageBox
        reply = QMessageBox.question(
            self, "删除 Lesson", "确认删除该 Lesson？保存时 validate 会校验。",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
        )
        if reply == QMessageBox.StandardButton.Yes:
            self.adapter.delete_lesson(lesson_id)
            self.refresh()
            self.tree_changed.emit()

    def _delete_unit(self, unit_id: str) -> None:
        from PySide6.QtWidgets import QMessageBox
        reply = QMessageBox.question(
            self, "删除 Unit", "确认删除该 Unit 及其所有 Lesson？保存时 validate 会校验。",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
        )
        if reply == QMessageBox.StandardButton.Yes:
            self.adapter.delete_unit(unit_id)
            self.refresh()
            self.tree_changed.emit()