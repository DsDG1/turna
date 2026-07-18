"""Publish dialog: release checklist for both expert and teacher views.

Expert mode (``teacher_friendly=False``) shows the full release-engineer
checklist: per-file version-bump checkboxes (cancelable), audio manifest
totals, id-set diff, and raw validate/lint status. Teacher mode
(``teacher_friendly=True``) hides the version concept (auto-applied, no raw
filenames), the id-set diff, and lint warnings, and humanizes validate
errors - the teacher sees "改了什么 / 缺什么 / 点发布".

Both modes reuse the CourseAdapter release_report + apply_version_bump +
save pipeline; validate failures disable the publish button (guiplan
§15.9; §12 risk table requires showing the version change and keeping the
ability to cancel in expert mode).
"""
from __future__ import annotations

from typing import Any

from PySide6.QtCore import Qt
from PySide6.QtWidgets import (
    QCheckBox,
    QDialog,
    QDialogButtonBox,
    QFileDialog,
    QGroupBox,
    QHBoxLayout,
    QLabel,
    QMessageBox,
    QPushButton,
    QVBoxLayout,
    QWidget,
)

from src.backend.course_adapter import CourseAdapter, SaveResult
from src.teacher.error_mapper import humanize_problem
from src.theme import current_palette


class PublishDialog(QDialog):
    """Modal publish checklist. On accept, applies version bump + save."""

    def __init__(
        self,
        adapter: CourseAdapter,
        parent: QWidget | None = None,
        *,
        teacher_friendly: bool = False,
    ) -> None:
        super().__init__(parent)
        self.setWindowTitle("准备发布")
        if teacher_friendly:
            self.resize(520, 560)
        else:
            self.resize(640, 600)
        self.adapter = adapter
        self.teacher_friendly = teacher_friendly
        self._bump_checks: dict[str, QCheckBox] = {}
        self._report: dict[str, Any] = {}

        self._build_ui()
        self._load_report()

    # --- ui ---------------------------------------------------------------

    def _build_ui(self) -> None:
        layout = QVBoxLayout(self)

        if self.teacher_friendly:
            self._build_teacher_ui(layout)
        else:
            self._build_expert_ui(layout)

        self.validation_label = QLabel()
        self.validation_label.setWordWrap(True)
        layout.addWidget(self.validation_label)

        row = QHBoxLayout()
        self.export_btn = QPushButton("导出报告")
        self.export_btn.clicked.connect(self._on_export)
        row.addWidget(self.export_btn)
        row.addStretch()
        self.buttons = QDialogButtonBox(
            QDialogButtonBox.StandardButton.Cancel
            | QDialogButtonBox.StandardButton.Ok
        )
        self.buttons.button(QDialogButtonBox.StandardButton.Ok).setText(
            "发布" if self.teacher_friendly else "确认发布"
        )
        self.buttons.accepted.connect(self._on_publish)
        self.buttons.rejected.connect(self.reject)
        row.addWidget(self.buttons)
        layout.addLayout(row)

    def _build_expert_ui(self, layout: QVBoxLayout) -> None:
        layout.addWidget(QLabel("<b>本次改动</b>"))
        self.changes_label = QLabel()
        self.changes_label.setWordWrap(True)
        layout.addWidget(self.changes_label)

        self.bump_group = QGroupBox("版本号变更（确认后执行，可取消）")
        self.bump_layout = QVBoxLayout(self.bump_group)
        layout.addWidget(self.bump_group)

        self.audio_group = QGroupBox("音频资源核对")
        audio_layout = QVBoxLayout(self.audio_group)
        self.audio_label = QLabel()
        self.audio_label.setWordWrap(True)
        audio_layout.addWidget(self.audio_label)
        layout.addWidget(self.audio_group)

        self.diff_group = QGroupBox("id 集变更")
        diff_layout = QVBoxLayout(self.diff_group)
        self.diff_label = QLabel()
        self.diff_label.setWordWrap(True)
        self.diff_label.setAlignment(Qt.AlignmentFlag.AlignTop)
        diff_layout.addWidget(self.diff_label)
        layout.addWidget(self.diff_group)

    def _build_teacher_ui(self, layout: QVBoxLayout) -> None:
        self.changes_label = QLabel()
        self.changes_label.setWordWrap(True)
        layout.addWidget(self.changes_label)

        self.audio_label = QLabel()
        self.audio_label.setWordWrap(True)
        layout.addWidget(self.audio_label)

        self.version_label = QLabel()
        self.version_label.setStyleSheet(f"color: {current_palette()['text_secondary']};")
        layout.addWidget(self.version_label)

    # --- load / render -----------------------------------------------------

    def _load_report(self) -> None:
        self._report = self.adapter.release_report()
        self._render_changes()
        if self.teacher_friendly:
            self._render_audio()
            self._render_version()
        else:
            self._render_bump()
            self._render_audio()
            self._render_diff()
        self._render_validation()

    def _render_changes(self) -> None:
        c = self._report["changes"]
        if self.teacher_friendly:
            lines = ["<b>本次改动：</b>"]
            labels = [
                ("index", "课程结构（章节/单元/课）"),
                ("vocab", "词库"),
                ("expressions", "表达"),
                ("grammar_points", "语法"),
            ]
            for key, label in labels:
                if c.get(key):
                    lines.append(f"  • {label}：有改动")
            if not any(c.get(k) for k, _ in labels):
                lines.append("  （无改动）")
            self.changes_label.setText("\n".join(lines))
            return
        labels = {
            "index": "index/section/unit/lesson 结构",
            "sections": "section 内容",
            "vocab": "词库",
            "expressions": "表达",
            "grammar_points": "语法",
        }
        lines = []
        for key, label in labels.items():
            mark = "有改动" if c.get(key) else "无改动"
            lines.append(f"  • {label}：{mark}")
        self.changes_label.setText("\n".join(lines))

    def _render_bump(self) -> None:
        for cb in self._bump_checks.values():
            self.bump_layout.removeWidget(cb)
            cb.deleteLater()
        self._bump_checks.clear()
        plan = self._report["version_bump"]
        if not plan:
            hint = QLabel("（无需 bump：index/expressions 无改动）")
            hint.setStyleSheet(f"color: {current_palette()['text_secondary']};")
            self.bump_layout.addWidget(hint)
            return
        for file_key, (cur, nxt) in plan.items():
            cb = QCheckBox(f"{file_key}.json: {cur} -> {nxt}")
            cb.setChecked(True)
            self._bump_checks[file_key] = cb
            self.bump_layout.addWidget(cb)

    def _render_version(self) -> None:
        plan = self._report["version_bump"]
        if not plan:
            self.version_label.setText("版本号：无需更新")
            return
        parts = [f"{cur} -> {nxt}" for cur, nxt in plan.values()]
        self.version_label.setText(f"版本号将自动更新：{', '.join(parts)}")

    def _render_audio(self) -> None:
        rows = self._report["audio_manifest"]
        missing = [r for r in rows if r["status"] == "missing"]
        if self.teacher_friendly:
            if not missing:
                self.audio_label.setText("音频资源：✓ 全部就位" if rows else "")
                return
            lines = [f"音频资源：⚠️ {len(missing)} 个音频未上传"]
            for r in missing:
                lines.append(f"  • {r['asset_id']}")
            self.audio_label.setText("\n".join(lines))
            self.audio_label.setStyleSheet("color: #E67E22;")
            return
        if not rows:
            self.audio_label.setText("（无 listening 资源引用）")
            return
        total = len(rows)
        lines = [f"共 {total} 项，{len(missing)} 项缺失"]
        for r in missing:
            lines.append(f"  ⚠️ {r['asset_id']}：{r['status']}")
        self.audio_label.setText("\n".join(lines))

    def _render_diff(self) -> None:
        diff = self._report["diff"]
        lines = []
        for key in ("vocab", "expressions", "grammar_points", "sections"):
            d = diff.get(key, {})
            added = d.get("added", [])
            removed = d.get("removed", [])
            unchanged = d.get("unchanged_count", 0)
            parts = [f"{key}: {unchanged} 不变"]
            if added:
                parts.append(f"+{', '.join(added)}")
            if removed:
                parts.append(f"-{', '.join(removed)}")
            lines.append("  • " + " | ".join(parts))
        self.diff_label.setText("\n".join(lines))

    def _render_validation(self) -> None:
        v = self._report["validation"]
        if self.teacher_friendly:
            if v["ok"]:
                self.validation_label.setText("✓ 校验通过，可以发布")
                self.validation_label.setStyleSheet("color: #27AE60;")
                self.buttons.button(QDialogButtonBox.StandardButton.Ok).setEnabled(True)
            else:
                lines = [f"✗ 校验未通过（{len(v['errors'])} 个问题），请先修复："]
                for e in v["errors"]:
                    lines.append(f"  • {humanize_problem(e)}")
                self.validation_label.setText("\n".join(lines))
                self.validation_label.setStyleSheet("color: #E74C3C;")
                self.buttons.button(QDialogButtonBox.StandardButton.Ok).setEnabled(False)
            return
        if v["ok"]:
            base = "✓ validate 通过"
        else:
            base = f"✗ validate 失败（{len(v['errors'])} 个错误）"
        warn = f" / ⚠ {len(v['warnings'])} 个 lint 警告" if v["warnings"] else ""
        self.validation_label.setText(base + warn)
        ok_enabled = v["ok"]
        self.buttons.button(QDialogButtonBox.StandardButton.Ok).setEnabled(ok_enabled)
        if not ok_enabled:
            detail = "\n".join(e.get("message", "") for e in v["errors"])
            self.validation_label.setToolTip(detail)

    # --- actions -----------------------------------------------------------

    def _on_publish(self) -> None:
        v = self._report["validation"]
        if not v["ok"]:
            if not self.teacher_friendly:
                QMessageBox.warning(
                    self, "无法发布", "校验未通过，请先修复错误再发布。"
                )
            return
        if self.teacher_friendly:
            real_plan: dict[str, tuple[int, int]] = dict(self._report["version_bump"])
        else:
            real_plan = {
                key: self._report["version_bump"][key]
                for key, cb in self._bump_checks.items()
                if cb.isChecked()
            }
        self.adapter.apply_version_bump(real_plan)
        result: SaveResult = self.adapter.save()
        if not result.ok:
            QMessageBox.critical(self, "发布失败", result.message)
            return
        QMessageBox.information(
            self,
            "发布成功",
            "内容已保存并校验通过。" if self.teacher_friendly
            else "版本号已 bump 并保存校验通过。",
        )
        self.accept()

    def _on_export(self) -> None:
        path, _ = QFileDialog.getSaveFileName(
            self, "导出发布报告", "release_report.txt", "Text Files (*.txt)"
        )
        if not path:
            return
        from pathlib import Path

        Path(path).write_text(self._report_text(), encoding="utf-8")
        QMessageBox.information(self, "已导出", f"报告已写入 {path}")

    def _report_text(self) -> str:
        r = self._report
        if self.teacher_friendly:
            lines = ["Varnamala 发布报告", "=" * 30, ""]
            lines.append("[改动]")
            for k, v in r["changes"].items():
                if v:
                    lines.append(f"  {k}: 改动")
            lines.append("")
            lines.append("[音频]")
            for row in r["audio_manifest"]:
                lines.append(f"  {row['asset_id']}: {row['status']}")
            lines.append("")
            lines.append("[版本号]")
            for f, (c, n) in r["version_bump"].items():
                lines.append(f"  {f}: {c} -> {n}")
            lines.append("")
            v = r["validation"]
            lines.append(f"[校验] ok={v['ok']}")
            for e in v["errors"]:
                lines.append(f"  ERROR: {humanize_problem(e)}")
            return "\n".join(lines) + "\n"
        lines: list[str] = ["Varnamala 发布报告", "=" * 40, ""]
        lines.append("[改动检测]")
        for k, v in r["changes"].items():
            lines.append(f"  {k}: {'改动' if v else '无'}")
        lines.append("")
        lines.append("[版本号变更]")
        if r["version_bump"]:
            for f, (c, n) in r["version_bump"].items():
                lines.append(f"  {f}.json: {c} -> {n}")
        else:
            lines.append("  无")
        lines.append("")
        lines.append("[音频资源]")
        for row in r["audio_manifest"]:
            lines.append(f"  {row['asset_id']}: {row['status']}")
        lines.append("")
        lines.append("[id 集变更]")
        for k, d in r["diff"].items():
            lines.append(
                f"  {k}: +{d['added']} -{d['removed']} ({d['unchanged_count']} 不变)"
            )
        lines.append("")
        lines.append("[校验]")
        v = r["validation"]
        lines.append(f"  validate ok: {v['ok']}")
        for e in v["errors"]:
            lines.append(f"  ERROR: {e.get('message', '')}")
        for w in v["warnings"]:
            lines.append(f"  WARN: {w.get('message', '')}")
        return "\n".join(lines) + "\n"
