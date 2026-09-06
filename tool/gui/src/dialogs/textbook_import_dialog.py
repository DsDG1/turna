"""Single-dialog textbook import: view layer.

The business logic lives in ``TextbookImportController``; this module builds the
6-step UI and wires user events to the controller. The dialog itself does NOT
write to disk or push undo commands — it emits ``sections_ready`` and the
MainWindow (``app.py``) runs ``_import_section_dict`` for each section.
"""
from __future__ import annotations

from pathlib import Path
from typing import Any

from PySide6.QtCore import QSettings, Qt, Signal
from PySide6.QtGui import QDragEnterEvent, QDropEvent
from PySide6.QtWidgets import (
    QButtonGroup,
    QComboBox,
    QDialog,
    QFileDialog,
    QGroupBox,
    QHBoxLayout,
    QLabel,
    QListWidget,
    QListWidgetItem,
    QMessageBox,
    QProgressBar,
    QPushButton,
    QRadioButton,
    QSpinBox,
    QSplitter,
    QStackedWidget,
    QTextEdit,
    QVBoxLayout,
    QWidget,
)

from src.dialogs.textbook_import.constants import (
    _PAGE_FOR_STEP,
    _STEPPER_STAGES,
    _STEP_TITLES,
    _STRATEGY_OPTIONS,
    STEP_CHAPTERS,
    STEP_EXTRACT,
    STEP_IMPORT,
    STEP_PARSE,
    STEP_PICK,
    STEP_REVIEW,
)
from src.dialogs.textbook_import.pages import (
    build_import_page,
    build_knowledge_page,
    build_source_page,
    build_ui,
)
from src.backend.import_step_result import ImportStepResult
from src.backend.import_strategy import ImportStrategy
from src.backend.textbook_project import TextbookProject
from src.backend.textbook_project_store import TextbookProjectStore
from src.dialogs.ai_fix_dialog import AiFixDialog
from src.dialogs.textbook_import_controller import TextbookImportController
from src.infrastructure.telemetry import telemetry
from src.theme import ai_color, current_palette
from src.widgets.bulk_import_preview_panel import BulkImportPreviewPanel
from src.widgets.resource_review_table import ResourceReviewTable, ResourceRow

