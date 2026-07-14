"""Teacher-friendly editors for listening, reading, and mastery lesson templates.

Each widget provides a simplified view plus an "Advanced Edit" button that
switches to the full expert LessonEditor for that lesson.
"""
from __future__ import annotations

from typing import Any

from PySide6.QtCore import Signal
from PySide6.QtWidgets import (
    QComboBox,
    QHBoxLayout,
    QInputDialog,
    QLabel,
    QLineEdit,
    QMessageBox,
    QPushButton,
    QTextEdit,
    QVBoxLayout,
    QWidget,
)

from src.backend.course_adapter import CourseAdapter
from src.backend.lesson_content import (
    ALLOWED_RUNTIME_TYPES,
    add_item,
    add_listening_phase,
    delete_item,
    delete_listening_phase,
    listening_phase_has_items,
    move_item,
    move_listening_phase,
    rename_listening_phase,
    switch_runtime_type,
)
from src.i18n.labels import interaction_label, layer_label
from src.teacher.question_cards import QuestionCard


class TeacherTemplateWidget(QWidget):
    """Base widget with breadcrumb and an advanced-edit toggle."""

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
        self._advanced_btn: QPushButton | None = None
        self._content_layout: QVBoxLayout | None = None
        self._last_item_type = "multipleChoice"
        self._build_ui()

    def _build_ui(self) -> None:
        layout = QVBoxLayout(self)
        layout.setContentsMargins(12, 12, 12, 12)
        layout.setSpacing(12)

        header = QWidget()
        hlayout = QHBoxLayout(header)
        hlayout.setContentsMargins(0, 0, 0, 0)
        breadcrumb = QLabel(
            f"{self.section.get('name', '')} › {self.unit.get('name', '')} › "
            f"{self.lesson.get('name', '')}"
        )
        breadcrumb.setStyleSheet("color: #9CA3AF;")
        hlayout.addWidget(breadcrumb)
        hlayout.addStretch()
        self._advanced_btn = QPushButton("高级编辑")
        self._advanced_btn.setCheckable(True)
        self._advanced_btn.toggled.connect(self._on_advanced_toggled)
        hlayout.addWidget(self._advanced_btn)
        preview_btn = QPushButton("🔍 预览本课")
        preview_btn.setToolTip("实际做题验证题目设置（guiplan §15.7）")
        preview_btn.clicked.connect(self._on_preview)
        hlayout.addWidget(preview_btn)
        layout.addWidget(header)

        self._content_host = QWidget()
        self._content_layout = QVBoxLayout(self._content_host)
        self._content_layout.setContentsMargins(0, 0, 0, 0)
        self._content_layout.setSpacing(12)
        layout.addWidget(self._content_host, 1)

        self._build_teacher_view()

    def _on_advanced_toggled(self, checked: bool) -> None:
        if self._advanced_btn is not None:
            self._advanced_btn.setText("返回教师视图" if checked else "高级编辑")
        self._clear_content()
        if checked:
            from src.widgets.lesson_editor import LessonEditor

            editor = LessonEditor(self.adapter, self.lesson)
            self._content_layout.addWidget(editor)
        else:
            self._build_teacher_view()

    def _clear_content(self) -> None:
        if self._content_layout is None:
            return
        while self._content_layout.count():
            child = self._content_layout.takeAt(0)
            if child.widget():
                child.widget().setParent(None)
                child.widget().deleteLater()

    def _build_teacher_view(self) -> None:
        raise NotImplementedError

    def _tool_button(self, text: str, tooltip: str, callback) -> QPushButton:
        btn = QPushButton(text)
        btn.setFixedWidth(32)
        btn.setToolTip(tooltip)
        btn.clicked.connect(callback)
        return btn

    def _item_type_combo(self, default: str | None = None) -> QComboBox:
        combo = QComboBox()
        for rt in ALLOWED_RUNTIME_TYPES:
            combo.addItem(interaction_label(rt), rt)
        combo.setCurrentIndex(combo.findData(default or self._last_item_type))
        combo.currentIndexChanged.connect(self._on_item_type_combo_changed)
        return combo

    def _on_item_type_combo_changed(self, index: int) -> None:
        combo = self.sender()
        if isinstance(combo, QComboBox):
            rt = combo.itemData(index)
            if rt:
                self._last_item_type = rt

    def _build_card(self, stage: dict[str, Any], item: dict[str, Any]) -> QuestionCard:
        card = QuestionCard(self.adapter, item)
        card.changed.connect(self.changed.emit)
        card.delete_requested.connect(lambda _c=False, st=stage, it=item: self._delete_item(st, it))
        card.type_changed.connect(lambda new_type, st=stage, it=item: self._change_item_type(st, it, new_type))
        card.move_up_requested.connect(lambda _c=False, st=stage, it=item: self._move_item(st, it, -1))
        card.move_down_requested.connect(lambda _c=False, st=stage, it=item: self._move_item(st, it, 1))
        return card

    def _delete_item(self, stage: dict[str, Any], item: dict[str, Any]) -> None:
        reply = QMessageBox.question(
            self, "删除题目", "确认删除这道题目？",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
        )
        if reply != QMessageBox.StandardButton.Yes:
            return
        delete_item(stage, item.get("id", ""))
        self.changed.emit()
        self._build_teacher_view()

    def _change_item_type(self, stage: dict[str, Any], item: dict[str, Any], new_type: str) -> None:
        items = stage.get("items", [])
        try:
            idx = items.index(item)
        except ValueError:
            return
        new_item = switch_runtime_type(item, new_type)
        items[idx] = new_item
        self.changed.emit()
        self._build_teacher_view()

    def _move_item(self, stage: dict[str, Any], item: dict[str, Any], delta: int) -> None:
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
        self._build_teacher_view()

    def _add_item_row(self, stage: dict[str, Any]) -> QWidget:
        row = QWidget()
        layout = QHBoxLayout(row)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(6)

        combo = self._item_type_combo()
        layout.addWidget(QLabel("题型："))
        layout.addWidget(combo)
        layout.addStretch()

        add_btn = QPushButton("+ 添加题目")
        add_btn.clicked.connect(lambda _c=False, st=stage, cb=combo: self._on_add_item(st, cb))
        layout.addWidget(add_btn)
        return row

    def _on_add_item(self, stage: dict[str, Any], combo: QComboBox) -> None:
        rt = combo.currentData() or "multipleChoice"
        self._last_item_type = rt
        add_item(stage, rt)
        self.changed.emit()
        self._build_teacher_view()

    def refresh_references(self) -> None:
        """Rebuild teacher view so QuestionCard reference dropdowns pick up
        resource changes (A3)."""
        self._build_teacher_view()

    def _on_preview(self) -> None:
        from src.teacher.preview_window import LessonPreviewDialog

        dlg = LessonPreviewDialog(self.adapter, self.lesson, self)
        dlg.exec()


