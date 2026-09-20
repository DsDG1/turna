"""Single-shell multi-view orchestration (GUI 焕新 W2).

Builds the new window anatomy inside ``build_central``:

```
AmbientBanner (self-hiding)
ActivityBar | CentralStack (welcome/edit/overview/resources) | [right dock]
PreviewHost strip (self-hiding, above the status bar)
StatusBar (see main_window_shell.build_status_bar)
```

The right Copilot dock is a real ``QDockWidget`` on the main window's right
edge — it lives outside the central widget, so it is added here after the
central widget is installed.

Compatibility contract preserved: ``host.tree`` / ``host.detail`` /
``host.repo_menu`` / ``host.save_action`` / ``host.workshop_action`` /
``host.overview_action`` / ``host.resources_menu_btn`` / ``host.mode_action``
/ ``host.job_tray`` / ``host._overview_window`` all keep working — only the
parents change.
"""
from __future__ import annotations

import contextlib
import functools
import logging
from typing import Any

from PySide6.QtCore import Qt
from PySide6.QtGui import QKeySequence, QShortcut
from PySide6.QtWidgets import (
    QDockWidget,
    QHBoxLayout,
    QLabel,
    QSplitter,
    QStackedWidget,
    QTabWidget,
    QVBoxLayout,
    QWidget,
)

from src.widgets.preview_host import PreviewHost
from src.widgets.ui.activity_bar import ActivityBar
from src.widgets.ui.containers import ViewHeader
from src.widgets.ui.toast import ToastHost
from src.widgets.welcome_view import WelcomeView

logger = logging.getLogger(__name__)

#: View keys handled by the central stack / activity bar. ``workshop`` is
#: intentionally not a stack page in W2 — it opens the existing window
#: (embedded in W5). ``welcome`` is a stack page but not a checkable item.
VIEW_KEYS = ("edit", "workshop", "overview", "resources")
STACK_KEYS = ("welcome", "edit", "overview", "resources")

_SETTINGS_KEY_LAST_VIEW = "shell/last_view"
_SETTINGS_KEY_STATE = "shell/window_state"
_SETTINGS_KEY_GEOMETRY = "shell/window_geometry"
_SETTINGS_KEY_SIDEBAR = "shell/sidebar_visible"
_SETTINGS_KEY_COPILOT = "shell/copilot_visible"


# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------


def _qs(host: Any) -> Any:
    return getattr(host, "_settings", None)


def _qs_bool(host: Any, key: str, default: bool) -> bool:
    qs = _qs(host)
    if qs is None:
        return default
    try:
        val = qs.value(key, default)
    except Exception:
        return default
    if isinstance(val, str):
        return val.lower() in ("true", "1", "yes")
    return bool(val)


def _telemetry(event: str, **payload: Any) -> None:
    try:
        from src.infrastructure.telemetry import telemetry

        telemetry.record_event(event, payload=payload or None)
    except Exception:
        pass


def node_breadcrumb(host: Any, node_ref: tuple[str, str] | None) -> list[str]:
    """Section › Unit › Lesson names for the edit-view header breadcrumb."""
    if node_ref is None:
        return []
    kind, node_id = node_ref
    adapter = getattr(host, "adapter", None)
    if adapter is None:
        return []
    try:
        if kind == "lesson":
            section, unit, lesson = adapter.find_lesson(node_id)
            return [
                str(section.get("name", section.get("id", ""))),
                str(unit.get("name", unit.get("id", ""))),
                str(lesson.get("name", lesson.get("id", ""))),
            ]
        if kind == "unit":
            section, unit = adapter.find_unit(node_id)
            return [
                str(section.get("name", section.get("id", ""))),
                str(unit.get("name", unit.get("id", ""))),
            ]
        if kind == "section":
            section = adapter.find_section(node_id)
            return [str(section.get("name", section.get("id", "")))]
    except Exception:
        return []
    return []


_KIND_LABELS = {"section": "章节", "unit": "单元", "lesson": "课时"}


