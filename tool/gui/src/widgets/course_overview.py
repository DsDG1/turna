"""Course structure overview window.

A non-modal bird's-eye view of the whole course: Section -> Unit -> Lesson
chips (with template badges) plus a multi-row stats bar, search/filter, and
Markdown export. Clicking a lesson chip emits ``lesson_selected`` so the main
window can locate it in the tree. Clicking the validation badge emits
``validation_requested`` with the combined problem list.

Stats computation lives in :mod:`src.backend.overview_stats` (pure functions,
no Qt). This module is rendering-only.

Geometry is persisted to QSettings.
"""
from __future__ import annotations

from typing import Any

from PySide6.QtCore import Qt, QSettings, Signal
from PySide6.QtGui import QGuiApplication
from PySide6.QtWidgets import (
    QFrame,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QPushButton,
    QScrollArea,
    QVBoxLayout,
    QWidget,
)

from src.backend.course_adapter import CourseAdapter
from src.backend.lesson_content import (
    TEMPLATE_COLORS,
    TEMPLATE_COLOR_DEFAULT,
    TEMPLATE_LABELS,
)
from src.backend.overview_stats import (
    OverviewStats,
    compute_overview_stats,
    export_markdown,
    filter_lessons,
    format_interaction_line,
    format_stats_line,
    lesson_is_empty,
)
from src.theme import current_palette

#: Cache of chip stylesheets keyed by template + empty flag. Rebuilt lazily
#: on first use, then reused across every refresh (palette switches trigger
#: a full window rebuild via refresh()).
_CHIP_STYLE_CACHE: dict[tuple[str, bool], str] = {}


def _pal(key: str) -> str:
    return current_palette().get(key, "#1F232C")


def _chip_style(template: str, empty: bool) -> str:
    """Return a cached stylesheet for a lesson chip of ``template``."""
    key = (template, empty)
    cached = _CHIP_STYLE_CACHE.get(key)
    if cached is not None:
        return cached
    color = TEMPLATE_COLORS.get(template, TEMPLATE_COLOR_DEFAULT) if not empty else _pal("border")
    border_left = f"4px solid {color}"
    bg = _pal("bg_secondary")
    bg_hover = _pal("bg")
    text = _pal("text")
    style = (
        f"_LessonChip {{ text-align: left; padding: 6px 10px; "
        f"border: 1px solid {_pal('border')}; border-left: {border_left}; "
        f"border-radius: 6px; background-color: {bg}; color: {text}; }}"
        f"_LessonChip:hover {{ background-color: {bg_hover}; }}"
    )
    _CHIP_STYLE_CACHE[key] = style
    return style


def _clear_chip_style_cache() -> None:
    """Drop cached stylesheets (used by tests after a palette switch)."""
    _CHIP_STYLE_CACHE.clear()


class _LessonChip(QPushButton):
    """A lesson chip: name + colored template badge."""

    def __init__(self, lesson: dict[str, Any], on_click) -> None:
        tmpl = lesson.get("template", "legacy")
        label = TEMPLATE_LABELS.get(tmpl, tmpl)
        empty = lesson_is_empty(lesson)
        name = lesson.get("name", lesson.get("id", ""))
        text = f"{name}   ·   {label}"
        if empty:
            text += "  （空）"
        super().__init__(text)
        tip_lines = [
            str(name),
            f"课型：{label}",
            f"ID：{lesson.get('id', '')}",
        ]
        if empty:
            tip_lines.append("（该课时尚无内容）")
        self.setToolTip("\n".join(tip_lines))
        self.setCursor(Qt.CursorShape.PointingHandCursor)
        self.setStyleSheet(_chip_style(tmpl, empty))
        self.clicked.connect(lambda: on_click(lesson.get("id", "")))


