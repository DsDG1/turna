"""Preview, validation, diff and floating JSON window coordination for AI dialog.

Decoupled from AiGeneratorDialog.
"""
from __future__ import annotations

import json
import logging
from typing import Any

from PySide6.QtCore import QObject
from PySide6.QtGui import QTextCursor
from PySide6.QtWidgets import (
    QInputDialog,
    QMessageBox,
    QPushButton,
    QWidget,
)

from src.dialogs.ai.result_window import ResultExpandWindow

logger = logging.getLogger(__name__)


def find_line_for_path(text: str, path: str) -> int | None:
    """Return the 1-based line whose content contains the id in an
    ``id:<id>`` path payload. Returns None for structural-only paths.
    """
    if not path.startswith("id:"):
        return None
    target = f'"{path[3:]}"'
    idx = text.find(target)
    if idx < 0:
        return None
    return text.count("\n", 0, idx) + 1


def jump_editor_to_path(editor: Any, path: str) -> None:
    """Jump the JSON editor to the line matching the path."""
    text = editor.toPlainText()
    if not text or not path:
        return
    line_no = find_line_for_path(text, path)
    if line_no is None:
        return
    cursor = editor.textCursor()
    cursor.movePosition(QTextCursor.MoveOperation.Start)
    for _ in range(line_no - 1):
        cursor.movePosition(QTextCursor.MoveOperation.Down)
    editor.setTextCursor(cursor)
    editor.setFocus()


def confirm_structural_removal(parent: QWidget, diff: dict[str, set[str]]) -> bool:
    """Ask the teacher to accept AI-removed units/lessons/words (B3)."""
    parts: list[str] = []
    labels = [
        ("removed_units", "单元"),
        ("removed_lessons", "课时"),
        ("removed_words", "词汇"),
        ("removed_expressions", "表达"),
        ("removed_grammar", "语法点"),
    ]
    for key, label in labels:
        ids = diff.get(key) or set()
        if ids:
            preview = ", ".join(sorted(ids)[:8])
            more = f" 等 {len(ids)} 个" if len(ids) > 8 else ""
            parts.append(f"{label}：{preview}{more}")
    if not parts:
        return True
    msg = (
        "AI 在编辑中删除了以下内容（结构保护）。\n"
        "若只想改一两题，请改用教师模式「AI 改这题」或工坊局部重生成。\n\n"
        + "\n".join(parts)
        + "\n\n是否仍接受这些删除？"
    )
    btn = QMessageBox.question(
        parent,
        "AI 删除了内容",
        msg,
        QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
        QMessageBox.StandardButton.No,
    )
    return btn == QMessageBox.StandardButton.Yes


def try_preview_lesson(parent: QWidget, adapter: Any, section: dict[str, Any]) -> None:
    """Pick a lesson from the current section and open the preview dialog."""
    from src.teacher.preview_window import LessonPreviewDialog

    lessons: list[tuple[str, dict]] = []
    for unit in section.get("units") or []:
        if not isinstance(unit, dict):
            continue
        for lesson in unit.get("lessons") or []:
            if isinstance(lesson, dict) and lesson.get("id"):
                label = f"{unit.get('name', unit.get('id', '?'))} › {lesson.get('name', lesson['id'])}"
                lessons.append((label, lesson))
    if not lessons:
        QMessageBox.information(parent, "无可试做课时", "当前课程没有课时可试做。")
        return
    if len(lessons) == 1:
        lesson = lessons[0][1]
    else:
        items = [lbl for lbl, _ in lessons]
        choice, ok = QInputDialog.getItem(
            parent, "选择课时试做", "课时：", items, 0, False
        )
        if not ok:
            return
        lesson = next(l for lbl, l in lessons if lbl == choice)
    vocab_override = {w.get("id"): w for w in (section.get("words") or []) if isinstance(w, dict) and w.get("id")}
    LessonPreviewDialog(adapter, lesson, parent, vocab_override=vocab_override).exec()


def view_section_diff(parent: QWidget, existing_section: dict[str, Any], generated: dict[str, Any]) -> None:
    """Show structural diff between existing section and generated JSON."""
    from src.widgets.diff_view import SectionDiffView
    SectionDiffView(existing_section, generated, parent).exec()


class GeneratorPreviewCoordinator(QObject):
    """Manages independent JSON floating window and preview reparenting."""

    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self._json_window: ResultExpandWindow | None = None
        self._parent_widget: QWidget | None = parent

    @property
    def json_window(self) -> ResultExpandWindow | None:
        return self._json_window

    @json_window.setter
    def json_window(self, win: ResultExpandWindow | None) -> None:
        self._json_window = win

    def on_json_window_toggled(
        self,
        checked: bool,
        active_editor: Any,
        active_host: Any,
        toggle_btns: list[QPushButton],
        on_closed_callback: Any,
    ) -> None:
        for btn in toggle_btns:
            btn.blockSignals(True)
            btn.setChecked(checked)
            btn.blockSignals(False)

        if checked:
            if self._json_window is None:
                self._json_window = ResultExpandWindow(self._parent_widget)
                self._json_window.finished.connect(on_closed_callback)
            self._json_window.host_editor(active_editor)
            active_editor.setVisible(True)
            self._json_window.show()
            self._json_window.raise_()
            self._json_window.activateWindow()
        else:
            self.close_json_window(active_host)

    def return_json_editor_to_host(self, host_layout: Any) -> None:
        win = self._json_window
        if win is None:
            return
        editor = win.release_editor()
        if editor is not None:
            host_layout.addWidget(editor)
            editor.setVisible(True)

    def close_json_window(self, host_layout: Any) -> None:
        win = self._json_window
        if win is not None:
            self.return_json_editor_to_host(host_layout)
            win.close()
            self._json_window = None
