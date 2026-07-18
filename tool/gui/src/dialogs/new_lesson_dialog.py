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
from src.backend.lesson_presets import FUNCTIONAL_TEMPLATES

NEW_TEMPLATES = ("intro", "practice", "review", "listening", "reading", "mastery")


class NewLessonDialog(QDialog):
    def __init__(self, parent=None) -> None:
        super().__init__(parent)
        self.setWindowTitle("新建 Lesson")
        self.use_wizard = False
        form = QFormLayout(self)
        self.name_edit = QLineEdit()
        self.name_edit.setPlaceholderText("New intro lesson")
        form.addRow("名称:", self.name_edit)
        self.template_combo = QComboBox()
        for t in NEW_TEMPLATES:
            self.template_combo.addItem(f"{TEMPLATE_LABELS.get(t, t)} ({t})", t)
        self.template_combo.currentIndexChanged.connect(self._update_wizard_btn)
        form.addRow("课型:", self.template_combo)

        buttons = QDialogButtonBox()
        self._wizard_btn = buttons.addButton(
            "向导创建（功能课）", QDialogButtonBox.ButtonRole.ActionRole
        )
        self._wizard_btn.setToolTip(
            "对听力/阅读/综合测验课型，打开分步向导与可视化蓝图预览（推荐）"
        )
        self._wizard_btn.clicked.connect(self._choose_wizard)
        ok_btn = buttons.addButton(QDialogButtonBox.StandardButton.Ok)
        ok_btn.setToolTip("直接用课型骨架新建（可随后在蓝图中编辑）")
        cancel_btn = buttons.addButton(QDialogButtonBox.StandardButton.Cancel)
        ok_btn.clicked.connect(self.accept)
        cancel_btn.clicked.connect(self.reject)
        form.addRow(buttons)
        self._update_wizard_btn()

    def _choose_wizard(self) -> None:
        self.use_wizard = True
        self.accept()

    def _update_wizard_btn(self, *_args) -> None:
        self._wizard_btn.setEnabled(self.template() in FUNCTIONAL_TEMPLATES)

    def template(self) -> str:
        return self.template_combo.currentData()

    def lesson_name(self) -> str:
        return self.name_edit.text().strip()
