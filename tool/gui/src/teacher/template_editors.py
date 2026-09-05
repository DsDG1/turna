"""Teacher-friendly editors for listening, reading, and mastery lesson templates.

Each widget provides a simplified view plus an "Advanced Edit" button that
switches to the full expert LessonEditor for that lesson.
"""
from __future__ import annotations

from typing import Any

from PySide6.QtCore import Signal
from PySide6.QtWidgets import (
    QComboBox,
    QDialog,
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

from src.application.commands import (
    AddItemCommand,
    AddListeningPhaseCommand,
    DeleteItemCommand,
    DeleteListeningPhaseCommand,
    MoveItemCommand,
    MoveListeningPhaseCommand,
    RenameListeningPhaseCommand,
    ReplaceItemCommand,
)
from src.backend.ai_generator import AiApiConfig
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
from src.dialogs.ai_lesson_helper_dialog import AiLessonHelperDialog
from src.i18n.labels import interaction_label
from src.teacher.question_cards import QuestionCard
from src.theme import current_palette


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
        ai_config: AiApiConfig | None = None,
    ) -> None:
        super().__init__(parent)
        self.adapter = adapter
        self.section = section
        self.unit = unit
        self.lesson = lesson
        self.undo_stack = undo_stack
        self.ai_config = ai_config
        self._advanced_btn: QPushButton | None = None
        self._content_layout: QVBoxLayout | None = None
        self._last_item_type = "multipleChoice"
        self._build_ui()

    def _build_ui(self) -> None:
        from src.teacher.shell_header import build_teacher_header

        layout = QVBoxLayout(self)
        layout.setContentsMargins(12, 12, 12, 12)
        layout.setSpacing(12)

        header, self._advanced_btn = build_teacher_header(
            self.section,
            self.unit,
            self.lesson,
            on_preview=self._on_preview,
            on_ai_rewrite=self._on_ai_rewrite,
            on_advanced_toggled=self._on_advanced_toggled,
        )
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
            widget = child.widget()
            if widget is not None:
                widget.setParent(None)
                widget.deleteLater()

    def _build_teacher_view(self) -> None:
        raise NotImplementedError

    def _tool_button(self, text: str, tooltip: str, callback) -> QPushButton:
        btn = QPushButton(text)
        btn.setMinimumWidth(48)
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
        card.setProperty("stage", stage)
        card.changed.connect(self.changed.emit)
        card.delete_requested.connect(self._on_card_delete_requested)
        card.type_changed.connect(self._on_card_type_changed)
        card.move_up_requested.connect(self._on_card_move_up_requested)
        card.move_down_requested.connect(self._on_card_move_down_requested)
        card.ai_rewrite_requested.connect(self._on_card_ai_rewrite_requested)
        return card

    def _on_card_delete_requested(self) -> None:
        card = self.sender()
        if isinstance(card, QuestionCard):
            stage = card.property("stage")
            if isinstance(stage, dict):
                self._delete_item(stage, card.item)

    def _on_card_type_changed(self, new_type: str) -> None:
        card = self.sender()
        if isinstance(card, QuestionCard):
            stage = card.property("stage")
            if isinstance(stage, dict):
                self._change_item_type(stage, card.item, new_type)

    def _on_card_move_up_requested(self) -> None:
        card = self.sender()
        if isinstance(card, QuestionCard):
            stage = card.property("stage")
            if isinstance(stage, dict):
                self._move_item(stage, card.item, -1)

    def _on_card_move_down_requested(self) -> None:
        card = self.sender()
        if isinstance(card, QuestionCard):
            stage = card.property("stage")
            if isinstance(stage, dict):
                self._move_item(stage, card.item, 1)

    def _on_card_ai_rewrite_requested(self) -> None:
        card = self.sender()
        if isinstance(card, QuestionCard):
            stage = card.property("stage")
            if isinstance(stage, dict):
                self._on_ai_rewrite_item(stage, card.item)

    def _on_ai_rewrite_item(self, stage: dict[str, Any], item: dict[str, Any]) -> None:
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
        item_id = item.get("id", "")
        if not item_id:
            return
        # Light confirm: show before/after prompt snippet (U1-3).
        before = str(item.get("prompt") or item.get("sentence") or item.get("id") or "")
        after = str(result.get("prompt") or result.get("sentence") or result.get("id") or "")
        if before != after:
            reply = QMessageBox.question(
                self,
                "确认 AI 改题",
                f"将替换本题内容：\n\n前：{before[:120]}\n后：{after[:120]}\n\n"
                "确认应用？（之后可用 Ctrl+Z 撤销）",
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
            )
            if reply != QMessageBox.StandardButton.Yes:
                return
        if self.undo_stack is not None:
            cmd = ReplaceItemCommand(stage, item_id, result)
            cmd.signals.changed.connect(self._build_teacher_view)
            self.undo_stack.push(cmd)
        else:
            items = stage.get("items", [])
            for i, it in enumerate(items):
                if it.get("id") == item_id:
                    items[i] = result
                    break
            self._build_teacher_view()
        self.changed.emit()

    def _delete_item(self, stage: dict[str, Any], item: dict[str, Any]) -> None:
        reply = QMessageBox.question(
            self, "删除题目", "确认删除这道题目？",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
        )
        if reply != QMessageBox.StandardButton.Yes:
            return
        if self.undo_stack is not None:
            cmd = DeleteItemCommand(stage, item)
            cmd.signals.changed.connect(self._build_teacher_view)
            self.undo_stack.push(cmd)
        else:
            delete_item(stage, item.get("id", ""))
            self._build_teacher_view()
        self.changed.emit()

    def _change_item_type(self, stage: dict[str, Any], item: dict[str, Any], new_type: str) -> None:
        new_item = switch_runtime_type(item, new_type)
        item_id = item.get("id", "")
        if not item_id:
            return
        if self.undo_stack is not None:
            cmd = ReplaceItemCommand(stage, item_id, new_item)
            cmd.signals.changed.connect(self._build_teacher_view)
            self.undo_stack.push(cmd)
        else:
            items = stage.get("items", [])
            for i, it in enumerate(items):
                if it.get("id") == item_id:
                    items[i] = new_item
                    break
            self._build_teacher_view()
        self.changed.emit()

    def _move_item(self, stage: dict[str, Any], item: dict[str, Any], delta: int) -> None:
        items = stage.get("items", [])
        try:
            idx = items.index(item)
        except ValueError:
            return
        new_idx = idx + delta
        if not (0 <= new_idx < len(items)):
            return
        if self.undo_stack is not None:
            cmd = MoveItemCommand(stage, idx, new_idx)
            cmd.signals.changed.connect(self._build_teacher_view)
            self.undo_stack.push(cmd)
        else:
            move_item(stage, idx, new_idx)
            self._build_teacher_view()
        self.changed.emit()

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
        add_btn.setProperty("stage", stage)
        add_btn.setProperty("combo", combo)
        add_btn.clicked.connect(self._on_add_item_btn_clicked)
        layout.addWidget(add_btn)
        return row

    def _on_add_item_btn_clicked(self) -> None:
        btn = self.sender()
        if isinstance(btn, QPushButton):
            stage = btn.property("stage")
            combo = btn.property("combo")
            if isinstance(stage, dict) and isinstance(combo, QComboBox):
                self._on_add_item(stage, combo)

    def _on_add_item(self, stage: dict[str, Any], combo: QComboBox) -> None:
        rt = combo.currentData() or "multipleChoice"
        self._last_item_type = rt
        if self.undo_stack is not None:
            cmd = AddItemCommand(stage, rt)
            cmd.signals.changed.connect(self._build_teacher_view)
            self.undo_stack.push(cmd)
        else:
            add_item(stage, rt)
            self._build_teacher_view()
        self.changed.emit()

    def refresh_references(self) -> None:
        """Rebuild teacher view so QuestionCard reference dropdowns pick up
        resource changes (A3)."""
        self._build_teacher_view()

    def _on_preview(self) -> None:
        from src.teacher.preview_window import LessonPreviewDialog

        dlg = LessonPreviewDialog(self.adapter, self.lesson, self)
        dlg.exec()

    def _on_ai_rewrite(self) -> None:
        from src.application.commands import AiEditLessonCommand

        dialog = AiLessonHelperDialog(
            self.adapter,
            self.lesson,
            mode="lesson",
            parent=self,
        )
        if dialog.exec() != QDialog.DialogCode.Accepted:
            return
        result = dialog.result()
        if result is None:
            return
        if self.undo_stack is not None:
            cmd = AiEditLessonCommand(self.adapter, self.lesson.get("id", ""), result)
            cmd.signals.changed.connect(self._build_teacher_view)
            self.undo_stack.push(cmd)
        else:
            self.lesson["content"] = result.get("content", self.lesson.get("content"))
            self.lesson["template"] = result.get("template", self.lesson.get("template"))
            self._build_teacher_view()
        self.changed.emit()


