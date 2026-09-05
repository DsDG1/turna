"""Review stage panel for the workshop (merge overhaul Phase C + P1 fluency).

Read-side companion of the design stage: it renders the current draft from
the ``DesignPanel``'s JSON editor (the single source of truth, B1) through
the structured ``ResultPreviewWidget``, and offers the shared review
actions — lesson preview (试做), diff against the existing course section,
AI fix (with confirm-diff), content-quality chips, and import.

aiEnhance perception U0: generation summary card + clickable quality dims.
"""
from __future__ import annotations

import logging
logger = logging.getLogger(__name__)


from typing import Any

from PySide6.QtWidgets import (
    QDialog,
    QDialogButtonBox,
    QHBoxLayout,
    QLabel,
    QMessageBox,
    QPlainTextEdit,
    QPushButton,
    QTextBrowser,
    QVBoxLayout,
    QWidget,
)

from src.backend.ai_presets_ui import EDIT_PRESET_LABELS, EDIT_PRESETS
from src.backend.ai_summary import build_generation_summary, format_summary_card
from src.backend.content_quality import (
    build_quality_fix_hint,
    build_quality_fix_hint_for_dimension,
    format_quality_line,
    score_section,
)
from src.backend.grounded_stats import draft_coverage, format_coverage_line
from src.theme import current_palette
from src.widgets.result_preview import ResultPreviewWidget

_EMPTY_HINT = (
    "还没有草稿 — 在中间 AI 轨道点「开始设计课程」，"
    "或打开「设计与草稿」对话生成。"
)

# Shared with Teacher / Fix (aiEnhance U1-5).
_REGEN_PRESETS: tuple[str, ...] = EDIT_PRESETS

_DIM_SHORT = {
    "coverage": "复现",
    "balance": "题型",
    "distractor": "干扰",
    "level_fit": "难度",
    "audio_ready": "听力",
    "resource_hygiene": "资源",
}


