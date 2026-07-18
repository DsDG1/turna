"""Unified authoring workspace (connectplan Phase 2 + merge overhaul A/B).

A non-modal window hosting the whole textbook → course pipeline:
项目 (library) → 素材 (source) → 知识 (knowledge) → 设计 (design) →
审校 (review) → 导入 (import). The legacy import dialog is embedded as a
plain widget (``embedded=True``) so its controller and tests are reused
unchanged.

UI (Phase B): left sidebar stage navigation with completion marks, a project
header, a per-stage page title/description header, a nav row on
workshop-owned pages, and one unified bottom bar (progress / stage / usage /
autosave / cancel) fed by the embedded panels' status signals.

Session continuity (随时中断、无限次恢复): the last-opened project id is kept
in QSettings and the current stage is persisted to ``project.ui_stage`` on
every navigation; closing/hiding the window cancels in-flight work and
autosaves, so reopening restores the exact view.
"""
from __future__ import annotations

from typing import Any

from PySide6.QtCore import Qt, QSettings, Signal
from PySide6.QtWidgets import (
    QDialog,
    QHBoxLayout,
    QLabel,
    QListWidget,
    QListWidgetItem,
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

#: Outer stage names; index 0 is the project library page. 素材/知识/导入 map
#: to the import panel's pages; 设计 is the grounded design panel; 审校 is the
#: workshop-owned review page (full panel lands in Phase C).
_STAGES = ("项目", "素材", "知识", "设计", "审校", "导入")
#: stage → (workshop stack index, import-panel page or None)
_STAGE_MAP = {0: (0, None), 1: (1, 0), 2: (1, 1), 3: (2, None), 4: (3, None), 5: (1, 2)}
_PANEL_PAGE_FOR_STAGE = {1: 0, 2: 1, 5: 2}
_STAGE_FOR_PANEL_PAGE = {0: 1, 1: 2, 2: 5}
#: _max_stage unlocked by reaching each import-panel page.
_MAX_STAGE_FOR_PANEL_PAGE = {0: 1, 1: 3, 2: 5}

_STAGE_DESCRIPTIONS = {
    0: "选择项目继续创作，或新建项目。所有进度自动保存，可随时关闭。",
    1: "选择教材文件，解析后勾选需要的章节。",
    2: "逐章提取词汇 / 表达 / 语法点并审校，质量标记辅助修正。",
    3: "与 AI 讨论并生成课程：有资源池时从池中选词编排，空白项目自由生成。",
    4: "检查 AI 草稿的结构与内容，确认后导入到当前课程。",
    5: "选择导入策略，把章节构建的课时批量导入到当前课程。",
}

_LAST_PROJECT_KEY = "workshop/last_project_id"


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
        self._project: TextbookProject | None = None
        self._blank = False
        self._panel: TextbookImportDialog | None = None
        self._design_panel = None
        self._review_panel = None
        self._max_stage = 0
        self._busy_sources: set[str] = set()
        self._imported_section_id: str | None = None
        self._nav_syncing = False
        self.setWindowTitle("课程工坊")
        self.resize(1100, 720)

        self._build_ui()
        self._restore_geometry()
        self._update_nav()

    # ------------------------------------------------------------------ UI
    def _build_ui(self) -> None:
        root = QVBoxLayout(self)
        root.setContentsMargins(12, 12, 12, 12)
        root.setSpacing(8)

        root.addWidget(self._build_header())

        body = QHBoxLayout()
        body.setSpacing(10)
        body.addWidget(self._build_sidebar())
        body.addLayout(self._build_content(), 1)
        root.addLayout(body, 1)

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
        self._project_btn.clicked.connect(lambda: self._go_to_stage(0))
        row.addWidget(self._project_btn)
        self._lang_label = QLabel("")
        self._lang_label.setStyleSheet(
            f"color: {current_palette()['text_secondary']};"
        )
        row.addWidget(self._lang_label)
        row.addStretch(1)
        self._dots_label = QLabel("")
        self._dots_label.setStyleSheet(
            f"color: {current_palette()['text_secondary']}; letter-spacing: 2px;"
        )
        row.addWidget(self._dots_label)
        return header

    def _build_sidebar(self) -> QWidget:
        self._stage_list = QListWidget()
        self._stage_list.setFixedWidth(132)
        for i, name in enumerate(_STAGES):
            item = QListWidgetItem(f"{i + 1} {name}")
            item.setData(Qt.ItemDataRole.UserRole, i)
            self._stage_list.addItem(item)
        self._stage_list.currentRowChanged.connect(self._on_nav_row_changed)
        return self._stage_list

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
        # 0: project library (embedded, non-modal).
        self._library = TextbookLibraryDialog(
            store=self._store, parent=self, embedded=True
        )
        self._library.setWindowFlags(Qt.WindowType.Widget)
        self._library.project_selected.connect(self._on_project_selected)
        self._stack.addWidget(self._library)
        # 1: import panel container (rebuilt per textbook project).
        self._panel_container = QWidget()
        self._panel_layout = QVBoxLayout(self._panel_container)
        self._panel_layout.setContentsMargins(0, 0, 0, 0)
        self._stack.addWidget(self._panel_container)
        # 2: design panel container (rebuilt per project).
        self._design_container = QWidget()
        self._design_layout = QVBoxLayout(self._design_container)
        self._design_layout.setContentsMargins(0, 0, 0, 0)
        self._stack.addWidget(self._design_container)
        # 3: review panel container (rebuilt per project).
        self._review_container = QWidget()
        self._review_layout = QVBoxLayout(self._review_container)
        self._review_layout.setContentsMargins(0, 0, 0, 0)
        self._stack.addWidget(self._review_container)
        content.addWidget(self._stack, 1)

        # Nav row — visible only on workshop-owned pages (embedded pages
        # carry their own action/nav buttons).
        self._nav_row = QWidget()
        nav = QHBoxLayout(self._nav_row)
        nav.setContentsMargins(0, 0, 0, 0)
        self._prev_btn = QPushButton("上一步")
        self._prev_btn.clicked.connect(self._on_prev)
        nav.addWidget(self._prev_btn)
        nav.addStretch(1)
        self._next_btn = QPushButton("下一步 →")
        self._next_btn.clicked.connect(self._on_next)
        nav.addWidget(self._next_btn)
        content.addWidget(self._nav_row)
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

    # ------------------------------------------------------------------ stages
    def _go_to_stage(self, stage: int) -> None:
        """Navigate to a stage; forward navigation is capped at _max_stage."""
        if stage not in _STAGE_MAP:
            return
        if stage != self._current_stage():
            if stage > self._max_stage or not self._stage_available(stage):
                self._sync_sidebar_row()
                return
            if self._panel is not None and self._panel._controller.is_busy:
                # Extraction owns chapter checkpoints — confirm before leaving.
                reply = QMessageBox.question(
                    self,
                    "提取进行中",
                    "知识提取正在进行。取消提取并切换阶段？",
                    QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
                )
                if reply != QMessageBox.StandardButton.Yes:
                    self._sync_sidebar_row()
                    return
                self._panel._controller.cancel()
        stack_index, panel_page = _STAGE_MAP[stage]
        # Leaving a page persists its state (阶段切换即保存).
        self._save_current_state()
        if stage == 3:
            # Knowledge stage may have changed the pool since the last visit;
            # re-ground and warn when a draft exists (connectplan §2.2).
            if self._design_panel.refresh_pool_from_project():
                self._design_panel.notice_pool_updated()
        if stage == 4:
            self._review_refresh()
        self._stack.setCurrentIndex(stack_index)
        if panel_page is not None:
            self._panel._stack.setCurrentIndex(panel_page)
        self._update_nav()
        self._persist_ui_stage(stage)

    def _current_stage(self) -> int:
        stack_index = self._stack.currentIndex()
        if stack_index == 0:
            return 0
        if stack_index == 2:
            return 3
        if stack_index == 3:
            return 4
        return _STAGE_FOR_PANEL_PAGE.get(self._panel_page(), 1)

    def _stage_available(self, stage: int) -> bool:
        """Whether a stage's page exists for the current project kind."""
        if stage == 0:
            return True
        if stage == 3:
            return self._design_panel is not None
        if stage == 4:
            return self._design_panel is not None and self._design_panel.has_draft()
        return self._panel is not None  # 素材/知识/导入 need the import panel

    def _stage_complete(self, stage: int) -> bool:
        if self._project is None:
            return False
        if stage == 1:
            return bool(self._project.chapters)
        if stage == 2:
            pool = self._project.resource_pool or {}
            return any(pool.get(k) for k in ("words", "expressions", "grammarPoints"))
        if stage == 3:
            return self._design_panel is not None and self._design_panel.has_draft()
        if stage == 5:
            return bool(self._project.imported_section_ids)
        return False

    def _panel_page(self) -> int:
        return self._panel._stack.currentIndex() if self._panel is not None else -1

    # ------------------------------------------------------------------ nav rendering
    def _on_nav_row_changed(self, row: int) -> None:
        if self._nav_syncing or row < 0:
            return
        self._go_to_stage(row)

    def _sync_sidebar_row(self) -> None:
        self._nav_syncing = True
        self._stage_list.setCurrentRow(self._current_stage())
        self._nav_syncing = False

    def _update_nav(self) -> None:
        current = self._current_stage()
        self._nav_syncing = True
        for i in range(self._stage_list.count()):
            item = self._stage_list.item(i)
            enabled = i <= self._max_stage and self._stage_available(i)
            flags = item.flags()
            if enabled:
                flags |= Qt.ItemFlag.ItemIsEnabled
            else:
                flags &= ~Qt.ItemFlag.ItemIsEnabled
            item.setFlags(flags)
            mark = " ✓" if self._stage_complete(i) else ""
            item.setText(f"{i + 1} {_STAGES[i]}{mark}")
            if self._blank and i in (1, 2, 5):
                item.setToolTip("该项目无教材素材")
            elif i == 4 and not self._stage_available(4):
                item.setToolTip("生成草稿后可用")
            else:
                item.setToolTip("")
        self._stage_list.setCurrentRow(current)
        self._nav_syncing = False

        # Header.
        if self._project is not None:
            self._project_btn.setText(self._project.name)
            self._lang_label.setText(
                f"{self._project.source_language} → {self._project.language}"
            )
        else:
            self._project_btn.setText("未选择项目")
            self._lang_label.setText("")
        dots = "".join(
            "●" if (i <= self._max_stage and self._stage_available(i)) else "○"
            for i in range(len(_STAGES))
        )
        self._dots_label.setText(dots)
        self._dots_label.setToolTip("阶段进度")

        self._page_title.setText(f"{current + 1} {_STAGES[current]}")
        self._page_desc.setText(_STAGE_DESCRIPTIONS.get(current, ""))

        # Nav row: workshop-owned pages only (0 项目 / 3 设计 / 4 审校).
        self._update_nav_row(current)

    def _update_nav_row(self, current: int) -> None:
        if current not in (0, 3, 4):
            self._nav_row.setVisible(False)
            return
        self._nav_row.setVisible(True)
        if current == 0:
            self._prev_btn.setVisible(False)
            self._next_btn.setText("继续 →")
            self._next_btn.setEnabled(self._project is not None)
        elif current == 3:
            self._prev_btn.setVisible(True)
            self._prev_btn.setText("上一步：项目" if self._blank else "上一步：知识")
            has_draft = (
                self._design_panel is not None and self._design_panel.has_draft()
            )
            self._next_btn.setText("下一步：审校 →")
            self._next_btn.setEnabled(has_draft)
            self._next_btn.setToolTip("" if has_draft else "请先生成课程草稿")
        else:  # 审校
            self._prev_btn.setVisible(True)
            self._prev_btn.setText("上一步：设计")
            self._next_btn.setText("导入草稿到课程 ↗")
            self._next_btn.setEnabled(True)

    def _on_prev(self) -> None:
        current = self._current_stage()
        if current == 3:
            self._go_to_stage(0 if self._blank else 2)
        elif current == 4:
            self._go_to_stage(3)

    def _on_next(self) -> None:
        current = self._current_stage()
        if current == 0:
            self._go_to_stage(3 if self._blank else 1)
        elif current == 3:
            self._go_to_stage(4)
        elif current == 4:
            self._review_import()

    # ------------------------------------------------------------------ project
    def current_project(self) -> TextbookProject | None:
        """The project currently open in the workshop (or None)."""
        return self._project

    def restore_last_session(self) -> bool:
        """Reopen the last-used project at its persisted stage, if any.

        Called by the host after construction so opening the workshop is a
        zero-click return to the previous view. Returns True when a project
        was restored.
        """
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

    def _on_project_selected(self, project: TextbookProject) -> None:
        """(Re)build the embedded import + design panels for the project."""
        # Save the outgoing project's state before swapping panels.
        self._save_current_state()
        self._persist_ui_stage(self._current_stage())

        # Cancel in-flight AI work before deleting the panels that own it;
        # the worker keep-alive registry prevents a crash, but a cancelled
        # request stops burning tokens for a project the user just left.
        if self._design_panel is not None and self._design_panel._controller.is_busy:
            self._design_panel._controller.cancel()
        if self._panel is not None and self._panel._controller.is_busy:
            self._panel._controller.cancel()
        if self._panel is not None:
            self._panel.setParent(None)
            self._panel.deleteLater()
            self._panel = None
        if self._design_panel is not None:
            self._design_panel.cleanup_attachments()
            self._design_panel.setParent(None)
            self._design_panel.deleteLater()
            self._design_panel = None
        if self._review_panel is not None:
            self._review_panel.setParent(None)
            self._review_panel.deleteLater()
            self._review_panel = None
        self._busy_sources.clear()
        self._ws_progress.setVisible(False)
        self._ws_cancel_btn.setVisible(False)
        self._ws_stage_label.setText("")
        self._ws_usage_label.setText("")
        self._ws_autosave_label.setText("")

        self._project = project
        self._blank = project.source_path is None
        self._max_stage = 0
        self._imported_section_id = None
        self._locate_btn.setEnabled(False)

        if not self._blank:
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
            panel.design_requested.connect(lambda: self._go_to_stage(3))
            panel.busy_changed.connect(self._on_panel_busy)
            panel.stage_text_changed.connect(self._on_stage_text)
            panel.usage_changed.connect(self._on_usage_text)
            panel.autosave_saved.connect(self._on_autosaved)
            panel._stack.currentChanged.connect(
                lambda _idx: self._sync_max_stage()
            )
            self._panel = panel
            self._panel_layout.addWidget(panel)
            panel.show()

        from src.dialogs.ai.design_panel import DesignPanel

        self._design_panel = DesignPanel(self.adapter, self)
        self._design_panel.set_status_widgets_visible(False)
        self._design_panel.set_project(project, self._store)
        self._design_panel.sections_ready.connect(self._on_panel_sections_ready)
        self._design_panel.draft_ready.connect(self._on_draft_ready)
        self._design_panel.busy_changed.connect(self._on_design_busy)
        self._design_panel.usage_changed.connect(self._on_usage_text)
        self._design_layout.addWidget(self._design_panel)
        self._design_panel.show()

        from src.dialogs.ai.review_panel import ReviewPanel

        self._review_panel = ReviewPanel(self._design_panel, self.adapter, self)
        self._review_layout.addWidget(self._review_panel)
        self._review_panel.show()

        # A restored draft unlocks the review stage immediately.
        if self._design_panel.has_draft():
            self._max_stage = max(self._max_stage, 4)

        if self._blank:
            # 空白 AI 项目: no textbook stages — go straight to design.
            self._max_stage = max(self._max_stage, 3)
            self._stack.setCurrentIndex(2)
            self._update_nav()
            self._persist_ui_stage(3)
        else:
            self._stack.setCurrentIndex(1)
            self._sync_max_stage()
            # Restore the persisted stage (降级到当前可达范围内).
            target = project.ui_stage
            if target is None:
                target = self._current_stage()
            target = self._degrade_stage(int(target))
            self._go_to_stage(target)

        settings = QSettings("Varnamala", "CourseEditor")
        settings.setValue(_LAST_PROJECT_KEY, project.project_id)

    def _degrade_stage(self, target: int) -> int:
        """Clamp a restore target to the nearest reachable stage."""
        target = max(0, min(target, len(_STAGES) - 1))
        while target > 0 and (target > self._max_stage or not self._stage_available(target)):
            target -= 1
        return target

    def _sync_max_stage(self) -> None:
        if self._panel is not None:
            page = self._panel._stack.currentIndex()
            self._max_stage = max(
                self._max_stage, _MAX_STAGE_FOR_PANEL_PAGE.get(page, 1)
            )
        if self._design_panel is not None and self._design_panel.has_draft():
            self._max_stage = max(self._max_stage, 4)
        self._update_nav()

    def _on_draft_ready(self) -> None:
        self._sync_max_stage()
        self._ws_stage_label.setText("草稿已生成，可进入「审校」阶段")

    # ------------------------------------------------------------------ review
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
        """Route cancellation to whichever task is running (统一取消)."""
        if "design" in self._busy_sources and self._design_panel is not None:
            self._design_panel._controller.cancel()
        if "panel" in self._busy_sources and self._panel is not None:
            self._panel._controller.cancel()

    # ---------------------------------------------------------- persistence
    def _persist_ui_stage(self, stage: int) -> None:
        """Record the current stage on the project for exact restore."""
        if self._project is None:
            return
        if self._project.ui_stage == stage:
            return
        self._project.ui_stage = stage
        try:
            self._store.save_project(self._project)
        except Exception:
            pass  # stage bookkeeping must never break the flow

    def _save_current_state(self) -> None:
        """Autosave workshop-owned editable state.

        Only the design panel needs a nudge here: the embedded import
        controller already autosaves itself on every mutation, and forcing
        its ``_autosave`` would rewrite ``resource_pool.updated_at`` (breaking
        interrupt idempotence) and could clobber project fields edited
        outside the controller.
        """
        if self._design_panel is not None:
            self._design_panel._autosave()

    def interrupt_and_save(self) -> None:
        """Cancel in-flight work and persist everything (随时中断).

        Non-blocking and idempotent: safe to call on hide/close and from the
        main window's closeEvent. Completed chapters/drafts stay on disk.
        """
        if self._design_panel is not None and self._design_panel._controller.is_busy:
            self._design_panel._controller.cancel()
        if self._panel is not None and self._panel._controller.is_busy:
            self._panel._controller.cancel()
        # Persist any autosave state the throttle is still holding back.
        if self._panel is not None:
            self._panel._controller.flush_autosave()
        if self._design_panel is not None:
            self._design_panel.cleanup_attachments()
        self._busy_sources.clear()
        self._save_current_state()
        self._persist_ui_stage(self._current_stage())

    # ------------------------------------------------------------------ import
    def _on_panel_sections_ready(self, sections: list, strategy: str) -> None:
        self._sync_max_stage()
        self.sections_ready.emit(sections, strategy)

    def on_import_finished(self, section_id: str | None) -> None:
        """Called by MainWindow after the import pipeline ran."""
        if section_id:
            self._imported_section_id = section_id
            self._locate_btn.setEnabled(True)
            self._update_nav()  # refresh the 导入 ✓ mark

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