# ---------------------------------------------------------------------------
# Activity bar
# ---------------------------------------------------------------------------


def _build_activity_bar(host: Any, parent: QWidget) -> ActivityBar:
    bar = ActivityBar(parent)

    # App menu (top ☰): reuse host.repo_menu built by build_toolbar — it is
    # the full app menu (新建/打开/最近/发布/生成音频/命令面板/设置).
    bar.add_menu_button("应用菜单")

    # View items (exclusive).
    edit_item = bar.add_item(
        "edit", "folder-open", "课程编辑  Ctrl+1", view=True
    )
    overview_item = bar.add_item(
        "overview", "map", "课程总览  Ctrl+3", view=True
    )
    resources_item = bar.add_item(
        "resources", "library", "资源库  Ctrl+4", view=True
    )
    # Workshop stays a window in W2: the item acts as a plain button that
    # opens/raises it (re-checks the previous view after the click).
    workshop_item = bar.add_item(
        "workshop", "sparkles", "课程工坊  Ctrl+2", checkable=False
    )
    bar.add_separator()
    copilot_item = bar.add_item(
        "copilot", "bot", "Copilot 面板  Ctrl+J", checkable=True
    )
    bar.add_stretch()
    teacher_item = bar.add_item(
        "teacher", "graduation-cap", "教师模式", checkable=True
    )
    settings_item = bar.add_item(
        "settings", "settings", "设置  Ctrl+,", checkable=False
    )

    host.activity_bar = bar
    host.activity_bar_items = {
        "edit": edit_item,
        "workshop": workshop_item,
        "overview": overview_item,
        "resources": resources_item,
        "copilot": copilot_item,
        "teacher": teacher_item,
        "settings": settings_item,
    }
    # Compat: tests assert repo_menu_btn exists — the activity-bar menu
    # button now hosts the app menu.
    host.repo_menu_btn = bar.menu_button
    host.repo_menu_btn.setMenu(host.repo_menu)

    bar.view_activated.connect(functools.partial(set_view, host))
    workshop_item.clicked.connect(functools.partial(_open_workshop_view, host))
    copilot_item.clicked.connect(functools.partial(_toggle_copilot, host))
    teacher_item.clicked.connect(functools.partial(_toggle_teacher, host))
    settings_item.clicked.connect(host._on_settings)

    # Teacher-mode item mirrors the canonical mode_action state.
    try:
        host.mode_action.toggled.connect(teacher_item.setChecked)
        teacher_item.setChecked(bool(host.mode_action.isChecked()))
    except Exception:
        logger.debug("shell_views: teacher item sync failed", exc_info=True)

    return bar


def _open_workshop_view(host: Any, _c: bool = False) -> None:
    """Ctrl+2 / rail click — workshop remains a window in W2 (embedded W5)."""
    _telemetry("shell.view_switched", view="workshop")
    try:
        host._on_workshop()
    except Exception:
        logger.debug("shell_views: workshop open failed", exc_info=True)


def _toggle_teacher(host: Any, _c: bool = False) -> None:
    try:
        host.mode_action.setChecked(not host.mode_action.isChecked())
    except Exception:
        logger.debug("shell_views: teacher toggle failed", exc_info=True)


def _toggle_copilot(host: Any, _c: bool = False, *, force: bool | None = None) -> None:
    dock = getattr(host, "copilot_dock", None)
    if dock is None:
        return
    # isHidden() tracks the explicit request even while ancestors are hidden.
    show = dock.isHidden() if force is None else force
    dock.setVisible(show)


# ---------------------------------------------------------------------------
# Central stack pages
# ---------------------------------------------------------------------------