class ListeningTeacherWidget(TeacherTemplateWidget):
    """Teacher view for listening lessons: phases with optional items."""

    def _build_teacher_view(self) -> None:
        layout = self._content_layout
        if layout is None:
            return

        title = QLabel(f"🎧 {self.lesson.get('name', '')}")
        title.setStyleSheet("font-size: 18px; font-weight: 700; color: #FFFFFF;")
        layout.addWidget(title)

        phases = self.lesson.get("content", {}).get("listeningPhases", []) or []
        for phase in phases:
            layout.addWidget(self._build_phase(phase))

        add_btn = QPushButton("+ 添加听力阶段")
        add_btn.clicked.connect(self._on_add_phase)
        layout.addWidget(add_btn)
        layout.addStretch()

    def _build_phase(self, phase: dict[str, Any]) -> QWidget:
        widget = QWidget()
        widget.setStyleSheet("QWidget { background-color: #1F232C; border-radius: 10px; }")
        playout = QVBoxLayout(widget)
        playout.setSpacing(10)
        playout.setContentsMargins(12, 12, 12, 12)

        playout.addWidget(self._build_phase_header(phase))

        type_combo = QComboBox()
        for pt in ("wordPairing", "dialogue", "summary"):
            type_combo.addItem(pt, pt)
        type_combo.setCurrentIndex(type_combo.findData(phase.get("type", "wordPairing")))
        type_combo.currentIndexChanged.connect(
            lambda _i, p=phase, cb=type_combo: self._on_phase_type_changed(p, cb)
        )
        playout.addWidget(QLabel("阶段类型："))
        playout.addWidget(type_combo)

        playout.addWidget(QLabel("音频资源："))
        audio_edit = QLineEdit(phase.get("audioAsset", ""))
        audio_edit.textChanged.connect(lambda t, p=phase: p.__setitem__("audioAsset", t))
        playout.addWidget(audio_edit)

        playout.addWidget(QLabel("Transcript："))
        transcript_edit = QTextEdit()
        transcript_edit.setPlainText(phase.get("transcript", ""))
        transcript_edit.setMaximumHeight(80)
        transcript_edit.textChanged.connect(
            lambda e=transcript_edit, p=phase: p.__setitem__("transcript", e.toPlainText())
        )
        playout.addWidget(transcript_edit)

        if listening_phase_has_items(phase.get("type", "")):
            for item in phase.get("items", []) or []:
                playout.addWidget(self._build_card(phase, item))
            playout.addWidget(self._add_item_row(phase))

        playout.addStretch()
        return widget

    def _build_phase_header(self, phase: dict[str, Any]) -> QWidget:
        header = QWidget()
        hlayout = QHBoxLayout(header)
        hlayout.setContentsMargins(0, 0, 0, 0)
        hlayout.setSpacing(6)

        title = QLabel(f"📁 {phase.get('name', phase.get('id', ''))}")
        title.setStyleSheet("font-size: 15px; font-weight: 700; color: #E8EAF0;")
        hlayout.addWidget(title)
        hlayout.addStretch()

        hlayout.addWidget(self._tool_button("✏️", "重命名", lambda _c=False, p=phase: self._on_rename_phase(p)))

        phases = self.lesson.get("content", {}).get("listeningPhases", []) or []
        idx = phases.index(phase) if phase in phases else -1
        up_btn = self._tool_button("↑", "上移", lambda _c=False, p=phase, i=idx: self._on_move_phase(p, i, -1))
        up_btn.setEnabled(idx > 0)
        hlayout.addWidget(up_btn)
        down_btn = self._tool_button("↓", "下移", lambda _c=False, p=phase, i=idx: self._on_move_phase(p, i, 1))
        down_btn.setEnabled(idx >= 0 and idx < len(phases) - 1)
        hlayout.addWidget(down_btn)

        hlayout.addWidget(self._tool_button("🗑️", "删除", lambda _c=False, p=phase: self._on_delete_phase(p)))

        return header

    def _on_add_phase(self) -> None:
        add_listening_phase(self.lesson, "wordPairing", "新阶段")
        self.changed.emit()
        self._build_teacher_view()

    def _on_rename_phase(self, phase: dict[str, Any]) -> None:
        old = phase.get("name", "")
        text, ok = QInputDialog.getText(self, "重命名", "新名称：", text=old)
        if ok and text:
            rename_listening_phase(phase, text)
            self.changed.emit()
            self._build_teacher_view()

    def _on_delete_phase(self, phase: dict[str, Any]) -> None:
        reply = QMessageBox.question(
            self, "删除听力阶段", f"确认删除听力阶段「{phase.get('name', '')}」？",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
        )
        if reply != QMessageBox.StandardButton.Yes:
            return
        delete_listening_phase(self.lesson, phase.get("id", ""))
        self.changed.emit()
        self._build_teacher_view()

    def _on_move_phase(self, phase: dict[str, Any], idx: int, delta: int) -> None:
        phases = self.lesson.get("content", {}).get("listeningPhases", []) or []
        if phase not in phases:
            return
        new_idx = idx + delta
        if not (0 <= new_idx < len(phases)):
            return
        move_listening_phase(self.lesson, idx, new_idx)
        self.changed.emit()
        self._build_teacher_view()

    def _on_phase_type_changed(self, phase: dict[str, Any], combo: QComboBox) -> None:
        new_type = combo.currentData()
        old_type = phase.get("type", "")
        if new_type == old_type:
            return
        phase["type"] = new_type
        if listening_phase_has_items(new_type):
            phase.setdefault("items", [])
        else:
            phase.pop("items", None)
        if new_type in ("dialogue", "summary"):
            phase.setdefault("audioAsset", "")
            phase.setdefault("transcript", "")
        self.changed.emit()
        self._build_teacher_view()


