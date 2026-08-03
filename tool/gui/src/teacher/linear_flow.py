"""Linear question flow for the teacher view (guiplan §15.4, T.3).

Collapses the 6-level nesting (section/unit/lesson/subLessons/stages/items)
into 3 teacher-facing layers: 课 -> 教学环节 -> 题目卡片. Section/Unit recede
to a breadcrumb at the top. Clicking a question shows its card inline.
"""
from __future__ import annotations

from typing import Any

from PySide6.QtCore import QEvent, QObject, QPoint, Qt, Signal
from PySide6.QtGui import QDrag, QDragEnterEvent, QDropEvent, QMouseEvent
from PySide6.QtWidgets import (
    QComboBox,
    QDialog,
    QFrame,
    QHBoxLayout,
    QInputDialog,
    QLabel,
    QMessageBox,
    QPushButton,
    QVBoxLayout,
    QWidget,
)
from PySide6.QtCore import QMimeData


class _DragDropFilter(QObject):
    """Simple drag source / drop target filter for reordering cards.

    Supports dragging a widget by its id and dropping it onto a container
    widget. The owning ``LinearFlowWidget`` is notified via
    ``_handle_drop(kind, source_id, pos)``.
    """

    _MIME_TYPE = "application/x-turna-reorder"

    def __init__(self, owner: "LinearFlowWidget", kind: str, item_id: str) -> None:
        super().__init__(owner)
        self._owner = owner
        self._kind = kind
        self._item_id = item_id
        self._drag_start: QPoint | None = None

    def eventFilter(self, watched: QObject, event) -> bool:
        if isinstance(event, QMouseEvent):
            if event.type() == QEvent.MouseButtonPress:
                if event.button() == Qt.MouseButton.LeftButton:
                    self._drag_start = event.globalPosition().toPoint()
                return False
            if event.type() == QEvent.MouseMove:
                if self._drag_start is None:
                    return False
                if (
                    event.globalPosition().toPoint() - self._drag_start
                ).manhattanLength() < 10:
                    return False
                mime = QMimeData()
                mime.setData(
                    self._MIME_TYPE,
                    f"{self._kind}:{self._item_id}".encode("utf-8"),
                )
                drag = QDrag(watched)
                drag.setMimeData(mime)
                self._drag_start = None
                drag.exec(Qt.DropAction.MoveAction)
                return True
        if isinstance(event, QDragEnterEvent):
            if event.mimeData().hasFormat(self._MIME_TYPE):
                event.acceptProposedAction()
                return True
        if isinstance(event, QDropEvent):
            data = bytes(event.mimeData().data(self._MIME_TYPE)).decode("utf-8")
            parts = data.split(":", 1)
            if len(parts) == 2:
                global_pos = watched.mapToGlobal(event.position().toPoint())
                self._owner._handle_drop(parts[0], parts[1], global_pos)
            event.acceptProposedAction()
            return True
        return super().eventFilter(watched, event)


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
from src.theme import current_palette
from src.widgets.option_models import build_options_model


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
        undo_stack: Any = None,
    ) -> None:
        super().__init__(parent)
        self.adapter = adapter
        self.section = section
        self.unit = unit
        self.lesson = lesson
        self.undo_stack = undo_stack
        self._last_item_type = "multipleChoice"
        self._content_layout: QVBoxLayout | None = None
        self._add_sub_btn: QPushButton | None = None
        self._sub_lesson_frames: dict[str, QFrame] = {}
        # Cached reference option models + the fingerprint of the adapter
        # resource lists they were built from. _build_ui reuses the models
        # when the resource lists haven't changed, avoiding a full
        # build_options_model (×3) on every rebuild.
        self._vocab_model = None
        self._expression_model = None
        self._grammar_model = None
        self._options_fp: tuple = ()
        self.setAcceptDrops(True)
        self.installEventFilter(_DragDropFilter(self, "container", ""))
        self._build_ui()

    def _build_ui(self) -> None:
        self._sub_lesson_frames.clear()
        if self.layout() is not None:
            while self.layout().count():
                child = self.layout().takeAt(0)
                widget = child.widget()
                if widget is not None:
                    widget.setParent(None)
                    widget.deleteLater()
        else:
            QVBoxLayout(self)

        layout = self.layout()
        if layout is None:
            return
        self._content_layout = layout
        layout.setSpacing(12)
        layout.setContentsMargins(12, 12, 12, 12)

        # Shared reference models for all cards in this render pass. Reuse
        # the previous models when the resource lists are unchanged (same
        # fingerprint of ids), so a rebuild pass driven by an unrelated
        # change doesn't rebuild three QStandardItemModels. The id tuple
        # captures add/remove/reorder; in-place label edits to an existing
        # resource are rare and will refresh on the next structural change.
        fp = (
            tuple(w.get("id", "") for w in self.adapter.vocab),
            tuple(e.get("id", "") for e in self.adapter.expressions),
            tuple(g.get("id", "") for g in self.adapter.grammar_points),
        )
        if fp != self._options_fp or self._vocab_model is None:
            self._vocab_model = build_options_model(
                self.adapter.vocab_options(), placeholder="(未选择)"
            )
            self._expression_model = build_options_model(
                self.adapter.expression_options(), placeholder="(无)"
            )
            self._grammar_model = build_options_model(
                self.adapter.grammar_options(), placeholder="(未关联)"
            )
            self._options_fp = fp

        breadcrumb = QLabel(
            f"{self.section.get('name', '')} › {self.unit.get('name', '')} › "
            f"{self.lesson.get('name', '')}"
        )
        breadcrumb.setStyleSheet(f"color: {current_palette()['text_secondary']}; padding: 4px;")
        layout.addWidget(breadcrumb)

        title = QLabel(self.lesson.get('name', ''))
        title.setStyleSheet(f"font-size: 18px; font-weight: 700; color: {current_palette()['text']};")
        layout.addWidget(title)

        preview_btn = QPushButton("预览本课")
        preview_btn.setToolTip("实际做题验证题目设置（guiplan §15.7）")
        preview_btn.clicked.connect(self._on_preview)
        layout.addWidget(preview_btn)

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

        header = self._build_sub_lesson_header(sl)
        header.installEventFilter(_DragDropFilter(self, "sublesson", sl.get("id", "")))
        header.setCursor(Qt.CursorShape.OpenHandCursor)
        flayout.addWidget(header)

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

        title = QLabel(f"{layer_label('subLesson')}：{sl.get('name', sl.get('id', ''))}")
        title.setStyleSheet(f"font-size: 15px; font-weight: 700; color: {current_palette()['text']};")
        hlayout.addWidget(title)
        hlayout.addStretch()

        hlayout.addWidget(self._tool_button("重命名", "重命名", lambda _c=False, s=sl: self._on_rename_sub_lesson(s)))

        idx = self._index_of_sub_lesson(sl)
        up_btn = self._tool_button("↑", "上移", lambda _c=False, s=sl, i=idx: self._on_move_sub_lesson(s, i, -1))
        up_btn.setEnabled(idx > 0)
        hlayout.addWidget(up_btn)
        down_btn = self._tool_button("↓", "下移", lambda _c=False, s=sl, i=idx: self._on_move_sub_lesson(s, i, 1))
        down_btn.setEnabled(idx >= 0 and idx < len(self._sub_lessons()) - 1)
        hlayout.addWidget(down_btn)

        hlayout.addWidget(self._tool_button("删除", "删除", lambda _c=False, s=sl: self._on_delete_sub_lesson(s)))

        return header

    def _build_stage(self, stage: dict[str, Any], sl: dict[str, Any]) -> QWidget:
        widget = QWidget()
        widget.setStyleSheet(f"QWidget {{ background-color: {current_palette()['bg_elevated']}; border-radius: 8px; }}")
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
        title.setStyleSheet(f"font-weight: 600; color: {current_palette()['text_secondary']};")
        hlayout.addWidget(title)
        hlayout.addStretch()

        hlayout.addWidget(self._tool_button("重命名", "重命名", lambda _c=False, st=stage: self._on_rename_stage(st)))

        idx = self._index_of_stage(stage, sl)
        up_btn = self._tool_button("↑", "上移", lambda _c=False, st=stage, s=sl, i=idx: self._on_move_stage(st, s, i, -1))
        up_btn.setEnabled(idx > 0)
        hlayout.addWidget(up_btn)
        down_btn = self._tool_button("↓", "下移", lambda _c=False, st=stage, s=sl, i=idx: self._on_move_stage(st, s, i, 1))
        down_btn.setEnabled(idx >= 0 and idx < len(sl.get("stages", []) or []) - 1)
        hlayout.addWidget(down_btn)

        hlayout.addWidget(self._tool_button("删除", "删除", lambda _c=False, st=stage, s=sl: self._on_delete_stage(st, s)))

        return header

    def _build_card(self, stage: dict[str, Any], item: dict[str, Any]) -> QuestionCard:
        card = QuestionCard(
            self.adapter,
            item,
            vocab_model=self._vocab_model,
            expression_model=self._expression_model,
            grammar_model=self._grammar_model,
        )
        card.changed.connect(self.changed.emit)
        card.delete_requested.connect(lambda _c=False, st=stage, it=item: self._on_delete_item(st, it))
        card.type_changed.connect(lambda new_type, st=stage, it=item: self._on_change_item_type(st, it, new_type))
        card.move_up_requested.connect(lambda _c=False, st=stage, it=item: self._on_move_item(st, it, -1))
        card.move_down_requested.connect(lambda _c=False, st=stage, it=item: self._on_move_item(st, it, 1))
        card.ai_rewrite_requested.connect(lambda _c=False, st=stage, it=item: self._on_ai_rewrite_item(st, it))
        return card

    def _on_ai_rewrite_item(self, stage: dict[str, Any], item: dict[str, Any]) -> None:
        from src.dialogs.ai_lesson_helper_dialog import AiLessonHelperDialog

        dialog = AiLessonHelperDialog(
            self.adapter,
            item,
            mode="item",
            parent=self,
        )
        if dialog.exec() != QDialog.DialogCode.Accepted:
            return
        result = dialog.result()
        if result is None:
            return
        self._replace_item(stage, item, result)

    def _tool_button(self, text: str, tooltip: str, callback) -> QPushButton:
        btn = QPushButton(text)
        btn.setMinimumWidth(48)
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
        content = self.lesson.setdefault("content", {})
        if self.undo_stack is not None:
            from src.application.commands import AddSubLessonCommand

            cmd = AddSubLessonCommand(content, "新环节")
            cmd.signals.changed.connect(self._rebuild)
            self.undo_stack.push(cmd)
            self.changed.emit()
            return
        add_sub_lesson(content, "新环节")
        self.changed.emit()
        self._rebuild()

    def _on_add_stage(self, sl: dict[str, Any]) -> None:
        if self.undo_stack is not None:
            from src.application.commands import AddStageCommand

            cmd = AddStageCommand(sl, "新步骤")
            cmd.signals.changed.connect(lambda: self._rebuild_sub_lesson(sl))
            self.undo_stack.push(cmd)
            self.changed.emit()
            return
        add_stage(sl, "新步骤")
        self.changed.emit()
        self._rebuild_sub_lesson(sl)

    def _on_add_item(self, stage: dict[str, Any], combo: QComboBox) -> None:
        rt = combo.currentData() or "multipleChoice"
        self._last_item_type = rt
        if self.undo_stack is not None:
            from src.application.commands import AddItemCommand

            cmd = AddItemCommand(stage, rt)
            cmd.signals.changed.connect(lambda: self._rebuild_stage_of(stage))
            self.undo_stack.push(cmd)
            self.changed.emit()
            return
        add_item(stage, rt)
        self.changed.emit()
        self._rebuild_stage_of(stage)

    def _on_delete_item(self, stage: dict[str, Any], item: dict[str, Any]) -> None:
        reply = QMessageBox.question(
            self, "删除题目", "确认删除这道题目？",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
        )
        if reply != QMessageBox.StandardButton.Yes:
            return
        if self.undo_stack is not None:
            from src.application.commands import DeleteItemCommand

            cmd = DeleteItemCommand(stage, item)
            cmd.signals.changed.connect(lambda: self._rebuild_stage_of(stage))
            self.undo_stack.push(cmd)
            self.changed.emit()
            return
        delete_item(stage, item.get("id", ""))
        self.changed.emit()
        self._rebuild_stage_of(stage)

    def _on_change_item_type(self, stage: dict[str, Any], item: dict[str, Any], new_type: str) -> None:
        new_item = switch_runtime_type(item, new_type)
        self._replace_item(stage, item, new_item)

    def _replace_item(
        self,
        stage: dict[str, Any],
        old_item: dict[str, Any],
        new_item: dict[str, Any],
    ) -> None:
        """Replace an item in a stage, using the undo stack when available."""
        item_id = old_item.get("id", "")
        if not item_id:
            return
        if self.undo_stack is not None:
            from src.application.commands import ReplaceItemCommand

            cmd = ReplaceItemCommand(stage, item_id, new_item)
            cmd.signals.changed.connect(lambda: self._rebuild_stage_of(stage))
            self.undo_stack.push(cmd)
            self.changed.emit()
            return
        items = stage.get("items", [])
        for i, it in enumerate(items):
            if it.get("id") == item_id:
                items[i] = new_item
                break
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
        if self.undo_stack is not None:
            from src.application.commands import MoveItemCommand

            cmd = MoveItemCommand(stage, idx, new_idx)
            cmd.signals.changed.connect(lambda: self._rebuild_stage_of(stage))
            self.undo_stack.push(cmd)
            self.changed.emit()
            return
        move_item(stage, idx, new_idx)
        self.changed.emit()
        self._rebuild_stage_of(stage)

    def _on_rename_sub_lesson(self, sl: dict[str, Any]) -> None:
        old = sl.get("name", "")
        text, ok = QInputDialog.getText(self, "重命名", "新名称：", text=old)
        if not ok or not text:
            return
        if self.undo_stack is not None:
            from src.application.commands import RenameSubLessonCommand

            cmd = RenameSubLessonCommand(sl, text)
            cmd.signals.changed.connect(lambda: self._rebuild_sub_lesson(sl))
            self.undo_stack.push(cmd)
            self.changed.emit()
            return
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
        content = self.lesson.setdefault("content", {})
        if self.undo_stack is not None:
            from src.application.commands import DeleteSubLessonCommand

            cmd = DeleteSubLessonCommand(content, sl)
            cmd.signals.changed.connect(self._rebuild)
            self.undo_stack.push(cmd)
            self.changed.emit()
            return
        delete_sub_lesson(content, sl.get("id", ""))
        self.changed.emit()
        self._rebuild()

    def _on_move_sub_lesson(self, sl: dict[str, Any], idx: int, delta: int) -> None:
        subs = self._sub_lessons()
        if sl not in subs:
            return
        new_idx = idx + delta
        if not (0 <= new_idx < len(subs)):
            return
        content = self.lesson.setdefault("content", {})
        if self.undo_stack is not None:
            from src.application.commands import MoveSubLessonCommand

            cmd = MoveSubLessonCommand(content, idx, new_idx)
            cmd.signals.changed.connect(self._rebuild)
            self.undo_stack.push(cmd)
            self.changed.emit()
            return
        move_sub_lesson(content, idx, new_idx)
        self.changed.emit()
        self._rebuild()

    def _on_rename_stage(self, stage: dict[str, Any]) -> None:
        old = stage.get("name", "")
        text, ok = QInputDialog.getText(self, "重命名", "新名称：", text=old)
        if not ok or not text:
            return
        if self.undo_stack is not None:
            from src.application.commands import RenameStageCommand

            cmd = RenameStageCommand(stage, text)
            # Stage header is rebuilt with its parent sub-lesson.
            for sl in self._sub_lessons():
                if stage in (sl.get("stages", []) or []):
                    cmd.signals.changed.connect(lambda checked=False, s=sl: self._rebuild_sub_lesson(s))
                    break
            self.undo_stack.push(cmd)
            self.changed.emit()
            return
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
        if self.undo_stack is not None:
            from src.application.commands import DeleteStageCommand

            cmd = DeleteStageCommand(sl, stage)
            cmd.signals.changed.connect(lambda: self._rebuild_sub_lesson(sl))
            self.undo_stack.push(cmd)
            self.changed.emit()
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
        if self.undo_stack is not None:
            from src.application.commands import MoveStageCommand

            cmd = MoveStageCommand(sl, idx, new_idx)
            cmd.signals.changed.connect(lambda: self._rebuild_sub_lesson(sl))
            self.undo_stack.push(cmd)
            self.changed.emit()
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

    def _ordered_sub_lesson_frames(self) -> list[QFrame]:
        """Return sub-lesson frames in their current visual order."""
        layout = self._content_layout
        if layout is None:
            return []
        frames: list[QFrame] = []
        for i in range(layout.count()):
            item = layout.itemAt(i)
            if item is None:
                continue
            widget = item.widget()
            if isinstance(widget, QFrame) and widget in self._sub_lesson_frames.values():
                frames.append(widget)
        return frames

    def _drop_target_index(self, local_y: int, widgets: list[QWidget]) -> int:
        """Return the insertion index for a drop at the given local y coordinate."""
        for i, widget in enumerate(widgets):
            geo = widget.geometry()
            center_y = geo.top() + geo.height() // 2
            if local_y < center_y:
                return i
        return len(widgets)

    def _handle_drop(self, kind: str, source_id: str, global_pos: QPoint) -> None:
        """Handle a drop from the drag-drop filter."""
        local_pos = self.mapFromGlobal(global_pos)
        if kind == "sublesson":
            self._handle_sub_lesson_drop(source_id, local_pos)
        # Stage and item reordering via drag-and-drop can be added here.

    def _handle_sub_lesson_drop(self, source_id: str, local_pos: QPoint) -> None:
        subs = self._sub_lessons()
        source_idx = next(
            (i for i, sl in enumerate(subs) if sl.get("id") == source_id), -1
        )
        if source_idx < 0:
            return
        frames = self._ordered_sub_lesson_frames()
        target_idx = self._drop_target_index(local_pos.y(), frames)
        if target_idx > len(subs):
            target_idx = len(subs)
        if target_idx == source_idx or target_idx == source_idx + 1:
            return
        if target_idx > source_idx:
            target_idx -= 1
        content = self.lesson.setdefault("content", {})
        if self.undo_stack is not None:
            from src.application.commands import MoveSubLessonCommand

            cmd = MoveSubLessonCommand(content, source_idx, target_idx)
            cmd.signals.changed.connect(self._rebuild)
            self.undo_stack.push(cmd)
            self.changed.emit()
        else:
            move_sub_lesson(content, source_idx, target_idx)
            self.changed.emit()
            self._rebuild()

    def _rebuild(self) -> None:
        self._build_ui()

    def refresh_references(self) -> None:
        """Rebuild so QuestionCard reference dropdowns pick up resource changes."""
        self._rebuild()

    def _on_preview(self) -> None:
        from src.teacher.preview_window import LessonPreviewDialog

        dlg = LessonPreviewDialog(self.adapter, self.lesson, self)
        dlg.exec()
