"""Standalone course-planning window (P0-2).

A teacher-facing outline editor:

- fill the planning form, ask the model for a course outline,
- review the section ladder and the course-wide lexicon,
- save the plan under ``tool/var/course_plans``.

The plan never touches course files. Per-section generation/import is P0-3 and
deliberately absent here.

Layering: this widget imports only ``src.application.course_plan_service`` and
PySide6. It must not import ``src.backend`` (``ui_backend`` is a ratchet).
"""
from __future__ import annotations

import json
import logging
from typing import Any

from PySide6.QtCore import Qt, QTimer
from PySide6.QtWidgets import (
    QAbstractItemView,
    QCheckBox,
    QComboBox,
    QDialog,
    QFileDialog,
    QFormLayout,
    QGroupBox,
    QHBoxLayout,
    QHeaderView,
    QLabel,
    QLineEdit,
    QMessageBox,
    QPlainTextEdit,
    QPushButton,
    QSpinBox,
    QSplitter,
    QTabWidget,
    QTableWidget,
    QTableWidgetItem,
    QVBoxLayout,
    QWidget,
)

from src.application.ai_request_worker import AiRequestWorker
from src.application.course_plan_service import PLAN_LEVELS, CoursePlanService
from src.application.ui_guard import safe_question

logger = logging.getLogger(__name__)


