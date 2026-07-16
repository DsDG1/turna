"""Unified authoring workspace (connectplan Phase 2).

A non-modal window hosting the whole textbook → course pipeline:
项目 (project library) → 素材 (source) → 知识 (knowledge) → 导入 (import).
The two legacy modal dialogs are embedded as plain widgets (``embedded=True``)
so their controllers and tests are reused unchanged; the workshop adds a
clickable outer stage navigation and a "locate in course tree" button.
"""
from __future__ import annotations

from typing import Any

from PySide6.QtCore import Qt, QSettings, Signal
from PySide6.QtWidgets import (
    QDialog,
    QHBoxLayout,
    QLabel,
    QPushButton,
    QStackedWidget,
    QVBoxLayout,
    QWidget,
)

from src.backend.textbook_project import TextbookProject
from src.backend.textbook_project_store import TextbookProjectStore
from src.dialogs.textbook_import_dialog import TextbookImportDialog
from src.dialogs.textbook_library_dialog import TextbookLibraryDialog

#: Outer stage names; index 0 is the project library page. 素材/知识/导入 map
#: to the import panel's pages; 设计 is the grounded design panel.
_STAGES = ("项目", "素材", "知识", "设计", "导入")
#: stage → (workshop stack index, import-panel page or None)
_STAGE_MAP = {0: (0, None), 1: (1, 0), 2: (1, 1), 3: (2, None), 4: (1, 2)}


