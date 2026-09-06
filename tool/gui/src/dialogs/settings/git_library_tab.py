"""Git library configuration tab for SettingsDialog (extracted)."""
from __future__ import annotations

from PySide6.QtWidgets import (
    QComboBox,
    QDoubleSpinBox,
    QFileDialog,
    QFormLayout,
    QGroupBox,
    QHBoxLayout,
    QHeaderView,
    QLabel,
    QLineEdit,
    QMessageBox,
    QPushButton,
    QSpinBox,
    QTableWidget,
    QTableWidgetItem,
    QVBoxLayout,
    QWidget,
)

from src.application import credential_store
from src.application import git_remote_catalog


def build_git_library_tab(dlg) -> QWidget:
    """Git library configuration: clone root, git bin, LAN defaults, saved remotes, credentials."""
    tab, layout = dlg._make_tab()

    # --- Basic config ---
    basic_group = QGroupBox("基础配置")
    basic_form = QFormLayout(basic_group)
    basic_form.setSpacing(10)

    clone_root_row = QHBoxLayout()
    dlg.git_clone_root_edit = QLineEdit()
    dlg.git_clone_root_edit.setPlaceholderText("默认克隆目录，如 ~/.turna/course-clones")
    clone_root_row.addWidget(dlg.git_clone_root_edit, 1)
    browse_clone = QPushButton("浏览...")
    browse_clone.clicked.connect(dlg._on_browse_clone_root_clicked)
    clone_root_row.addWidget(browse_clone)
    basic_form.addRow("克隆根目录:", clone_root_row)

    dlg.git_bin_edit = QLineEdit()
    dlg.git_bin_edit.setPlaceholderText("留空则使用系统 git")
    basic_form.addRow("Git 二进制路径:", dlg.git_bin_edit)

    dlg.default_lang_edit = QLineEdit()
    dlg.default_lang_edit.setPlaceholderText("如 tr / en / sw")
    basic_form.addRow("默认语言代码:", dlg.default_lang_edit)

    dlg.git_timeout_spin = QDoubleSpinBox()
    dlg.git_timeout_spin.setRange(5.0, 600.0)
    dlg.git_timeout_spin.setSuffix(" 秒")
    dlg.git_timeout_spin.setDecimals(1)
    basic_form.addRow("Git 操作超时:", dlg.git_timeout_spin)

    assets_row = QHBoxLayout()
    dlg.assets_repo_root_edit = QLineEdit()
    dlg.assets_repo_root_edit.setPlaceholderText("留空则自动检测（项目根目录）")
    assets_row.addWidget(dlg.assets_repo_root_edit, 1)
    browse_assets = QPushButton("浏览...")
    browse_assets.clicked.connect(dlg._on_browse_assets_root_clicked)
    assets_row.addWidget(browse_assets)
    basic_form.addRow("Assets 仓库根目录:", assets_row)

    layout.addWidget(basic_group)

    # --- LAN server defaults ---
    lan_group = QGroupBox("局域网协作默认")
    lan_form = QFormLayout(lan_group)
    lan_form.setSpacing(10)

    dlg.lan_port_spin = QSpinBox()
    dlg.lan_port_spin.setRange(1, 65535)
    lan_form.addRow("默认端口:", dlg.lan_port_spin)

    dlg.lan_bind_combo = QComboBox()
    dlg.lan_bind_combo.addItem("所有网卡 (0.0.0.0)", "0.0.0.0")
    dlg.lan_bind_combo.addItem("仅本机 (127.0.0.1)", "127.0.0.1")
    lan_form.addRow("绑定地址:", dlg.lan_bind_combo)

    dlg.lan_token_edit = QLineEdit()
    dlg.lan_token_edit.setEchoMode(QLineEdit.EchoMode.Password)
    dlg.lan_token_edit.setPlaceholderText("留空则不鉴权（局域网内任意可访问）")
    lan_form.addRow("访问令牌:", dlg.lan_token_edit)

    layout.addWidget(lan_group)

    # --- SSH key ---
    ssh_group = QGroupBox("SSH 密钥")
    ssh_form = QFormLayout(ssh_group)
    ssh_form.setSpacing(10)
    ssh_row = QHBoxLayout()
    dlg.ssh_key_edit = QLineEdit()
    dlg.ssh_key_edit.setPlaceholderText("~/.ssh/id_ed25519")
    ssh_row.addWidget(dlg.ssh_key_edit, 1)
    browse_ssh = QPushButton("浏览...")
    browse_ssh.clicked.connect(dlg._pick_ssh_key)
    ssh_row.addWidget(browse_ssh)
    ssh_form.addRow("私钥路径:", ssh_row)
    layout.addWidget(ssh_group)

    # --- Saved remotes ---
    remotes_group = QGroupBox("已保存的远程仓库")
    remotes_layout = QVBoxLayout(remotes_group)
    remotes_layout.setSpacing(8)

    dlg.remotes_table = QTableWidget(0, 4)
    dlg.remotes_table.setHorizontalHeaderLabels(["名称", "URL", "本地目录", "语言"])
    dlg.remotes_table.horizontalHeader().setSectionResizeMode(1, QHeaderView.ResizeMode.Stretch)
    dlg.remotes_table.setEditTriggers(QTableWidget.EditTrigger.NoEditTriggers)
    dlg.remotes_table.setSelectionBehavior(QTableWidget.SelectionBehavior.SelectRows)
    dlg.remotes_table.setFixedHeight(140)
    remotes_layout.addWidget(dlg.remotes_table)

    remotes_btn_row = QHBoxLayout()
    remotes_btn_row.setSpacing(8)
    dlg.add_remote_btn = QPushButton("添加...")
    dlg.add_remote_btn.clicked.connect(dlg._on_add_remote)
    remotes_btn_row.addWidget(dlg.add_remote_btn)
    dlg.edit_remote_btn = QPushButton("编辑...")
    dlg.edit_remote_btn.clicked.connect(dlg._on_edit_remote)
    remotes_btn_row.addWidget(dlg.edit_remote_btn)
    dlg.del_remote_btn = QPushButton("删除")
    dlg.del_remote_btn.clicked.connect(dlg._on_del_remote)
    remotes_btn_row.addWidget(dlg.del_remote_btn)
    remotes_btn_row.addStretch(1)
    remotes_layout.addLayout(remotes_btn_row)

    layout.addWidget(remotes_group)

    # --- Credentials ---
    cred_group = QGroupBox("HTTPS 凭据")
    cred_layout = QVBoxLayout(cred_group)
    cred_layout.setSpacing(8)

    dlg.keyring_status_label = QLabel("检测中...")
    dlg.keyring_status_label.setObjectName("hintLabel")
    dlg.keyring_status_label.setWordWrap(True)
    cred_layout.addWidget(dlg.keyring_status_label)

    cred_form = QFormLayout()
    cred_form.setSpacing(8)
    dlg.cred_url_combo = QComboBox()
    dlg.cred_url_combo.setEditable(True)
    cred_form.addRow("远程 URL:", dlg.cred_url_combo)
    cred_row = QHBoxLayout()
    dlg.set_token_btn = QPushButton("设置/更新令牌")
    dlg.set_token_btn.clicked.connect(dlg._on_set_token)
    cred_row.addWidget(dlg.set_token_btn)
    dlg.del_token_btn = QPushButton("删除令牌")
    dlg.del_token_btn.clicked.connect(dlg._on_del_token)
    cred_row.addWidget(dlg.del_token_btn)
    cred_row.addStretch(1)
    cred_form.addRow(cred_row)
    cred_layout.addLayout(cred_form)

    layout.addWidget(cred_group)
    layout.addStretch(1)
    return tab



