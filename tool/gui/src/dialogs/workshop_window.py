"""Course workshop: project library + unified authoring canvas.

IA (post six-stage migration):
  stack 0 — project library
  stack 1 — unified workspace (material / knowledge / AI orbit /
            outline / design+JSON / import)

A lightweight checklist in the header tracks 素材 · 知识 · 草稿 · 导入.
``project.ui_stage`` is 0 for the library and any non-zero value for the
canvas (legacy 1–5 values restore to the canvas). Session continuity keeps
``workshop/last_project_id`` in QSettings; hide/close cancels in-flight work
and autosaves.
"""
from __future__ import annotations

from typing import Any

from PySide6.QtCore import Qt, QSettings, QTimer, Signal
from PySide6.QtGui import QKeySequence, QShortcut
from PySide6.QtWidgets import (
    QDialog,
    QHBoxLayout,
    QLabel,
    QMessageBox,
    QProgressBar,
    QPushButton,
    QStackedWidget,
    QVBoxLayout,
    QWidget,
)

from src.backend.textbook_project import TextbookProject
from src.backend.textbook_project_store import TextbookProjectStore
from src.dialogs.textbook_import_dialog import TextbookImportDialog
from src.dialogs.textbook_library_dialog import TextbookLibraryDialog
from src.theme import current_palette
from src.widgets.unified_workspace import UnifiedWorkspaceWidget

_LAST_PROJECT_KEY = "workshop/last_project_id"

# ui_stage: 0 = library, 1 = canvas (legacy stages 1–5 map to canvas).
_UI_LIBRARY = 0
_UI_CANVAS = 1

_LIBRARY_TITLE = "项目库"
_LIBRARY_DESC = "选择项目继续创作，或新建项目。所有进度自动保存，可随时关闭。"
_CANVAS_TITLE = "创意画布"
_CANVAS_DESC = (
    "左侧管理教材与知识点，中间拖入气泡让 AI 聚焦生成，右侧审校结构后导入课程。"
)