def _build_edit_page(host: Any) -> QWidget:
    """Edit view: ViewHeader + [sidebar tree | DetailPanel] splitter."""
    page = QWidget(host.central_stack)
    page.setObjectName("EditView")
    col = QVBoxLayout(page)
    col.setContentsMargins(0, 0, 0, 0)
    col.setSpacing(0)

    host.edit_header = ViewHeader("编辑", page)
    col.addWidget(host.edit_header)

    splitter = QSplitter(Qt.Orientation.Horizontal, page)
    splitter.setObjectName("EditSplitter")

    # W3: sidebar = SearchField + tree + mini toolbar (keeps host.tree API).
    from src.widgets.tree_sidebar import TreeSidebar

    host.tree_sidebar = TreeSidebar(host.tree)
    host.tree_sidebar.setObjectName("SideBar")
    host.tree_sidebar.setMinimumWidth(220)
    splitter.addWidget(host.tree_sidebar)
    splitter.addWidget(host.detail)
    splitter.setStretchFactor(0, 2)
    splitter.setStretchFactor(1, 3)
    splitter.setChildrenCollapsible(True)
    host.edit_splitter = splitter
    col.addWidget(splitter, 1)

    # 教师过滤 toggle mirrors the global teacher-mode action (both ways).
    try:
        host.tree_sidebar.teacher_filter_btn.setChecked(
            bool(host.mode_action.isChecked())
        )
        host.tree_sidebar.teacher_filter_btn.toggled.connect(
            host.mode_action.setChecked
        )
        host.mode_action.toggled.connect(
            host.tree_sidebar.teacher_filter_btn.setChecked
        )
    except Exception:
        logger.debug("shell_views: teacher filter wiring failed", exc_info=True)

    # Keep the breadcrumb in sync with the selected node.
    def _sync_header(ref: tuple[str, str]) -> None:
        host.edit_header.set_breadcrumb(node_breadcrumb(host, ref))

    host.tree.node_selected.connect(_sync_header)
    return page


def _build_overview_page(host: Any) -> QWidget:
    """Overview view: lazily embeds CourseOverviewWindow (no Window flag)."""
    page = QWidget(host.central_stack)
    page.setObjectName("OverviewView")
    col = QVBoxLayout(page)
    col.setContentsMargins(0, 0, 0, 0)
    col.setSpacing(0)

    header = ViewHeader("总览", page)
    header.set_breadcrumb("Section / Unit / Lesson 鸟瞰")
    col.addWidget(header)
    host.overview_header = header

    holder = QWidget(page)
    holder_layout = QVBoxLayout(holder)
    holder_layout.setContentsMargins(0, 0, 0, 0)
    holder_layout.setSpacing(0)
    host.overview_holder = holder
    host.overview_holder_layout = holder_layout
    col.addWidget(holder, 1)
    return page


def ensure_overview_embedded(host: Any) -> Any:
    """Create the embedded overview widget once; reuse the window class."""
    from src.widgets.course_overview import CourseOverviewWindow

    existing = getattr(host, "_overview_widget", None)
    if existing is not None:
        # Guard against a stale wrapper whose C++ object is gone.
        try:
            from shiboken6 import isValid as _shiboken_is_valid

            if _shiboken_is_valid(existing):
                return existing
        except ImportError:
            try:
                existing.windowTitle()  # raises RuntimeError if deleted
                return existing
            except RuntimeError:
                pass
        host._overview_widget = None
        host._overview_window = None

    overview = CourseOverviewWindow(host.adapter, host.overview_holder, embedded=True)
    overview.lesson_selected.connect(
        functools.partial(_on_overview_lesson_click, host)
    )
    overview.validation_requested.connect(host._on_overview_validation)
    overview.destroyed.connect(host._on_overview_destroyed)
    host.overview_holder_layout.addWidget(overview, 1)
    host._overview_widget = overview
    # Compat: tree-refresh sync + close-teardown read _overview_window.
    host._overview_window = overview
    return overview


def _on_overview_lesson_click(host: Any, lesson_id: str) -> None:
    """Embedded overview click → locate in tree, then switch to edit view."""
    try:
        host._on_overview_lesson_selected(lesson_id)
    finally:
        set_view(host, "edit")


