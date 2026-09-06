"""Connect / sync domain: clone, fetch, pull, push, copy-to-assets, resources (C)."""
from __future__ import annotations

import logging
from datetime import datetime
from pathlib import Path

from PySide6.QtWidgets import (
    QFileDialog,
    QFormLayout,
    QHBoxLayout,
    QInputDialog,
    QLabel,
    QLineEdit,
    QMessageBox,
    QPushButton,
    QVBoxLayout,
    QWidget,
)

logger = logging.getLogger(__name__)


def build_sync_tab(dlg):
    """Tab 1: Remote Collaboration & Sync (assembly; handlers live per-domain)."""
    from src.dialogs.git_library import branches, remotes, repo_browser

    dlg.sync_tab = QWidget()
    sync_layout = QVBoxLayout(dlg.sync_tab)
    sync_layout.setSpacing(10)
    sync_layout.setContentsMargins(8, 8, 8, 8)

    remotes.build_remotes_section(dlg, sync_layout)

    form = QFormLayout()
    form.setSpacing(8)
    dlg.url_edit = QLineEdit()
    dlg.url_edit.setPlaceholderText("https://github.com/you/my-turkish-course.git 或局域网协作地址")
    form.addRow("远程仓库 URL:", dlg.url_edit)

    dir_row = QHBoxLayout()
    dir_row.setSpacing(8)
    dlg.dir_edit = QLineEdit()
    dlg.dir_edit.setPlaceholderText("本地克隆目录")
    dir_row.addWidget(dlg.dir_edit, 1)
    browse = QPushButton("浏览...")
    browse.clicked.connect(dlg._on_browse)
    dir_row.addWidget(browse)
    form.addRow("本地目录:", dir_row)

    dlg.lang_edit = QLineEdit()
    dlg.lang_edit.setPlaceholderText("例如：tr / en / sw（用于复制到 assets/courses/<lang>）")
    form.addRow("语言代码:", dlg.lang_edit)
    sync_layout.addLayout(form)

    connect_row = QHBoxLayout()
    dlg.connect_btn = QPushButton("连接 / 克隆")
    dlg.connect_btn.setToolTip("克隆远程仓库到本地目录（已存在则拉取最新）")
    dlg.connect_btn.clicked.connect(dlg._on_connect)
    connect_row.addWidget(dlg.connect_btn)
    connect_row.addStretch()
    sync_layout.addLayout(connect_row)

    # Action buttons
    actions = QHBoxLayout()
    actions.setSpacing(8)

    dlg.open_btn = QPushButton("在编辑器中打开")
    dlg.open_btn.setEnabled(False)
    dlg.open_btn.clicked.connect(dlg._on_open)
    actions.addWidget(dlg.open_btn)

    dlg.fetch_btn = QPushButton("检查更新")
    dlg.fetch_btn.setEnabled(False)
    dlg.fetch_btn.clicked.connect(dlg._on_fetch)
    actions.addWidget(dlg.fetch_btn)

    dlg.pull_btn = QPushButton("拉取最新")
    dlg.pull_btn.setEnabled(False)
    dlg.pull_btn.clicked.connect(dlg._on_pull)
    actions.addWidget(dlg.pull_btn)

    dlg.push_btn = QPushButton("保存并推送 (push)")
    dlg.push_btn.setEnabled(False)
    dlg.push_btn.clicked.connect(dlg._on_push)
    actions.addWidget(dlg.push_btn)

    dlg.copy_btn = QPushButton("复制到 assets")
    dlg.copy_btn.setEnabled(False)
    dlg.copy_btn.clicked.connect(dlg._on_copy_to_assets)
    actions.addWidget(dlg.copy_btn)

    dlg.sync_res_btn = QPushButton("同步资源池")
    dlg.sync_res_btn.setToolTip("双向合并本地资源与 Git 仓库的 vocab/expressions/grammar")
    dlg.sync_res_btn.setEnabled(False)
    dlg.sync_res_btn.clicked.connect(dlg._on_sync_resources)
    actions.addWidget(dlg.sync_res_btn)

    actions.addStretch()
    sync_layout.addLayout(actions)

    # Branch selector
    branches.build_branch_row(dlg, sync_layout)

    # History / file tree / diff preview
    repo_browser.build_inspect_section(dlg, sync_layout)

    return dlg.sync_tab


def on_browse(dlg) -> None:
    chosen = QFileDialog.getExistingDirectory(dlg, "选择本地克隆目录", dlg.dir_edit.text() or "")
    if chosen:
        dlg.dir_edit.setText(chosen)


def on_connect(dlg) -> None:
    url = dlg.url_edit.text().strip()
    local = dlg.dir_edit.text().strip()
    if not url or not local:
        QMessageBox.warning(dlg, "信息不完整", "请填写远程仓库 URL 和本地目录。")
        return
    local_path = Path(local)
    dlg._run_git_async(
        "连接",
        dlg.git.clone,
        url,
        local_path,
        on_ok=lambda _result: setattr(dlg, "_clone_dir", local_path),
        ok_title="连接成功",
        ok_message=f"已就绪：{local_path}",
        error_title="连接失败",
    )


def on_open(dlg) -> None:
    if dlg._clone_dir is None:
        return
    dlg.open_requested.emit(str(dlg._clone_dir))
    dlg.accept()


def on_fetch(dlg) -> None:
    if dlg._clone_dir is None:
        return
    dlg._run_git_async(
        "获取最新状态",
        dlg.git.fetch,
        dlg._clone_dir,
        ok_title="获取完成",
        ok_message="已获取远程最新状态。",
        error_title="获取状态失败",
    )


