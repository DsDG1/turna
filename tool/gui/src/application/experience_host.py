"""ExperienceHost — typed contract for the host window (``MainWindow``).

History: every experience handler/controller received ``host: Any`` and
poked at ~90 private attributes of ``MainWindow`` through ``getattr``
probes. The coupling was invisible: renaming a ``MainWindow`` internal
silently broke a whole subsystem, and the failure was swallowed by
best-effort ``except`` blocks.

This Protocol makes the implicit contract explicit and machine-checkable:

* **Structural** — ``MainWindow`` satisfies it by construction; no
  inheritance change is required.
* **Documented** — every member groups into a subsystem below; comments
  say what the contract means, probes (``getattr(host, x, None)``) mean
  the member is *optional* and the handler degrades gracefully.
* **Gated** — ``tool/check_ai_boundaries.py --fail-undeclared-host-access``
  fails when a file annotated with ``ExperienceHost`` touches ``host._x``
  that is not declared here. New coupling must be added to the contract
  explicitly.

Types are deliberately loose (``Any`` for widgets/workers/data) — the
value of this file is the *surface*, not fine-grained types.
"""
from __future__ import annotations

from typing import Any, Callable, Protocol

# Shorthand for the many callback members.
_Handler = Callable[..., Any]


class ExperienceHost(Protocol):
    """Structural type of the window every experience module runs against."""

    # ── Qt window surface ────────────────────────────────────────────────
    def statusBar(self) -> Any: ...
    def activateWindow(self) -> None: ...
    def showNormal(self) -> None: ...
    def raise_(self) -> None: ...
    def setMouseTracking(self, enabled: bool) -> None: ...
    def isVisible(self) -> bool: ...
    def windowTitle(self) -> str: ...
    def rect(self) -> Any: ...

    # ── Core services (stable public API) ────────────────────────────────
    session: Any                    # application.course_session.CourseSession
    adapter: Any                    # backend.course_adapter.CourseAdapter
    course_dir: str                 # '' when no repo is open
    job_tray: Any                   # background job tray (is_busy_ai / jobs)
    undo_stack: Any                 # QUndoStack for course edits
    tree: Any                       # widgets.course_tree.CourseTreeWidget
    experience_metrics: Any         # ExperienceMetrics (inc_suggestion/inc_job)
    conflict_guard: Any             # write-conflict guard service
    teacher_mode: bool
    experience: Any                 # experience shell aggregate on MainWindow
    experience_dock_widget: Any     # widgets.experience_dock.ExperienceDock
    experience_memory: Any          # memory subsystem handle
    experience_timeline: Any        # timeline widget handle
    ambient_banner: Any             # ambient suggestion banner widget
    mode_action: Any                # QAction toggling experience mode
    detail: Any                     # detail panel widget

    # ── Settings / policy / AI configuration ─────────────────────────────
    _settings_obj: Any              # Settings instance (probed)
    _settings: Any                  # legacy alias, probed
    _ai_config: Any                 # AiApiConfig for workers (probed)
    _save_worker: Any               # in-flight background save AiRequestWorker
    _resolve_experience_policy: _Handler      # () -> PolicyDecision (probed)
    _deny_ai_write_if_blocked: _Handler       # (label=…) -> bool gate (probed)
    _usage_today_for_policy: _Handler         # usage dict for budget (probed)

    # ── Dispatch bookkeeping ─────────────────────────────────────────────
    _dispatch_action_id: str        # action_id visible to handlers during dispatch

    # ── AI edit / regenerate flows ───────────────────────────────────────
    _on_ai_edit: _Handler                     # node AI edit entry (M5/M7)
    _run_regen_flow: _Handler                 # single lesson/unit regen
    _run_ai_fix_batch: _Handler               # batch validate-fix scheduler
    _run_fill_lesson_patch_flow: _Handler     # fill-empty patch flow
    _run_local_validate: _Handler             # local validate trigger
    _make_ai_worker: _Handler                 # AiRequestWorker factory
    _experience_worker: Any                   # live AiRequestWorker or None
    _refresh_validate_after_ai: _Handler      # post-AI validate refresh

    # ── AI fix / diagnose callbacks ──────────────────────────────────────
    _on_ai_edit_applied: _Handler             # after edit applied (refresh+undo)
    _refresh_experience: _Handler             # dock/suggestion refresh entry
    _on_ai_fix_requested: _Handler
    _on_ai_fix_single: _Handler
    _on_ai_batch_fix_requested: _Handler
    _diagnose_worker: Any                     # diagnose LLM worker or None
    _on_diagnose_problems: _Handler
    _on_diagnose_failed: _Handler
    _start_experience_diagnose: _Handler      # probed

    # ── Suggestions / memory / ambient state ─────────────────────────────
    _record_experience_event: _Handler        # telemetry-style event sink
    _record_window_duration: _Handler
    _flush_experience_metrics: _Handler
    _shown_suggestion_keys: Any               # set of already-shown keys
    _ambient_archived: Any
    _ambient_mute: Any                        # proactive mute state (make_mute)
    _defer_store: Any                         # A3 ② DeferStore (defer resurface)
    _heartbeat_wait_idle: bool                # ambient heartbeat paused flag
    _ambient_heartbeat: Any                   # QTimer (orphan: no creator in src)
    _campaign_auto_offered_for: Any
    _precog_cache: Any
    _experience_why_current: _Handler         # probed
    _experience_fill_empty: _Handler
    _experience_ocr: _Handler
    _confirm_scope_for_low_confidence: _Handler  # probed
    _confirm_clear_memory: _Handler           # probed
    _refresh_ambient: _Handler

    # ── Focus ring / presence / immersive mode ───────────────────────────
    _sync_focus_ring: _Handler
    _sync_experience_focus: _Handler
    _sync_experience_memory: _Handler         # probed
    _sync_experience_attachments: _Handler
    _presence_lock_widgets: Any               # list[QWidget] locked in presence
    _presence_mouse_filter: Any               # event filter installed on host
    _presence_drive_seen: Any
    _presence_ai_busy: bool                   # probed
    _sovereign_entered_at: Any                # timestamp or None
    _on_mode_toggled: _Handler

    # ── Workshop / git / textbook ────────────────────────────────────────
    _workshop_window: Any                     # WorkshopWindow or None
    _on_workshop: _Handler
    _on_workshop_locate: _Handler             # probed
    _on_workshop_attachments_changed: _Handler  # probed
    _on_workshop_ocr_requested: _Handler      # probed
    _show_git_skill_result: _Handler
    _git_library: Any                         # probed
    _git_clone_dir: Any                       # probed
    _on_textbook_sections: _Handler           # probed
    _import_service: Any                      # SectionImportService
    _last_imported_section_id: Any
    _open_repo_path: _Handler                 # probed
    _add_recent_repo: _Handler                # probed

    # ── Goal planner ─────────────────────────────────────────────────────
    _goal_last_plan: Any                      # last GoalPlan dict or None
    _goal_merge_plan: _Handler
    _goal_sandbox: Any
    _goal_fill_worker_factory: Any            # probed

    # ── Command palette ──────────────────────────────────────────────────
    _active_command_palette: Any              # palette window or None
    _palette_llm_worker: Any
    _palette_llm_pending_query: Any           # probed
    _palette_async_candidate_hook: Any        # probed
    _palette_help_non_modal: _Handler         # probed

    # ── Overview / validation / publish / save ───────────────────────────
    _overview_window: Any                     # CourseOverviewWindow or None
    _on_overview_destroyed: _Handler
    _on_overview_lesson_selected: _Handler
    _on_overview_validation: _Handler
    _show_validation_report: _Handler
    _last_compare_report: Any
    _compare_sections_non_modal: _Handler     # probed
    _batch_regen_inline: Any                  # probed
    _last_demote_blocked_s: Any
    _last_help_dialog: Any
    _on_resources: _Handler                   # hygiene window opener
    _on_publish: _Handler                     # probed
    _on_save: _Handler                        # probed
    _on_experience_suggestion: _Handler       # probed
    _on_experience_pin_toggled: _Handler      # probed
    _enable_editor_actions: _Handler          # probed
    _apply_undo_limit: _Handler               # probed
    _teacher_focused_item_id: Any             # probed
    _current_node_ref: Any                    # NodeRef of current selection
    _current_section_for_experience: _Handler
