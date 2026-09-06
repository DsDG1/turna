"""Saved-remote catalog domain: double-click reconnect + save/delete (B)."""
from __future__ import annotations

from PySide6.QtWidgets import (
    QHBoxLayout,
    QHeaderView,
    QLabel,
    QMessageBox,
    QPushButton,
    QTableWidget,
    QTableWidgetItem,
    QVBoxLayout,
)


def build_remotes_section(dlg, sync_layout: QVBoxLayout) -> None:
    """Saved remotes table (one-click reconnect) at the top of the sync tab."""
    sync_layout.addWidget(QLabel("已保存的远程仓库（双击连接）:"))
    dlg.remotes_table = QTableWidget(0, 4)
    dlg.remotes_table.setHorizontalHeaderLabels(["名称", "URL", "本地目录", "语言"])
    dlg.remotes_table.horizontalHeader().setSectionResizeMode(1, QHeaderView.ResizeMode.Stretch)
    dlg.remotes_table.setEditTriggers(QTableWidget.EditTrigger.NoEditTriggers)
    dlg.remotes_table.setSelectionBehavior(QTableWidget.SelectionBehavior.SelectRows)
    dlg.remotes_table.setFixedHeight(100)
    dlg.remotes_table.doubleClicked.connect(dlg._on_remote_double_click)
    sync_layout.addWidget(dlg.remotes_table)

    remotes_btn_row = QHBoxLayout()
    remotes_btn_row.setSpacing(6)
    dlg.save_remote_btn = QPushButton("保存当前为远程")
    dlg.save_remote_btn.setToolTip("把当前填写的 URL/目录/语言保存为命名远程")
    dlg.save_remote_btn.clicked.connect(dlg._on_save_current_remote)
    remotes_btn_row.addWidget(dlg.save_remote_btn)
    dlg.del_remote_btn = QPushButton("删除选中")
    dlg.del_remote_btn.clicked.connect(dlg._on_del_saved_remote)
    remotes_btn_row.addWidget(dlg.del_remote_btn)
    remotes_btn_row.addStretch()
    sync_layout.addLayout(remotes_btn_row)


def populate_saved_remotes(dlg) -> None:
    from src.application import git_remote_catalog

    remotes = git_remote_catalog.load_remotes()
    dlg.remotes_table.setRowCount(len(remotes))
    for row, r in enumerate(remotes):
        dlg.remotes_table.setItem(row, 0, QTableWidgetItem(r.name))
        dlg.remotes_table.setItem(row, 1, QTableWidgetItem(r.url))
        dlg.remotes_table.setItem(row, 2, QTableWidgetItem(r.local_dir))
        dlg.remotes_table.setItem(row, 3, QTableWidgetItem(r.lang))


def on_remote_double_click(dlg, index) -> None:
    from src.application import git_remote_catalog

    row = index.row()
    if row < 0:
        return
    # QTableWidget.item(row, col) returns None if the cell was never
    # populated (corrupt catalog); guard each lookup instead of crashing
    # with AttributeError on .text(). (B3)
    def _cell(col: int) -> str:
        item = dlg.remotes_table.item(row, col)
        return item.text() if item is not None else ""
    name = _cell(0)
    url = _cell(1)
    local_dir = _cell(2)
    lang = _cell(3)
    if url:
        dlg.url_edit.setText(url)
    if local_dir:
        dlg.dir_edit.setText(local_dir)
    if lang:
        dlg.lang_edit.setText(lang)
    # Auto-connect.
    if url and local_dir:
        dlg._on_connect()
        git_remote_catalog.mark_synced(name)


def on_save_current_remote(dlg) -> None:
    from src.application import git_remote_catalog

    url = dlg.url_edit.text().strip()
    local_dir = dlg.dir_edit.text().strip()
    if not url:
        QMessageBox.warning(dlg, "缺少 URL", "请先填写远程仓库 URL。")
        return
    # Derive a name from the URL if none exists.
    name = url.rstrip("/").split("/")[-1].replace(".git", "") or "remote"
    existing = git_remote_catalog.find_by_url(url)
    if existing:
        name = existing.name
    remote = git_remote_catalog.SavedRemote(
        name=name,
        url=url,
        local_dir=local_dir,
        lang=dlg.lang_edit.text().strip(),
    )
    git_remote_catalog.add_remote(remote)
    populate_saved_remotes(dlg)
    QMessageBox.information(dlg, "已保存", f"远程「{name}」已保存。")


def on_del_saved_remote(dlg) -> None:
    from src.application import git_remote_catalog

    row = dlg.remotes_table.currentRow()
    if row < 0:
        return
    item = dlg.remotes_table.item(row, 0)
    if item is None:
        return
    name = item.text()
    git_remote_catalog.remove_remote(name)
    populate_saved_remotes(dlg)