def on_pull(dlg) -> None:
    if dlg._clone_dir is None:
        return
    dlg._run_git_async(
        "拉取",
        dlg.git.pull,
        dlg._clone_dir,
        on_ok=lambda _r: None,
        ok_title="已是最新",
        ok_message="已拉取远程最新内容。",
        error_title="拉取失败",
        on_error=lambda message: on_pull_conflict(dlg, message),
    )


def on_pull_conflict(dlg, message: str) -> None:
    """Offer conflict resolution options when pull --ff-only fails."""
    if dlg._clone_dir is None:
        return
    reply = QMessageBox.question(
        dlg,
        "拉取冲突",
        f"快进拉取失败（可能有分叉提交）。\n\n{message}\n\n"
        f"选择解决方式：\n"
        f"  Yes = Rebase（推荐，保持线性历史）\n"
        f"  No = Stash + Pull + Pop（暂存本地改动后拉取）\n"
        f"  Cancel = 放弃",
        QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No | QMessageBox.StandardButton.Cancel,
        QMessageBox.StandardButton.Yes,
    )
    if reply == QMessageBox.StandardButton.Yes:
        dlg._run_git_async(
            "rebase",
            dlg.git.pull_rebase,
            dlg._clone_dir,
            ok_title="Rebase 成功",
            ok_message="已 rebase 到远程最新。",
            error_title="Rebase 失败",
        )
    elif reply == QMessageBox.StandardButton.No:
        def _after_stash(_r: object) -> None:
            dlg._run_git_async(
                "pull",
                dlg.git.pull,
                dlg._clone_dir,
                on_ok=lambda _r2: dlg._run_git_async(
                    "stash pop",
                    dlg.git.stash_pop,
                    dlg._clone_dir,
                    ok_title="已完成",
                    ok_message="已暂存+拉取+恢复本地改动。",
                    error_title="恢复改动失败",
                ),
                error_title="拉取失败",
            )
        dlg._run_git_async(
            "stash",
            dlg.git.stash,
            dlg._clone_dir,
            on_ok=_after_stash,
            error_title="暂存失败",
        )


def on_push(dlg) -> None:
    if dlg._clone_dir is None:
        return

    # Auto-save current editor state if it's active
    parent = dlg.parent()
    if parent is not None and getattr(parent, "course_dir", None) == dlg._clone_dir:
        if hasattr(parent, "_on_save"):
            parent._on_save()

    # Confirm push
    reply = QMessageBox.question(
        dlg,
        "保存并推送",
        "确定要推送本地改动吗？\n当前编辑的改动已被自动保存。",
        QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.Cancel,
        QMessageBox.StandardButton.Yes,
    )
    if reply != QMessageBox.StandardButton.Yes:
        return
    msg, ok = commit_message(dlg)
    if not ok:
        return
    dlg._run_git_async(
        "推送",
        dlg.git.commit_and_push,
        dlg._clone_dir,
        msg,
        ok_title="已推送",
        ok_message="本地改动已提交并推送到远程。",
        error_title="推送失败",
    )


def commit_message(dlg) -> tuple[str, bool]:
    default_msg = f"自动保存: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"
    text, ok = QInputDialog.getText(
        dlg, "提交信息", "提交信息（commit message）：", text=default_msg
    )
    return (text.strip() or default_msg, bool(ok))


def on_copy_to_assets(dlg) -> None:
    if dlg._clone_dir is None:
        return
    lang = dlg.lang_edit.text().strip()
    if not lang:
        QMessageBox.warning(dlg, "缺少语言代码", "请填写语言代码以确定 assets 目标目录。")
        return
    from src.backend.git_library import GitLibrary

    # Use configurable repo_root from settings if set.
    repo_root = None
    if dlg._settings is not None and dlg._settings.assets_repo_root:
        repo_root = Path(dlg._settings.assets_repo_root)
    try:
        if repo_root:
            target = GitLibrary.save_to_assets(dlg._clone_dir, lang, repo_root=repo_root)
        else:
            target = GitLibrary.save_to_assets(dlg._clone_dir, lang)
    except FileExistsError as exc:
        reply = QMessageBox.question(
            dlg,
            "目标已存在",
            f"{exc}\
\
是否覆盖？",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.Cancel,
            QMessageBox.StandardButton.Cancel,
        )
        if reply != QMessageBox.StandardButton.Yes:
            return
        try:
            target = GitLibrary.save_to_assets(
                dlg._clone_dir, lang, overwrite=True
            )
        except RuntimeError as exc2:
            QMessageBox.critical(dlg, "复制失败", str(exc2))
            return
    except RuntimeError as exc:
        QMessageBox.critical(dlg, "复制失败", str(exc))
        return
    QMessageBox.information(
        dlg,
        "已复制到 assets",
        f"课程已写入：\n{target}\n\n打包时会随 app 一起分发。",
    )


def on_sync_resources(dlg) -> None:
    if dlg._clone_dir is None:
        return
    lang = dlg.lang_edit.text().strip()
    if not lang:
        QMessageBox.warning(dlg, "缺少语言代码", "请填写语言代码。")
        return
    reply = QMessageBox.question(
        dlg, "同步资源池",
        f"将本地课程资源与 Git 仓库 {dlg._clone_dir} 双向合并？",
        QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.Cancel,
        QMessageBox.StandardButton.Cancel,
    )
    if reply != QMessageBox.StandardButton.Yes:
        return
    try:
        result = dlg.adapter.sync_resources_with_git(dlg._clone_dir, lang)
        QMessageBox.information(
            dlg, "同步完成",
            f"资源同步完成：\
{result}",
        )
    except Exception as exc:
        QMessageBox.critical(dlg, "同步失败", str(exc))