class ReviewPanel(QWidget):
    """Structured review of the design draft before import."""

    def __init__(
        self,
        design_panel: Any,
        adapter: Any,
        parent: QWidget | None = None,
    ) -> None:
        super().__init__(parent)
        self._design_panel = design_panel
        self.adapter = adapter
        self._last_quality = None

        lay = QVBoxLayout(self)
        lay.setContentsMargins(8, 8, 8, 8)
        lay.setSpacing(6)

        self._preview = ResultPreviewWidget(adapter, self)
        self._preview.regenerate_requested.connect(self._on_regenerate_requested)
        lay.addWidget(self._preview, 1)

        self._hint_label = QLabel("")
        self._hint_label.setStyleSheet(
            f"color: {current_palette()['text_secondary']};"
        )
        lay.addWidget(self._hint_label)

        self._coverage_label = QLabel("")
        self._coverage_label.setWordWrap(True)
        self._coverage_label.setStyleSheet(
            f"color: {current_palette()['text_secondary']}; font-size: 11px;"
        )
        self._coverage_label.setVisible(False)
        lay.addWidget(self._coverage_label)

        # U0-1: generation summary card (human-readable, not raw JSON).
        self._summary_browser = QTextBrowser()
        self._summary_browser.setMaximumHeight(140)
        self._summary_browser.setOpenExternalLinks(False)
        self._summary_browser.setVisible(False)
        self._summary_browser.setStyleSheet(
            f"font-size: 11px; color: {current_palette()['text']};"
        )
        lay.addWidget(self._summary_browser)

        self._quality_label = QLabel("")
        self._quality_label.setWordWrap(True)
        self._quality_label.setStyleSheet(
            f"color: {current_palette()['text_secondary']}; font-size: 11px;"
        )
        self._quality_label.setVisible(False)
        self._quality_label.setToolTip(
            "内容质量分（规则探针，不阻断保存/导入）。点击下方维度可查看问题并定向修复。"
        )
        lay.addWidget(self._quality_label)

        # U0-3: clickable quality dimension chips.
        self._dim_row = QHBoxLayout()
        self._dim_buttons: dict[str, QPushButton] = {}
        for dim, short in _DIM_SHORT.items():
            btn = QPushButton(short)
            btn.setFlat(True)
            btn.setEnabled(False)
            btn.setToolTip(f"查看「{short}」维度问题并一键修复（建议性）")
            btn.setProperty("dimension_key", dim)
            btn.clicked.connect(self._on_dim_btn_clicked)
            self._dim_buttons[dim] = btn
            self._dim_row.addWidget(btn)
        self._dim_row.addStretch(1)
        lay.addLayout(self._dim_row)

        row = QHBoxLayout()
        self._try_btn = QPushButton("试做")
        self._try_btn.setToolTip("用播放器试做草稿中的某一课时")
        self._try_btn.clicked.connect(self._on_try)
        row.addWidget(self._try_btn)
        self._diff_btn = QPushButton("与现有课程对比 (diff)")
        self._diff_btn.clicked.connect(self._on_diff)
        row.addWidget(self._diff_btn)
        self._fix_btn = QPushButton("AI 修复")
        self._fix_btn.setToolTip("让 AI 修复校验发现的问题（应用前可查看 diff）")
        self._fix_btn.clicked.connect(self._on_fix)
        row.addWidget(self._fix_btn)
        self._quality_fix_btn = QPushButton("按质量分修复")
        self._quality_fix_btn.setToolTip(
            "根据内容质量低分维度（复现/干扰项/待补等）让 AI 定向改进；不阻断导入"
        )
        self._quality_fix_btn.clicked.connect(self._on_quality_fix)
        row.addWidget(self._quality_fix_btn)
        self._fill_review_btn = QPushButton("清待补")
        self._fill_review_btn.setToolTip(
            "对草稿中 [待补] / needs-review 词条做第二趟 AI 补全（需配置 API）"
        )
        self._fill_review_btn.clicked.connect(self._on_fill_needs_review)
        row.addWidget(self._fill_review_btn)
        self._restore_btn = QPushButton("恢复上一版草稿")
        self._restore_btn.setToolTip("恢复生成/局部重生成前的草稿检查点")
        self._restore_btn.clicked.connect(self._on_restore_checkpoint)
        row.addWidget(self._restore_btn)
        row.addStretch(1)
        self._import_btn = QPushButton("导入到课程 ↗")
        self._import_btn.setDefault(True)
        self._import_btn.clicked.connect(self._on_import)
        row.addWidget(self._import_btn)
        lay.addLayout(row)

        # U2-1: ReadyImport decision strip (advisory).
        self._decision_label = QLabel("")
        self._decision_label.setWordWrap(True)
        self._decision_label.setVisible(False)
        self._decision_label.setStyleSheet(
            f"font-size: 12px; font-weight: 600; color: {current_palette()['text']};"
        )
        lay.addWidget(self._decision_label)

        self.refresh()

    # ------------------------------------------------------------------ state
    def _ai_config(self):
        controller = getattr(self._design_panel, "_controller", None)
        if controller is not None and hasattr(controller, "ai_config"):
            return controller.ai_config()
        from src.application.ai_runtime import runtime_from_host
        return runtime_from_host(self).config()

    def _draft(self) -> dict | None:
        """Current editor truth from the design panel (None when empty)."""
        return self._design_panel._current_editor_json_silent()

    def refresh(self) -> None:
        """Re-render from the design panel's current draft."""
        draft = self._draft()
        has = draft is not None
        if has:
            self._preview.show_section(draft)
            units = draft.get("units", [])
            lessons = sum(len(u.get("lessons", [])) for u in units)
            self._hint_label.setText(
                f"草稿「{draft.get('name', draft.get('id', ''))}」："
                f"{len(units)} 单元 · {lessons} 课时 · {len(draft.get('words', []))} 词"
            )
            pool = self._design_panel._controller.resource_pool
            cov = draft_coverage(draft, pool)
            cov_line = format_coverage_line(cov)
            self._coverage_label.setText(cov_line)
            self._coverage_label.setVisible(bool(cov_line))
            structural = self._collect_structural(draft)
            self._refresh_quality(draft, pool, structural=structural)
            self._refresh_summary(draft, pool, structural=structural)
            self._refresh_decision(structural=structural)
            self._silent_validate(draft)
        else:
            self._hint_label.setText(_EMPTY_HINT)
            self._coverage_label.setText("")
            self._coverage_label.setVisible(False)
            self._quality_label.setText("")
            self._quality_label.setVisible(False)
            self._summary_browser.setPlainText("")
            self._summary_browser.setVisible(False)
            self._decision_label.setText("")
            self._decision_label.setVisible(False)
            self._last_quality = None
            for dim, btn in self._dim_buttons.items():
                btn.setEnabled(False)
                btn.setText(_DIM_SHORT.get(dim, dim))
                btn.setStyleSheet("")
        for btn in (
            self._try_btn,
            self._diff_btn,
            self._fix_btn,
            self._quality_fix_btn,
            self._fill_review_btn,
            self._import_btn,
        ):
            btn.setEnabled(has)
        can_restore = bool(
            getattr(self._design_panel._controller, "_draft_checkpoint", None)
        )
        self._restore_btn.setEnabled(can_restore)
        if has:
            # Enable 清待补 only when hygiene suggests work.
            ph = 0
            nr = 0
            if self._last_quality is not None:
                hyg = self._last_quality.hygiene or {}
                ph = int(
                    hyg.get("placeholder_count")
                    or hyg.get("placeholders")
                    or 0
                )
                nr = int(
                    hyg.get("needs_review_count")
                    or hyg.get("needs_review")
                    or 0
                )
            self._fill_review_btn.setEnabled(bool(ph or nr))

    def _course_level(self) -> str:
        adapter = self.adapter
        if adapter is None:
            return "A1"
        try:
            return str(adapter.index.get("level") or "A1")
        except Exception:
            return "A1"

    def _collect_structural(self, draft: dict) -> list[Any]:
        if self.adapter is None:
            return []
        try:
            return list(
                self.adapter.validate_section_json(draft, check_existing_ids=False)
                or []
            )
        except TypeError:
            try:
                return list(self.adapter.validate_section_json(draft) or [])
            except Exception:
                return []
        except Exception:
            return []

    def _refresh_summary(
        self,
        draft: dict,
        pool: list | None,
        *,
        structural: list[Any] | None = None,
    ) -> None:
        controller = self._design_panel._controller
        mode = str(controller.params.get("generation_mode") or "fast")
        model_json = ""
        try:
            cfg = self._ai_config()
            model_json = (
                getattr(cfg, "model_json", None)
                or getattr(cfg, "model", "")
                or ""
            )
        except Exception:
            model_json = ""
        cache_hit = bool(getattr(controller, "last_cache_hit", False))
        summary = build_generation_summary(
            draft,
            level=self._course_level(),
            resource_pool=pool,
            structural=structural,
            usage=controller.usage,
            cache_hit=cache_hit,
            model_json=str(model_json),
            mode=mode,
            quality_report=self._last_quality,
        )
        self._summary_browser.setPlainText(format_summary_card(summary))
        self._summary_browser.setVisible(True)

    def _refresh_quality(
        self,
        draft: dict,
        pool: list | None,
        *,
        structural: list[Any] | None = None,
    ) -> None:
        if structural is None:
            structural = self._collect_structural(draft)
        report = score_section(
            draft,
            level=self._course_level(),
            resource_pool=pool,
            structural_errors=structural or None,
        )
        self._last_quality = report
        chips = []
        for dim, score in report.scores.items():
            label = _DIM_SHORT.get(dim, dim)
            chips.append(f"{label} {score:.2f}")
            btn = self._dim_buttons.get(dim)
            if btn is not None:
                btn.setText(f"{label} {score:.2f}")
                btn.setEnabled(True)
                # Soft color cue for low dimensions.
                if score < 0.7:
                    btn.setStyleSheet("color: #dc2626; font-weight: 600;")
                elif score < 0.85:
                    btn.setStyleSheet("color: #d97706;")
                else:
                    btn.setStyleSheet("")
        line = (
            f"内容质量 {report.mean:.2f}（{report.badge()}）· "
            + " · ".join(chips)
            + "  · 点击维度可钻取"
        )
        if report.error_count or report.warning_count:
            line += f" · {report.error_count}e/{report.warning_count}w"
        self._quality_label.setText(line)
        self._quality_label.setToolTip(format_quality_line(report))
        pal = current_palette()
        if report.badge() == "error":
            color = pal.get("error", pal["text_secondary"])
        elif report.badge() == "warning":
            color = pal.get("warning", pal["text_secondary"])
        else:
            color = pal.get("success", pal["text_secondary"])
        self._quality_label.setStyleSheet(f"color: {color}; font-size: 11px;")
        self._quality_label.setVisible(True)

    def _on_dim_btn_clicked(self) -> None:
        sender = self.sender()
        if not sender:
            return
        dim = sender.property("dimension_key")
        if isinstance(dim, str):
            self._on_dimension_clicked(dim)

    def _on_dimension_clicked(self, dimension: str) -> None:
        """U0-3: show issues for one dimension; offer targeted AI fix."""
        draft = self._draft()
        if draft is None or self._last_quality is None:
            return
        report = self._last_quality
        score = float(report.scores.get(dimension, 0.0))
        issues = [
            i for i in report.issues if i.dimension == dimension
        ]
        short = _DIM_SHORT.get(dimension, dimension)
        if not issues:
            body = f"维度「{short}」当前 {score:.2f}，暂无具体问题条目。"
            if score >= 0.85:
                QMessageBox.information(self, f"质量 · {short}", body)
                return
            body += "\n是否仍按该维度让 AI 定向改进？"
        else:
            lines = [f"维度「{short}」{score:.2f}："]
            for issue in issues[:12]:
                lines.append(f"· {issue.message}")
            body = "\n".join(lines) + "\n\n是否按此维度 AI 修复？（建议性，不阻断导入）"
        reply = QMessageBox.question(
            self,
            f"质量 · {short}",
            body,
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
        )
        if reply != QMessageBox.StandardButton.Yes:
            return
        problems = report.to_problem_dicts(dimensions=[dimension], max_issues=40)
        if not problems:
            problems = [
                {
                    "level": "warning",
                    "path": f"quality.{dimension}",
                    "message": f"[{dimension}] 请提升该维度（当前 {score:.2f}）",
                    "dimension": dimension,
                }
            ]
        hint = build_quality_fix_hint_for_dimension(report, dimension)
        from src.dialogs.ai_fix_dialog import AiFixDialog

        dlg = AiFixDialog(
            problems,
            draft,
            self._course_context_for_fix(draft),
            self._ai_config(),
            parent=self,
            initial_hint=hint,
            window_title=f"按质量维修复 · {short}",
        )
        if dlg.exec() != QDialog.DialogCode.Accepted:
            return
        corrected = dlg.corrected_node()
        if corrected is None:
            return
        self._apply_corrected_draft(draft, corrected)

    def _on_fill_needs_review(self) -> None:
        """U1-6: explicit second-pass fill for [待补]/needs-review on the draft."""
        draft = self._draft()
        if draft is None:
            return
        controller = self._design_panel._controller
        if controller.is_busy:
            QMessageBox.information(self, "清待补", "当前有任务进行中，请稍候。")
            return
        from src.backend.ai_generator import fill_needs_review_resources
        from src.dialogs.ai.worker import AiRequestWorker

        config = self._ai_config()
        self._fill_review_btn.setEnabled(False)
        self._hint_label.setText("正在补全 [待补] / needs-review …")

        def _target() -> dict:
            return fill_needs_review_resources(config, draft)

        worker = AiRequestWorker(_target)

        def _on_ok(result: Any) -> None:
            self._fill_review_btn.setEnabled(True)
            if not isinstance(result, dict):
                QMessageBox.warning(self, "清待补", "AI 返回了无法识别的结果。")
                return
            if not self._confirm_apply_fix(draft, result):
                return
            self._design_panel._json_editor.set_json(result)
            controller.set_draft(result)
            self.refresh()
            QMessageBox.information(self, "清待补", "已应用补全结果（可继续校验后导入）。")

        def _on_err(msg: str) -> None:
            self._fill_review_btn.setEnabled(True)
            QMessageBox.warning(self, "清待补失败", msg)

        worker.result_ready.connect(_on_ok)
        worker.error_occurred.connect(_on_err)
        worker.start()
        # Keep a reference so GC doesn't kill the QThread mid-flight.
        self._fill_worker = worker

    def _silent_validate(self, draft: dict) -> None:
        """Run validate when adapter is available; no dialogs."""
        if self.adapter is None:
            return
        try:
            problems = self.adapter.validate_section_json(
                draft, check_existing_ids=False
            )
        except TypeError:
            # Some adapters only accept section without kwargs.
            try:
                problems = self.adapter.validate_section_json(draft)
            except Exception:
                return
        except Exception:
            return
        self._preview.apply_validation(problems)

    # ------------------------------------------------------------------ actions
    def _on_try(self) -> None:
        self._design_panel._on_try_lesson()
        self.refresh()

    def _on_diff(self) -> None:
        draft = self._draft()
        if draft is None:
            return
        if self.adapter is None:
            QMessageBox.information(self, "对比", "未加载课程，无法对比。")
            return
        try:
            existing = self.adapter.find_section(draft.get("id", ""))
        except KeyError:
            QMessageBox.information(
                self, "对比", "当前课程中没有同 id 的 section — 导入将是全新内容。"
            )
            return
        from src.widgets.diff_view import SectionDiffView

        SectionDiffView(existing, draft, self).exec()

    def _confirm_apply_fix(self, original: dict, corrected: dict) -> bool:
        """Show structural diff; return True if user accepts the fix."""
        from src.widgets.diff_view import SectionDiffView

        dlg = SectionDiffView(
            original,
            corrected,
            self,
            confirm=True,
            title="AI 修复预览 — 确认后应用",
        )
        return dlg.exec() == QDialog.DialogCode.Accepted

    def _course_context_for_fix(self, draft: dict) -> dict[str, Any]:
        language = "en"
        existing: dict[str, list] = {
            "vocab": [],
            "expressions": [],
            "grammar_points": [],
        }
        if self.adapter is not None:
            try:
                language = self.adapter.index.get("language", "en")
            except Exception:
                language = "en"
            try:
                existing = {
                    "vocab": [w.get("id") for w in self.adapter.vocab if w.get("id")],
                    "expressions": [
                        e.get("id") for e in self.adapter.expressions if e.get("id")
                    ],
                    "grammar_points": [
                        g.get("id") for g in self.adapter.grammar_points if g.get("id")
                    ],
                }
            except Exception:
                logger.debug("dialogs/ai/review_panel.py:544 best-effort step failed", exc_info=True)
        return {
            "node_kind": "section",
            "node_id": draft.get("id", ""),
            "language": language,
            "existing_resource_ids": existing,
        }

    def _apply_corrected_draft(self, draft: dict, corrected: dict) -> None:
        if not self._confirm_apply_fix(draft, corrected):
            return
        self._design_panel._json_editor.set_json(corrected)
        self._design_panel._controller.set_draft(corrected)
        self.refresh()

    def _on_fix(self) -> None:
        draft = self._draft()
        if draft is None:
            return
        if self.adapter is None:
            QMessageBox.information(self, "AI 修复", "未加载课程，无法校验与修复。")
            return
        problems = self.adapter.validate_section_json(draft, check_existing_ids=False)
        if not problems:
            QMessageBox.information(self, "AI 修复", "校验没有发现问题，无需修复。")
            return
        from src.dialogs.ai_fix_dialog import AiFixDialog

        dlg = AiFixDialog(
            problems,
            draft,
            self._course_context_for_fix(draft),
            self._ai_config(),
            parent=self,
        )

        if dlg.exec() != QDialog.DialogCode.Accepted:
            return
        corrected = dlg.corrected_node()
        if corrected is None:
            return
        self._apply_corrected_draft(draft, corrected)

    def _on_quality_fix(self) -> None:
        """P2-6: AI fix driven by content-quality low dimensions (not structural only)."""
        draft = self._draft()
        if draft is None:
            return
        pool = getattr(self._design_panel._controller, "resource_pool", None)
        report = self._last_quality or score_section(
            draft, level=self._course_level(), resource_pool=pool
        )
        lows = report.low_dimensions(0.75)
        problems = report.to_problem_dicts(
            dimensions=lows or None,
            max_issues=40,
        )
        if not problems and report.mean >= 0.85 and report.error_count == 0:
            QMessageBox.information(
                self,
                "按质量分修复",
                f"内容质量已较好（均值 {report.mean:.2f}），无需定向修复。",
            )
            return
        if not problems:
            problems = [
                {
                    "level": "warning",
                    "path": "quality.overall",
                    "message": f"[overall] 请整体提升可教性（当前均值 {report.mean:.2f}）",
                    "dimension": "coverage",
                }
            ]
        hint = build_quality_fix_hint(report)
        from src.dialogs.ai_fix_dialog import AiFixDialog

        dlg = AiFixDialog(
            problems,
            draft,
            self._course_context_for_fix(draft),
            self._ai_config(),
            parent=self,
            initial_hint=hint,
            window_title="按质量分 AI 修复",
        )
        if dlg.exec() != QDialog.DialogCode.Accepted:
            return
        corrected = dlg.corrected_node()
        if corrected is None:
            return
        self._apply_corrected_draft(draft, corrected)

    def _refresh_decision(self, *, structural: list[Any] | None = None) -> None:
        """U2-1: human decision strip before import."""
        report = self._last_quality
        err_n = 0
        for p in structural or []:
            if isinstance(p, dict) and p.get("level", "error") != "error":
                continue
            err_n += 1
        if report is None:
            self._decision_label.setVisible(False)
            return
        mean = report.mean
        badge = report.badge()
        if err_n:
            text = (
                f"导入建议：先修结构错误（{err_n} 个）— 可用「AI 修复」或主界面校验批量修。"
                f" 质量均值 {mean:.2f}（建议性，不阻断）。"
            )
            color = "#dc2626"
        elif badge == "error" or mean < 0.55:
            text = (
                f"导入建议：内容质量偏低（{mean:.2f}）— 建议点维度钻取或「按质量分修复」后再导入。"
            )
            color = "#d97706"
        elif badge == "warning" or mean < 0.75:
            text = (
                f"导入建议：可导入，但建议扫一眼低分维（均值 {mean:.2f}）。"
                " 也可先「试做」再导入。"
            )
            color = "#d97706"
        else:
            text = (
                f"导入建议：结构与质量均较好（均值 {mean:.2f}）— 可导入到课程。"
                " 导入后建议在总览/教师模式复查。"
            )
            color = "#16a34a"
        self._decision_label.setText(text)
        self._decision_label.setStyleSheet(
            f"font-size: 12px; font-weight: 600; color: {color};"
        )
        self._decision_label.setVisible(True)

    def _on_import(self) -> None:
        # U2-1: optional soft confirm when structural errors or very low quality.
        report = self._last_quality
        draft = self._draft()
        structural = self._collect_structural(draft) if draft else []
        err_n = sum(
            1
            for p in structural
            if not isinstance(p, dict) or p.get("level", "error") == "error"
        )
        if err_n:
            reply = QMessageBox.question(
                self,
                "仍有结构错误",
                f"当前草稿仍有 {err_n} 个结构错误。导入可能被拒绝或产生坏数据。\n"
                "是否仍继续尝试导入？",
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
                QMessageBox.StandardButton.No,
            )
            if reply != QMessageBox.StandardButton.Yes:
                return
        elif report is not None and report.mean < 0.55:
            reply = QMessageBox.question(
                self,
                "质量偏低",
                f"内容质量均值仅 {report.mean:.2f}（建议性）。\n"
                "建议先「按质量分修复」或点维度钻取。是否仍导入？",
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
                QMessageBox.StandardButton.No,
            )
            if reply != QMessageBox.StandardButton.Yes:
                return
        # Validation + emit lives on the design panel (single truth path).
        self._design_panel._on_import()

    def _on_restore_checkpoint(self) -> None:
        controller = self._design_panel._controller
        if not controller.restore_draft_checkpoint():
            QMessageBox.information(self, "恢复草稿", "没有可恢复的上一版草稿。")
            return
        # Push restored draft into the editor (controller only holds the model).
        if controller.draft is not None:
            self._design_panel._json_editor.set_json(controller.draft)
        self.refresh()

    def _prompt_regenerate_instruction(self, kind: str, node_id: str) -> str | None:
        """Dialog with preset chips; return instruction or None if cancelled.

        Empty string means regenerate with default model prompt (no extra instruction).
        """
        label = "课时" if kind == "lesson" else "单元"
        dlg = QDialog(self)
        dlg.setWindowTitle(f"局部重生成 — {label}")
        lay = QVBoxLayout(dlg)
        lay.addWidget(
            QLabel(
                f"用 AI 重写该{label}（{node_id}）。\n"
                "可填写额外指令；留空则使用默认重写。生成前会保存草稿检查点。"
            )
        )
        edit = QPlainTextEdit()
        edit.setPlaceholderText("例如：加强干扰项；补全 transcript；降低难度…")
        edit.setMinimumHeight(80)
        lay.addWidget(edit)
        scope_label = QLabel("")
        scope_label.setWordWrap(True)
        scope_label.setStyleSheet(
            f"color: {current_palette()['text_secondary']}; font-size: 11px;"
        )
        lay.addWidget(scope_label)

        def _update_scope(_text: str | None = None) -> None:
            from src.backend.ai_scope import format_scope_resolution, resolve_edit_scope

            draft = self._draft() or {}
            res = resolve_edit_scope(edit.toPlainText(), draft)
            # Local regenerate already targets this node; show NL parse as hint.
            scope_label.setText(
                f"作用域提示：{format_scope_resolution(res)} · 本次将重写本{label} {node_id}"
            )

        edit.textChanged.connect(_update_scope)
        _update_scope()
        chips = QHBoxLayout()
        for text, short in zip(EDIT_PRESETS, EDIT_PRESET_LABELS):
            btn = QPushButton(short)
            btn.setToolTip(text)
            btn.setFlat(True)

            def _append(_checked: bool = False, t: str = text) -> None:
                cur = edit.toPlainText().strip()
                edit.setPlainText(f"{cur}；{t}" if cur else t)

            btn.clicked.connect(_append)
            chips.addWidget(btn)
        chips.addStretch(1)
        lay.addLayout(chips)
        buttons = QDialogButtonBox(
            QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel
        )
        buttons.button(QDialogButtonBox.StandardButton.Ok).setText("开始重生成")
        buttons.accepted.connect(dlg.accept)
        buttons.rejected.connect(dlg.reject)
        lay.addWidget(buttons)
        if dlg.exec() != QDialog.DialogCode.Accepted:
            return None
        return edit.toPlainText().strip()

    def _on_regenerate_requested(self, kind: str, node_id: str) -> None:
        controller = self._design_panel._controller
        if controller.is_busy:
            QMessageBox.information(self, "局部重生成", "当前有任务进行中，请稍候。")
            return
        instruction = self._prompt_regenerate_instruction(kind, node_id)
        if instruction is None:
            return
        # Empty instruction → pass None so backend uses its default wording.
        instr = instruction or None
        if kind == "lesson":
            controller.regenerate_lesson(node_id, instruction=instr)
        else:
            controller.regenerate_unit(node_id, instruction=instr)
