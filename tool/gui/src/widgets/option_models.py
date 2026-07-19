"""Shared Qt item models for reference dropdowns.

Building one ``QStandardItemModel`` per render pass and sharing it across all
comboboxes in a view avoids the O(n*m) cost of calling ``addItem`` once per
option per card.
"""
from __future__ import annotations

from PySide6.QtCore import Qt
from PySide6.QtGui import QStandardItem, QStandardItemModel


def build_options_model(
    options: list[tuple[str, str]], *, placeholder: str
) -> QStandardItemModel:
    """Build a read-only item model for a reference dropdown.

    Row 0 is the placeholder with an empty id; remaining rows store the
    option id in ``Qt.ItemDataRole.UserRole``.
    """
    model = QStandardItemModel(len(options) + 1, 1)
    placeholder_item = QStandardItem(placeholder)
    placeholder_item.setData("", Qt.ItemDataRole.UserRole)
    placeholder_item.setEditable(False)
    model.setItem(0, 0, placeholder_item)
    for row, (opt_id, label) in enumerate(options, start=1):
        item = QStandardItem(label)
        item.setData(opt_id, Qt.ItemDataRole.UserRole)
        item.setEditable(False)
        model.setItem(row, 0, item)
    return model


def select_by_id(combo, model: QStandardItemModel, current_id: str) -> None:
    """Set a combobox's current index to the row whose UserRole equals ``current_id``.

    Falls back to index 0 (placeholder) when the id is missing.
    """
    if not current_id:
        combo.setCurrentIndex(0)
        return
    matches = model.match(
        model.index(0, 0),
        Qt.ItemDataRole.UserRole,
        current_id,
        hits=1,
        flags=Qt.MatchFlag.MatchExactly,
    )
    if matches:
        combo.setCurrentIndex(matches[0].row())
    else:
        combo.setCurrentIndex(0)
