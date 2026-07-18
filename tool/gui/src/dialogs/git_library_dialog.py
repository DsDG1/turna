"""Dialog for connecting to an external Git course library.

Lets the author clone a remote course repository, open it in the editor,
push local edits back, and copy the course into the app's bundled
``assets/courses/<lang>/`` directory. All network/overwrite operations are
explicit and confirmed.
"""
from __future__ import annotations

from pathlib import Path

from PySide6.QtCore import Signal
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
)

from src.backend.course_adapter import CourseAdapter
from src.backend.git_library import GitLibrary


class GitLibraryDialog(QDialog):
    """Connect to a git course repo; open / pull / push / copy-to-assets.

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
        self.setWindowTitle("资源库（Git）")
        self.resize(620, 420)
        self._build_ui()
        self._load_defaults()
        self._refresh_state()

    def _build_ui(self) -> None:
        layout = QVBoxLayout(self)
        layout.setSpacing(12)
        layout.setContentsMargins(16, 16, 16, 16)

        form = QFormLayout()
        form.setSpacing(8)

        self.url_edit = QLineEdit()
        self.url_edit.setPlaceholderText("https://github.com/you/my-turkish-course.git")
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

        layout.addLayout(form)

        connect_row = QHBoxLayout()
        self.connect_btn = QPushButton("连接 / 克隆")
        self.connect_btn.setToolTip("克隆远程仓库到本地目录（已存在则拉取最新）")
        self.connect_btn.clicked.connect(self._on_connect)
        connect_row.addWidget(self.connect_btn)
        connect_row.addStretch()
        layout.addLayout(connect_row)

        # Status + course summary.
        self.status_label = QLabel("尚未连接。")
        self.status_label.setWordWrap(True)
        self.status_label.setStyleSheet("color: #9CA3AF; font-size: 12px;")
        layout.addWidget(self.status_label)

        # Action buttons (enabled after a successful connect).
        actions = QHBoxLayout()
        actions.setSpacing(8)
        self.open_btn = QPushButton("在编辑器中打开")
        self.open_btn.setEnabled(False)
        self.open_btn.clicked.connect(self._on_open)
        actions.addWidget(self.open_btn)

        self.pull_btn = QPushButton("拉取最新")
        self.pull_btn.setEnabled(False)
        self.pull_btn.clicked.connect(self._on_pull)
        actions.addWidget(self.pull_btn)

        self.push_btn = QPushButton("保存回仓库（push）")
        self.push_btn.setEnabled(False)
        self.push_btn.clicked.connect(self._on_push)
        actions.addWidget(self.push_btn)

        self.copy_btn = QPushButton("复制到 assets")
        self.copy_btn.setEnabled(False)
        self.copy_btn.clicked.connect(self._on_copy_to_assets)
        actions.addWidget(self.copy_btn)
        actions.addStretch()
        layout.addLayout(actions)

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
        self.pull_btn.setEnabled(connected)
        self.push_btn.setEnabled(connected)
        self.copy_btn.setEnabled(connected and bool(self.lang_edit.text().strip()))
        if not connected:
            self.status_label.setText("尚未连接。")
            return
        try:
            st = self.git.status(self._clone_dir)  # type: ignore[arg-type]
        except RuntimeError as exc:
            self.status_label.setText(f"状态读取失败：{exc}")
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

    def _on_connect(self) -> None:
        url = self.url_edit.text().strip()
        local = self.dir_edit.text().strip()
        if not url or not local:
            QMessageBox.warning(self, "信息不完整", "请填写远程仓库 URL 和本地目录。")
            return
        local_path = Path(local)
        try:
            self._set_clone_dir_pending(local_path)
            self.git.clone(url, local_path)
        except RuntimeError as exc:
            QMessageBox.critical(self, "连接失败", str(exc))
            self._clone_dir = None
            self._refresh_state()
            return
        self._clone_dir = local_path
        self._refresh_state()
        QMessageBox.information(self, "连接成功", f"已就绪：{local_path}")

    def _set_clone_dir_pending(self, path: Path) -> None:
        # Placeholder hook for future pre-clone validation.
        self._pending_dir = path

    def _on_open(self) -> None:
        if self._clone_dir is None:
            return
        self.open_requested.emit(str(self._clone_dir))
        self.accept()

    def _on_pull(self) -> None:
        if self._clone_dir is None:
            return
        try:
            self.git.pull(self._clone_dir)
        except RuntimeError as exc:
            QMessageBox.critical(self, "拉取失败", str(exc))
            return
        self._refresh_state()
        QMessageBox.information(self, "已是最新", "已拉取远程最新内容。")

    def _on_push(self) -> None:
        if self._clone_dir is None:
            return
        # Encourage saving first.
        reply = QMessageBox.question(
            self,
            "保存回仓库",
            "将本地改动提交并推送到远程仓库？\n请确认编辑器已「保存」到该克隆目录。",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.Cancel,
            QMessageBox.StandardButton.Yes,
        )
        if reply != QMessageBox.StandardButton.Yes:
            return
        msg, ok = self._commit_message()
        if not ok:
            return
        try:
            self.git.commit_and_push(self._clone_dir, msg)
        except RuntimeError as exc:
            QMessageBox.critical(self, "推送失败", str(exc))
            return
        self._refresh_state()
        QMessageBox.information(self, "已推送", "本地改动已提交并推送到远程。")

    def _commit_message(self) -> tuple[str, bool]:
        text, ok = QInputDialog.getText(
            self, "提交信息", "提交信息（commit message）：", text="update course content"
        )
        return (text.strip(), bool(ok))

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