class WorkshopWindow(QDialog):
    """Non-modal course-authoring workspace window."""

    sections_ready = Signal(list, str)
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
        self._project: TextbookProject | None = None
        self._blank = False
        self._panel: TextbookImportDialog | None = None
        self._design_panel = None
        self._review_panel = None
        self._unified_workspace: UnifiedWorkspaceWidget | None = None
        self._busy_sources: set[str] = set()
        self._imported_section_id: str | None = None
        self.setWindowTitle("课程工坊")
        self.resize(1100, 720)

        self._build_ui()
        self._install_shortcuts()
        self._restore_geometry()
        self._update_header()

    def _install_shortcuts(self) -> None:
        """Esc cancels busy work; Ctrl+Enter also wired on the orbit widget."""
        esc = QShortcut(QKeySequence(Qt.Key.Key_Escape), self)
        esc.activated.connect(self._on_escape)

    def _on_escape(self) -> None:
        if not self._busy_sources:
            return
        reply = QMessageBox.question(
            self,
            "取消任务",
            "有任务正在进行，是否取消？",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
            QMessageBox.StandardButton.No,
        )
        if reply == QMessageBox.StandardButton.Yes:
            self._on_cancel_busy()

    # ------------------------------------------------------------------ UI
    def _build_ui(self) -> None:
        root = QVBoxLayout(self)
        root.setContentsMargins(12, 12, 12, 12)
        root.setSpacing(8)

        root.addWidget(self._build_header())
        root.addLayout(self._build_content(), 1)
        root.addWidget(self._build_bottom_bar())

    def _build_header(self) -> QWidget:
        header = QWidget()
        row = QHBoxLayout(header)
        row.setContentsMargins(4, 0, 4, 0)
        row.addWidget(QLabel("项目："))
        self._project_btn = QPushButton("未选择项目")
        self._project_btn.setFlat(True)
        self._project_btn.setStyleSheet("font-weight: 600;")
        self._project_btn.setToolTip("点击返回项目库，切换或新建项目")
        self._project_btn.clicked.connect(lambda: self._go_to_library())
        row.addWidget(self._project_btn)
        self._lang_label = QLabel("")
        self._lang_label.setStyleSheet(
            f"color: {current_palette()['text_secondary']};"
        )
        row.addWidget(self._lang_label)
        row.addStretch(1)
        self._checklist_label = QLabel("")
        self._checklist_label.setStyleSheet(
            f"color: {current_palette()['text_secondary']}; letter-spacing: 1px;"
        )
        self._checklist_label.setToolTip(
            "进度：素材（已加载章节）· 知识（资源池）· 草稿（AI 生成）· 导入（已写入课程）"
        )
        row.addWidget(self._checklist_label)
        return header

    def _build_content(self) -> QVBoxLayout:
        content = QVBoxLayout()
        content.setSpacing(6)

        self._page_title = QLabel("")
        self._page_title.setStyleSheet("font-size: 16px; font-weight: 600;")
        content.addWidget(self._page_title)
        self._page_desc = QLabel("")
        self._page_desc.setWordWrap(True)
        self._page_desc.setStyleSheet(
            f"color: {current_palette()['text_secondary']};"
        )
        content.addWidget(self._page_desc)

        self._stack = QStackedWidget()
        self._library = TextbookLibraryDialog(
            store=self._store, parent=self, embedded=True
        )
        self._library.setWindowFlags(Qt.WindowType.Widget)
        self._library.project_selected.connect(self._on_project_selected)
        self._stack.addWidget(self._library)

        self._unified_container = QWidget()
        self._unified_layout = QVBoxLayout(self._unified_container)
        self._unified_layout.setContentsMargins(0, 0, 0, 0)
        self._stack.addWidget(self._unified_container)

        content.addWidget(self._stack, 1)
        return content

    def _build_bottom_bar(self) -> QWidget:
        bar = QWidget()
        row = QHBoxLayout(bar)
        row.setContentsMargins(4, 0, 4, 0)
        self._locate_btn = QPushButton("定位到课程树")
        self._locate_btn.setEnabled(False)
        self._locate_btn.setToolTip("导入成功后，在主窗口课程树中选中该 section")
        self._locate_btn.clicked.connect(self._on_locate)
        row.addWidget(self._locate_btn)
        self._ws_progress = QProgressBar()
        self._ws_progress.setRange(0, 0)
        self._ws_progress.setFixedWidth(160)
        self._ws_progress.setVisible(False)
        row.addWidget(self._ws_progress)
        self._ws_stage_label = QLabel("")
        row.addWidget(self._ws_stage_label)
        row.addStretch(1)
        self._ws_usage_label = QLabel("")
        self._ws_usage_label.setStyleSheet(
            f"color: {current_palette()['text_secondary']}; font-size: 11px;"
        )
        row.addWidget(self._ws_usage_label)
        self._ws_autosave_label = QLabel("")
        self._ws_autosave_label.setStyleSheet(
            f"color: {current_palette()['text_secondary']}; font-size: 11px;"
        )
        row.addWidget(self._ws_autosave_label)
        self._ws_cancel_btn = QPushButton("取消任务")
        self._ws_cancel_btn.setVisible(False)
        self._ws_cancel_btn.clicked.connect(self._on_cancel_busy)
        row.addWidget(self._ws_cancel_btn)
        close_btn = QPushButton("关闭")
        close_btn.clicked.connect(self.hide)
        row.addWidget(close_btn)
        return bar

    # ------------------------------------------------------------------ navigation
    def _is_on_canvas(self) -> bool:
        return self._stack.currentIndex() == 1

    def _go_to_library(self) -> None:
        """Return to the project library (stage 0)."""
        if not self._confirm_leave_if_panel_busy():
            return
        if self._unified_workspace is not None:
            try:
                self._unified_workspace.save_ui_state()
            except Exception:
                pass
        self._save_current_state()
        self._stack.setCurrentIndex(0)
        self._update_header()
        self._persist_ui_stage(_UI_LIBRARY)

    def _go_to_canvas(self) -> None:
        """Show the unified workspace for the current project."""
        if self._project is None:
            return
        self._stack.setCurrentIndex(1)
        self._update_header()
        self._persist_ui_stage(_UI_CANVAS)

    def _go_to_stage(self, stage: int) -> None:
        """Compatibility helper: 0 → library, any other → canvas."""
        if stage == 0:
            self._go_to_library()
        else:
            self._go_to_canvas()

    def _degrade_stage(self, target: int) -> int:
        """Map any stage id to a stack page index (0 library, 1 canvas)."""
        return _UI_LIBRARY if target == 0 else _UI_CANVAS

    def _confirm_leave_if_panel_busy(self) -> bool:
        """If textbook extraction is running, ask before leaving the canvas."""
        if self._panel is None:
            return True
        controller = self._panel._controller
        if not getattr(controller, "is_busy", False):
            return True
        reply = QMessageBox.question(
            self,
            "任务进行中",
            "正在提取知识点，离开将取消当前任务。是否继续？",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
            QMessageBox.StandardButton.No,
        )
        if reply != QMessageBox.StandardButton.Yes:
            return False
        controller.cancel()
        return True

    # ------------------------------------------------------------------ checklist
    def _checklist_flags(self) -> dict[str, bool]:
        """Compute progress marks for the header checklist."""
        material = False
        knowledge = False
        draft = False
        imported = bool(self._imported_section_id)

        if self._project is not None:
            if self._blank:
                material = True  # blank AI project skips textbook material
            elif self._panel is not None:
                material = len(getattr(self._panel._controller, "chapters", []) or []) > 0
            else:
                material = bool(self._project.source_path)

            rp = self._project.resource_pool or {}
            knowledge = bool(
                rp.get("words") or rp.get("expressions") or rp.get("grammarPoints")
            )
            if self._project.imported_section_ids:
                imported = True

        if self._design_panel is not None:
            draft = bool(self._design_panel.has_draft())

        return {
            "material": material,
            "knowledge": knowledge,
            "draft": draft,
            "imported": imported,
        }

    def _format_checklist(self) -> str:
        flags = self._checklist_flags()
        parts = [
            ("素材", flags["material"]),
            ("知识", flags["knowledge"]),
            ("草稿", flags["draft"]),
            ("导入", flags["imported"]),
        ]
        return " · ".join(f"{'✓' if ok else '○'}{name}" for name, ok in parts)

    def _update_header(self) -> None:
        if self._project is not None:
            self._project_btn.setText(self._project.name)
            self._lang_label.setText(
                f"{self._project.source_language} → {self._project.language}"
            )
        else:
            self._project_btn.setText("未选择项目")
            self._lang_label.setText("")

        if self._is_on_canvas() and self._project is not None:
            self._page_title.setText(_CANVAS_TITLE)
            self._page_desc.setText(_CANVAS_DESC)
            self._checklist_label.setText(self._format_checklist())
            self._checklist_label.setVisible(True)
        else:
            self._page_title.setText(_LIBRARY_TITLE)
            self._page_desc.setText(_LIBRARY_DESC)
            self._checklist_label.setText("")
            self._checklist_label.setVisible(False)

    # ------------------------------------------------------------------ project
    def current_project(self) -> TextbookProject | None:
        """The project currently open in the workshop (or None)."""
        return self._project

    def restore_last_session(self) -> bool:
        """Reopen the last-used project on the canvas, if any."""
        if self._project is not None:
            return True
        settings = QSettings("Varnamala", "CourseEditor")
        project_id = settings.value(_LAST_PROJECT_KEY, "")
        if not project_id:
            return False
        project = self._store.load_project(str(project_id))
        if project is None:
            return False
        self._on_project_selected(project)
        return True

    def _teardown_workspace(self) -> None:
        """Detach current panels; delete on next event-loop tick to reduce flash."""
        if self._unified_workspace is not None:
            try:
                self._unified_workspace.save_ui_state()
            except Exception:
                pass
            old_ws = self._unified_workspace
            self._unified_workspace = None
            old_ws.hide()
            old_ws.setParent(None)
            QTimer.singleShot(0, old_ws.deleteLater)

        if self._panel is not None:
            old = self._panel
            self._panel = None
            old.setParent(None)
            QTimer.singleShot(0, old.deleteLater)
        if self._design_panel is not None:
            old = self._design_panel
            try:
                old.cleanup_attachments()
            except Exception:
                pass
            self._design_panel = None
            old.setParent(None)
            QTimer.singleShot(0, old.deleteLater)
        if self._review_panel is not None:
            old = self._review_panel
            self._review_panel = None
            old.setParent(None)
            QTimer.singleShot(0, old.deleteLater)

        self._busy_sources.clear()
        self._ws_progress.setVisible(False)
        self._ws_cancel_btn.setVisible(False)
        self._ws_stage_label.setText("")
        self._ws_usage_label.setText("")
        self._ws_autosave_label.setText("")

    def _on_project_selected(self, project: TextbookProject) -> None:
        """(Re)build the embedded panels and open the unified canvas."""
        # Save outgoing project before teardown.
        if self._design_panel is not None and self._design_panel._controller.is_busy:
            self._design_panel._controller.cancel()
        if self._panel is not None and self._panel._controller.is_busy:
            self._panel._controller.cancel()
        if self._panel is not None:
            self._panel._controller.flush_autosave()
        if self._unified_workspace is not None:
            try:
                self._unified_workspace.save_ui_state()
            except Exception:
                pass
        self._save_current_state()

        self._teardown_workspace()

        self._project = project
        self._blank = project.source_path is None
        self._imported_section_id = None
        if project.imported_section_ids:
            # Prefer the last recorded import for locate.
            self._imported_section_id = project.imported_section_ids[-1]
        self._locate_btn.setEnabled(bool(self._imported_section_id))

        # Textbook import panel (also for blank: empty source, knowledge optional).
        panel = TextbookImportDialog(
            self.adapter,
            self,
            project=project,
            store=self._store,
            embedded=True,
        )
        panel.setWindowFlags(Qt.WindowType.Widget)
        panel.set_stepper_visible(False)
        panel.set_bottom_bar_visible(False)
        panel.sections_ready.connect(self._on_panel_sections_ready)
        panel.busy_changed.connect(self._on_panel_busy)
        panel.stage_text_changed.connect(self._on_stage_text)
        panel.usage_changed.connect(self._on_usage_text)
        panel.autosave_saved.connect(self._on_autosaved)
        self._panel = panel

        from src.dialogs.ai.design_panel import DesignPanel

        self._design_panel = DesignPanel(self.adapter, self)
        self._design_panel.set_status_widgets_visible(False)
        self._design_panel.set_project(project, self._store)
        self._design_panel.sections_ready.connect(self._on_panel_sections_ready)
        self._design_panel.draft_ready.connect(self._on_draft_ready)
        self._design_panel.busy_changed.connect(self._on_design_busy)
        self._design_panel.usage_changed.connect(self._on_usage_text)

        from src.dialogs.ai.review_panel import ReviewPanel

        self._review_panel = ReviewPanel(self._design_panel, self.adapter, self)

        self._unified_workspace = UnifiedWorkspaceWidget(
            self.adapter,
            self._panel,
            self._design_panel,
            self._review_panel,
            self,
            blank=self._blank,
            project_id=project.project_id,
        )
        self._unified_layout.addWidget(self._unified_workspace)
        self._unified_workspace.show()

        self._stack.setCurrentIndex(1)
        self._update_header()

        settings = QSettings("Varnamala", "CourseEditor")
        settings.setValue(_LAST_PROJECT_KEY, project.project_id)
        self._persist_ui_stage(_UI_CANVAS)

    def _on_draft_ready(self) -> None:
        self._ws_stage_label.setText("草稿已生成")
        self._update_header()
        if self._review_panel is not None:
            self._review_panel.refresh()

    # ------------------------------------------------------------------ review helpers (tests / host)
    def _review_refresh(self) -> None:
        if self._review_panel is not None:
            self._review_panel.refresh()

    def _review_import(self) -> None:
        if self._review_panel is not None:
            self._review_panel._on_import()

    # ---------------------------------------------------------- bottom bar slots
    def _on_panel_busy(self, busy: bool, stage: str) -> None:
        self._set_busy_source("panel", busy, stage)

    def _on_design_busy(self, busy: bool, stage: str) -> None:
        self._set_busy_source("design", busy, stage)

    def _set_busy_source(self, source: str, busy: bool, stage: str) -> None:
        if busy:
            self._busy_sources.add(source)
        else:
            self._busy_sources.discard(source)
        any_busy = bool(self._busy_sources)
        self._ws_progress.setVisible(any_busy)
        self._ws_cancel_btn.setVisible(any_busy)
        if stage:
            self._ws_stage_label.setText(stage)
        elif not any_busy:
            self._ws_stage_label.setText("")

    def _on_stage_text(self, text: str) -> None:
        self._ws_stage_label.setText(text)

    def _on_usage_text(self, text: str) -> None:
        self._ws_usage_label.setText(text)

    def _on_autosaved(self, text: str) -> None:
        self._ws_autosave_label.setText(text)

    def _on_cancel_busy(self) -> None:
        """Route cancellation to whichever task is running."""
        if "design" in self._busy_sources and self._design_panel is not None:
            self._design_panel._controller.cancel()
        if "panel" in self._busy_sources and self._panel is not None:
            self._panel._controller.cancel()

    # ---------------------------------------------------------- persistence
    def _persist_ui_stage(self, stage: int) -> None:
        if self._project is None:
            return
        # Normalize legacy multi-stage values to canvas (1).
        normalized = _UI_LIBRARY if stage == 0 else _UI_CANVAS
        if self._project.ui_stage == normalized:
            return
        self._project.ui_stage = normalized
        try:
            self._store.save_project(self._project)
        except Exception:
            pass

    def _save_current_state(self) -> None:
        """Autosave design panel state (import controller saves itself)."""
        if self._unified_workspace is not None:
            try:
                self._unified_workspace.save_ui_state()
            except Exception:
                pass
        if self._design_panel is not None:
            # Immediate write on interrupt / project switch (P2 throttled path).
            if hasattr(self._design_panel, "flush_autosave"):
                self._design_panel.flush_autosave()
            else:
                self._design_panel._autosave()

    def interrupt_and_save(self) -> None:
        """Cancel in-flight work and persist everything (随时中断)."""
        if self._design_panel is not None and self._design_panel._controller.is_busy:
            self._design_panel._controller.cancel()
        if self._panel is not None and self._panel._controller.is_busy:
            self._panel._controller.cancel()
        if self._panel is not None:
            self._panel._controller.flush_autosave()
        if self._design_panel is not None:
            self._design_panel.cleanup_attachments()
        self._busy_sources.clear()
        self._save_current_state()
        stage = _UI_CANVAS if self._is_on_canvas() else _UI_LIBRARY
        self._persist_ui_stage(stage)

    # ------------------------------------------------------------------ import
    def _on_panel_sections_ready(self, sections: list, strategy: str) -> None:
        self.sections_ready.emit(sections, strategy)
        self._update_header()

    def on_import_finished(self, section_id: str | None) -> None:
        """Called by MainWindow after the import pipeline ran."""
        if section_id:
            self._imported_section_id = section_id
            self._locate_btn.setEnabled(True)
            self._update_header()

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

    def _save_geometry(self) -> None:
        settings = QSettings("Varnamala", "CourseEditor")
        settings.setValue(self._GEOMETRY_KEY, self.saveGeometry())

    def closeEvent(self, event: Any) -> None:
        self.interrupt_and_save()
        self._save_geometry()
        super().closeEvent(event)

    def hideEvent(self, event: Any) -> None:
        self.interrupt_and_save()
        self._save_geometry()
        super().hideEvent(event)
