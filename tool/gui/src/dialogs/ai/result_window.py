"""Independent window hosting the AI generator's JSON editor (Change 1).

The wish-mode result pane crams the structured preview, an unbounded JSON
editor and the plain-language explanation into one narrow vertical splitter
section, crushing the chat area after generation. This window pops the JSON
editor out into its own resizable, non-modal window (mirrors
``ChatExpandWindow``) so the in-dialog layout stays breathable.

The dialog reparents its active ``JsonEditor`` into this window when opened
and reparents it back when closed — the same reparenting technique already
used for the shared ``PromptTemplateBar``. Edits flow back through the
editor's existing ``textChanged`` signals, which ``_current_json`` reads
parent-agnostically.
"""
from __future__ import annotations

import logging
logger = logging.getLogger(__name__)


import time

from PySide6.QtCore import Qt, QSettings
from PySide6.QtWidgets import (
    QDialog,
    QHBoxLayout,
    QLabel,
    QPushButton,
    QVBoxLayout,
    QWidget,
)

from src.theme import current_palette


class ResultExpandWindow(QDialog):
    """Non-modal, resizable window hosting a reparented JSON editor."""

    _GEO_KEY = "ai_json_window/geometry"
    _MAX_KEY = "ai_json_window/maximized"

    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.setWindowTitle("AI 生成结果 · JSON（独立窗口）")
        self.setWindowFlag(Qt.WindowType.Window, True)
        self.resize(900, 700)
        self.setMinimumSize(560, 380)

        self._editor = None  # the reparented JsonEditor
        self._usage_t0 = time.perf_counter()

        root = QVBoxLayout(self)
        root.setContentsMargins(10, 10, 10, 10)
        root.setSpacing(8)

        header = QHBoxLayout()
        header.setSpacing(8)
        hint = QLabel("可直接编辑 JSON；关闭窗口后编辑器回到生成页。")
        hint.setStyleSheet(f"color: {current_palette()['text_secondary']}; font-size: 12px;")
        header.addWidget(hint, 1)
        self.done_btn = QPushButton("收起（回到生成页）")
        self.done_btn.clicked.connect(self.close)
        header.addWidget(self.done_btn)
        root.addLayout(header)

        # The editor host layout; the reparented editor is added here.
        self._host = QVBoxLayout()
        self._host.setContentsMargins(0, 0, 0, 0)
        root.addLayout(self._host, 1)

        self._load_geometry()

    # --- editor reparenting ---------------------------------------------

    def host_editor(self, editor: QWidget) -> None:
        """Reparent ``editor`` (a JsonEditor) into this window."""
        self._remove_current_editor()
        editor.setParent(self)
        self._host.addWidget(editor)
        self._editor = editor

    def release_editor(self) -> QWidget | None:
        """Detach the hosted editor so the caller can reparent it back.

        Returns the editor widget (now parentless) or None.
        """
        editor = self._editor
        if editor is not None:
            self._host.removeWidget(editor)
            editor.setParent(None)
            self._editor = None
        return editor

    def _remove_current_editor(self) -> None:
        if self._editor is not None:
            self._host.removeWidget(self._editor)
            self._editor.setParent(None)
            self._editor = None

    # --- geometry persistence -------------------------------------------

    def _load_geometry(self) -> None:
        qs = QSettings("Turna", "CourseEditor")
        geo = qs.value(self._GEO_KEY)
        if geo is not None:
            self.restoreGeometry(geo)
        if qs.value(self._MAX_KEY, False) in (True, "true", "1"):
            self.showMaximized()

    def _save_geometry(self) -> None:
        qs = QSettings("Turna", "CourseEditor")
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
            logger.debug("dialogs/ai/result_window.py:130 best-effort step failed", exc_info=True)
