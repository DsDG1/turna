"""Inline course health panel (P0-1).

Rendered inside the overview view, not as a modal dialog: the guard pins
``application → dialogs`` imports as a ratchet, and a new dialog entry would
add debt for no benefit. This widget depends only on
``src.application.course_health_service`` (application layer), never on
``src.backend`` directly.

The panel is a read-only worklist. It emits intents; the overview controller
performs the locate / dispatch through the normal Experience funnel, so each
repair keeps its own preview / confirm / undo path.
"""
from __future__ import annotations

import logging
from typing import Any

from PySide6.QtCore import Qt, Signal
from PySide6.QtWidgets import (
    QAbstractItemView,
    QApplication,
    QFrame,
    QHBoxLayout,
    QHeaderView,
    QLabel,
    QListWidget,
    QListWidgetItem,
    QPushButton,
    QSplitter,
    QTableWidget,
    QTableWidgetItem,
    QVBoxLayout,
    QWidget,
)

from src.application.course_health_service import CourseHealthService

logger = logging.getLogger(__name__)

_SEVERITY_LABELS = {
    "error": "错误",
    "warning": "警告",
    "info": "提示",
}

_DATA_ERRORS = (AttributeError, IndexError, KeyError, TypeError, ValueError, RuntimeError)


def _position_text(finding: dict[str, Any]) -> str:
    lesson_id = str(finding.get("lesson_id") or "")
    unit_id = str(finding.get("unit_id") or "")
    section_id = str(finding.get("section_id") or "")
    if lesson_id:
        return f"课 {lesson_id}"
    if unit_id:
        return f"单元 {unit_id}"
    if section_id:
        return f"节 {section_id}"
    return "全局"


