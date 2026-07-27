"""C-04 SelectionHub — unified focus / multi-select protocol (v4.57).

Duck-types MainWindow. Keeps tree / teacher / pin focus paths single-sourced
without a heavyweight Qt hub widget.
"""
from __future__ import annotations

from typing import Any, Sequence


def sync_focus(host: Any, *, immediate: bool = False) -> None:
    """Rebuild FocusRing + focus-only Experience refresh."""
    try:
        host._sync_focus_ring()
    except Exception:
        pass
    try:
        host._refresh_experience(immediate=immediate, focus_only=True)
    except Exception:
        pass


def apply_tree_selection(
    host: Any,
    node_ref: tuple[str, str] | None,
    *,
    multi: Sequence[Any] | None = None,
    surface: str | None = None,
) -> None:
    """Apply primary tree selection (+ optional multi) into Experience."""
    if node_ref is not None:
        host._current_node_ref = node_ref
    surf = surface
    if surf is None:
        surf = "teacher" if getattr(host, "teacher_mode", False) else "tree"
    try:
        host.experience.set_surface(surf)
        if node_ref is not None:
            host.experience.set_selection(
                node_ref, multi=list(multi) if multi else None
            )
    except Exception:
        pass
    sync_focus(host, immediate=False)


def apply_teacher_item_focus(host: Any, item_id: str) -> None:
    """Teacher-mode item focus → Experience selection as item ref."""
    lid = str(item_id or "").strip()
    if not lid:
        return
    try:
        host._teacher_focused_item_id = lid
    except Exception:
        pass
    try:
        host.experience.set_surface("teacher")
        host.experience.set_selection(("item", lid))
    except Exception:
        pass
    sync_focus(host, immediate=True)
