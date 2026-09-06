"""LAN share domain: server hosting, address list, peers, log polling (F)."""
from __future__ import annotations

import logging
from datetime import datetime

from PySide6.QtCore import Qt
from PySide6.QtWidgets import (
    QCheckBox,
    QComboBox,
    QFormLayout,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QMessageBox,
    QPushButton,
    QTextEdit,
    QVBoxLayout,
    QWidget,
)

from src.theme import current_palette

logger = logging.getLogger(__name__)


def build_lan_tab(dlg) -> QWidget:
    """Tab 2: LAN Share & Collaboration."""
    dlg.lan_tab = QWidget()
    lan_layout = QVBoxLayout(dlg.lan_tab)
    lan_layout.setSpacing(12)
    lan_layout.setContentsMargins(8, 8, 8, 8)

    dlg.lan_info_label = QLabel("请先在“远程协作”中连接或克隆仓库，然后再开启局域网共享。")
    dlg.lan_info_label.setWordWrap(True)
    dlg.lan_info_label.setStyleSheet(f"color: {current_palette()['text_secondary']}; font-size: 12px;")
    lan_layout.addWidget(dlg.lan_info_label)

    lan_form = QFormLayout()
    lan_form.setSpacing(8)
    dlg.port_edit = QLineEdit("5000")
    dlg.port_edit.setPlaceholderText("默认 5000")
    lan_form.addRow("服务端口:", dlg.port_edit)

    dlg.lan_bind_combo = QComboBox()
    dlg.lan_bind_combo.addItem("所有网卡 (0.0.0.0)", "0.0.0.0")
    dlg.lan_bind_combo.addItem("仅本机 (127.0.0.1)", "127.0.0.1")
    lan_form.addRow("绑定地址:", dlg.lan_bind_combo)

    dlg.lan_token_edit = QLineEdit()
    dlg.lan_token_edit.setEchoMode(QLineEdit.EchoMode.Password)
    dlg.lan_token_edit.setPlaceholderText("留空则不鉴权（局域网内任意可访问）")
    lan_form.addRow("访问令牌:", dlg.lan_token_edit)

    dlg.lan_readonly_check = QCheckBox("只读模式（禁止 push，仅允许 clone/fetch）")
    lan_form.addRow(dlg.lan_readonly_check)

    dlg.lan_allow_ips_edit = QLineEdit()
    dlg.lan_allow_ips_edit.setPlaceholderText("IP 白名单，逗号分隔（留空=允许所有）")
    lan_form.addRow("IP 白名单:", dlg.lan_allow_ips_edit)
    lan_layout.addLayout(lan_form)

    lan_btn_row = QHBoxLayout()
    lan_btn_row.setSpacing(8)
    dlg.start_share_btn = QPushButton("开启共享")
    dlg.start_share_btn.clicked.connect(dlg._on_start_share)
    lan_btn_row.addWidget(dlg.start_share_btn)

    dlg.stop_share_btn = QPushButton("停止共享")
    dlg.stop_share_btn.clicked.connect(dlg._on_stop_share)
    dlg.stop_share_btn.setEnabled(False)
    lan_btn_row.addWidget(dlg.stop_share_btn)

    lan_btn_row.addStretch()
    lan_layout.addLayout(lan_btn_row)

    dlg.server_status_label = QLabel("共享状态: 未开启")
    dlg.server_status_label.setStyleSheet(f"font-weight: bold; color: {current_palette()['text_secondary']};")
    lan_layout.addWidget(dlg.server_status_label)

    # LAN address list with copy buttons
    dlg.lan_addresses_widget = QWidget()
    dlg.lan_addresses_layout = QVBoxLayout(dlg.lan_addresses_widget)
    dlg.lan_addresses_layout.setContentsMargins(0, 0, 0, 0)
    dlg.lan_addresses_layout.setSpacing(6)
    lan_layout.addWidget(dlg.lan_addresses_widget)

    # Online members
    lan_layout.addWidget(QLabel("在线成员:"))
    dlg.peers_label = QLabel("（暂无连接）")
    dlg.peers_label.setStyleSheet(f"color: {current_palette()['text_secondary']}; font-size: 12px;")
    lan_layout.addWidget(dlg.peers_label)

    # Logging text area
    lan_layout.addWidget(QLabel("最近协作日志 / 诊断信息:"))
    dlg.log_text = QTextEdit()
    dlg.log_text.setReadOnly(True)
    dlg.log_text.setFixedHeight(100)
    dlg.log_text.setStyleSheet(f"background-color: {current_palette()['bg_input']}; color: {current_palette()['success']}; font-family: monospace;")
    lan_layout.addWidget(dlg.log_text)

    return dlg.lan_tab


