"""Repository session host: recent repos, AI config, open/new course flow.

Extracted from ``src/app.py`` (P2 slim-down); every function takes the
MainWindow (``host``) as context. The window keeps same-name delegating
methods so tests and signal wiring are unchanged.
"""
from __future__ import annotations

from pathlib import Path

import contextlib
import logging

from PySide6.QtWidgets import QFileDialog, QMessageBox

from src.backend.ai import AiApiConfig
from src.backend.course_adapter import CourseAdapter
from src.infrastructure.telemetry import telemetry

logger = logging.getLogger(__name__)


def load_recent_repos(host) -> list[dict[str, str]]:
    return [dict(r) for r in host._settings_obj.recent_repos]


def add_recent_repo(host, path: Path) -> None:
    host._settings_obj.add_recent_repo(path)
    host._settings_obj.save_to_qsettings(host._settings)


def populate_recent_menu(host) -> None:
    host.recent_menu.clear()
    repos = host._load_recent_repos()
    if not repos:
        action = host.recent_menu.addAction("（无历史记录）")
        action.setEnabled(False)
        return
    for repo in repos:
        path = repo.get("path", "")
        action = host.recent_menu.addAction(path)
        action.setProperty("repo_path", path)
        action.triggered.connect(host._on_recent_repo_action_triggered)


def on_recent_repo_action_triggered(host) -> None:
    sender = host.sender()
    if not sender:
        return
    p = sender.property("repo_path")
    if isinstance(p, str):
        host._open_repo_path(p)


def clear_recent_repos(host) -> None:
    host._settings_obj.clear_recent_repos()
    host._settings_obj.save_to_qsettings(host._settings)


def load_ai_config(host) -> AiApiConfig:
    """Load AI API config from the central Settings object."""
    return AiApiConfig(
        base_url=host._settings_obj.ai_base_url,
        api_key=host._settings_obj.ai_api_key,
        model=host._settings_obj.ai_model,
        supports_reasoning=host._settings_obj.ai_supports_reasoning,
        model_chat=host._settings_obj.ai_model_chat,
        model_json=host._settings_obj.ai_model_json,
        strict_schema=host._settings_obj.ai_strict_schema,
    )


def save_ai_config(host, config: AiApiConfig) -> None:
    """Persist AI API config through the central Settings object."""
    host._settings_obj.ai_base_url = config.base_url
    host._settings_obj.ai_api_key = config.api_key
    host._settings_obj.ai_model = config.model
    host._settings_obj.ai_supports_reasoning = config.supports_reasoning
    host._settings_obj.save_to_qsettings(host._settings)


def apply_ai_cache(host) -> None:
    """第三枪 批次① Step 9: install/clear the process-wide AI cache.

    Called on startup and whenever the user toggles
    ``ai_cache_enabled`` in Settings. When disabled, the default cache is
    cleared so no stale entries survive a re-enable. Disk persistence is
    not enabled in this build (memory-only LRU); a future iteration can
    add a ``ai/cache_disk_dir`` setting.
    """
    from src.backend.ai_cache import AiCache, set_default_cache

    if host._settings_obj.ai_cache_enabled:
        set_default_cache(AiCache(maxsize=128, enabled=True))
    else:
        set_default_cache(None)


def maybe_open_last_repo(host) -> None:
    from src.application.ui_guard import is_headless_ui, safe_question

    if is_headless_ui():
        return
    repos = host._load_recent_repos()
    if not repos:
        return
    last_path = repos[0].get("path", "")
    if not last_path or not Path(last_path).exists():
        return
    if safe_question(
        host,
        "打开最近仓库",
        f"是否打开上次使用的课程仓库？\n{last_path}",
        default_yes=True,
    ):
        host._open_repo_path(last_path)


def load_via_session(host, path: Path) -> None:
    """Worker-safe loader shared by every open path (B1).

    Runs on the background open worker, so it must ONLY load — never touch
    session/GUI state: ``session.open_course`` here would rebind
    ``session.course_dir`` (host.course_dir proxies it) *before*
    ``bind_loaded_course`` reads the old path for ``prepare_course_switch``,
    silently skipping the course-switch cleanup, and would ``clear()`` the
    QUndoStack off the GUI thread. Session rebinding already happens on the
    main thread in ``bind_loaded_course`` via the host property proxies.
    Failure semantics stay unified: ``adapter.load`` rolls its own binding
    back, so the session keeps pointing at the previous course.
    """
    host.adapter.load(path)


def open_repo_path(host, path_str: str) -> None:
    from src.application.course_lifecycle import open_course_flow
    from src.application.ui_guard import safe_warning

    path = Path(path_str)
    if not path.exists() or not CourseAdapter.is_course_dir(path):
        safe_warning(host, "无法打开", f"目录不存在或不是有效的课程仓库：\n{path}")
        return

    open_course_flow(host, path, load=lambda p: load_via_session(host, p))


def show_load_error(host, message: str) -> None:
    """Show a load error dialog with optional AI analysis."""
    from src.dialogs.ai_error_analyzer import offer_ai_analysis
    if offer_ai_analysis(host, "加载失败", message):
        from src.dialogs.ai_error_analyzer import AiErrorAnalyzerDialog

        # analyze_exception(), not traceback.format_exc(): we are outside any
        # except block here, so format_exc() would hand the model the useless
        # "NoneType: None" instead of the load error above.
        AiErrorAnalyzerDialog.analyze_exception(
            host,
            message,
            context={"action": "repo.open"},
        ).exec()


def enable_editor_actions(host) -> None:
    host.save_action.setEnabled(True)
    host.workshop_action.setEnabled(True)
    host.overview_action.setEnabled(True)
    host.resources_menu_btn.setEnabled(True)
    host.publish_action.setEnabled(True)
    host.generate_audio_action.setEnabled(True)
    # W2: repo loaded — leave the welcome view and unlock the rail items.
    with contextlib.suppress(Exception):
        host._sync_shell_views()
    try:
        from src.application import shell_views

        shell_views.sync_save_state_label(host)
        shell_views.sync_activity_badges(host)
    except Exception:
        # Shell chrome only (status caption + activity-bar badge counts). The
        # repo is already loaded and unlocked by this point; failing to refresh
        # the chrome must not abort the open flow or roll the repo back.
        logger.debug("post-open shell chrome sync failed", exc_info=True)


def on_new_course(host) -> None:
    from src.application.course_lifecycle import confirm_course_switch, open_course_flow
    from src.dialogs.init_course_dialog import InitCourseDialog

    # Dirty-check BEFORE the dialog: init_new() replaces the adapter content,
    # so after accept the old course's unsaved edits are already unrecoverable.
    if not confirm_course_switch(host):
        return
    dlg = InitCourseDialog(host.adapter, host)
    if not dlg.exec():
        telemetry.record_event("repo.new.cancelled")
        return
    init_dir = dlg.init_dir()
    if not init_dir:
        return
    # init_new() already wrote + bound the adapter; only the shared tail
    # (bind/undo clear/recent/status) remains.
    open_course_flow(
        host,
        init_dir,
        load=None,
        confirm=False,
        status_message=f"已新建并加载: {init_dir}",
        telemetry_event="repo.new",
        telemetry_payload={"course_dir": str(init_dir)},
    )


def on_open(host) -> None:
    from src.application.course_lifecycle import open_course_flow

    start = str(host.course_dir) if host.course_dir else ""
    chosen = QFileDialog.getExistingDirectory(host, "选择课程目录", start)
    if not chosen:
        telemetry.record_event("repo.open.cancelled")
        return
    open_course_flow(host, Path(chosen), load=lambda p: load_via_session(host, p))
