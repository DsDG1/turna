"""Dialog for connecting to an external Git course library.

Lets the author clone a remote course repository, open it in the editor,
push local edits back, and copy the course into the app's bundled
assets/courses/<lang>/ directory. Includes LAN collaboration sharing.
"""
from __future__ import annotations

from datetime import datetime
from pathlib import Path
from typing import Any

from PySide6.QtCore import Signal, Qt, QTimer
from PySide6.QtWidgets import (
    QDialog,
    QDialogButtonBox,
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
    QTabWidget,
    QTableWidget,
    QTableWidgetItem,
    QHeaderView,
    QTextEdit,
)

from src.backend.course_adapter import CourseAdapter
from src.backend.git_library import GitLibrary
from src.dialogs.ai.worker import AiRequestWorker


class GitLibraryDialog(QDialog):
    """Connect to a git course repo; open / pull / push / copy-to-assets / host LAN share.

    The dialog operates on a clone directory it manages. When the user clicks
    「打开此仓库」, ``open_requested`` is emitted with the clone path so the
    main window can load it into the editor.
    """

    open_requested = Signal(str)  # clone directory path

    def __init__(self, adapter: CourseAdapter, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.adapter = adapter
        self.git = GitLibrary()
        self._clone_dir: Path | None = None
        self._git_worker: Any | None = None
        self._local_git_server_thread: Any | None = None
        
        self.setWindowTitle("资源库（Git / 局域网协作）")
        self.resize(720, 540)
        self._build_ui()
        self._load_defaults()

        # Start QTimer for server logs polling
        self.log_timer = QTimer(self)
        self.log_timer.setInterval(1000)
        self.log_timer.timeout.connect(self._poll_server_logs)
        self.log_timer.start()
        # Length-based short-circuit so the common "no new logs" tick skips
        # the join + toPlainText() comparison entirely.
        self._last_log_len = -1

        self._refresh_state()

    @property
    def git_server_thread(self) -> Any:
        parent = self.parent()
        if parent is not None:
            return getattr(parent, "_git_server_thread", None)
        return self._local_git_server_thread

    @git_server_thread.setter
    def git_server_thread(self, val: Any) -> None:
        parent = self.parent()
        if parent is not None:
            setattr(parent, "_git_server_thread", val)
        else:
            self._local_git_server_thread = val

    def _build_ui(self) -> None:
        layout = QVBoxLayout(self)
        layout.setSpacing(12)
        layout.setContentsMargins(16, 16, 16, 16)

        self.tabs = QTabWidget()

        # --- Tab 1: Remote Collaboration ---
        self.sync_tab = QWidget()
        sync_layout = QVBoxLayout(self.sync_tab)
        sync_layout.setSpacing(10)
        sync_layout.setContentsMargins(8, 8, 8, 8)

        form = QFormLayout()
        form.setSpacing(8)
        self.url_edit = QLineEdit()
        self.url_edit.setPlaceholderText("https://github.com/you/my-turkish-course.git 或局域网协作地址")
        form.addRow("远程仓库 URL:", self.url_edit)

        dir_row = QHBoxLayout()
        dir_row.setSpacing(8)
        self.dir_edit = QLineEdit()
        self.dir_edit.setPlaceholderText("本地克隆目录")
        dir_row.addWidget(self.dir_edit, 1)
        browse = QPushButton("浏览...")
        browse.clicked.connect(self._on_browse)
        dir_row.addWidget(browse)
        form.addRow("本地目录:", dir_row)

        self.lang_edit = QLineEdit()
        self.lang_edit.setPlaceholderText("例如：tr / en / sw（用于复制到 assets/courses/<lang>）")
        form.addRow("语言代码:", self.lang_edit)
        sync_layout.addLayout(form)

        connect_row = QHBoxLayout()
        self.connect_btn = QPushButton("连接 / 克隆")
        self.connect_btn.setToolTip("克隆远程仓库到本地目录（已存在则拉取最新）")
        self.connect_btn.clicked.connect(self._on_connect)
        connect_row.addWidget(self.connect_btn)
        connect_row.addStretch()
        sync_layout.addLayout(connect_row)

        # Action buttons
        actions = QHBoxLayout()
        actions.setSpacing(8)

        self.open_btn = QPushButton("在编辑器中打开")
        self.open_btn.setEnabled(False)
        self.open_btn.clicked.connect(self._on_open)
        actions.addWidget(self.open_btn)

        self.fetch_btn = QPushButton("检查更新")
        self.fetch_btn.setEnabled(False)
        self.fetch_btn.clicked.connect(self._on_fetch)
        actions.addWidget(self.fetch_btn)

        self.pull_btn = QPushButton("拉取最新")
        self.pull_btn.setEnabled(False)
        self.pull_btn.clicked.connect(self._on_pull)
        actions.addWidget(self.pull_btn)

        self.push_btn = QPushButton("保存并推送 (push)")
        self.push_btn.setEnabled(False)
        self.push_btn.clicked.connect(self._on_push)
        actions.addWidget(self.push_btn)

        self.copy_btn = QPushButton("复制到 assets")
        self.copy_btn.setEnabled(False)
        self.copy_btn.clicked.connect(self._on_copy_to_assets)
        actions.addWidget(self.copy_btn)

        actions.addStretch()
        sync_layout.addLayout(actions)

        # Recent Commit History
        sync_layout.addWidget(QLabel("最近提交历史:"))
        self.history_table = QTableWidget(0, 4)
        self.history_table.setHorizontalHeaderLabels(["哈希", "作者", "日期", "提交信息"])
        self.history_table.horizontalHeader().setSectionResizeMode(3, QHeaderView.ResizeMode.Stretch)
        self.history_table.setEditTriggers(QTableWidget.EditTrigger.NoEditTriggers)
        self.history_table.setFixedHeight(120)
        sync_layout.addWidget(self.history_table)

        self.tabs.addTab(self.sync_tab, "远程协作 / 同步")

        # --- Tab 2: LAN Share ---
        self.lan_tab = QWidget()
        lan_layout = QVBoxLayout(self.lan_tab)
        lan_layout.setSpacing(12)
        lan_layout.setContentsMargins(8, 8, 8, 8)

        self.lan_info_label = QLabel("请先在“远程协作”中连接或克隆仓库，然后再开启局域网共享。")
        self.lan_info_label.setWordWrap(True)
        self.lan_info_label.setStyleSheet("color: #6B7280; font-size: 12px;")
        lan_layout.addWidget(self.lan_info_label)

        lan_form = QFormLayout()
        lan_form.setSpacing(8)
        self.port_edit = QLineEdit("5000")
        self.port_edit.setPlaceholderText("默认 5000")
        lan_form.addRow("服务端口:", self.port_edit)
        lan_layout.addLayout(lan_form)

        lan_btn_row = QHBoxLayout()
        lan_btn_row.setSpacing(8)
        self.start_share_btn = QPushButton("开启共享")
        self.start_share_btn.clicked.connect(self._on_start_share)
        lan_btn_row.addWidget(self.start_share_btn)

        self.stop_share_btn = QPushButton("停止共享")
        self.stop_share_btn.clicked.connect(self._on_stop_share)
        self.stop_share_btn.setEnabled(False)
        lan_btn_row.addWidget(self.stop_share_btn)

        lan_btn_row.addStretch()
        lan_layout.addLayout(lan_btn_row)

        self.server_status_label = QLabel("共享状态: 未开启")
        self.server_status_label.setStyleSheet("font-weight: bold; color: #6B7280;")
        lan_layout.addWidget(self.server_status_label)

        # LAN address list with copy buttons
        self.lan_addresses_widget = QWidget()
        self.lan_addresses_layout = QVBoxLayout(self.lan_addresses_widget)
        self.lan_addresses_layout.setContentsMargins(0, 0, 0, 0)
        self.lan_addresses_layout.setSpacing(6)
        lan_layout.addWidget(self.lan_addresses_widget)

        # Logging text area
        lan_layout.addWidget(QLabel("最近协作日志 / 诊断信息:"))
        self.log_text = QTextEdit()
        self.log_text.setReadOnly(True)
        self.log_text.setFixedHeight(120)
        self.log_text.setStyleSheet("background-color: #1F2937; color: #10B981; font-family: monospace;")
        lan_layout.addWidget(self.log_text)

        self.tabs.addTab(self.lan_tab, "局域网协作共享")

        # --- Tab 3: Team Memo Board ---
        self.memo_tab = QWidget()
        memo_layout = QVBoxLayout(self.memo_tab)
        memo_layout.setSpacing(10)
        memo_layout.setContentsMargins(8, 8, 8, 8)

        memo_layout.addWidget(QLabel("团队协作留言板 (通过 Git 仓库自动同步):"))
        self.memo_text = QTextEdit()
        self.memo_text.setReadOnly(True)
        self.memo_text.setStyleSheet("background-color: #F9FAFB; color: #374151; font-size: 13px;")
        memo_layout.addWidget(self.memo_text)

        memo_input_row = QHBoxLayout()
        self.memo_input = QLineEdit()
        self.memo_input.setPlaceholderText("在此处输入协作留言（如：第5节音频已校对），按回车或点击发送...")
        self.memo_input.returnPressed.connect(self._on_send_memo)
        memo_input_row.addWidget(self.memo_input, 1)

        self.send_memo_btn = QPushButton("发送留言")
        self.send_memo_btn.clicked.connect(self._on_send_memo)
        memo_input_row.addWidget(self.send_memo_btn)
        memo_layout.addLayout(memo_input_row)

        self.tabs.addTab(self.memo_tab, "团队留言板")

        layout.addWidget(self.tabs)

        # Status + course summary (shared, at bottom).
        self.status_label = QLabel("尚未连接。")
        self.status_label.setWordWrap(True)
        self.status_label.setStyleSheet("color: #9CA3AF; font-size: 12px;")
        layout.addWidget(self.status_label)

        buttons = QDialogButtonBox(QDialogButtonBox.StandardButton.Close)
        buttons.rejected.connect(self.reject)
        layout.addWidget(buttons)

    def _load_defaults(self) -> None:
        default_dir = Path.home() / ".varnamala" / "course-clones"
        self.dir_edit.setText(str(default_dir))

    def _on_browse(self) -> None:
        chosen = QFileDialog.getExistingDirectory(self, "选择本地克隆目录", self.dir_edit.text() or "")
        if chosen:
            self.dir_edit.setText(chosen)

    def _refresh_state(self) -> None:
        connected = self._clone_dir is not None and (self._clone_dir / ".git").is_dir()
        self.open_btn.setEnabled(connected)
        self.fetch_btn.setEnabled(connected)
        self.pull_btn.setEnabled(connected)
        self.push_btn.setEnabled(connected)
        self.copy_btn.setEnabled(connected and bool(self.lang_edit.text().strip()))

        self._refresh_history()
        self._refresh_memos()

        if not connected:
            self.status_label.setText("尚未连接。")
            self.lan_info_label.setText("请先在“远程协作 / 同步”中连接或克隆仓库，然后再开启局域网共享。")
            self._refresh_server_ui()
            return

        self.lan_info_label.setText(f"共享的本地目录: {self._clone_dir}")

        try:
            st = self.git.status(self._clone_dir)  # type: ignore[arg-type]
        except RuntimeError as exc:
            self.status_label.setText(f"状态读取失败：{exc}")
            self._refresh_server_ui()
            return

        chips = []
        if st.dirty:
            chips.append("有未提交改动")
        if st.ahead:
            chips.append(f"领先 {st.ahead} 个提交")
        if st.behind:
            chips.append(f"落后 {st.behind} 个提交")
        if not chips:
            chips.append("与远程一致")
        branch = st.branch or "(分离 HEAD)"
        summary = f"分支 {branch} · {' · '.join(chips)}"

        # Course summary from index.json.
        try:
            import json

            idx_path = self._clone_dir / "index.json"  # type: ignore[union-attr]
            if idx_path.is_file():
                data = json.loads(idx_path.read_text(encoding="utf-8"))
                sections = data.get("sections") or []
                summary += (
                    f"\n课程：{data.get('displayName', '?')}（语言 {data.get('language', '?')}，"
                    f"{len(sections)} 个 section）"
                )
        except Exception:
            pass
        self.status_label.setText(summary)
        self._refresh_server_ui()

    def _refresh_server_ui(self) -> None:
        # Clear layout — also delete the per-IP QHBoxLayouts (whose items have
        # no widget()) and their child QLabels/QPushButtons, otherwise each
        # refresh leaks the address-row widgets.
        while self.lan_addresses_layout.count():
            item = self.lan_addresses_layout.takeAt(0)
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

        thread = self.git_server_thread
        if thread is not None and thread.server is not None:
            self.server_status_label.setText("共享状态: 正在共享中...")
            self.server_status_label.setStyleSheet("font-weight: bold; color: #10B981;")  # green
            self.start_share_btn.setEnabled(False)
            self.stop_share_btn.setEnabled(True)
            self.port_edit.setEnabled(False)

            # Rebuild addresses with copy buttons
            ips = self._get_local_ips()
            port = thread.port
            
            lbl_title = QLabel("局域网协作地址 (其他设备可使用任一地址进行连接/克隆/推送):")
            lbl_title.setStyleSheet("font-weight: bold;")
            self.lan_addresses_layout.addWidget(lbl_title)

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
                copy_btn.clicked.connect(lambda checked=False, u=url: self._copy_to_clipboard(u))
                row_layout.addWidget(copy_btn)
                
                self.lan_addresses_widget.layout().addLayout(row_layout)
        else:
            self.server_status_label.setText("共享状态: 未开启")
            self.server_status_label.setStyleSheet("font-weight: bold; color: #6B7280;")  # gray
            connected = self._clone_dir is not None and (self._clone_dir / ".git").is_dir()
            self.start_share_btn.setEnabled(connected)
            self.stop_share_btn.setEnabled(False)
            self.port_edit.setEnabled(True)

    def _copy_to_clipboard(self, text: str) -> None:
        from PySide6.QtGui import QGuiApplication
        clipboard = QGuiApplication.clipboard()
        clipboard.setText(text)
        
        parent = self.parent()
        if parent is not None and hasattr(parent, "statusBar"):
            parent.statusBar().showMessage(f"已复制地址: {text}", 3000)
        else:
            QMessageBox.information(self, "已复制", f"已复制到剪贴板：\n{text}")

    def closeEvent(self, event) -> None:  # noqa: N802
        # Stop the 1s log-poll timer so it doesn't fire while the dialog is
        # being torn down (QTimer is parented to self but deleteLater may lag).
        self.log_timer.stop()
        super().closeEvent(event)

    def _poll_server_logs(self) -> None:
        thread = self.git_server_thread
        if thread is not None and thread.server is not None:
            try:
                logs = list(thread.server.log_queue)
                if not logs:
                    if self._last_log_len != 0:
                        self._last_log_len = 0
                        if self.log_text.toPlainText():
                            self.log_text.clear()
                    return
                if len(logs) == self._last_log_len:
                    return
                self._last_log_len = len(logs)
                current_text = "\n".join(logs)
                if self.log_text.toPlainText() != current_text:
                    self.log_text.setPlainText(current_text)
                    self.log_text.verticalScrollBar().setValue(
                        self.log_text.verticalScrollBar().maximum()
                    )
            except Exception:
                pass
        else:
            if self._last_log_len != 0:
                self._last_log_len = 0
                if self.log_text.toPlainText():
                    self.log_text.clear()

    def _refresh_history(self) -> None:
        if self._clone_dir is None or not (self._clone_dir / ".git").is_dir():
            self.history_table.setRowCount(0)
            return
        try:
            commits = self.git.get_history(self._clone_dir, count=5)
            self.history_table.setRowCount(len(commits))
            for row, commit in enumerate(commits):
                self.history_table.setItem(row, 0, QTableWidgetItem(commit["hash"]))
                self.history_table.setItem(row, 1, QTableWidgetItem(commit["author"]))
                self.history_table.setItem(row, 2, QTableWidgetItem(commit["date"]))
                self.history_table.setItem(row, 3, QTableWidgetItem(commit["message"]))
        except Exception:
            self.history_table.setRowCount(0)

    def _refresh_memos(self) -> None:
        if self._clone_dir is None:
            self.memo_text.setPlainText("请先在“远程协作”中连接或克隆仓库。")
            self.memo_input.setEnabled(False)
            self.send_memo_btn.setEnabled(False)
            return

        self.memo_input.setEnabled(True)
        self.send_memo_btn.setEnabled(True)

        memo_file = self._clone_dir / ".collaboration_memo.json"
        if not memo_file.is_file():
            self.memo_text.setPlainText("留言板目前为空。发布第一条留言来开始协作吧！")
            return

        try:
            import json
            data = json.loads(memo_file.read_text(encoding="utf-8"))
            lines = []
            for entry in data.get("messages", []):
                lines.append(f"【{entry.get('time', '')}】 {entry.get('user', '未知')} ({entry.get('ip', '未知')}):")
                lines.append(f"  {entry.get('text', '')}\n")
            if lines:
                self.memo_text.setPlainText("\n".join(lines))
                self.memo_text.verticalScrollBar().setValue(
                    self.memo_text.verticalScrollBar().maximum()
                )
            else:
                self.memo_text.setPlainText("留言板目前为空。")
        except Exception as exc:
            self.memo_text.setPlainText(f"读取留言板失败：{exc}")

    def _on_send_memo(self) -> None:
        text = self.memo_input.text().strip()
        if not text or self._clone_dir is None:
            return

        import getpass
        user = getpass.getuser()
        try:
            ips = self._get_local_ips()
            ip = ips[0] if ips else "未知"
        except Exception:
            ip = "未知"

        memo_file = self._clone_dir / ".collaboration_memo.json"

        import json
        messages = []
        if memo_file.is_file():
            try:
                data = json.loads(memo_file.read_text(encoding="utf-8"))
                messages = data.get("messages", [])
            except Exception:
                pass

        messages.append({
            "time": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            "user": user,
            "ip": ip,
            "text": text
        })

        try:
            memo_file.write_text(json.dumps({"messages": messages}, ensure_ascii=False, indent=2), encoding="utf-8")
            self.memo_input.clear()
            self._refresh_memos()

            # Pull-rebase first so a teammate's earlier push does not cause a
            # non-fast-forward rejection, then commit + push the memo file.
            def _push_memo(_result: Any) -> None:
                self._run_git_async(
                    "推送留言",
                    self.git.commit_and_push_file,
                    self._clone_dir,
                    ".collaboration_memo.json",
                    f"留言: {text[:20]}",
                    ok_title="已同步留言",
                    ok_message="留言已推送到远程仓库。",
                    error_title="留言同步失败",
                )

            self._run_git_async(
                "拉取最新留言",
                self.git.pull_rebase,
                self._clone_dir,
                on_ok=_push_memo,
                error_title="留言同步失败",
            )
        except Exception as exc:
            QMessageBox.critical(self, "发送失败", f"无法写入并推送留言：{exc}")

    def _get_local_ips(self) -> list[str]:
        import socket
        ips = []
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(("8.8.8.8", 80))
            ips.append(s.getsockname()[0])
            s.close()
        except Exception:
            pass
        try:
            hostname = socket.gethostname()
            for ip in socket.gethostbyname_ex(hostname)[2]:
                if ip not in ips and not ip.startswith("127."):
                    ips.append(ip)
        except Exception:
            pass
        if not ips:
            ips.append("127.0.0.1")
        return ips

    def _on_start_share(self) -> None:
        if not self._clone_dir:
            QMessageBox.warning(self, "未连接仓库", "请先连接或克隆一个本地目录。")
            return

        port_str = self.port_edit.text().strip()
        if not port_str.isdigit():
            QMessageBox.warning(self, "端口错误", "端口必须为数字。")
            return
        port = int(port_str)

        try:
            from src.backend.git_library import GitServerThread
            # Configure Git to allow push to currently checked out branch
            self.git.enable_lan_write(self._clone_dir)

            # Start background thread
            thread = GitServerThread(self._clone_dir, host="0.0.0.0", port=port)
            thread.start()
            self.git_server_thread = thread
            # Ensure the server thread + bound port are released when the app
            # quits even if the user never reopens the dialog to stop it.
            from PySide6.QtWidgets import QApplication

            app = QApplication.instance()
            if app is not None:
                app.aboutToQuit.connect(self._stop_share_on_quit)
            QMessageBox.information(
                self,
                "共享成功",
                f"已启动局域网协作服务！\n端口：{port}\n您可以进入“局域网协作共享”页签查看协作地址。\n窗口关闭后共享仍在后台运行。"
            )
        except OSError as exc:
            QMessageBox.critical(self, "启动失败", f"无法绑定端口 {port}，可能已被占用：\n{exc}")
            self.git_server_thread = None
        except Exception as exc:
            QMessageBox.critical(self, "启动失败", f"发生未知错误：\n{exc}")
            self.git_server_thread = None

        self._refresh_state()

    def _on_stop_share(self) -> None:
        thread = self.git_server_thread
        if thread:
            thread.stop()
            thread.join(timeout=1.0)
            self.git_server_thread = None
        self._refresh_state()

    def _stop_share_on_quit(self) -> None:
        """Release the LAN server thread + port when the application quits.

        Connected to ``QApplication.aboutToQuit`` from ``_on_start_share`` so
        the port does not stay bound if the user closes the editor without
        revisiting the dialog to click 停止共享.
        """
        thread = self.git_server_thread
        if thread is not None and getattr(thread, "server", None) is not None:
            try:
                thread.stop()
            except Exception:
                pass
            self.git_server_thread = None

    def _on_connect(self) -> None:
        url = self.url_edit.text().strip()
        local = self.dir_edit.text().strip()
        if not url or not local:
            QMessageBox.warning(self, "信息不完整", "请填写远程仓库 URL 和本地目录。")
            return
        local_path = Path(local)
        self._set_clone_dir_pending(local_path)
        self._run_git_async(
            "连接",
            self.git.clone,
            url,
            local_path,
            on_ok=lambda _result: setattr(self, "_clone_dir", local_path),
            ok_title="连接成功",
            ok_message=f"已就绪：{local_path}",
            error_title="连接失败",
        )

    def _set_clone_dir_pending(self, path: Path) -> None:
        self._pending_dir = path

    def _run_git_async(
        self,
        label: str,
        fn,
        *args,
        on_ok=None,
        ok_title: str = "",
        ok_message: str = "",
        error_title: str = "",
    ) -> None:
        """Run a synchronous git call in a background worker."""
        self._set_git_busy(True, label)
        worker = AiRequestWorker(fn, *args)
        worker.result_ready.connect(
            lambda result: self._on_git_result(
                worker, result, on_ok, ok_title, ok_message
            )
        )
        worker.error_occurred.connect(
            lambda msg: self._on_git_error(worker, msg, error_title)
        )
        self._git_worker = worker
        worker.start()

    def _on_git_result(
        self,
        worker: Any,
        result: Any,
        on_ok,
        ok_title: str,
        ok_message: str,
    ) -> None:
        if worker is not self._git_worker:
            return
        self._git_worker = None
        self._set_git_busy(False, "")
        if on_ok is not None:
            on_ok(result)
        self._refresh_state()
        if ok_title:
            QMessageBox.information(self, ok_title, ok_message)

    def _on_git_error(self, worker: Any, message: str, error_title: str) -> None:
        if worker is not self._git_worker:
            return
        self._git_worker = None
        self._set_git_busy(False, "")
        self._refresh_state()
        if error_title:
            QMessageBox.critical(self, error_title, message)

    def _set_git_busy(self, busy: bool, label: str = "") -> None:
        self.connect_btn.setEnabled(not busy)
        self.open_btn.setEnabled(not busy)
        self.fetch_btn.setEnabled(not busy)
        self.pull_btn.setEnabled(not busy)
        self.push_btn.setEnabled(not busy)
        self.copy_btn.setEnabled(not busy)
        self.start_share_btn.setEnabled(not busy and self.git_server_thread is None)
        self.stop_share_btn.setEnabled(not busy and self.git_server_thread is not None)
        self.memo_input.setEnabled(not busy)
        self.send_memo_btn.setEnabled(not busy)
        if busy:
            self.status_label.setText(f"{label}中…")

    def _on_open(self) -> None:
        if self._clone_dir is None:
            return
        self.open_requested.emit(str(self._clone_dir))
        self.accept()

    def _on_fetch(self) -> None:
        if self._clone_dir is None:
            return
        self._run_git_async(
            "获取最新状态",
            self.git.fetch,
            self._clone_dir,
            ok_title="获取完成",
            ok_message="已获取远程最新状态。",
            error_title="获取状态失败",
        )

    def _on_pull(self) -> None:
        if self._clone_dir is None:
            return
        self._run_git_async(
            "拉取",
            self.git.pull,
            self._clone_dir,
            ok_title="已是最新",
            ok_message="已拉取远程最新内容。",
            error_title="拉取失败",
        )

    def _on_push(self) -> None:
        if self._clone_dir is None:
            return

        # Auto-save current editor state if it's active
        parent = self.parent()
        if parent is not None and getattr(parent, "course_dir", None) == self._clone_dir:
            if hasattr(parent, "_on_save"):
                parent._on_save()

        # Confirm push
        reply = QMessageBox.question(
            self,
            "保存并推送",
            "确定要推送本地改动吗？\n当前编辑的改动已被自动保存。",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.Cancel,
            QMessageBox.StandardButton.Yes,
        )
        if reply != QMessageBox.StandardButton.Yes:
            return
        msg, ok = self._commit_message()
        if not ok:
            return
        self._run_git_async(
            "推送",
            self.git.commit_and_push,
            self._clone_dir,
            msg,
            ok_title="已推送",
            ok_message="本地改动已提交并推送到远程。",
            error_title="推送失败",
        )

    def _commit_message(self) -> tuple[str, bool]:
        default_msg = f"自动保存: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"
        text, ok = QInputDialog.getText(
            self, "提交信息", "提交信息（commit message）：", text=default_msg
        )
        return (text.strip() or default_msg, bool(ok))

    def _on_copy_to_assets(self) -> None:
        if self._clone_dir is None:
            return
        lang = self.lang_edit.text().strip()
        if not lang:
            QMessageBox.warning(self, "缺少语言代码", "请填写语言代码以确定 assets 目标目录。")
            return
        try:
            target = GitLibrary.save_to_assets(self._clone_dir, lang)
        except FileExistsError as exc:
            reply = QMessageBox.question(
                self,
                "目标已存在",
                f"{exc}\n\n是否覆盖？",
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.Cancel,
                QMessageBox.StandardButton.Cancel,
            )
            if reply != QMessageBox.StandardButton.Yes:
                return
            try:
                target = GitLibrary.save_to_assets(
                    self._clone_dir, lang, overwrite=True
                )
            except RuntimeError as exc2:
                QMessageBox.critical(self, "复制失败", str(exc2))
                return
        except RuntimeError as exc:
            QMessageBox.critical(self, "复制失败", str(exc))
            return
        QMessageBox.information(
            self,
            "已复制到 assets",
            f"课程已写入：\n{target}\n\n打包时会随 app 一起分发。",
        )

    def clone_dir(self) -> Path | None:
        return self._clone_dir