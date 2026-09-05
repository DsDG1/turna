"""Wizard generation panel creating intro courses from local vocabulary.

Decoupled from AiGeneratorDialog.
"""
from __future__ import annotations

import logging
from typing import Any

from PySide6.QtCore import Qt, Signal
from PySide6.QtWidgets import (
    QFormLayout,
    QLabel,
    QLineEdit,
    QListWidget,
    QListWidgetItem,
    QPushButton,
    QVBoxLayout,
    QWidget,
)

from src.backend.lesson_content import build_intro_lesson
from src.infrastructure.telemetry import telemetry

logger = logging.getLogger(__name__)


class GeneratorWizardPanel(QWidget):
    """Guided lesson creation that builds structured lessons directly from vocabulary."""

    generated_ready = Signal(dict)

    def __init__(
        self,
        adapter: Any,
        palette: dict[str, str] | None = None,
        parent: QWidget | None = None,
    ) -> None:
        super().__init__(parent)
        self.adapter = adapter
        self._pal = palette or {}

        layout = QVBoxLayout(self)
        layout.setSpacing(12)
        layout.setContentsMargins(0, 0, 0, 0)

        layout.addWidget(QLabel("<b>向导生成：从词库选题自动生成 intro 课程</b>"))

        form = QFormLayout()
        self.name_edit = QLineEdit()
        self.name_edit.setPlaceholderText("如：问候语")
        self.desc_edit = QLineEdit()
        self.desc_edit.setPlaceholderText("一句话说明这节课学什么")
        form.addRow("名称:", self.name_edit)
        form.addRow("描述:", self.desc_edit)
        layout.addLayout(form)

        layout.addWidget(QLabel("选择要教学的词："))
        self.word_list = QListWidget()
        if hasattr(self.adapter, "vocab_options"):
            for wid, label in self.adapter.vocab_options():
                item = QListWidgetItem(label)
                item.setData(Qt.ItemDataRole.UserRole, wid)
                item.setFlags(item.flags() | Qt.ItemFlag.ItemIsUserCheckable)
                item.setCheckState(Qt.CheckState.Unchecked)
                self.word_list.addItem(item)
        layout.addWidget(self.word_list)

        self.summary_label = QLabel("已选 0 个词")
        text_sec = self._pal.get("text_secondary", "#9CA3AF")
        self.summary_label.setStyleSheet(f"color: {text_sec};")
        layout.addWidget(self.summary_label)
        self.word_list.itemChanged.connect(self.update_summary)

        self.generate_btn = QPushButton("生成课程")
        self.generate_btn.clicked.connect(self.generate)
        layout.addWidget(self.generate_btn)
        layout.addStretch()

    def update_summary(self, _item: QListWidgetItem | None = None) -> None:
        n = sum(
            1
            for i in range(self.word_list.count())
            if self.word_list.item(i).checkState() == Qt.CheckState.Checked
        )
        self.summary_label.setText(f"已选 {n} 个词，将生成 {n} 个教学环节")

    def selected_words(self) -> list[dict[str, Any]]:
        ids = {
            self.word_list.item(i).data(Qt.ItemDataRole.UserRole)
            for i in range(self.word_list.count())
            if self.word_list.item(i).checkState() == Qt.CheckState.Checked
        }
        vocab = getattr(self.adapter, "vocab", []) or []
        return [w for w in vocab if w.get("id") in ids]

    def generate(self) -> dict[str, Any] | None:
        words = self.selected_words()
        if not words:
            err_color = self._pal.get("error", "#E74C3C")
            self.summary_label.setText("⚠️ 请至少选择 1 个词")
            self.summary_label.setStyleSheet(f"color: {err_color};")
            return None

        lesson = build_intro_lesson(
            self.name_edit.text().strip(),
            self.desc_edit.text().strip(),
            words,
        )
        section = {
            "id": f"wizard-{lesson.get('id', 'lesson')}",
            "name": lesson.get("name", "向导课程"),
            "description": lesson.get("description", ""),
            "prerequisiteSectionIds": [],
            "words": [],
            "expressions": [],
            "grammarPoints": [],
            "units": [
                {
                    "id": f"wizard-{lesson.get('id', 'lesson')}-u1",
                    "name": "Unit 1",
                    "description": "",
                    "prerequisiteUnitIds": [],
                    "lessons": [lesson],
                }
            ],
        }
        telemetry.record_event("ai.wizard.generate", payload={"lesson_id": lesson.get("id", "")})
        self.generated_ready.emit(section)
        return section