class CourseHealthPanel(QFrame):
    """Findings table + grouped repair worklist (read-only scan)."""

    refresh_requested = Signal()
    locate_requested = Signal(str, str)
    execute_requested = Signal(dict)

    def __init__(self, adapter: Any, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self._service = CourseHealthService(adapter)
        self._report: dict[str, Any] = {}
        self.setFrameShape(QFrame.Shape.StyledPanel)

        root = QVBoxLayout(self)
        root.setContentsMargins(10, 8, 10, 8)
        root.setSpacing(6)

        hint = QLabel(
            "只读扫描：空课、词汇螺旋、阅读/听力缺口、低质节与资源冲突。"
            "执行修复会走各自的预览、确认与撤销。"
        )
        hint.setWordWrap(True)
        root.addWidget(hint)

        split = QSplitter(Qt.Orientation.Horizontal)
        split.setChildrenCollapsible(False)

        left = QWidget()
        left_layout = QVBoxLayout(left)
        left_layout.setContentsMargins(0, 0, 0, 0)
        left_layout.setSpacing(4)
        left_layout.addWidget(QLabel("发现的问题"))
        self.table = QTableWidget(0, 5)
        self.table.setHorizontalHeaderLabels(["级别", "类型", "位置", "问题", "建议动作"])
        self.table.setEditTriggers(QAbstractItemView.EditTrigger.NoEditTriggers)
        self.table.setSelectionBehavior(QAbstractItemView.SelectionBehavior.SelectRows)
        self.table.setSelectionMode(QAbstractItemView.SelectionMode.SingleSelection)
        self.table.verticalHeader().setVisible(False)
        self.table.setWordWrap(False)
        header = self.table.horizontalHeader()
        header.setSectionResizeMode(0, QHeaderView.ResizeMode.ResizeToContents)
        header.setSectionResizeMode(1, QHeaderView.ResizeMode.ResizeToContents)
        header.setSectionResizeMode(2, QHeaderView.ResizeMode.ResizeToContents)
        header.setSectionResizeMode(3, QHeaderView.ResizeMode.Stretch)
        header.setSectionResizeMode(4, QHeaderView.ResizeMode.ResizeToContents)
        self.table.itemSelectionChanged.connect(self._update_buttons)
        self.table.itemDoubleClicked.connect(self._on_table_item_double_clicked)
        left_layout.addWidget(self.table, 1)
        split.addWidget(left)

        right = QWidget()
        right_layout = QVBoxLayout(right)
        right_layout.setContentsMargins(0, 0, 0, 0)
        right_layout.setSpacing(4)
        right_layout.addWidget(QLabel("修复工作单"))
        self.plan = QListWidget()
        self.plan.setSelectionMode(QAbstractItemView.SelectionMode.SingleSelection)
        self.plan.itemSelectionChanged.connect(self._update_buttons)
        self.plan.itemDoubleClicked.connect(self._on_plan_item_double_clicked)
        right_layout.addWidget(self.plan, 1)
        split.addWidget(right)
        split.setStretchFactor(0, 3)
        split.setStretchFactor(1, 2)
        root.addWidget(split, 1)

        self.summary = QLabel()
        self.summary.setWordWrap(True)
        root.addWidget(self.summary)

        row = QHBoxLayout()
        self.refresh_btn = QPushButton("重新扫描")
        self.refresh_btn.clicked.connect(self.refresh)
        self.refresh_btn.clicked.connect(self.refresh_requested.emit)
        self.locate_btn = QPushButton("定位")
        self.locate_btn.setToolTip("在课程树中定位选中的问题节点")
        self.locate_btn.clicked.connect(self._emit_locate)
        self.run_btn = QPushButton("执行选中")
        self.run_btn.setToolTip("执行选中的一步；动作自带预览/确认")
        self.run_btn.clicked.connect(self._emit_execute)
        row.addWidget(self.refresh_btn)
        row.addStretch()
        row.addWidget(self.locate_btn)
        row.addWidget(self.run_btn)
        root.addLayout(row)

        self._update_buttons()

    # --- scan -----------------------------------------------------------

    def refresh(self) -> None:
        """Rebuild the report from the adapter (wait cursor for big courses)."""
        QApplication.setOverrideCursor(Qt.CursorShape.WaitCursor)
        try:
            report = self._service.build_report()
        except _DATA_ERRORS as exc:
            logger.warning("course health scan failed", exc_info=True)
            self.summary.setText(f"扫描失败：{exc}")
            return
        finally:
            QApplication.restoreOverrideCursor()
        self.set_report(report)

    def set_report(self, report: dict[str, Any] | None) -> None:
        self._report = dict(report or {})
        findings = list(self._report.get("findings") or [])
        steps = list(self._report.get("steps") or [])

        self.table.setRowCount(0)
        for finding in findings:
            self._append_finding(finding)

        self.plan.clear()
        for step in steps:
            calls = int(step.get("estimated_calls") or 0)
            title = str(step.get("title") or step.get("action_id") or "修复")
            action = str(step.get("action_title") or step.get("action_id") or "")
            suffix = f" · 预计 {calls} 次 AI 调用" if calls else ""
            row = QListWidgetItem(f"{step.get('step_id') or ''}  {title}")
            row.setToolTip(f"{action}{suffix}".strip(" ·"))
            row.setData(Qt.ItemDataRole.UserRole, step)
            self.plan.addItem(row)
        if self.plan.count():
            self.plan.setCurrentRow(0)

        counts = self._report.get("counts") or {}
        scanned_at = str(self._report.get("scanned_at") or "")
        self.summary.setText(
            "错误 {e} · 警告 {w} · 提示 {i} · 修复计划 {n} 步 / 预计 {calls} 次 AI 调用"
            "{when}".format(
                e=int(counts.get("error") or 0),
                w=int(counts.get("warning") or 0),
                i=int(counts.get("info") or 0),
                n=len(steps),
                calls=int(self._report.get("estimated_calls") or 0),
                when=f" · 扫描于 {scanned_at}" if scanned_at else "",
            )
        )
        if not findings:
            self.summary.setText(self.summary.text() + " · 未发现结构性问题")
        self._update_buttons()

    def _append_finding(self, finding: dict[str, Any]) -> None:
        row = self.table.rowCount()
        self.table.insertRow(row)
        severity = str(finding.get("severity") or "info")
        values = [
            _SEVERITY_LABELS.get(severity, severity),
            str(finding.get("kind_label") or finding.get("kind") or ""),
            _position_text(finding),
            str(finding.get("title") or ""),
            str(finding.get("action_title") or finding.get("action_id") or "人工"),
        ]
        for col, value in enumerate(values):
            item = QTableWidgetItem(value)
            if col == 3:
                detail = str(finding.get("detail") or "")
                if detail:
                    item.setToolTip(detail)
            if col == 0:
                item.setData(Qt.ItemDataRole.UserRole, finding)
            self.table.setItem(row, col, item)

    # --- selection / signals -------------------------------------------

    def _selected_finding(self) -> dict[str, Any] | None:
        row = self.table.currentRow()
        if row < 0:
            return None
        item = self.table.item(row, 0)
        if item is None:
            return None
        data = item.data(Qt.ItemDataRole.UserRole)
        return dict(data) if isinstance(data, dict) else None

    def _selected_step(self) -> dict[str, Any] | None:
        item = self.plan.currentItem()
        if item is None:
            return None
        data = item.data(Qt.ItemDataRole.UserRole)
        return dict(data) if isinstance(data, dict) else None

    def _update_buttons(self) -> None:
        finding = self._selected_finding()
        has_node = bool(
            finding
            and (
                finding.get("lesson_id")
                or finding.get("unit_id")
                or finding.get("section_id")
            )
        )
        self.locate_btn.setEnabled(has_node)
        self.run_btn.setEnabled(self._selected_step() is not None)

    def _on_table_item_double_clicked(self, _item: Any) -> None:
        """Signal slot: a double-click on a finding locates it in the tree.

        Named method rather than a lambda so ``test_signal_lifecycle`` can prove
        the connection is a bound slot (and so it can be disconnected by name).
        """
        self._emit_locate()

    def _on_plan_item_double_clicked(self, _item: Any) -> None:
        """Signal slot: a double-click on a repair step executes it."""
        self._emit_execute()

    def _emit_locate(self) -> None:
        finding = self._selected_finding()
        if not finding:
            return
        if finding.get("lesson_id"):
            self.locate_requested.emit("lesson", str(finding["lesson_id"]))
        elif finding.get("unit_id"):
            self.locate_requested.emit("unit", str(finding["unit_id"]))
        elif finding.get("section_id"):
            self.locate_requested.emit("section", str(finding["section_id"]))

    def _emit_execute(self) -> None:
        step = self._selected_step()
        if step:
            self.execute_requested.emit(step)
