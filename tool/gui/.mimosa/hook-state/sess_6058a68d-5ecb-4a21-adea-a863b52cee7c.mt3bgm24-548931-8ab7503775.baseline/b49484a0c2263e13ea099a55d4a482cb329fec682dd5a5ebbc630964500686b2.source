"""Validation report dialog + tree jump (S-10 final / v4.56)."""
from __future__ import annotations

from typing import Any, Sequence


def jump_to_node(host: Any, node_ref: tuple[str, str]) -> None:
    """Select the given node in the course tree."""
    kind, node_id = node_ref
    tree = getattr(host, "tree", None)
    if tree is None:
        return
    try:
        if kind == "lesson":
            tree.select_lesson(node_id)
        elif kind == "section":
            tree.select_section(node_id)
        elif kind == "unit":
            tree.select_unit(node_id)
    except Exception:
        pass


def show_validation_report(
    host: Any,
    problems: Sequence[dict],
    title: str = "校验结果",
) -> None:
    """Show a non-modal validation report panel with double-click-to-jump."""
    from PySide6.QtWidgets import QDialog, QDialogButtonBox, QVBoxLayout

    from src.widgets.validation_report import ValidationReportWidget

    dlg = QDialog(host)
    dlg.setWindowTitle(title)
    dlg.resize(640, 420)
    report = ValidationReportWidget(host.adapter, dlg)
    report.show_problems(list(problems))
    report.jump_to.connect(lambda ref: jump_to_node(host, ref))
    report.ai_fix_requested.connect(host._on_ai_fix_requested)
    report.ai_batch_fix_requested.connect(host._on_ai_batch_fix_requested)
    report.ai_fix_single_requested.connect(host._on_ai_fix_single)
    buttons = QDialogButtonBox(QDialogButtonBox.StandardButton.Close)
    buttons.rejected.connect(dlg.reject)
    layout = QVBoxLayout(dlg)
    layout.addWidget(report)
    layout.addWidget(buttons)
    dlg.setModal(False)
    dlg.show()
