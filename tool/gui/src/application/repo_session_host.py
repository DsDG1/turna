"""Repository session host: recent repos, AI config, open/new course flow.

Extracted from ``src/app.py`` (P2 slim-down); every function takes the
MainWindow (``host``) as context. The window keeps same-name delegating
methods so tests and signal wiring are unchanged.
"""
from __future__ import annotations

from pathlib import Path

from PySide6.QtWidgets import QMessageBox

from src.backend.ai import AiApiConfig
from src.backend.course_adapter import CourseAdapter
from src.infrastructure.telemetry import telemetry


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


def open_repo_path(host, path_str: str) -> None:
    from src.application.ui_guard import safe_warning

    path = Path(path_str)
    if not path.exists() or not CourseAdapter.is_course_dir(path):
        safe_warning(host, "无法打开", f"目录不存在或不是有效的课程仓库：\n{path}")
        return
    session = getattr(host, "session", None)
    if session is not None:
        try:
            session.open_course(path)
        except Exception as exc:
            telemetry.record_error(
                exc,
                context={"action": "repo.open", "path": str(path)},
            )
            host._show_load_error(str(exc))
            return
    else:
        try:
            host.adapter.load(path)
        except Exception as exc:
            telemetry.record_error(
                exc,
                context={"action": "repo.open", "path": str(path)},
            )
            host._show_load_error(str(exc))
            return
        host.course_dir = path
        host.undo_stack.clear()
    host.tree.display(host.adapter)
    host._enable_editor_actions()
    host._add_recent_repo(path)
    telemetry.record_event(
        "repo.open",
        payload={"path": str(path)},
    )
    host.statusBar().showMessage(f"已加载: {host.course_dir}", 4000)


def show_load_error(host, message: str) -> None:
    """Show a load error dialog with optional AI analysis."""
    from src.dialogs.ai_error_analyzer import offer_ai_analysis
    if offer_ai_analysis(host, "加载失败", message):
        import traceback

        from src.dialogs.ai_error_analyzer import AiErrorAnalyzerDialog

        AiErrorAnalyzerDialog(
            traceback.format_exc(),
            context={"action": "repo.open"},
            parent=host,
        ).exec()


def enable_editor_actions(host) -> None:
    host.save_action.setEnabled(True)
    host.workshop_action.setEnabled(True)
    host.overview_action.setEnabled(True)
    host.resources_menu_btn.setEnabled(True)
    host.publish_action.setEnabled(True)
    host.generate_audio_action.setEnabled(True)


def on_new_course(host) -> None:
    from src.dialogs.init_course_dialog import InitCourseDialog

    dlg = InitCourseDialog(host.adapter, host)
    if not dlg.exec():
        telemetry.record_event("repo.new.cancelled")
        return
    init_dir = dlg.init_dir()
    if not init_dir:
        return
    host.course_dir = init_dir
    host.tree.display(host.adapter)
    host.undo_stack.clear()
    host._enable_editor_actions()
    host._add_recent_repo(init_dir)
    telemetry.record_event(
        "repo.new",
        payload={"course_dir": str(init_dir)},
    )
    host.statusBar().showMessage(f"已新建并加载: {init_dir}", 5000)


def on_open(host) -> None:
    start = str(host.course_dir) if host.course_dir else ""
    chosen = QFileDialog.getExistingDirectory(host, "选择课程目录", start)
    if not chosen:
        telemetry.record_event("repo.open.cancelled")
        return
    try:
        host.adapter.load(Path(chosen))
    except Exception as exc:
        telemetry.record_error(
            exc,
            context={"action": "repo.open", "path": chosen},
        )
        host._show_load_error(str(exc))
        return
    host.course_dir = Path(chosen)
    host.tree.display(host.adapter)
    host.undo_stack.clear()
    host._enable_editor_actions()
    host._add_recent_repo(host.course_dir)
    telemetry.record_event(
        "repo.open",
        payload={"path": str(host.course_dir)},
    )
    host.statusBar().showMessage(f"已加载: {host.course_dir}", 4000)
