"""Main window for the Turna GUI course editor."""
from __future__ import annotations

import time
from pathlib import Path
from typing import Any

from PySide6.QtCore import QEvent, QObject, QSettings, QTimer
from PySide6.QtGui import QUndoStack
from PySide6.QtWidgets import (
    QApplication,
    QLabel,
    QMainWindow,
    QMessageBox,
    QPushButton,
    QSizePolicy,
)

from src.application import runtime_context
from src.application.course_session import CourseSession
from src.application.experience_shell import ExperienceShell
from src.application.experience_window_bridge import (
    flush_experience_metrics,
    on_experience_context_changed,
    on_experience_pin_toggled,
    on_experience_resources_changed,
    record_experience_event,
    refresh_experience,
    sync_focus_ring,
)
from src.application.main_window_shell import (
    build_central,
    build_experience_actions,
    build_status_bar,
    build_toolbar,
    build_undo_actions,
)
from src.application.repo_session_host import (
    add_recent_repo,
    apply_ai_cache,
    clear_recent_repos,
    enable_editor_actions,
    load_ai_config,
    load_recent_repos,
    maybe_open_last_repo,
    on_new_course,
    on_open,
    on_recent_repo_action_triggered,
    open_repo_path,
    populate_recent_menu,
    save_ai_config,
    show_load_error,
)
from src.application.save_host import run_async_direct_save
from src.application.settings import Settings, migrate_legacy_varnamala_qsettings
from src.application.experience_skills_mixin import ExperienceSkillsMixin
from src.backend.ai import AiApiConfig
from src.backend.course_adapter import CourseAdapter
from src.backend.experience.conflict_guard import ConflictGuard
from src.backend.experience.metrics import ExperienceMetrics
from src.backend.experience.proactive import make_mute
from src.backend.import_step_result import ImportStepResult
from src.backend.import_strategy import ImportStrategy
from src.infrastructure.telemetry import telemetry
from src.theme import apply_theme
from src.widgets.experience_dock import ExperienceDock
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

        self.session = CourseSession(parent=self)
        self._workshop_window = None
        self._overview_window = None

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

        self.undo_stack.setUndoLimit(self._settings_obj.undo_limit)
        self.undo_stack.cleanChanged.connect(self._on_undo_clean_changed)

        # Debounce timer for tree/overview refreshes (see _on_tree_changed).
        self._tree_refresh_timer = QTimer(self)
        self._tree_refresh_timer.setSingleShot(True)
        self._tree_refresh_timer.setInterval(250)
        self._tree_refresh_timer.timeout.connect(self._flush_tree_refresh)

        # Background interactive-save worker (see _save_course_async).
        self._save_worker = None

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
        self._build_experience_actions()
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
        from src.application.section_import_service import build_import_service

        return build_import_service(self)

    def _on_import_command_pushed(self, cmd, section_id: str) -> None:
        """Wire an import undo command to the tree and reveal the section."""
        cmd.signals.changed.connect(self.tree._on_command_changed)
        self.tree.select_section(section_id)

    def _load_extraction_prompt_overrides(self) -> None:
        """Load persisted extraction-prompt overrides into the default library."""
        try:
            from src.backend import knowledge_prompt
            from src.application.ai_prompt_library import AiPromptLibrary

            knowledge_prompt.load_overrides_from(AiPromptLibrary(self._settings))
        except Exception:
            # Prompt overrides are an enhancement; never block startup.
            logger.debug("app.py:_load_extraction_prompt_overrides best-effort step failed", exc_info=True)

    def _build_undo_actions(self) -> None:
        build_undo_actions(self)

    def _build_experience_actions(self) -> None:
        build_experience_actions(self)

    def _on_undo_clean_changed(self, clean: bool) -> None:
        if self.course_dir is not None:
            marker = "" if clean else " *"
            base = "Turna 课程编辑器"
            if self.teacher_mode:
                base += " · 教师模式"
            self.setWindowTitle(base + marker)

    def _build_toolbar(self) -> None:
        build_toolbar(self)
    def _build_central(self) -> None:
        build_central(self)
    def _build_status_bar(self) -> None:
        build_status_bar(self)
    # --- Recent repository management ------------------------------------

    def _load_recent_repos(self) -> list[dict[str, str]]:
        return load_recent_repos(self)

    def _add_recent_repo(self, path: Path) -> None:
        add_recent_repo(self, path)

    def _populate_recent_menu(self) -> None:
        populate_recent_menu(self)

    def _on_recent_repo_action_triggered(self) -> None:
        on_recent_repo_action_triggered(self)

    def _clear_recent_repos(self) -> None:
        clear_recent_repos(self)

    def _load_ai_config(self) -> AiApiConfig:
        return load_ai_config(self)

    def _save_ai_config(self, config: AiApiConfig) -> None:
        save_ai_config(self, config)

    def _apply_ai_cache(self) -> None:
        apply_ai_cache(self)

    def _maybe_open_last_repo(self) -> None:
        maybe_open_last_repo(self)

    def _open_repo_path(self, path_str: str) -> None:
        open_repo_path(self, path_str)

    def _show_load_error(self, message: str) -> None:
        show_load_error(self, message)

    def _enable_editor_actions(self) -> None:
        enable_editor_actions(self)

    # --- Toolbar actions -------------------------------------------------

    def _on_new_course(self) -> None:
        on_new_course(self)

    def _on_open(self) -> None:
        on_open(self)

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
        """Open the unified authoring workspace (connectplan Phase 2)."""
        from src.application import workshop_controller

        workshop_controller.open_workshop(self)

    def _on_workshop_locate(self, section_id: str) -> None:
        """Reveal an imported section in the main course tree."""
        from src.application import workshop_controller

        workshop_controller.on_workshop_locate(self, section_id)

    def _on_overview(self) -> None:
        """Open the course structure overview window (workshop2 P4)."""
        from src.application import overview_controller

        overview_controller.open_overview(self)

    def _on_overview_lesson_selected(self, lesson_id: str) -> None:
        """Locate a lesson clicked in the overview inside the main tree."""
        from src.application import overview_controller

        overview_controller.on_overview_lesson_selected(self, lesson_id)

    def _on_overview_validation(self, problems: list) -> None:
        """Open the existing validation report with problems from the overview."""
        from src.application import overview_controller

        overview_controller.on_overview_validation(self, problems)

    def _on_overview_destroyed(self, *_args) -> None:
        from src.application import overview_controller

        overview_controller.on_overview_destroyed(self, *_args)

    def _on_textbook_sections(self, sections: list, strategy: str) -> None:
        from src.application import workshop_controller

        workshop_controller.on_textbook_sections(self, sections, strategy)

    def _offer_open_teacher_after_import(self, section_id: str | None) -> None:
        """After workshop import, optionally switch to teacher mode and locate.

        Skips the modal prompt when the main window is not visible (unit tests /
        headless automation) so batch imports never hang on QMessageBox.
        """
        from src.application import workshop_controller

        workshop_controller.offer_open_teacher_after_import(self, section_id)

    def _import_draft_into_section(self, draft: dict, section_id: str) -> None:
        """Append the draft's units into an existing section as new units."""
        from src.application import workshop_controller

        workshop_controller.import_draft_into_section(self, draft, section_id)

    def _record_draft_import(self, draft: dict, section_id: str | None) -> None:
        """Persist a workshop draft-import back into the project."""
        from src.application import workshop_controller

        workshop_controller.record_draft_import(self, draft, section_id)

    def _import_draft_into_unit(self, draft: dict, unit_id: str) -> None:
        """Append the draft's lessons into an existing unit as new lessons."""
        from src.application import workshop_controller

        workshop_controller.import_draft_into_unit(self, draft, unit_id)

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

    def _on_resources(self, initial_filter: str = "") -> None:
        from src.application import resources_controller

        resources_controller.open_resources(self, initial_filter=initial_filter)

    def _on_git_library(self) -> None:
        from src.application import resources_controller

        resources_controller.open_git_library(self)

    def _on_publish(self) -> None:
        from src.application import resources_controller

        resources_controller.open_publish(self)

    def _on_generate_audio(self) -> None:
        """Generate listening-lesson audio (MiniMax TTS) for the loaded course."""
        self._audio_controller.handle_generate_audio(self)

    def _on_save(self, *, reason: str = "menu") -> None:
        telemetry.record_event("repo.save.triggered", payload={"reason": reason})
        self._save_course_async()

    def _save_course_async(self) -> None:
        run_async_direct_save(self)

    def _show_validation_report(
        self, problems: list[dict], title: str = "校验结果"
    ) -> None:
        """Show a non-modal validation report panel with double-click-to-jump."""
        from src.application import validation_controller

        validation_controller.show_validation_report(self, problems, title=title)

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
        from src.application import validation_controller

        validation_controller.jump_to_node(self, node_ref)

    def _clear_ai_key_on_exit(self) -> None:
        """Wipe the API key from memory and storage when the window closes."""
        from src.application import close_controller

        close_controller.clear_ai_key_on_exit(self)

    def closeEvent(self, event) -> None:  # noqa: N802
        from src.application import close_controller

        close_controller.handle_close_event(self, event)

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
        sync_focus_ring(self)

    def _on_experience_context_changed(self, ctx) -> None:
        on_experience_context_changed(self, ctx)

    def _on_experience_pin_toggled(self) -> None:
        on_experience_pin_toggled(self)

    def _refresh_experience(self, *, immediate: bool = False, focus_only: bool = False) -> None:
        refresh_experience(self, immediate=immediate, focus_only=focus_only)

    def _on_experience_resources_changed(self) -> None:
        on_experience_resources_changed(self)

    def _flush_experience_metrics(self, reason: str = "", *, course_dir: Any = None) -> None:
        flush_experience_metrics(self, reason=reason, course_dir=course_dir)

    def _record_experience_event(self, event_name: str, label: str = "", **payload) -> None:
        record_experience_event(self, event_name, label=label, **payload)

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

    # ── CourseSession Transparent Properties ─────────────────────────────

    @property
    def adapter(self) -> CourseAdapter:
        return self.session.adapter

    @adapter.setter
    def adapter(self, val: CourseAdapter) -> None:
        self.session.adapter = val

    @property
    def course_dir(self) -> Path | None:
        return self.session.course_dir

    @course_dir.setter
    def course_dir(self, val: Path | None) -> None:
        self.session.course_dir = Path(val) if val is not None else None

    @property
    def undo_stack(self) -> QUndoStack:
        return self.session.undo_stack

    @undo_stack.setter
    def undo_stack(self, val: QUndoStack) -> None:
        self.session.undo_stack = val

    @property
    def _current_node_ref(self) -> tuple[str, str] | None:
        return self.session.current_node_ref

    @_current_node_ref.setter
    def _current_node_ref(self, val: tuple[str, str] | None) -> None:
        self.session.current_node_ref = val

    @property
    def teacher_mode(self) -> bool:
        return self.session.teacher_mode

    @teacher_mode.setter
    def teacher_mode(self, val: bool) -> None:
        self.session.teacher_mode = val

    @property
    def conflict_guard(self) -> ConflictGuard:
        return self.session.conflict_guard

    @conflict_guard.setter
    def conflict_guard(self, val: ConflictGuard) -> None:
        self.session.conflict_guard = val

    @property
    def experience_metrics(self) -> ExperienceMetrics:
        return self.session.experience_metrics

    @experience_metrics.setter
    def experience_metrics(self, val: ExperienceMetrics) -> None:
        self.session.experience_metrics = val

    @property
    def _last_imported_section_id(self) -> str | None:
        return self.session.last_imported_section_id

    @_last_imported_section_id.setter
    def _last_imported_section_id(self, val: str | None) -> None:
        self.session.last_imported_section_id = val
