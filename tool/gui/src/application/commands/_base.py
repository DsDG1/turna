"""Shared plumbing for the commands package.

QUndoCommand subclasses cannot be QObjects, so every command carries a
``_Signals`` emitter (created via :func:`_make_changed`) whose ``changed``
signal re-renders the teacher views; ``_remove_by_id`` is the common
delete-by-id primitive used by item/tree/AI commands alike.
"""
from __future__ import annotations

from PySide6.QtCore import QObject, Signal


class _Signals(QObject):
    """Per-command signal emitter (QUndoCommand cannot itself be a QObject)."""
    changed = Signal()


def _make_changed() -> _Signals:
    return _Signals()


def _remove_by_id(lst: list, target_id: str) -> int:
    """Delete the first item whose ``id`` equals ``target_id``; return its index (-1 if not found)."""
    for i, entry in enumerate(lst):
        if entry is not None and entry.get("id") == target_id:
            del lst[i]
            return i
    return -1