class ListeningTeacherWidget(TeacherTemplateWidget):
    """Teacher view for listening lessons: phases with optional items."""

    def _build_teacher_view(self) -> None:
        layout = self._content_layout
        if layout is None:
            return

        title = QLabel(self.lesson.get('name', ''))
        title.setStyleSheet(f"font-size: 18px; font-weight: 700; color: {current_palette()['text']};")
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
        widget.setStyleSheet(f"QWidget {{ background-color: {current_palette()['bg_elevated']}; border-radius: 10px; }}")
        playout = QVBoxLayout(widget)
        playout.setSpacing(10)
        playout.setContentsMargins(12, 12, 12, 12)

        playout.addWidget(self._build_phase_header(phase))

        type_combo = QComboBox()
        for pt in ("wordPairing", "dialogue", "summary"):
            type_combo.addItem(pt, pt)
        type_combo.setCurrentIndex(type_combo.findData(phase.get("type", "wordPairing")))
        type_combo.setProperty("phase", phase)
        type_combo.currentIndexChanged.connect(self._on_phase_type_combo_changed)
        playout.addWidget(QLabel("阶段类型："))
        playout.addWidget(type_combo)

        playout.addWidget(QLabel("音频资源："))
        audio_edit = QLineEdit(phase.get("audioAsset", ""))
        audio_edit.setProperty("phase", phase)
        audio_edit.textChanged.connect(self._on_phase_audio_changed)
        playout.addWidget(audio_edit)

        playout.addWidget(QLabel("Transcript："))
        transcript_edit = QTextEdit()
        transcript_edit.setPlainText(phase.get("transcript", ""))
        transcript_edit.setMaximumHeight(80)
        transcript_edit.setProperty("phase", phase)
        transcript_edit.textChanged.connect(self._on_phase_transcript_changed)
        playout.addWidget(transcript_edit)

        if listening_phase_has_items(phase.get("type", "")):
            for item in phase.get("items", []) or []:
                playout.addWidget(self._build_card(phase, item))
            playout.addWidget(self._add_item_row(phase))

        playout.addStretch()
        return widget

    def _on_phase_type_combo_changed(self, _index: int) -> None:
        combo = self.sender()
        if isinstance(combo, QComboBox):
            phase = combo.property("phase")
            if isinstance(phase, dict):
                self._on_phase_type_changed(phase, combo)

    def _on_phase_audio_changed(self, text: str) -> None:
        edit = self.sender()
        if isinstance(edit, QLineEdit):
            phase = edit.property("phase")
            if isinstance(phase, dict):
                phase["audioAsset"] = text

    def _on_phase_transcript_changed(self) -> None:
        edit = self.sender()
        if isinstance(edit, QTextEdit):
            phase = edit.property("phase")
            if isinstance(phase, dict):
                phase["transcript"] = edit.toPlainText()

    def _build_phase_header(self, phase: dict[str, Any]) -> QWidget:
        header = QWidget()
        hlayout = QHBoxLayout(header)
        hlayout.setContentsMargins(0, 0, 0, 0)
        hlayout.setSpacing(6)

        title = QLabel(phase.get('name', phase.get('id', '')))
        title.setStyleSheet(f"font-size: 15px; font-weight: 700; color: {current_palette()['text']};")
        hlayout.addWidget(title)
        hlayout.addStretch()

        rename_btn = self._tool_button("重命名", "重命名", self._on_rename_phase_clicked)
        rename_btn.setProperty("phase", phase)
        hlayout.addWidget(rename_btn)

        phases = self.lesson.get("content", {}).get("listeningPhases", []) or []
        idx = phases.index(phase) if phase in phases else -1
        up_btn = self._tool_button("↑", "上移", self._on_move_phase_up_clicked)
        up_btn.setProperty("phase", phase)
        up_btn.setProperty("index", idx)
        up_btn.setEnabled(idx > 0)
        hlayout.addWidget(up_btn)
        down_btn = self._tool_button("↓", "下移", self._on_move_phase_down_clicked)
        down_btn.setProperty("phase", phase)
        down_btn.setProperty("index", idx)
        down_btn.setEnabled(idx >= 0 and idx < len(phases) - 1)
        hlayout.addWidget(down_btn)

        delete_btn = self._tool_button("删除", "删除", self._on_delete_phase_clicked)
        delete_btn.setProperty("phase", phase)
        hlayout.addWidget(delete_btn)

        return header

    def _on_rename_phase_clicked(self) -> None:
        btn = self.sender()
        if isinstance(btn, QPushButton):
            phase = btn.property("phase")
            if isinstance(phase, dict):
                self._on_rename_phase(phase)

    def _on_move_phase_up_clicked(self) -> None:
        btn = self.sender()
        if isinstance(btn, QPushButton):
            phase = btn.property("phase")
            idx = btn.property("index")
            if isinstance(phase, dict) and isinstance(idx, int):
                self._on_move_phase(phase, idx, -1)

    def _on_move_phase_down_clicked(self) -> None:
        btn = self.sender()
        if isinstance(btn, QPushButton):
            phase = btn.property("phase")
            idx = btn.property("index")
            if isinstance(phase, dict) and isinstance(idx, int):
                self._on_move_phase(phase, idx, 1)

    def _on_delete_phase_clicked(self) -> None:
        btn = self.sender()
        if isinstance(btn, QPushButton):
            phase = btn.property("phase")
            if isinstance(phase, dict):
                self._on_delete_phase(phase)

    def _on_add_phase(self) -> None:
        if self.undo_stack is not None:
            cmd = AddListeningPhaseCommand(self.lesson, "wordPairing", "新阶段")
            cmd.signals.changed.connect(self._build_teacher_view)
            self.undo_stack.push(cmd)
        else:
            add_listening_phase(self.lesson, "wordPairing", "新阶段")
            self._build_teacher_view()
        self.changed.emit()

    def _on_rename_phase(self, phase: dict[str, Any]) -> None:
        old = phase.get("name", "")
        text, ok = QInputDialog.getText(self, "重命名", "新名称：", text=old)
        if not ok or not text:
            return
        if self.undo_stack is not None:
            cmd = RenameListeningPhaseCommand(phase, text)
            cmd.signals.changed.connect(self._build_teacher_view)
            self.undo_stack.push(cmd)
        else:
            rename_listening_phase(phase, text)
            self._build_teacher_view()
        self.changed.emit()

    def _on_delete_phase(self, phase: dict[str, Any]) -> None:
        reply = QMessageBox.question(
            self, "删除听力阶段", f"确认删除听力阶段「{phase.get('name', '')}」？",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
        )
        if reply != QMessageBox.StandardButton.Yes:
            return
        if self.undo_stack is not None:
            cmd = DeleteListeningPhaseCommand(self.lesson, phase)
            cmd.signals.changed.connect(self._build_teacher_view)
            self.undo_stack.push(cmd)
        else:
            delete_listening_phase(self.lesson, phase.get("id", ""))
            self._build_teacher_view()
        self.changed.emit()

    def _on_move_phase(self, phase: dict[str, Any], idx: int, delta: int) -> None:
        phases = self.lesson.get("content", {}).get("listeningPhases", []) or []
        if phase not in phases:
            return
        new_idx = idx + delta
        if not (0 <= new_idx < len(phases)):
            return
        if self.undo_stack is not None:
            cmd = MoveListeningPhaseCommand(self.lesson, idx, new_idx)
            cmd.signals.changed.connect(self._build_teacher_view)
            self.undo_stack.push(cmd)
        else:
            move_listening_phase(self.lesson, idx, new_idx)
            self._build_teacher_view()
        self.changed.emit()

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

        title = QLabel(self.lesson.get('name', ''))
        title.setStyleSheet(f"font-size: 18px; font-weight: 700; color: {current_palette()['text']};")
        layout.addWidget(title)

        passage = self.lesson.setdefault("content", {}).setdefault("readingPassage", {})
        layout.addWidget(QLabel("标题："))
        title_edit = QLineEdit(passage.get("title", ""))
        title_edit.setProperty("passage", passage)
        title_edit.textChanged.connect(self._on_passage_title_changed)
        layout.addWidget(title_edit)

        layout.addWidget(QLabel("正文段落（每段一行）："))
        paragraphs_edit = QTextEdit()
        paragraphs = passage.get("paragraphs", []) or []
        paragraphs_edit.setPlainText("\n\n".join(paragraphs))
        paragraphs_edit.setMaximumHeight(160)
        paragraphs_edit.setProperty("passage", passage)
        paragraphs_edit.textChanged.connect(self._on_passage_paragraphs_changed)
        layout.addWidget(paragraphs_edit)

    def _on_passage_title_changed(self, text: str) -> None:
        edit = self.sender()
        if isinstance(edit, QLineEdit):
            passage = edit.property("passage")
            if isinstance(passage, dict):
                passage["title"] = text

    def _on_passage_paragraphs_changed(self) -> None:
        edit = self.sender()
        if isinstance(edit, QTextEdit):
            passage = edit.property("passage")
            if isinstance(passage, dict):
                passage["paragraphs"] = [
                    para.strip() for para in edit.toPlainText().split("\n\n") if para.strip()
                ]

        stage = self._stage()
        if stage is not None:
            layout.addWidget(QLabel(stage.get('name', ' comprehension')))
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

        title = QLabel(self.lesson.get('name', ''))
        title.setStyleSheet(f"font-size: 18px; font-weight: 700; color: {current_palette()['text']};")
        layout.addWidget(title)

        stage = self._stage()
        if stage is None:
            from src.backend.lesson_content import add_stage
            stage = add_stage(self.lesson.setdefault("content", {}), "Check")

        layout.addWidget(QLabel(stage.get('name', '综合测验')))
        for item in stage.get("items", []) or []:
            layout.addWidget(self._build_card(stage, item))
        layout.addWidget(self._add_item_row(stage))
        layout.addStretch()

    def _stage(self) -> dict[str, Any] | None:
        stages = self.lesson.get("content", {}).get("stages", []) or []
        return stages[0] if stages else None
