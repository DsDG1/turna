"""Independent teacher-mode window (guiplan2 usability).

Clicking "教师模式" now proactively pops up this window instead of only
surfacing the teacher UI inline when a lesson happens to be selected. The
window hosts a lesson picker (QComboBox of all lessons) plus the same
teacher widget built by ``detail_panel.build_teacher_widget``, wrapped in a
QScrollArea. Edits flow back through ``widget.changed`` → a callback the
main window wires to its tree-refresh path.

Geometry is persisted to QSettings (mirrors the ``ChatExpandWindow`` pattern
in ``dialogs/ai/chat_expand_window.py``). Non-modal ``.show()``.
"""
from __future__ import annotations

import time
from typing import Any, Callable

from PySide6.QtCore import Qt, QSettings
from PySide6.QtGui import QUndoStack
from PySide6.QtWidgets import (
    QComboBox,
    QDialog,
    QHBoxLayout,
    QLabel,
    QScrollArea,
    QVBoxLayout,
    QWidget,
)

from src.backend.ai_generator import AiApiConfig
from src.backend.course_adapter import CourseAdapter
from src.widgets.detail_panel import build_teacher_widget


class TeacherWindow(QDialog):
    """Independent, non-modal window for the teacher lesson editor."""

    _GEO_KEY = "teacher_window/geometry"
    _MAX_KEY = "teacher_window/maximized"

    def __init__(
        self,
        adapter: CourseAdapter,
        undo_stack: QUndoStack | None,
        ai_config: AiApiConfig | None,
        on_changed: Callable[[], None],
        parent: QWidget | None = None,
    ) -> None:
        super().__init__(parent)
        self.setWindowTitle("教师模式 · 课程编辑")
        self.setWindowFlag(Qt.WindowType.Window, True)
        self.resize(1000, 760)
        self.setMinimumSize(640, 480)

        self.adapter = adapter
        self.undo_stack = undo_stack
        self.ai_config = ai_config
        self._on_changed = on_changed
        self._current_widget: QWidget | None = None
        self._usage_t0 = time.perf_counter()

        root = QVBoxLayout(self)
        root.setContentsMargins(12, 12, 12, 12)
        root.setSpacing(8)

        picker_row = QHBoxLayout()
        picker_row.setSpacing(8)
        picker_row.addWidget(QLabel("选择课时:"))
        self.lesson_combo = QComboBox()
        self.lesson_combo.setMinimumWidth(360)
        self.lesson_combo.currentIndexChanged.connect(self._on_combo_changed)
        picker_row.addWidget(self.lesson_combo, 1)
        root.addLayout(picker_row)

        self._placeholder = QLabel("请选择一节课")
        self._placeholder.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self._placeholder.setStyleSheet("color: #9CA3AF; font-size: 14px;")

        self._scroll = QScrollArea()
        self._scroll.setWidgetResizable(True)
        root.addWidget(self._scroll, 1)

        self._populate_combo()
        self._load_geometry()

    # --- combo / lessons ------------------------------------------------

    def _all_lessons(self) -> list[tuple[dict[str, Any], dict[str, Any], dict[str, Any]]]:
        """Return (section, unit, lesson) triples for every lesson, in tree order."""
        out: list[tuple[dict[str, Any], dict[str, Any], dict[str, Any]]] = []
        for section in self.adapter.sections:
            for unit in section.get("units", []):
                for lesson in unit.get("lessons", []):
                    out.append((section, unit, lesson))
        return out

    def _populate_combo(self) -> None:
        self.lesson_combo.blockSignals(True)
        self.lesson_combo.clear()
        for section, unit, lesson in self._all_lessons():
            label = (
                f"{section.get('name', section.get('id', ''))} / "
                f"{unit.get('name', unit.get('id', ''))} / "
                f"{lesson.get('name', lesson.get('id', ''))}"
            )
            self.lesson_combo.addItem(label, lesson.get("id", ""))
        self.lesson_combo.blockSignals(False)
        if self.lesson_combo.count() > 0:
            self._show_placeholder(False)
            self._rebuild_current()
        else:
            self._show_placeholder(True)

    def _show_placeholder(self, show: bool) -> None:
        if show:
            self._scroll.setWidget(self._placeholder)
        else:
            if self._scroll.widget() is self._placeholder:
                self._scroll.takeWidget()

    def _on_combo_changed(self, _index: int) -> None:
        self._rebuild_current()

    def _rebuild_current(self) -> None:
        lid = self.lesson_combo.currentData()
        if not lid:
            self._show_placeholder(True)
            return
        try:
            section, unit, lesson = self.adapter.find_lesson(lid)
        except KeyError:
            self._show_placeholder(True)
            return
        # Dispose the previous teacher widget before building a new one.
        prev = self._current_widget
        self._current_widget = None
        if prev is not None:
            prev.setParent(None)
            prev.deleteLater()
        widget = build_teacher_widget(
            self.adapter, section, unit, lesson, self, self.undo_stack, self.ai_config
        )
        widget.changed.connect(self._on_changed)
        self._current_widget = widget
        self._show_placeholder(False)
        self._scroll.setWidget(widget)

    # --- selection helpers ----------------------------------------------

    def show_lesson(self, lesson_id: str) -> None:
        """Switch the picker to ``lesson_id`` and rebuild; no-op if absent."""
        for i in range(self.lesson_combo.count()):
            if self.lesson_combo.itemData(i) == lesson_id:
                if self.lesson_combo.currentIndex() != i:
                    self.lesson_combo.setCurrentIndex(i)
                else:
                    self._rebuild_current()
                return
        # Not found (e.g. stale id) — refresh combo then retry once.
        self._populate_combo()
        for i in range(self.lesson_combo.count()):
            if self.lesson_combo.itemData(i) == lesson_id:
                self.lesson_combo.setCurrentIndex(i)
                return

    def refresh_lesson_list(self) -> None:
        """Rebuild the combo after a structural change, preserving selection."""
        current = self.lesson_combo.currentData()
        self._populate_combo()
        if current is not None:
            self.show_lesson(current)

    # --- geometry persistence -------------------------------------------

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
        self._record_window_duration()
        super().closeEvent(event)

    def _record_window_duration(self) -> None:
        try:
            import time

            from src.infrastructure.operations_log import operations

            start = getattr(self, "_usage_t0", None) or time.perf_counter()
            name = self.windowTitle() or type(self).__name__
            operations.record_duration(
                "window.duration",
                (time.perf_counter() - start) * 1000.0,
                payload={"window": name},
            )
            operations.record_action("window.close", name)
        except Exception:
            pass