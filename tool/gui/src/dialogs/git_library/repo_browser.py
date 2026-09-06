"""Repo inspection domain: history / diff / file tree / reset / revert (E)."""
from __future__ import annotations

from PySide6.QtCore import Qt
from PySide6.QtWidgets import (
    QDialog,
    QHBoxLayout,
    QHeaderView,
    QLabel,
    QMenu,
    QMessageBox,
    QPushButton,
    QTableWidget,
    QTableWidgetItem,
    QTextEdit,
    QTreeWidget,
    QTreeWidgetItem,
    QVBoxLayout,
)


def build_inspect_section(dlg, sync_layout) -> None:
    """Diff-preview button + recent-commit history + repo file tree."""
    # Pre-push diff preview button
    dlg.diff_preview_btn = QPushButton("查看待推送改动 (diff)")
    dlg.diff_preview_btn.setEnabled(False)
    dlg.diff_preview_btn.clicked.connect(dlg._on_diff_preview)
    sync_layout.addWidget(dlg.diff_preview_btn)

    # Recent Commit History
    sync_layout.addWidget(QLabel("最近提交历史:"))
    dlg.history_table = QTableWidget(0, 4)
    dlg.history_table.setHorizontalHeaderLabels(["哈希", "作者", "日期", "提交信息"])
    dlg.history_table.horizontalHeader().setSectionResizeMode(3, QHeaderView.ResizeMode.Stretch)
    dlg.history_table.setEditTriggers(QTableWidget.EditTrigger.NoEditTriggers)
    dlg.history_table.setFixedHeight(100)
    dlg.history_table.setContextMenuPolicy(Qt.ContextMenuPolicy.CustomContextMenu)
    dlg.history_table.customContextMenuRequested.connect(dlg._on_history_context_menu)
    sync_layout.addWidget(dlg.history_table)

    # File tree browser for the cloned repo.
    sync_layout.addWidget(QLabel("仓库文件（双击在编辑器中打开）:"))
    dlg.file_tree = QTreeWidget()
    dlg.file_tree.setHeaderLabels(["文件"])
    dlg.file_tree.setFixedHeight(100)
    dlg.file_tree.itemDoubleClicked.connect(dlg._on_file_tree_double_click)
    sync_layout.addWidget(dlg.file_tree)


def refresh_history(dlg) -> None:
    if dlg._clone_dir is None or not (dlg._clone_dir / ".git").is_dir():
        dlg.history_table.setRowCount(0)
        return
    try:
        commits = dlg.git.get_history(dlg._clone_dir, count=5)
        dlg.history_table.setRowCount(len(commits))
        for row, commit in enumerate(commits):
            dlg.history_table.setItem(row, 0, QTableWidgetItem(commit["hash"]))
            dlg.history_table.setItem(row, 1, QTableWidgetItem(commit["author"]))
            dlg.history_table.setItem(row, 2, QTableWidgetItem(commit["date"]))
            dlg.history_table.setItem(row, 3, QTableWidgetItem(commit["message"]))
    except Exception as exc:
        dlg.history_table.setRowCount(0)
        # Surface the failure instead of leaving an empty table that
        # looks like a repo with no commits. (B4)
        dlg.status_label.setText(f"读取历史失败：{exc}")


def refresh_file_tree(dlg) -> None:
    dlg.file_tree.clear()
    if dlg._clone_dir is None or not (dlg._clone_dir / ".git").is_dir():
        return
    try:
        files = dlg.git.list_files(dlg._clone_dir)
        # Build a tree from file paths.
        root_item = QTreeWidgetItem(dlg.file_tree, [dlg._clone_dir.name])
        nodes: dict[str, QTreeWidgetItem] = {"": root_item}
        for fpath in sorted(files):
            if fpath.startswith(".git"):
                continue
            parts = fpath.split("/")
            parent_key = ""
            for i, part in enumerate(parts):
                key = "/".join(parts[: i + 1])
                if key not in nodes:
                    is_leaf = i == len(parts) - 1
                    node = QTreeWidgetItem(nodes[parent_key], [part])
                    if is_leaf:
                        node.setData(0, Qt.ItemDataRole.UserRole, fpath)
                    nodes[key] = node
                parent_key = key
        dlg.file_tree.expandItem(root_item)
    except Exception as exc:
        # Same rationale as refresh_branches: don't mask a broken repo
        # as an empty tree. (B4)
        dlg.status_label.setText(f"读取文件树失败：{exc}")


def on_file_tree_double_click(dlg, item) -> None:
    file_path = item.data(0, Qt.ItemDataRole.UserRole)
    if file_path and dlg._clone_dir is not None:
        full_path = dlg._clone_dir / file_path
        dlg.open_requested.emit(str(full_path))
        dlg.accept()


def on_diff_preview(dlg) -> None:
    if dlg._clone_dir is None:
        return
    try:
        diff_text = dlg.git.diff_working_vs_head(dlg._clone_dir, stat=True)
        if not diff_text.strip():
            QMessageBox.information(dlg, "无改动", "工作树与 HEAD 无差异。")
            return
        dlg2 = QDialog(dlg)
        dlg2.setWindowTitle("待推送改动（工作树 vs HEAD）")
        dlg2.resize(700, 500)
        layout = QVBoxLayout(dlg2)
        edit = QTextEdit()
        edit.setReadOnly(True)
        edit.setPlainText(diff_text)
        edit.setStyleSheet("font-family: monospace;")
        layout.addWidget(edit)
        dlg2.exec()
    except RuntimeError as exc:
        QMessageBox.critical(dlg, "Diff 失败", str(exc))


def on_history_context_menu(dlg, position) -> None:
    row = dlg.history_table.rowAt(position.y())
    if row < 0:
        return
    item = dlg.history_table.item(row, 0)
    if item is None:
        return
    ref = item.text()
    menu = QMenu(dlg)
    menu.addAction(f"Reset --hard 到 {ref}", lambda: dlg._on_reset_to(ref, "hard"))
    menu.addAction(f"Reset --soft 到 {ref}", lambda: dlg._on_reset_to(ref, "soft"))
    menu.addAction(f"Revert {ref}", lambda: dlg._on_revert(ref))
    menu.exec(dlg.history_table.viewport().mapToGlobal(position))


def on_reset_to(dlg, ref: str, mode: str) -> None:
    if dlg._clone_dir is None:
        return
    reply = QMessageBox.question(
        dlg, f"Reset {mode}",
        f"确定要 reset --{mode} 到 {ref} 吗？此操作可能丢失改动。",
        QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.Cancel,
        QMessageBox.StandardButton.Cancel,
    )
    if reply != QMessageBox.StandardButton.Yes:
        return
    dlg._run_git_async(
        f"reset --{mode}",
        dlg.git.reset_to,
        dlg._clone_dir,
        ref,
        mode,
        ok_title="已 reset",
        ok_message=f"已 reset --{mode} 到 {ref}。",
        error_title="reset 失败",
    )


def on_revert(dlg, ref: str) -> None:
    if dlg._clone_dir is None:
        return
    dlg._run_git_async(
        f"revert {ref}",
        dlg.git.revert,
        dlg._clone_dir,
        ref,
        ok_title="已 revert",
        ok_message=f"已 revert {ref}（创建新提交）。",
        error_title="revert 失败",
    )
