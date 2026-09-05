"""Section diff view for edit mode (guiplan2 P3.4).

Shows added / removed / changed units, lessons and resources between an
existing section and the AI-edited one, as a three-color tree (green added,
red removed, yellow changed). Backed by ``full_section_diff`` (pure function).
"""
from __future__ import annotations

import logging
logger = logging.getLogger(__name__)


from typing import Any

from PySide6.QtGui import QColor
from PySide6.QtWidgets import (
    QDialog,
    QDialogButtonBox,
    QHBoxLayout,
    QLabel,
    QPushButton,
    QTreeWidget,
    QTreeWidgetItem,
    QVBoxLayout,
    QWidget,
)

from src.backend.ai_generator import full_section_diff

try:
    from src.theme import current_palette
except Exception:  # noqa: BLE001
    current_palette = None  # type: ignore[assignment]


def _pal() -> dict[str, str]:
    if current_palette is not None:
        try:
            return current_palette()
        except Exception:  # noqa: BLE001
            logger.debug("widgets/diff_view.py:36 best-effort step failed", exc_info=True)
    return {"success": "#27AE60", "error": "#E74C3C", "warning": "#FF9F43"}


_CATEGORY_LABELS = {
    "units": "单元",
    "lessons": "课时",
    "words": "词汇",
    "expressions": "表达",
    "grammar": "语法点",
}


class SectionDiffView(QDialog):
    """Modal dialog showing the structural diff between two sections.

    When ``confirm=True``, shows Apply/Cancel and returns Accepted only if
    the user clicks Apply (used by workshop AI-fix preview).
    """

    def __init__(
        self,
        existing: dict[str, Any],
        generated: dict[str, Any],
        parent: QWidget | None = None,
        *,
        confirm: bool = False,
        title: str | None = None,
    ) -> None:
        super().__init__(parent)
        self.setWindowTitle(title or "编辑 diff（增 / 删 / 改）")
        self.resize(420, 480)
        self.diff = full_section_diff(existing, generated)
        self._confirm = confirm
        self._build_ui()

    def _build_ui(self) -> None:
        layout = QVBoxLayout(self)
        layout.setContentsMargins(12, 12, 12, 12)
        layout.setSpacing(8)
        pal = _pal()
        added_c = QColor(pal.get("success", "#27AE60"))
        removed_c = QColor(pal.get("error", "#E74C3C"))
        changed_c = QColor(pal.get("warning", "#FF9F43"))

        any_change = any(
            self.diff[cat][kind]
            for cat in self.diff
            for kind in ("added", "removed", "changed")
        )
        if not any_change:
            layout.addWidget(QLabel("✓ 无结构差异（仅内容可能微调）。"))
        else:
            hint = QLabel("绿=新增  红=删除  黄=修改")
            hint.setStyleSheet(
                f"color: {pal.get('text_secondary', '#9CA3AF')}; font-size: 12px;"
            )
            layout.addWidget(hint)

            tree = QTreeWidget()
            tree.setHeaderHidden(True)
            for category, kinds in self.diff.items():
                total = (
                    len(kinds["added"])
                    + len(kinds["removed"])
                    + len(kinds["changed"])
                )
                if total == 0:
                    continue
                cat_node = QTreeWidgetItem(
                    [f"{_CATEGORY_LABELS.get(category, category)} ({total})"]
                )
                tree.addTopLevelItem(cat_node)
                for label, items, color, prefix in (
                    ("新增", kinds["added"], added_c, "+"),
                    ("删除", kinds["removed"], removed_c, "-"),
                    ("修改", kinds["changed"], changed_c, "~"),
                ):
                    if not items:
                        continue
                    kind_node = QTreeWidgetItem([f"{label} ({len(items)})"])
                    kind_node.setForeground(0, color)
                    cat_node.addChild(kind_node)
                    for item_id in items:
                        leaf = QTreeWidgetItem([f"{prefix} {item_id}"])
                        leaf.setForeground(0, color)
                        kind_node.addChild(leaf)
                cat_node.setExpanded(True)
            layout.addWidget(tree, 1)

        if self._confirm:
            buttons = QDialogButtonBox(
                QDialogButtonBox.StandardButton.Apply
                | QDialogButtonBox.StandardButton.Cancel
            )
            # QDialogButtonBox.Apply does not auto-accept; wire manually.
            apply_btn = buttons.button(QDialogButtonBox.StandardButton.Apply)
            if apply_btn is not None:
                apply_btn.setText("应用修改")
                apply_btn.clicked.connect(self.accept)
            buttons.rejected.connect(self.reject)
            layout.addWidget(buttons)
        else:
            close_row = QHBoxLayout()
            close_row.addStretch(1)
            close_btn = QPushButton("关闭")
            close_btn.clicked.connect(self.accept)
            close_row.addWidget(close_btn)
            layout.addLayout(close_row)
