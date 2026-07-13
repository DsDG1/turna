"""Linear question flow for the teacher view (guiplan §15.4, T.3).

Collapses the 6-level nesting (section/unit/lesson/subLessons/stages/items)
into 3 teacher-facing layers: 课 -> 教学环节 -> 题目卡片. Section/Unit recede
to a breadcrumb at the top. Clicking a question shows its card inline.
"""
from __future__ import annotations

from typing import Any

from PySide6.QtCore import Signal
from PySide6.QtWidgets import (
    QComboBox,
    QFrame,
    QHBoxLayout,
    QInputDialog,
    QLabel,
    QMessageBox,
    QPushButton,
    QVBoxLayout,
    QWidget,
)

from src.backend.course_adapter import CourseAdapter
from src.backend.lesson_content import (
    ALLOWED_RUNTIME_TYPES,
    add_item,
    add_stage,
    add_sub_lesson,
    delete_item,
    delete_stage,
    delete_sub_lesson,
    move_item,
    move_stage,
    move_sub_lesson,
    rename_stage,
    rename_sub_lesson,
    switch_runtime_type,
)
from src.i18n.labels import interaction_label, layer_label
from src.teacher.question_cards import QuestionCard


class LinearFlowWidget(QWidget):
    """Teacher view of a single lesson: breadcrumb + 3-layer folded list."""

    changed = Signal()

    def __init__(
        self,
        adapter: CourseAdapter,
        section: dict[str, Any],
        unit: dict[str, Any],
        lesson: dict[str, Any],
        parent: QWidget | None = None,
    ) -> None:
        super().__init__(parent)
        self.adapter = adapter
        self.section = section
        self.unit = unit
        self.lesson = lesson
        self._last_item_type = "multipleChoice"
        self._content_layout: QVBoxLayout | None = None
        self._add_sub_btn: QPushButton | None = None
        self._sub_lesson_frames: dict[str, QFrame] = {}
        self._build_ui()

    def _build_ui(self) -> None:
        self._sub_lesson_frames.clear()
        if self.layout() is not None:
            while self.layout().count():
                child = self.layout().takeAt(0)
                if child.widget():
                    child.widget().setParent(None)
                    child.widget().deleteLater()
        else:
            QVBoxLayout(self)

        layout = self.layout()
        if layout is None:
            return
        self._content_layout = layout
        layout.setSpacing(12)
        layout.setContentsMargins(12, 12, 12, 12)

        breadcrumb = QLabel(
            f"{self.section.get('name', '')} › {self.unit.get('name', '')} › "
            f"{self.lesson.get('name', '')}"
        )
        breadcrumb.setStyleSheet("color: #9CA3AF; padding: 4px;")
        layout.addWidget(breadcrumb)

        title = QLabel(f"📚 {self.lesson.get('name', '')}")
        title.setStyleSheet("font-size: 18px; font-weight: 700; color: #FFFFFF;")
        layout.addWidget(title)

        for sl in self._sub_lessons():
            frame = self._build_sub_lesson(sl)
            layout.addWidget(frame)

        self._add_sub_btn = QPushButton("+ 添加教学环节")
        self._add_sub_btn.clicked.connect(self._on_add_sub_lesson)
        layout.addWidget(self._add_sub_btn)
        layout.addStretch()

    def _sub_lessons(self) -> list[dict[str, Any]]:
        return self.lesson.get("content", {}).get("subLessons", []) or []

    def _index_of_sub_lesson(self, sl: dict[str, Any]) -> int:
        """Return the index of a sub-lesson in the list using identity first."""
        subs = self._sub_lessons()
        for i, candidate in enumerate(subs):
            if candidate is sl:
                return i
        try:
            return subs.index(sl)
        except ValueError:
            return -1

    def _index_of_stage(self, stage: dict[str, Any], sl: dict[str, Any]) -> int:
        """Return the index of a stage in the sub-lesson using identity first."""
        stages = sl.get("stages", []) or []
        for i, candidate in enumerate(stages):
            if candidate is stage:
                return i
        try:
            return stages.index(stage)
        except ValueError:
            return -1

    def _build_sub_lesson(self, sl: dict[str, Any]) -> QFrame:
        frame = QFrame()
        frame.setStyleSheet(
            "QFrame { background-color: #1F232C; border: 1px solid #2C313C; border-radius: 10px; }"
        )
        flayout = QVBoxLayout(frame)
        flayout.setSpacing(10)
        flayout.setContentsMargins(12, 12, 12, 12)

        flayout.addWidget(self._build_sub_lesson_header(sl))

        stages_widget = QWidget()
        stages_layout = QVBoxLayout(stages_widget)
        stages_layout.setContentsMargins(16, 0, 0, 0)
        stages_layout.setSpacing(10)

        for stage in sl.get("stages", []) or []:
            stages_layout.addWidget(self._build_stage(stage, sl))

        add_stage_btn = QPushButton("+ 添加教学步骤")
        add_stage_btn.clicked.connect(lambda _c=False, s=sl: self._on_add_stage(s))
        stages_layout.addWidget(add_stage_btn)

        flayout.addWidget(stages_widget)
        flayout.addStretch()

        self._sub_lesson_frames[sl.get("id", "")] = frame
        return frame

    def _build_sub_lesson_header(self, sl: dict[str, Any]) -> QWidget:
        header = QWidget()
        hlayout = QHBoxLayout(header)
        hlayout.setContentsMargins(0, 0, 0, 0)
        hlayout.setSpacing(6)

        title = QLabel(f"📁 {layer_label('subLesson')}：{sl.get('name', sl.get('id', ''))}")
        title.setStyleSheet("font-size: 15px; font-weight: 700; color: #E8EAF0;")
        hlayout.addWidget(title)
        hlayout.addStretch()

        hlayout.addWidget(self._tool_button("✏️", "重命名", lambda _c=False, s=sl: self._on_rename_sub_lesson(s)))

        idx = self._index_of_sub_lesson(sl)
        up_btn = self._tool_button("↑", "上移", lambda _c=False, s=sl, i=idx: self._on_move_sub_lesson(s, i, -1))
        up_btn.setEnabled(idx > 0)
        hlayout.addWidget(up_btn)
        down_btn = self._tool_button("↓", "下移", lambda _c=False, s=sl, i=idx: self._on_move_sub_lesson(s, i, 1))
        down_btn.setEnabled(idx >= 0 and idx < len(self._sub_lessons()) - 1)
        hlayout.addWidget(down_btn)

        hlayout.addWidget(self._tool_button("🗑️", "删除", lambda _c=False, s=sl: self._on_delete_sub_lesson(s)))

        return header

    def _build_stage(self, stage: dict[str, Any], sl: dict[str, Any]) -> QWidget:
        widget = QWidget()
        widget.setStyleSheet("QWidget { background-color: #232833; border-radius: 8px; }")
        slayout = QVBoxLayout(widget)
        slayout.setSpacing(8)
        slayout.setContentsMargins(10, 10, 10, 10)

        slayout.addWidget(self._build_stage_header(stage, sl))

        for item in stage.get("items", []) or []:
            slayout.addWidget(self._build_card(stage, item))

        add_row = QWidget()
        add_layout = QHBoxLayout(add_row)
        add_layout.setContentsMargins(0, 0, 0, 0)
        add_layout.setSpacing(6)

        type_combo = QComboBox()
        for rt in ALLOWED_RUNTIME_TYPES:
            type_combo.addItem(interaction_label(rt), rt)
        type_combo.setCurrentIndex(type_combo.findData(self._last_item_type))
        type_combo.currentIndexChanged.connect(self._on_item_type_combo_changed)
        add_layout.addWidget(QLabel("题型："))
        add_layout.addWidget(type_combo)
        add_layout.addStretch()

        add_btn = QPushButton("+ 添加题目")
        add_btn.clicked.connect(lambda _c=False, st=stage, cb=type_combo: self._on_add_item(st, cb))
        add_layout.addWidget(add_btn)

        slayout.addWidget(add_row)
        return widget

    def _build_stage_header(self, stage: dict[str, Any], sl: dict[str, Any]) -> QWidget:
        header = QWidget()
        hlayout = QHBoxLayout(header)
        hlayout.setContentsMargins(0, 0, 0, 0)
        hlayout.setSpacing(6)

        title = QLabel(f"  {layer_label('stage')}：{stage.get('name', stage.get('id', ''))}")
        title.setStyleSheet("font-weight: 600; color: #9CA3AF;")
        hlayout.addWidget(title)
        hlayout.addStretch()

        hlayout.addWidget(self._tool_button("✏️", "重命名", lambda _c=False, st=stage: self._on_rename_stage(st)))

        idx = self._index_of_stage(stage, sl)
        up_btn = self._tool_button("↑", "上移", lambda _c=False, st=stage, s=sl, i=idx: self._on_move_stage(st, s, i, -1))
        up_btn.setEnabled(idx > 0)
        hlayout.addWidget(up_btn)
        down_btn = self._tool_button("↓", "下移", lambda _c=False, st=stage, s=sl, i=idx: self._on_move_stage(st, s, i, 1))
        down_btn.setEnabled(idx >= 0 and idx < len(sl.get("stages", []) or []) - 1)
        hlayout.addWidget(down_btn)

        hlayout.addWidget(self._tool_button("🗑️", "删除", lambda _c=False, st=stage, s=sl: self._on_delete_stage(st, s)))

        return header

    def _build_card(self, stage: dict[str, Any], item: dict[str, Any]) -> QuestionCard:
        card = QuestionCard(self.adapter, item)
        card.changed.connect(self.changed.emit)
        card.delete_requested.connect(lambda _c=False, st=stage, it=item: self._on_delete_item(st, it))
        card.type_changed.connect(lambda new_type, st=stage, it=item: self._on_change_item_type(st, it, new_type))
        card.move_up_requested.connect(lambda _c=False, st=stage, it=item: self._on_move_item(st, it, -1))
        card.move_down_requested.connect(lambda _c=False, st=stage, it=item: self._on_move_item(st, it, 1))
        return card

    def _tool_button(self, text: str, tooltip: str, callback) -> QPushButton:
        btn = QPushButton(text)
        btn.setFixedWidth(32)
        btn.setToolTip(tooltip)
        btn.clicked.connect(callback)
        return btn

    def _on_item_type_combo_changed(self, index: int) -> None:
        combo = self.sender()
        if isinstance(combo, QComboBox):
            rt = combo.itemData(index)
            if rt:
                self._last_item_type = rt

    def _on_add_sub_lesson(self) -> None:
        sl = add_sub_lesson(self.lesson.setdefault("content", {}), "新环节")
        self.changed.emit()
        if self._content_layout is not None and self._add_sub_btn is not None:
            frame = self._build_sub_lesson(sl)
            insert_idx = self._content_layout.indexOf(self._add_sub_btn)
            self._content_layout.insertWidget(insert_idx, frame)
            self._refresh_sub_lesson_move_buttons()
        else:
            self._rebuild()

    def _on_add_stage(self, sl: dict[str, Any]) -> None:
        stage = add_stage(sl, "新步骤")
        self.changed.emit()
        self._rebuild_sub_lesson(sl)

    def _on_add_item(self, stage: dict[str, Any], combo: QComboBox) -> None:
        rt = combo.currentData() or "multipleChoice"
        self._last_item_type = rt
        item = add_item(stage, rt)
        self.changed.emit()
        self._rebuild_stage_of(stage)

    def _on_delete_item(self, stage: dict[str, Any], item: dict[str, Any]) -> None:
        reply = QMessageBox.question(
            self, "删除题目", "确认删除这道题目？",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
        )
        if reply != QMessageBox.StandardButton.Yes:
            return
        delete_item(stage, item.get("id", ""))
        self.changed.emit()
        self._rebuild_stage_of(stage)

    def _on_change_item_type(self, stage: dict[str, Any], item: dict[str, Any], new_type: str) -> None:
        items = stage.get("items", [])
        try:
            idx = items.index(item)
        except ValueError:
            return
        new_item = switch_runtime_type(item, new_type)
        items[idx] = new_item
        self.changed.emit()
        self._rebuild_stage_of(stage)

    def _on_move_item(self, stage: dict[str, Any], item: dict[str, Any], delta: int) -> None:
        items = stage.get("items", [])
        try:
            idx = items.index(item)
        except ValueError:
            return
        new_idx = idx + delta
        if not (0 <= new_idx < len(items)):
            return
        move_item(stage, idx, new_idx)
        self.changed.emit()
        self._rebuild_stage_of(stage)

    def _on_rename_sub_lesson(self, sl: dict[str, Any]) -> None:
        old = sl.get("name", "")
        text, ok = QInputDialog.getText(self, "重命名", "新名称：", text=old)
        if ok and text:
            rename_sub_lesson(sl, text)
            self.changed.emit()
            self._rebuild_sub_lesson(sl)

    def _on_delete_sub_lesson(self, sl: dict[str, Any]) -> None:
        reply = QMessageBox.question(
            self, "删除教学环节", f"确认删除教学环节「{sl.get('name', '')}」？",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
        )
        if reply != QMessageBox.StandardButton.Yes:
            return
        delete_sub_lesson(self.lesson.setdefault("content", {}), sl.get("id", ""))
        self.changed.emit()
        self._rebuild()

    def _on_move_sub_lesson(self, sl: dict[str, Any], idx: int, delta: int) -> None:
        subs = self._sub_lessons()
        if sl not in subs:
            return
        new_idx = idx + delta
        if not (0 <= new_idx < len(subs)):
            return
        move_sub_lesson(self.lesson.setdefault("content", {}), idx, new_idx)
        self.changed.emit()
        self._rebuild()

    def _on_rename_stage(self, stage: dict[str, Any]) -> None:
        old = stage.get("name", "")
        text, ok = QInputDialog.getText(self, "重命名", "新名称：", text=old)
        if ok and text:
            rename_stage(stage, text)
            self.changed.emit()
            self._rebuild_stage_of(stage)

    def _on_delete_stage(self, stage: dict[str, Any], sl: dict[str, Any]) -> None:
        reply = QMessageBox.question(
            self, "删除教学步骤", f"确认删除教学步骤「{stage.get('name', '')}」？",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
        )
        if reply != QMessageBox.StandardButton.Yes:
            return
        delete_stage(sl, stage.get("id", ""))
        self.changed.emit()
        self._rebuild_sub_lesson(sl)

    def _on_move_stage(self, stage: dict[str, Any], sl: dict[str, Any], idx: int, delta: int) -> None:
        stages = sl.get("stages", [])
        if stage not in stages:
            return
        new_idx = idx + delta
        if not (0 <= new_idx < len(stages)):
            return
        move_stage(sl, idx, new_idx)
        self.changed.emit()
        self._rebuild_sub_lesson(sl)

    def _rebuild_stage_of(self, stage: dict[str, Any]) -> None:
        """Rebuild the stage widget that contains the given stage."""
        for sl in self._sub_lessons():
            if stage in (sl.get("stages", []) or []):
                self._rebuild_sub_lesson(sl)
                return
        self._rebuild()

    def _rebuild_sub_lesson(self, sl: dict[str, Any]) -> None:
        old_frame = self._sub_lesson_frames.get(sl.get("id", ""))
        if old_frame is None or self._content_layout is None:
            self._rebuild()
            return
        idx = self._content_layout.indexOf(old_frame)
        if idx < 0:
            self._rebuild()
            return
        old_frame.setParent(None)
        old_frame.deleteLater()
        new_frame = self._build_sub_lesson(sl)
        self._content_layout.insertWidget(idx, new_frame)
        self._refresh_sub_lesson_move_buttons()

    def _refresh_sub_lesson_move_buttons(self) -> None:
        # Move buttons are rebuilt during _rebuild_sub_lesson, so no extra work needed.
        pass

    def _rebuild(self) -> None:
        self._build_ui()
