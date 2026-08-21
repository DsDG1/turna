"""Dialog that picks where a workshop draft is imported.

Three modes:
- ``new_section``: append as a brand-new section (the historical behavior,
  routed through the shared section-import pipeline).
- ``into_section``: split the draft's units out and append them as new units
  inside an existing section (fresh ids avoid collisions).
- ``into_unit``: split the draft's lessons out and append them as new lessons
  inside an existing unit (fresh ids avoid collisions).
"""
from __future__ import annotations

from dataclasses import dataclass

from PySide6.QtWidgets import (
    QComboBox,
    QDialog,
    QDialogButtonBox,
    QLabel,
    QRadioButton,
    QVBoxLayout,
    QWidget,
)


@dataclass
class ImportTarget:
    """Where to import a workshop draft."""

    mode: str  # "new_section" | "into_section" | "into_unit"
    section_id: str | None = None
    unit_id: str | None = None


class ImportTargetDialog(QDialog):
    """Pick the import target for a workshop draft section."""

    def __init__(self, adapter, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.adapter = adapter
        self.setWindowTitle("导入到课程")
        self.resize(440, 260)
        self._build_ui()

    def _build_ui(self) -> None:
        layout = QVBoxLayout(self)
        layout.setSpacing(10)

        layout.addWidget(QLabel("选择导入目标："))
        self._new_section_radio = QRadioButton("作为新 Section 导入（默认）")
        self._into_section_radio = QRadioButton("导入到已有 Section，作为新 Unit 追加")
        self._into_unit_radio = QRadioButton("导入到已有 Unit，作为新 Lesson 追加")
        self._new_section_radio.setChecked(True)
        layout.addWidget(self._new_section_radio)
        layout.addWidget(self._into_section_radio)
        layout.addWidget(self._into_unit_radio)

        self._section_label = QLabel("目标 Section：")
        self._section_combo = QComboBox()
        for s in self.adapter.sections:
            self._section_combo.addItem(
                f"{s.get('name', '')} ({s.get('id', '')})", s.get("id", "")
            )
        layout.addWidget(self._section_label)
        layout.addWidget(self._section_combo)

        self._unit_label = QLabel("目标 Unit：")
        self._unit_combo = QComboBox()
        self._refresh_unit_combo()
        layout.addWidget(self._unit_label)
        layout.addWidget(self._unit_combo)

        self._section_combo.currentIndexChanged.connect(self._refresh_unit_combo)
        self._into_section_radio.toggled.connect(self._update_visibility)
        self._into_unit_radio.toggled.connect(self._update_visibility)
        self._new_section_radio.toggled.connect(self._update_visibility)
        self._update_visibility()

        buttons = QDialogButtonBox(
            QDialogButtonBox.StandardButton.Ok
            | QDialogButtonBox.StandardButton.Cancel
        )
        buttons.button(QDialogButtonBox.StandardButton.Ok).setText("导入")
        buttons.button(QDialogButtonBox.StandardButton.Cancel).setText("取消")
        buttons.accepted.connect(self.accept)
        buttons.rejected.connect(self.reject)
        layout.addWidget(buttons)

    def _refresh_unit_combo(self, *_args) -> None:
        sid = self._section_combo.currentData()
        self._unit_combo.clear()
        for section in self.adapter.sections:
            if section.get("id") == sid:
                for u in section.get("units", []):
                    self._unit_combo.addItem(
                        f"{u.get('name', '')} ({u.get('id', '')})", u.get("id", "")
                    )
                break

    def _update_visibility(self, *_args) -> None:
        into_section = self._into_section_radio.isChecked()
        into_unit = self._into_unit_radio.isChecked()
        show_section = into_section or into_unit
        self._section_label.setVisible(show_section)
        self._section_combo.setVisible(show_section)
        self._unit_label.setVisible(into_unit)
        self._unit_combo.setVisible(into_unit)

    def select(self) -> ImportTarget | None:
        """Exec the dialog and return the chosen target, or None if cancelled."""
        if self.exec() != QDialog.DialogCode.Accepted:
            return None
        if self._into_section_radio.isChecked():
            return ImportTarget(
                "into_section", section_id=self._section_combo.currentData()
            )
        if self._into_unit_radio.isChecked():
            return ImportTarget("into_unit", unit_id=self._unit_combo.currentData())
        return ImportTarget("new_section")