def refresh_server_ui(dlg) -> None:
    # Clear layout — also delete the per-IP QHBoxLayouts (whose items have
    # no widget()) and their child QLabels/QPushButtons, otherwise each
    # refresh leaks the address-row widgets.
    while dlg.lan_addresses_layout.count():
        item = dlg.lan_addresses_layout.takeAt(0)
        w = item.widget()
        if w is not None:
            w.deleteLater()
            continue
        sub = item.layout()
        if sub is not None:
            while sub.count():
                cw = sub.takeAt(0).widget()
                if cw is not None:
                    cw.deleteLater()
            sub.deleteLater()

    thread = dlg.git_server_thread
    if thread is not None and thread.server is not None:
        dlg.server_status_label.setText("共享状态: 正在共享中...")
        dlg.server_status_label.setStyleSheet(f"font-weight: bold; color: {current_palette()['success']};")  # green
        dlg.start_share_btn.setEnabled(False)
        dlg.stop_share_btn.setEnabled(True)
        dlg.port_edit.setEnabled(False)

        # Rebuild addresses with copy buttons
        ips = get_local_ips()
        port = thread.port

        lbl_title = QLabel("局域网协作地址 (其他设备可使用任一地址进行连接/克隆/推送):")
        lbl_title.setStyleSheet("font-weight: bold;")
        dlg.lan_addresses_layout.addWidget(lbl_title)

        for ip in ips:
            url = f"http://{ip}:{port}/"
            row_layout = QHBoxLayout()
            row_layout.setContentsMargins(0, 0, 0, 0)

            url_lbl = QLabel(f"• {url}")
            url_lbl.setTextInteractionFlags(Qt.TextInteractionFlag.TextSelectableByMouse)
            row_layout.addWidget(url_lbl, 1)

            copy_btn = QPushButton("复制")
            copy_btn.setFixedWidth(50)
            copy_btn.setStyleSheet("padding: 2px; font-size: 11px;")
            copy_btn.setProperty("copy_url", url)
            copy_btn.clicked.connect(dlg._on_copy_url_clicked)
            row_layout.addWidget(copy_btn)

            dlg.lan_addresses_widget.layout().addLayout(row_layout)
    else:
        dlg.server_status_label.setText("共享状态: 未开启")
        dlg.server_status_label.setStyleSheet(f"font-weight: bold; color: {current_palette()['text_secondary']};")  # gray
        connected = dlg._clone_dir is not None and (dlg._clone_dir / ".git").is_dir()
        dlg.start_share_btn.setEnabled(connected)
        dlg.stop_share_btn.setEnabled(False)
        dlg.port_edit.setEnabled(True)


def on_copy_url_clicked(dlg) -> None:
    sender = dlg.sender()
    if not sender:
        return
    url = sender.property("copy_url")
    if isinstance(url, str):
        copy_to_clipboard(dlg, url)


def copy_to_clipboard(dlg, text: str) -> None:
    from PySide6.QtGui import QGuiApplication
    clipboard = QGuiApplication.clipboard()
    clipboard.setText(text)

    parent = dlg.parent()
    if parent is not None and hasattr(parent, "statusBar"):
        parent.statusBar().showMessage(f"已复制地址: {text}", 3000)
    else:
        QMessageBox.information(dlg, "已复制", f"已复制到剪贴板：\n{text}")


def refresh_peers(dlg) -> None:
    thread = dlg.git_server_thread
    if thread is None or thread.server is None:
        dlg.peers_label.setText("（暂无连接）")
        return
    peers = getattr(thread.server, "connected_peers", {})
    now = datetime.now().timestamp()
    # Expire peers older than 60s.
    active = [ip for ip, ts in peers.items() if now - ts < 60.0]
    if active:
        dlg.peers_label.setText(f"在线: {', '.join(active)}")
    else:
        dlg.peers_label.setText("（暂无连接）")


def on_tab_changed(dlg, index: int) -> None:
    """Pause log polling unless the LAN tab is visible + a server runs. (P2)"""
    lan_index = dlg.tabs.indexOf(dlg.lan_tab)
    server_running = (
        dlg.git_server_thread is not None
        and getattr(dlg.git_server_thread, "server", None) is not None
    )
    if index == lan_index and server_running:
        if not dlg.log_timer.isActive():
            dlg.log_timer.start()
        # Immediate refresh so switching to the tab shows current logs.
        poll_server_logs(dlg)
    else:
        if dlg.log_timer.isActive():
            dlg.log_timer.stop()


def poll_server_logs(dlg) -> None:
    thread = dlg.git_server_thread
    if thread is not None and thread.server is not None:
        try:
            logs = list(thread.server.log_queue)
            if not logs:
                if dlg._last_log_len != 0:
                    dlg._last_log_len = 0
                    if dlg.log_text.toPlainText():
                        dlg.log_text.clear()
                return
            if len(logs) == dlg._last_log_len:
                return
            dlg._last_log_len = len(logs)
            current_text = "\n".join(logs)
            if dlg.log_text.toPlainText() != current_text:
                dlg.log_text.setPlainText(current_text)
                dlg.log_text.verticalScrollBar().setValue(
                    dlg.log_text.verticalScrollBar().maximum()
                )
        except Exception:
            logger.debug("dialogs/git_library/lan_share.py:poll_server_logs best-effort step failed", exc_info=True)
        refresh_peers(dlg)
    else:
        if dlg._last_log_len != 0:
            dlg._last_log_len = 0
            if dlg.log_text.toPlainText():
                dlg.log_text.clear()
        refresh_peers(dlg)


