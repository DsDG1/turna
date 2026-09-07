"""Main-window shell construction (toolbar / central / status bar).

Extracted from ``src/app.py`` (P2 slim-down); every builder takes the
MainWindow (``host``) as context and assigns widget attributes back onto it,
so the window keeps all original attribute and method names.
"""
from __future__ import annotations

from PySide6.QtCore import Qt
from PySide6.QtGui import QAction, QKeySequence
from PySide6.QtWidgets import (
    QLabel,
    QMainWindow,
    QMenu,
    QSplitter,
    QStatusBar,
    QToolBar,
    QToolButton,
    QVBoxLayout,
    QWidget,
)

from src.theme import current_palette
from src.application.presence_mode import DEMOTE_SHORTCUT
from src.widgets.ambient_banner import AmbientBanner
from src.widgets.course_tree import CourseTreeWidget
from src.widgets.detail_panel import DetailPanel
from src.widgets.experience_dock import ExperienceDock
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
    toolbar = QToolBar("main")
    toolbar.setMovable(False)
    toolbar.setToolButtonStyle(Qt.ToolButtonStyle.ToolButtonTextBesideIcon)
    host.addToolBar(toolbar)

    host.repo_menu_btn = QToolButton(host)
    host.repo_menu_btn.setText("课程仓库")
    host.repo_menu_btn.setPopupMode(QToolButton.ToolButtonPopupMode.InstantPopup)
    host.repo_menu = QMenu(host)
    host.repo_menu.addAction("新建课程目录…").triggered.connect(host._on_new_course)
    host.repo_menu.addAction("打开课程目录…").triggered.connect(host._on_open)
    host.repo_menu.addSeparator()
    host.recent_menu = QMenu("最近仓库", host)
    host.recent_menu.aboutToShow.connect(host._populate_recent_menu)
    host.repo_menu.addMenu(host.recent_menu)
    host.repo_menu.addAction("清除历史记录").triggered.connect(host._clear_recent_repos)
    host.repo_menu_btn.setMenu(host.repo_menu)
    toolbar.addWidget(host.repo_menu_btn)

    host.save_action = QAction("保存", host)
    host.save_action.setEnabled(False)
    host.save_action.triggered.connect(host._on_save)
    toolbar.addAction(host.save_action)

    toolbar.addSeparator()

    host.workshop_action = QAction("课程工坊", host)
    host.workshop_action.setEnabled(False)
    host.workshop_action.setToolTip("教材 → 知识 → 课程，一站式创作工作区")
    host.workshop_action.triggered.connect(host._on_workshop)
    toolbar.addAction(host.workshop_action)

    host.overview_action = QAction("总览", host)
    host.overview_action.setEnabled(False)
    host.overview_action.setToolTip("课程结构总览（Section / Unit / Lesson 鸟瞰，点击定位）")
    host.overview_action.triggered.connect(host._on_overview)
    toolbar.addAction(host.overview_action)

    host.resources_menu_btn = QToolButton(host)
    host.resources_menu_btn.setText("资源库")
    host.resources_menu_btn.setEnabled(False)
    host.resources_menu_btn.setPopupMode(QToolButton.ToolButtonPopupMode.InstantPopup)
    host.resources_menu = QMenu(host)
    host.resources_menu.addAction("本地资源").triggered.connect(host._on_resources)
    host.resources_menu.addAction("Git 资源库").triggered.connect(host._on_git_library)
    host.resources_menu_btn.setMenu(host.resources_menu)
    toolbar.addWidget(host.resources_menu_btn)

    host.publish_action = QAction("发布", host)
    host.publish_action.setEnabled(False)
    host.publish_action.triggered.connect(host._on_publish)
    toolbar.addAction(host.publish_action)

    host.generate_audio_action = QAction("生成听力音频", host)
    host.generate_audio_action.setEnabled(False)
    host.generate_audio_action.setToolTip(
        "扫描课程中的听力阶段，用 MiniMax TTS 生成 audioAsset 对应的 MP3"
    )
    host.generate_audio_action.triggered.connect(host._on_generate_audio)
    toolbar.addAction(host.generate_audio_action)

    toolbar.addSeparator()

    host.mode_action = QAction("教师模式", host)
    host.mode_action.setCheckable(True)
    host.mode_action.toggled.connect(host._on_mode_toggled)
    toolbar.addAction(host.mode_action)

    toolbar.addSeparator()

    host.settings_action = QAction("设置", host)
    host.settings_action.triggered.connect(host._on_settings)
    toolbar.addAction(host.settings_action)



def build_central(host) -> None:
    container = QWidget(host)
    root_layout = QVBoxLayout(container)
    root_layout.setContentsMargins(0, 0, 0, 0)
    root_layout.setSpacing(0)

    host.ambient_banner = AmbientBanner(container)
    host.ambient_banner.accepted.connect(host._on_ambient_accepted)
    host.ambient_banner.archived.connect(host._on_ambient_archived)
    host.ambient_banner.mute_changed.connect(host._on_ambient_mute_changed)
    root_layout.addWidget(host.ambient_banner)

    splitter = QSplitter(Qt.Horizontal)

    host.tree = CourseTreeWidget()
    host.tree.undo_stack = host.undo_stack
    host.tree.node_selected.connect(host._on_node_selected)
    host.tree.tree_changed.connect(host._on_tree_changed)
    host.tree.ai_edit_requested.connect(host._on_ai_edit)
    host.tree.ai_fix_requested.connect(host._on_ai_fix_from_tree)
    host.tree.rename_requested.connect(host._on_rename_requested)
    splitter.addWidget(host.tree.wrap_with_move_toolbar())

    host.detail = DetailPanel()
    host.detail.undo_stack = host.undo_stack
    host.detail.ai_config = host._ai_config
    # Detail edits change node labels without rebuilding the tree, so they
    # mark it stale; the tree's own tree_changed already rebuilt ithost.
    host.detail.tree_changed.connect(host._on_detail_tree_changed)
    splitter.addWidget(host.detail)

    splitter.setStretchFactor(0, 2)
    splitter.setStretchFactor(1, 3)
    root_layout.addWidget(splitter, 1)
    host.setCentralWidget(container)



def build_status_bar(host) -> None:
    status = QStatusBar()
    status.setFixedHeight(28)

    host.job_tray = JobTray(host)
    host.job_tray.job_activated.connect(host._on_job_activated)
    status.addPermanentWidget(host.job_tray)

    host._health_status_label.setStyleSheet(
        f"color: {current_palette().get('text_secondary', '#888')}; font-size: 11px;"
    )
    status.addPermanentWidget(host._health_status_label)

    disclaimer = QLabel("AI 生成内容仅供参考，请作者自行审核其准确性与适用性。")
    disclaimer.setStyleSheet(
        f"color: {current_palette()['text_secondary']}; font-size: 11px;"
    )
    disclaimer.setToolTip(disclaimer.text())
    status.addPermanentWidget(disclaimer)
    host.setStatusBar(status)

