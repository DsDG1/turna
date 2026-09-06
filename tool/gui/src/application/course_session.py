"""CourseSession — in-memory editing session for course authoring.

Decouples core course editing state, mutations, undo management, and node
selection from the top-level QMainWindow UI shell. Services, background
workers, and controllers interact with this session rather than probing the
window instance directly.
"""
from __future__ import annotations

import logging
from pathlib import Path
from typing import Any

from PySide6.QtCore import QObject, Signal
from PySide6.QtGui import QUndoStack

from src.backend.course_adapter import CourseAdapter
from src.backend.experience.conflict_guard import ConflictGuard
from src.backend.experience.metrics import ExperienceMetrics

logger = logging.getLogger(__name__)


class CourseSession(QObject):
    """Encapsulates in-memory course state, mutation tracking, and selection."""

    repo_opened = Signal(Path)
    repo_closed = Signal()
    node_selected = Signal(tuple)          # (kind, id)
    teacher_mode_changed = Signal(bool)
    dirty_changed = Signal(bool)

    def __init__(self, parent: QObject | None = None) -> None:
        super().__init__(parent)
        self.adapter = CourseAdapter()
        self.course_dir: Path | None = None
        self.undo_stack = QUndoStack(self)
        self.conflict_guard = ConflictGuard()
        self.experience_metrics = ExperienceMetrics()
        self.current_node_ref: tuple[str, str] | None = None
        self.teacher_mode: bool = False
        self.last_imported_section_id: str | None = None

        self.undo_stack.cleanChanged.connect(self._on_undo_clean_changed)

    def _on_undo_clean_changed(self, is_clean: bool) -> None:
        self.dirty_changed.emit(not is_clean)

    @property
    def is_open(self) -> bool:
        """True when a course directory is currently loaded."""
        return self.course_dir is not None

    @property
    def is_dirty(self) -> bool:
        """True when there are unsaved edits on the undo stack."""
        return not self.undo_stack.isClean()

    def open_course(self, path: Path | str) -> None:
        """Load course from directory, reset undo history, and notify listeners."""
        self.course_dir = Path(path)
        self.adapter.load(self.course_dir)
        self.undo_stack.clear()
        self.current_node_ref = None
        self.last_imported_section_id = None
        self.repo_opened.emit(self.course_dir)

    def close_course(self) -> None:
        """Reset session state when closing the current course."""
        self.course_dir = None
        self.undo_stack.clear()
        self.current_node_ref = None
        self.last_imported_section_id = None
        self.repo_closed.emit()

    def select_node(self, kind: str, node_id: str) -> None:
        """Set currently selected node reference and emit signal if changed."""
        ref = (kind, node_id)
        if self.current_node_ref != ref:
            self.current_node_ref = ref
            self.node_selected.emit(ref)

    def set_teacher_mode(self, enabled: bool) -> None:
        """Toggle teacher preview mode."""
        if self.teacher_mode != enabled:
            self.teacher_mode = enabled
            self.teacher_mode_changed.emit(enabled)