def _build_resources_page(host: Any) -> QWidget:
    """Resources view: ViewHeader + tab[本地资源 | Git 资源库]."""
    page = QWidget(host.central_stack)
    page.setObjectName("ResourcesView")
    col = QVBoxLayout(page)
    col.setContentsMargins(0, 0, 0, 0)
    col.setSpacing(0)

    host.resources_header = ViewHeader("资源", page)
    host.resources_header.set_breadcrumb("词库 · 表达 · 语法 · Git 协作")
    col.addWidget(host.resources_header)

    host.resources_tabs = QTabWidget(page)
    host.resources_tabs.setObjectName("ResourcesTabs")
    col.addWidget(host.resources_tabs, 1)

    # Git tab: launcher panel (the dialog keeps its full behavior — LAN
    # server, workers, saved remotes — rather than being embedded).
    git_tab = QWidget()
    git_col = QVBoxLayout(git_tab)
    git_col.addStretch(1)
    git_hint = QLabel(
        "连接 Git 课程仓库：克隆 / 拉取 / 推送 / 局域网协作分享。"
    )
    git_hint.setAlignment(Qt.AlignmentFlag.AlignCenter)
    git_hint.setWordWrap(True)
    git_col.addWidget(git_hint)
    from src.widgets.ui.buttons import TurnaButton

    git_btn = TurnaButton(
        "打开 Git 资源库", variant="primary", icon_name="git-branch", parent=git_tab
    )
    git_btn.clicked.connect(host._on_git_library)
    git_col.addWidget(git_btn, 0, Qt.AlignmentFlag.AlignCenter)
    git_col.addStretch(1)
    host.resources_tabs.addTab(git_tab, "Git 资源库")
    host._resources_git_tab = git_tab
    return page


def ensure_resources_embedded(host: Any, initial_filter: str = "") -> Any:
    """Create/refresh the local-resources tab (teacher vocab vs full editor)."""
    from src.application.resources_controller import harvest_resource_selection

    teacher_mode = bool(getattr(host, "teacher_mode", False))
    existing = getattr(host, "_resources_editor", None)
    built_for = getattr(host, "_resources_built_for_teacher", None)
    had_editor_tab = existing is not None
    if existing is not None:
        # Guard against a stale wrapper whose C++ object is gone.
        try:
            from shiboken6 import isValid as _shiboken_is_valid

            alive = _shiboken_is_valid(existing)
        except ImportError:
            try:
                existing.isWidgetType()
                alive = True
            except RuntimeError:
                alive = False
        if not alive:
            existing = None
            host._resources_editor = None
    if existing is not None and built_for == teacher_mode:
        if initial_filter and hasattr(existing, "search_edit"):
            existing.search_edit.setText(str(initial_filter))
        return existing

    # Mode flipped (or first build): drop the stale tab content.
    if had_editor_tab:
        if existing is not None:
            harvest_resource_selection(host, existing)
            try:
                existing.setParent(None)
                existing.deleteLater()
            except Exception:
                pass
        host._resources_editor = None
        host.resources_tabs.removeTab(0)

    if teacher_mode:
        from src.teacher.vocab_table import VocabTableWidget

        editor = VocabTableWidget(host.adapter, host.resources_tabs)
    else:
        from src.widgets.resource_editor import ResourceEditorDialog

        editor = ResourceEditorDialog(
            host.adapter,
            host.resources_tabs,
            initial_filter=str(initial_filter or ""),
        )
    host.resources_tabs.insertTab(0, editor, "本地资源")
    host.resources_tabs.setCurrentIndex(0)
    host._resources_editor = editor
    host._resources_built_for_teacher = teacher_mode
    return editor


def _build_welcome_page(host: Any) -> QWidget:
    host.welcome_view = WelcomeView(
        on_new=host._on_new_course,
        on_open=host._on_open,
        on_open_recent=lambda path: host._open_repo_path(path),
        parent=host.central_stack,
    )
    return host.welcome_view


# ---------------------------------------------------------------------------
# View switching
# ---------------------------------------------------------------------------


