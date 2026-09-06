"""Branch management domain: list / create / switch / delete (D)."""
from __future__ import annotations

from PySide6.QtWidgets import QComboBox, QHBoxLayout, QInputDialog, QLabel, QMessageBox, QPushButton


def build_branch_row(dlg, sync_layout) -> None:
    """Branch selector row inside the sync tab."""
    branch_row = QHBoxLayout()
    branch_row.setSpacing(8)
    branch_row.addWidget(QLabel("分支:"))
    dlg.branch_combo = QComboBox()
    dlg.branch_combo.setMinimumWidth(150)
    dlg.branch_combo.currentIndexChanged.connect(dlg._on_branch_changed)
    branch_row.addWidget(dlg.branch_combo)
    dlg.new_branch_btn = QPushButton("新建")
    dlg.new_branch_btn.setEnabled(False)
    dlg.new_branch_btn.clicked.connect(dlg._on_new_branch)
    branch_row.addWidget(dlg.new_branch_btn)
    dlg.switch_branch_btn = QPushButton("切换")
    dlg.switch_branch_btn.setEnabled(False)
    dlg.switch_branch_btn.clicked.connect(dlg._on_switch_branch)
    branch_row.addWidget(dlg.switch_branch_btn)
    dlg.del_branch_btn = QPushButton("删除")
    dlg.del_branch_btn.setEnabled(False)
    dlg.del_branch_btn.clicked.connect(dlg._on_del_branch)
    branch_row.addWidget(dlg.del_branch_btn)
    branch_row.addStretch()
    sync_layout.addLayout(branch_row)


def refresh_branches(dlg) -> None:
    dlg.branch_combo.clear()
    if dlg._clone_dir is None or not (dlg._clone_dir / ".git").is_dir():
        return
    try:
        branches = dlg.git.list_branches(dlg._clone_dir)
        current = dlg.git.current_branch(dlg._clone_dir)
        for b in branches:
            dlg.branch_combo.addItem(b)
        idx = dlg.branch_combo.findText(current)
        if idx >= 0:
            dlg.branch_combo.setCurrentIndex(idx)
    except Exception as exc:
        # A broken repo (corrupted .git, missing HEAD) used to silently
        # produce an empty branch list with no status update, so the user
        # saw a blank combo and assumed the repo had no branches. Surface
        # the failure instead. (B4)
        dlg.status_label.setText(f"读取分支失败：{exc}")


def on_branch_changed(dlg, _index: int) -> None:
    pass  # selection only; switch happens on button click.


def on_new_branch(dlg) -> None:
    if dlg._clone_dir is None:
        return
    name, ok = QInputDialog.getText(dlg, "新建分支", "分支名:")
    if not ok or not name.strip():
        return
    dlg._run_git_async(
        "新建分支",
        dlg.git.create_branch,
        dlg._clone_dir,
        name.strip(),
        ok_title="已创建",
        ok_message=f"已创建并切换到分支 {name.strip()}。",
        error_title="新建分支失败",
    )


def on_switch_branch(dlg) -> None:
    if dlg._clone_dir is None:
        return
    name = dlg.branch_combo.currentText()
    if not name:
        return
    dlg._run_git_async(
        "切换分支",
        dlg.git.switch_branch,
        dlg._clone_dir,
        name,
        ok_title="已切换",
        ok_message=f"已切换到分支 {name}。",
        error_title="切换分支失败",
    )


def on_del_branch(dlg) -> None:
    if dlg._clone_dir is None:
        return
    name = dlg.branch_combo.currentText()
    if not name:
        return
    reply = QMessageBox.question(
        dlg, "删除分支", f"确定要删除分支 {name} 吗？",
        QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.Cancel,
        QMessageBox.StandardButton.Cancel,
    )
    if reply != QMessageBox.StandardButton.Yes:
        return
    dlg._run_git_async(
        "删除分支",
        dlg.git.delete_branch,
        dlg._clone_dir,
        name,
        ok_title="已删除",
        ok_message=f"已删除分支 {name}。",
        error_title="删除分支失败",
    )
