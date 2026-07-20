"""Template-aware teacher view for sub-lesson based templates.

Handles intro / practice / review / legacy with a shared linear flow, but adds:
- a template badge so teachers always know which canonical template they are editing
- a default interaction type matching the pedagogical intent
- one-click content generators tailored to each template
"""
from __future__ import annotations

from typing import Any

from PySide6.QtCore import Qt
from PySide6.QtWidgets import (
    QCheckBox,
    QDialog,
    QDialogButtonBox,
    QLabel,
    QListWidget,
    QListWidgetItem,
    QMessageBox,
    QPushButton,
    QVBoxLayout,
    QWidget,
)
from shiboken6 import isValid

from src.backend.ai_generator import AiApiConfig
from src.backend.course_adapter import CourseAdapter
from src.backend.lesson_content import (
    INTERACTION_LABELS,
    build_intro_lesson,
    build_practice_lesson,
    build_review_lesson,
)
from src.dialogs.ai_lesson_helper_dialog import AiLessonHelperDialog
from src.teacher.linear_flow import LinearFlowWidget
from src.teacher.preview_window import _PreviewCard
from src.theme import current_palette
from src.widgets.option_models import build_options_model


class _WordSelectorDialog(QDialog):
    """Simple multi-select word dialog with optional mix-type checkboxes."""

    def __init__(
        self,
        adapter: CourseAdapter,
        title: str,
        allow_mix_types: bool = False,
        parent: QWidget | None = None,
    ) -> None:
        super().__init__(parent)
        self.setWindowTitle(title)
        self.resize(480, 520)
        self._selected_word_ids: set[str] = set()
        self._selected_types: tuple[str, ...] = ()

        layout = QVBoxLayout(self)
        layout.addWidget(QLabel("<b>选择要使用的词汇：</b>"))

        self.word_list = QListWidget()
        for wid, label in adapter.vocab_options():
            item = QListWidgetItem(label)
            item.setData(Qt.ItemDataRole.UserRole, wid)
            item.setFlags(item.flags() | Qt.ItemFlag.ItemIsUserCheckable)
            item.setCheckState(Qt.CheckState.Unchecked)
            self.word_list.addItem(item)
        layout.addWidget(self.word_list)

        self.mix_group: QWidget | None = None
        self.type_checkboxes: dict[str, QCheckBox] = {}
        if allow_mix_types:
            self.mix_group = QWidget()
            mix_layout = QVBoxLayout(self.mix_group)
            mix_layout.setContentsMargins(0, 0, 0, 0)
            mix_layout.addWidget(QLabel("<b>包含哪些题型：</b>"))
            for rt in ("multipleChoice", "fillBlank", "translateSentence", "typeTheWord"):
                cb = QCheckBox(INTERACTION_LABELS.get(rt, rt))
                cb.setProperty("runtimeType", rt)
                if rt in ("multipleChoice", "fillBlank"):
                    cb.setChecked(True)
                mix_layout.addWidget(cb)
                self.type_checkboxes[rt] = cb
            layout.addWidget(self.mix_group)

        self.summary = QLabel("已选 0 个词")
        self.summary.setStyleSheet("color: gray;")
        layout.addWidget(self.summary)
        self.word_list.itemChanged.connect(self._update_summary)

        buttons = QDialogButtonBox(
            QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel
        )
        buttons.button(QDialogButtonBox.StandardButton.Ok).setText("生成")
        buttons.accepted.connect(self._on_accept)
        buttons.rejected.connect(self.reject)
        layout.addWidget(buttons)

    def _update_summary(self, _item: QListWidgetItem | None = None) -> None:
        n = sum(
            1
            for i in range(self.word_list.count())
            if self.word_list.item(i).checkState() == Qt.CheckState.Checked
        )
        self.summary.setText(f"已选 {n} 个词")

    def _on_accept(self) -> None:
        self._selected_word_ids = {
            self.word_list.item(i).data(Qt.ItemDataRole.UserRole)
            for i in range(self.word_list.count())
            if self.word_list.item(i).checkState() == Qt.CheckState.Checked
        }
        if not self._selected_word_ids:
            self.summary.setText("⚠️ 请至少选择 1 个词")
            self.summary.setStyleSheet(f"color: {current_palette()['error']};")
            return
        types = [
            rt
            for rt, cb in self.type_checkboxes.items()
            if cb.isChecked()
        ]
        self._selected_types = tuple(types)
        self.accept()

    def selected_word_ids(self) -> set[str]:
        return self._selected_word_ids

    def selected_types(self) -> tuple[str, ...]:
        return self._selected_types


