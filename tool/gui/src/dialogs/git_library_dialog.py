"""Dialog for connecting to an external Git course library.

Thin shell: assembly + delegation. Each feature domain lives in
``src/dialogs/git_library/`` (sync / remotes / branches / repo_browser /
lan_share / memo), and async git plumbing in ``git_worker_hub.GitWorkerHub``.
All widget attributes and method names are preserved on this class so tests
and signal wiring keep working unchanged.

Lets the author clone a remote course repository, open it in the editor,
push local edits back, and copy the course into the app's bundled
assets/courses/<lang>/ directory. Includes LAN collaboration sharing.
"""
from __future__ import annotations

import logging
from pathlib import Path
from typing import Any

from PySide6.QtCore import Signal, QTimer
from PySide6.QtWidgets import (
    QDialog,
    QDialogButtonBox,
    QLabel,
    QTabWidget,
    QVBoxLayout,
    QWidget,
)

from src.application.settings import course_clones_dir

from src.backend.course_adapter import CourseAdapter
from src.application import credential_store
from src.backend.git_library import GitLibrary
from src.dialogs.git_library import (
    branches,
    lan_share,
    memo,
    repo_browser,
    remotes,
    sync,
)
from src.dialogs.git_library.git_worker_hub import GitWorkerHub
from src.theme import current_palette