def set_view(host: Any, key: str, *, initial_filter: str = "") -> None:
    """Switch the central stack to *key* (or open the workshop window)."""
    if key == "workshop":
        _open_workshop_view(host)
        return
    if key not in ("edit", "overview", "resources", "welcome"):
        return

    # Leaving the resources view harvests the editor selection + dirty flag
    # (the modal path used to do this on dialog close).
    previous = getattr(host, "_current_view", None)
    if previous == "resources" and key != "resources":
        try:
            from src.application.resources_controller import (
                harvest_resource_selection,
            )

            editor = getattr(host, "_resources_editor", None)
            if editor is not None:
                harvest_resource_selection(host, editor)
        except Exception:
            logger.debug("shell_views: resource harvest failed", exc_info=True)

    page = getattr(host, "_view_pages", {}).get(key)
    if page is None:
        return

    if key == "overview":
        overview = ensure_overview_embedded(host)
        overview.refresh()
    elif key == "resources":
        ensure_resources_embedded(host, initial_filter=initial_filter)

    host.central_stack.setCurrentWidget(page)
    host._current_view = key
    try:
        host.activity_bar.set_current(key)
    except Exception:
        logger.debug("shell_views: set_current failed", exc_info=True)
    if key != "welcome":
        qs = _qs(host)
        if qs is not None:
            with contextlib.suppress(Exception):
                qs.setValue(_SETTINGS_KEY_LAST_VIEW, key)
    _telemetry("shell.view_switched", view=key)


def current_view(host: Any) -> str:
    return str(getattr(host, "_current_view", "welcome"))


def sync_shell_views(host: Any) -> None:
    """Reconcile view availability + welcome/edit handoff with repo state.

    Called on startup (welcome) and whenever a repo is loaded
    (``enable_editor_actions``) — the three repo-gated rail items disable
    when ``course_dir`` is None, and the stack shows the welcome page.
    """
    has_repo = getattr(host, "course_dir", None) is not None
    items = getattr(host, "activity_bar_items", {})
    for key in ("edit", "workshop", "overview", "resources"):
        item = items.get(key)
        if item is not None:
            item.setEnabled(has_repo)

    if not has_repo:
        page = getattr(host, "_view_pages", {}).get("welcome")
        if page is not None:
            host.central_stack.setCurrentWidget(page)
            host._current_view = "welcome"
            for key in VIEW_KEYS:
                item = items.get(key)
                if item is not None and item.isCheckable():
                    item.setChecked(False)
        try:
            host.welcome_view.refresh_repos(host._load_recent_repos())
        except Exception:
            logger.debug("shell_views: welcome refresh failed", exc_info=True)
        return

    # Repo loaded: leave welcome for the persisted last view (default edit).
    if getattr(host, "_current_view", "welcome") == "welcome":
        target = "edit"
        qs = _qs(host)
        if qs is not None:
            try:
                saved = qs.value(_SETTINGS_KEY_LAST_VIEW, "edit")
                if isinstance(saved, str) and saved in ("edit", "overview", "resources"):
                    target = saved
            except Exception:
                target = "edit"
        set_view(host, target)


def reveal_edit_view(host: Any) -> None:
    """Surface the edit view before locating a node (W2 locate semantics).

    Safe on duck-typed hosts without ``_set_view`` and when no repo is
    loaded — in both cases the tree is unreachable anyway, so this no-ops.
    """
    try:
        set_view_fn = getattr(host, "_set_view", None)
        if callable(set_view_fn) and getattr(host, "course_dir", None) is not None:
            set_view_fn("edit")
    except Exception:
        pass


