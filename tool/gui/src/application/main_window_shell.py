"""Main-window shell construction (toolbar / central / status bar).

Extracted from ``src/app.py`` (P2 slim-down); every builder takes the
MainWindow (``host``) as context and assigns widget attributes back onto it,
so the window keeps all original attribute and method names.
"""
from __future__ import annotations

import functools

from PySide6.QtGui import QAction, QKeySequence
from PySide6.QtWidgets import (
    QLabel,
    QMenu,
    QStatusBar,
    QToolButton,
)

from src.theme import current_palette
from src.application.presence_mode import DEMOTE_SHORTCUT
from src.widgets.ambient_banner import AmbientBanner
from src.widgets.course_tree import CourseTreeWidget
from src.widgets.detail_panel import DetailPanel
from src.widgets.job_tray import JobTray


def build_undo_actions(host) -> None:
    host.undo_action = host.undo_stack.createUndoAction(host, "撤销")
    host.undo_action.setShortcut(QKeySequence.StandardKey.Undo)
    host.redo_action = host.undo_stack.createRedoAction(host, "重做")
    host.redo_action.setShortcut(QKeySequence.StandardKey.Redo)
    host.addAction(host.undo_action)
    host.addAction(host.redo_action)


def build_experience_actions(host) -> None:
    """Ctrl+Shift+D — demote experience mode back to copilot (one-key safety valve)."""
    host.demote_action = QAction("降档回 Copilot", host)
    host.demote_action.setShortcut(QKeySequence(DEMOTE_SHORTCUT))
    host.demote_action.triggered.connect(host._on_demote_experience)
    host.addAction(host.demote_action)


def build_toolbar(host) -> None:
    """Build the action/menu layer that feeds the Activity Bar.

    W2: the global QToolBar is gone — actions now live on the app menu
    (Activity Bar ☰), per-view headers, and keyboard shortcuts. Every
    public attribute (``repo_menu`` / ``save_action`` / ``mode_action`` …)
    is preserved because tests and controllers reference them.
    """
    host.repo_menu = QMenu(host)
    host.repo_menu.addAction("新建课程目录…").triggered.connect(host._on_new_course)
    host.repo_menu.addAction("打开课程目录…").triggered.connect(host._on_open)
    host.repo_menu.addSeparator()
    host.recent_menu = QMenu("最近仓库", host)
    host.recent_menu.aboutToShow.connect(host._populate_recent_menu)
    host.repo_menu.addMenu(host.recent_menu)
    host.repo_menu.addAction("清除历史记录").triggered.connect(host._clear_recent_repos)
    # repo_menu_btn is assigned to the ActivityBar menu button in
    # shell_views._build_activity_bar (kept for tests/preview).
    host.repo_menu_btn = QToolButton(host)
    host.repo_menu_btn.setMenu(host.repo_menu)
    host.repo_menu_btn.hide()

    host.save_action = QAction("保存", host)
    host.save_action.setShortcut(QKeySequence("Ctrl+S"))
    host.save_action.setEnabled(False)
    host.save_action.triggered.connect(host._on_save)
    host.addAction(host.save_action)

    host.workshop_action = QAction("课程工坊", host)
    host.workshop_action.setEnabled(False)
    host.workshop_action.setToolTip("教材 → 知识 → 课程，一站式创作工作区（Ctrl+2）")
    host.workshop_action.triggered.connect(host._on_workshop)

    host.overview_action = QAction("总览", host)
    host.overview_action.setEnabled(False)
    host.overview_action.setToolTip("课程结构总览（Section / Unit / Lesson 鸟瞰，点击定位）（Ctrl+3）")
    host.overview_action.triggered.connect(host._on_overview)

    host.resources_menu = QMenu(host)
    host.resources_menu.addAction("本地资源").triggered.connect(host._on_resources)
    host.resources_menu.addAction("Git 资源库").triggered.connect(host._on_git_library)
    host.resources_menu_btn = QToolButton(host)
    host.resources_menu_btn.setText("资源库")
    host.resources_menu_btn.setEnabled(False)
    host.resources_menu_btn.setPopupMode(QToolButton.ToolButtonPopupMode.InstantPopup)
    host.resources_menu_btn.setMenu(host.resources_menu)
    host.resources_menu_btn.hide()

    host.publish_action = QAction("发布", host)
    host.publish_action.setEnabled(False)
    host.publish_action.triggered.connect(host._on_publish)

    host.generate_audio_action = QAction("生成听力音频", host)
    host.generate_audio_action.setEnabled(False)
    host.generate_audio_action.setToolTip(
        "扫描课程中的听力阶段，用 MiniMax TTS 生成 audioAsset 对应的 MP3"
    )
    host.generate_audio_action.triggered.connect(host._on_generate_audio)

    # The rest of the app menu: publish / audio / palette / settings.
    host.repo_menu.addSeparator()
    host.repo_menu.addAction(host.publish_action)
    host.repo_menu.addAction(host.generate_audio_action)
    host.repo_menu.addSeparator()
    host.palette_action = QAction("命令面板", host)
    host.palette_action.setShortcut(QKeySequence("Ctrl+K"))
    host.palette_action.triggered.connect(host._open_command_palette)
    host.repo_menu.addAction(host.palette_action)
    # addAction too so Ctrl+K works even before the menu is opened.
    host.addAction(host.palette_action)
    host.repo_menu.addSeparator()

    host.mode_action = QAction("教师模式", host)
    host.mode_action.setCheckable(True)
    host.mode_action.toggled.connect(host._on_mode_toggled)

    host.settings_action = QAction("设置", host)
    host.settings_action.setShortcut(QKeySequence("Ctrl+,"))
    host.settings_action.triggered.connect(host._on_settings)
    host.repo_menu.addAction(host.settings_action)
    host.addAction(host.settings_action)



