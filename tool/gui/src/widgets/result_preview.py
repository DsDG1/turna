"""Result preview widget for the AI course generator.

Shows a human-readable overview of a generated section (name/id, unit count,
lesson count, top-level resource counts) plus a one-click validation panel
that reuses ``CourseAdapter.validate_section_json`` and renders problems as
color-coded chips. Validation failures are surfaced via the ``validity_changed``
signal so the host dialog can enable/disable the import button.
"""
from __future__ import annotations

from typing import Any

from PySide6.QtCore import Qt, Signal
from PySide6.QtWidgets import (
    QFrame,
    QHBoxLayout,
    QLabel,
    QPushButton,
    QVBoxLayout,
    QWidget,
)


class _StatCard(QFrame):
    """A small peacock-styled stat tile (label + value)."""

    def __init__(self, label: str, value: str, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.setObjectName("statCard")
        self.setStyleSheet(
            "QFrame#statCard {"
            "  background-color: #1F232C;"
            "  border: 1px solid #2C313C;"
            "  border-radius: 8px;"
            "}"
        )
        layout = QVBoxLayout(self)
        layout.setContentsMargins(10, 8, 10, 8)
        layout.setSpacing(2)
        value_label = QLabel(value)
        value_label.setStyleSheet("color: #46D1BF; font-size: 16px; font-weight: 600; border: none;")
        value_label.setProperty("role", "value")
        layout.addWidget(value_label)
        caption = QLabel(label)
        caption.setStyleSheet("color: #9CA3AF; font-size: 11px; border: none;")
        layout.addWidget(caption)
        self._value_label = value_label

    def set_value(self, value: str) -> None:
        self._value_label.setText(value)


def _count_lessons(section: dict[str, Any]) -> int:
    total = 0
    for unit in section.get("units") or []:
        if not isinstance(unit, dict):
            continue
        for lesson in unit.get("lessons") or []:
            if isinstance(lesson, dict):
                total += 1
    return total


def _section_resource_counts(section: dict[str, Any]) -> dict[str, int]:
    """Count top-level resource entries declared on the section itself."""
    return {
        "vocab": len(section.get("words") or []),
        "expressions": len(section.get("expressions") or []),
        "grammar_points": len(section.get("grammarPoints") or []),
    }


class ResultPreviewWidget(QWidget):
    """Overview cards + validation chips for a generated section.

    ``validity_changed`` emits True when the current section validates with no
    errors (warnings are allowed), False otherwise. The host uses this to
    enable/disable the import button.
    """

    validity_changed = Signal(bool)

    def __init__(self, adapter, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.adapter = adapter
        self._section: dict[str, Any] | None = None
        self._build_ui()

    def _build_ui(self) -> None:
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(8)

        cards_row = QHBoxLayout()
        cards_row.setSpacing(8)
        self.card_section = _StatCard("课程", "—")
        self.card_units = _StatCard("单元", "0")
        self.card_lessons = _StatCard("课时", "0")
        self.card_vocab = _StatCard("词条", "0")
        self.card_expressions = _StatCard("表达", "0")
        self.card_grammar = _StatCard("语法点", "0")
        for card in (
            self.card_section,
            self.card_units,
            self.card_lessons,
            self.card_vocab,
            self.card_expressions,
            self.card_grammar,
        ):
            cards_row.addWidget(card)
        cards_row.addStretch()
        layout.addLayout(cards_row)

        action_row = QHBoxLayout()
        action_row.setSpacing(8)
        self.validate_btn = QPushButton("一键校验")
        self.validate_btn.setToolTip("校验当前生成结果，错误会显示为红色标签")
        self.validate_btn.clicked.connect(self._on_validate)
        action_row.addWidget(self.validate_btn)
        self.status_label = QLabel("")
        self.status_label.setStyleSheet("color: #9CA3AF; font-size: 12px;")
        action_row.addWidget(self.status_label, 1)
        layout.addLayout(action_row)

        self.chip_row = QHBoxLayout()
        self.chip_row.setSpacing(6)
        self.chip_row.setContentsMargins(0, 0, 0, 0)
        self._chip_container = QWidget()
        self._chip_container.setLayout(self.chip_row)
        layout.addWidget(self._chip_container)

    def show_section(self, section: dict[str, Any]) -> None:
        """Update the overview cards for ``section`` (does not validate)."""
        self._section = section
        if not isinstance(section, dict):
            self._clear_cards()
            return
        name = str(section.get("name") or section.get("id") or "—")
        self.card_section.set_value(name if len(name) <= 14 else name[:13] + "…")
        self.card_section.setToolTip(name)
        units = section.get("units") or []
        self.card_units.set_value(str(len(units)))
        self.card_lessons.set_value(str(_count_lessons(section)))
        counts = _section_resource_counts(section)
        self.card_vocab.set_value(str(counts["vocab"]))
        self.card_expressions.set_value(str(counts["expressions"]))
        self.card_grammar.set_value(str(counts["grammar_points"]))
        self._clear_chips()
        self.status_label.setText("点击「一键校验」检查结果。")
        self.status_label.setStyleSheet("color: #9CA3AF; font-size: 12px;")

    def _clear_cards(self) -> None:
        for card in (
            self.card_section,
            self.card_units,
            self.card_lessons,
            self.card_vocab,
            self.card_expressions,
            self.card_grammar,
        ):
            card.set_value("0" if card is not self.card_section else "—")

    def _clear_chips(self) -> None:
        while self.chip_row.count():
            item = self.chip_row.takeAt(0)
            w = item.widget()
            if w is not None:
                w.setParent(None)
                w.deleteLater()

    def _add_chip(self, text: str, level: str) -> None:
        chip = QLabel(text)
        chip.setWordWrap(True)
        if level == "error":
            color = "#E74C3C"
            bg = "rgba(231, 76, 60, 0.12)"
        else:
            color = "#FF9F43"
            bg = "rgba(255, 159, 67, 0.12)"
        chip.setStyleSheet(
            f"color: {color}; background-color: {bg};"
            "border-radius: 6px; padding: 3px 8px; font-size: 12px;"
        )
        chip.setMaximumWidth(560)
        self.chip_row.addWidget(chip)

    def _on_validate(self) -> None:
        if self._section is None:
            return
        problems = self.adapter.validate_section_json(self._section)
        self._clear_chips()
        errors = [p for p in problems if p.get("level") == "error"]
        warnings = [p for p in problems if p.get("level") == "warning"]
        for p in problems:
            self._add_chip(p.get("message", ""), p.get("level", "error"))
        if not problems:
            self.status_label.setText("✓ 校验通过，可以导入。")
            self.status_label.setStyleSheet("color: #27AE60; font-size: 12px;")
            self.validity_changed.emit(True)
        elif not errors:
            self.status_label.setText(f"⚠ {len(warnings)} 条警告，仍可导入。")
            self.status_label.setStyleSheet("color: #FF9F43; font-size: 12px;")
            self.validity_changed.emit(True)
        else:
            self.status_label.setText(f"✗ {len(errors)} 个错误，请修改后再导入。")
            self.status_label.setStyleSheet("color: #E74C3C; font-size: 12px;")
            self.validity_changed.emit(False)

    def section(self) -> dict[str, Any] | None:
        return self._section