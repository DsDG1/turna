"""Reusable validation report panel (A2, guiplan §8 ValidationReport).

Renders CLI validate/lint problem lists as a clickable list. Double-clicking
an item with a resolvable node path emits ``jump_to`` so the MainWindow can
select + highlight the offending node in the tree. Reuses the pure
``error_mapper`` (originally a teacher-view helper) so expert and teacher
modes share the same path -> human message -> jump ref pipeline.

aiEnhance U1-2: multi-select + batch AI fix signal.
"""
from __future__ import annotations

from typing import Any

from PySide6.QtCore import Qt, Signal
from PySide6.QtGui import QColor
from PySide6.QtWidgets import (
    QAbstractItemView,
    QFrame,
    QHBoxLayout,
    QLabel,
    QListWidget,
    QListWidgetItem,
    QPushButton,
    QVBoxLayout,
    QWidget,
)

from src.backend.course_adapter import CourseAdapter
from src.teacher.error_mapper import humanize_problem, problem_to_node_ref
from src.theme import current_palette


class ValidationReportWidget(QWidget):
    """List of validate/lint problems with double-click-to-jump.

    ``jump_to`` carries a ``(kind, id)`` node ref, or is not emitted when the
    problem has no resolvable path (caller shows it in the global panel).

    ``ai_fix_requested`` is emitted when the user clicks the AI auto-fix button.
    It carries the currently selected problem dict and its node ref (or None).
    Kept for backward compatibility (single-item callers).

    ``ai_batch_fix_requested`` carries a list of ``(problem, node_ref)`` pairs
    for multi-select batch repair (U1-2).
    """

    jump_to = Signal(tuple)  # (kind, id)
    ai_fix_requested = Signal(object, object)  # problem, node_ref
    ai_batch_fix_requested = Signal(list)  # list[(problem, node_ref)]

    def __init__(self, adapter: CourseAdapter, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.adapter = adapter
        self._problems: list[dict[str, Any]] = []

        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(6)

        header = QHBoxLayout()
        self.title = QLabel("校验结果")
        pal = current_palette()
        self.title.setStyleSheet(f"font-weight: 700; color: {pal['error']};")
        header.addWidget(self.title)
        header.addStretch()
        self.ai_fix_btn = QPushButton("AI 自动修正")
        self.ai_fix_btn.setToolTip(
            "使用 AI 修正选中的校验问题（可多选：Ctrl/Shift；同节点合并一次修复）"
        )
        self.ai_fix_btn.setEnabled(False)
        self.ai_fix_btn.clicked.connect(self._on_ai_fix_clicked)
        header.addWidget(self.ai_fix_btn)
        layout.addLayout(header)

        self.list_widget = QListWidget()
        self.list_widget.setFrameShape(QFrame.Shape.NoFrame)
        self.list_widget.setSelectionMode(
            QAbstractItemView.SelectionMode.ExtendedSelection
        )
        self.list_widget.itemDoubleClicked.connect(self._on_item_double_clicked)
        self.list_widget.itemSelectionChanged.connect(self._on_selection_changed)
        layout.addWidget(self.list_widget)

        self._hint = QLabel(
            "双击跳转节点；可多选后点「AI 自动修正」（Ctrl/Shift 多选）"
        )
        self._hint.setStyleSheet(
            f"color: {current_palette()['text_secondary']}; font-size: 11px;"
        )
        layout.addWidget(self._hint)

    def show_problems(self, problems: list[dict[str, Any]]) -> None:
        """Render a list of problem dicts (keys: level, message, path)."""
        self._problems = list(problems)
        self.list_widget.clear()
        errors = [p for p in self._problems if p.get("level") == "error"]
        warnings = [p for p in self._problems if p.get("level") == "warning"]
        self.title.setText(
            f"校验结果：{len(errors)} 个错误，{len(warnings)} 个警告"
        )
        pal = current_palette()
        self.title.setStyleSheet(
            f"font-weight: 700; color: {pal['error']};" if errors
            else f"font-weight: 700; color: {pal['warning']};" if warnings
            else f"font-weight: 700; color: {pal['success']};"
        )
        for problem in self._problems:
            level = problem.get("level", "error")
            human = humanize_problem(problem)
            node_ref = problem_to_node_ref(problem, self.adapter.sections)
            tag = "❌" if level == "error" else "⚠️"
            location = ""
            if node_ref is not None:
                location = f"  [{node_ref[0]}: {node_ref[1]}]"
            text = f"{tag} {human}{location}"
            item = QListWidgetItem(text)
            item.setData(Qt.ItemDataRole.UserRole, problem)
            item.setForeground(QColor(current_palette()['text']))
            item.setToolTip(problem.get("message", ""))
            self.list_widget.addItem(item)
        self._hint.setVisible(bool(self._problems))
        self._on_selection_changed()

    def clear(self) -> None:
        self._problems = []
        self.list_widget.clear()
        self.title.setText("校验结果")
        self.title.setStyleSheet(f"font-weight: 700; color: {current_palette()['text']};")
        self._hint.setVisible(False)
        self.ai_fix_btn.setEnabled(False)

    def selected_problems(self) -> list[dict[str, Any]]:
        """Return currently selected problem dicts (selection order)."""
        out: list[dict[str, Any]] = []
        for item in self.list_widget.selectedItems():
            problem = item.data(Qt.ItemDataRole.UserRole)
            if isinstance(problem, dict):
                out.append(problem)
        return out

    def _on_item_double_clicked(self, item: QListWidgetItem) -> None:
        problem = item.data(Qt.ItemDataRole.UserRole)
        if not isinstance(problem, dict):
            return
        ref = problem_to_node_ref(problem, self.adapter.sections)
        if ref is not None:
            self.jump_to.emit(ref)

    def _on_selection_changed(self) -> None:
        selected = self.selected_problems()
        if not selected:
            self.ai_fix_btn.setEnabled(False)
            return
        # Enable if at least one selected problem maps to a node (or any selected).
        self.ai_fix_btn.setEnabled(True)
        n = len(selected)
        self.ai_fix_btn.setText(
            "AI 自动修正" if n <= 1 else f"AI 自动修正（{n}）"
        )

    def _on_ai_fix_clicked(self) -> None:
        selected = self.selected_problems()
        if not selected:
            # Fall back to current item for older selection paths.
            item = self.list_widget.currentItem()
            if item is None:
                return
            problem = item.data(Qt.ItemDataRole.UserRole)
            if isinstance(problem, dict):
                selected = [problem]
        if not selected:
            return
        pairs: list[tuple[dict[str, Any], tuple[str, str] | None]] = []
        for problem in selected:
            ref = problem_to_node_ref(problem, self.adapter.sections)
            pairs.append((problem, ref))
        # Prefer batch signal (U1-2). Still emit the legacy single-item signal
        # when exactly one problem is selected so older callers keep working;
        # MainWindow should connect *either* batch *or* single, not both on the
        # same path (see app._show_validation_report).
        if len(pairs) == 1:
            self.ai_fix_requested.emit(pairs[0][0], pairs[0][1])
        else:
            self.ai_batch_fix_requested.emit(pairs)