def build_central(host) -> None:
    from src.application import shell_views

    host.ambient_banner = AmbientBanner(host)
    host.ambient_banner.accepted.connect(host._on_ambient_accepted)
    host.ambient_banner.archived.connect(host._on_ambient_archived)
    host.ambient_banner.mute_changed.connect(host._on_ambient_mute_changed)
    # Banner is added to the shell root inside build_shell (same position:
    # top of the window, self-hiding when empty).

    host.tree = CourseTreeWidget()
    host.tree.undo_stack = host.undo_stack
    host.tree.node_selected.connect(host._on_node_selected)
    host.tree.tree_changed.connect(host._on_tree_changed)
    host.tree.ai_edit_requested.connect(host._on_ai_edit)
    host.tree.ai_fix_requested.connect(host._on_ai_fix_from_tree)
    host.tree.rename_requested.connect(host._on_rename_requested)

    host.detail = DetailPanel()
    host.detail.undo_stack = host.undo_stack
    host.detail.ai_config = host._ai_config
    # Detail edits change node labels without rebuilding the tree, so they
    # mark it stale; the tree's own tree_changed already rebuilt ithost.
    host.detail.tree_changed.connect(host._on_detail_tree_changed)

    # W2 shell: ActivityBar + CentralStack + PreviewHost strip (+ right
    # Copilot dock attached after the central widget is installed). The
    # banner is already the shell root's first child — same position as
    # before, self-hiding when empty.
    shell = shell_views.build_shell(host)
    host.setCentralWidget(shell)

    shell_views.build_copilot_dock(host)
    shell_views.build_shell_shortcuts(host)
    shell_views.restore_shell_state(host)
    shell_views.sync_shell_views(host)



_AI_DISCLAIMER = "AI 生成内容仅供参考，请作者自行审核其准确性与适用性。"


def build_status_bar(host) -> None:
    """Decluttered status bar: JobTray │ save-state │ health │ density │ theme.

    The AI disclaimer moves into the JobTray tooltip; the save indicator is
    driven by ``shell_views.sync_save_state_label`` / ``mark_saved``.
    """
    from src.application import shell_views
    from src.icons import icon as _icon
    from src.theme_tokens import PALETTES

    status = QStatusBar()
    status.setFixedHeight(28)

    host.job_tray = JobTray(host)
    host.job_tray.job_activated.connect(host._on_job_activated)
    host.job_tray.ai_busy_changed.connect(host._on_job_tray_ai_busy_changed)
    host.job_tray.setToolTip(_AI_DISCLAIMER)
    status.addPermanentWidget(host.job_tray)

    # Save-state indicator (● 未保存 / ✓ 已保存 HH:MM) — styled via QSS
    # (objectName + saveState property, see theme_styles/shell.py).
    host.save_state_label = QLabel("")
    host.save_state_label.setObjectName("SaveStateLabel")
    status.addPermanentWidget(host.save_state_label)
    shell_views.sync_save_state_label(host)

    host._health_status_label.setStyleSheet(
        f"color: {current_palette().get('text_secondary', '#888')}; font-size: 11px;"
    )
    status.addPermanentWidget(host._health_status_label)

    # Right end: density + theme quick-switch (buried in Settings before).
    host.density_btn = QToolButton(host)
    host.density_btn.setText("密度")
    host.density_btn.setIcon(_icon("layers", size=14, role="muted"))
    host.density_btn.setPopupMode(QToolButton.ToolButtonPopupMode.InstantPopup)
    host.density_btn.setToolTip("显示密度：舒适 / 紧凑")
    density_menu = QMenu(host.density_btn)

    def _apply_density(k: str, _checked: bool = False) -> None:
        host._set_density(k)

    for density_key, density_label in (
        ("comfortable", "舒适"),
        ("compact", "紧凑"),
    ):
        act = density_menu.addAction(density_label)
        act.setCheckable(True)
        act.setChecked(host._settings_obj.density == density_key)
        act.setData(density_key)
        act.triggered.connect(functools.partial(_apply_density, density_key))
    host.density_btn.setMenu(density_menu)
    status.addPermanentWidget(host.density_btn)

    host.theme_btn = QToolButton(host)
    host.theme_btn.setText("主题")
    host.theme_btn.setIcon(_icon("sparkles", size=14, role="muted"))
    host.theme_btn.setPopupMode(QToolButton.ToolButtonPopupMode.InstantPopup)
    host.theme_btn.setToolTip("界面主题")
    theme_menu = QMenu(host.theme_btn)

    def _apply_theme(k: str, _checked: bool = False) -> None:
        host._set_theme(k)

    _theme_labels = {
        "dark": "深色",
        "light": "浅色",
        "high-contrast-dark": "高对比 · 深色",
        "high-contrast-light": "高对比 · 浅色",
    }
    for theme_key in PALETTES:
        act = theme_menu.addAction(_theme_labels.get(theme_key, theme_key))
        act.setCheckable(True)
        act.setChecked(host._settings_obj.theme == theme_key)
        act.triggered.connect(functools.partial(_apply_theme, theme_key))
    host.theme_btn.setMenu(theme_menu)
    status.addPermanentWidget(host.theme_btn)

    host.setStatusBar(status)