def notify_toast(
    host: Any,
    message: str,
    *,
    severity: str = "info",
    title: str = "",
    duration_ms: int = 4000,
) -> bool:
    """Show a non-blocking toast on the nearest window that can host one (W4).

    Host resolution (see :func:`_resolve_toast_host`): an explicit
    ``toast_host`` attribute on ``host`` (the shell), then the top-level
    window of an embedded widget (views inside the central stack resolve to
    MainWindow), then — for standalone windows/dialogs that are currently
    visible — a host created on demand. Returns True when a real
    ``ToastHost`` handled the message, False when no host could be found
    (tests / not-yet-shown windows / MagicMock hosts) — callers
    should fall back to ``QMessageBox`` in that case so existing
    notification assertions keep working. ``title`` is prepended when both
    exist so the toast keeps the original box's context.
    """
    toast_host = _resolve_toast_host(host)
    if not isinstance(toast_host, ToastHost):
        return False
    try:
        text = f"{title}：{message}" if title else message
        toast_host.show_toast(text, severity=severity, duration_ms=duration_ms)
        return True
    except Exception:
        logger.debug("notify_toast failed", exc_info=True)
        return False


def _resolve_toast_host(host: Any) -> ToastHost | None:
    """Locate (or lazily create) the :class:`ToastHost` for ``host``."""
    toast_host = getattr(host, "toast_host", None)
    if isinstance(toast_host, ToastHost):
        return toast_host
    window = host.window() if isinstance(host, QWidget) else None
    if window is not None:
        if window is not host:
            toast_host = getattr(window, "toast_host", None)
            if isinstance(toast_host, ToastHost):
                return toast_host
        # Lazily attach a host to a visible standalone window/dialog. Hidden
        # windows never get one: tests drive unshown widgets and rely on the
        # modal fallback path.
        if window.isWindow() and window.isVisible():
            try:
                toast_host = ToastHost(window)
                toast_host.show()
                window.toast_host = toast_host
                return toast_host
            except Exception:
                logger.debug(
                    "_resolve_toast_host lazy create failed", exc_info=True
                )
    return None


def toggle_sidebar(host: Any) -> None:
    """Ctrl+B — collapse/restore the edit-view course-tree sidebar."""
    sidebar = getattr(host, "tree_sidebar", None)
    if sidebar is None:
        return
    sidebar.setVisible(sidebar.isHidden())
    qs = _qs(host)
    if qs is not None:
        with contextlib.suppress(Exception):
            qs.setValue(_SETTINGS_KEY_SIDEBAR, not sidebar.isHidden())


def mark_saved(host: Any) -> None:
    """Update the status-bar save indicator after a successful save."""
    from datetime import datetime

    label = getattr(host, "save_state_label", None)
    if label is None:
        return
    host._last_saved_at = datetime.now()
    label.setText(f"✓ 已保存 {host._last_saved_at.strftime('%H:%M')}")
    label.setProperty("saveState", "clean")
    label.style().unpolish(label)
    label.style().polish(label)


def sync_save_state_label(host: Any) -> None:
    """Undo-stack clean state → ● 未保存 / ✓ 已保存 status text."""
    label = getattr(host, "save_state_label", None)
    if label is None:
        return
    if getattr(host, "course_dir", None) is None:
        label.setText("")
        return
    if host.undo_stack.isClean():
        last = getattr(host, "_last_saved_at", None)
        label.setText(
            f"✓ 已保存 {last.strftime('%H:%M')}" if last is not None else "✓ 已保存"
        )
        label.setProperty("saveState", "clean")
    else:
        label.setText("● 未保存")
        label.setProperty("saveState", "dirty")
    label.style().unpolish(label)
    label.style().polish(label)


# ---------------------------------------------------------------------------
# Activity-bar badges (W2 pipeline: overview / workshop / copilot)
# ---------------------------------------------------------------------------


def sync_activity_badges(host: Any) -> None:
    """Refresh rail badges: 总览=校验错误数(红) · 工坊=未导入项目 · Copilot=未读建议."""
    bar = getattr(host, "activity_bar", None)
    if bar is None:
        return
    for sync in (_sync_overview_badge, _sync_workshop_badge, _sync_copilot_badge):
        try:
            sync(host, bar)
        except Exception:
            logger.debug("shell_views: badge sync step failed", exc_info=True)


def _sync_overview_badge(host: Any, bar: Any) -> None:
    if getattr(host, "course_dir", None) is None:
        bar.set_badge("overview", 0, danger=True)
        return
    experience = getattr(host, "experience", None)
    ctx = getattr(experience, "context", None) if experience is not None else None
    count = int(getattr(ctx, "validate_error_count", 0) or 0)
    bar.set_badge("overview", count, danger=True)


