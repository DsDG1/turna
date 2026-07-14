"""Right-side detail panel container: switches form by selected node kind."""
from __future__ import annotations

from typing import Any

from PySide6.QtCore import Signal
from PySide6.QtWidgets import QLabel, QSplitter, QVBoxLayout, QWidget

from src.backend.course_adapter import CourseAdapter
from src.widgets.metadata_form import MetadataForm
from src.widgets.lesson_editor import LessonEditor


class DetailPanel(QWidget):
    """Container that shows the metadata form + content editor for a node."""

    tree_changed = Signal()

    def __init__(self) -> None:
        super().__init__()
        layout = QVBoxLayout(self)
        layout.setContentsMargins(16, 16, 16, 16)
        layout.setSpacing(12)

        self.breadcrumb = QLabel("编辑内容")
        self.breadcrumb.setObjectName("breadcrumbLabel")
        self.breadcrumb.setStyleSheet("font-size: 13px; color: #9CA3AF;")
        layout.addWidget(self.breadcrumb)

        self.title = QLabel("选择左侧节点开始编辑")
        self.title.setObjectName("titleLabel")
        self.title.setStyleSheet("font-size: 20px; font-weight: 700; color: #FFFFFF;")
        layout.addWidget(self.title)

        self.splitter = QSplitter()
        self.form = MetadataForm()
        self.splitter.addWidget(self.form)
        self.content_host = QWidget()
        self.content_layout = QVBoxLayout(self.content_host)
        self.content_layout.setContentsMargins(0, 0, 0, 0)
        self.content_layout.setSpacing(12)
        self.splitter.addWidget(self.content_host)
        self.splitter.setStretchFactor(0, 1)
        self.splitter.setStretchFactor(1, 3)
        layout.addWidget(self.splitter, 1)

        self.adapter: CourseAdapter | None = None
        self._current_content_widget: QWidget | None = None
        self._resource_listener = self._on_resources_changed

    def clear_content(self) -> None:
        while self.content_layout.count():
            child = self.content_layout.takeAt(0)
            if child.widget():
                child.widget().deleteLater()
        self._current_content_widget = None

    def _attach_adapter(self, adapter: CourseAdapter) -> None:
        """Swap the resource-change listener to the new adapter (A3)."""
        if self.adapter is adapter and adapter is not None:
            return
        if self.adapter is not None:
            self.adapter.remove_resource_listener(self._resource_listener)
        self.adapter = adapter
        if adapter is not None:
            adapter.add_resource_listener(self._resource_listener)

    def _inject_form_undo_stack(self) -> None:
        """Give the metadata form access to the shared undo stack and wire its
        metadata_changed signal to tree_changed so the tree title updates."""
        stack = getattr(self, "undo_stack", None)
        self.form.undo_stack = stack
        try:
            self.form.metadata_changed.disconnect()
        except (TypeError, RuntimeError):
            pass
        self.form.metadata_changed.connect(self.tree_changed.emit)

    def _on_resources_changed(self) -> None:
        """Resource lists changed; refresh the current content widget's
        reference dropdowns in place instead of reloading the whole node."""
        widget = self._current_content_widget
        if widget is None:
            return
        refresh = getattr(widget, "refresh_references", None)
        if callable(refresh):
            try:
                refresh()
            except Exception:
                pass

    def show_node(self, adapter: CourseAdapter, node_ref: tuple[str, str]) -> None:
        self._attach_adapter(adapter)
        self._inject_form_undo_stack()
        kind, node_id = node_ref
        self.clear_content()
        try:
            if kind == "section":
                section = adapter.find_section(node_id)
                self.form.show_section(adapter, section)
                self.title.setText(section.get("name", node_id))
                self.breadcrumb.setText(f"编辑内容  ›  Section")
            elif kind == "unit":
                _section, unit = adapter.find_unit(node_id)
                self.form.show_unit(adapter, unit)
                self.title.setText(unit.get("name", node_id))
                self.breadcrumb.setText(
                    f"编辑内容  ›  {_section.get('name', '')}  ›  Unit"
                )
            elif kind == "lesson":
                section, unit, lesson = adapter.find_lesson(node_id)
                self.form.show_lesson(adapter, lesson)
                self.title.setText(lesson.get("name", node_id))
                self.breadcrumb.setText(
                    f"编辑内容  ›  {section.get('name', '')}  /  "
                    f"{unit.get('name', '')}  /  {lesson.get('name', '')}"
                )
                editor = LessonEditor(adapter, lesson)
                self.content_layout.addWidget(editor)
                self._current_content_widget = editor
        except KeyError:
            self.title.setText(f"未找到节点: {node_id}")
            self.breadcrumb.setText("编辑内容")

    def show_teacher_lesson(
        self,
        adapter: CourseAdapter,
        section: dict[str, Any],
        unit: dict[str, Any],
        lesson: dict[str, Any],
    ) -> None:
        """Show the teacher-view widget for this lesson's template."""
        from PySide6.QtWidgets import QScrollArea

        from src.teacher.linear_flow import LinearFlowWidget
        from src.teacher.template_editors import (
            ListeningTeacherWidget,
            MasteryTeacherWidget,
            ReadingTeacherWidget,
        )

        self._attach_adapter(adapter)
        self._inject_form_undo_stack()
        self.clear_content()
        self.form.show_lesson(adapter, lesson)
        self.title.setText(lesson.get("name", lesson.get("id", "")))
        self.breadcrumb.setText(
            f"编辑内容  ›  {section.get('name', '')}  /  "
            f"{unit.get('name', '')}  /  {lesson.get('name', '')}"
        )

        undo_stack = getattr(self, "undo_stack", None)
        template = lesson.get("template", "legacy")
        if template in ("listening",):
            widget: QWidget = ListeningTeacherWidget(adapter, section, unit, lesson, self, undo_stack)
        elif template in ("reading",):
            widget = ReadingTeacherWidget(adapter, section, unit, lesson, self, undo_stack)
        elif template in ("mastery",):
            widget = MasteryTeacherWidget(adapter, section, unit, lesson, self, undo_stack)
        else:
            widget = LinearFlowWidget(adapter, section, unit, lesson, self, undo_stack)

        widget.changed.connect(self.tree_changed.emit)
        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setWidget(widget)
        self.content_layout.addWidget(scroll)
        self._current_content_widget = widget