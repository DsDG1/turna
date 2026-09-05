"""One-shot resolver for many colliding section merges (connectplan D7).

Historically, importing K colliding chapters under the merge strategy opened
K sequential ``AiMergePreviewDialog``s. ``BulkMergeResolveDialog`` shows every
collision in one table; each row can merge (default), skip, or be fine-tuned
via the existing per-section preview dialog ("细看").
"""
from __future__ import annotations

from typing import Any

from PySide6.QtWidgets import (
    QComboBox,
    QDialog,
    QDialogButtonBox,
    QHBoxLayout,
    QHeaderView,
    QLabel,
    QPushButton,
    QTableWidget,
    QTableWidgetItem,
    QVBoxLayout,
    QWidget,
)

from src.backend.course_adapter import SectionMergePlan

# Row actions.
_MERGE = "merge"
_SKIP = "skip"
_DETAIL = "detail"


def _counts(plan: SectionMergePlan) -> tuple[int, int]:
    """(add_count, replace_count) over units + lessons."""
    added = len(plan.added_units) + sum(
        len(v) for v in plan.added_lessons_by_unit.values()
    )
    replaced = len(plan.replaced_units) + sum(
        len(v) for v in plan.replaced_lessons_by_unit.values()
    )
    return added, replaced


class BulkMergeResolveDialog(QDialog):
    """Resolve all merge collisions of one bulk import in a single dialog."""

    def __init__(
        self,
        plans: list[SectionMergePlan],
        parent: QWidget | None = None,
        *,
        detail_opener: Any | None = None,
    ) -> None:
        super().__init__(parent)
        self.setWindowTitle("批量合并冲突处理")
        self.resize(720, 420)
        self._plans = list(plans)
        # Per-row resolution: the plan to apply (possibly tuned) or None (skip).
        self._decisions: list[SectionMergePlan | None] = list(plans)
        self._tuned: set[int] = set()
        # detail_opener(plan) -> SectionMergePlan | None; defaults to the
        # interactive AiMergePreviewDialog. Injected in tests.
        self._detail_opener = detail_opener or self._default_detail_opener
        self._combos: list[QComboBox] = []
        self._build_ui()

    @staticmethod
    def _default_detail_opener(plan: SectionMergePlan) -> SectionMergePlan | None:
        from src.dialogs.ai.ai_merge_preview_dialog import AiMergePreviewDialog

        dlg = AiMergePreviewDialog(plan)
        if dlg.exec() != QDialog.DialogCode.Accepted:
            return None
        return dlg.plan()

    def _build_ui(self) -> None:
        layout = QVBoxLayout(self)
        layout.setSpacing(12)
        layout.setContentsMargins(16, 16, 16, 16)
        layout.addWidget(
            QLabel(
                f"本次导入有 {len(self._plans)} 个 section 与现有课程冲突。"
                "逐行选择处理方式，或「细看」微调合并内容。"
            )
        )

        self._table = QTableWidget(len(self._plans), 5)
        self._table.setHorizontalHeaderLabels(
            ["section id", "名称", "新增", "替换", "处理"]
        )
        self._table.horizontalHeader().setSectionResizeMode(
            1, QHeaderView.ResizeMode.Stretch
        )
        self._table.verticalHeader().setVisible(False)
        for row, plan in enumerate(self._plans):
            section = plan.incoming_section or {}
            added, replaced = _counts(plan)
            sid = section.get("id", plan.target_section_id or "")
            self._table.setItem(row, 0, QTableWidgetItem(sid))
            self._table.setItem(row, 1, QTableWidgetItem(section.get("name", "")))
            self._table.setItem(row, 2, QTableWidgetItem(str(added)))
            self._table.setItem(row, 3, QTableWidgetItem(str(replaced)))
            combo = QComboBox()
            combo.addItem("合并（默认全选）", _MERGE)
            combo.addItem("跳过", _SKIP)
            combo.addItem("细看…", _DETAIL)
            combo.setProperty("row_idx", row)
            combo.currentIndexChanged.connect(self._on_combo_index_changed)
            self._combos.append(combo)
            self._table.setCellWidget(row, 4, combo)
        layout.addWidget(self._table, 1)

        bulk_row = QHBoxLayout()
        merge_all = QPushButton("全部合并")
        merge_all.clicked.connect(self._on_merge_all_clicked)
        skip_all = QPushButton("全部跳过")
        skip_all.clicked.connect(self._on_skip_all_clicked)
        bulk_row.addWidget(merge_all)
        bulk_row.addWidget(skip_all)
        bulk_row.addStretch(1)
        layout.addLayout(bulk_row)

        buttons = QDialogButtonBox(
            QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel
        )
        buttons.button(QDialogButtonBox.StandardButton.Ok).setText("确定")
        buttons.button(QDialogButtonBox.StandardButton.Cancel).setText("取消")
        buttons.accepted.connect(self.accept)
        buttons.rejected.connect(self.reject)
        layout.addWidget(buttons)

    def _on_combo_index_changed(self, _idx: int) -> None:
        sender = self.sender()
        if not isinstance(sender, QComboBox):
            return
        row = sender.property("row_idx")
        if row is not None:
            self._on_action_changed(int(row), sender)

    def _on_merge_all_clicked(self) -> None:
        self._set_all(_MERGE)

    def _on_skip_all_clicked(self) -> None:
        self._set_all(_SKIP)

    def _on_action_changed(self, row: int, combo: QComboBox) -> None:
        action = combo.currentData()
        if action == _DETAIL:
            tuned = self._detail_opener(self._plans[row])
            if tuned is None:
                # Detail dialog cancelled → fall back to plain merge.
                self._decisions[row] = self._plans[row]
                self._tuned.discard(row)
                combo.blockSignals(True)
                combo.setCurrentIndex(0)
                combo.blockSignals(False)
            else:
                self._decisions[row] = tuned
                self._tuned.add(row)
                combo.setItemText(2, "已自定义 ✓")
            return
        self._tuned.discard(row)
        self._decisions[row] = self._plans[row] if action == _MERGE else None

    def _set_all(self, action: str) -> None:
        for row, combo in enumerate(self._combos):
            combo.blockSignals(True)
            combo.setCurrentIndex(0 if action == _MERGE else 1)
            combo.blockSignals(False)
            self._tuned.discard(row)
            self._decisions[row] = self._plans[row] if action == _MERGE else None

    def decisions(self) -> list[SectionMergePlan | None]:
        """Per input plan: the plan to apply, or None to skip that section."""
        return list(self._decisions)

    @staticmethod
    def resolve(
        plans: list[SectionMergePlan],
        parent: QWidget | None = None,
        *,
        detail_opener: Any | None = None,
    ) -> list[SectionMergePlan | None] | None:
        """Modal convenience wrapper: decisions, or None when cancelled."""
        dlg = BulkMergeResolveDialog(plans, parent, detail_opener=detail_opener)
        if dlg.exec() != QDialog.DialogCode.Accepted:
            return None
        return dlg.decisions()