def _sync_workshop_badge(host: Any, bar: Any) -> None:
    if getattr(host, "course_dir", None) is None:
        bar.set_badge("workshop", 0)
        return
    from src.backend.textbook_project_store import TextbookProjectStore

    summaries = TextbookProjectStore().list_project_summaries()
    pending = sum(1 for s in summaries if not getattr(s, "imported", False))
    bar.set_badge("workshop", pending)


def _sync_copilot_badge(host: Any, bar: Any) -> None:
    experience = getattr(host, "experience", None)
    suggestions = (
        list(getattr(experience, "suggestions", []) or [])
        if experience is not None
        else []
    )
    seen = getattr(host, "_shown_suggestion_keys", None)
    if seen is None:
        seen = set()
        host._shown_suggestion_keys = seen
    keys = {
        s.get("action_id")
        for s in suggestions
        if isinstance(s, dict) and s.get("action_id")
    }
    dock = getattr(host, "copilot_dock", None)
    if dock is not None and not dock.isHidden():
        # Dock visible → everything currently shown counts as read.
        seen.update(keys)
        bar.set_badge("copilot", 0)
        return
    bar.set_badge("copilot", len(keys - seen))


# ---------------------------------------------------------------------------
# Shortcuts
# ---------------------------------------------------------------------------


def _shortcut(host: Any, keys: str, slot) -> None:
    sc = QShortcut(QKeySequence(keys), host)
    sc.setContext(Qt.ShortcutContext.WindowShortcut)
    sc.activated.connect(slot)


def build_shell_shortcuts(host: Any) -> None:
    """Ctrl+1~4 views · B sidebar · J copilot · K palette · S save · , settings."""
    _shortcut(host, "Ctrl+1", functools.partial(set_view, host, "edit"))
    _shortcut(host, "Ctrl+2", functools.partial(set_view, host, "workshop"))
    _shortcut(host, "Ctrl+3", functools.partial(set_view, host, "overview"))
    _shortcut(host, "Ctrl+4", functools.partial(set_view, host, "resources"))
    _shortcut(host, "Ctrl+B", functools.partial(toggle_sidebar, host))
    _shortcut(host, "Ctrl+J", functools.partial(_toggle_copilot, host))
    # Ctrl+K lives on palette_action and Ctrl+, on settings_action (both
    # QActions added to the window in build_toolbar — a second QShortcut on
    # the same keys would make them ambiguous).


# ---------------------------------------------------------------------------
# Assembly + persistence
# ---------------------------------------------------------------------------


def build_shell(host: Any) -> QWidget:
    """Compose the W2 central widget: banner / rail / stack / preview strip."""
    container = QWidget(host)
    root = QVBoxLayout(container)
    root.setContentsMargins(0, 0, 0, 0)
    root.setSpacing(0)

    # AmbientBanner stays exactly where it was — self-hiding by design.
    root.addWidget(host.ambient_banner)

    body = QHBoxLayout()
    body.setContentsMargins(0, 0, 0, 0)
    body.setSpacing(0)
    root.addLayout(body, 1)

    _build_activity_bar(host, container)
    body.addWidget(host.activity_bar)

    center = QWidget()
    center_col = QVBoxLayout(center)
    center_col.setContentsMargins(0, 0, 0, 0)
    center_col.setSpacing(0)

    host.central_stack = QStackedWidget(center)
    host.central_stack.setObjectName("CentralStack")
    center_col.addWidget(host.central_stack, 1)

    # Orphan #2: the confirmation strip finally lives above the status bar.
    host.preview_host = PreviewHost(center)
    center_col.addWidget(host.preview_host)

    # W4: toast overlay pinned bottom-right of the content area; replaces
    # non-confirmation QMessageBox notifications via notify_toast().
    host.toast_host = ToastHost(center)

    body.addWidget(center, 1)

    # Stack pages (welcome/edit/overview/resources; workshop opens a window).
    host._view_pages = {
        "welcome": _build_welcome_page(host),
        "edit": _build_edit_page(host),
        "overview": _build_overview_page(host),
        "resources": _build_resources_page(host),
    }
    for key in STACK_KEYS:
        host.central_stack.addWidget(host._view_pages[key])

    host._current_view = "welcome"
    host.central_stack.setCurrentWidget(host._view_pages["welcome"])

    return container


