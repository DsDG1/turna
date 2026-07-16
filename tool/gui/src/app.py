"""Main window for the Varnamala GUI course editor."""
from __future__ import annotations

import time
from pathlib import Path

from PySide6.QtCore import Qt, QSettings
from PySide6.QtGui import QAction, QKeySequence, QUndoStack
from PySide6.QtWidgets import (
    QApplication,
    QDialog,
    QFileDialog,
    QHBoxLayout,
    QLabel,
    QMainWindow,
    QMenu,
    QMessageBox,
    QSplitter,
    QStatusBar,
    QToolBar,
    QToolButton,
    QVBoxLayout,
    QWidget,
)

from src.application.commands import (
    AiEditLessonCommand,
    AiEditSectionCommand,
    AiEditUnitCommand,
    AppendLessonCommand,
    ImportAiSectionCommand,
    MergeAiSectionCommand,
)
from src.application.settings import Settings
from src.backend.ai_generator import AiApiConfig
from src.backend.course_adapter import CourseAdapter
from src.backend.import_step_result import ImportStepResult
from src.backend.import_strategy import (
    ImportStrategy,
    plan_bulk_import,
    resolve_action,
    unique_section_id,
)
from src.infrastructure.telemetry import telemetry
from src.theme import apply_theme
from src.widgets.course_tree import CourseTreeWidget
from src.widgets.detail_panel import DetailPanel


def current_ai_config() -> AiApiConfig:
    """Return the current AI config from the active MainWindow.

    Dialogs that need AI configuration should call this helper instead of
    maintaining their own input fields. Returns an empty config if no main
    window is present (e.g. during tests).
    """
    app = QApplication.instance()
    if app is None:
        return AiApiConfig()
    for widget in app.topLevelWidgets():
        if isinstance(widget, MainWindow):
            return widget._ai_config
    return AiApiConfig()


def current_settings() -> Settings:
    """Return the current Settings from the active MainWindow.

    Mirrors ``current_ai_config`` for non-AI preferences (e.g. the AI retry
    limit). Returns a default ``Settings`` instance when no main window is
    present (tests / sandbox).
    """
    app = QApplication.instance()
    if app is None:
        return Settings()
    for widget in app.topLevelWidgets():
        if isinstance(widget, MainWindow):
            return widget._settings_obj
    return Settings()


