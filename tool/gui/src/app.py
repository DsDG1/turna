"""Main window for the Turna GUI course editor."""
from __future__ import annotations

import time
from pathlib import Path

from PySide6.QtCore import QEvent, QObject, Qt, QSettings, QTimer
from PySide6.QtGui import QAction, QKeySequence, QUndoStack
from PySide6.QtWidgets import (
    QApplication,
    QDialog,
    QFileDialog,
    QLabel,
    QMainWindow,
    QMenu,
    QMessageBox,
    QPushButton,
    QSizePolicy,
    QSplitter,
    QStatusBar,
    QToolBar,
    QToolButton,
    QVBoxLayout,
    QWidget,
)

from src.application import runtime_context
from src.application.commands import (
    AiEditLessonCommand,
    AiEditUnitCommand,
    AppendLessonCommand,
    AppendLessonsToUnitCommand,
    AppendUnitCommand,
    AppendUnitsToSectionCommand,
    MergeAiSectionCommand,
)
from src.application.course_lifecycle import clear_experience_session, REASON_CLOSE_COURSE
from src.application.experience_shell import ExperienceShell, format_health_status_line
from src.application.settings import Settings, migrate_legacy_varnamala_qsettings
from src.application.experience_skills_mixin import ExperienceSkillsMixin
from src.backend.ai_generator import AiApiConfig
from src.backend.course_adapter import CourseAdapter
from src.backend.experience.conflict_guard import ConflictGuard
from src.backend.experience.metrics import ExperienceMetrics
from src.backend.experience.proactive import make_mute
from src.backend.import_step_result import ImportStepResult
from src.backend.import_strategy import ImportStrategy
from src.infrastructure.telemetry import telemetry
from src.theme import apply_theme, current_palette
from src.widgets.ambient_banner import AmbientBanner
from src.widgets.course_tree import CourseTreeWidget
from src.widgets.detail_panel import DetailPanel
from src.widgets.experience_dock import ExperienceDock
from src.widgets.job_tray import JobTray
import logging
logger = logging.getLogger(__name__)


def current_ai_config() -> AiApiConfig:
    """Current AI config, delegated to the runtime_context registry.

    Kept as a re-export point so existing callers (and tests) are unaffected.
    """
    return runtime_context.current_ai_config()


def current_settings() -> Settings:
    """Current settings, delegated to the runtime_context registry."""
    return runtime_context.current_settings()


class _ButtonSizePolicyFilter(QObject):
    """Keep every QPushButton wide enough to show its full text.

    QPushButton defaults to a Preferred horizontal size policy, so a tight
    layout can shrink it below its text width and clip the label. Switching
    to Minimum makes the text width the floor - the button grows to fit and
    never clips. Installed app-wide so every button (including ones created
    later) benefits.
    """

    def eventFilter(self, obj, event):  # noqa: N802
        if event.type() == QEvent.Type.Polish and isinstance(obj, QPushButton):
            sp = obj.sizePolicy()
            if sp.horizontalPolicy() != QSizePolicy.Policy.Minimum:
                sp.setHorizontalPolicy(QSizePolicy.Policy.Minimum)
                obj.setSizePolicy(sp)
        return False