class SubLessonFlowWidget(LinearFlowWidget):
    """Teacher view for intro / practice / review / legacy lessons."""

    _DEFAULT_ITEM_TYPE: dict[str, str] = {
        "intro": "showWord",
        "practice": "multipleChoice",
        "review": "multipleChoice",
        "legacy": "multipleChoice",
    }

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
        self.template = lesson.get("template", "legacy")
        self._assistant_title = {
            "intro": "从词库生成认识课",
            "practice": "从词库生成练习",
            "review": "从词库生成复习",
        }.get(self.template)
        self.ai_config = ai_config
        self._preview_visible = False
        self._preview_container: QWidget | None = None
        super().__init__(adapter, section, unit, lesson, parent, undo_stack)
        self._last_item_type = self._DEFAULT_ITEM_TYPE.get(
            self.template, "multipleChoice"
        )
        self.changed.connect(self._refresh_preview)

    def _alive_preview(self) -> QWidget | None:
        """Return preview container only if its C++ object is still alive."""
        w = self._preview_container
        if w is None or not isValid(w):
            if w is not None:
                self._preview_container = None
            return None
        return w

    def _on_toggle_preview(self, checked: bool) -> None:
        self._preview_visible = checked
        container = self._alive_preview()
        if container is None:
            return
        container.setVisible(checked)
        if checked:
            self._refresh_preview()

    def _refresh_preview(self) -> None:
        container = self._alive_preview()
        if container is None or not container.isVisible():
            return
        layout = container.layout()
        if layout is None:
            return
        while layout.count():
            child = layout.takeAt(0)
            widget = child.widget()
            if widget is not None:
                widget.setParent(None)
                widget.deleteLater()

        items = self._collect_items()
        if not items:
            layout.addWidget(QLabel("（暂无题目）"))
            return
        for item in items:
            layout.addWidget(_PreviewCard(self.adapter, item))
        layout.addStretch()

    def _collect_items(self) -> list[dict[str, Any]]:
        items: list[dict[str, Any]] = []
        content = self.lesson.get("content", {})
        for sub in content.get("subLessons", []) or []:
            for stage in sub.get("stages", []) or []:
                items.extend(stage.get("items", []) or [])
        return items

    def _build_ui(self) -> None:
        from src.teacher.shell_header import build_teacher_header

        self._sub_lesson_frames.clear()
        self._preview_container = None
        if self.layout() is not None:
            while self.layout().count():
                child = self.layout().takeAt(0)
                widget = child.widget()
                if widget is not None:
                    widget.setParent(None)
                    widget.deleteLater()
        else:
            QVBoxLayout(self)

        main = self.layout()
        if main is None:
            return
        main.setSpacing(12)
        main.setContentsMargins(12, 12, 12, 12)

        # Header: breadcrumb + badge row, then a wrapping row of action
        # buttons (template extras first, then 预览/AI改写/高级编辑).
        extras: list[QWidget] = []
        if self._assistant_title is not None:
            assistant_btn = QPushButton(self._assistant_title)
            assistant_btn.setToolTip("根据所选词汇一键生成完整课程结构")
            assistant_btn.clicked.connect(self._on_generate_from_vocab)
            extras.append(assistant_btn)

        preview_toggle = QPushButton("实时预览")
        preview_toggle.setCheckable(True)
        preview_toggle.setChecked(self._preview_visible)
        preview_toggle.setToolTip("在当前页面内预览所有题目")
        preview_toggle.toggled.connect(self._on_toggle_preview)
        extras.append(preview_toggle)

        header, self._advanced_btn = build_teacher_header(
            self.section,
            self.unit,
            self.lesson,
            on_preview=self._on_preview,
            on_ai_rewrite=self._on_ai_rewrite,
            on_advanced_toggled=self._on_advanced_toggled,
            extra_widgets=extras,
        )
        main.addWidget(header)

        # Body host: swapped between teacher view and raw LessonEditor.
        self._content_host = QWidget()
        self._content_layout = QVBoxLayout(self._content_host)
        self._content_layout.setContentsMargins(0, 0, 0, 0)
        self._content_layout.setSpacing(12)
        main.addWidget(self._content_host, 1)

        self._build_teacher_body()

    def _build_teacher_body(self) -> None:
        """Build the teacher-view body: live preview + sub-lesson frames."""
        self._clear_content()

        # Shared reference models for all cards in this render pass.
        self._vocab_model = build_options_model(
            self.adapter.vocab_options(), placeholder="(未选择)"
        )
        self._expression_model = build_options_model(
            self.adapter.expression_options(), placeholder="(无)"
        )
        self._grammar_model = build_options_model(
            self.adapter.grammar_options(), placeholder="(未关联)"
        )

        self._preview_container = QWidget()
        preview_layout = QVBoxLayout(self._preview_container)
        preview_layout.setContentsMargins(8, 8, 8, 8)
        preview_layout.setSpacing(8)
        self._preview_container.setStyleSheet(
            "background-color: #1A1D24; border: 1px solid #2C313C; border-radius: 8px;"
        )
        self._preview_container.setVisible(self._preview_visible)
        self._content_layout.addWidget(self._preview_container)
        self._refresh_preview()

        for sl in self._sub_lessons():
            frame = self._build_sub_lesson(sl)
            self._content_layout.addWidget(frame)

        self._add_sub_btn = QPushButton("+ 添加教学环节")
        self._add_sub_btn.clicked.connect(self._on_add_sub_lesson)
        self._content_layout.addWidget(self._add_sub_btn)
        self._content_layout.addStretch()

    def _clear_content(self) -> None:
        # Drop Python refs before deleteLater so toggle/refresh cannot touch
        # a destroyed C++ QWidget (shiboken RuntimeError).
        self._preview_container = None
        if self._content_layout is None:
            return
        while self._content_layout.count():
            child = self._content_layout.takeAt(0)
            widget = child.widget()
            if widget is not None:
                widget.setParent(None)
                widget.deleteLater()

    def _on_advanced_toggled(self, checked: bool) -> None:
        from src.widgets.lesson_editor import LessonEditor

        if self._advanced_btn is not None:
            self._advanced_btn.setText("返回教师视图" if checked else "高级编辑")
        if checked:
            self._preview_visible = False
        self._clear_content()
        if checked:
            editor = LessonEditor(self.adapter, self.lesson)
            self._content_layout.addWidget(editor)
        else:
            self._build_teacher_body()

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
            cmd.signals.changed.connect(self._rebuild)
            self.undo_stack.push(cmd)
        else:
            self.lesson["content"] = result.get("content", self.lesson.get("content"))
            self.lesson["template"] = result.get("template", self.lesson.get("template"))
        self._rebuild()
        self.changed.emit()

    def _on_generate_from_vocab(self) -> None:
        dialog = _WordSelectorDialog(
            self.adapter,
            self._assistant_title or "生成课程",
            allow_mix_types=self.template == "practice",
            parent=self,
        )
        if dialog.exec() != QDialog.DialogCode.Accepted:
            return

        words = [w for w in self.adapter.vocab if w["id"] in dialog.selected_word_ids()]
        if not words:
            return

        name = self.lesson.get("name", "")
        description = self.lesson.get("description", "")

        if self.template == "intro":
            generated = build_intro_lesson(name, description, words)
        elif self.template == "practice":
            generated = build_practice_lesson(
                name, description, words, dialog.selected_types()
            )
        elif self.template == "review":
            generated = build_review_lesson(name, description, words)
        else:
            return

        reply = QMessageBox.question(
            self,
            "覆盖确认",
            "生成新课程结构会替换当前课的所有内容，确定继续？",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
        )
        if reply != QMessageBox.StandardButton.Yes:
            return

        # Preserve identity-critical fields; replace content shape.
        self.lesson["content"] = generated["content"]
        self.lesson["template"] = generated["template"]
        self._rebuild()
        self.changed.emit()
