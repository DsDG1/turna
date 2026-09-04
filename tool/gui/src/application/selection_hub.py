"""C-04 SelectionHub — unified focus / multi-select protocol (v4.57).

Duck-types MainWindow. Keeps tree / teacher / pin focus paths single-sourced
without a heavyweight Qt hub widget.
"""
from __future__ import annotations

from typing import Any, Sequence
import logging
from src.application.experience_host import ExperienceHost
logger = logging.getLogger(__name__)


def sync_focus(host: ExperienceHost, *, immediate: bool = False) -> None:
    """Rebuild FocusRing + focus-only Experience refresh."""
    try:
        host._sync_focus_ring()
    except Exception:
        logger.debug("application/selection_hub.py:sync_focus best-effort step failed", exc_info=True)
    try:
        host._refresh_experience(immediate=immediate, focus_only=True)
    except Exception:
        logger.debug("application/selection_hub.py:sync_focus best-effort step failed", exc_info=True)


def apply_tree_selection(
    host: ExperienceHost,
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
        logger.debug("application/selection_hub.py:apply_tree_selection best-effort step failed", exc_info=True)
    sync_focus(host, immediate=False)


def apply_teacher_item_focus(host: ExperienceHost, item_id: str) -> None:
    """Teacher-mode item focus → Experience selection as item ref."""
    lid = str(item_id or "").strip()
    if not lid:
        return
    try:
        host._teacher_focused_item_id = lid
    except Exception:
        logger.debug("application/selection_hub.py:apply_teacher_item_focus best-effort step failed", exc_info=True)
    try:
        host.experience.set_surface("teacher")
        host.experience.set_selection(("item", lid))
    except Exception:
        logger.debug("application/selection_hub.py:apply_teacher_item_focus best-effort step failed", exc_info=True)
    sync_focus(host, immediate=True)