class CourseOverviewWindow(QWidget):
    """Non-modal course structure overview with search, filter, and export."""

    _GEO_KEY = "course_overview/geometry"
    _MAX_KEY = "course_overview/maximized"

    lesson_selected = Signal(str)
    validation_requested = Signal(list)  # list[dict[str, Any]]

    def __init__(self, adapter: CourseAdapter, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.setWindowTitle("课程结构总览")
        self.setWindowFlag(Qt.WindowType.Window, True)
        self.resize(860, 640)
        self.setMinimumSize(520, 400)
        self.adapter = adapter

        self._stats: OverviewStats | None = None
        self._template_filter: str | None = None

        root = QVBoxLayout(self)
        root.setContentsMargins(14, 12, 14, 12)
        root.setSpacing(10)

        # --- Toolbar: stats + actions -----------------------------------
        self._stats_label = QLabel()
        self._stats_label.setTextFormat(Qt.TextFormat.RichText)
        self._stats_label.setStyleSheet(
            f"font-weight: 600; color: {_pal('text')}; padding: 4px 0;"
        )
        self._stats_label.setWordWrap(True)
        self._stats_label.setTextInteractionFlags(
            Qt.TextInteractionFlag.TextSelectableByMouse
        )
        # Clickable validation badge.
        self._stats_label.linkActivated.connect(self._on_stats_link)
        root.addWidget(self._stats_label)

        action_row = QHBoxLayout()
        action_row.setSpacing(6)
        self._search = QLineEdit()
        self._search.setPlaceholderText("按名称 / ID 过滤课时…")
        self._search.setClearButtonEnabled(True)
        self._search.textChanged.connect(self._on_filter_changed)
        action_row.addWidget(self._search, 1)
        self._export_btn = QPushButton("导出 Markdown")
        self._export_btn.setToolTip("把当前可见结构导出为 Markdown（复制到剪贴板）")
        self._export_btn.clicked.connect(self._on_export)
        action_row.addWidget(self._export_btn)
        root.addLayout(action_row)

        # --- Template filter chip row -----------------------------------
        self._filter_row = QWidget()
        self._filter_layout = QHBoxLayout(self._filter_row)
        self._filter_layout.setContentsMargins(0, 0, 0, 0)
        self._filter_layout.setSpacing(6)
        self._filter_layout.addWidget(QLabel("课型过滤:"))
        self._template_buttons: dict[str, QPushButton] = {}
        for tmpl, label in TEMPLATE_LABELS.items():
            btn = QPushButton(label)
            btn.setCheckable(True)
            btn.setCursor(Qt.CursorShape.PointingHandCursor)
            color = TEMPLATE_COLORS.get(tmpl, TEMPLATE_COLOR_DEFAULT)
            btn.setStyleSheet(
                f"QPushButton {{ padding: 2px 8px; border: 1px solid {color}; "
                f"border-radius: 4px; color: {color}; background: transparent; }}"
                f"QPushButton:checked {{ background: {color}; color: white; }}"
            )
            btn.clicked.connect(lambda _checked=False, t=tmpl: self._on_template_toggle(t))
            self._template_buttons[tmpl] = btn
            self._filter_layout.addWidget(btn)
        self._clear_filter_btn = QPushButton("清除")
        self._clear_filter_btn.clicked.connect(self._on_clear_filter)
        self._filter_layout.addWidget(self._clear_filter_btn)
        self._filter_layout.addStretch()
        root.addWidget(self._filter_row)

        # --- Scroll area ------------------------------------------------
        self._scroll = QScrollArea()
        self._scroll.setWidgetResizable(True)
        root.addWidget(self._scroll, 1)

        # Persistent host widget: refresh() clears and refills its layout
        # instead of allocating a new QWidget every time.
        self._host = QWidget()
        self._host_layout = QVBoxLayout(self._host)
        self._host_layout.setContentsMargins(4, 4, 4, 4)
        self._host_layout.setSpacing(12)
        self._scroll.setWidget(self._host)

        self._load_geometry()
        self.refresh()

    # --- rendering ------------------------------------------------------

    def refresh(self) -> None:
        """Rebuild the overview from the adapter."""
        # New stats (skip validation if it would block the UI; it's recomputed
        # lazily on demand via the validation link).
        self._stats = compute_overview_stats(self.adapter, include_validation=False)
        # If validation was already known from a previous refresh, keep its
        # counts so the badge doesn't flicker off/on.
        self._render()

    def refresh_with_validation(self) -> None:
        """Rebuild including validation counts (slower; spawns CLI)."""
        self._stats = compute_overview_stats(self.adapter, include_validation=True)
        self._render()

    def _render(self) -> None:
        if self._stats is None:
            self._stats = compute_overview_stats(self.adapter, include_validation=False)

        _clear_chip_style_cache()

        layout = self._host_layout
        while layout.count():
            child = layout.takeAt(0)
            widget = child.widget()
            if widget is not None:
                widget.setParent(None)
                widget.deleteLater()

        needle = self._search.text() if hasattr(self, "_search") else ""
        matches = filter_lessons(
            self.adapter.sections,
            text=needle,
            template=self._template_filter,
        )
        # Build a set of (section_id, lesson_id) for quick visibility lookup.
        visible: set[tuple[str, str]] = {
            (str(s.get("id", "")), str(l.get("id", ""))) for s, _u, l in matches
        }

        for section in self.adapter.sections:
            sid = str(section.get("id", ""))
            if not any((sid, str(l.get("id", ""))) in visible for _s, _u, l in
                       filter_lessons([section], text=needle, template=self._template_filter)):
                continue
            section_card = self._render_section(section, visible, sid)
            layout.addWidget(section_card)
            layout.addSpacing(2)

        if not matches:
            empty_msg = QLabel("（无匹配课时）")
            empty_msg.setStyleSheet(f"color: {_pal('text_secondary')}; padding: 20px;")
            empty_msg.setAlignment(Qt.AlignmentFlag.AlignCenter)
            layout.addWidget(empty_msg)

        layout.addStretch()
        self._update_stats_label()
        self._update_filter_state()

    def _render_section(
        self, section: dict[str, Any], visible: set[tuple[str, str]], sid: str
    ) -> QFrame:
        assert self._stats is not None
        sec_stat = next(
            (s for s in self._stats.sections if s.section_id == sid), None
        )

        card = QFrame()
        card.setFrameShape(QFrame.Shape.StyledPanel)
        card.setStyleSheet(
            f"QFrame {{ background-color: {_pal('bg_secondary')}; "
            f"border: 1px solid {_pal('border')}; border-radius: 10px; }}"
        )
        v = QVBoxLayout(card)
        v.setContentsMargins(14, 10, 14, 10)
        v.setSpacing(8)

        # Header: title + meta + interaction composition.
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
        meta_parts = [f"{n_units} units · {n_lessons} lessons"]
        if sec_stat and sec_stat.empty_lesson_count:
            meta_parts.append(f"空 {sec_stat.empty_lesson_count}")
        if sec_stat and sec_stat.quality_mean is not None:
            # U2-2: advisory quality lamp on section cards.
            badge = sec_stat.quality_badge or "ok"
            meta_parts.append(f"质量 {sec_stat.quality_mean:.2f}({badge})")
        meta = QLabel(" · ".join(meta_parts))
        q_color = _pal("text_secondary")
        if sec_stat and sec_stat.quality_badge == "error":
            q_color = current_palette().get("error", "#dc2626")
        elif sec_stat and sec_stat.quality_badge == "warning":
            q_color = current_palette().get("warning", "#d97706")
        meta.setStyleSheet(f"color: {q_color};")
        meta.setToolTip(
            "内容质量为建议性规则分，不阻断保存；低分可在工坊/校验处 AI 定向修。"
            if sec_stat and sec_stat.quality_mean is not None
            else ""
        )
        header.addWidget(meta)
        v.addLayout(header)

        # Interaction composition line.
        if sec_stat and sec_stat.interaction_counts:
            comp = QLabel(format_interaction_line(sec_stat.interaction_counts))
            comp.setStyleSheet(
                f"font-size: 11px; color: {_pal('text_secondary')};"
            )
            comp.setWordWrap(True)
            v.addWidget(comp)

        # Unit rows with lesson chips.
        for unit in section.get("units", []):
            unit_lessons = [
                l for l in unit.get("lessons", []) or []
                if (sid, str(l.get("id", ""))) in visible
            ]
            if not unit_lessons:
                continue
            v.addWidget(self._render_unit(unit, unit_lessons))
        return card

    def _render_unit(self, unit: dict[str, Any], lessons: list[dict[str, Any]]) -> QWidget:
        row = QWidget()
        col = QVBoxLayout(row)
        col.setContentsMargins(8, 4, 8, 4)
        col.setSpacing(6)

        unit_label = QLabel(f"  {unit.get('name', unit.get('id', ''))}")
        unit_label.setStyleSheet(f"font-weight: 600; color: {_pal('text_secondary')};")
        col.addWidget(unit_label)

        chips = QHBoxLayout()
        chips.setSpacing(6)
        for lesson in lessons:
            chip = _LessonChip(lesson, self.lesson_selected.emit)
            chips.addWidget(chip)
        chips.addStretch()
        col.addLayout(chips)
        return row

    # --- stats label ----------------------------------------------------

    def _update_stats_label(self) -> None:
        assert self._stats is not None
        text = format_stats_line(self._stats).replace("\n", "<br>")
        # Make the validation segment clickable if present.
        if self._stats.validation_errors or self._stats.validation_warnings:
            href = (
                f'<a href="#validation" style="color:{_pal("warning")};">'
                f"校验: {self._stats.validation_errors} 错 / "
                f"{self._stats.validation_warnings} 警"
                f"</a>"
            )
            # Replace the plain-text validation segment with the link.
            plain = (
                f"校验: {self._stats.validation_errors} 错 / "
                f"{self._stats.validation_warnings} 警"
            )
            text = text.replace(plain, href)
        # If no validation yet, show a "刷新校验" link.
        if "校验" not in text:
            href = f'<a href="#validate" style="color:{_pal("text_secondary")};">刷新校验</a>'
            text += f"<br>{href}"
        self._stats_label.setText(text)

    def _on_stats_link(self, link: str) -> None:
        if link == "#validation":
            # Already have validation data; emit it.
            self._emit_validation()
        elif link == "#validate":
            # Compute validation now, then emit.
            self.refresh_with_validation()
            self._emit_validation()

    def _emit_validation(self) -> None:
        """Collect problems from the CLI and emit validation_requested."""
        if self.adapter.course_dir is None:
            return
        try:
            from src.backend import api

            result = api.validate_course_dir(self.adapter.course_dir)
            problems = [p.to_dict() for p in result.problems]
            problems.extend(
                p.to_dict() for p in api.lint_course_dir(self.adapter.course_dir)
            )
        except Exception:
            problems = []
        self.validation_requested.emit(problems)

    # --- filter / search -----------------------------------------------

    def _on_filter_changed(self, _text: str) -> None:
        self._render()

    def _on_template_toggle(self, tmpl: str) -> None:
        # Exclusive toggle: clicking the active filter clears it.
        if self._template_filter == tmpl:
            self._template_filter = None
            self._template_buttons[tmpl].setChecked(False)
        else:
            if self._template_filter is not None:
                prev = self._template_buttons.get(self._template_filter)
                if prev is not None:
                    prev.setChecked(False)
            self._template_filter = tmpl
            self._template_buttons[tmpl].setChecked(True)
        self._render()

    def _on_clear_filter(self) -> None:
        self._search.clear()
        if self._template_filter is not None:
            btn = self._template_buttons.get(self._template_filter)
            if btn is not None:
                btn.setChecked(False)
            self._template_filter = None
        self._render()

    def _update_filter_state(self) -> None:
        """Hide template filter buttons for templates that don't exist."""
        if self._stats is None:
            return
        present = set(self._stats.template_counts.keys())
        for tmpl, btn in self._template_buttons.items():
            btn.setVisible(tmpl in present)

    # --- export ---------------------------------------------------------

    def _on_export(self) -> None:
        if self._stats is None:
            return
        md = export_markdown(
            self._stats,
            self.adapter.sections,
            text=self._search.text(),
            template=self._template_filter,
        )
        clipboard = QGuiApplication.clipboard()
        if clipboard is not None:
            clipboard.setText(md)
        self._export_btn.setText("已复制 ✓")
        # Revert the label after 1.5s.
        from PySide6.QtCore import QTimer

        QTimer.singleShot(1500, lambda: self._export_btn.setText("导出 Markdown"))

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