def on_browse_clone_root_clicked(dlg) -> None:
    dlg._pick_dir(dlg.git_clone_root_edit)



def on_browse_assets_root_clicked(dlg) -> None:
    dlg._pick_dir(dlg.assets_repo_root_edit)



def pick_dir(dlg, line_edit: QLineEdit) -> None:
    chosen = QFileDialog.getExistingDirectory(dlg, "选择目录", line_edit.text() or "")
    if chosen:
        line_edit.setText(chosen)


def pick_ssh_key(dlg) -> None:
    from pathlib import Path
    start = dlg.ssh_key_edit.text() or str(Path.home() / ".ssh")
    chosen, _ = QFileDialog.getOpenFileName(dlg, "选择 SSH 私钥", start, "All Files (*)")
    if chosen:
        dlg.ssh_key_edit.setText(chosen)


def populate_remotes_table(dlg) -> None:
    remotes = git_remote_catalog.load_remotes()
    dlg.remotes_table.setRowCount(len(remotes))
    for row, r in enumerate(remotes):
        dlg.remotes_table.setItem(row, 0, QTableWidgetItem(r.name))
        dlg.remotes_table.setItem(row, 1, QTableWidgetItem(r.url))
        dlg.remotes_table.setItem(row, 2, QTableWidgetItem(r.local_dir))
        dlg.remotes_table.setItem(row, 3, QTableWidgetItem(r.lang))
    # Also refresh the credential URL combo.
    dlg.cred_url_combo.clear()
    for r in remotes:
        dlg.cred_url_combo.addItem(r.url)