def build_copilot_dock(host: Any) -> None:
    """Right-edge QDockWidget hosting ExperienceDock in a tab container."""
    dock = QDockWidget("Copilot", host)
    dock.setObjectName("CopilotDock")
    dock.setAllowedAreas(
        Qt.DockWidgetArea.RightDockWidgetArea | Qt.DockWidgetArea.LeftDockWidgetArea
    )
    rail = QTabWidget(dock)
    rail.setObjectName("RightRail")
    rail.setDocumentMode(True)
    rail.addTab(host.experience_dock_widget, "Copilot")
    dock.setWidget(rail)
    host.copilot_rail = rail
    host.copilot_dock = dock
    host.addDockWidget(Qt.DockWidgetArea.RightDockWidgetArea, dock)
    dock.setMinimumWidth(240)
    dock.setMaximumWidth(560)

    # Rail item ↔ dock visibility two-way sync.
    item = getattr(host, "activity_bar_items", {}).get("copilot")
    if item is not None:
        dock.visibilityChanged.connect(item.setChecked)
    # Persist visibility when it changes (cheap — QSettings write on toggle).
    dock.visibilityChanged.connect(
        functools.partial(_persist_copilot_visibility, host)
    )


def _persist_copilot_visibility(host: Any, _v: bool = False) -> None:
    qs = _qs(host)
    dock = getattr(host, "copilot_dock", None)
    if qs is None or dock is None:
        return
    with contextlib.suppress(Exception):
        qs.setValue(_SETTINGS_KEY_COPILOT, not dock.isHidden())


def restore_shell_state(host: Any) -> None:
    """Restore window geometry, dock layout, sidebar + copilot visibility."""
    qs = _qs(host)
    if qs is None:
        return
    try:
        geo = qs.value(_SETTINGS_KEY_GEOMETRY)
        if geo is not None:
            host.restoreGeometry(geo)
        state = qs.value(_SETTINGS_KEY_STATE)
        if state is not None:
            host.restoreState(state)
    except Exception:
        logger.debug("shell_views: restoreState failed", exc_info=True)

    # Explicit visibility keys (saveState covers position, not visibility).
    try:
        dock = getattr(host, "copilot_dock", None)
        if dock is not None:
            dock.setVisible(_qs_bool(host, _SETTINGS_KEY_COPILOT, True))
    except Exception:
        logger.debug("shell_views: copilot restore failed", exc_info=True)
    try:
        sidebar = getattr(host, "tree_sidebar", None)
        if sidebar is not None:
            sidebar.setVisible(_qs_bool(host, _SETTINGS_KEY_SIDEBAR, True))
    except Exception:
        logger.debug("shell_views: sidebar restore failed", exc_info=True)


def save_shell_state(host: Any) -> None:
    """Persist window geometry, dock layout, sidebar + copilot visibility."""
    qs = _qs(host)
    if qs is None:
        return
    try:
        qs.setValue(_SETTINGS_KEY_GEOMETRY, host.saveGeometry())
        qs.setValue(_SETTINGS_KEY_STATE, host.saveState())
        dock = getattr(host, "copilot_dock", None)
        if dock is not None:
            qs.setValue(_SETTINGS_KEY_COPILOT, not dock.isHidden())
        sidebar = getattr(host, "tree_sidebar", None)
        if sidebar is not None:
            qs.setValue(_SETTINGS_KEY_SIDEBAR, not sidebar.isHidden())
    except Exception:
        logger.debug("shell_views: save_shell_state failed", exc_info=True)