class CoursePlanWindow(QWidget):
    """Non-modal planning window: form → outline → persisted plan."""

    def __init__(
        self,
        adapter: Any,
        parent: QWidget | None = None,
        *,
        config_fn: Any = None,
        settings_fn: Any = None,
        import_fn: Any = None,
    ) -> None:
        super().__init__(parent)
        self.setWindowFlag(Qt.WindowType.Window, True)
        self.setWindowTitle("整门课程规划")
        self.resize(1120, 740)
        self.setMinimumSize(900, 560)
        self.setAttribute(Qt.WidgetAttribute.WA_DeleteOnClose, True)

        self._adapter = adapter
        self._service = CoursePlanService(adapter)
        self._config_fn = config_fn or (lambda: None)
        self._settings_fn = settings_fn or (lambda: None)
        self._import_fn = import_fn
        self._plan: Any = None
        self._worker: AiRequestWorker | None = None
        self._busy = False
        self._chunks = 0
        self._usage_total = 0
        self._section_usage = 0
        self._gen_section_id = ""
        self._task_kind = ""  # "" | "plan" | "section"
        self._had_error = False
        self._closing = False

        self._build_ui()
        self._apply_spec_to_form(self._service.default_spec())
        self._reload_summaries()

    # --- construction ---------------------------------------------------

    def _build_ui(self) -> None:
        root = QVBoxLayout(self)
        root.setContentsMargins(14, 12, 14, 12)
        root.setSpacing(10)

        hint = QLabel(
            "先生成大纲，再逐节生成草稿并导入。大纲与草稿只保存到 "
            "tool/var/course_plans，不写课程 JSON；导入仍走现有校验、合并预览与撤销。"
        )
        hint.setWordWrap(True)
        root.addWidget(hint)

        top = QHBoxLayout()
        top.addWidget(QLabel("已保存规划"))
        self.plan_combo = QComboBox()
        self.plan_combo.setMinimumWidth(360)
        top.addWidget(self.plan_combo, 1)
        self.load_btn = QPushButton("载入")
        self.load_btn.clicked.connect(self._on_load_plan)
        top.addWidget(self.load_btn)
        self.delete_btn = QPushButton("删除")
        self.delete_btn.clicked.connect(self._on_delete_plan)
        top.addWidget(self.delete_btn)
        root.addLayout(top)

        split = QSplitter(Qt.Orientation.Horizontal)
        split.setChildrenCollapsible(False)

        # --- form -------------------------------------------------------
        form_box = QGroupBox("规划参数")
        form = QFormLayout(form_box)
        form.setFieldGrowthPolicy(QFormLayout.FieldGrowthPolicy.AllNonFixedFieldsGrow)
        self.lang_edit = QLineEdit()
        self.src_edit = QLineEdit()
        self.topic_edit = QLineEdit()
        self.topic_edit.setPlaceholderText("例如：日常土耳其语 · 旅行场景")
        form.addRow("目标语言", self.lang_edit)
        form.addRow("提示语言", self.src_edit)
        form.addRow("课程主题", self.topic_edit)

        self.level_from_combo = QComboBox()
        self.level_to_combo = QComboBox()
        for level in PLAN_LEVELS:
            self.level_from_combo.addItem(level)
            self.level_to_combo.addItem(level)
        levels = QHBoxLayout()
        levels.addWidget(self.level_from_combo, 1)
        levels.addWidget(QLabel("→"))
        levels.addWidget(self.level_to_combo, 1)
        form.addRow("等级范围", levels)

        self.sections_spin = QSpinBox()
        self.sections_spin.setRange(1, 24)
        self.lessons_spin = QSpinBox()
        self.lessons_spin.setRange(1, 60)
        self.budget_spin = QSpinBox()
        self.budget_spin.setRange(0, 5000)
        self.budget_spin.setSingleStep(10)
        form.addRow("章节数", self.sections_spin)
        form.addRow("每章课时数", self.lessons_spin)
        form.addRow("全课程新词预算", self.budget_spin)

        self.mode_combo = QComboBox()
        self.mode_combo.addItem("快速（整节一次）", "fast")
        self.mode_combo.addItem("精修（大纲→分课）", "refine")
        form.addRow("逐节生成模式", self.mode_combo)

        self.token_budget_spin = QSpinBox()
        self.token_budget_spin.setRange(0, 10_000_000)
        self.token_budget_spin.setSingleStep(1000)
        self.token_budget_spin.setToolTip("0 表示不限；达到预算后停止自动连续生成")
        form.addRow("Token 预算", self.token_budget_spin)

        self.auto_next_check = QCheckBox("本节完成后自动继续下一节")
        form.addRow("", self.auto_next_check)

        self.can_do_edit = QPlainTextEdit()
        self.can_do_edit.setPlaceholderText("每行一条 can-do，例如：能点餐并询问价格")
        self.can_do_edit.setMaximumHeight(90)
        form.addRow("can-do 目标", self.can_do_edit)

        self.constraints_edit = QPlainTextEdit()
        self.constraints_edit.setPlaceholderText("可选的额外约束（场景、语法重点、禁用主题等）")
        self.constraints_edit.setMaximumHeight(90)
        form.addRow("额外约束", self.constraints_edit)

        self.syllabus_btn = QPushButton("载入教学纲领…")
        self.syllabus_btn.setToolTip(
            "读取教学纲领/课程大纲文件，自动填写主题、等级、单元数、课时与"
            "can-do 目标；配置了 AI 时再由模型精读一遍。"
        )
        self.syllabus_btn.clicked.connect(self._on_load_syllabus)
        form.addRow(self.syllabus_btn)

        self.generate_btn = QPushButton("生成大纲")
        self.generate_btn.setToolTip("调用当前 AI 配置生成课程大纲；失败会回灌校验错误重试一次")
        self.generate_btn.clicked.connect(self._on_generate)
        form.addRow(self.generate_btn)
        split.addWidget(form_box)

        # --- outline + lexicon -----------------------------------------
        right = QWidget()
        right_layout = QVBoxLayout(right)
        right_layout.setContentsMargins(0, 0, 0, 0)
        right_layout.setSpacing(6)
        tabs = QTabWidget()

        outline_tab = QWidget()
        outline_layout = QVBoxLayout(outline_tab)
        outline_layout.setContentsMargins(0, 0, 0, 0)
        self.table = QTableWidget(0, 10)
        self.table.setHorizontalHeaderLabels(
            [
                "#",
                "章节名",
                "等级",
                "单元",
                "课时/单元",
                "课型",
                "新词",
                "can-do",
                "复现",
                "状态",
            ]
        )
        self.table.setEditTriggers(QAbstractItemView.EditTrigger.NoEditTriggers)
        self.table.setSelectionBehavior(QAbstractItemView.SelectionBehavior.SelectRows)
        self.table.setSelectionMode(QAbstractItemView.SelectionMode.SingleSelection)
        self.table.verticalHeader().setVisible(False)
        self.table.setWordWrap(False)
        self.table.itemSelectionChanged.connect(self._update_section_buttons)
        header = self.table.horizontalHeader()
        header.setSectionResizeMode(0, QHeaderView.ResizeMode.ResizeToContents)
        header.setSectionResizeMode(1, QHeaderView.ResizeMode.Stretch)
        for col in range(2, 10):
            header.setSectionResizeMode(col, QHeaderView.ResizeMode.ResizeToContents)
        outline_layout.addWidget(self.table, 1)
        tabs.addTab(outline_tab, "课程大纲")

        lexicon_tab = QWidget()
        lexicon_layout = QVBoxLayout(lexicon_tab)
        lexicon_layout.setContentsMargins(0, 0, 0, 0)
        self.lex_table = QTableWidget(0, 5)
        self.lex_table.setHorizontalHeaderLabels(
            ["节", "词", "翻译", "词性", "ID"]
        )
        self.lex_table.setEditTriggers(QAbstractItemView.EditTrigger.NoEditTriggers)
        self.lex_table.setSelectionBehavior(
            QAbstractItemView.SelectionBehavior.SelectRows
        )
        self.lex_table.verticalHeader().setVisible(False)
        self.lex_table.setWordWrap(False)
        lex_header = self.lex_table.horizontalHeader()
        lex_header.setSectionResizeMode(0, QHeaderView.ResizeMode.ResizeToContents)
        lex_header.setSectionResizeMode(1, QHeaderView.ResizeMode.Stretch)
        lex_header.setSectionResizeMode(2, QHeaderView.ResizeMode.Stretch)
        lex_header.setSectionResizeMode(3, QHeaderView.ResizeMode.ResizeToContents)
        lex_header.setSectionResizeMode(4, QHeaderView.ResizeMode.ResizeToContents)
        lexicon_layout.addWidget(self.lex_table, 1)
        tabs.addTab(lexicon_tab, "全局词表")

        right_layout.addWidget(tabs, 1)

        self.summary = QLabel()
        self.summary.setWordWrap(True)
        right_layout.addWidget(self.summary)

        right_layout.addWidget(QLabel("大纲警告"))
        self.warnings_view = QPlainTextEdit()
        self.warnings_view.setReadOnly(True)
        self.warnings_view.setMaximumHeight(84)
        self.warnings_view.setPlaceholderText("无")
        right_layout.addWidget(self.warnings_view)
        split.addWidget(right)
        split.setStretchFactor(0, 0)
        split.setStretchFactor(1, 1)
        split.setSizes([360, 760])
        root.addWidget(split, 1)

        bottom = QHBoxLayout()
        self.status = QLabel("就绪")
        self.status.setWordWrap(True)
        bottom.addWidget(self.status, 1)
        self.gen_section_btn = QPushButton("生成本节")
        self.gen_section_btn.setToolTip("按当前选中章节生成草稿；只保存草稿，不导入")
        self.gen_section_btn.setEnabled(False)
        self.gen_section_btn.clicked.connect(self._on_generate_section)
        bottom.addWidget(self.gen_section_btn)
        self.view_draft_btn = QPushButton("查看草稿")
        self.view_draft_btn.setEnabled(False)
        self.view_draft_btn.clicked.connect(self._on_view_draft)
        bottom.addWidget(self.view_draft_btn)
        self.import_section_btn = QPushButton("导入本节")
        self.import_section_btn.setToolTip("作为新 section 导入当前课程；走校验/Undo，需再保存课程")
        self.import_section_btn.setEnabled(False)
        self.import_section_btn.clicked.connect(self._on_import_section)
        bottom.addWidget(self.import_section_btn)
        self.save_btn = QPushButton("保存规划")
        self.save_btn.setEnabled(False)
        self.save_btn.clicked.connect(self._on_save)
        bottom.addWidget(self.save_btn)
        self.close_btn = QPushButton("关闭")
        self.close_btn.clicked.connect(self.close)
        bottom.addWidget(self.close_btn)
        root.addLayout(bottom)

    # --- form <-> spec --------------------------------------------------

    def _apply_spec_to_form(self, spec: Any) -> None:
        self.lang_edit.setText(str(getattr(spec, "language", "") or ""))
        self.src_edit.setText(str(getattr(spec, "source_language", "") or ""))
        self.topic_edit.setText(str(getattr(spec, "topic", "") or ""))
        self.level_from_combo.setCurrentText(
            str(getattr(spec, "level_from", "A1") or "A1")
        )
        self.level_to_combo.setCurrentText(
            str(getattr(spec, "level_to", "A2") or "A2")
        )
        self.sections_spin.setValue(int(getattr(spec, "section_count", 6) or 6))
        self.lessons_spin.setValue(
            int(getattr(spec, "lessons_per_section", 9) or 9)
        )
        self.budget_spin.setValue(int(getattr(spec, "word_budget", 240) or 0))
        self.can_do_edit.setPlainText(
            "\n".join(str(x) for x in (getattr(spec, "can_do", None) or []))
        )
        self.constraints_edit.setPlainText(
            str(getattr(spec, "constraints", "") or "")
        )

    def _read_spec(self):
        can_do = [
            line.strip()
            for line in self.can_do_edit.toPlainText().splitlines()
            if line.strip()
        ]
        return self._service.build_spec(
            language=self.lang_edit.text().strip(),
            source_language=self.src_edit.text().strip(),
            topic=self.topic_edit.text().strip(),
            level_from=self.level_from_combo.currentText(),
            level_to=self.level_to_combo.currentText(),
            section_count=self.sections_spin.value(),
            lessons_per_section=self.lessons_spin.value(),
            word_budget=self.budget_spin.value(),
            can_do=can_do,
            constraints=self.constraints_edit.toPlainText().strip(),
        )

    # --- plan picker ----------------------------------------------------

    def _reload_summaries(self, *, select: str = "") -> None:
        self.plan_combo.blockSignals(True)
        self.plan_combo.clear()
        self.plan_combo.addItem("（未载入）", "")
        for row in self._service.summaries():
            title = str(row.get("title") or "未命名课程")
            updated = str(row.get("updated_at") or "")[:10]
            label = (
                f"{title}（{row.get('section_count', 0)} 节 / "
                f"{row.get('word_count', 0)} 词 · {updated}）"
            )
            self.plan_combo.addItem(label, str(row.get("plan_id") or ""))
            index = self.plan_combo.count() - 1
            self.plan_combo.setItemData(
                index,
                str(row.get("course_dir") or ""),
                Qt.ItemDataRole.ToolTipRole,
            )
        if select:
            position = self.plan_combo.findData(select)
            if position >= 0:
                self.plan_combo.setCurrentIndex(position)
        self.plan_combo.blockSignals(False)

    def _on_load_plan(self) -> None:
        plan_id = str(self.plan_combo.currentData() or "")
        if not plan_id:
            QMessageBox.information(self, "载入规划", "请先选择一个已保存的规划。")
            return
        plan = self._service.load(plan_id)
        if plan is None:
            QMessageBox.warning(self, "载入规划", "这个规划文件无法读取。")
            return
        self._apply_spec_to_form(plan.spec)
        self._set_plan(plan)
        self.status.setText(f"已载入：{plan.title}")

    def _on_delete_plan(self) -> None:
        plan_id = str(self.plan_combo.currentData() or "")
        if not plan_id:
            QMessageBox.information(self, "删除规划", "请先选择一个已保存的规划。")
            return
        if not safe_question(
            self, "删除规划", "删除这个大纲文件？课程内容不受影响。"
        ):
            return
        if self._service.delete(plan_id):
            self._clear_plan()
            self._reload_summaries()
            self.status.setText("规划已删除。")
        else:
            QMessageBox.warning(self, "删除规划", "删除失败：文件可能已被移动或占用。")

    # --- syllabus ingestion ---------------------------------------------

    def _on_load_syllabus(self) -> None:
        """Read a teaching syllabus and fill the planning form from it."""
        if self._busy:
            return
        path, _ = QFileDialog.getOpenFileName(
            self,
            "选择教学纲领 / 课程大纲",
            "",
            "教学纲领 (*.md *.markdown *.txt *.pdf *.docx);;所有文件 (*)",
        )
        if not path:
            return
        config = self._config_fn()
        if config is not None and not getattr(config, "is_complete", False):
            # Incomplete endpoint: the heuristic still fills the form, the AI
            # refinement pass is skipped instead of failing the whole action.
            config = None
        self._had_error = False
        self._task_kind = "syllabus"
        self.status.setText("解析教学纲领中…")
        worker = AiRequestWorker(self._service.load_syllabus, path, config)
        worker.result_ready.connect(self._on_syllabus_ready)
        worker.error_occurred.connect(self._on_syllabus_error)
        worker.completed.connect(self._on_worker_completed)
        self._worker = worker
        self._set_busy(True)
        worker.start()

    def _on_syllabus_ready(self, payload: object) -> None:
        if not isinstance(payload, dict):
            self._had_error = True
            self.status.setText("教学纲领解析失败：返回格式异常。")
            return
        values = payload.get("values") or {}
        self.topic_edit.setText(str(values.get("topic") or ""))
        level_from = str(values.get("level_from") or "")
        level_to = str(values.get("level_to") or "")
        if level_from in PLAN_LEVELS:
            self.level_from_combo.setCurrentText(level_from)
        if level_to in PLAN_LEVELS:
            self.level_to_combo.setCurrentText(level_to)
        self.sections_spin.setValue(int(values.get("section_count") or 6))
        self.lessons_spin.setValue(int(values.get("lessons_per_section") or 9))
        self.budget_spin.setValue(int(values.get("word_budget") or 0))
        self.can_do_edit.setPlainText("
".join(values.get("can_do") or []))
        self.constraints_edit.setPlainText(str(values.get("constraints") or ""))
        summary = str(payload.get("summary") or "教学纲领已解析。")
        warnings = list(payload.get("warnings") or [])
        if warnings:
            summary += "；需确认：" + "；".join(warnings)
        self.status.setText(summary)
        self.status.setToolTip(summary)

    def _on_syllabus_error(self, message: str) -> None:
        self._had_error = True
        self.status.setText(f"教学纲领解析失败：{message}")
        if not self._closing:
            QMessageBox.warning(self, "载入教学纲领", message or "未知错误")

    # --- generation -----------------------------------------------------

    def _on_generate(self) -> None:
        if self._busy:
            return
        spec = self._read_spec()
        if not spec.topic.strip():
            QMessageBox.information(self, "生成大纲", "请先填写课程主题。")
            return
        if PLAN_LEVELS.index(spec.level_to) < PLAN_LEVELS.index(spec.level_from):
            QMessageBox.warning(self, "生成大纲", "结束等级不能低于起始等级。")
            return
        config = self._config_fn()
        if config is None or not getattr(config, "is_complete", False):
            QMessageBox.warning(
                self,
                "生成大纲",
                "请先在「设置 ▸ AI 配置」中填写 Base URL、API Key 与模型。",
            )
            return

        settings = self._settings_fn()
        timeout = float(getattr(settings, "ai_timeout", 120.0) or 120.0)
        temperature = float(getattr(settings, "ai_temperature", 0.4) or 0.4)
        temperature = max(0.1, min(0.6, temperature))

        self._chunks = 0
        self._usage_total = 0
        self._section_usage = 0
        self._gen_section_id = ""
        self._task_kind = "plan"
        self._had_error = False
        self.status.setText("生成大纲中…")
        worker = AiRequestWorker(
            self._service.generate,
            config,
            spec,
            course_dir=str(getattr(self._adapter, "course_dir", "") or ""),
            timeout=timeout,
            temperature=temperature,
            max_retries=1,
        )
        worker.result_ready.connect(self._on_plan_ready)
        worker.error_occurred.connect(self._on_plan_error)
        worker.chunk_ready.connect(self._on_chunk)
        worker.usage_ready.connect(self._on_usage)
        worker.completed.connect(self._on_worker_completed)
        self._worker = worker
        self._set_busy(True)
        worker.start()

    def _on_chunk(self, text: str) -> None:
        self._chunks += len(text or "")
        if self._had_error:
            return
        if self._task_kind == "section":
            self.status.setText(f"生成章节中… 已接收 {self._chunks} 字符")
        else:
            self.status.setText(f"生成大纲中… 已接收 {self._chunks} 字符")

    def _on_usage(self, usage: object) -> None:
        if not isinstance(usage, dict):
            return
        try:
            total = int(usage.get("total_tokens") or 0)
        except (TypeError, ValueError):
            total = 0
        if self._task_kind == "section":
            self._section_usage = total
        else:
            self._usage_total = total

    def _on_plan_ready(self, plan: object) -> None:
        sections = getattr(plan, "sections", None)
        if not isinstance(sections, list):
            self._had_error = True
            QMessageBox.warning(self, "生成大纲", "模型没有返回可用的章节列表。")
            return
        try:
            plan.course_dir = str(getattr(self._adapter, "course_dir", "") or "")
        except AttributeError:
            # A duck-typed plan without a writable course_dir is still usable;
            # the course binding is metadata, not part of the outline.
            logger.debug("course plan has no writable course_dir", exc_info=True)
        self._set_plan(plan)
        try:
            plan_id = self._service.save(plan)
        except OSError as exc:
            self.status.setText(f"大纲已生成，但保存失败：{exc}")
            return
        self._reload_summaries(select=plan_id)
        tokens = f" · {self._usage_total} tokens" if self._usage_total else ""
        self.status.setText(
            f"大纲已生成并保存：{len(sections)} 节 / "
            f"{int(getattr(plan, 'word_count', 0))} 词{tokens}"
        )

    def _on_plan_error(self, message: str) -> None:
        self._had_error = True
        self.status.setText(f"生成失败：{message}")
        if not self._closing:
            QMessageBox.warning(self, "生成大纲失败", message or "未知错误")

    def _on_section_error(self, message: str) -> None:
        self._had_error = True
        self.status.setText(f"生成章节失败：{message}")
        if not self._closing:
            QMessageBox.warning(self, "生成章节失败", message or "未知错误")

    def _on_worker_completed(self) -> None:
        task = self._task_kind
        self._worker = None
        self._set_busy(False)
        self._task_kind = ""
        if self._closing:
            return
        if (
            task == "section"
            and not self._had_error
            and self.auto_next_check.isChecked()
        ):
            if self._budget_ok():
                QTimer.singleShot(0, self._generate_next_pending)
            else:
                self.status.setText(
                    f"{self.status.text()} · 已达 token 预算，停止自动继续"
                )

    def _budget_ok(self) -> bool:
        plan = self._plan
        if plan is None:
            return True
        budget = int(getattr(plan, "token_budget", 0) or 0)
        if budget <= 0:
            return True
        return int(getattr(plan, "usage_total", 0) or 0) < budget

    def _generate_next_pending(self) -> None:
        """Auto-continue: pick the first section without a draft/import."""
        if self._busy or self._plan is None:
            return
        sections = list(getattr(self._plan, "sections", None) or [])
        for row, section in enumerate(sections):
            sid = str(getattr(section, "section_id", "") or "")
            if not sid:
                continue
            status = str(
                (getattr(self._plan, "progress", None) or {})
                .get(sid, {})
                .get("status", "")
            )
            if status == "imported":
                continue
            if self._service.load_draft(self._plan, sid) is not None:
                continue
            self.table.selectRow(row)
            self._on_generate_section()
            return
        self.status.setText("没有待生成章节：全部已有草稿或已导入。")

    # --- plan rendering -------------------------------------------------

    def _set_plan(self, plan: Any) -> None:
        self._plan = plan
        sections = list(getattr(plan, "sections", None) or [])
        progress = getattr(plan, "progress", None) or {}
        self.table.setRowCount(0)
        for index, section in enumerate(sections, start=1):
            sid = str(getattr(section, "section_id", "") or "")
            words = []
            try:
                words = list(plan.words_for(sid))
            except (AttributeError, TypeError):
                words = []
            entry = progress.get(sid) if isinstance(progress, dict) else None
            entry = entry if isinstance(entry, dict) else {}
            status = str(entry.get("status") or "")
            status_label = {
                "draft": "草稿",
                "imported": "已导入",
            }.get(status, "未生成")
            final_id = str(entry.get("final_section_id") or "")
            if status == "imported" and final_id and final_id != sid:
                status_label += f"（{final_id}）"
            values = [
                str(index),
                str(getattr(section, "name", "") or ""),
                str(getattr(section, "level", "") or ""),
                str(getattr(section, "unit_count", "") or ""),
                str(getattr(section, "lessons_per_unit", "") or ""),
                "、".join(getattr(section, "template_mix", None) or []),
                str(len(words)),
                "；".join(getattr(section, "can_do", None) or []),
                "、".join(getattr(section, "review_terms", None) or []),
                status_label,
            ]
            row = self.table.rowCount()
            self.table.insertRow(row)
            for col, value in enumerate(values):
                item = QTableWidgetItem(value)
                if col == 1:
                    tip = "\n".join(
                        part
                        for part in (
                            str(getattr(section, "description", "") or ""),
                            str(getattr(section, "brief", "") or ""),
                        )
                        if part
                    )
                    if tip:
                        item.setToolTip(tip)
                self.table.setItem(row, col, item)

        spec = getattr(plan, "spec", None)
        budget = int(getattr(plan, "token_budget", 0) or 0)
        usage = int(getattr(plan, "usage_total", 0) or 0)
        self.token_budget_spin.setValue(budget)
        usage_text = f"{usage}/{budget}" if budget > 0 else str(usage)
        self.summary.setText(
            f"{len(sections)} 节 · {int(getattr(plan, 'word_count', 0))} 词 · "
            f"{getattr(spec, 'level_from', '')} → {getattr(spec, 'level_to', '')} · "
            f"预算 {getattr(spec, 'word_budget', '')} · tokens {usage_text}"
        )
        warnings = [str(w) for w in (getattr(plan, "warnings", None) or [])]
        self.warnings_view.setPlainText(
            "\n".join(f"• {w}" for w in warnings) if warnings else "无"
        )
        self._fill_lexicon(plan, sections)
        self.save_btn.setEnabled(not self._busy)
        self._update_section_buttons()

    def _fill_lexicon(self, plan: Any, sections: list) -> None:
        names = {
            str(getattr(section, "section_id", "")): str(
                getattr(section, "name", "") or ""
            )
            for section in sections
        }
        words = list(getattr(plan, "lexicon", None) or [])
        self.lex_table.setRowCount(0)
        for word in words:
            sid = str(getattr(word, "section_id", "") or "")
            values = [
                names.get(sid, sid),
                str(getattr(word, "term", "") or ""),
                str(getattr(word, "translation", "") or ""),
                str(getattr(word, "pos", "") or ""),
                str(getattr(word, "id", "") or ""),
            ]
            row = self.lex_table.rowCount()
            self.lex_table.insertRow(row)
            for col, value in enumerate(values):
                self.lex_table.setItem(row, col, QTableWidgetItem(value))

    def _clear_plan(self) -> None:
        self._plan = None
        self.table.setRowCount(0)
        self.lex_table.setRowCount(0)
        self.summary.setText("")
        self.warnings_view.setPlainText("")
        self.save_btn.setEnabled(False)
        self._update_section_buttons()

    def _set_busy(self, busy: bool) -> None:
        self._busy = busy
        self.generate_btn.setEnabled(not busy)
        self.syllabus_btn.setEnabled(not busy)
        self.load_btn.setEnabled(not busy)
        self.delete_btn.setEnabled(not busy)
        self.plan_combo.setEnabled(not busy)
        self.save_btn.setEnabled(not busy and self._plan is not None)
        self._update_section_buttons()

    # --- per-section generation / import --------------------------------

    def _selected_section_id(self) -> str:
        row = self.table.currentRow()
        if row < 0 or self._plan is None:
            return ""
        sections = list(getattr(self._plan, "sections", None) or [])
        if row >= len(sections):
            return ""
        return str(getattr(sections[row], "section_id", "") or "")

    def _update_section_buttons(self) -> None:
        sid = self._selected_section_id()
        draft = (
            self._service.load_draft(self._plan, sid)
            if (sid and self._plan is not None)
            else None
        )
        self.gen_section_btn.setEnabled(
            bool(sid) and self._plan is not None and not self._busy
        )
        self.view_draft_btn.setEnabled(draft is not None and not self._busy)
        self.import_section_btn.setEnabled(
            draft is not None
            and self._import_fn is not None
            and not self._busy
        )

    def _select_section(self, section_id: str) -> None:
        sections = list(getattr(self._plan, "sections", None) or [])
        for row, section in enumerate(sections):
            if str(getattr(section, "section_id", "") or "") == section_id:
                self.table.selectRow(row)
                return

    def _on_generate_section(self) -> None:
        if self._busy or self._plan is None:
            return
        sid = self._selected_section_id()
        if not sid:
            QMessageBox.information(self, "生成本节", "请先在大纲里选中一个章节。")
            return
        config = self._config_fn()
        if config is None or not getattr(config, "is_complete", False):
            QMessageBox.warning(
                self,
                "生成本节",
                "请先在「设置 ▸ AI 配置」中填写 Base URL、API Key 与模型。",
            )
            return

        plan = self._plan
        plan.token_budget = int(self.token_budget_spin.value())
        if not self._budget_ok():
            QMessageBox.information(
                self,
                "生成本节",
                "当前规划已达到 token 预算。调大预算或把它设为 0（不限）后继续。",
            )
            return

        settings = self._settings_fn()
        timeout = float(getattr(settings, "ai_timeout", 120.0) or 120.0)
        temperature = float(getattr(settings, "ai_temperature", 0.4) or 0.4)
        temperature = max(0.1, min(0.6, temperature))
        mode = str(self.mode_combo.currentData() or "fast")

        self._chunks = 0
        self._section_usage = 0
        self._gen_section_id = sid
        self._task_kind = "section"
        self._had_error = False
        self.status.setText(f"生成 {sid} 中…")

        worker = AiRequestWorker(
            self._service.generate_section,
            config,
            plan,
            sid,
            mode=mode,
            timeout=timeout,
            temperature=temperature,
            max_retries=1,
        )
        worker.result_ready.connect(self._on_section_ready)
        worker.error_occurred.connect(self._on_section_error)
        worker.chunk_ready.connect(self._on_chunk)
        worker.usage_ready.connect(self._on_usage)
        worker.completed.connect(self._on_worker_completed)
        self._worker = worker
        self._set_busy(True)
        worker.start()

    def _on_section_ready(self, draft: object) -> None:
        sid = self._gen_section_id
        if self._plan is None or not sid or not isinstance(draft, dict):
            self._had_error = True
            QMessageBox.warning(self, "生成本节", "模型没有返回可用的 section 草稿。")
            return
        plan = self._plan
        self._service.mark_progress(
            plan, sid, status="draft", usage=self._section_usage
        )
        try:
            plan_id = self._service.save_draft(plan, sid, draft)
        except OSError as exc:
            self._had_error = True
            self.status.setText(f"草稿已生成，但保存失败：{exc}")
            return
        self._reload_summaries(select=plan_id)
        self._set_plan(plan)
        self._select_section(sid)
        self._update_section_buttons()
        tokens = f"，{self._section_usage} tokens" if self._section_usage else ""
        self.status.setText(f"{sid} 草稿已保存{tokens}；可预览或导入。")

    def _on_view_draft(self) -> None:
        sid = self._selected_section_id()
        if self._plan is None or not sid:
            return
        draft = self._service.load_draft(self._plan, sid)
        if draft is None:
            QMessageBox.information(self, "查看草稿", "这一节还没有草稿。")
            return
        dialog = QDialog(self)
        dialog.setWindowTitle(f"草稿预览 · {sid}")
        dialog.resize(900, 640)
        layout = QVBoxLayout(dialog)
        view = QPlainTextEdit()
        view.setReadOnly(True)
        view.setPlainText(json.dumps(draft, ensure_ascii=False, indent=2))
        layout.addWidget(view, 1)
        close = QPushButton("关闭")
        close.clicked.connect(dialog.accept)
        row = QHBoxLayout()
        row.addStretch()
        row.addWidget(close)
        layout.addLayout(row)
        dialog.exec()

    def _on_import_section(self) -> None:
        sid = self._selected_section_id()
        if self._plan is None or not sid or self._import_fn is None:
            return
        draft = self._service.load_draft(self._plan, sid)
        if draft is None:
            QMessageBox.information(self, "导入本节", "这一节还没有草稿。")
            return
        if not safe_question(
            self,
            "导入本节",
            f"把 {sid} 作为新 section 导入当前课程？\n"
            "会走现有校验与合并预览，可 Ctrl+Z 撤销；导入后仍需保存课程。",
        ):
            return
        try:
            outcome, final_id, message = self._import_fn(draft)
        except (RuntimeError, ValueError, TypeError) as exc:
            QMessageBox.warning(self, "导入本节", f"导入失败：{exc}")
            return
        if outcome in ("imported", "merged", "replaced"):
            self._service.mark_progress(
                self._plan,
                sid,
                status="imported",
                final_section_id=final_id,
            )
            try:
                self._service.save(self._plan)
            except OSError as exc:
                self.status.setText(f"已导入，但规划保存失败：{exc}")
                return
            self._set_plan(self._plan)
            self._select_section(sid)
            self.status.setText(
                f"{sid} 已导入为 {final_id or sid}，记得保存课程（Ctrl+S）。"
            )
        else:
            QMessageBox.warning(
                self, "导入本节", message or f"导入未完成（{outcome}）。"
            )

    # --- save / close ---------------------------------------------------

    def _on_save(self) -> None:
        if self._plan is None:
            QMessageBox.information(self, "保存规划", "还没有可保存的大纲。")
            return
        try:
            plan_id = self._service.save(self._plan)
        except OSError as exc:
            QMessageBox.warning(self, "保存规划", f"保存失败：{exc}")
            return
        self._reload_summaries(select=plan_id)
        self.status.setText(f"规划已保存：{plan_id}")

    def closeEvent(self, event) -> None:
        self._closing = True
        worker = self._worker
        if worker is not None:
            worker.cancel()
            worker.wait(2000)
        super().closeEvent(event)
