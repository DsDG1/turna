"""Dialog for creating a new lesson from a template."""
from __future__ import annotations

from PySide6.QtWidgets import (
    QComboBox,
    QDialog,
    QDialogButtonBox,
    QFormLayout,
    QLineEdit,
)

from src.backend.lesson_content import TEMPLATE_LABELS

NEW_TEMPLATES = ("intro", "practice", "review", "listening", "reading", "mastery")


class NewLessonDialog(QDialog):
    def __init__(self, parent=None) -> None:
        super().__init__(parent)
        self.setWindowTitle("新建 Lesson")
        form = QFormLayout(self)
        self.name_edit = QLineEdit()
        self.name_edit.setPlaceholderText("New intro lesson")
        form.addRow("名称:", self.name_edit)
        self.template_combo = QComboBox()
        for t in NEW_TEMPLATES:
            self.template_combo.addItem(f"{TEMPLATE_LABELS.get(t, t)} ({t})", t)
        form.addRow("课型:", self.template_combo)
        buttons = QDialogButtonBox(
            QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel
        )
        buttons.accepted.connect(self.accept)
        buttons.rejected.connect(self.reject)
        form.addRow(buttons)

    def template(self) -> str:
        return self.template_combo.currentData()

    def lesson_name(self) -> str:
        return self.name_edit.text().strip()