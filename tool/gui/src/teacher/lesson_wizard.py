"""Lesson wizard for the teacher view (guiplan §15.3, T.2).

Replaces empty-template cloning with a guided flow: the teacher picks a course
type and a set of words, and the wizard generates a contract-valid lesson
structure. For the intro template each selected word becomes one sub-lesson
with three stages (show word -> translate -> fill blank).

The generation is a pure function (build_intro_lesson) so it can be unit-tested
without PySide6 and round-trip tested against course_cli validate.
"""
from __future__ import annotations

from typing import Any

from PySide6.QtCore import Qt
from PySide6.QtWidgets import (
    QCheckBox,
    QDialog,
    QDialogButtonBox,
    QFormLayout,
    QLabel,
    QLineEdit,
    QListWidget,
    QListWidgetItem,
    QPushButton,
    QVBoxLayout,
    QWidget,
)

from src.backend.course_adapter import CourseAdapter
from src.backend.lesson_content import short_id
from src.i18n.labels import TEMPLATE_LABELS


def build_intro_lesson(
    name: str,
    description: str,
    words: list[dict[str, Any]],
) -> dict[str, Any]:
    """Generate an intro lesson from selected vocab words.

    Each word becomes one sub-lesson (教学环节) with three stages:
    1. showWord - present the new word
    2. translateSentence - translate the word's meaning
    3. fillBlank - reinforce with a fill-in-the-blank

    Pure function: no I/O, no id collisions with existing lessons (caller
    appends to unit; ids are fresh via short_id).
    """
    sub_lessons: list[dict[str, Any]] = []
    for w in words:
        wid = w["id"]
        term = w.get("term", wid)
        translation = w.get("translation", "")
        sub_lessons.append(
            {
                "id": short_id("sl"),
                "name": f"认识 {term}",
                "stages": [
                    {
                        "id": short_id("st"),
                        "name": "展示",
                        "items": [
                            {
                                "runtimeType": "showWord",
                                "id": short_id("sw"),
                                "wordId": wid,
                                "context": "",
                                "grammarPointId": "",
                                "expressionId": "",
                            }
                        ],
                    },
                    {
                        "id": short_id("st"),
                        "name": "翻译",
                        "items": [
                            {
                                "runtimeType": "translateSentence",
                                "id": short_id("ts"),
                                "source": translation,
                                "expected": term,
                                "hints": [],
                                "grammarPointId": "",
                            }
                        ],
                    },
                    {
                        "id": short_id("st"),
                        "name": "填空",
                        "items": [
                            {
                                "runtimeType": "fillBlank",
                                "id": short_id("fb"),
                                "sentence": f"___ -> {translation}",
                                "answer": term,
                                "hint": "",
                                "grammarPointId": "",
                            }
                        ],
                    },
                ],
            }
        )
    return {
        "id": short_id("l"),
        "name": name or "新认识新词课",
        "description": description,
        "type": "normal",
        "template": "intro",
        "prerequisiteLessonIds": [],
        "content": {"subLessons": sub_lessons},
    }


class LessonWizardDialog(QDialog):
    """Guided new-lesson dialog. Step 1: pick type. Step 2: pick words."""

    def __init__(self, adapter: CourseAdapter, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.setWindowTitle("新建课 - 向导")
        self.resize(560, 620)
        self.adapter = adapter
        self._lesson: dict[str, Any] | None = None
        self._build_ui()

    def _build_ui(self) -> None:
        layout = QVBoxLayout(self)

        layout.addWidget(QLabel("<b>第 1 步：你想创建什么课？</b>"))
        self.template_hint = QLabel(
            f"当前仅支持「{TEMPLATE_LABELS['intro']}」（选词自动生成展示+翻译+填空）"
        )
        self.template_hint.setStyleSheet("color: gray;")
        layout.addWidget(self.template_hint)

        layout.addWidget(QLabel("<b>第 2 步：课程名称与描述</b>"))
        form = QFormLayout()
        self.name_edit = QLineEdit()
        self.name_edit.setPlaceholderText("如：问候语")
        self.desc_edit = QLineEdit()
        self.desc_edit.setPlaceholderText("一句话说明这节课学什么")
        form.addRow("名称:", self.name_edit)
        form.addRow("描述:", self.desc_edit)
        layout.addLayout(form)

        layout.addWidget(QLabel("<b>第 3 步：你今天要教哪些词？</b>"))
        self.word_list = QListWidget()
        for wid, label in self.adapter.vocab_options():
            item = QListWidgetItem(label)
            item.setData(Qt.ItemDataRole.UserRole, wid)
            item.setFlags(item.flags() | Qt.ItemFlag.ItemIsUserCheckable)
            item.setCheckState(Qt.CheckState.Unchecked)
            self.word_list.addItem(item)
        layout.addWidget(self.word_list)

        self.summary = QLabel("已选 0 个词")
        self.summary.setStyleSheet("color: gray;")
        layout.addWidget(self.summary)
        self.word_list.itemChanged.connect(self._update_summary)

        self.buttons = QDialogButtonBox(
            QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel
        )
        self.buttons.button(QDialogButtonBox.StandardButton.Ok).setText("生成课程")
        self.buttons.accepted.connect(self._on_generate)
        self.buttons.rejected.connect(self.reject)
        layout.addWidget(self.buttons)

    def _update_summary(self, _item: QListWidgetItem) -> None:
        n = sum(
            1
            for i in range(self.word_list.count())
            if self.word_list.item(i).checkState() == Qt.CheckState.Checked
        )
        self.summary.setText(f"已选 {n} 个词，将生成 {n} 个教学环节")

    def _selected_words(self) -> list[dict[str, Any]]:
        ids = {
            self.word_list.item(i).data(Qt.ItemDataRole.UserRole)
            for i in range(self.word_list.count())
            if self.word_list.item(i).checkState() == Qt.CheckState.Checked
        }
        return [w for w in self.adapter.vocab if w["id"] in ids]

    def _on_generate(self) -> None:
        words = self._selected_words()
        if not words:
            self.summary.setText("⚠️ 请至少选择 1 个词")
            self.summary.setStyleSheet("color: #E74C3C;")
            return
        self._lesson = build_intro_lesson(
            self.name_edit.text().strip(),
            self.desc_edit.text().strip(),
            words,
        )
        self.accept()

    def lesson(self) -> dict[str, Any] | None:
        return self._lesson