class TextbookImportDialog(QDialog):
    """Single-window textbook import timeline. Emits ``sections_ready``."""

    sections_ready = Signal(list, str)  # (list[dict], strategy) - one section per kept chapter — one section per kept chapter
    # Ask the host (WorkshopWindow) to jump to the grounded design stage.
    design_requested = Signal()
    # Status signals for the workshop's unified bottom bar (Phase B). The
    # built-in bottom bar can be hidden via ``set_bottom_bar_visible``.
    busy_changed = Signal(bool, str)  # (busy, stage text)
    stage_text_changed = Signal(str)  # progress detail, e.g. 第 x/y 章
    usage_changed = Signal(str)  # formatted usage line
    autosave_saved = Signal(str)  # formatted autosave timestamp line

    def __init__(
        self,
        adapter,
        parent: QWidget | None = None,
        *,
        project: TextbookProject | None = None,
        store: TextbookProjectStore | None = None,
        embedded: bool = False,
        worker_factory=None,
    ) -> None:
        super().__init__(parent)
        self.adapter = adapter
        self._parent_window = parent
        self._project = project
        self._store = store or TextbookProjectStore()
        # Embedded mode (P2-2): hosted inside WorkshopWindow as a plain
        # widget — never close/hide ourselves, signals still fire.
        self._embedded = embedded
        self.setWindowTitle("导入教材")
        self.resize(720, 600)
        self.setAcceptDrops(True)

        # P4-2 auto-cascade (standard -> vocab_only) is on by default; the
        # ``textbook/auto_cascade`` QSettings key can turn it off.
        auto_cascade = QSettings("Turna", "CourseEditor").value(
            "textbook/auto_cascade", True, type=bool
        )
        self._controller = TextbookImportController(
            ai_config_fn=self._ai_config,
            worker_factory=worker_factory,
            on_step_changed=self._on_step_changed,
            on_extract_log=self._on_extract_log,
            on_extract_progress=self._on_extract_progress,
            on_sections_ready=self._on_controller_sections_ready,
            on_autosave=self._on_autosave,
            on_quality_report_changed=self._on_quality_report_changed,
            on_usage_update=self._on_usage_update,
            language=project.language if project else "Turkish",
            source_language=project.source_language if project else "Chinese",
            project_name=project.name if project else "",
            auto_cascade=auto_cascade,
        )

        self._build_ui()
        self._apply_preset()  # push the default textbook-type preset to the controller
        self._selected_chapter_index: int | None = None
        if project is not None:
            self._picked_label.setText(
                Path(project.source_path).name if project.source_path else "未选择"
            )
            self._controller.apply_project(project)
            # A project freshly created in the library has just picked its
            # source file — load it immediately instead of asking again (P0-3).
            if not project.chapters and project.source_path:
                source = Path(project.source_path)
                if source.exists():
                    self._load_file(source)
        else:
            self._go_to_step(STEP_PICK)

    # ------------------------------------------------------------------ UI

    def _build_ui(self) -> None:
        build_ui(self)
    def _build_source_page(self) -> QWidget:
        return build_source_page(self)
    def _build_knowledge_page(self) -> QWidget:
        return build_knowledge_page(self)
    def _build_import_page(self) -> QWidget:
        return build_import_page(self)
    # ------------------------------------------------------------- step nav

    def _go_to_step(self, step: int) -> None:
        page = _PAGE_FOR_STEP.get(step, 0)
        self._stack.setCurrentIndex(page)
        secondary = current_palette()["text_secondary"]
        for i, s in enumerate(_STEPPER_STAGES):
            lbl = self._stepper_labels[s]
            if i < page:
                lbl.setText("✓ " + _STEP_TITLES[s])
                lbl.setStyleSheet(f"color: {secondary};")
            elif i == page:
                lbl.setText("▸ " + _STEP_TITLES[s])
                lbl.setStyleSheet(f"color: {ai_color('ai_accent')}; font-weight: 600;")
            else:
                lbl.setText("○ " + _STEP_TITLES[s])
                lbl.setStyleSheet(f"color: {secondary};")

    def set_stepper_visible(self, visible: bool) -> None:
        """Show/hide the built-in stage stepper (hidden inside WorkshopWindow,
        which provides its own outer stage navigation)."""
        self._stepper_widget.setVisible(visible)

    def set_bottom_bar_visible(self, visible: bool) -> None:
        """Show/hide the built-in bottom bar (hidden inside WorkshopWindow,
        which renders the same state in its unified bottom bar via the
        ``busy_changed``/``stage_text_changed``/``usage_changed``/
        ``autosave_saved`` signals)."""
        self._bottom_bar.setVisible(visible)

    def _set_busy(self, busy: bool, stage: str = "") -> None:
        self._progress.setVisible(busy)
        self._stage_label.setText(stage)
        self._stage_label.setVisible(bool(stage))
        self.busy_changed.emit(busy, stage)

    # ------------------------------------------------------------- controller callbacks

    def _on_step_changed(self, step: int, result: ImportStepResult | None) -> None:
        self._go_to_step(step)
        if result is None:
            return
        self._set_busy(False)
        if result.outcome == "error":
            self._show_error_with_recovery(step, result)

        if step == STEP_CHAPTERS:
            self._show_parse_preview()
            self._populate_chapters()
        elif step == STEP_EXTRACT and result.outcome == "success":
            self._set_busy(True, "提取中…")
        elif step == STEP_REVIEW:
            self._populate_review()
        elif step == STEP_IMPORT and result.outcome == "success":
            if not self._embedded:
                self.close()

    def _show_parse_preview(self) -> None:
        has_text = bool(self._controller.markdown)
        self._parse_preview.setPlainText(self._controller.markdown[:2000])
        self._parse_preview.setVisible(has_text)
        self._preview_caption.setVisible(has_text)
        self._parse_error_label.setVisible(False)

    def _show_error_for_step(self, step: int, result: ImportStepResult) -> None:
        if step in (STEP_PICK, STEP_PARSE):
            # File load/parse failures surface inline on the pick page.
            self._parse_error_label.setText(result.message)
            self._parse_error_label.setVisible(True)
            self._parse_preview.setPlainText("")
        else:
            QMessageBox.warning(self, "导入教材", result.message)

    def _show_error_with_recovery(self, step: int, result: ImportStepResult) -> None:
        """Show an error, rendering ``recovery_options`` as action buttons (P0-4)."""
        options = [o for o in (result.recovery_options or []) if o]
        if not result.recoverable or not options:
            self._show_error_for_step(step, result)
            return
        box = QMessageBox(self)
        box.setIcon(QMessageBox.Icon.Warning)
        box.setWindowTitle("导入教材")
        box.setText(result.message)
        option_buttons = [
            (opt, box.addButton(opt, QMessageBox.ButtonRole.ActionRole))
            for opt in options
        ]
        box.addButton("关闭", QMessageBox.ButtonRole.RejectRole)
        box.exec()
        clicked = box.clickedButton()
        for opt, btn in option_buttons:
            if clicked is btn:
                self._run_recovery_action(opt)
                return

    def _run_recovery_action(self, option: str) -> None:
        """Map a recovery-option label from the controller to a view action."""
        if option == "重新选择":
            self._go_to_step(STEP_PICK)
            self._on_pick_file()
        elif option == "打开设置":
            window = self._parent_window
            if window is not None and hasattr(window, "_on_settings"):
                window._on_settings()
        elif option == "返回勾选":
            self._go_to_step(STEP_CHAPTERS)
        elif option == "返回审校":
            self._go_to_step(STEP_REVIEW)

    def _on_extract_log(self, message: str) -> None:
        self._extract_log.insertPlainText(message)
        self._extract_log.ensureCursorVisible()
        self._update_extract_status_light(message)

    def _update_extract_status_light(self, message: str) -> None:
        """U0-6: surface slide-window / cascade / reextract in a status lamp."""
        if not hasattr(self, "_extract_status_label"):
            return
        text = message or ""
        low = text.lower()
        if "自动降级" in text or "vocab_only" in low and "降级" in text:
            self._extract_status_label.setText("抽取状态：已自动降级 → 仅词汇")
            self._extract_status_label.setStyleSheet(
                "color: #d97706; font-size: 11px; font-weight: 600;"
            )
        elif "滑窗" in text or "窗" in text and ("/" in text or "window" in low):
            # Keep last window-ish line visible.
            snippet = text.strip().splitlines()[-1][:120]
            self._extract_status_label.setText(f"抽取状态：{snippet}")
            self._extract_status_label.setStyleSheet(
                "color: #0f766e; font-size: 11px; font-weight: 600;"
            )
        elif "按质量重抽完成" in text or "重抽完成" in text:
            self._extract_status_label.setText("抽取状态：按质量重抽完成 · 已重算质量分")
            self._extract_status_label.setStyleSheet(
                "color: #16a34a; font-size: 11px; font-weight: 600;"
            )
        elif "按质量重抽失败" in text or "重抽失败" in text:
            self._extract_status_label.setText("抽取状态：按质量重抽失败（已保留原结果）")
            self._extract_status_label.setStyleSheet(
                "color: #dc2626; font-size: 11px; font-weight: 600;"
            )
        elif "完成" in text and ("词" in text or "表达" in text):
            self._extract_status_label.setText("抽取状态：本章完成")
            self._extract_status_label.setStyleSheet(
                "color: #16a34a; font-size: 11px; font-weight: 600;"
            )
        elif "失败" in text:
            self._extract_status_label.setText("抽取状态：失败 — 见日志")
            self._extract_status_label.setStyleSheet(
                "color: #dc2626; font-size: 11px; font-weight: 600;"
            )

    def _on_autosave(self, project: TextbookProject) -> None:
        """Persist project snapshot, preserving original identity and imports."""
        if self._project is not None:
            self._project.merge_from(project)
            self._store.save_project(self._project)
        else:
            self._store.save_project(project)
            self._project = project
        text = f"已自动保存于 {project.updated_at[:19].replace('T', ' ')}"
        self._autosave_label.setText(text)
        self.autosave_saved.emit(text)

    def _on_extract_progress(self, progress: dict[str, Any]) -> None:
        current = progress.get("current", 0)
        total = progress.get("total", 0)
        remaining = progress.get("remaining_seconds")
        text = f"第 {current}/{total} 章"
        if remaining is not None:
            text += f"，预计剩余 {remaining} 秒"
        self._stage_label.setText(text)
        self.stage_text_changed.emit(text)
        if hasattr(self, "_extract_status_label"):
            self._extract_status_label.setText(f"抽取状态：{text}")
            self._extract_status_label.setStyleSheet(
                "color: #0f766e; font-size: 11px; font-weight: 600;"
            )

    def _on_quality_report_changed(self, report) -> None:
        self._refresh_quality_summary(report)

    def _apply_preset(self, *_args) -> None:
        """Push the selected textbook-type preset onto the controller."""
        from src.backend.textbook_presets import preset_for

        name = self._preset_combo.currentData() if hasattr(self, "_preset_combo") else None
        self._controller.preset = preset_for(name) if name else None

    def _on_usage_update(self, chapter_index: int, chapter_usage: dict, project_usage: dict) -> None:
        """Render the running project token/cost estimate (bookplan2 Phase 5)."""
        from src.backend.ai_usage import format_usage_line

        config = self._ai_config()
        model = getattr(config, "model", "")
        text = f"项目用量：{format_usage_line(project_usage, model)}"
        self._usage_label.setText(text)
        self.usage_changed.emit(text)

    # ------------------------------------------------------------- ① pick

    def dragEnterEvent(self, event: QDragEnterEvent) -> None:
        if event.mimeData().hasUrls():
            event.acceptProposedAction()
        else:
            super().dragEnterEvent(event)

    def dropEvent(self, event: QDropEvent) -> None:
        urls = event.mimeData().urls()
        paths = [Path(u.toLocalFile()) for u in urls if u.isLocalFile()]
        if paths:
            self._load_file(paths[0])
        event.acceptProposedAction()

    def _on_pick_file(self) -> None:
        path, _ = QFileDialog.getOpenFileName(
            self, "选择教材", "", "教材 (*.md *.txt *.pdf);;所有文件 (*)"
        )
        if path:
            self._load_file(Path(path))

    def _load_file(self, path: Path) -> None:
        self._picked_label.setText(path.name)
        self._parse_error_label.setVisible(False)
        self._pick_btn.setEnabled(False)
        self._load_busy_label.setVisible(True)

        result = self._controller.load_file_async(
            path,
            on_done=lambda r: self._on_load_done(path, r),
        )
        # Validation failures return immediately; restore busy UI here.
        if result is not None:
            self._on_load_done(path, result)

    def _on_load_done(self, path: Path, result: ImportStepResult) -> None:
        self._pick_btn.setEnabled(True)
        self._load_busy_label.setVisible(False)
        if result.outcome == "error":
            # Load/parse errors are returned, not emitted — surface them here.
            self._show_error_with_recovery(STEP_PICK, result)

    # ------------------------------------------------------------- ③ chapters

    def _populate_chapters(self) -> None:
        chapters = [cr.chapter for cr in self._controller.chapters]
        self._chapter_list.clear()
        if not chapters:
            self._empty_chapters_label.setVisible(True)
            return
        self._empty_chapters_label.setVisible(False)
        for idx, cr in enumerate(self._controller.chapters, start=1):
            ch = cr.chapter
            item = QListWidgetItem(f"{idx}. {ch.title}  ({len(ch.markdown)} 字)")
            item.setCheckState(Qt.CheckState.Checked if cr.keep else Qt.CheckState.Unchecked)
            self._chapter_list.addItem(item)

    def _select_all_chapters(self) -> None:
        self._set_all_chapters(True)

    def _on_concurrency_changed(self, value: int) -> None:
        if hasattr(self, "_controller"):
            self._controller.max_concurrent = int(value)

    def _set_all_chapters(self, checked: bool) -> None:
        state = Qt.CheckState.Checked if checked else Qt.CheckState.Unchecked
        for i in range(self._chapter_list.count()):
            self._chapter_list.item(i).setCheckState(state)
        self._sync_chapter_keep_flags()

    def _invert_chapters(self) -> None:
        for i in range(self._chapter_list.count()):
            it = self._chapter_list.item(i)
            it.setCheckState(
                Qt.CheckState.Checked
                if it.checkState() == Qt.CheckState.Unchecked
                else Qt.CheckState.Unchecked
            )
        self._sync_chapter_keep_flags()

    def _sync_chapter_keep_flags(self) -> None:
        for i in range(self._chapter_list.count()):
            it = self._chapter_list.item(i)
            self._controller.set_chapter_kept(i, it.checkState() == Qt.CheckState.Checked)

    # ------------------------------------------------------------ ④ extract

    def _start_extraction(self) -> None:
        self._sync_chapter_keep_flags()
        self._extract_log.clear()
        result = self._controller.start_extraction()
        if result.outcome == "error":
            self._show_error_with_recovery(STEP_CHAPTERS, result)

    def _ai_config(self):
        from src.application.ai_runtime import runtime_from_host

        return runtime_from_host(self.parentWidget() or self).config()

    # ------------------------------------------------------------- ⑤ review

    def _populate_review(self) -> None:
        report = self._controller.compute_quality_report(adapter=self.adapter)
        rows: list[ResourceRow] = []
        for ci, cr in enumerate(self._controller.chapters):
            if not cr.keep:
                continue
            chapter_quality = report.chapter_quality(ci)
            issues = chapter_quality.issues if chapter_quality else []
            if cr.knowledge is not None:
                for rtype, entries in (
                    ("word", cr.knowledge.words),
                    ("expression", cr.knowledge.expressions),
                    ("grammarPoint", cr.knowledge.grammarPoints),
                ):
                    for i, entry in enumerate(entries):
                        row_issues = [
                            issue
                            for issue in issues
                            if issue.resource_type == rtype and issue.resource_index == i
                        ]
                        rows.append(
                            ResourceRow(
                                chapter_index=ci,
                                resource_type=rtype,
                                entry=entry,
                                issues=row_issues,
                            )
                        )
        self._review_table.set_rows(rows)
        self._populate_chapter_quality_list(report)
        self._refresh_quality_summary(report)

    def _populate_chapter_quality_list(self, report) -> None:
        self._chapter_quality_list.clear()
        for ci, cr in enumerate(self._controller.chapters):
            if not cr.keep:
                continue
            badge = report.badge_for_chapter(ci)
            icon = {"error": "🔴", "warning": "🟡", "ok": "🟢"}.get(badge, "⚪")
            item = QListWidgetItem(f"{icon} {cr.chapter.title}")
            item.setData(Qt.ItemDataRole.UserRole, ci)
            self._chapter_quality_list.addItem(item)

    def _on_chapter_quality_selected(self, row: int) -> None:
        item = self._chapter_quality_list.item(row)
        if item is None:
            self._selected_chapter_index = None
            self._review_table.set_chapter_filter(None)
            return
        ci = item.data(Qt.ItemDataRole.UserRole)
        self._selected_chapter_index = ci
        self._review_table.set_chapter_filter(ci)
        self._update_recovery_buttons(ci)

    def _update_recovery_buttons(self, ci: int) -> None:
        cr = self._controller.chapters[ci]
        failed = bool(cr.error)
        for btn in (self._retry_btn, self._retry_vocab_btn, self._skip_btn):
            btn.setVisible(failed)
        # 「按质量重抽」is offered on chapters that extracted successfully but
        # still carry quality issues (P4-4).
        report = self._controller.quality_report
        chapter_quality = report.chapter_quality(ci) if report else None
        has_issues = bool(chapter_quality and chapter_quality.issues)
        self._reextract_btn.setVisible(cr.knowledge is not None and has_issues)
        if failed:
            self._chapter_recovery_label.setText(
                f"第 {ci + 1} 章抽取失败：{cr.error}"
            )
        else:
            self._chapter_recovery_label.setText("")

    def _on_retry_chapter(self, mode: str) -> None:
        if self._selected_chapter_index is None:
            return
        telemetry.record_event(
            "textbook.extract.chapter.retry"
            if mode == "standard"
            else "textbook.extract.chapter.vocab_only",
            payload={"chapter_index": self._selected_chapter_index, "mode": mode},
        )
        result = self._controller.retry_chapter(self._selected_chapter_index, mode=mode)
        if result.outcome == "error":
            QMessageBox.warning(self, "重试抽取", result.message)
        else:
            self._set_busy(True, "重试中…")

    def _on_retry_standard_clicked(self) -> None:
        self._on_retry_chapter("standard")

    def _on_retry_vocab_clicked(self) -> None:
        self._on_retry_chapter("vocab_only")

    def _on_skip_chapter(self) -> None:
        if self._selected_chapter_index is None:
            return
        telemetry.record_event(
            "textbook.extract.chapter.skip",
            payload={"chapter_index": self._selected_chapter_index},
        )
        self._controller.skip_chapter(self._selected_chapter_index)
        self._populate_review()

    def _on_reextract_chapter(self) -> None:
        if self._selected_chapter_index is None:
            return
        result = self._controller.reextract_chapter_targeted(
            self._selected_chapter_index
        )
        if result.outcome == "error":
            QMessageBox.warning(self, "按质量重抽", result.message)
        else:
            self._set_busy(True, "按质量重抽中…")

    def _on_review_rows_changed(self) -> None:
        telemetry.record_event("textbook.review.edit")

    def _on_ai_fix_requested(self, rows: list[ResourceRow]) -> None:
        telemetry.record_event(
            "textbook.review.ai_fix",
            payload={"row_count": len(rows)},
        )
        self._run_ai_fix_for_rows(rows)

    def _run_ai_fix_for_rows(self, rows: list[ResourceRow]) -> None:
        if not rows:
            return
        words = [r.entry for r in rows if r.resource_type == "word"]
        expressions = [r.entry for r in rows if r.resource_type == "expression"]
        grammar_points = [r.entry for r in rows if r.resource_type == "grammarPoint"]
        temp_section = {
            "id": "temp-fix-section",
            "name": "审校临时节点",
            "description": "",
            "level": "A1",
            "prerequisiteSectionIds": [],
            "units": [],
            "words": words,
            "expressions": expressions,
            "grammarPoints": grammar_points,
        }
        problems: list[dict[str, Any]] = []
        for r in rows:
            for issue in r.issues:
                path = r.resource_type
                if issue.resource_index is not None:
                    path += f"[{issue.resource_index}]"
                if issue.field:
                    path += f".{issue.field}"
                problems.append(
                    {
                        "level": issue.level,
                        "message": issue.message,
                        "path": path,
                    }
                )
        course_context = {
            "node_kind": "section",
            "language": self._controller._language,
            "source_language": self._controller._source_language,
            "existing_resource_ids": {
                "vocab": [w.get("id") for w in getattr(self.adapter, "vocab", []) if w.get("id")],
                "expressions": [
                    e.get("id") for e in getattr(self.adapter, "expressions", []) if e.get("id")
                ],
                "grammar_points": [
                    g.get("id") for g in getattr(self.adapter, "grammar_points", []) if g.get("id")
                ],
            },
        }
        config = self._ai_config()
        if not getattr(config, "is_complete", False):
            QMessageBox.warning(self, "AI 修复", "请先在设置中配置 AI API。")
            return
        dlg = AiFixDialog(
            problems,
            temp_section,
            course_context,
            config,
            parent=self,
        )
        if dlg.exec() != QDialog.DialogCode.Accepted:
            return
        corrected = dlg.corrected_node()
        if corrected is None:
            return
        # Map corrected resources back into the rows that were sent.
        corrected_words = corrected.get("words", [])
        corrected_exprs = corrected.get("expressions", [])
        corrected_grammar = corrected.get("grammarPoints", [])
        for rtype, corrected_list in (
            ("word", corrected_words),
            ("expression", corrected_exprs),
            ("grammarPoint", corrected_grammar),
        ):
            for r, entry in zip(
                [r for r in rows if r.resource_type == rtype], corrected_list
            ):
                r.entry.clear()
                r.entry.update(entry)
        self._controller.apply_review_rows(self._review_table.kept_rows())
        self._populate_review()

    def _refresh_quality_summary(self, report) -> None:
        overall = report.overall
        if not overall:
            self._quality_summary_label.setText("")
            return
        errors = overall.get("error_count", 0)
        warnings = overall.get("warning_count", 0)
        parts = []
        for key in ("coverage", "duplicate_rate", "consistency", "lang_check"):
            if key in overall:
                parts.append(f"{key}={overall[key]:.2f}")
        self._quality_summary_label.setText(
            f"质量概览：{errors} 个错误，{warnings} 个警告 | {' | '.join(parts)}"
        )

    # ------------------------------------------------------------ ⑥ import

    def _current_strategy(self) -> str:
        """Return the currently-selected import-strategy value."""
        for value, radio in self._strategy_buttons.items():
            if radio.isChecked():
                return value
        return ImportStrategy.MERGE.value

    def _on_strategy_changed(self) -> None:
        telemetry.record_event(
            "textbook.import.strategy_changed",
            payload={"strategy": self._current_strategy()},
        )
        self._refresh_preview()

    def _on_strategy_id_toggled(self, _id: int, checked: bool) -> None:
        if checked:
            self._on_strategy_changed()

    def _on_back_to_review_clicked(self) -> None:
        self._go_to_step(STEP_REVIEW)

    def _on_design_btn_clicked(self) -> None:
        self.design_requested.emit()

    def _goto_import_preview(self) -> None:
        """Apply review edits, then show the import/preview page."""
        self._controller.apply_review_rows(self._review_table.kept_rows())
        self._go_to_step(STEP_IMPORT)
        self._refresh_preview()

    def _refresh_preview(self) -> None:
        """Recompute the bulk-import preview for the current strategy."""
        previews = self._controller.preview_import(self.adapter, self._current_strategy())
        self._preview_panel.set_previews(previews)

    def _on_controller_sections_ready(self, sections: list) -> None:
        """Forward built sections to MainWindow with the chosen strategy."""
        self.sections_ready.emit(sections, self._current_strategy())

    def _on_import(self) -> None:
        self._controller.apply_review_rows(self._review_table.kept_rows())
        # Dedup intra-project + align course-collision ids before building so
        # the emitted sections carry unified ids (bookplan2 Phase 4).
        self._controller.merge_knowledge(self.adapter)
        result = self._controller.build_sections()
        if result.outcome == "error":
            self._show_error_with_recovery(STEP_IMPORT, result)

    # ------------------------------------------------------------- cancel

    def _on_cancel(self) -> None:
        if self._controller.is_busy:
            self._controller.cancel()
            self._set_busy(True, "正在取消…")
            return
        if not self._embedded:
            self.close()
