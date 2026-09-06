"""Textbook project library: create, resume, or delete import projects."""
from __future__ import annotations

import logging
logger = logging.getLogger(__name__)


from pathlib import Path
from typing import Any

from PySide6.QtCore import Qt, Signal
from PySide6.QtWidgets import (
    QComboBox,
    QDialog,
    QDialogButtonBox,
    QFileDialog,
    QFormLayout,
    QHBoxLayout,
    QHeaderView,
    QLabel,
    QLineEdit,
    QMessageBox,
    QPushButton,
    QTableWidget,
    QTableWidgetItem,
    QVBoxLayout,
)

from src.backend.textbook_project import TextbookProject
from src.backend.textbook_project_store import ProjectSummary, TextbookProjectStore
from src.application.settings import course_clones_dir
from src.dialogs.git_library.git_worker_hub import GitWorkerHub

_STEP_LABELS = [
    "选择教材",
    "解析课本",
    "章节勾选",
    "提取知识点",
    "审校",
    "导入",
]


class TextbookLibraryDialog(QDialog):
    """Dialog for managing textbook import projects.

    Emits ``project_selected`` when the user chooses to create or continue a
    project. The caller then opens ``TextbookImportDialog`` with that project.
    """

    project_selected = Signal(object)  # TextbookProject | None

    def __init__(
        self,
        store: TextbookProjectStore | None = None,
        parent: Any | None = None,
        *,
        embedded: bool = False,
    ) -> None:
        super().__init__(parent)
        self._store = store or TextbookProjectStore()
        self.selected_project: TextbookProject | None = None
        self._summaries: list[ProjectSummary] = []
        # Embedded mode (P2-2): hosted inside WorkshopWindow as a plain
        # widget — project selection is signalled, never accept()/hide.
        self._embedded = embedded
        self.setWindowTitle("课本项目库")
        self.resize(720, 420)
        self._build_ui()
        self._refresh_list()

    def _build_ui(self) -> None:
        layout = QVBoxLayout(self)
        layout.setContentsMargins(16, 16, 16, 16)
        layout.setSpacing(12)

        layout.addWidget(QLabel("选择项目继续创作，或新建：教材项目从素材开始，空白 AI 项目直达设计。所有进度自动保存，可随时关闭。"))

        self._table = QTableWidget(0, 5)
        self._table.setHorizontalHeaderLabels(
            ["项目名称", "源文件", "当前步骤", "更新时间", "已导入"]
        )
        self._table.horizontalHeader().setSectionResizeMode(0, QHeaderView.ResizeMode.Stretch)
        self._table.horizontalHeader().setSectionResizeMode(1, QHeaderView.ResizeMode.Stretch)
        self._table.setSelectionBehavior(QTableWidget.SelectionBehavior.SelectRows)
        self._table.setSelectionMode(QTableWidget.SelectionMode.SingleSelection)
        self._table.doubleClicked.connect(self._on_continue)
        layout.addWidget(self._table)

        self._empty_label = QLabel("还没有项目：从教材新建，或创建空白 AI 项目直接开始设计。")
        self._empty_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        from src.theme import current_palette

        self._empty_label.setStyleSheet(
            f"color: {current_palette()['text_secondary']}; padding: 40px;"
        )
        layout.addWidget(self._empty_label)

        btn_row = QHBoxLayout()
        self._new_btn = QPushButton("从教材新建…")
        self._new_btn.setToolTip("选择 .md/.txt/.pdf 教材文件，提取知识点后由 AI 设计课程")
        self._new_btn.clicked.connect(self._on_new)
        self._new_blank_btn = QPushButton("空白 AI 项目")
        self._new_blank_btn.setToolTip("无教材，直接进入 AI 设计阶段自由生成课程")
        self._new_blank_btn.clicked.connect(self._on_new_blank)
        self._from_git_btn = QPushButton("从 Git 库导入教材…")
        self._from_git_btn.setToolTip("从已保存的 Git 远程仓库克隆并选择教材源文件")
        self._from_git_btn.clicked.connect(self._on_import_from_git)
        self._publish_git_btn = QPushButton("发布到 Git 库…")
        self._publish_git_btn.setToolTip("将项目导出的 section JSON 推送到 Git 远程仓库")
        self._publish_git_btn.clicked.connect(self._on_publish_to_git)
        self._continue_btn = QPushButton("继续")
        self._continue_btn.setEnabled(False)
        self._continue_btn.clicked.connect(self._on_continue)
        self._delete_btn = QPushButton("删除")
        self._delete_btn.setEnabled(False)
        self._delete_btn.clicked.connect(self._on_delete)
        btn_row.addWidget(self._new_btn)
        btn_row.addWidget(self._new_blank_btn)
        btn_row.addWidget(self._from_git_btn)
        btn_row.addWidget(self._publish_git_btn)
        btn_row.addStretch()
        btn_row.addWidget(self._continue_btn)
        btn_row.addWidget(self._delete_btn)
        layout.addLayout(btn_row)

        self._table.itemSelectionChanged.connect(self._update_button_state)

        # --- async git worker plumbing (delegates to GitWorkerHub) --------
        self.git_worker_hub = GitWorkerHub(self)
        self._git_busy_label = QLabel("")
        self._git_busy_label.setVisible(False)
        layout.addWidget(self._git_busy_label)

    @property
    def _git_worker(self) -> Any:
        """Compat view of the hub's in-flight worker (tests poll it)."""
        return self.git_worker_hub._worker

    @_git_worker.setter
    def _git_worker(self, val: Any) -> None:
        self.git_worker_hub._worker = val

    def _set_git_busy(self, busy: bool, label: str = "") -> None:
        """Toggle the async-git busy state (disable git buttons + hint)."""
        self._from_git_btn.setEnabled(not busy)
        self._publish_git_btn.setEnabled(not busy)
        self._git_busy_label.setText(label)
        self._git_busy_label.setVisible(busy)

    def _run_git_async(
        self,
        label: str,
        fn,
        *args,
        on_ok=None,
        error_title: str = "操作失败",
    ) -> None:
        """Run a git/backend call in a background worker (main thread stays
        responsive during network clone/push).

        Delegates to the shared ``GitWorkerHub`` (cancels/disconnects any
        still-running previous worker, shows a busy hint, and delivers the
        result or error message back on the UI thread).
        """
        self.git_worker_hub.run_async(
            label, fn, *args, on_ok=on_ok, error_title=error_title
        )

    def _refresh_list(self) -> None:
        self._summaries = self._store.list_project_summaries()
        self._table.setRowCount(len(self._summaries))
        for row, summary in enumerate(self._summaries):
            self._table.setItem(row, 0, QTableWidgetItem(summary.name))
            source_name = (
                Path(summary.source_path).name
                if summary.has_source
                else "—（纯 AI 项目）"
            )
            self._table.setItem(row, 1, QTableWidgetItem(source_name))
            step_label = (
                _STEP_LABELS[summary.current_step]
                if 0 <= summary.current_step < len(_STEP_LABELS)
                else "未知"
            )
            self._table.setItem(row, 2, QTableWidgetItem(step_label))
            self._table.setItem(row, 3, QTableWidgetItem(summary.updated_at[:19].replace("T", " ")))
            imported = "是" if summary.imported else "否"
            self._table.setItem(row, 4, QTableWidgetItem(imported))

        has_projects = len(self._summaries) > 0
        self._table.setVisible(has_projects)
        self._empty_label.setVisible(not has_projects)
        self._update_button_state()

    def _selected_summary(self) -> ProjectSummary | None:
        rows = self._table.selectionModel().selectedRows()
        if not rows:
            return None
        idx = rows[0].row()
        if 0 <= idx < len(self._summaries):
            return self._summaries[idx]
        return None

    def _update_button_state(self) -> None:
        has_selection = self._selected_summary() is not None
        self._continue_btn.setEnabled(has_selection)
        self._delete_btn.setEnabled(has_selection)

    def _on_new(self) -> None:
        path, _ = QFileDialog.getOpenFileName(
            self,
            "选择教材",
            "",
            "教材 (*.md *.txt *.pdf);;所有文件 (*)",
        )
        if not path:
            return
        languages = self._pick_languages()
        if languages is None:
            return
        source = Path(path)
        name = source.stem
        project = self._store.create_project(
            name=name,
            source_path=source,
            language=languages[0],
            source_language=languages[1],
        )
        self.selected_project = project
        self.project_selected.emit(project)
        if not self._embedded:
            self.accept()

    def _on_new_blank(self) -> None:
        """Create a source-less AI project: name + languages, no textbook file.

        This is the form the standalone "AI 生成课程" feature takes inside
        the workshop — the workshop jumps such projects straight to the
        design stage.
        """
        meta = self._pick_blank_meta()
        if meta is None:
            return
        name, target, source = meta
        project = self._store.create_project(
            name=name, source_path=None, language=target, source_language=source
        )
        self.selected_project = project
        self.project_selected.emit(project)
        if not self._embedded:
            self.accept()

    def _pick_blank_meta(self) -> tuple[str, str, str] | None:
        """Ask for the name and language pair of a blank AI project.

        Returns ``(name, target_language, source_language)`` or None on cancel.
        """
        dlg = QDialog(self)
        dlg.setWindowTitle("空白 AI 项目")
        lay = QVBoxLayout(dlg)
        lay.addWidget(QLabel("无教材的自由创作：打开后将直接进入 AI 设计阶段。"))
        form = QFormLayout()
        name_edit = QLineEdit()
        name_edit.setPlaceholderText("如：土耳其语入门")
        target = QComboBox()
        target.setEditable(True)
        target.addItems(
            ["Turkish", "English", "Spanish", "Japanese", "Korean", "German", "French"]
        )
        source = QComboBox()
        source.setEditable(True)
        source.addItems(["Chinese", "English", "Japanese", "Korean"])
        form.addRow("项目名称", name_edit)
        form.addRow("目标语言", target)
        form.addRow("讲解语言", source)
        lay.addLayout(form)
        btns = QDialogButtonBox(
            QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel
        )
        btns.accepted.connect(dlg.accept)
        btns.rejected.connect(dlg.reject)
        lay.addWidget(btns)
        if dlg.exec() != QDialog.DialogCode.Accepted:
            return None
        return (
            name_edit.text().strip() or "未命名项目",
            target.currentText().strip() or "Turkish",
            source.currentText().strip() or "Chinese",
        )

    def _pick_languages(self) -> tuple[str, str] | None:
        """Ask for the target/source language pair of a new project (P0-3).

        Returns ``(target_language, source_language)`` or None on cancel.
        """
        dlg = QDialog(self)
        dlg.setWindowTitle("项目语言")
        lay = QVBoxLayout(dlg)
        lay.addWidget(QLabel("选择这本教材的目标语言（要学）与讲解语言："))
        form = QFormLayout()
        target = QComboBox()
        target.setEditable(True)
        target.addItems(
            ["Turkish", "English", "Spanish", "Japanese", "Korean", "German", "French"]
        )
        source = QComboBox()
        source.setEditable(True)
        source.addItems(["Chinese", "English", "Japanese", "Korean"])
        form.addRow("目标语言", target)
        form.addRow("讲解语言", source)
        lay.addLayout(form)
        btns = QDialogButtonBox(
            QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel
        )
        btns.accepted.connect(dlg.accept)
        btns.rejected.connect(dlg.reject)
        lay.addWidget(btns)
        if dlg.exec() != QDialog.DialogCode.Accepted:
            return None
        return (
            target.currentText().strip() or "Turkish",
            source.currentText().strip() or "Chinese",
        )

    def _on_continue(self) -> None:
        summary = self._selected_summary()
        if summary is None:
            return
        project = self._store.load_project(summary.project_id)
        if project is None:
            QMessageBox.critical(self, "打开失败", "无法加载所选项目。")
            return
        if project.source_path and project.source_changed():
            reply = QMessageBox.question(
                self,
                "源文件已变更",
                "教材源文件自上次保存后已被修改。是否继续？",
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
            )
            if reply != QMessageBox.StandardButton.Yes:
                return
        self.selected_project = project
        self.project_selected.emit(project)
        if not self._embedded:
            self.accept()

    def _on_delete(self) -> None:
        summary = self._selected_summary()
        if summary is None:
            return
        reply = QMessageBox.question(
            self,
            "删除项目",
            f"确定要删除项目「{summary.name}」吗？本地项目文件将被一并删除。",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
        )
        if reply == QMessageBox.StandardButton.Yes:
            self._store.delete_project(summary.project_id)
            self._refresh_list()

    def _on_import_from_git(self) -> None:
        """Clone a saved git remote and create a project from a textbook file within it."""
        from src.application import git_remote_catalog
        from src.backend.git_library import GitLibrary

        remotes = git_remote_catalog.load_remotes()
        if not remotes:
            QMessageBox.information(
                self, "无已保存远程",
                "请先在「资源库 ▸ Git 资源库」中保存一个远程仓库。",
            )
            return
        # Pick a remote.
        items = [f"{r.name} — {r.url}" for r in remotes]
        from PySide6.QtWidgets import QInputDialog
        choice, ok = QInputDialog.getItem(
            self, "选择远程仓库", "选择要导入教材的 Git 远程：", items, 0, False
        )
        if not ok or not choice:
            return
        idx = items.index(choice)
        remote = remotes[idx]
        # Clone/pull runs in a background worker — a cold clone of a large
        # repo took 10s+ of frozen UI on the main thread before.
        git = GitLibrary()
        local_dir = Path(remote.local_dir) if remote.local_dir else course_clones_dir() / remote.name

        def _after_clone(_result) -> None:
            # Back on the UI thread: continue with the modal pickers.
            git_remote_catalog.mark_synced(remote.name)
            path, _filter = QFileDialog.getOpenFileName(
                self, "选择教材（从克隆的仓库中）", str(local_dir),
                "教材 (*.md *.txt *.pdf);;所有文件 (*)",
            )
            if not path:
                return
            languages = self._pick_languages()
            if languages is None:
                return
            source = Path(path)
            name = source.stem
            project = self._store.create_project(
                name=name,
                source_path=source,
                language=languages[0],
                source_language=languages[1],
            )
            self.selected_project = project
            self.project_selected.emit(project)
            if not self._embedded:
                self.accept()

        self._run_git_async(
            f"正在从 {remote.name} 克隆…",
            git.clone,
            remote.url,
            local_dir,
            on_ok=_after_clone,
            error_title="克隆失败",
        )

    def _on_publish_to_git(self) -> None:
        """Export the selected project's section JSON to a git remote and push."""
        summary = self._selected_summary()
        if summary is None:
            QMessageBox.information(self, "未选择项目", "请先选择一个项目。")
            return
        from src.application import git_remote_catalog
        from src.backend.git_library import GitLibrary

        remotes = git_remote_catalog.load_remotes()
        if not remotes:
            QMessageBox.information(
                self, "无已保存远程",
                "请先在「资源库 ▸ Git 资源库」中保存一个远程仓库。",
            )
            return
        items = [f"{r.name} — {r.url}" for r in remotes]
        from PySide6.QtWidgets import QInputDialog
        choice, ok = QInputDialog.getItem(
            self, "选择远程仓库", "选择要发布到的 Git 远程：", items, 0, False
        )
        if not ok or not choice:
            return
        idx = items.index(choice)
        remote = remotes[idx]

        def _publish_chain() -> int:
            """Backend-only publish chain, runs on the worker thread."""
            import json

            project = self._store.load_project(summary.project_id)
            if project is None:
                raise RuntimeError("无法加载所选项目。")
            # Publishable sections are the workshop design draft (the same
            # payload「导入到课程」emits). ``project.sections`` never existed —
            # this path used to AttributeError before the async rework.
            sections = list(
                (getattr(project, "design", None) or {}).get("draft_sections")
                or []
            )
            if not sections:
                raise RuntimeError("项目还没有可发布的草稿 sections（请先在工坊生成设计）。")
            git = GitLibrary()
            local_dir = (
                Path(remote.local_dir) if remote.local_dir
                else course_clones_dir() / remote.name
            )
            try:
                git.clone(remote.url, local_dir)
            except RuntimeError as exc:
                raise RuntimeError(f"克隆失败：{exc}") from exc
            sections_dir = local_dir / "sections"
            sections_dir.mkdir(parents=True, exist_ok=True)
            exported = 0
            for section in sections:
                sid = section.get("id", f"section{exported + 1}")
                (sections_dir / f"{sid}.json").write_text(
                    json.dumps(section, ensure_ascii=False, indent=2),
                    encoding="utf-8",
                )
                exported += 1
            index_path = local_dir / "index.json"
            index_data = {
                "version": 5,
                "language": project.language,
                "sections": sections,
            }
            index_path.write_text(
                json.dumps(index_data, ensure_ascii=False, indent=2),
                encoding="utf-8",
            )
            try:
                git.commit_and_push(
                    local_dir,
                    f"发布教材项目: {summary.name} ({exported} sections)",
                )
            except RuntimeError as exc:
                raise RuntimeError(f"推送失败：{exc}") from exc
            return exported

        def _after_publish(exported: int) -> None:
            git_remote_catalog.mark_synced(remote.name)
            QMessageBox.information(
                self, "发布成功",
                f"已将 {exported} 个 section 发布到 {remote.name}。\n"
                f"仓库：{Path(remote.local_dir) if remote.local_dir else course_clones_dir() / remote.name}",
            )

        self._run_git_async(
            f"正在发布到 {remote.name}（克隆 + 推送）…",
            _publish_chain,
            on_ok=_after_publish,
            error_title="发布失败",
        )
