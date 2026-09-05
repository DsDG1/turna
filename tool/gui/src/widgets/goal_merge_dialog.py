"""E3-B1 Goal merge checklist dialog (select subset of sandbox items)."""
from __future__ import annotations

import logging
logger = logging.getLogger(__name__)


from typing import Any

from PySide6.QtCore import Qt
from PySide6.QtWidgets import (
    QCheckBox,
    QDialog,
    QDialogButtonBox,
    QHBoxLayout,
    QLabel,
    QPushButton,
    QScrollArea,
    QVBoxLayout,
    QWidget,
)

from src.backend.experience.sandbox import MERGE_SELECT_CAP, merge_item_key


class GoalMergeDialog(QDialog):
    """Checklist over MergePlan items. Accept → selected keys; Reject → cancel."""

    def __init__(
        self,
        merge_plan: Any,
        parent: QWidget | None = None,
        *,
        plan_summary: str = "",
        max_select: int = MERGE_SELECT_CAP,
    ) -> None:
        super().__init__(parent)
        self.setWindowTitle("Goal 合并清单")
        self.resize(520, 480)
        self._plan = merge_plan
        self._max_select = max(1, int(max_select))
        self._checks: list[tuple[str, QCheckBox]] = []

        root = QVBoxLayout(self)
        hint = QLabel(
            (plan_summary or getattr(merge_plan, "summary", "") or "选择要调度的步骤")
            + f"\n最多勾选 {self._max_select} 项；零勾选 = 不合并。"
        )
        hint.setWordWrap(True)
        root.addWidget(hint)

        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        body = QWidget()
        form = QVBoxLayout(body)
        items = list(getattr(merge_plan, "items", None) or [])
        for i, it in enumerate(items):
            key = merge_item_key(it)
            payload = getattr(it, "sandbox_payload", None)
            tag = ""
            try:
                from src.backend.experience.goal_generate import (
                    is_lesson_payload_mergeable,
                )

                if is_lesson_payload_mergeable(payload):
                    meta = (
                        payload.get("meta")
                        if isinstance(payload, dict)
                        and isinstance(payload.get("meta"), dict)
                        else {}
                    )
                    is_stub = bool(meta.get("sandbox_stub_fill"))
                    tag = " · stub 占位→Patch" if is_stub else " · AI 生成→Patch"
                elif getattr(it, "kind", "") == "action":
                    tag = " · skill"
            except Exception:
                logger.debug("widgets/goal_merge_dialog.py:73 best-effort step failed", exc_info=True)
            label = (
                f"[{getattr(it, 'kind', '?')}] "
                f"{getattr(it, 'summary', '') or getattr(it, 'action_id', key)}"
                f"{tag}"
            )
            cb = QCheckBox(label)
            cb.setChecked(i < self._max_select)
            cb.stateChanged.connect(self._on_toggle)
            form.addWidget(cb)
            self._checks.append((key, cb))
        form.addStretch(1)
        scroll.setWidget(body)
        root.addWidget(scroll, 1)

        row = QHBoxLayout()
        sel_all = QPushButton("全选(上限内)")
        sel_all.clicked.connect(self._select_capped)
        sel_none = QPushButton("全不选")
        sel_none.clicked.connect(self._select_none)
        row.addWidget(sel_all)
        row.addWidget(sel_none)
        row.addStretch(1)
        root.addLayout(row)

        buttons = QDialogButtonBox(
            QDialogButtonBox.StandardButton.Cancel
            | QDialogButtonBox.StandardButton.Ok
        )
        buttons.button(QDialogButtonBox.StandardButton.Ok).setText("合并所选")
        buttons.accepted.connect(self.accept)
        buttons.rejected.connect(self.reject)
        root.addWidget(buttons)
        self._ok_btn = buttons.button(QDialogButtonBox.StandardButton.Ok)
        self._sync_ok()

    def _on_toggle(self, *_args: Any) -> None:
        # Enforce cap: uncheck newest if over.
        checked = [(k, cb) for k, cb in self._checks if cb.isChecked()]
        if len(checked) > self._max_select:
            # Uncheck from the end of list beyond cap
            over = checked[self._max_select :]
            for _k, cb in over:
                cb.blockSignals(True)
                cb.setChecked(False)
                cb.blockSignals(False)
        self._sync_ok()

    def _sync_ok(self) -> None:
        n = sum(1 for _k, cb in self._checks if cb.isChecked())
        if self._ok_btn is not None:
            self._ok_btn.setEnabled(n > 0)
            self._ok_btn.setText(f"合并所选（{n}）" if n else "合并所选")

    def _select_capped(self) -> None:
        for i, (_k, cb) in enumerate(self._checks):
            cb.blockSignals(True)
            cb.setChecked(i < self._max_select)
            cb.blockSignals(False)
        self._sync_ok()

    def _select_none(self) -> None:
        for _k, cb in self._checks:
            cb.blockSignals(True)
            cb.setChecked(False)
            cb.blockSignals(False)
        self._sync_ok()

    def selected_keys(self) -> list[str]:
        return [k for k, cb in self._checks if cb.isChecked()]