def refresh_keyring_status(dlg) -> None:
    status = credential_store.keyring_status()
    if status["available"]:
        dlg.keyring_status_label.setText(
            f"✓ keyring 可用（后端：{status['backend']}）。HTTPS 令牌将安全存储。"
        )
    else:
        dlg.keyring_status_label.setText(
            "⚠ keyring 后端不可用，令牌将回退到 QSettings 存储（安全性较低）。"
        )



def on_add_remote(dlg) -> None:
    from PySide6.QtWidgets import QInputDialog
    name, ok = QInputDialog.getText(dlg, "新建远程", "名称:")
    if not ok or not name.strip():
        return
    name = name.strip()
    remotes = git_remote_catalog.load_remotes()
    if any(r.name == name for r in remotes):
        QMessageBox.warning(dlg, "重名", f"已存在名为「{name}」的远程。")
        return
    remote = git_remote_catalog.SavedRemote(
        name=name,
        url="",
        local_dir=dlg.git_clone_root_edit.text().strip(),
        lang=dlg.default_lang_edit.text().strip(),
    )
    remotes = git_remote_catalog.add_remote(remote)
    dlg._populate_remotes_table()
    dlg._edit_remote_dialog(name)



def on_edit_remote(dlg) -> None:
    row = dlg.remotes_table.currentRow()
    if row < 0:
        QMessageBox.information(dlg, "编辑远程", "请先选中一个远程。")
        return
    name = dlg.remotes_table.item(row, 0).text()
    dlg._edit_remote_dialog(name)



def edit_remote_dialog(dlg, name: str) -> None:
    remotes = git_remote_catalog.load_remotes()
    target = next((r for r in remotes if r.name == name), None)
    if target is None:
        return
    from PySide6.QtWidgets import QDialog, QDialogButtonBox
    dlg = QDialog(dlg)
    dlg.setWindowTitle(f"编辑远程：{name}")
    form = QFormLayout(dlg)
    name_edit = QLineEdit(target.name)
    url_edit = QLineEdit(target.url)
    url_edit.setPlaceholderText("https://github.com/you/repo.git")
    dir_edit = QLineEdit(target.local_dir)
    dir_edit.setPlaceholderText("本地克隆目录")
    lang_edit = QLineEdit(target.lang)
    lang_edit.setPlaceholderText("tr / en / sw")
    form.addRow("名称:", name_edit)
    form.addRow("URL:", url_edit)
    form.addRow("本地目录:", dir_edit)
    form.addRow("语言代码:", lang_edit)
    buttons = QDialogButtonBox(
        QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel
    )
    buttons.accepted.connect(dlg.accept)
    buttons.rejected.connect(dlg.reject)
    form.addRow(buttons)
    if dlg.exec() == QDialog.DialogCode.Accepted:
        new_name = name_edit.text().strip()
        git_remote_catalog.update_remote(
            name,
            new_name=new_name,
            url=url_edit.text().strip(),
            local_dir=dir_edit.text().strip(),
            lang=lang_edit.text().strip(),
        )
        dlg._populate_remotes_table()



def on_del_remote(dlg) -> None:
    row = dlg.remotes_table.currentRow()
    if row < 0:
        return
    name = dlg.remotes_table.item(row, 0).text()
    if not dlg._confirm_clear("删除远程", f"确定要删除远程「{name}」吗？此操作不可撤销。"):
        return
    git_remote_catalog.remove_remote(name)
    dlg._populate_remotes_table()



def on_set_token(dlg) -> None:
    from PySide6.QtWidgets import QInputDialog
    url = dlg.cred_url_combo.currentText().strip()
    if not url:
        QMessageBox.warning(dlg, "缺少 URL", "请填写或选择远程 URL。")
        return
    existing = credential_store.get_git_token(url) or ""
    token, ok = QInputDialog.getText(
        dlg, "设置令牌", f"HTTPS 令牌 for {url}:",
        text=existing, echo=QLineEdit.EchoMode.Password
    )
    if not ok:
        return
    credential_store.set_git_token(url, token)
    QMessageBox.information(dlg, "已保存", "令牌已存储。")



def on_del_token(dlg) -> None:
    url = dlg.cred_url_combo.currentText().strip()
    if not url:
        return
    if credential_store.delete_git_token(url):
        QMessageBox.information(dlg, "已删除", "令牌已删除。")
    else:
        QMessageBox.information(dlg, "无令牌", "该 URL 没有已存储的令牌。")

