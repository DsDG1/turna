"""Main window for the Varnamala GUI course editor."""
from __future__ import annotations

from pathlib import Path

from PySide6.QtCore import Qt, QSettings
from PySide6.QtGui import QAction
from PySide6.QtWidgets import (
    QFileDialog,
    QHBoxLayout,
    QLabel,
    QMainWindow,
    QMenu,
    QMessageBox,
    QSplitter,
    QStatusBar,
    QToolBar,
    QToolButton,
    QVBoxLayout,
    QWidget,
)

from src.backend.course_adapter import CourseAdapter
from src.widgets.course_tree import CourseTreeWidget
from src.widgets.detail_panel import DetailPanel


class MainWindow(QMainWindow):
    """Application main window: tree on the left, detail panel on the right."""

    def __init__(self) -> None:
        super().__init__()
        self.setWindowTitle("Varnamala 课程编辑器")
        self.resize(1280, 800)

        self.adapter = CourseAdapter()
        self.course_dir: Path | None = None
        self._current_node_ref: tuple[str, str] | None = None
        self.teacher_mode: bool = False

        self._settings = QSettings("Varnamala", "CourseEditor")

        self._build_toolbar()
        self._build_central()
        self._build_status_bar()
        self._maybe_open_last_repo()

    def _build_toolbar(self) -> None:
        toolbar = QToolBar("main")
        toolbar.setMovable(False)
        toolbar.setToolButtonStyle(Qt.ToolButtonStyle.ToolButtonTextBesideIcon)
        self.addToolBar(toolbar)

        self.new_action = QAction("新建课程目录", self)
        self.new_action.triggered.connect(self._on_new_course)
        toolbar.addAction(self.new_action)

        self.open_action = QAction("打开课程目录", self)
        self.open_action.triggered.connect(self._on_open)
        toolbar.addAction(self.open_action)

        self.recent_btn = QToolButton(self)
        self.recent_btn.setText("最近仓库")
        self.recent_btn.setPopupMode(QToolButton.ToolButtonPopupMode.InstantPopup)
        self.recent_menu = QMenu(self)
        self.recent_btn.setMenu(self.recent_menu)
        self.recent_menu.aboutToShow.connect(self._populate_recent_menu)
        toolbar.addWidget(self.recent_btn)

        self.save_action = QAction("保存", self)
        self.save_action.setEnabled(False)
        self.save_action.triggered.connect(self._on_save)
        toolbar.addAction(self.save_action)

        toolbar.addSeparator()

        self.wizard_action = QAction("向导建课", self)
        self.wizard_action.setEnabled(False)
        self.wizard_action.triggered.connect(self._on_wizard)
        toolbar.addAction(self.wizard_action)

        self.ai_action = QAction("AI 生成课程（Beta）", self)
        self.ai_action.setEnabled(False)
        self.ai_action.triggered.connect(self._on_ai_generate)
        toolbar.addAction(self.ai_action)

        self.resources_action = QAction("资源库", self)
        self.resources_action.setEnabled(False)
        self.resources_action.triggered.connect(self._on_resources)
        toolbar.addAction(self.resources_action)

        self.publish_action = QAction("发布", self)
        self.publish_action.setEnabled(False)
        self.publish_action.triggered.connect(self._on_publish)
        toolbar.addAction(self.publish_action)

        toolbar.addSeparator()

        self.mode_action = QAction("教师模式", self)
        self.mode_action.setCheckable(True)
        self.mode_action.toggled.connect(self._on_mode_toggled)
        toolbar.addAction(self.mode_action)

    def _build_central(self) -> None:
        splitter = QSplitter(Qt.Horizontal)

        self.tree = CourseTreeWidget()
        self.tree.node_selected.connect(self._on_node_selected)
        self.tree.tree_changed.connect(self._on_tree_changed)
        splitter.addWidget(self.tree)

        self.detail = DetailPanel()
        splitter.addWidget(self.detail)

        splitter.setStretchFactor(0, 2)
        splitter.setStretchFactor(1, 3)
        self.setCentralWidget(splitter)

    def _build_status_bar(self) -> None:
        status = QStatusBar()
        status.setFixedHeight(28)
        disclaimer = QLabel("AI 生成内容仅供参考，请作者自行审核其准确性与适用性。")
        disclaimer.setStyleSheet("color: #9CA3AF; font-size: 11px;")
        disclaimer.setToolTip(disclaimer.text())
        status.addPermanentWidget(disclaimer)
        self.setStatusBar(status)

    # --- Recent repository management ------------------------------------

    def _load_recent_repos(self) -> list[dict[str, str]]:
        raw = self._settings.value("recent_repos", "[]")
        if not isinstance(raw, str):
            return []
        try:
            import json
            data = json.loads(raw)
            if isinstance(data, list):
                return [item for item in data if isinstance(item, dict) and item.get("path")]
        except Exception:
            pass
        return []

    def _save_recent_repos(self, repos: list[dict[str, str]]) -> None:
        import json
        self._settings.setValue("recent_repos", json.dumps(repos[:10], ensure_ascii=False))

    def _add_recent_repo(self, path: Path) -> None:
        from datetime import datetime, timezone
        repos = self._load_recent_repos()
        path_str = str(Path(path).resolve())
        repos = [r for r in repos if r.get("path") != path_str]
        repos.insert(0, {"path": path_str, "opened_at": datetime.now(timezone.utc).isoformat()})
        self._save_recent_repos(repos)

    def _populate_recent_menu(self) -> None:
        self.recent_menu.clear()
        repos = self._load_recent_repos()
        if not repos:
            action = self.recent_menu.addAction("（无历史记录）")
            action.setEnabled(False)
            return
        for repo in repos:
            path = repo.get("path", "")
            action = self.recent_menu.addAction(path)
            action.triggered.connect(lambda checked=False, p=path: self._open_repo_path(p))
        self.recent_menu.addSeparator()
        clear_action = self.recent_menu.addAction("清除历史记录")
        clear_action.triggered.connect(self._clear_recent_repos)

    def _clear_recent_repos(self) -> None:
        self._save_recent_repos([])

    def _maybe_open_last_repo(self) -> None:
        repos = self._load_recent_repos()
        if not repos:
            return
        last_path = repos[0].get("path", "")
        if not last_path or not Path(last_path).exists():
            return
        reply = QMessageBox.question(
            self,
            "打开最近仓库",
            f"是否打开上次使用的课程仓库？\n{last_path}",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
            QMessageBox.StandardButton.Yes,
        )
        if reply == QMessageBox.StandardButton.Yes:
            self._open_repo_path(last_path)

    def _open_repo_path(self, path_str: str) -> None:
        path = Path(path_str)
        if not path.exists() or not CourseAdapter.is_course_dir(path):
            QMessageBox.warning(self, "无法打开", f"目录不存在或不是有效的课程仓库：\n{path}")
            return
        try:
            self.adapter.load(path)
        except Exception as exc:
            QMessageBox.critical(self, "加载失败", str(exc))
            return
        self.course_dir = path
        self.tree.display(self.adapter)
        self._enable_editor_actions()
        self._add_recent_repo(path)
        self.statusBar().showMessage(f"已加载: {self.course_dir}", 4000)

    def _enable_editor_actions(self) -> None:
        self.save_action.setEnabled(True)
        self.wizard_action.setEnabled(True)
        self.ai_action.setEnabled(True)
        self.resources_action.setEnabled(True)
        self.publish_action.setEnabled(True)

    # --- Toolbar actions -------------------------------------------------

    def _on_new_course(self) -> None:
        from src.dialogs.init_course_dialog import InitCourseDialog

        dlg = InitCourseDialog(self.adapter, self)
        if not dlg.exec():
            return
        init_dir = dlg.init_dir()
        if not init_dir:
            return
        self.course_dir = init_dir
        self.tree.display(self.adapter)
        self._enable_editor_actions()
        self._add_recent_repo(init_dir)
        self.statusBar().showMessage(f"已新建并加载: {init_dir}", 5000)

    def _on_open(self) -> None:
        start = str(self.course_dir) if self.course_dir else ""
        chosen = QFileDialog.getExistingDirectory(self, "选择课程目录", start)
        if not chosen:
            return
        try:
            self.adapter.load(Path(chosen))
        except Exception as exc:
            QMessageBox.critical(self, "加载失败", str(exc))
            return
        self.course_dir = Path(chosen)
        self.tree.display(self.adapter)
        self._enable_editor_actions()
        self._add_recent_repo(self.course_dir)
        self.statusBar().showMessage(f"已加载: {self.course_dir}", 4000)

    def _on_mode_toggled(self, checked: bool) -> None:
        self.teacher_mode = checked
        self.mode_action.setText("教师模式：开" if checked else "教师模式")
        self.setWindowTitle(
            "Varnamala 课程编辑器 · 教师模式" if checked else "Varnamala 课程编辑器"
        )
        if self._current_node_ref is not None:
            self._on_node_selected(self._current_node_ref)
        self.statusBar().showMessage(
            "已切换到教师模式" if checked else "已切换到专家模式", 3000
        )

    def _on_wizard(self) -> None:
        from src.teacher.lesson_wizard import LessonWizardDialog

        dlg = LessonWizardDialog(self.adapter, self)
        if not dlg.exec() or dlg.lesson() is None:
            return
        lesson = dlg.lesson()
        node_ref = self._current_node_ref
        try:
            if node_ref and node_ref[0] == "unit":
                _section, unit = self.adapter.find_unit(node_ref[1])
            elif node_ref and node_ref[0] == "lesson":
                _section, unit, _lesson = self.adapter.find_lesson(node_ref[1])
            else:
                if not self.adapter.sections:
                    QMessageBox.critical(self, "创建失败", "课程没有 Section，请先添加 Section。")
                    return
                section = self.adapter.sections[0]
                units = section.get("units", [])
                if not units:
                    QMessageBox.critical(self, "创建失败", "目标 Section 没有 Unit，请先添加 Unit。")
                    return
                unit = units[0]
            unit.setdefault("lessons", []).append(lesson)
        except Exception as exc:
            QMessageBox.critical(self, "创建失败", str(exc))
            return
        self.tree.refresh()
        self.tree.select_lesson(lesson["id"])
        self.statusBar().showMessage(
            f"已生成课程「{lesson.get('name', '')}」，记得保存", 5000
        )

    def _on_ai_generate(self) -> None:
        from src.dialogs.ai_generator_dialog import AiGeneratorDialog

        if not self._settings.value("ai_beta_warning_shown", False):
            QMessageBox.information(
                self,
                "AI 生成课程（Beta）",
                "AI 生成课程为 Beta 功能，生成结果仅供参考，请作者自行审核。\n\n"
                "本功能会消耗大量 token，且建议模型支持 1M 上下文窗口。\n\n"
                "点击「确定」继续。",
            )
            self._settings.setValue("ai_beta_warning_shown", True)

        dlg = AiGeneratorDialog(self.adapter, self)
        if not dlg.exec():
            return
        try:
            section = dlg.section_json()
        except ValueError as exc:
            QMessageBox.warning(self, "无法导入", str(exc))
            return
        if not self.course_dir:
            QMessageBox.warning(self, "未加载课程目录", "请先打开课程目录。")
            return

        existing_ids = {s.get("id") for s in self.adapter.sections}
        existing_index_ids = {
            e.get("id") for e in self.adapter.index.get("sections", [])
        }
        sid = section.get("id") or ""
        if not sid:
            QMessageBox.warning(self, "缺少 section id", "生成的 JSON 缺少顶层 id 字段。")
            return
        if sid in existing_ids or sid in existing_index_ids:
            QMessageBox.warning(
                self,
                "ID 冲突",
                f"section id「{sid}」已存在，请修改 JSON 中的 id 后再导入。",
            )
            return

        problems = self.adapter.validate_section_json(section)
        errors = [p for p in problems if p["level"] == "error"]
        warnings = [p for p in problems if p["level"] == "warning"]
        if errors:
            detail = "\n".join(f"[{p['level']}] {p['message']}" for p in errors)
            QMessageBox.warning(self, "AI section 校验失败", detail)
            return
        if warnings:
            detail = "\n".join(f"[{p['level']}] {p['message']}" for p in warnings)
            QMessageBox.information(
                self, "AI section 导入警告", f"存在警告，但仍可导入：\n\n{detail}"
            )

        section_file_name = f"sections/{sid}.json"
        section.setdefault("prerequisiteSectionIds", [])

        self.adapter.sections.append(section)
        self.adapter.index.setdefault("sections", []).append(
            {
                "id": sid,
                "name": section.get("name", sid),
                "description": section.get("description", ""),
                "level": section.get("level", ""),
                "prerequisiteSectionIds": section.get("prerequisiteSectionIds", []),
                "file": section_file_name,
            }
        )

        self.tree.refresh()
        self.tree.select_section(sid)
        self.statusBar().showMessage(
            f"已通过 AI 生成课程「{section.get('name', sid)}」并已选中，记得保存", 6000
        )

    def _on_node_selected(self, node_ref: tuple[str, str]) -> None:
        self._current_node_ref = node_ref
        if self.course_dir is None:
            return
        if self.teacher_mode and node_ref[0] == "lesson":
            try:
                section, unit, lesson = self.adapter.find_lesson(node_ref[1])
            except KeyError:
                self.detail.show_node(self.adapter, node_ref)
                return
            self.detail.show_teacher_lesson(self.adapter, section, unit, lesson)
        else:
            self.detail.show_node(self.adapter, node_ref)

    def _on_tree_changed(self) -> None:
        self.tree.refresh()

    def _on_resources(self) -> None:
        if self.teacher_mode:
            from PySide6.QtWidgets import QDialog, QDialogButtonBox

            from src.teacher.vocab_table import VocabTableWidget

            dlg = QDialog(self)
            dlg.setWindowTitle("词库")
            dlg.resize(760, 520)
            table = VocabTableWidget(self.adapter, dlg)
            buttons = QDialogButtonBox(QDialogButtonBox.StandardButton.Close)
            buttons.rejected.connect(dlg.reject)
            layout = QVBoxLayout(dlg)
            layout.addWidget(table)
            layout.addWidget(buttons)
            dlg.exec()
            if table.is_dirty():
                self.tree.refresh()
                self.statusBar().showMessage("词库已修改，记得保存", 5000)
            return
        from PySide6.QtWidgets import QDialog, QDialogButtonBox

        from src.widgets.resource_editor import ResourceEditorDialog

        dlg = QDialog(self)
        dlg.setWindowTitle("资源编辑")
        dlg.resize(900, 560)
        editor = ResourceEditorDialog(self.adapter, dlg)
        buttons = QDialogButtonBox(QDialogButtonBox.StandardButton.Close)
        buttons.rejected.connect(dlg.reject)
        layout = QVBoxLayout(dlg)
        layout.addWidget(editor)
        layout.addWidget(buttons)
        dlg.exec()

        if editor.is_dirty():
            self.tree.refresh()
            if self._current_node_ref is not None:
                self.detail.show_node(self.adapter, self._current_node_ref)
            self.statusBar().showMessage("资源已修改，记得保存", 5000)

    def _on_publish(self) -> None:
        if self.teacher_mode:
            from src.teacher.publish_dialog import TeacherPublishDialog

            dlg = TeacherPublishDialog(self.adapter, self)
            if dlg.exec():
                self.tree.refresh()
                self.statusBar().showMessage("发布成功", 5000)
            return
        from src.widgets.publish_dialog import PublishDialog

        dlg = PublishDialog(self.adapter, self)
        if dlg.exec():
            self.tree.refresh()
            if self._current_node_ref is not None:
                self.detail.show_node(self.adapter, self._current_node_ref)
            self.statusBar().showMessage("发布成功", 5000)

    def _on_save(self) -> None:
        result = self.adapter.save()
        self.tree.refresh()
        if result.ok:
            self.statusBar().showMessage(result.message or "保存成功", 5000)
        else:
            self.statusBar().showMessage(result.message or "保存失败（已回滚）", 8000)
            if result.errors:
                detail_text = "\n".join(
                    f"[{e.get('level', 'error')}] {e.get('message', '')}"
                    for e in result.errors
                )
                QMessageBox.warning(self, "校验失败（已回滚）", detail_text)

    def closeEvent(self, event) -> None:  # noqa: N802
        if self.course_dir and self.adapter and any(self.adapter.detect_changes().values()):
            reply = QMessageBox.question(
                self,
                "未保存的更改",
                "当前课程有未保存的更改，是否保存？",
                (
                    QMessageBox.StandardButton.Save
                    | QMessageBox.StandardButton.Discard
                    | QMessageBox.StandardButton.Cancel
                ),
                QMessageBox.StandardButton.Save,
            )
            if reply == QMessageBox.StandardButton.Save:
                result = self.adapter.save()
                if result.ok:
                    event.accept()
                else:
                    event.ignore()
                    detail_text = "\n".join(
                        f"[{e.get('level', 'error')}] {e.get('message', '')}"
                        for e in result.errors
                    )
                    QMessageBox.warning(
                        self,
                        "保存失败（窗口未关闭）",
                        detail_text or result.message or "未知错误",
                    )
            elif reply == QMessageBox.StandardButton.Discard:
                event.accept()
            else:
                event.ignore()
        else:
            event.accept()
