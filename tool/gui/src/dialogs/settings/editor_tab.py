"""Editor behaviour + recent-repos tab for SettingsDialog (extracted)."""
from __future__ import annotations

from PySide6.QtCore import Qt
from PySide6.QtWidgets import (
    QCheckBox,
    QFormLayout,
    QGroupBox,
    QHBoxLayout,
    QListWidget,
    QListWidgetItem,
    QPushButton,
    QSpinBox,
    QVBoxLayout,
    QWidget,
)


def build_editor_tab(dlg) -> QWidget:
    tab, layout = dlg._make_tab()

    behaviour_group = QGroupBox("编辑器行为")
    behaviour_form = QFormLayout(behaviour_group)
    behaviour_form.setSpacing(10)

    dlg.auto_save_check = QCheckBox("关闭窗口时自动保存未保存的更改")
    behaviour_form.addRow(dlg.auto_save_check)

    dlg.undo_spin = QSpinBox()
    dlg.undo_spin.setRange(10, 500)
    behaviour_form.addRow("撤销步数上限:", dlg.undo_spin)

    layout.addWidget(behaviour_group)

    history_group = QGroupBox("最近仓库")
    history_layout = QVBoxLayout(history_group)
    history_layout.setSpacing(8)

    dlg.recent_list = QListWidget()
    history_layout.addWidget(dlg.recent_list)

    history_buttons = QHBoxLayout()
    history_buttons.setSpacing(8)
    dlg.remove_recent_btn = QPushButton("删除选中")
    dlg.remove_recent_btn.clicked.connect(dlg._on_remove_recent)
    dlg.clear_recent_btn = QPushButton("清空全部")
    dlg.clear_recent_btn.setObjectName("dangerButton")
    dlg.clear_recent_btn.clicked.connect(dlg._on_clear_recent)
    history_buttons.addWidget(dlg.remove_recent_btn)
    history_buttons.addWidget(dlg.clear_recent_btn)
    history_buttons.addStretch(1)
    history_layout.addLayout(history_buttons)

    layout.addWidget(history_group)
    return tab



def populate_recent_list(dlg) -> None:
    dlg.recent_list.clear()
    for repo in dlg._settings.recent_repos:
        path = repo.get("path", "")
        item = QListWidgetItem(path)
        item.setData(Qt.ItemDataRole.UserRole, path)
        dlg.recent_list.addItem(item)



def on_remove_recent(dlg) -> None:
    item = dlg.recent_list.currentItem()
    if item is None:
        return
    path = item.data(Qt.ItemDataRole.UserRole)
    dlg._settings.remove_recent_repo(path)
    dlg._populate_recent_list()



def on_clear_recent(dlg) -> None:
    if dlg._confirm_clear("清空历史", "确定要清空所有最近仓库历史吗？此操作不可撤销。"):
        dlg._settings.clear_recent_repos()
        dlg._populate_recent_list()