class MainWindow(ExperienceSkillsMixin, QMainWindow):
    """Application main window: tree on the left, detail panel on the right."""

    def __init__(self) -> None:
        super().__init__()
        self.setWindowTitle("Turna 课程编辑器")
        self.resize(1280, 800)

        self.adapter = CourseAdapter()
        self.course_dir: Path | None = None
        self._current_node_ref: tuple[str, str] | None = None
        self.teacher_mode: bool = False
        self._workshop_window = None
        self._overview_window = None
        self._last_imported_section_id: str | None = None

        self._settings = QSettings("Turna", "CourseEditor")
        self._settings_obj = Settings.load_from_qsettings(self._settings)
        # One-shot migration from legacy "Varnamala" -> "Turna" namespace.
        # No-op when the new namespace already has keys.
        migrate_legacy_varnamala_qsettings()
        apply_theme(QApplication.instance(), self._settings_obj)

        # Keep button text from being clipped by tight layouts (applies to
        # every QPushButton app-wide, including ones created later).
        self._btn_size_filter = _ButtonSizePolicyFilter()
        QApplication.instance().installEventFilter(self._btn_size_filter)

        # AI API config is managed centrally via the Settings panel. Base URL
        # and model are persisted; the API key is memory-only and cleared on exit.
        self._ai_config = self._load_ai_config()
        # Live getters so lower layers read settings without importing src.app.
        # Lambdas (not snapshots) because _save_ai_config / Settings dialog rebind.
        runtime_context.set_providers(
            self,
            settings_fn=lambda: self._settings_obj,
            config_fn=lambda: self._ai_config,
        )
        self._apply_ai_cache()

        self.undo_stack = QUndoStack(self)
        self.undo_stack.setUndoLimit(self._settings_obj.undo_limit)
        self.undo_stack.cleanChanged.connect(self._on_undo_clean_changed)

        # Debounce timer for tree/overview refreshes (see _on_tree_changed).
        self._tree_refresh_timer = QTimer(self)
        self._tree_refresh_timer.setSingleShot(True)
        self._tree_refresh_timer.setInterval(250)
        self._tree_refresh_timer.timeout.connect(self._flush_tree_refresh)

        # Background interactive-save worker (see _save_course_async).
        self._save_worker = None

        self.experience_metrics = ExperienceMetrics()
        self.conflict_guard = ConflictGuard()
        self.experience = ExperienceShell(parent=self, debounce_ms=120)
        self.experience.context_changed.connect(self._on_experience_context_changed)
        self.experience_dock_widget = ExperienceDock(self)
        self.experience_dock_widget.suggestion_clicked.connect(self._on_experience_suggestion)
        self.experience_dock_widget.pin_toggled.connect(self._on_experience_pin_toggled)

        self._health_status_label = QLabel("未加载课程", self)
        self.experience.status_line_changed.connect(self._health_status_label.setText)

        self._shown_suggestion_keys: set[str] = set()
        self._ambient_archived: set[str] = set()
        self._defer_store = self._load_defer_store()
        self._ambient_mute = make_mute(self._load_experience_mute_dict())
        self._campaign_auto_offered_for: Any = None
        self._dispatch_action_id: str = ""
        self._experience_worker = None
        self._diagnose_worker = None
        self._presence_lock_widgets: list[Any] = []
        self._presence_mouse_filter = None
        self._presence_drive_seen: set[str] = set()
        self._presence_ai_busy: bool = False
        self._sovereign_entered_at = None
        self._gaze_overlay = None
        self._goal_last_plan = None
        self._goal_sandbox = None
        self._active_command_palette = None
        self._palette_llm_worker = None
        self._last_compare_report = None
        self._teacher_focused_item_id = None

        self._undo_detail_timer = QTimer(self)
        self._undo_detail_timer.setSingleShot(True)
        self._undo_detail_timer.setInterval(50)
        self._undo_detail_timer.timeout.connect(self._flush_undo_detail_refresh)
        self.undo_stack.indexChanged.connect(self._on_undo_index_changed)

        try:
            self.adapter.add_resource_listener(self._on_experience_resources_changed)
        except Exception:
            logger.debug("app.py: add_resource_listener best-effort failed", exc_info=True)

        self._build_toolbar()
        self._build_central()
        self._build_status_bar()
        self._build_undo_actions()
        self._import_service = self._make_import_service()
        from src.application.ai_edit_controller import AiEditController
        from src.application.ai_fix_controller import AiFixController
        from src.application.audio_controller import AudioController

        self._ai_edit_controller = AiEditController()
        self._ai_fix_controller = AiFixController()
        self._audio_controller = AudioController()
        self._usage_t0 = time.perf_counter()
        self._load_extraction_prompt_overrides()
        self._maybe_open_last_repo()

    def _make_import_service(self):
        """Build the shared section-import pipeline with UI callbacks wired."""
        from src.application.section_import_service import SectionImportService

        def _merge_resolver(plan):
            from src.dialogs.ai.ai_merge_preview_dialog import AiMergePreviewDialog

            preview = AiMergePreviewDialog(plan, parent=self)
            if preview.exec() != QDialog.DialogCode.Accepted:
                return None
            return preview.plan()

        def _bulk_merge_resolver(plans):
            from src.widgets.bulk_merge_resolve_panel import BulkMergeResolveDialog

            return BulkMergeResolveDialog.resolve(plans, parent=self)

        def _on_status(msg: str) -> None:
            # Resource notes are suffixes to the action message, not replacements.
            if msg.startswith("（"):
                self.statusBar().showMessage(
                    self.statusBar().currentMessage() + msg, 8000
                )
            else:
                self.statusBar().showMessage(msg, 8000)

        return SectionImportService(
            None,
            self.undo_stack,
            adapter_fn=lambda: self.adapter,
            show_error=lambda title, msg: QMessageBox.warning(self, title, msg),
            show_info=lambda title, msg: QMessageBox.information(self, title, msg),
            merge_resolver=_merge_resolver,
            bulk_merge_resolver=_bulk_merge_resolver,
            on_command_pushed=self._on_import_command_pushed,
            on_status=_on_status,
        )

    def _on_import_command_pushed(self, cmd, section_id: str) -> None:
        """Wire an import undo command to the tree and reveal the section."""
        cmd.signals.changed.connect(self.tree._on_command_changed)
        self.tree.select_section(section_id)

    def _load_extraction_prompt_overrides(self) -> None:
        """Load persisted extraction-prompt overrides into the default library."""
        try:
            from src.backend import knowledge_prompt
            from src.backend.ai_prompt_library import AiPromptLibrary

            knowledge_prompt.load_overrides_from(AiPromptLibrary(self._settings))
        except Exception:
            # Prompt overrides are an enhancement; never block startup.
            logger.debug("app.py:_load_extraction_prompt_overrides best-effort step failed", exc_info=True)

    def _build_undo_actions(self) -> None:
        self.undo_action = self.undo_stack.createUndoAction(self, "撤销")
        self.undo_action.setShortcut(QKeySequence.StandardKey.Undo)
        self.redo_action = self.undo_stack.createRedoAction(self, "重做")
        self.redo_action.setShortcut(QKeySequence.StandardKey.Redo)
        self.addAction(self.undo_action)
        self.addAction(self.redo_action)

    def _on_undo_clean_changed(self, clean: bool) -> None:
        if self.course_dir is not None:
            marker = "" if clean else " *"
            base = "Turna 课程编辑器"
            if self.teacher_mode:
                base += " · 教师模式"
            self.setWindowTitle(base + marker)

    def _build_toolbar(self) -> None:
        toolbar = QToolBar("main")
        toolbar.setMovable(False)
        toolbar.setToolButtonStyle(Qt.ToolButtonStyle.ToolButtonTextBesideIcon)
        self.addToolBar(toolbar)

        self.repo_menu_btn = QToolButton(self)
        self.repo_menu_btn.setText("课程仓库")
        self.repo_menu_btn.setPopupMode(QToolButton.ToolButtonPopupMode.InstantPopup)
        self.repo_menu = QMenu(self)
        self.repo_menu.addAction("新建课程目录…").triggered.connect(self._on_new_course)
        self.repo_menu.addAction("打开课程目录…").triggered.connect(self._on_open)
        self.repo_menu.addSeparator()
        self.recent_menu = QMenu("最近仓库", self)
        self.recent_menu.aboutToShow.connect(self._populate_recent_menu)
        self.repo_menu.addMenu(self.recent_menu)
        self.repo_menu.addAction("清除历史记录").triggered.connect(self._clear_recent_repos)
        self.repo_menu_btn.setMenu(self.repo_menu)
        toolbar.addWidget(self.repo_menu_btn)

        self.save_action = QAction("保存", self)
        self.save_action.setEnabled(False)
        self.save_action.triggered.connect(self._on_save)
        toolbar.addAction(self.save_action)

        toolbar.addSeparator()

        self.workshop_action = QAction("课程工坊", self)
        self.workshop_action.setEnabled(False)
        self.workshop_action.setToolTip("教材 → 知识 → 课程，一站式创作工作区")
        self.workshop_action.triggered.connect(self._on_workshop)
        toolbar.addAction(self.workshop_action)

        self.overview_action = QAction("总览", self)
        self.overview_action.setEnabled(False)
        self.overview_action.setToolTip("课程结构总览（Section / Unit / Lesson 鸟瞰，点击定位）")
        self.overview_action.triggered.connect(self._on_overview)
        toolbar.addAction(self.overview_action)

        self.resources_menu_btn = QToolButton(self)
        self.resources_menu_btn.setText("资源库")
        self.resources_menu_btn.setEnabled(False)
        self.resources_menu_btn.setPopupMode(QToolButton.ToolButtonPopupMode.InstantPopup)
        self.resources_menu = QMenu(self)
        self.resources_menu.addAction("本地资源").triggered.connect(self._on_resources)
        self.resources_menu.addAction("Git 资源库").triggered.connect(self._on_git_library)
        self.resources_menu_btn.setMenu(self.resources_menu)
        toolbar.addWidget(self.resources_menu_btn)

        self.publish_action = QAction("发布", self)
        self.publish_action.setEnabled(False)
        self.publish_action.triggered.connect(self._on_publish)
        toolbar.addAction(self.publish_action)

        self.generate_audio_action = QAction("生成听力音频", self)
        self.generate_audio_action.setEnabled(False)
        self.generate_audio_action.setToolTip(
            "扫描课程中的听力阶段，用 MiniMax TTS 生成 audioAsset 对应的 MP3"
        )
        self.generate_audio_action.triggered.connect(self._on_generate_audio)
        toolbar.addAction(self.generate_audio_action)

        toolbar.addSeparator()

        self.mode_action = QAction("教师模式", self)
        self.mode_action.setCheckable(True)
        self.mode_action.toggled.connect(self._on_mode_toggled)
        toolbar.addAction(self.mode_action)

        toolbar.addSeparator()

        self.settings_action = QAction("设置", self)
        self.settings_action.triggered.connect(self._on_settings)
        toolbar.addAction(self.settings_action)

    def _build_central(self) -> None:
        container = QWidget(self)
        root_layout = QVBoxLayout(container)
        root_layout.setContentsMargins(0, 0, 0, 0)
        root_layout.setSpacing(0)

        self.ambient_banner = AmbientBanner(container)
        self.ambient_banner.accepted.connect(self._on_ambient_accepted)
        self.ambient_banner.archived.connect(self._on_ambient_archived)
        self.ambient_banner.mute_changed.connect(self._on_ambient_mute_changed)
        root_layout.addWidget(self.ambient_banner)

        splitter = QSplitter(Qt.Horizontal)

        self.tree = CourseTreeWidget()
        self.tree.undo_stack = self.undo_stack
        self.tree.node_selected.connect(self._on_node_selected)
        self.tree.tree_changed.connect(self._on_tree_changed)
        self.tree.ai_edit_requested.connect(self._on_ai_edit)
        self.tree.ai_fix_requested.connect(self._on_ai_fix_from_tree)
        self.tree.rename_requested.connect(self._on_rename_requested)
        splitter.addWidget(self.tree.wrap_with_move_toolbar())

        self.detail = DetailPanel()
        self.detail.undo_stack = self.undo_stack
        self.detail.ai_config = self._ai_config
        # Detail edits change node labels without rebuilding the tree, so they
        # mark it stale; the tree's own tree_changed already rebuilt itself.
        self.detail.tree_changed.connect(self._on_detail_tree_changed)
        splitter.addWidget(self.detail)

        splitter.setStretchFactor(0, 2)
        splitter.setStretchFactor(1, 3)
        root_layout.addWidget(splitter, 1)
        self.setCentralWidget(container)

    def _build_status_bar(self) -> None:
        status = QStatusBar()
        status.setFixedHeight(28)

        self.job_tray = JobTray(self)
        self.job_tray.job_activated.connect(self._on_job_activated)
        status.addPermanentWidget(self.job_tray)

        self._health_status_label.setStyleSheet(
            f"color: {current_palette().get('text_secondary', '#888')}; font-size: 11px;"
        )
        status.addPermanentWidget(self._health_status_label)

        disclaimer = QLabel("AI 生成内容仅供参考，请作者自行审核其准确性与适用性。")
        disclaimer.setStyleSheet(
            f"color: {current_palette()['text_secondary']}; font-size: 11px;"
        )
        disclaimer.setToolTip(disclaimer.text())
        status.addPermanentWidget(disclaimer)
        self.setStatusBar(status)

    # --- Recent repository management ------------------------------------

    def _load_recent_repos(self) -> list[dict[str, str]]:
        return [dict(r) for r in self._settings_obj.recent_repos]

    def _add_recent_repo(self, path: Path) -> None:
        self._settings_obj.add_recent_repo(path)
        self._settings_obj.save_to_qsettings(self._settings)

    def _populate_recent_menu(self) -> None:
        self.recent_menu.clear()
        repos = self._load_recent_repos()
        if not repos:
            action = self.recent_menu.addAction("（无历史记录）")
            action.setEnabled(False)
            return
        for repo in repos:
            path = repo.get("path", "")
            action = self.recent_menu.addAction(path)
            action.setProperty("repo_path", path)
            action.triggered.connect(self._on_recent_repo_action_triggered)

    def _on_recent_repo_action_triggered(self) -> None:
        sender = self.sender()
        if not sender:
            return
        p = sender.property("repo_path")
        if isinstance(p, str):
            self._open_repo_path(p)

    def _clear_recent_repos(self) -> None:
        self._settings_obj.clear_recent_repos()
        self._settings_obj.save_to_qsettings(self._settings)

    def _load_ai_config(self) -> AiApiConfig:
        """Load AI API config from the central Settings object."""
        return AiApiConfig(
            base_url=self._settings_obj.ai_base_url,
            api_key=self._settings_obj.ai_api_key,
            model=self._settings_obj.ai_model,
            supports_reasoning=self._settings_obj.ai_supports_reasoning,
            model_chat=self._settings_obj.ai_model_chat,
            model_json=self._settings_obj.ai_model_json,
            strict_schema=self._settings_obj.ai_strict_schema,
        )

    def _save_ai_config(self, config: AiApiConfig) -> None:
        """Persist AI API config through the central Settings object."""
        self._settings_obj.ai_base_url = config.base_url
        self._settings_obj.ai_api_key = config.api_key
        self._settings_obj.ai_model = config.model
        self._settings_obj.ai_supports_reasoning = config.supports_reasoning
        self._settings_obj.save_to_qsettings(self._settings)

    def _apply_ai_cache(self) -> None:
        """第三枪 批次① Step 9: install/clear the process-wide AI cache.

        Called on startup and whenever the user toggles
        ``ai_cache_enabled`` in Settings. When disabled, the default cache is
        cleared so no stale entries survive a re-enable. Disk persistence is
        not enabled in this build (memory-only LRU); a future iteration can
        add a ``ai/cache_disk_dir`` setting.
        """
        from src.backend.ai_cache import AiCache, set_default_cache

        if self._settings_obj.ai_cache_enabled:
            set_default_cache(AiCache(maxsize=128, enabled=True))
        else:
            set_default_cache(None)

    def _maybe_open_last_repo(self) -> None:
        repos = self._load_recent_repos()
        if not repos:
            return
        last_path = repos[0].get("path", "")
        if not last_path or not Path(last_path).exists():
            return
        reply = QMessageBox.question(
            self,
            "打开最近仓库",
            f"是否打开上次使用的课程仓库？\n{last_path}",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
            QMessageBox.StandardButton.Yes,
        )
        if reply == QMessageBox.StandardButton.Yes:
            self._open_repo_path(last_path)

    def _open_repo_path(self, path_str: str) -> None:
        path = Path(path_str)
        if not path.exists() or not CourseAdapter.is_course_dir(path):
            QMessageBox.warning(self, "无法打开", f"目录不存在或不是有效的课程仓库：\n{path}")
            return
        try:
            self.adapter.load(path)
        except Exception as exc:
            telemetry.record_error(
                exc,
                context={"action": "repo.open", "path": str(path)},
            )
            self._show_load_error(str(exc))
            return
        self.course_dir = path
        self.tree.display(self.adapter)
        self.undo_stack.clear()
        self._enable_editor_actions()
        self._add_recent_repo(path)
        telemetry.record_event(
            "repo.open",
            payload={"path": str(path)},
        )
        self.statusBar().showMessage(f"已加载: {self.course_dir}", 4000)

    def _show_load_error(self, message: str) -> None:
        """Show a load error dialog with optional AI analysis."""
        from src.dialogs.ai_error_analyzer import offer_ai_analysis
        if offer_ai_analysis(self, "加载失败", message):
            import traceback

            from src.dialogs.ai_error_analyzer import AiErrorAnalyzerDialog

            AiErrorAnalyzerDialog(
                traceback.format_exc(),
                context={"action": "repo.open"},
                parent=self,
            ).exec()

    def _enable_editor_actions(self) -> None:
        self.save_action.setEnabled(True)
        self.workshop_action.setEnabled(True)
        self.overview_action.setEnabled(True)
        self.resources_menu_btn.setEnabled(True)
        self.publish_action.setEnabled(True)
        self.generate_audio_action.setEnabled(True)

    # --- Toolbar actions -------------------------------------------------

    def _on_new_course(self) -> None:
        from src.dialogs.init_course_dialog import InitCourseDialog

        dlg = InitCourseDialog(self.adapter, self)
        if not dlg.exec():
            telemetry.record_event("repo.new.cancelled")
            return
        init_dir = dlg.init_dir()
        if not init_dir:
            return
        self.course_dir = init_dir
        self.tree.display(self.adapter)
        self.undo_stack.clear()
        self._enable_editor_actions()
        self._add_recent_repo(init_dir)
        telemetry.record_event(
            "repo.new",
            payload={"course_dir": str(init_dir)},
        )
        self.statusBar().showMessage(f"已新建并加载: {init_dir}", 5000)

    def _on_open(self) -> None:
        start = str(self.course_dir) if self.course_dir else ""
        chosen = QFileDialog.getExistingDirectory(self, "选择课程目录", start)
        if not chosen:
            telemetry.record_event("repo.open.cancelled")
            return
        try:
            self.adapter.load(Path(chosen))
        except Exception as exc:
            telemetry.record_error(
                exc,
                context={"action": "repo.open", "path": chosen},
            )
            self._show_load_error(str(exc))
            return
        self.course_dir = Path(chosen)
        self.tree.display(self.adapter)
        self.undo_stack.clear()
        self._enable_editor_actions()
        self._add_recent_repo(self.course_dir)
        telemetry.record_event(
            "repo.open",
            payload={"path": str(self.course_dir)},
        )
        self.statusBar().showMessage(f"已加载: {self.course_dir}", 4000)

    def _on_mode_toggled(self, checked: bool) -> None:
        self.teacher_mode = checked
        self.mode_action.setText("教师模式：开" if checked else "教师模式")
        self.setWindowTitle(
            "Turna 课程编辑器 · 教师模式" if checked else "Turna 课程编辑器"
        )
        telemetry.record_event(
            "app.mode_changed",
            payload={"teacher_mode": checked},
        )
        self._apply_mode_shell()
        if checked:
            # Default to the first lesson so the authoring surface is never
            # empty when nothing (or a non-lesson node) is selected.
            if self._current_node_ref is None or self._current_node_ref[0] != "lesson":
                first = self._first_lesson_id()
                if first is not None:
                    self._current_node_ref = ("lesson", first)
        if self._current_node_ref is not None:
            self._on_node_selected(self._current_node_ref)
        self.statusBar().showMessage(
            "已切换到教师模式" if checked else "已切换到专家模式", 3000
        )

    def _first_lesson_id(self) -> str | None:
        """Return the id of the first lesson in tree order, or None."""
        if self.adapter is None:
            return None
        for section in self.adapter.sections:
            for unit in section.get("units", []):
                for lesson in unit.get("lessons", []):
                    return lesson.get("id")
        return None

    def _apply_mode_shell(self) -> None:
        """Reconfigure the shell for the active mode (tree badges, etc.)."""
        self.tree.set_teacher_mode(self.teacher_mode)

    def _on_settings(self) -> None:
        from src.dialogs.settings_dialog import SettingsDialog

        telemetry.record_event("settings.open")
        dlg = SettingsDialog(self._settings_obj, self)
        dlg.settings_changed.connect(self._on_settings_changed)
        dlg.exec()

    def _on_settings_changed(self) -> None:
        """Re-apply settings that can change at runtime."""
        self._settings_obj.save_to_qsettings(self._settings)
        self._ai_config = self._load_ai_config()
        self.detail.ai_config = self._ai_config
        self._apply_ai_cache()
        self.undo_stack.setUndoLimit(self._settings_obj.undo_limit)
        apply_theme(QApplication.instance(), self._settings_obj)
        self.statusBar().showMessage("设置已应用", 3000)

    def _import_section_dict(self, section: dict, strategy: str = ImportStrategy.MERGE.value) -> str:
        """Import (or merge) a section dict into the loaded course.

        Used by the AI edit flow. Validates
        the section (format-only, ids may intentionally collide), then dispatches
        on ``strategy``: append a new section (``ImportAiSectionCommand``), merge
        into an existing one (``AiMergePreviewDialog`` + ``MergeAiSectionCommand``),
        skip, force-replace (``AiEditSectionCommand``), or append-as-new with a
        fresh id. Pushes onto the undo stack, selects the section, and shows a
        status message.

        Returns one of: ``"imported"`` (new section appended), ``"merged"``
        (merged into an existing section), ``"skipped"`` (user cancelled the
        merge preview, or ``skip_existing`` strategy), ``"replaced"``
        (``force_replace`` overwrote an existing section), or ``"blocked"``
        (missing/invalid section or validation errors). Callers emit their own
        telemetry based on the outcome.
        """
        result = self._import_section_dict_result(section, strategy=strategy)
        return result.details.get("outcome", "blocked") if result.details else "blocked"

    def _import_section_dict_result(
        self,
        section: dict,
        *,
        strategy: str = ImportStrategy.MERGE.value,
    ) -> ImportStepResult:
        """Structured version of ``_import_section_dict``.

        Thin delegate over ``SectionImportService`` (connectplan P1-2); the
        pipeline itself lives in ``src/application/section_import_service.py``
        and is shared by the AI generator, textbook import, and workshop.
        """
        return self._import_service.import_section(section, strategy=strategy)

    def _show_beta_warning_once(self, key: str, title: str, message: str) -> None:
        """Show a one-time informational beta warning, remembered via QSettings."""
        if not self._settings.value(key, False):
            QMessageBox.information(self, title, message)
            self._settings.setValue(key, True)

    def _on_workshop(self) -> None:
        """Open the unified authoring workspace (connectplan Phase 2).

        The workshop is the single entry for course authoring: textbook
        import, grounded AI design, and from-scratch AI generation (blank
        projects) all live inside it. Opening it restores the last project
        at its persisted stage (随时中断、无限次恢复).
        """
        from src.dialogs.workshop_window import WorkshopWindow

        telemetry.record_event("workshop.open")
        self._show_beta_warning_once(
            "workshop_beta_warning_shown",
            "课程工坊",
            "课程工坊：从教材到课程一站式创作，AI 生成结果请自行审核。\n\n"
            "知识点提取与 AI 生成都可能消耗大量 token，建议模型支持 1M 上下文窗口。\n\n"
            "点击「确定」继续。",
        )

        if self._workshop_window is None:
            self._workshop_window = WorkshopWindow(self.adapter, self)
            self._workshop_window.sections_ready.connect(self._on_textbook_sections)
            self._workshop_window.locate_requested.connect(self._on_workshop_locate)
            self._workshop_window.restore_last_session()
        self._workshop_window.show()
        self._workshop_window.raise_()
        self._workshop_window.activateWindow()

    def _on_workshop_locate(self, section_id: str) -> None:
        """Reveal an imported section in the main course tree."""
        self.showNormal()
        self.raise_()
        self.activateWindow()
        self.tree.select_section(section_id)

    def _on_overview(self) -> None:
        """Open the course structure overview window (workshop2 P4)."""
        from src.widgets.course_overview import CourseOverviewWindow

        telemetry.record_event("overview.open")
        if self._overview_window is None:
            self._overview_window = CourseOverviewWindow(self.adapter, self)
            self._overview_window.lesson_selected.connect(self._on_overview_lesson_selected)
            self._overview_window.validation_requested.connect(self._on_overview_validation)
            self._overview_window.destroyed.connect(self._on_overview_destroyed)
        self._overview_window.refresh()
        self._overview_window.show()
        self._overview_window.raise_()
        self._overview_window.activateWindow()

    def _on_overview_lesson_selected(self, lesson_id: str) -> None:
        """Locate a lesson clicked in the overview inside the main tree."""
        self.showNormal()
        self.raise_()
        self.activateWindow()
        self.tree.select_lesson(lesson_id)

    def _on_overview_validation(self, problems: list) -> None:
        """Open the existing validation report with problems from the overview."""
        self._show_validation_report(problems, title="课程结构总览 - 校验结果")

    def _on_overview_destroyed(self, *_args) -> None:
        self._overview_window = None

    def _on_textbook_sections(self, sections: list, strategy: str) -> None:
        if not self.course_dir:
            QMessageBox.warning(self, "未加载课程目录", "请先打开课程目录。")
            return
        # Workshop "import into existing section/unit" modes (encoded in the
        # strategy string by ImportTargetDialog).
        if strategy.startswith("into_section:"):
            self._import_draft_into_section(sections[0], strategy.split(":", 1)[1])
            return
        if strategy.startswith("into_unit:"):
            self._import_draft_into_unit(sections[0], strategy.split(":", 1)[1])
            return
        results, counts = self._import_service.import_bulk(sections, strategy=strategy)
        successful = [
            (
                (r.details or {}).get("source_id", ""),
                (r.details or {}).get("section_id", ""),
            )
            for r in results
            if (r.details or {}).get("outcome") in ("imported", "merged", "replaced")
        ]
        summary = (
            f"导入完成：新增 {counts['imported']} 个，"
            f"合并 {counts['merged']} 个，"
            f"覆盖 {counts['replaced']} 个，"
            f"跳过 {counts['skipped']} 个，"
            f"失败 {counts['blocked']} 个。"
        )
        # Record the import back into the workshop's current project so the
        # library can show 已导入 (connectplan P0-2); import_map tracks where
        # each source id actually landed (P1-1). merge_from() preserves both
        # fields, so later autosaves cannot clobber them.
        project = (
            self._workshop_window.current_project()
            if self._workshop_window is not None
            else None
        )
        if project is not None and successful:
            from src.backend.textbook_project_store import record_imported_sections

            added = record_imported_sections(
                project,
                [final for _, final in successful],
                id_pairs=[(src, final) for src, final in successful if src],
            )
            if added:
                summary += "\n项目已记录导入状态。"
        if successful:
            self._last_imported_section_id = successful[-1][1]
            if self._workshop_window is not None:
                self._workshop_window.on_import_finished(
                    self._last_imported_section_id
                )
        QMessageBox.information(self, "导入教材", summary)
        if successful:
            self._offer_open_teacher_after_import(self._last_imported_section_id)

    def _offer_open_teacher_after_import(self, section_id: str | None) -> None:
        """After workshop import, optionally switch to teacher mode and locate.

        Skips the modal prompt when the main window is not visible (unit tests /
        headless automation) so batch imports never hang on QMessageBox.
        """
        if not section_id:
            return
        if not self.isVisible():
            return
        reply = QMessageBox.question(
            self,
            "导入完成",
            "要切换到教师模式并在课程树中定位该章节吗？",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
            QMessageBox.StandardButton.Yes,
        )
        if reply != QMessageBox.StandardButton.Yes:
            return
        if not self.teacher_mode:
            self.mode_action.setChecked(True)
            # toggled signal may already fire; ensure mode is applied
            if not self.teacher_mode:
                self._on_mode_toggled(True)
        self._on_workshop_locate(section_id)
        # Prefer first lesson under the section for teacher surface.
        try:
            section = self.adapter.find_section(section_id)
        except Exception:
            return
        for unit in section.get("units") or []:
            for lesson in unit.get("lessons") or []:
                lid = lesson.get("id")
                if lid:
                    self.tree.select_lesson(lid)
                    return

    def _import_draft_into_section(self, draft: dict, section_id: str) -> None:
        """Append the draft's units into an existing section as new units.

        Each unit is cloned with fresh ids (unit id + every lesson's structural
        ids) so it cannot collide with the existing course. The draft's
        top-level resources are merged (and rolled back on undo) so lesson
        references resolve.
        """
        from src.backend.lesson_content import clone_unit_with_fresh_ids

        try:
            section = self.adapter.find_section(section_id)
        except KeyError:
            QMessageBox.warning(self, "找不到目标", f"目标 Section「{section_id}」不存在。")
            return
        units = [u for u in draft.get("units") or [] if isinstance(u, dict)]
        if not units:
            QMessageBox.information(self, "无可导入内容", "草稿中没有 Unit。")
            return
        fresh_units = [
            clone_unit_with_fresh_ids(u, name=u.get("name", "新 Unit")) for u in units
        ]
        cmd = AppendUnitsToSectionCommand(
            self.adapter, section_id, fresh_units, resource_section=draft
        )
        cmd.signals.changed.connect(self._on_ai_edit_applied)
        self.undo_stack.push(cmd)
        self.tree.refresh_incremental()
        self.adapter.notify_resources_changed()
        self.statusBar().showMessage(
            f"已把 {len(fresh_units)} 个 Unit 追加到「{section.get('name', section_id)}」，记得保存",
            8000,
        )
        self._record_draft_import(draft, section_id)
        if self._workshop_window is not None:
            self._workshop_window.on_import_finished(section_id)
        self._offer_open_teacher_after_import(section_id)

    def _record_draft_import(self, draft: dict, section_id: str | None) -> None:
        """Persist a workshop draft-import back into the project so the
        workshop's 已导入 checklist mark and locate button survive a close +
        reopen (mirrors the bulk-import path in _on_textbook_sections)."""
        if not section_id:
            return
        project = (
            self._workshop_window.current_project()
            if self._workshop_window is not None
            else None
        )
        if project is None:
            return
        from src.backend.textbook_project_store import record_imported_sections

        source_id = draft.get("id", "") if isinstance(draft, dict) else ""
        record_imported_sections(
            project,
            [section_id],
            id_pairs=[(source_id, section_id)] if source_id else None,
        )

    def _import_draft_into_unit(self, draft: dict, unit_id: str) -> None:
        """Append the draft's lessons into an existing unit as new lessons.

        Each lesson is cloned with fresh ids so it cannot collide with the
        existing course. The draft's top-level resources are merged (and
        rolled back on undo) so lesson references resolve.
        """
        from src.backend.lesson_content import clone_lesson_with_fresh_ids

        try:
            _s, unit = self.adapter.find_unit(unit_id)
        except KeyError:
            QMessageBox.warning(self, "找不到目标", f"目标 Unit「{unit_id}」不存在。")
            return
        lessons = [
            lesson
            for u in draft.get("units") or []
            if isinstance(u, dict)
            for lesson in u.get("lessons") or []
            if isinstance(lesson, dict)
        ]
        if not lessons:
            QMessageBox.information(self, "无可导入内容", "草稿中没有 Lesson。")
            return
        fresh_lessons = [
            clone_lesson_with_fresh_ids(lesson, name=lesson.get("name", "新 Lesson"))
            for lesson in lessons
        ]
        for lesson in fresh_lessons:
            lesson["prerequisiteLessonIds"] = []
        cmd = AppendLessonsToUnitCommand(
            self.adapter, unit_id, fresh_lessons, resource_section=draft
        )
        cmd.signals.changed.connect(self._on_ai_edit_applied)
        self.undo_stack.push(cmd)
        self.tree.refresh_incremental()
        self.adapter.notify_resources_changed()
        self.statusBar().showMessage(
            f"已把 {len(fresh_lessons)} 个 Lesson 追加到「{unit.get('name', unit_id)}」，记得保存",
            8000,
        )
        section_id = _s.get("id") if isinstance(_s, dict) else None
        self._record_draft_import(draft, section_id)
        if section_id and self._workshop_window is not None:
            self._workshop_window.on_import_finished(section_id)
        if section_id:
            self._offer_open_teacher_after_import(section_id)

    def _validate_node(self, kind: str, node_json: dict, *, check_existing_ids: bool = True) -> list[dict]:
        """Validate a section/unit/lesson node by wrapping it in a temp section."""
        if kind == "section":
            return self.adapter.validate_section_json(node_json, check_existing_ids=check_existing_ids)
        if kind == "unit":
            wrapper = {"id": "temp", "name": "temp", "units": [node_json]}
        elif kind == "lesson":
            wrapper = {"id": "temp", "name": "temp", "units": [{"id": "temp", "lessons": [node_json]}]}
        else:
            return []
        return self.adapter.validate_section_json(wrapper, check_existing_ids=check_existing_ids)

    def _on_ai_edit(self, kind: str, node_id: str) -> None:
        self._ai_edit_controller.handle_ai_edit(self, kind, node_id)

    def _detect_ai_edit_conflicts(
        self, kind: str, node_id: str, new_node: dict
    ) -> list[tuple[str, str, str]]:
        return self._ai_edit_controller.detect_conflicts(
            self.adapter, kind, node_id, new_node
        )

    def _ask_ai_edit_conflict_resolution(
        self, kind: str, conflicts: list[tuple[str, str, str]]
    ) -> str:
        return self._ai_edit_controller.ask_conflict_resolution(self, kind, conflicts)

    def _on_ai_edit_applied(self) -> None:
        self.tree.refresh_incremental()
        self.tree.tree_changed.emit()
        if self._current_node_ref is not None:
            self._on_node_selected(self._current_node_ref)

    def _on_ai_fix_from_tree(self, kind: str, node_id: str) -> None:
        """Handle AI fix request from the course tree context menu."""
        self._ai_fix_controller.handle_ai_fix_from_tree(self, kind, node_id)

    @staticmethod
    def _extract_unit(new_section: dict, unit_id: str) -> dict | None:
        from src.application.ai_edit_controller import AiEditController

        return AiEditController.extract_unit(new_section, unit_id)

    @staticmethod
    def _extract_lesson(new_section: dict, lesson_id: str) -> dict | None:
        from src.application.ai_edit_controller import AiEditController

        return AiEditController.extract_lesson(new_section, lesson_id)

    def _on_node_selected(self, node_ref: tuple[str, str]) -> None:
        self._current_node_ref = node_ref
        if self.course_dir is None:
            return
        if self.teacher_mode:
            # Teacher mode renders the lesson authoring surface inline in the
            # right detail pane (single teacher surface; no separate window).
            if node_ref[0] == "lesson":
                try:
                    section, unit, lesson = self.adapter.find_lesson(node_ref[1])
                except KeyError:
                    self.detail.show_node(self.adapter, node_ref)
                    return
                self.detail.show_teacher_lesson(self.adapter, section, unit, lesson)
            else:
                self.detail.show_node(self.adapter, node_ref)
        else:
            self.detail.show_node(self.adapter, node_ref)

    def _on_rename_requested(self, kind: str, node_id: str) -> None:
        """F2: focus the name field of the currently-shown node."""
        # Ensure the detail panel is showing the node being renamed.
        if self._current_node_ref != (kind, node_id):
            self._on_node_selected((kind, node_id))
        self.detail.form.focus_name()

    def _on_tree_changed(self) -> None:
        # Debounce: teacher-view keystrokes and command bursts emit this
        # per change; collapsing to one rebuild per quiet window avoids an
        # O(tree) widget churn on every character.
        self._tree_refresh_timer.start()

    def _on_detail_tree_changed(self) -> None:
        # Form edits mutate node data (names shown in the tree) without a
        # tree rebuild, so the widget is stale until the debounced flush.
        self.tree.mark_stale()
        self._tree_refresh_timer.start()

    def _flush_tree_refresh(self) -> None:
        # Command paths already rebuilt the tree in
        # CourseTreeWidget._on_command_changed(); refresh only when detail-side
        # edits marked it stale, instead of always paying a second full rebuild.
        self.tree.refresh_if_stale()
        # Keep the overview window in sync if it is visible.
        if self._overview_window is not None and self._overview_window.isVisible():
            self._overview_window.refresh()

    def _on_resources(self) -> None:
        telemetry.record_event("resources.open", payload={"teacher_mode": self.teacher_mode})
        if self.teacher_mode:
            from PySide6.QtWidgets import QDialog, QDialogButtonBox

            from src.teacher.vocab_table import VocabTableWidget

            dlg = QDialog(self)
            dlg.setWindowTitle("词库")
            dlg.resize(760, 520)
            table = VocabTableWidget(self.adapter, dlg)
            buttons = QDialogButtonBox(QDialogButtonBox.StandardButton.Close)
            buttons.rejected.connect(dlg.reject)
            layout = QVBoxLayout(dlg)
            layout.addWidget(table)
            layout.addWidget(buttons)
            dlg.exec()
            if table.is_dirty():
                self.statusBar().showMessage("词库已修改，记得保存", 5000)
            return
        from PySide6.QtWidgets import QDialog, QDialogButtonBox

        from src.widgets.resource_editor import ResourceEditorDialog

        dlg = QDialog(self)
        dlg.setWindowTitle("资源编辑")
        dlg.resize(900, 560)
        editor = ResourceEditorDialog(self.adapter, dlg)
        buttons = QDialogButtonBox(QDialogButtonBox.StandardButton.Close)
        buttons.rejected.connect(dlg.reject)
        layout = QVBoxLayout(dlg)
        layout.addWidget(editor)
        layout.addWidget(buttons)
        dlg.exec()

        if editor.is_dirty():
            self.statusBar().showMessage("资源已修改，记得保存", 5000)

    def _on_git_library(self) -> None:
        from src.dialogs.git_library_dialog import GitLibraryDialog

        telemetry.record_event("git_library.open")
        dlg = GitLibraryDialog(self.adapter, self, settings=self._settings_obj)
        dlg.open_requested.connect(self._open_repo_path)
        dlg.exec()
        # After the dialog closes, if a clone dir was opened, reflect it.
        clone = dlg.clone_dir()
        if clone is not None and self.course_dir == clone:
            self.statusBar().showMessage(f"已从 Git 资源库加载: {clone}", 5000)

    def _on_publish(self) -> None:
        from src.widgets.publish_dialog import PublishDialog

        telemetry.record_event("publish.open", payload={"teacher_mode": self.teacher_mode})
        dlg = PublishDialog(self.adapter, self, teacher_friendly=self.teacher_mode)
        if dlg.exec():
            self.tree.refresh()
            if not self.teacher_mode and self._current_node_ref is not None:
                self.detail.show_node(self.adapter, self._current_node_ref)
            self.statusBar().showMessage("发布成功", 5000)

    def _on_generate_audio(self) -> None:
        """Generate listening-lesson audio (MiniMax TTS) for the loaded course."""
        self._audio_controller.handle_generate_audio(self)

    def _on_save(self, *, reason: str = "menu") -> None:
        telemetry.record_event("repo.save.triggered", payload={"reason": reason})
        self._save_course_async()

    def _save_course_async(self) -> None:
        """Run adapter.save() on a background worker (interactive saves).

        The full save chain (temp-dir write + validate + backup + file replace
        + snapshot + lint) used to run on the UI thread, freezing the window
        for hundreds of ms on large courses. It now runs on an
        AiRequestWorker. Structural edits are frozen for the duration: the
        save thread iterates the in-memory model, and blocking input keeps the
        same data-safety guarantee the old synchronous freeze provided, while
        the UI thread stays responsive (status bar, window dragging).
        """
        from src.dialogs.ai.worker import AiRequestWorker

        prev = getattr(self, "_save_worker", None)
        if prev is not None and prev.isRunning():
            self.statusBar().showMessage("正在保存…", 2000)
            return
        if self.adapter is None:
            return

        self.save_action.setEnabled(False)
        self.centralWidget().setEnabled(False)
        self.statusBar().showMessage("保存中…")

        worker = AiRequestWorker(self.adapter.save)

        def _unfreeze() -> None:
            self.save_action.setEnabled(True)
            self.centralWidget().setEnabled(True)
            self._save_worker = None

        def _on_result(result) -> None:
            _unfreeze()
            self.tree.refresh()
            if result.ok:
                self.undo_stack.setClean()
                self.statusBar().showMessage(result.message or "保存成功", 5000)
            else:
                self.statusBar().showMessage(result.message or "保存失败（已回滚）", 8000)
                if result.errors:
                    self._show_validation_report(result.errors, title="校验失败（已回滚）")

        def _on_error(message: str) -> None:
            _unfreeze()
            self.statusBar().showMessage(f"保存失败：{message}", 8000)

        worker.result_ready.connect(_on_result)
        worker.error_occurred.connect(_on_error)
        self._save_worker = worker
        worker.start()

    def _show_validation_report(
        self, problems: list[dict], title: str = "校验结果"
    ) -> None:
        """Show a non-modal validation report panel with double-click-to-jump."""
        from PySide6.QtWidgets import QDialog, QDialogButtonBox, QVBoxLayout

        from src.widgets.validation_report import ValidationReportWidget

        dlg = QDialog(self)
        dlg.setWindowTitle(title)
        dlg.resize(640, 420)
        report = ValidationReportWidget(self.adapter, dlg)
        report.show_problems(problems)
        report.jump_to.connect(self._jump_to_node)
        # Single-select uses legacy signal; multi-select uses batch (widget
        # emits exactly one of the two per click).
        report.ai_fix_requested.connect(self._on_ai_fix_requested)
        report.ai_batch_fix_requested.connect(self._on_ai_batch_fix_requested)
        buttons = QDialogButtonBox(QDialogButtonBox.StandardButton.Close)
        buttons.rejected.connect(dlg.reject)
        layout = QVBoxLayout(dlg)
        layout.addWidget(report)
        layout.addWidget(buttons)
        dlg.setModal(False)
        dlg.show()

    def _on_ai_fix_requested(
        self, problem: dict[str, Any], node_ref: tuple[str, str] | None
    ) -> None:
        """Handle single AI auto-fix request (legacy signal)."""
        if node_ref is None:
            return
        self._run_ai_fix_batch([(problem, node_ref)])

    def _on_ai_batch_fix_requested(self, pairs: list) -> None:
        """Handle multi-select AI fix from ValidationReport (U1-2)."""
        if not pairs:
            return
        self._run_ai_fix_batch(list(pairs))

    def _run_ai_fix_batch(
        self,
        pairs: list[tuple[dict[str, Any], tuple[str, str] | None]],
    ) -> None:
        """Group problems by node and run AiFixDialog once per node (sequential)."""
        self._ai_fix_controller.run_ai_fix_batch(self, pairs)

    def _apply_ai_fix_for_node(
        self,
        kind: str,
        node_id: str,
        problems: list[dict[str, Any]],
    ) -> bool:
        """Run one AiFixDialog + merge for a single node. Returns True if applied."""
        return self._ai_fix_controller.apply_ai_fix_for_node(
            self, kind, node_id, problems
        )

    def _jump_to_node(self, node_ref: tuple[str, str]) -> None:
        kind, node_id = node_ref
        if kind == "lesson":
            self.tree.select_lesson(node_id)
        elif kind == "section":
            self.tree.select_section(node_id)
        elif kind == "unit":
            self.tree.select_unit(node_id)

    def _clear_ai_key_on_exit(self) -> None:
        """Wipe the API key from memory and storage when the window closes.

        Base URL and model are preserved for the next session, but the API key
        is intentionally ephemeral.
        """
        self._ai_config.api_key = ""
        self._settings_obj.ai_api_key = ""
        self._settings_obj.save_to_qsettings(self._settings)

    def closeEvent(self, event) -> None:  # noqa: N802
        telemetry.record_event("app.close_requested")
        # Wait out an in-flight background save so the save thread never
        # races shutdown (equivalent to the old synchronous save on close).
        save_worker = getattr(self, "_save_worker", None)
        if save_worker is not None and save_worker.isRunning():
            save_worker.wait()
        if self.course_dir and self.adapter and any(self.adapter.detect_changes().values()):
            if self._settings_obj.auto_save_on_close:
                result = self.adapter.save()
                if result.ok:
                    telemetry.record_event("app.close_saved")
                    event.accept()
                else:
                    event.ignore()
                    detail_text = "\n".join(
                        f"[{e.get('level', 'error')}] {e.get('message', '')}"
                        for e in result.errors
                    )
                    QMessageBox.warning(
                        self,
                        "自动保存失败（窗口未关闭）",
                        detail_text or result.message or "未知错误",
                    )
                # Fall through to the shared teardown below on success.

            else:
                reply = QMessageBox.question(
                    self,
                    "未保存的更改",
                    "当前课程有未保存的更改，是否保存？",
                    (
                        QMessageBox.StandardButton.Save
                        | QMessageBox.StandardButton.Discard
                        | QMessageBox.StandardButton.Cancel
                    ),
                    QMessageBox.StandardButton.Save,
                )
                if reply == QMessageBox.StandardButton.Save:
                    result = self.adapter.save()
                    if result.ok:
                        telemetry.record_event("app.close_saved")
                        event.accept()
                    else:
                        event.ignore()
                        detail_text = "\n".join(
                            f"[{e.get('level', 'error')}] {e.get('message', '')}"
                            for e in result.errors
                        )
                        QMessageBox.warning(
                            self,
                            "保存失败（窗口未关闭）",
                            detail_text or result.message or "未知错误",
                        )
                elif reply == QMessageBox.StandardButton.Discard:
                    telemetry.record_event("app.close_discarded")
                    event.accept()
                else:
                    telemetry.record_event("app.close_cancelled")
                    event.ignore()
        else:
            event.accept()

        if event.isAccepted():
            # Persist and tear down the workshop so no authoring state is
            # lost and the window does not dangle (随时中断、无限次恢复).
            if self._workshop_window is not None:
                self._workshop_window.interrupt_and_save()
                self._workshop_window.close()
                self._workshop_window = None
            if self._overview_window is not None:
                self._overview_window.close()
                self._overview_window = None
            runtime_context.clear_providers(self)
            self._clear_ai_key_on_exit()
            self._record_window_duration()

    def _record_window_duration(
        self, name: str = "MainWindow", duration_s: float | None = None, **payload
    ) -> None:
        try:
            from src.infrastructure.operations_log import operations

            if duration_s is not None:
                telemetry.record_event(
                    f"window.{name}.duration", duration_s=duration_s, **payload
                )
                return

            start = getattr(self, "_usage_t0", None)
            if start:
                operations.record_duration(
                    "window.duration",
                    (time.perf_counter() - start) * 1000.0,
                    payload={"window": name},
                )
                operations.record_action("window.close", name)
        except Exception:
            logger.debug("app.py:_record_window_duration best-effort step failed", exc_info=True)

    def _on_undo_index_changed(self, _idx: int) -> None:
        self._undo_detail_timer.start()

    def _flush_undo_detail_refresh(self) -> None:
        self._undo_detail_timer.stop()
        if self._current_node_ref and self.adapter:
            if hasattr(self, "detail") and self.detail is not None:
                self.detail.show_node(self.adapter, self._current_node_ref)

    def _on_job_activated(self, job_id: str) -> None:
        if not hasattr(self, "job_tray") or self.job_tray is None:
            return
        job = self.job_tray.registry.get(job_id)
        if job is None:
            self.statusBar().showMessage(f"任务未找到：{job_id}", 4000)
            return
        node_key = getattr(job, "node_key", "") or ""
        if not node_key:
            self.statusBar().showMessage(f"任务无对应节点：{job.label or job_id}", 4000)
            return
        if node_key.startswith("section:"):
            sec_id = node_key[len("section:"):]
            self.tree.select_section(sec_id)
        elif node_key.startswith("lesson:"):
            les_id = node_key[len("lesson:"):]
            self.tree.select_lesson(les_id)
        elif node_key.startswith("unit:"):
            unit_id = node_key[len("unit:"):]
            if hasattr(self.tree, "select_unit"):
                self.tree.select_unit(unit_id)

    def _sync_focus_ring(self) -> None:
        if not hasattr(self, "focus_ring") or self.focus_ring is None:
            return
        self.focus_ring.clear_roles("selected", "pinned")
        if self._current_node_ref:
            kind, nid = self._current_node_ref
            self.focus_ring.set(f"{kind}:{nid}", "selected")
        if hasattr(self, "experience") and self.experience is not None:
            for pref in getattr(self.experience, "pinned_refs", []):
                if isinstance(pref, tuple) and len(pref) == 2:
                    self.focus_ring.set(f"{pref[0]}:{pref[1]}", "pinned")

    def _on_experience_context_changed(self, ctx) -> None:
        if hasattr(self, "experience_dock_widget") and self.experience_dock_widget is not None:
            sugs = getattr(self.experience, "suggestions", []) if hasattr(self, "experience") else []
            self.experience_dock_widget.apply_context_and_suggestions(ctx, sugs)
        if hasattr(self, "_refresh_ambient"):
            self._refresh_ambient()

    def _on_experience_pin_toggled(self) -> None:
        if hasattr(self, "experience") and self.experience is not None:
            self.experience.toggle_pin_selection()
            self._sync_focus_ring()
            self._refresh_experience(immediate=False, focus_only=True)

    def _refresh_experience(self, *, immediate: bool = False, focus_only: bool = False) -> None:
        if self.course_dir is None:
            clear_experience_session(self, reason=REASON_CLOSE_COURSE)
            if hasattr(self, "_health_status_label"):
                self._health_status_label.setText(format_health_status_line(None))
            return

        if hasattr(self, "experience") and self.experience is not None:
            self.experience.set_adapter(self.adapter)
            if hasattr(self, "job_tray") and self.job_tray is not None:
                self.experience.set_active_jobs(self.job_tray.active_jobs())
            if hasattr(self, "_current_node_ref"):
                self.experience.set_selection(self._current_node_ref)
            if focus_only:
                self.experience.invalidate_focus()
            else:
                if immediate:
                    self.experience.rebuild_now()
                else:
                    self.experience.invalidate()

    def _on_experience_resources_changed(self) -> None:
        if hasattr(self, "experience") and self.experience is not None:
            self.experience.mark_stale()

    def _flush_experience_metrics(self, reason: str = "", *, course_dir: Any = None) -> None:
        metrics = getattr(self, "experience_metrics", None)
        if metrics is not None and hasattr(metrics, "snapshot"):
            snap = metrics.snapshot()
            telemetry.record_event(
                "experience.metrics_flush",
                reason=reason,
                course_dir=str(course_dir or self.course_dir or ""),
                **snap,
            )

    def _record_experience_event(self, event_name: str, label: str = "", **payload) -> None:
        try:
            telemetry.record_event(event_name, label=label, **payload)
        except Exception:
            logger.debug("MainWindow._record_experience_event best-effort failed", exc_info=True)

    def _on_workshop_ocr_requested(
        self, path: str, original_name: str, unlink_after: bool = False
    ) -> None:
        from src.application.workshop_controller import on_workshop_ocr_requested

        on_workshop_ocr_requested(self, path, original_name, unlink_after)

    def _on_undo_index_changed(self, idx: int = 0) -> None:
        if hasattr(self, "_undo_detail_timer"):
            self._undo_detail_timer.start()

    def _flush_undo_detail_refresh(self) -> None:
        if hasattr(self, "_undo_detail_timer") and self._undo_detail_timer.isActive():
            self._undo_detail_timer.stop()
        if getattr(self, "_current_node_ref", None) and getattr(self, "course_dir", None):
            self._on_node_selected(self._current_node_ref)