class WorkshopWindow(QDialog):
    """Non-modal course-authoring workspace window."""

    #: Forwarded from the embedded import panel: (sections, strategy).
    sections_ready = Signal(list, str)
    #: User asked to reveal a section in the main window's course tree.
    locate_requested = Signal(str)

    def __init__(
        self,
        adapter: Any,
        parent: QWidget | None = None,
        *,
        store: TextbookProjectStore | None = None,
    ) -> None:
        super().__init__(parent, Qt.WindowType.Window)
        self.adapter = adapter
        self._parent_window = parent
        self._store = store or TextbookProjectStore()
        self._panel: TextbookImportDialog | None = None
        self._design_panel = None
        self._max_stage = 0
        self._imported_section_id: str | None = None
        self.setWindowTitle("课程工坊")
        self.resize(980, 700)

        self._build_ui()
        self._restore_geometry()
        self._update_stage_buttons()

    # ------------------------------------------------------------------ UI
    def _build_ui(self) -> None:
        layout = QVBoxLayout(self)
        layout.setContentsMargins(12, 12, 12, 12)
        layout.setSpacing(8)

        # Clickable stage navigation.
        nav = QHBoxLayout()
        nav.addWidget(QLabel("阶段："))
        self._stage_buttons: list[QPushButton] = []
        for i, name in enumerate(_STAGES):
            btn = QPushButton(name)
            btn.setFlat(True)
            btn.clicked.connect(lambda _checked=False, idx=i: self._go_to_stage(idx))
            self._stage_buttons.append(btn)
            nav.addWidget(btn)
            if i < len(_STAGES) - 1:
                nav.addWidget(QLabel("→"))
        nav.addStretch(1)
        layout.addLayout(nav)

        self._stack = QStackedWidget()
        self._library = TextbookLibraryDialog(
            store=self._store, parent=self, embedded=True
        )
        self._library.setWindowFlags(Qt.WindowType.Widget)
        self._library.project_selected.connect(self._on_project_selected)
        self._stack.addWidget(self._library)
        # Placeholder for the import panel page (replaced per project).
        self._panel_container = QWidget()
        self._panel_layout = QVBoxLayout(self._panel_container)
        self._panel_layout.setContentsMargins(0, 0, 0, 0)
        self._stack.addWidget(self._panel_container)
        # Placeholder for the design panel page (replaced per project).
        self._design_container = QWidget()
        self._design_layout = QVBoxLayout(self._design_container)
        self._design_layout.setContentsMargins(0, 0, 0, 0)
        self._stack.addWidget(self._design_container)
        layout.addWidget(self._stack, 1)

        bottom = QHBoxLayout()
        self._locate_btn = QPushButton("定位到课程树")
        self._locate_btn.setEnabled(False)
        self._locate_btn.setToolTip("导入成功后，在主窗口课程树中选中该 section")
        self._locate_btn.clicked.connect(self._on_locate)
        bottom.addWidget(self._locate_btn)
        bottom.addStretch(1)
        close_btn = QPushButton("关闭")
        close_btn.clicked.connect(self.hide)
        bottom.addWidget(close_btn)
        layout.addLayout(bottom)

    # ------------------------------------------------------------------ stages
    def _go_to_stage(self, stage: int) -> None:
        """Navigate to a stage; forward navigation is capped at _max_stage."""
        if stage > self._max_stage or stage not in _STAGE_MAP:
            return
        if self._panel is not None and self._panel._controller.is_busy:
            return  # extraction in flight — stay put
        stack_index, panel_page = _STAGE_MAP[stage]
        if stack_index == 1 and self._panel is None:
            return
        if stack_index == 2 and self._design_panel is None:
            return
        if stack_index == 2:
            # Knowledge stage may have changed the pool since the last visit;
            # re-ground and warn when a draft exists (connectplan §2.2).
            if self._design_panel.refresh_pool_from_project():
                self._design_panel.notice_pool_updated()
        self._stack.setCurrentIndex(stack_index)
        if panel_page is not None:
            self._panel._stack.setCurrentIndex(panel_page)
        self._update_stage_buttons()

    def _current_stage(self) -> int:
        stack_index = self._stack.currentIndex()
        if stack_index == 0:
            return 0
        if stack_index == 2:
            return 3
        return {0: 1, 1: 2, 2: 4}.get(self._panel_page(), 1)

    def _update_stage_buttons(self) -> None:
        current = self._current_stage()
        for i, btn in enumerate(self._stage_buttons):
            btn.setEnabled(i <= self._max_stage and (i == 0 or self._panel is not None))
            btn.setStyleSheet("font-weight: 600;" if i == current else "")

    def _panel_page(self) -> int:
        return self._panel._stack.currentIndex() if self._panel is not None else -1

    # ------------------------------------------------------------------ project
    def _on_project_selected(self, project: TextbookProject) -> None:
        """(Re)build the embedded import + design panels for the project."""
        if self._panel is not None:
            self._panel.setParent(None)
            self._panel.deleteLater()
            self._panel = None
        if self._design_panel is not None:
            self._design_panel.setParent(None)
            self._design_panel.deleteLater()
            self._design_panel = None
        panel = TextbookImportDialog(
            self.adapter,
            self,
            project=project,
            store=self._store,
            embedded=True,
        )
        panel.setWindowFlags(Qt.WindowType.Widget)
        panel.set_stepper_visible(False)
        panel.sections_ready.connect(self._on_panel_sections_ready)
        panel.design_requested.connect(lambda: self._go_to_stage(3))
        panel._stack.currentChanged.connect(
            lambda _idx: self._sync_max_stage()
        )
        self._panel = panel
        self._panel_layout.addWidget(panel)
        panel.show()

        from src.dialogs.ai.design_panel import DesignPanel

        self._design_panel = DesignPanel(self.adapter, self)
        self._design_panel.set_project(project, self._store)
        self._design_panel.sections_ready.connect(self._on_panel_sections_ready)
        self._design_layout.addWidget(self._design_panel)
        self._design_panel.show()

        self._stack.setCurrentIndex(1)
        self._sync_max_stage()
        self._update_stage_buttons()

    def _sync_max_stage(self) -> None:
        if self._panel is None:
            return
        # Panel pages: 0 素材 → stage 1; 1 知识 → stage 3 (design unlocked
        # once extraction started); 2 导入 → stage 4.
        page = self._panel._stack.currentIndex()
        self._max_stage = max(self._max_stage, {0: 1, 1: 3, 2: 4}.get(page, 1))

    # ------------------------------------------------------------------ import
    def _on_panel_sections_ready(self, sections: list, strategy: str) -> None:
        self._sync_max_stage()
        self._update_stage_buttons()
        self.sections_ready.emit(sections, strategy)

    def on_import_finished(self, section_id: str | None) -> None:
        """Called by MainWindow after the import pipeline ran."""
        if section_id:
            self._imported_section_id = section_id
            self._locate_btn.setEnabled(True)

    def _on_locate(self) -> None:
        if self._imported_section_id:
            self.locate_requested.emit(self._imported_section_id)

    # ------------------------------------------------------------------ geometry
    _GEOMETRY_KEY = "workshop/geometry"

    def _restore_geometry(self) -> None:
        settings = QSettings("Varnamala", "CourseEditor")
        geo = settings.value(self._GEOMETRY_KEY)
        if geo:
            self.restoreGeometry(geo)

    def closeEvent(self, event: Any) -> None:
        settings = QSettings("Varnamala", "CourseEditor")
        settings.setValue(self._GEOMETRY_KEY, self.saveGeometry())
        super().closeEvent(event)

    def hideEvent(self, event: Any) -> None:
        settings = QSettings("Varnamala", "CourseEditor")
        settings.setValue(self._GEOMETRY_KEY, self.saveGeometry())
        super().hideEvent(event)