logger = logging.getLogger(__name__)


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
        self.git_worker_hub = GitWorkerHub(self)
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

    # --- assembly ---------------------------------------------------------

    def _build_ui(self) -> None:
        layout = QVBoxLayout(self)
        layout.setSpacing(12)
        layout.setContentsMargins(16, 16, 16, 16)

        self.tabs = QTabWidget()
        self.tabs.addTab(self._build_sync_tab(), "远程协作 / 同步")
        self.tabs.addTab(self._build_lan_tab(), "局域网协作共享")
        self.tabs.addTab(self._build_memo_tab(), "团队留言板")
        # Pause the 1s log-poll timer whenever the LAN tab isn't visible so
        # the (potentially large) join + toPlainText comparison doesn't run
        # every second for the whole dialog lifetime while the user is on
        # another tab. Restarted on tab switch if a server is running. (P2)
        self.tabs.currentChanged.connect(self._on_tab_changed)

        layout.addWidget(self.tabs)
        self._build_footer(layout)

    def _build_sync_tab(self) -> QWidget:
        """Tab 1: Remote Collaboration & Sync (assembly in git_library.sync)."""
        return sync.build_sync_tab(self)

    def _build_lan_tab(self) -> QWidget:
        """Tab 2: LAN Share & Collaboration (assembly in git_library.lan_share)."""
        return lan_share.build_lan_tab(self)

    def _build_memo_tab(self) -> QWidget:
        """Tab 3: Team Memo Board (assembly in git_library.memo)."""
        return memo.build_memo_tab(self)

    def _build_footer(self, layout: QVBoxLayout) -> None:
        """Build status label and dialog button box at the bottom."""
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

    # --- central state refresh (orchestrator) ------------------------------

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
            logger.debug("dialogs/git_library_dialog.py:_refresh_state best-effort step failed", exc_info=True)
        self.status_label.setText(summary)
        self._refresh_server_ui()

    # --- domain delegations ------------------------------------------------

    def _on_browse(self) -> None:
        sync.on_browse(self)

    def _on_connect(self) -> None:
        sync.on_connect(self)

    def _on_open(self) -> None:
        sync.on_open(self)

    def _on_fetch(self) -> None:
        sync.on_fetch(self)

    def _on_pull(self) -> None:
        sync.on_pull(self)

    def _on_pull_conflict(self, message: str) -> None:
        sync.on_pull_conflict(self, message)

    def _on_push(self) -> None:
        sync.on_push(self)

    def _commit_message(self) -> tuple[str, bool]:
        return sync.commit_message(self)

    def _on_copy_to_assets(self) -> None:
        sync.on_copy_to_assets(self)

    def _on_sync_resources(self) -> None:
        sync.on_sync_resources(self)

    def _populate_saved_remotes(self) -> None:
        remotes.populate_saved_remotes(self)

    def _on_remote_double_click(self, index) -> None:
        remotes.on_remote_double_click(self, index)

    def _on_save_current_remote(self) -> None:
        remotes.on_save_current_remote(self)

    def _on_del_saved_remote(self) -> None:
        remotes.on_del_saved_remote(self)

    def _refresh_branches(self) -> None:
        branches.refresh_branches(self)

    def _on_branch_changed(self, _index: int) -> None:
        branches.on_branch_changed(self, _index)

    def _on_new_branch(self) -> None:
        branches.on_new_branch(self)

    def _on_switch_branch(self) -> None:
        branches.on_switch_branch(self)

    def _on_del_branch(self) -> None:
        branches.on_del_branch(self)

    def _refresh_history(self) -> None:
        repo_browser.refresh_history(self)

    def _refresh_file_tree(self) -> None:
        repo_browser.refresh_file_tree(self)

    def _on_file_tree_double_click(self, item) -> None:
        repo_browser.on_file_tree_double_click(self, item)

    def _on_diff_preview(self) -> None:
        repo_browser.on_diff_preview(self)

    def _on_history_context_menu(self, position) -> None:
        repo_browser.on_history_context_menu(self, position)

    def _on_reset_to(self, ref: str, mode: str) -> None:
        repo_browser.on_reset_to(self, ref, mode)

    def _on_revert(self, ref: str) -> None:
        repo_browser.on_revert(self, ref)

    def _refresh_server_ui(self) -> None:
        lan_share.refresh_server_ui(self)

    def _on_copy_url_clicked(self) -> None:
        lan_share.on_copy_url_clicked(self)

    def _copy_to_clipboard(self, text: str) -> None:
        lan_share.copy_to_clipboard(self, text)

    def _refresh_peers(self) -> None:
        lan_share.refresh_peers(self)

    def _on_tab_changed(self, index: int) -> None:
        lan_share.on_tab_changed(self, index)

    def _poll_server_logs(self) -> None:
        lan_share.poll_server_logs(self)

    def _get_local_ips(self) -> list[str]:
        return lan_share.get_local_ips()

    def _on_start_share(self) -> None:
        lan_share.on_start_share(self)

    def _on_stop_share(self) -> None:
        lan_share.on_stop_share(self)

    def _stop_share_on_quit(self) -> None:
        lan_share.stop_share_on_quit(self)

    def _refresh_memos(self) -> None:
        memo.refresh_memos(self)

    def _on_send_memo(self) -> None:
        memo.on_send_memo(self)

    def _on_memo_prev_page(self) -> None:
        memo.on_memo_prev_page(self)

    def _on_memo_next_page(self) -> None:
        memo.on_memo_next_page(self)

    def _on_edit_memo(self) -> None:
        memo.on_edit_memo(self)

    def _on_del_memo(self) -> None:
        memo.on_del_memo(self)

    def _edit_or_delete_memo(self, memo_id: str, action: str, new_text: str = "") -> None:
        memo.edit_or_delete_memo(self, memo_id, action, new_text)

    # --- async git plumbing -------------------------------------------------

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
        self.git_worker_hub.run_async(
            label,
            fn,
            *args,
            on_ok=on_ok,
            ok_title=ok_title,
            ok_message=ok_message,
            error_title=error_title,
            on_error=on_error,
        )

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

    # --- lifecycle -----------------------------------------------------------

    def closeEvent(self, event) -> None:  # noqa: N802
        # Stop the 1s log-poll timer so it doesn't fire while the dialog is
        # being torn down (QTimer is parented to self but deleteLater may lag).
        self.log_timer.stop()
        super().closeEvent(event)

    def clone_dir(self) -> Path | None:
        return self._clone_dir
