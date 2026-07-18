"""Course structure overview window (workshop2 P4).

A non-modal bird's-eye view of the whole course: Section -> Unit -> Lesson
chips (with template badges) plus a top stats bar. Clicking a lesson chip
emits ``lesson_selected`` so the main window can locate it in the tree.

Geometry is persisted to QSettings.
"""
from __future__ import annotations

from collections import Counter
from typing import Any

from PySide6.QtCore import Qt, QSettings, Signal
from PySide6.QtWidgets import (
    QFrame,
    QHBoxLayout,
    QLabel,
    QPushButton,
    QScrollArea,
    QVBoxLayout,
    QWidget,
)

from src.backend.course_adapter import CourseAdapter
from src.backend.lesson_content import TEMPLATE_LABELS
from src.theme import current_palette

#: Soft badge color per functional template; others share a neutral tone.
_TEMPLATE_COLORS: dict[str, str] = {
    "listening": "#3B82F6",
    "reading": "#10B981",
    "mastery": "#F59E0B",
    "intro": "#6366F1",
    "practice": "#8B5CF6",
    "review": "#EC4899",
    "legacy": "#6B7280",
}


def _pal(key: str) -> str:
    return current_palette().get(key, "#1F232C")


class _LessonChip(QPushButton):
    """A lesson chip: name + colored template badge."""

    def __init__(self, lesson: dict[str, Any], on_click) -> None:
        tmpl = lesson.get("template", "legacy")
        label = TEMPLATE_LABELS.get(tmpl, tmpl)
        super().__init__(f"{lesson.get('name', lesson.get('id', ''))}   ·   {label}")
        self.setToolTip(f"{lesson.get('name', '')}\n课型：{label}\nID：{lesson.get('id', '')}")
        self.setCursor(Qt.CursorShape.PointingHandCursor)
        color = _TEMPLATE_COLORS.get(tmpl, "#6B7280")
        self.setStyleSheet(
            f"_LessonChip {{ text-align: left; padding: 6px 10px; "
            f"border: 1px solid {_pal('border')}; border-left: 4px solid {color}; "
            f"border-radius: 6px; background-color: {_pal('bg_secondary')}; "
            f"color: {_pal('text')}; }}"
            f"_LessonChip:hover {{ background-color: {_pal('bg')}; }}"
        )
        self.clicked.connect(lambda: on_click(lesson.get("id", "")))


class CourseOverviewWindow(QWidget):
    """Non-modal course structure overview."""

    _GEO_KEY = "course_overview/geometry"
    _MAX_KEY = "course_overview/maximized"

    lesson_selected = Signal(str)

    def __init__(self, adapter: CourseAdapter, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.setWindowTitle("课程结构总览")
        self.setWindowFlag(Qt.WindowType.Window, True)
        self.resize(860, 640)
        self.setMinimumSize(520, 400)
        self.adapter = adapter

        root = QVBoxLayout(self)
        root.setContentsMargins(14, 12, 14, 12)
        root.setSpacing(10)

        self._stats_label = QLabel()
        self._stats_label.setStyleSheet(
            f"font-weight: 600; color: {_pal('text')}; padding: 4px 0;"
        )
        root.addWidget(self._stats_label)

        self._scroll = QScrollArea()
        self._scroll.setWidgetResizable(True)
        root.addWidget(self._scroll, 1)

        self._load_geometry()
        self.refresh()

    # --- rendering ------------------------------------------------------

    def refresh(self) -> None:
        """Rebuild the overview from the adapter."""
        host = QWidget()
        layout = QVBoxLayout(host)
        layout.setContentsMargins(4, 4, 4, 4)
        layout.setSpacing(12)

        sections = self.adapter.sections
        tmpl_counter: Counter[str] = Counter()
        unit_count = 0
        lesson_count = 0

        for section in sections:
            section_card = self._build_section_card(section, tmpl_counter)
            layout.addWidget(section_card)
            for unit in section.get("units", []):
                unit_count += 1
                lesson_count += len(unit.get("lessons", []))
            layout.addSpacing(2)

        layout.addStretch()
        self._scroll.setWidget(host)

        self._stats_label.setText(
            f"Sections: {len(sections)}   ·   Units: {unit_count}   ·   "
            f"Lessons: {lesson_count}     课型分布: "
            + "   ".join(
                f"{TEMPLATE_LABELS.get(t, t)} {n}"
                for t, n in tmpl_counter.most_common()
            )
            if lesson_count
            else f"Sections: {len(sections)}   ·   Units: {unit_count}   ·   Lessons: 0"
        )

    def _build_section_card(
        self, section: dict[str, Any], tmpl_counter: Counter[str]
    ) -> QFrame:
        card = QFrame()
        card.setFrameShape(QFrame.Shape.StyledPanel)
        card.setStyleSheet(
            f"QFrame {{ background-color: {_pal('bg_secondary')}; "
            f"border: 1px solid {_pal('border')}; border-radius: 10px; }}"
        )
        v = QVBoxLayout(card)
        v.setContentsMargins(14, 10, 14, 10)
        v.setSpacing(8)

        header = QHBoxLayout()
        title = QLabel(
            f"{section.get('name', section.get('id', ''))}   "
            f"({section.get('level', '')})"
        )
        title.setStyleSheet(f"font-weight: 700; font-size: 14px; color: {_pal('text')};")
        header.addWidget(title)
        header.addStretch()
        n_units = len(section.get("units", []))
        n_lessons = sum(len(u.get("lessons", [])) for u in section.get("units", []))
        meta = QLabel(f"{n_units} units · {n_lessons} lessons")
        meta.setStyleSheet(f"color: {_pal('text_secondary')};")
        header.addWidget(meta)
        v.addLayout(header)

        for unit in section.get("units", []):
            v.addWidget(self._build_unit_row(unit, tmpl_counter))
        return card

    def _build_unit_row(
        self, unit: dict[str, Any], tmpl_counter: Counter[str]
    ) -> QWidget:
        row = QWidget()
        h = QVBoxLayout(row)
        h.setContentsMargins(8, 4, 8, 4)
        h.setSpacing(6)

        unit_label = QLabel(f"  {unit.get('name', unit.get('id', ''))}")
        unit_label.setStyleSheet(
            f"font-weight: 600; color: {_pal('text_secondary')};"
        )
        h.addWidget(unit_label)

        chips = QHBoxLayout()
        chips.setSpacing(6)
        lessons = unit.get("lessons", [])
        if not lessons:
            empty = QLabel("（无课时）")
            empty.setStyleSheet(f"color: {_pal('text_secondary')};")
            chips.addWidget(empty)
        for lesson in lessons:
            tmpl_counter[lesson.get("template", "legacy")] += 1
            chip = _LessonChip(lesson, self.lesson_selected.emit)
            chips.addWidget(chip)
        chips.addStretch()
        h.addLayout(chips)
        return row

    # --- geometry -------------------------------------------------------

    def _load_geometry(self) -> None:
        qs = QSettings("Varnamala", "CourseEditor")
        geo = qs.value(self._GEO_KEY)
        if geo is not None:
            self.restoreGeometry(geo)
        if qs.value(self._MAX_KEY, False) in (True, "true", "1"):
            self.showMaximized()

    def _save_geometry(self) -> None:
        qs = QSettings("Varnamala", "CourseEditor")
        qs.setValue(self._GEO_KEY, self.saveGeometry())
        qs.setValue(self._MAX_KEY, self.isMaximized())

    def closeEvent(self, event) -> None:  # noqa: N802
        self._save_geometry()
        super().closeEvent(event)
