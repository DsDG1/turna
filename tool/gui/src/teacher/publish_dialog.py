"""Guided publish dialog for the teacher view (guiplan §15.9, T.8).

Hides the version concept: the teacher only sees "改了什么 / 缺什么 / 点发布".
Version bump runs automatically in the background (still shown as a confirmation
line per §15.15 risk table, but without raw json filenames). Reuses the M4
CourseAdapter release_report + apply_version_bump + save pipeline.
"""
from __future__ import annotations

from typing import Any

from PySide6.QtCore import Qt
from PySide6.QtWidgets import (
    QDialog,
    QDialogButtonBox,
    QFileDialog,
    QHBoxLayout,
    QLabel,
    QMessageBox,
    QPushButton,
    QVBoxLayout,
    QWidget,
)

from src.backend.course_adapter import CourseAdapter
from src.teacher.error_mapper import humanize_problem


class TeacherPublishDialog(QDialog):
    """Guided publish: teacher sees changes/missing-audio/errors, not version."""

    def __init__(self, adapter: CourseAdapter, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.setWindowTitle("准备发布")
        self.resize(520, 560)
        self.adapter = adapter
        self._report: dict[str, Any] = {}
        self._build_ui()
        self._load()

    def _build_ui(self) -> None:
        layout = QVBoxLayout(self)

        self.changes_label = QLabel()
        self.changes_label.setWordWrap(True)
        layout.addWidget(self.changes_label)

        self.audio_label = QLabel()
        self.audio_label.setWordWrap(True)
        layout.addWidget(self.audio_label)

        self.version_label = QLabel()
        self.version_label.setStyleSheet("color: gray;")
        layout.addWidget(self.version_label)

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
        self.buttons.button(QDialogButtonBox.StandardButton.Ok).setText("发布")
        self.buttons.accepted.connect(self._on_publish)
        self.buttons.rejected.connect(self.reject)
        row.addWidget(self.buttons)
        layout.addLayout(row)

    def _load(self) -> None:
        self._report = self.adapter.release_report()
        self._render_changes()
        self._render_audio()
        self._render_version()
        self._render_validation()

    def _render_changes(self) -> None:
        c = self._report["changes"]
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

    def _render_audio(self) -> None:
        rows = self._report["audio_manifest"]
        missing = [r for r in rows if r["status"] == "missing"]
        if not missing:
            self.audio_label.setText("音频资源：✓ 全部就位" if rows else "")
            return
        lines = [f"音频资源：⚠️ {len(missing)} 个音频未上传"]
        for r in missing:
            lines.append(f"  • {r['asset_id']}")
        self.audio_label.setText("\n".join(lines))
        self.audio_label.setStyleSheet("color: #E67E22;")

    def _render_version(self) -> None:
        plan = self._report["version_bump"]
        if not plan:
            self.version_label.setText("版本号：无需更新")
            return
        parts = [f"{cur} -> {nxt}" for cur, nxt in plan.values()]
        self.version_label.setText(f"版本号将自动更新：{', '.join(parts)}")

    def _render_validation(self) -> None:
        v = self._report["validation"]
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

    def _on_publish(self) -> None:
        v = self._report["validation"]
        if not v["ok"]:
            return
        plan = self._report["version_bump"]
        self.adapter.apply_version_bump(plan)
        result = self.adapter.save()
        if not result.ok:
            QMessageBox.critical(self, "发布失败", result.message)
            return
        QMessageBox.information(self, "发布成功", "内容已保存并校验通过。")
        self.accept()

    def _on_export(self) -> None:
        path, _ = QFileDialog.getSaveFileName(
            self, "导出报告", "release_report.txt", "Text Files (*.txt)"
        )
        if not path:
            return
        from pathlib import Path

        Path(path).write_text(self._report_text(), encoding="utf-8")
        QMessageBox.information(self, "已导出", f"报告已写入 {path}")

    def _report_text(self) -> str:
        r = self._report
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