class MainWindow(QMainWindow):
    """Application main window: tree on the left, detail panel on the right."""

    def __init__(self) -> None:
        super().__init__()
        self.setWindowTitle("Varnamala 课程编辑器")
        self.resize(1280, 800)

        self.adapter = CourseAdapter()
        self.course_dir: Path | None = None
        self._current_node_ref: tuple[str, str] | None = None
        self.teacher_mode: bool = False
        self._teacher_window = None

        self._settings = QSettings("Varnamala", "CourseEditor")
        self._settings_obj = Settings.load_from_qsettings(self._settings)
        apply_theme(QApplication.instance(), self._settings_obj)

        # AI API config is managed centrally via the Settings panel. Base URL
        # and model are persisted; the API key is memory-only and cleared on exit.
        self._ai_config = self._load_ai_config()

        self.undo_stack = QUndoStack(self)
        self.undo_stack.setUndoLimit(self._settings_obj.undo_limit)
        self.undo_stack.cleanChanged.connect(self._on_undo_clean_changed)

        self._build_toolbar()
        self._build_central()
        self._build_status_bar()
        self._build_undo_actions()
        self._usage_t0 = time.perf_counter()
        self._maybe_open_last_repo()

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
            base = "Varnamala 课程编辑器"
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

        self.ai_action = QAction("AI 生成课程（Beta）", self)
        self.ai_action.setEnabled(False)
        self.ai_action.triggered.connect(self._on_ai_generate)
        toolbar.addAction(self.ai_action)

        self.textbook_action = QAction("导入教材（Beta）", self)
        self.textbook_action.setEnabled(False)
        self.textbook_action.triggered.connect(self._on_textbook_import)
        toolbar.addAction(self.textbook_action)

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
        splitter = QSplitter(Qt.Horizontal)

        self.tree = CourseTreeWidget()
        self.tree.undo_stack = self.undo_stack
        self.tree.node_selected.connect(self._on_node_selected)
        self.tree.tree_changed.connect(self._on_tree_changed)
        self.tree.ai_edit_requested.connect(self._on_ai_edit)
        self.tree.ai_fix_requested.connect(self._on_ai_fix_from_tree)
        splitter.addWidget(self.tree.wrap_with_move_toolbar())

        self.detail = DetailPanel()
        self.detail.undo_stack = self.undo_stack
        self.detail.ai_config = self._ai_config
        self.detail.tree_changed.connect(self._on_tree_changed)
        splitter.addWidget(self.detail)

        splitter.setStretchFactor(0, 2)
        splitter.setStretchFactor(1, 3)
        self.setCentralWidget(splitter)

    def _build_status_bar(self) -> None:
        status = QStatusBar()
        status.setFixedHeight(28)
        disclaimer = QLabel("AI 生成内容仅供参考，请作者自行审核其准确性与适用性。")
        disclaimer.setStyleSheet("color: #9CA3AF; font-size: 11px;")
        disclaimer.setToolTip(disclaimer.text())
        status.addPermanentWidget(disclaimer)
        self.setStatusBar(status)

    # --- Recent repository management ------------------------------------

    def _load_recent_repos(self) -> list[dict[str, str]]:
        return [dict(r) for r in self._settings_obj.recent_repos]

    def _save_recent_repos(self, repos: list[dict[str, str]]) -> None:
        self._settings_obj.recent_repos = [dict(r) for r in repos]
        self._settings_obj.save_to_qsettings(self._settings)

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
            action.triggered.connect(lambda checked=False, p=path: self._open_repo_path(p))

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
        )

    def _save_ai_config(self, config: AiApiConfig) -> None:
        """Persist AI API config through the central Settings object."""
        self._settings_obj.ai_base_url = config.base_url
        self._settings_obj.ai_api_key = config.api_key
        self._settings_obj.ai_model = config.model
        self._settings_obj.ai_supports_reasoning = config.supports_reasoning
        self._settings_obj.save_to_qsettings(self._settings)

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
        msg = QMessageBox(self)
        msg.setIcon(QMessageBox.Icon.Critical)
        msg.setWindowTitle("加载失败")
        msg.setText(message)
        msg.addButton("确定", QMessageBox.ButtonRole.AcceptRole)
        analyze_btn = msg.addButton("AI 分析原因", QMessageBox.ButtonRole.ActionRole)
        msg.exec()
        if msg.clickedButton() == analyze_btn:
            import traceback

            from src.dialogs.ai_error_analyzer import AiErrorAnalyzerDialog

            AiErrorAnalyzerDialog(
                traceback.format_exc(),
                context={"action": "repo.open"},
                parent=self,
            ).exec()

    def _enable_editor_actions(self) -> None:
        self.save_action.setEnabled(True)
        self.ai_action.setEnabled(True)
        self.textbook_action.setEnabled(True)
        self.resources_menu_btn.setEnabled(True)
        self.publish_action.setEnabled(True)

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
            "Varnamala 课程编辑器 · 教师模式" if checked else "Varnamala 课程编辑器"
        )
        telemetry.record_event(
            "app.mode_changed",
            payload={"teacher_mode": checked},
        )
        if checked:
            self._open_teacher_window()
        else:
            self._close_teacher_window()
        if self._current_node_ref is not None:
            self._on_node_selected(self._current_node_ref)
        self.statusBar().showMessage(
            "已切换到教师模式" if checked else "已切换到专家模式", 3000
        )

    def _open_teacher_window(self) -> None:
        """Proactively pop up the independent teacher window (Change 2).

        Defaults to the currently-selected lesson if one is selected,
        otherwise to the first lesson in the course. No-op if no course is
        loaded or the course has no lessons (the window shows a placeholder
        picker in that case).
        """
        if self.course_dir is None or self.adapter is None:
            return
        from src.dialogs.teacher_window import TeacherWindow

        if self._teacher_window is None:
            self._teacher_window = TeacherWindow(
                self.adapter,
                self.undo_stack,
                self._ai_config,
                self._on_tree_changed,
                self,
            )
            self._teacher_window.finished.connect(self._on_teacher_window_closed)
        # Decide which lesson to show.
        target_id: str | None = None
        if self._current_node_ref is not None and self._current_node_ref[0] == "lesson":
            target_id = self._current_node_ref[1]
        if target_id is None:
            for s in self.adapter.sections:
                for u in s.get("units", []):
                    for l in u.get("lessons", []):
                        target_id = l.get("id")
                        break
                if target_id:
                    break
        if target_id is not None:
            self._teacher_window.show_lesson(target_id)
        else:
            self._teacher_window.refresh_lesson_list()
        self._teacher_window.show()
        self._teacher_window.raise_()
        self._teacher_window.activateWindow()

    def _close_teacher_window(self) -> None:
        win = self._teacher_window
        if win is not None:
            win.close()

    def _on_teacher_window_closed(self) -> None:
        """Window closed by the user → uncheck the toggle (signal-safe)."""
        self._teacher_window = None
        self.mode_action.blockSignals(True)
        self.mode_action.setChecked(False)
        self.mode_action.blockSignals(False)
        self.teacher_mode = False
        self.mode_action.setText("教师模式")
        self.setWindowTitle("Varnamala 课程编辑器")
        if self._current_node_ref is not None:
            self._on_node_selected(self._current_node_ref)

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
        self.undo_stack.setUndoLimit(self._settings_obj.undo_limit)
        apply_theme(QApplication.instance(), self._settings_obj)
        self.statusBar().showMessage("设置已应用", 3000)

    def _on_ai_generate(self) -> None:
        from src.dialogs.ai_generator_dialog import AiGeneratorDialog

        telemetry.record_event("ai.generate.open")
        if not self._settings.value("ai_beta_warning_shown", False):
            QMessageBox.information(
                self,
                "AI 生成课程（Beta）",
                "AI 生成课程为 Beta 功能，生成结果仅供参考，请作者自行审核。\n\n"
                "本功能会消耗大量 token，且建议模型支持 1M 上下文窗口。\n\n"
                "点击「确定」继续。",
            )
            self._settings.setValue("ai_beta_warning_shown", True)

        dlg = AiGeneratorDialog(self.adapter, self)
        if not dlg.exec():
            telemetry.record_event("ai.generate.cancelled")
            return
        try:
            section = dlg.section_json()
        except ValueError as exc:
            QMessageBox.warning(self, "无法导入", str(exc))
            return
        if not self.course_dir:
            QMessageBox.warning(self, "未加载课程目录", "请先打开课程目录。")
            return

        outcome = self._import_section_dict(section)
        sid = section.get("id", "")
        if outcome == "imported":
            telemetry.record_event("ai.generate.imported", payload={"section_id": sid})
        elif outcome == "merged":
            telemetry.record_event("ai.generate.merged", payload={"section_id": sid})
        elif outcome == "skipped":
            telemetry.record_event(
                "ai.generate.merge.cancelled", payload={"section_id": sid}
            )

    def _import_section_dict(self, section: dict, strategy: str = ImportStrategy.MERGE.value) -> str:
        """Import (or merge) a section dict into the loaded course.

        Shared by ``_on_ai_generate`` and the textbook import flow. Validates
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

        Returns an ``ImportStepResult`` so bulk callers (e.g. textbook import)
        can aggregate outcomes instead of showing one dialog per section.

        ``strategy`` selects the collision behaviour; see
        ``src.backend.import_strategy``. Defaults to ``merge`` so the AI
        generator flow is unchanged.
        """
        sid = section.get("id") or ""
        if not sid:
            QMessageBox.warning(self, "缺少 section id", "生成的 JSON 缺少顶层 id 字段。")
            return ImportStepResult.error(
                "import", "缺少 section id", details={"outcome": "blocked"}
            )

        # Format-only validation: the AI may intentionally reuse existing ids.
        problems = self.adapter.validate_section_json(section, check_existing_ids=False)
        errors = [p for p in problems if p["level"] == "error"]
        warnings = [p for p in problems if p["level"] == "warning"]
        if errors:
            detail = "\n".join(f"[{p['level']}] {p['message']}" for p in errors)
            QMessageBox.warning(self, "AI section 校验失败", detail)
            return ImportStepResult.error(
                "import", "校验失败", details={"outcome": "blocked", "errors": errors}
            )
        if warnings:
            detail = "\n".join(f"[{p['level']}] {p['message']}" for p in warnings)
            QMessageBox.information(
                self, "AI section 导入警告", f"存在警告，但仍可导入：\n\n{detail}"
            )

        existing_ids = {s.get("id") for s in self.adapter.sections}
        existing_index_ids = {
            e.get("id") for e in self.adapter.index.get("sections", [])
        }
        exists = sid in existing_ids or sid in existing_index_ids
        action = resolve_action(exists, strategy)

        if action == "skip":
            self.statusBar().showMessage(
                f"已跳过「{section.get('name', sid)}」（同 id section 已存在）", 8000
            )
            return ImportStepResult.success(
                "import",
                message="跳过已存在 section",
                details={"outcome": "skipped", "section_id": sid},
            )

        if action == "replace":
            # Force-overwrite the existing section wholesale (no preview).
            cmd = AiEditSectionCommand(self.adapter, sid, section, resource_section=section)
            cmd.signals.changed.connect(self.tree._on_command_changed)
            self.undo_stack.push(cmd)
            self.tree.select_section(sid)
            self.statusBar().showMessage(
                f"已覆盖「{section.get('name', sid)}」，记得保存", 8000
            )
            outcome = "replaced"
        elif action == "append_new":
            # Single-section path (AI generator): rewrite the id here. The
            # textbook batch path (_on_textbook_sections) pre-rewrites the id
            # from plan_bulk_import's target_id, so it reaches this point with
            # a fresh id and resolves to "append" instead — this branch then
            # only fires for non-batch callers.
            new_id = unique_section_id(self.adapter, sid)
            section = dict(section)
            section["id"] = new_id
            section.setdefault("prerequisiteSectionIds", [])
            cmd = ImportAiSectionCommand(self.adapter, section)
            cmd.signals.changed.connect(self.tree._on_command_changed)
            self.undo_stack.push(cmd)
            self.tree.select_section(new_id)
            self.statusBar().showMessage(
                f"已作为新 section「{new_id}」导入（原 id {sid} 已存在），记得保存", 8000
            )
            sid = new_id
            outcome = "imported"
        elif action == "merge":
            # Merge into the existing section via interactive preview.
            plan = self.adapter.plan_section_merge(sid, section)
            from src.dialogs.ai.ai_merge_preview_dialog import AiMergePreviewDialog

            preview = AiMergePreviewDialog(plan, parent=self)
            if preview.exec() != QDialog.DialogCode.Accepted:
                return ImportStepResult(
                    step="import",
                    outcome="cancelled",
                    message="用户取消了合并预览",
                    details={"outcome": "skipped", "section_id": sid},
                )
            cmd = MergeAiSectionCommand(self.adapter, preview.plan())
            cmd.signals.changed.connect(self.tree._on_command_changed)
            self.undo_stack.push(cmd)
            self.tree.select_section(sid)
            self.statusBar().showMessage(
                f"已将 AI 生成内容合并到「{section.get('name', sid)}」，记得保存", 8000
            )
            outcome = "merged"
        else:  # "append" - brand new section
            section.setdefault("prerequisiteSectionIds", [])
            cmd = ImportAiSectionCommand(self.adapter, section)
            cmd.signals.changed.connect(self.tree._on_command_changed)
            self.undo_stack.push(cmd)
            self.tree.select_section(sid)
            self.statusBar().showMessage(
                f"已通过 AI 生成课程「{section.get('name', sid)}」并已选中，记得保存", 8000
            )
            outcome = "imported"

        resource_note = ""
        added = self.adapter.detect_changes()
        if added.get("vocab") or added.get("expressions") or added.get("grammar_points"):
            resource_note = "（资源已合并到词库/表达/语法，记得保存）"
        if resource_note:
            self.statusBar().showMessage(
                self.statusBar().currentMessage() + resource_note, 8000
            )
        return ImportStepResult.success(
            "import",
            message=f"section {outcome}",
            details={"outcome": outcome, "section_id": sid},
        )

    def _on_textbook_import(self) -> None:
        from src.dialogs.textbook_import_dialog import TextbookImportDialog
        from src.dialogs.textbook_library_dialog import TextbookLibraryDialog

        telemetry.record_event("textbook.import.open")
        if not self._settings.value("textbook_beta_warning_shown", False):
            QMessageBox.information(
                self,
                "导入教材（Beta）",
                "导入教材为 Beta 功能，结果仅供参考，请作者自行审核。\n\n"
                "本功能会消耗大量 token（逐章 LLM 抽取），且建议模型支持 1M 上下文窗口。\n\n"
                "支持 .md / .txt / 文本原生 PDF（扫描件暂不支持）。\n\n"
                "点击「确定」继续。",
            )
            self._settings.setValue("textbook_beta_warning_shown", True)

        library = TextbookLibraryDialog(parent=self)
        if library.exec() != QDialog.DialogCode.Accepted:
            telemetry.record_event("textbook.import.library.cancelled")
            return
        project = library.selected_project
        if project is None:
            telemetry.record_event("textbook.import.closed")
            return

        dlg = TextbookImportDialog(self.adapter, self, project=project)
        dlg.sections_ready.connect(self._on_textbook_sections)
        dlg.exec()
        telemetry.record_event("textbook.import.closed")

    def _on_textbook_sections(self, sections: list, strategy: str) -> None:
        if not self.course_dir:
            QMessageBox.warning(self, "未加载课程目录", "请先打开课程目录。")
            return
        # Pre-compute the per-section plan so the summary reflects the strategy
        # (e.g. append_as_new rewrites ids; skip drops collisions). Execution
        # still goes through ``_import_section_dict_result`` per section so the
        # interactive merge preview (``merge`` strategy) can prompt per section.
        plans = plan_bulk_import(sections, self.adapter, strategy)
        counts = {"imported": 0, "merged": 0, "replaced": 0, "skipped": 0, "blocked": 0}
        for section, plan in zip(sections, plans):
            sid = section.get("id", "")
            # For append_as_new, use the planned target id so the section is
            # imported under the non-colliding id the preview promised.
            if plan.action == "append_new" and plan.target_id != sid:
                section = dict(section)
                section["id"] = plan.target_id
                sid = plan.target_id
            result = self._import_section_dict_result(section, strategy=strategy)
            outcome = result.details.get("outcome", "blocked") if result.details else "blocked"
            counts[outcome] = counts.get(outcome, 0) + 1
            if outcome == "imported":
                telemetry.record_event(
                    "textbook.import.imported", payload={"section_id": sid}
                )
            elif outcome == "merged":
                telemetry.record_event(
                    "textbook.import.merged", payload={"section_id": sid}
                )
            elif outcome == "replaced":
                telemetry.record_event(
                    "textbook.import.replaced", payload={"section_id": sid}
                )
            elif outcome == "skipped":
                telemetry.record_event(
                    "textbook.import.merge.cancelled", payload={"section_id": sid}
                )
        summary = (
            f"导入完成：新增 {counts['imported']} 个，"
            f"合并 {counts['merged']} 个，"
            f"覆盖 {counts['replaced']} 个，"
            f"跳过 {counts['skipped']} 个，"
            f"失败 {counts['blocked']} 个。"
        )
        QMessageBox.information(self, "导入教材", summary)

    def _on_ai_edit(self, kind: str, node_id: str) -> None:
        from src.dialogs.ai_generator_dialog import AiGeneratorDialog

        telemetry.record_event("ai.edit.open", payload={"kind": kind, "node_id": node_id})
        if not self._settings.value("ai_beta_warning_shown", False):
            QMessageBox.information(
                self,
                "AI 编辑课程（Beta）",
                "AI 编辑课程为 Beta 功能，编辑结果仅供参考，请作者自行审核。\n\n"
                "本功能会消耗大量 token，且建议模型支持 1M 上下文窗口。\n\n"
                "点击「确定」继续。",
            )
            self._settings.setValue("ai_beta_warning_shown", True)

        if not self.course_dir:
            QMessageBox.warning(self, "未加载课程目录", "请先打开课程目录。")
            return

        try:
            if kind == "section":
                section = self.adapter.find_section(node_id)
            elif kind == "unit":
                section, _unit = self.adapter.find_unit(node_id)
            elif kind == "lesson":
                section, _unit, _lesson = self.adapter.find_lesson(node_id)
            else:
                return
        except KeyError as exc:
            QMessageBox.warning(self, "无法编辑", str(exc))
            return

        edit_mode = {
            "scope": kind,
            "scope_id": node_id,
            "existing_section": section,
        }
        dlg = AiGeneratorDialog(self.adapter, self, edit_mode=edit_mode)
        if not dlg.exec():
            telemetry.record_event("ai.edit.cancelled", payload={"kind": kind})
            return
        try:
            new_section = dlg.section_json()
        except ValueError as exc:
            QMessageBox.warning(self, "无法应用编辑", str(exc))
            return

        sid = section.get("id", "")
        if kind == "section":
            plan = self.adapter.plan_section_merge(sid, new_section)
            from src.dialogs.ai.ai_merge_preview_dialog import AiMergePreviewDialog

            preview = AiMergePreviewDialog(plan, parent=self)
            if preview.exec() != QDialog.DialogCode.Accepted:
                telemetry.record_event("ai.edit.merge.cancelled", payload={"kind": kind, "node_id": node_id})
                return
            cmd = MergeAiSectionCommand(self.adapter, preview.plan())
            cmd.signals.changed.connect(self._on_ai_edit_applied)
            self.undo_stack.push(cmd)
            self.tree.select_section(sid)
        elif kind == "unit":
            new_unit = self._extract_unit(new_section, node_id)
            if new_unit is None:
                QMessageBox.warning(
                    self, "无法应用编辑", f"AI 返回的 JSON 中找不到 unit「{node_id}」。"
                )
                return
            problems = self.adapter.validate_section_json(
                {"id": "temp", "name": "temp", "units": [new_unit]},
                check_existing_ids=False,
            )
            errors = [p for p in problems if p.get("level") == "error"]
            if errors:
                QMessageBox.warning(self, "AI 编辑校验失败", "\n".join(p["message"] for p in errors))
                return
            cmd = AiEditUnitCommand(
                self.adapter, sid, node_id, new_unit, resource_section=new_section
            )
            cmd.signals.changed.connect(self._on_ai_edit_applied)
            self.undo_stack.push(cmd)
            self.tree.refresh_incremental()
        elif kind == "lesson":
            new_lesson = self._extract_lesson(new_section, node_id)
            if new_lesson is None:
                QMessageBox.warning(
                    self, "无法应用编辑", f"AI 返回的 JSON 中找不到 lesson「{node_id}」。"
                )
                return
            problems = self.adapter.validate_section_json(
                {"id": "temp", "name": "temp", "units": [{"id": "temp", "lessons": [new_lesson]}]},
                check_existing_ids=False,
            )
            errors = [p for p in problems if p.get("level") == "error"]
            if errors:
                QMessageBox.warning(self, "AI 编辑校验失败", "\n".join(p["message"] for p in errors))
                return
            cmd = AiEditLessonCommand(
                self.adapter, node_id, new_lesson, resource_section=new_section
            )
            cmd.signals.changed.connect(self._on_ai_edit_applied)
            self.undo_stack.push(cmd)
            self.tree.refresh_incremental()

        telemetry.record_event("ai.edit.applied", payload={"kind": kind, "node_id": node_id})
        if self._current_node_ref is not None:
            self._on_node_selected(self._current_node_ref)
        self.statusBar().showMessage(
            f"已应用 AI 编辑（{kind}），记得保存", 8000
        )

    def _on_ai_edit_applied(self) -> None:
        self.tree.refresh_incremental()
        self.tree.tree_changed.emit()
        if self._current_node_ref is not None:
            self._on_node_selected(self._current_node_ref)

    def _on_ai_fix_from_tree(self, kind: str, node_id: str) -> None:
        """Handle AI fix request from the course tree context menu."""
        # Validate the node to collect concrete problems for the prompt.
        try:
            if kind == "section":
                node_json = self.adapter.find_section(node_id)
                problems = self.adapter.validate_section_json(node_json)
            elif kind == "unit":
                section, node_json = self.adapter.find_unit(node_id)
                problems = self.adapter.validate_section_json({
                    "id": "temp",
                    "name": "temp",
                    "units": [node_json],
                })
            elif kind == "lesson":
                _section, _unit, node_json = self.adapter.find_lesson(node_id)
                problems = self.adapter.validate_section_json({
                    "id": "temp",
                    "name": "temp",
                    "units": [{"id": "temp", "lessons": [node_json]}],
                })
            else:
                return
        except KeyError:
            QMessageBox.warning(self, "无法定位节点", f"找不到节点：{kind}/{node_id}")
            return
        if not problems:
            QMessageBox.information(self, "无需修正", "当前节点没有检测到校验问题。")
            return
        self._on_ai_fix_requested(problems[0], (kind, node_id))

    @staticmethod
    def _extract_unit(new_section: dict, unit_id: str) -> dict | None:
        for u in new_section.get("units") or []:
            if isinstance(u, dict) and u.get("id") == unit_id:
                return u
        return None

    @staticmethod
    def _extract_lesson(new_section: dict, lesson_id: str) -> dict | None:
        for u in new_section.get("units") or []:
            if not isinstance(u, dict):
                continue
            for l in u.get("lessons") or []:
                if isinstance(l, dict) and l.get("id") == lesson_id:
                    return l
        return None

    def _on_node_selected(self, node_ref: tuple[str, str]) -> None:
        self._current_node_ref = node_ref
        if self.course_dir is None:
            return
        if self.teacher_mode:
            # Route lesson selections to the teacher window (single teacher
            # surface) while keeping the inline panel on node metadata so the
            # right pane is not empty.
            if node_ref[0] == "lesson":
                if self._teacher_window is not None:
                    self._teacher_window.show_lesson(node_ref[1])
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

    def _on_tree_changed(self) -> None:
        self.tree.refresh()
        # Keep the teacher window's lesson picker in sync after structural edits.
        if self._teacher_window is not None:
            self._teacher_window.refresh_lesson_list()

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
        dlg = GitLibraryDialog(self.adapter, self)
        dlg.open_requested.connect(self._open_repo_path)
        dlg.exec()
        # After the dialog closes, if a clone dir was opened, reflect it.
        clone = dlg.clone_dir()
        if clone is not None and self.course_dir == clone:
            self.statusBar().showMessage(f"已从 Git 资源库加载: {clone}", 5000)

    def _on_publish(self) -> None:
        telemetry.record_event("publish.open", payload={"teacher_mode": self.teacher_mode})
        if self.teacher_mode:
            from src.teacher.publish_dialog import TeacherPublishDialog

            dlg = TeacherPublishDialog(self.adapter, self)
            if dlg.exec():
                self.tree.refresh()
                self.statusBar().showMessage("发布成功", 5000)
            return
        from src.widgets.publish_dialog import PublishDialog

        dlg = PublishDialog(self.adapter, self)
        if dlg.exec():
            self.tree.refresh()
            if self._current_node_ref is not None:
                self.detail.show_node(self.adapter, self._current_node_ref)
            self.statusBar().showMessage("发布成功", 5000)

    def _on_save(self) -> None:
        telemetry.record_event("repo.save.triggered")
        result = self.adapter.save()
        self.tree.refresh()
        if result.ok:
            self.undo_stack.setClean()
            self.statusBar().showMessage(result.message or "保存成功", 5000)
        else:
            self.statusBar().showMessage(result.message or "保存失败（已回滚）", 8000)
            if result.errors:
                self._show_validation_report(result.errors, title="校验失败（已回滚）")

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
        report.ai_fix_requested.connect(self._on_ai_fix_requested)
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
        """Handle AI auto-fix request from validation report or context menu."""
        if node_ref is None:
            return
        kind, node_id = node_ref
        try:
            if kind == "section":
                node_json = self.adapter.find_section(node_id)
            elif kind == "unit":
                _section, node_json = self.adapter.find_unit(node_id)
            elif kind == "lesson":
                _section, _unit, node_json = self.adapter.find_lesson(node_id)
            else:
                return
        except KeyError:
            QMessageBox.warning(self, "无法定位节点", f"找不到节点：{kind}/{node_id}")
            return

        course_context = {
            "node_kind": kind,
            "node_id": node_id,
            "language": self.adapter.index.get("language", "en"),
            "existing_resource_ids": {
                "vocab": [w.get("id") for w in self.adapter.vocab if w.get("id")],
                "expressions": [e.get("id") for e in self.adapter.expressions if e.get("id")],
                "grammar_points": [g.get("id") for g in self.adapter.grammar_points if g.get("id")],
            },
        }
        from src.dialogs.ai_fix_dialog import AiFixDialog

        dlg = AiFixDialog(
            [problem],
            node_json,
            course_context,
            self._ai_config,
            parent=self,
        )
        if dlg.exec() != QDialog.DialogCode.Accepted:
            return
        corrected = dlg.corrected_node()
        if corrected is None:
            return

        # Validate the corrected node locally before applying.
        if kind == "section":
            problems = self.adapter.validate_section_json(
                corrected, check_existing_ids=False
            )
        elif kind == "unit":
            problems = self.adapter.validate_section_json(
                {"id": "temp", "name": "temp", "units": [corrected]},
                check_existing_ids=False,
            )
        elif kind == "lesson":
            problems = self.adapter.validate_section_json(
                {"id": "temp", "name": "temp", "units": [{"id": "temp", "lessons": [corrected]}]},
                check_existing_ids=False,
            )
        else:
            problems = []
        errors = [p for p in problems if p.get("level") == "error"]
        if errors:
            detail = "\n".join(f"[{p['level']}] {p['message']}" for p in errors)
            QMessageBox.warning(self, "AI 修正后仍有问题", detail)
            return

        # Apply via undo stack.
        if kind == "section":
            plan = self.adapter.plan_section_merge(node_id, corrected)
            from src.dialogs.ai.ai_merge_preview_dialog import AiMergePreviewDialog

            preview = AiMergePreviewDialog(plan, parent=self)
            if preview.exec() != QDialog.DialogCode.Accepted:
                telemetry.record_event("ai.fix.merge.cancelled", payload={"kind": kind, "node_id": node_id})
                return
            cmd = MergeAiSectionCommand(self.adapter, preview.plan())
            cmd.signals.changed.connect(self._on_ai_edit_applied)
            self.undo_stack.push(cmd)
            self.tree.select_section(node_id)
        elif kind == "unit":
            section, _ = self.adapter.find_unit(node_id)
            cmd = AiEditUnitCommand(
                self.adapter, section.get("id", ""), node_id, corrected, resource_section=corrected
            )
            cmd.signals.changed.connect(self._on_ai_edit_applied)
            self.undo_stack.push(cmd)
            self.tree.refresh_incremental()
        elif kind == "lesson":
            cmd = AiEditLessonCommand(
                self.adapter, node_id, corrected, resource_section=corrected
            )
            cmd.signals.changed.connect(self._on_ai_edit_applied)
            self.undo_stack.push(cmd)
            self.tree.refresh_incremental()

        if self._current_node_ref is not None:
            self._on_node_selected(self._current_node_ref)
        self.statusBar().showMessage("AI 自动修正已应用，记得保存", 5000)

    def _jump_to_node(self, node_ref: tuple[str, str]) -> None:
        kind, node_id = node_ref
        if kind == "lesson":
            self.tree.select_lesson(node_id)
        elif kind == "section":
            self.tree.select_section(node_id)
        elif kind == "unit":
            for top_idx in range(self.tree.topLevelItemCount()):
                section = self.tree.topLevelItem(top_idx)
                for i in range(section.childCount()):
                    unit = section.child(i)
                    ref = unit.data(0, 0x0100)
                    if ref and ref[0] == "unit" and ref[1] == node_id:
                        self.tree.setCurrentItem(unit)
                        self.tree.node_selected.emit(ref)
                        return

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
        if self.course_dir and self.adapter and any(self.adapter.detect_changes().values()):
            if self._settings_obj.auto_save_on_close:
                result = self.adapter.save()
                if result.ok:
                    telemetry.record_event("app.close_saved")
                    event.accept()
                    self._clear_ai_key_on_exit()
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
                return

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
            # Tear down the independent teacher window so it does not dangle.
            if self._teacher_window is not None:
                self._teacher_window.close()
                self._teacher_window = None
            self._clear_ai_key_on_exit()
            self._record_window_duration()

    def _record_window_duration(self) -> None:
        try:
            from src.infrastructure.operations_log import operations

            start = getattr(self, "_usage_t0", None)
            if start:
                operations.record_duration(
                    "window.duration",
                    (time.perf_counter() - start) * 1000.0,
                    payload={"window": "MainWindow"},
                )
                operations.record_action("window.close", "MainWindow")
        except Exception:
            pass