def get_local_ips() -> list[str]:
    import socket
    ips = []
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ips.append(s.getsockname()[0])
        s.close()
    except Exception:
        logger.debug("dialogs/git_library/lan_share.py:get_local_ips best-effort step failed", exc_info=True)
    try:
        hostname = socket.gethostname()
        for ip in socket.gethostbyname_ex(hostname)[2]:
            if ip not in ips and not ip.startswith("127."):
                ips.append(ip)
    except Exception:
        logger.debug("dialogs/git_library/lan_share.py:get_local_ips best-effort step failed", exc_info=True)
    if not ips:
        ips.append("127.0.0.1")
    return ips


def on_start_share(dlg) -> None:
    if not dlg._clone_dir:
        QMessageBox.warning(dlg, "未连接仓库", "请先连接或克隆一个本地目录。")
        return

    port_str = dlg.port_edit.text().strip()
    if not port_str.isdigit():
        QMessageBox.warning(dlg, "端口错误", "端口必须为数字。")
        return
    port = int(port_str)
    host = dlg.lan_bind_combo.currentData() or "0.0.0.0"
    token = dlg.lan_token_edit.text().strip()
    read_only = dlg.lan_readonly_check.isChecked()
    allow_ips_raw = dlg.lan_allow_ips_edit.text().strip()
    allow_ips = [ip.strip() for ip in allow_ips_raw.split(",") if ip.strip()] if allow_ips_raw else []

    from src.backend.git_library import GitServerThread
    # Configure Git to allow push to currently checked out branch.
    dlg.git.enable_lan_write(dlg._clone_dir)

    # Try to bind; auto-increment port on conflict (up to 10 attempts).
    thread = None
    for attempt in range(10):
        try:
            thread = GitServerThread(
                dlg._clone_dir,
                host=host,
                port=port + attempt,
                auth_token=token,
                read_only=read_only,
                allow_ips=allow_ips,
            )
            break
        except OSError:
            if attempt == 9:
                thread = None
            continue

    if thread is None:
        QMessageBox.critical(
            dlg, "启动失败",
            f"无法绑定端口 {port}-{port + 9}，可能均已被占用。",
        )
        dlg.git_server_thread = None
        dlg._refresh_state()
        return

    try:
        thread.start()
        dlg.git_server_thread = thread
        from PySide6.QtWidgets import QApplication
        app = QApplication.instance()
        if app is not None:
            app.aboutToQuit.connect(dlg._stop_share_on_quit)
        # Start the log-poll timer now that a server is running (only
        # polls meaningfully while the LAN tab is visible — see
        # _on_tab_changed). (P2)
        if not dlg.log_timer.isActive():
            dlg.log_timer.start()
        QMessageBox.information(
            dlg,
            "共享成功",
            f"已启动局域网协作服务！\n绑定：{host}:{thread.port}\n"
            f"鉴权：{'是' if token else '否'}\n只读：{'是' if read_only else '否'}\n"
            f"IP 白名单：{', '.join(allow_ips) if allow_ips else '允许所有'}\n"
            f"窗口关闭后共享仍在后台运行。",
        )
    except Exception as exc:
        # ``GitServerThread.__init__`` already bound the listening socket
        # synchronously, so a failure in ``thread.start()`` would leak
        # the bound port until process exit (B15): ``dlg.git_server_thread``
        # is None so ``_on_stop_share`` would never close it. Close the
        # server explicitly here.
        try:
            thread.server.server_close()
        except Exception:  # noqa: BLE001 — best-effort cleanup
            logger.debug("dialogs/git_library/lan_share.py:on_start_share best-effort step failed", exc_info=True)
        QMessageBox.critical(dlg, "启动失败", f"发生未知错误：\n{exc}")
        dlg.git_server_thread = None

    dlg._refresh_state()


def on_stop_share(dlg) -> None:
    thread = dlg.git_server_thread
    if thread:
        thread.stop()
        thread.join(timeout=1.0)
        dlg.git_server_thread = None
    # No server running -> no point polling. (P2)
    dlg.log_timer.stop()
    dlg._refresh_state()


def stop_share_on_quit(dlg) -> None:
    """Release the LAN server thread + port when the application quits.

    Connected to ``QApplication.aboutToQuit`` from ``on_start_share`` so
    the port does not stay bound if the user closes the editor without
    revisiting the dialog to click 停止共享.
    """
    thread = dlg.git_server_thread
    if thread is not None and getattr(thread, "server", None) is not None:
        try:
            thread.stop()
        except Exception:
            logger.debug("dialogs/git_library/lan_share.py:stop_share_on_quit best-effort step failed", exc_info=True)
        dlg.git_server_thread = None
