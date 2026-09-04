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
    QCheckBox,
    QComboBox,
    QDialog,
    QDialogButtonBox,
    QFileDialog,
    QFormLayout,
    QHBoxLayout,
    QHeaderView,
    QInputDialog,
    QLabel,
    QLineEdit,
    QMenu,
    QMessageBox,
    QPushButton,
    QTabWidget,
    QTableWidget,
    QTableWidgetItem,
    QTextEdit,
    QTreeWidget,
    QTreeWidgetItem,
    QVBoxLayout,
    QWidget,
)
from src.application.settings import course_clones_dir

from src.backend.course_adapter import CourseAdapter
from src.backend import credential_store
from src.backend import git_remote_catalog
from src.backend.git_library import GitLibrary
from src.dialogs.ai.worker import AiRequestWorker
from src.theme import current_palette


class GitLibraryDialog(QDialog):
    """Connect to a git course repo; open / pull / push / copy-to-assets / host LAN share.

    The dialog operates on a clone directory it manages. When the user clicks
    「打开此仓库」, ``open_requested`` is emitted with the clone path so the
    main window can load it into the editor.
    """

    open_requested = Signal(str)  # clone directory path

    def __init__(
        self,
        adapter: CourseAdapter,
        parent: QWidget | None = None,
        settings: Any = None,
    ) -> None:
        super().__init__(parent)
        self.adapter = adapter
        self._settings = settings
        # Build GitLibrary from settings (git_bin, timeout, token, ssh_key).
        git_bin = "git"
        timeout = 60.0
        token = ""
        ssh_key = ""
        if settings is not None:
            git_bin = settings.git_bin or "git"
            timeout = settings.git_timeout
            ssh_key = credential_store.get_ssh_key_path()
        self.git = GitLibrary(git_bin=git_bin, timeout=timeout, token=token, ssh_key_path=ssh_key)
        self._clone_dir: Path | None = None
        self._git_worker: Any | None = None
        self._local_git_server_thread: Any | None = None

        self.setWindowTitle("资源库（Git / 局域网协作）")
        self.resize(820, 620)
        self._build_ui()
        self._load_defaults()
        self._populate_saved_remotes()

        # Start QTimer for server logs polling
        self.log_timer = QTimer(self)
        self.log_timer.setInterval(1000)
        self.log_timer.timeout.connect(self._poll_server_logs)
        # Don't start unconditionally: the LAN tab may not even be visible.
        # _on_tab_changed / _on_start_share start it when appropriate.
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

        # Saved remotes table (one-click reconnect).
        from PySide6.QtWidgets import QHeaderView
        sync_layout.addWidget(QLabel("已保存的远程仓库（双击连接）:"))
        self.remotes_table = QTableWidget(0, 4)
        self.remotes_table.setHorizontalHeaderLabels(["名称", "URL", "本地目录", "语言"])
        self.remotes_table.horizontalHeader().setSectionResizeMode(1, QHeaderView.ResizeMode.Stretch)
        self.remotes_table.setEditTriggers(QTableWidget.EditTrigger.NoEditTriggers)
        self.remotes_table.setSelectionBehavior(QTableWidget.SelectionBehavior.SelectRows)
        self.remotes_table.setFixedHeight(100)
        self.remotes_table.doubleClicked.connect(self._on_remote_double_click)
        sync_layout.addWidget(self.remotes_table)

        remotes_btn_row = QHBoxLayout()
        remotes_btn_row.setSpacing(6)
        self.save_remote_btn = QPushButton("保存当前为远程")
        self.save_remote_btn.setToolTip("把当前填写的 URL/目录/语言保存为命名远程")
        self.save_remote_btn.clicked.connect(self._on_save_current_remote)
        remotes_btn_row.addWidget(self.save_remote_btn)
        self.del_remote_btn = QPushButton("删除选中")
        self.del_remote_btn.clicked.connect(self._on_del_saved_remote)
        remotes_btn_row.addWidget(self.del_remote_btn)
        remotes_btn_row.addStretch()
        sync_layout.addLayout(remotes_btn_row)

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

        self.sync_res_btn = QPushButton("同步资源池")
        self.sync_res_btn.setToolTip("双向合并本地资源与 Git 仓库的 vocab/expressions/grammar")
        self.sync_res_btn.setEnabled(False)
        self.sync_res_btn.clicked.connect(self._on_sync_resources)
        actions.addWidget(self.sync_res_btn)

        actions.addStretch()
        sync_layout.addLayout(actions)

        # Branch selector
        branch_row = QHBoxLayout()
        branch_row.setSpacing(8)
        branch_row.addWidget(QLabel("分支:"))
        self.branch_combo = QComboBox()
        self.branch_combo.setMinimumWidth(150)
        self.branch_combo.currentIndexChanged.connect(self._on_branch_changed)
        branch_row.addWidget(self.branch_combo)
        self.new_branch_btn = QPushButton("新建")
        self.new_branch_btn.setEnabled(False)
        self.new_branch_btn.clicked.connect(self._on_new_branch)
        branch_row.addWidget(self.new_branch_btn)
        self.switch_branch_btn = QPushButton("切换")
        self.switch_branch_btn.setEnabled(False)
        self.switch_branch_btn.clicked.connect(self._on_switch_branch)
        branch_row.addWidget(self.switch_branch_btn)
        self.del_branch_btn = QPushButton("删除")
        self.del_branch_btn.setEnabled(False)
        self.del_branch_btn.clicked.connect(self._on_del_branch)
        branch_row.addWidget(self.del_branch_btn)
        branch_row.addStretch()
        sync_layout.addLayout(branch_row)

        # Pre-push diff preview button
        self.diff_preview_btn = QPushButton("查看待推送改动 (diff)")
        self.diff_preview_btn.setEnabled(False)
        self.diff_preview_btn.clicked.connect(self._on_diff_preview)
        sync_layout.addWidget(self.diff_preview_btn)

        # Recent Commit History
        sync_layout.addWidget(QLabel("最近提交历史:"))
        self.history_table = QTableWidget(0, 4)
        self.history_table.setHorizontalHeaderLabels(["哈希", "作者", "日期", "提交信息"])
        self.history_table.horizontalHeader().setSectionResizeMode(3, QHeaderView.ResizeMode.Stretch)
        self.history_table.setEditTriggers(QTableWidget.EditTrigger.NoEditTriggers)
        self.history_table.setFixedHeight(100)
        self.history_table.setContextMenuPolicy(Qt.ContextMenuPolicy.CustomContextMenu)
        self.history_table.customContextMenuRequested.connect(self._on_history_context_menu)
        sync_layout.addWidget(self.history_table)

        # File tree browser for the cloned repo.
        sync_layout.addWidget(QLabel("仓库文件（双击在编辑器中打开）:"))
        self.file_tree = QTreeWidget()
        self.file_tree.setHeaderLabels(["文件"])
        self.file_tree.setFixedHeight(100)
        self.file_tree.itemDoubleClicked.connect(self._on_file_tree_double_click)
        sync_layout.addWidget(self.file_tree)

        self.tabs.addTab(self.sync_tab, "远程协作 / 同步")

        # --- Tab 2: LAN Share ---
        self.lan_tab = QWidget()
        lan_layout = QVBoxLayout(self.lan_tab)
        lan_layout.setSpacing(12)
        lan_layout.setContentsMargins(8, 8, 8, 8)

        self.lan_info_label = QLabel("请先在“远程协作”中连接或克隆仓库，然后再开启局域网共享。")
        self.lan_info_label.setWordWrap(True)
        self.lan_info_label.setStyleSheet(f"color: {current_palette()['text_secondary']}; font-size: 12px;")
        lan_layout.addWidget(self.lan_info_label)

        lan_form = QFormLayout()
        lan_form.setSpacing(8)
        self.port_edit = QLineEdit("5000")
        self.port_edit.setPlaceholderText("默认 5000")
        lan_form.addRow("服务端口:", self.port_edit)

        self.lan_bind_combo = QComboBox()
        self.lan_bind_combo.addItem("所有网卡 (0.0.0.0)", "0.0.0.0")
        self.lan_bind_combo.addItem("仅本机 (127.0.0.1)", "127.0.0.1")
        lan_form.addRow("绑定地址:", self.lan_bind_combo)

        self.lan_token_edit = QLineEdit()
        self.lan_token_edit.setEchoMode(QLineEdit.EchoMode.Password)
        self.lan_token_edit.setPlaceholderText("留空则不鉴权（局域网内任意可访问）")
        lan_form.addRow("访问令牌:", self.lan_token_edit)

        self.lan_readonly_check = QCheckBox("只读模式（禁止 push，仅允许 clone/fetch）")
        lan_form.addRow(self.lan_readonly_check)

        self.lan_allow_ips_edit = QLineEdit()
        self.lan_allow_ips_edit.setPlaceholderText("IP 白名单，逗号分隔（留空=允许所有）")
        lan_form.addRow("IP 白名单:", self.lan_allow_ips_edit)
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
        self.server_status_label.setStyleSheet(f"font-weight: bold; color: {current_palette()['text_secondary']};")
        lan_layout.addWidget(self.server_status_label)

        # LAN address list with copy buttons
        self.lan_addresses_widget = QWidget()
        self.lan_addresses_layout = QVBoxLayout(self.lan_addresses_widget)
        self.lan_addresses_layout.setContentsMargins(0, 0, 0, 0)
        self.lan_addresses_layout.setSpacing(6)
        lan_layout.addWidget(self.lan_addresses_widget)

        # Online members
        lan_layout.addWidget(QLabel("在线成员:"))
        self.peers_label = QLabel("（暂无连接）")
        self.peers_label.setStyleSheet(f"color: {current_palette()['text_secondary']}; font-size: 12px;")
        lan_layout.addWidget(self.peers_label)

        # Logging text area
        lan_layout.addWidget(QLabel("最近协作日志 / 诊断信息:"))
        self.log_text = QTextEdit()
        self.log_text.setReadOnly(True)
        self.log_text.setFixedHeight(100)
        self.log_text.setStyleSheet(f"background-color: {current_palette()['bg_input']}; color: {current_palette()['success']}; font-family: monospace;")
        lan_layout.addWidget(self.log_text)

        self.tabs.addTab(self.lan_tab, "局域网协作共享")

        # --- Tab 3: Team Memo Board ---
        self.memo_tab = QWidget()
        memo_layout = QVBoxLayout(self.memo_tab)
        memo_layout.setSpacing(10)
        memo_layout.setContentsMargins(8, 8, 8, 8)

        memo_layout.addWidget(QLabel("团队协作留言板（通过 Git 仓库自动同步，支持回复/编辑/删除）:"))

        # Search bar
        search_row = QHBoxLayout()
        self.memo_search_edit = QLineEdit()
        self.memo_search_edit.setPlaceholderText("搜索留言...")
        self.memo_search_edit.textChanged.connect(self._refresh_memos)
        search_row.addWidget(self.memo_search_edit, 1)
        memo_layout.addLayout(search_row)

        self.memo_text = QTextEdit()
        self.memo_text.setReadOnly(True)
        self.memo_text.setStyleSheet(f"background-color: {current_palette()['bg_input']}; color: {current_palette()['text']}; font-size: 13px;")
        memo_layout.addWidget(self.memo_text)

        # Pagination
        self._memo_page = 0
        self._memo_page_size = 20
        page_row = QHBoxLayout()
        self.memo_prev_btn = QPushButton("上一页")
        self.memo_prev_btn.clicked.connect(self._on_memo_prev_page)
        page_row.addWidget(self.memo_prev_btn)
        self.memo_next_btn = QPushButton("下一页")
        self.memo_next_btn.clicked.connect(self._on_memo_next_page)
        page_row.addWidget(self.memo_next_btn)
        self.memo_page_label = QLabel("第 1 页")
        page_row.addWidget(self.memo_page_label)
        page_row.addStretch()
        memo_layout.addLayout(page_row)

        memo_input_row = QHBoxLayout()
        reply_row = QHBoxLayout()
        reply_row.addWidget(QLabel("回复:"))
        self.memo_reply_combo = QComboBox()
        self.memo_reply_combo.addItem("（新留言）", "")
        reply_row.addWidget(self.memo_reply_combo, 1)
        memo_input_row.addLayout(reply_row, 1)

        self.memo_input = QLineEdit()
        self.memo_input.setPlaceholderText("输入留言，按回车发送...")
        self.memo_input.returnPressed.connect(self._on_send_memo)
        memo_input_row.addWidget(self.memo_input, 2)

        self.send_memo_btn = QPushButton("发送")
        self.send_memo_btn.clicked.connect(self._on_send_memo)
        memo_input_row.addWidget(self.send_memo_btn)
        memo_layout.addLayout(memo_input_row)

        # Edit / delete buttons for own memos
        edit_row = QHBoxLayout()
        self.memo_edit_btn = QPushButton("编辑选中留言")
        self.memo_edit_btn.clicked.connect(self._on_edit_memo)
        edit_row.addWidget(self.memo_edit_btn)
        self.memo_del_btn = QPushButton("删除选中留言")
        self.memo_del_btn.clicked.connect(self._on_del_memo)
        edit_row.addWidget(self.memo_del_btn)
        edit_row.addStretch()
        memo_layout.addLayout(edit_row)

        self.tabs.addTab(self.memo_tab, "团队留言板")
        # Pause the 1s log-poll timer whenever the LAN tab isn't visible so
        # the (potentially large) join + toPlainText comparison doesn't run
        # every second for the whole dialog lifetime while the user is on
        # another tab. Restarted on tab switch if a server is running. (P2)
        self.tabs.currentChanged.connect(self._on_tab_changed)

        layout.addWidget(self.tabs)

        # Status + course summary (shared, at bottom).
        self.status_label = QLabel("尚未连接。")
        self.status_label.setWordWrap(True)
        self.status_label.setStyleSheet(f"color: {current_palette()['text_secondary']}; font-size: 12px;")
        layout.addWidget(self.status_label)

        buttons = QDialogButtonBox(QDialogButtonBox.StandardButton.Close)
        buttons.rejected.connect(self.reject)
        layout.addWidget(buttons)

    def _load_defaults(self) -> None:
        # Auto-fill from settings if available.
        if self._settings is not None:
            clone_root = self._settings.git_clone_root
            if clone_root:
                self.dir_edit.setText(clone_root)
            else:
                default_dir = course_clones_dir()
                self.dir_edit.setText(str(default_dir))
            lang = self._settings.default_lang_code
            if lang:
                self.lang_edit.setText(lang)
            # LAN defaults
            self.port_edit.setText(str(self._settings.lan_default_port))
            bind_idx = self.lan_bind_combo.findData(self._settings.lan_bind_address)
            if bind_idx >= 0:
                self.lan_bind_combo.setCurrentIndex(bind_idx)
            self.lan_token_edit.setText(self._settings.lan_token)
        else:
            default_dir = course_clones_dir()
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
        self.sync_res_btn.setEnabled(connected)
        self.diff_preview_btn.setEnabled(connected)
        self.new_branch_btn.setEnabled(connected)
        self.switch_branch_btn.setEnabled(connected)
        self.del_branch_btn.setEnabled(connected)

        self._refresh_history()
        self._refresh_branches()
        self._refresh_file_tree()
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
            self.server_status_label.setStyleSheet(f"font-weight: bold; color: {current_palette()['success']};")  # green
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
            self.server_status_label.setStyleSheet(f"font-weight: bold; color: {current_palette()['text_secondary']};")  # gray
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

    # --- saved remotes ---------------------------------------------------

    def _populate_saved_remotes(self) -> None:
        remotes = git_remote_catalog.load_remotes()
        self.remotes_table.setRowCount(len(remotes))
        for row, r in enumerate(remotes):
            self.remotes_table.setItem(row, 0, QTableWidgetItem(r.name))
            self.remotes_table.setItem(row, 1, QTableWidgetItem(r.url))
            self.remotes_table.setItem(row, 2, QTableWidgetItem(r.local_dir))
            self.remotes_table.setItem(row, 3, QTableWidgetItem(r.lang))

    def _on_remote_double_click(self, index) -> None:
        row = index.row()
        if row < 0:
            return
        # QTableWidget.item(row, col) returns None if the cell was never
        # populated (corrupt catalog); guard each lookup instead of crashing
        # with AttributeError on .text(). (B3)
        def _cell(col: int) -> str:
            item = self.remotes_table.item(row, col)
            return item.text() if item is not None else ""
        name = _cell(0)
        url = _cell(1)
        local_dir = _cell(2)
        lang = _cell(3)
        if url:
            self.url_edit.setText(url)
        if local_dir:
            self.dir_edit.setText(local_dir)
        if lang:
            self.lang_edit.setText(lang)
        # Auto-connect.
        if url and local_dir:
            self._on_connect()
            git_remote_catalog.mark_synced(name)

    def _on_save_current_remote(self) -> None:
        url = self.url_edit.text().strip()
        local_dir = self.dir_edit.text().strip()
        if not url:
            QMessageBox.warning(self, "缺少 URL", "请先填写远程仓库 URL。")
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
            lang=self.lang_edit.text().strip(),
        )
        git_remote_catalog.add_remote(remote)
        self._populate_saved_remotes()
        QMessageBox.information(self, "已保存", f"远程「{name}」已保存。")

    def _on_del_saved_remote(self) -> None:
        row = self.remotes_table.currentRow()
        if row < 0:
            return
        item = self.remotes_table.item(row, 0)
        if item is None:
            return
        name = item.text()
        git_remote_catalog.remove_remote(name)
        self._populate_saved_remotes()

    # --- branches --------------------------------------------------------

    def _refresh_branches(self) -> None:
        self.branch_combo.clear()
        if self._clone_dir is None or not (self._clone_dir / ".git").is_dir():
            return
        try:
            branches = self.git.list_branches(self._clone_dir)
            current = self.git.current_branch(self._clone_dir)
            for b in branches:
                self.branch_combo.addItem(b)
            idx = self.branch_combo.findText(current)
            if idx >= 0:
                self.branch_combo.setCurrentIndex(idx)
        except Exception as exc:
            # A broken repo (corrupted .git, missing HEAD) used to silently
            # produce an empty branch list with no status update, so the user
            # saw a blank combo and assumed the repo had no branches. Surface
            # the failure instead. (B4)
            self.status_label.setText(f"读取分支失败：{exc}")

    def _on_branch_changed(self, _index: int) -> None:
        pass  # selection only; switch happens on button click.

    def _on_new_branch(self) -> None:
        if self._clone_dir is None:
            return
        name, ok = QInputDialog.getText(self, "新建分支", "分支名:")
        if not ok or not name.strip():
            return
        self._run_git_async(
            "新建分支",
            self.git.create_branch,
            self._clone_dir,
            name.strip(),
            ok_title="已创建",
            ok_message=f"已创建并切换到分支 {name.strip()}。",
            error_title="新建分支失败",
        )

    def _on_switch_branch(self) -> None:
        if self._clone_dir is None:
            return
        name = self.branch_combo.currentText()
        if not name:
            return
        self._run_git_async(
            "切换分支",
            self.git.switch_branch,
            self._clone_dir,
            name,
            ok_title="已切换",
            ok_message=f"已切换到分支 {name}。",
            error_title="切换分支失败",
        )

    def _on_del_branch(self) -> None:
        if self._clone_dir is None:
            return
        name = self.branch_combo.currentText()
        if not name:
            return
        reply = QMessageBox.question(
            self, "删除分支", f"确定要删除分支 {name} 吗？",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.Cancel,
            QMessageBox.StandardButton.Cancel,
        )
        if reply != QMessageBox.StandardButton.Yes:
            return
        self._run_git_async(
            "删除分支",
            self.git.delete_branch,
            self._clone_dir,
            name,
            ok_title="已删除",
            ok_message=f"已删除分支 {name}。",
            error_title="删除分支失败",
        )

    # --- file tree -------------------------------------------------------

    def _refresh_file_tree(self) -> None:
        self.file_tree.clear()
        if self._clone_dir is None or not (self._clone_dir / ".git").is_dir():
            return
        try:
            files = self.git.list_files(self._clone_dir)
            # Build a tree from file paths.
            root_item = QTreeWidgetItem(self.file_tree, [self._clone_dir.name])
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
            self.file_tree.expandItem(root_item)
        except Exception as exc:
            # Same rationale as _refresh_branches: don't mask a broken repo
            # as an empty tree. (B4)
            self.status_label.setText(f"读取文件树失败：{exc}")

    def _on_file_tree_double_click(self, item) -> None:
        file_path = item.data(0, Qt.ItemDataRole.UserRole)
        if file_path and self._clone_dir is not None:
            full_path = self._clone_dir / file_path
            self.open_requested.emit(str(full_path))
            self.accept()

    # --- diff preview & history context menu -----------------------------

    def _on_diff_preview(self) -> None:
        if self._clone_dir is None:
            return
        try:
            diff_text = self.git.diff_working_vs_head(self._clone_dir, stat=True)
            if not diff_text.strip():
                QMessageBox.information(self, "无改动", "工作树与 HEAD 无差异。")
                return
            dlg = QDialog(self)
            dlg.setWindowTitle("待推送改动（工作树 vs HEAD）")
            dlg.resize(700, 500)
            layout = QVBoxLayout(dlg)
            edit = QTextEdit()
            edit.setReadOnly(True)
            edit.setPlainText(diff_text)
            edit.setStyleSheet("font-family: monospace;")
            layout.addWidget(edit)
            dlg.exec()
        except RuntimeError as exc:
            QMessageBox.critical(self, "Diff 失败", str(exc))

    def _on_history_context_menu(self, position) -> None:
        row = self.history_table.rowAt(position.y())
        if row < 0:
            return
        item = self.history_table.item(row, 0)
        if item is None:
            return
        ref = item.text()
        menu = QMenu(self)
        menu.addAction(f"Reset --hard 到 {ref}", lambda: self._on_reset_to(ref, "hard"))
        menu.addAction(f"Reset --soft 到 {ref}", lambda: self._on_reset_to(ref, "soft"))
        menu.addAction(f"Revert {ref}", lambda: self._on_revert(ref))
        menu.exec(self.history_table.viewport().mapToGlobal(position))

    def _on_reset_to(self, ref: str, mode: str) -> None:
        if self._clone_dir is None:
            return
        reply = QMessageBox.question(
            self, f"Reset {mode}",
            f"确定要 reset --{mode} 到 {ref} 吗？此操作可能丢失改动。",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.Cancel,
            QMessageBox.StandardButton.Cancel,
        )
        if reply != QMessageBox.StandardButton.Yes:
            return
        self._run_git_async(
            f"reset --{mode}",
            self.git.reset_to,
            self._clone_dir,
            ref,
            mode,
            ok_title="已 reset",
            ok_message=f"已 reset --{mode} 到 {ref}。",
            error_title="reset 失败",
        )

    def _on_revert(self, ref: str) -> None:
        if self._clone_dir is None:
            return
        self._run_git_async(
            f"revert {ref}",
            self.git.revert,
            self._clone_dir,
            ref,
            ok_title="已 revert",
            ok_message=f"已 revert {ref}（创建新提交）。",
            error_title="revert 失败",
        )

    # --- resource pool sync ----------------------------------------------

    def _on_sync_resources(self) -> None:
        if self._clone_dir is None:
            return
        lang = self.lang_edit.text().strip()
        if not lang:
            QMessageBox.warning(self, "缺少语言代码", "请填写语言代码。")
            return
        reply = QMessageBox.question(
            self, "同步资源池",
            f"将本地课程资源与 Git 仓库 {self._clone_dir} 双向合并？",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.Cancel,
            QMessageBox.StandardButton.Cancel,
        )
        if reply != QMessageBox.StandardButton.Yes:
            return
        try:
            from src.backend.course_adapter import CourseAdapter
            result = self.adapter.sync_resources_with_git(self._clone_dir, lang)
            QMessageBox.information(
                self, "同步完成",
                f"资源同步完成：\n{result}",
            )
        except Exception as exc:
            QMessageBox.critical(self, "同步失败", str(exc))

    # --- memo pagination / edit / delete ---------------------------------

    def _on_memo_prev_page(self) -> None:
        if self._memo_page > 0:
            self._memo_page -= 1
            self._refresh_memos()

    def _on_memo_next_page(self) -> None:
        self._memo_page += 1
        self._refresh_memos()

    def _on_edit_memo(self) -> None:
        if self._clone_dir is None:
            return
        memo_id, ok = QInputDialog.getText(self, "编辑留言", "留言 ID:")
        if not ok or not memo_id.strip():
            return
        new_text, ok2 = QInputDialog.getText(self, "编辑留言", "新内容:")
        if not ok2 or not new_text.strip():
            return
        self._edit_or_delete_memo(memo_id.strip(), action="edit", new_text=new_text.strip())

    def _on_del_memo(self) -> None:
        if self._clone_dir is None:
            return
        memo_id, ok = QInputDialog.getText(self, "删除留言", "留言 ID:")
        if not ok or not memo_id.strip():
            return
        reply = QMessageBox.question(
            self, "删除留言", f"确定要删除留言 {memo_id.strip()} 吗？",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.Cancel,
            QMessageBox.StandardButton.Cancel,
        )
        if reply != QMessageBox.StandardButton.Yes:
            return
        self._edit_or_delete_memo(memo_id.strip(), action="delete")

    def _edit_or_delete_memo(self, memo_id: str, action: str, new_text: str = "") -> None:
        if self._clone_dir is None:
            return
        memo_file = self._clone_dir / ".collaboration_memo.json"
        import json
        import getpass
        user = getpass.getuser()
        try:
            data = json.loads(memo_file.read_text(encoding="utf-8")) if memo_file.is_file() else {"messages": []}
        except Exception:
            data = {"messages": []}
        messages = data.get("messages", [])
        found = False
        for m in messages:
            if m.get("id") == memo_id:
                if m.get("user") != user:
                    QMessageBox.warning(self, "无权限", "只能编辑/删除自己的留言。")
                    return
                if action == "edit":
                    m["text"] = new_text
                    m["edited_at"] = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                elif action == "delete":
                    messages.remove(m)
                found = True
                break
        if not found:
            QMessageBox.warning(self, "未找到", f"未找到 ID 为 {memo_id} 的留言。")
            return
        data["messages"] = messages
        # Atomic write: tmp + os.replace so a crash mid-write cannot
        # corrupt the collaborator's memo file (B19).
        import os
        tmp = memo_file.with_suffix(memo_file.suffix + ".tmp")
        tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
        os.replace(tmp, memo_file)
        self._refresh_memos()
        # Push.
        self._run_git_async(
            "推送留言",
            self.git.commit_and_push_file,
            self._clone_dir,
            ".collaboration_memo.json",
            f"留言{action}: {memo_id}",
            ok_title="已同步",
            ok_message="留言变更已推送。",
            error_title="留言同步失败",
        )

    # --- peers (online members) ------------------------------------------

    def _refresh_peers(self) -> None:
        thread = self.git_server_thread
        if thread is None or thread.server is None:
            self.peers_label.setText("（暂无连接）")
            return
        peers = getattr(thread.server, "connected_peers", {})
        now = datetime.now().timestamp()
        # Expire peers older than 60s.
        active = [ip for ip, ts in peers.items() if now - ts < 60.0]
        if active:
            self.peers_label.setText(f"在线: {', '.join(active)}")
        else:
            self.peers_label.setText("（暂无连接）")

    def closeEvent(self, event) -> None:  # noqa: N802
        # Stop the 1s log-poll timer so it doesn't fire while the dialog is
        # being torn down (QTimer is parented to self but deleteLater may lag).
        self.log_timer.stop()
        super().closeEvent(event)

    def _on_tab_changed(self, index: int) -> None:
        """Pause log polling unless the LAN tab is visible + a server runs. (P2)"""
        lan_index = self.tabs.indexOf(self.lan_tab)
        server_running = (
            self.git_server_thread is not None
            and getattr(self.git_server_thread, "server", None) is not None
        )
        if index == lan_index and server_running:
            if not self.log_timer.isActive():
                self.log_timer.start()
            # Immediate refresh so switching to the tab shows current logs.
            self._poll_server_logs()
        else:
            if self.log_timer.isActive():
                self.log_timer.stop()

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
            self._refresh_peers()
        else:
            if self._last_log_len != 0:
                self._last_log_len = 0
                if self.log_text.toPlainText():
                    self.log_text.clear()
            self._refresh_peers()

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
        except Exception as exc:
            self.history_table.setRowCount(0)
            # Surface the failure instead of leaving an empty table that
            # looks like a repo with no commits. (B4)
            self.status_label.setText(f"读取历史失败：{exc}")

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
            self.memo_reply_combo.clear()
            self.memo_reply_combo.addItem("（新留言）", "")
            self.memo_page_label.setText("第 1 页")
            return

        try:
            import json
            data = json.loads(memo_file.read_text(encoding="utf-8"))
            messages = data.get("messages", [])

            # Search filter.
            search = self.memo_search_edit.text().strip().lower()
            if search:
                messages = [
                    m for m in messages
                    if search in m.get("text", "").lower()
                    or search in m.get("user", "").lower()
                ]

            # Build threaded display: top-level messages + their replies.
            by_parent: dict[str, list] = {}
            for m in messages:
                parent = m.get("parent_id", "")
                by_parent.setdefault(parent, []).append(m)

            # Top-level messages (parent_id == "").
            top_level = sorted(by_parent.get("", []), key=lambda m: m.get("time", ""))

            # Pagination.
            total = len(top_level)
            start = self._memo_page * self._memo_page_size
            end = start + self._memo_page_size
            page_items = top_level[start:end]
            total_pages = max(1, (total + self._memo_page_size - 1) // self._memo_page_size)
            self.memo_page_label.setText(f"第 {self._memo_page + 1} / {total_pages} 页（共 {total} 条）")
            self.memo_prev_btn.setEnabled(self._memo_page > 0)
            self.memo_next_btn.setEnabled(end < total)

            # Reply combo.
            self.memo_reply_combo.clear()
            self.memo_reply_combo.addItem("（新留言）", "")
            for m in top_level:
                label = f"{m.get('id', '?')}: {m.get('text', '')[:30]}"
                self.memo_reply_combo.addItem(label, m.get("id", ""))

            # Render threaded.
            lines = []
            def _render(msg: dict, indent: str) -> None:
                lines.append(f"{indent}【{msg.get('time', '')}】 {msg.get('user', '?')} (ID: {msg.get('id', '?')[:8]}):")
                lines.append(f"{indent}  {msg.get('text', '')}")
                if msg.get("edited_at"):
                    lines.append(f"{indent}  (编辑于 {msg['edited_at']})")
                for reply in sorted(by_parent.get(msg.get("id", ""), []), key=lambda m: m.get("time", "")):
                    _render(reply, indent + "    ")
            for m in page_items:
                _render(m, "")
            if lines:
                self.memo_text.setPlainText("\n".join(lines))
                self.memo_text.verticalScrollBar().setValue(
                    self.memo_text.verticalScrollBar().maximum()
                )
            else:
                self.memo_text.setPlainText("（无匹配留言）")
        except Exception as exc:
            self.memo_text.setPlainText(f"读取留言板失败：{exc}")

    def _on_send_memo(self) -> None:
        text = self.memo_input.text().strip()
        if not text or self._clone_dir is None:
            return

        import getpass
        import uuid
        user = getpass.getuser()
        try:
            ips = self._get_local_ips()
            ip = ips[0] if ips else "未知"
        except Exception:
            ip = "未知"

        parent_id = self.memo_reply_combo.currentData() or ""
        memo_id = uuid.uuid4().hex[:12]

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
            "id": memo_id,
            "parent_id": parent_id,
            "time": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            "user": user,
            "ip": ip,
            "text": text,
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
        host = self.lan_bind_combo.currentData() or "0.0.0.0"
        token = self.lan_token_edit.text().strip()
        read_only = self.lan_readonly_check.isChecked()
        allow_ips_raw = self.lan_allow_ips_edit.text().strip()
        allow_ips = [ip.strip() for ip in allow_ips_raw.split(",") if ip.strip()] if allow_ips_raw else []

        from src.backend.git_library import GitServerThread
        # Configure Git to allow push to currently checked out branch.
        self.git.enable_lan_write(self._clone_dir)

        # Try to bind; auto-increment port on conflict (up to 10 attempts).
        thread = None
        for attempt in range(10):
            try:
                thread = GitServerThread(
                    self._clone_dir,
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
                self, "启动失败",
                f"无法绑定端口 {port}-{port + 9}，可能均已被占用。",
            )
            self.git_server_thread = None
            self._refresh_state()
            return

        try:
            thread.start()
            self.git_server_thread = thread
            from PySide6.QtWidgets import QApplication
            app = QApplication.instance()
            if app is not None:
                app.aboutToQuit.connect(self._stop_share_on_quit)
            # Start the log-poll timer now that a server is running (only
            # polls meaningfully while the LAN tab is visible — see
            # _on_tab_changed). (P2)
            if not self.log_timer.isActive():
                self.log_timer.start()
            QMessageBox.information(
                self,
                "共享成功",
                f"已启动局域网协作服务！\n绑定：{host}:{thread.port}\n"
                f"鉴权：{'是' if token else '否'}\n只读：{'是' if read_only else '否'}\n"
                f"IP 白名单：{', '.join(allow_ips) if allow_ips else '允许所有'}\n"
                f"窗口关闭后共享仍在后台运行。",
            )
        except Exception as exc:
            # ``GitServerThread.__init__`` already bound the listening socket
            # synchronously, so a failure in ``thread.start()`` would leak
            # the bound port until process exit (B15): ``self.git_server_thread``
            # is None so ``_on_stop_share`` would never close it. Close the
            # server explicitly here.
            try:
                thread.server.server_close()
            except Exception:  # noqa: BLE001 — best-effort cleanup
                pass
            QMessageBox.critical(self, "启动失败", f"发生未知错误：\n{exc}")
            self.git_server_thread = None

        self._refresh_state()

    def _on_stop_share(self) -> None:
        thread = self.git_server_thread
        if thread:
            thread.stop()
            thread.join(timeout=1.0)
            self.git_server_thread = None
        # No server running -> no point polling. (P2)
        self.log_timer.stop()
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

    def _run_git_async(
        self,
        label: str,
        fn,
        *args,
        on_ok=None,
        ok_title: str = "",
        ok_message: str = "",
        error_title: str = "",
        on_error=None,
    ) -> None:
        """Run a synchronous git call in a background worker.

        Cancels any still-running previous git worker before starting the new
        one: without this, firing a second op while the first is in flight
        would leave the old QThread running (its result is dropped by the
        ``worker is not self._git_worker`` guard in ``_on_git_result``) and
        could race on the shared git clone's index. (B5)
        """
        # Cancel and disconnect the previous worker so its late signals can't
        # land in our slots after we've moved on.
        prev = getattr(self, "_git_worker", None)
        if prev is not None:
            try:
                if prev.isRunning():
                    prev.cancel()
                for sig_name in ("result_ready", "error_occurred", "completed", "finished"):
                    try:
                        getattr(prev, sig_name).disconnect()
                    except (TypeError, RuntimeError, AttributeError):
                        pass
            except Exception:  # noqa: BLE001 — defensive; never block new op
                pass
        self._set_git_busy(True, label)
        worker = AiRequestWorker(fn, *args)
        worker.result_ready.connect(
            lambda result: self._on_git_result(
                worker, result, on_ok, ok_title, ok_message
            )
        )
        worker.error_occurred.connect(
            lambda msg: self._on_git_error(worker, msg, error_title, on_error)
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

    def _on_git_error(self, worker: Any, message: str, error_title: str, on_error=None) -> None:
        if worker is not self._git_worker:
            return
        self._git_worker = None
        self._set_git_busy(False, "")
        self._refresh_state()
        if on_error is not None:
            on_error(message)
        elif error_title:
            QMessageBox.critical(self, error_title, message)

    def _set_git_busy(self, busy: bool, label: str = "") -> None:
        self.connect_btn.setEnabled(not busy)
        self.open_btn.setEnabled(not busy)
        self.fetch_btn.setEnabled(not busy)
        self.pull_btn.setEnabled(not busy)
        self.push_btn.setEnabled(not busy)
        self.copy_btn.setEnabled(not busy)
        self.sync_res_btn.setEnabled(not busy)
        self.diff_preview_btn.setEnabled(not busy)
        self.new_branch_btn.setEnabled(not busy)
        self.switch_branch_btn.setEnabled(not busy)
        self.del_branch_btn.setEnabled(not busy)
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
            on_ok=lambda _r: None,
            ok_title="已是最新",
            ok_message="已拉取远程最新内容。",
            error_title="拉取失败",
            on_error=self._on_pull_conflict,
        )

    def _on_pull_conflict(self, message: str) -> None:
        """Offer conflict resolution options when pull --ff-only fails."""
        if self._clone_dir is None:
            return
        reply = QMessageBox.question(
            self,
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
            self._run_git_async(
                "rebase",
                self.git.pull_rebase,
                self._clone_dir,
                ok_title="Rebase 成功",
                ok_message="已 rebase 到远程最新。",
                error_title="Rebase 失败",
            )
        elif reply == QMessageBox.StandardButton.No:
            def _after_stash(_r: Any) -> None:
                self._run_git_async(
                    "pull",
                    self.git.pull,
                    self._clone_dir,
                    on_ok=lambda _r2: self._run_git_async(
                        "stash pop",
                        self.git.stash_pop,
                        self._clone_dir,
                        ok_title="已完成",
                        ok_message="已暂存+拉取+恢复本地改动。",
                        error_title="恢复改动失败",
                    ),
                    error_title="拉取失败",
                )
            self._run_git_async(
                "stash",
                self.git.stash,
                self._clone_dir,
                on_ok=_after_stash,
                error_title="暂存失败",
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
        # Use configurable repo_root from settings if set.
        repo_root = None
        if self._settings is not None and self._settings.assets_repo_root:
            repo_root = Path(self._settings.assets_repo_root)
        try:
            if repo_root:
                target = GitLibrary.save_to_assets(self._clone_dir, lang, repo_root=repo_root)
            else:
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