class ReadingTeacherWidget(TeacherTemplateWidget):
    """Teacher view for reading lessons: passage + comprehension items."""

    def _build_teacher_view(self) -> None:
        layout = self._content_layout
        if layout is None:
            return

        title = QLabel(f"📖 {self.lesson.get('name', '')}")
        title.setStyleSheet("font-size: 18px; font-weight: 700; color: #FFFFFF;")
        layout.addWidget(title)

        passage = self.lesson.setdefault("content", {}).setdefault("readingPassage", {})
        layout.addWidget(QLabel("标题："))
        title_edit = QLineEdit(passage.get("title", ""))
        title_edit.textChanged.connect(lambda t, p=passage: p.__setitem__("title", t))
        layout.addWidget(title_edit)

        layout.addWidget(QLabel("正文段落（每段一行）："))
        paragraphs_edit = QTextEdit()
        paragraphs = passage.get("paragraphs", []) or []
        paragraphs_edit.setPlainText("\n\n".join(paragraphs))
        paragraphs_edit.setMaximumHeight(160)
        paragraphs_edit.textChanged.connect(
            lambda e=paragraphs_edit, p=passage: p.__setitem__(
                "paragraphs",
                [para.strip() for para in e.toPlainText().split("\n\n") if para.strip()],
            )
        )
        layout.addWidget(paragraphs_edit)

        stage = self._stage()
        if stage is not None:
            layout.addWidget(QLabel(f"📝 {stage.get('name', ' comprehension')}"))
            for item in stage.get("items", []) or []:
                layout.addWidget(self._build_card(stage, item))
            layout.addWidget(self._add_item_row(stage))

        layout.addStretch()

    def _stage(self) -> dict[str, Any] | None:
        stages = self.lesson.get("content", {}).get("stages", []) or []
        return stages[0] if stages else None


class MasteryTeacherWidget(TeacherTemplateWidget):
    """Teacher view for mastery lessons: single stage with items."""

    def _build_teacher_view(self) -> None:
        layout = self._content_layout
        if layout is None:
            return

        title = QLabel(f"🏆 {self.lesson.get('name', '')}")
        title.setStyleSheet("font-size: 18px; font-weight: 700; color: #FFFFFF;")
        layout.addWidget(title)

        stage = self._stage()
        if stage is None:
            from src.backend.lesson_content import add_stage
            stage = add_stage(self.lesson.setdefault("content", {}), "Check")

        layout.addWidget(QLabel(f"📝 {stage.get('name', '综合测验')}"))
        for item in stage.get("items", []) or []:
            layout.addWidget(self._build_card(stage, item))
        layout.addWidget(self._add_item_row(stage))
        layout.addStretch()

    def _stage(self) -> dict[str, Any] | None:
        stages = self.lesson.get("content", {}).get("stages", []) or []
        return stages[0] if stages else None
