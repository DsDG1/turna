"""Serialization to/from TextbookProject and autosave synchronization for textbook import."""
from __future__ import annotations

import logging
from pathlib import Path
from typing import Any, Callable

from src.backend.textbook_project import TextbookProject
from src.backend.textbook_project_store import _new_project_id
from src.infrastructure.telemetry import telemetry

logger = logging.getLogger(__name__)


def serialize_to_project(
    *,
    project_id: str,
    project_name: str,
    source_path: Path | None,
    markdown: str,
    language: str,
    source_language: str,
    chapters: list[Any],
    current_step: int,
) -> TextbookProject:
    """Serialize controller state into a ``TextbookProject``."""
    name = project_name or "未命名项目"
    pid = project_id or _new_project_id(name)
    project = TextbookProject.create(
        project_id=pid,
        name=name,
        source_path=source_path,
        markdown=markdown,
        language=language,
        source_language=source_language,
    )
    project.set_chapters(
        [(cr.chapter, cr.keep, cr.knowledge, cr.error) for cr in chapters]
    )
    project.current_step = current_step
    # Snapshot the merged knowledge as the resource pool (connectplan §3.1);
    # dedup stays with the import-time KnowledgeMerger.
    project.update_resource_pool()
    return project


def execute_autosave(
    on_autosave: Callable[[TextbookProject], None] | None,
    project: TextbookProject,
    status_hook: Callable[[str], None] | None = None,
) -> None:
    """Safely invoke the autosave callback with telemetry error logging.

    Autosave must never break the workflow, but a permanently-failing autosave
    (disk full, read-only project dir) used to lose all extraction work silently.
    Record the error so the failure is at least observable in telemetry, and
    surface it once to the user via the status hook if available. (B9)
    """
    if on_autosave is None:
        return
    try:
        on_autosave(project)
    except Exception as exc:
        telemetry.record_error(exc, context={"action": "textbook.autosave"})
        if callable(status_hook):
            try:
                status_hook(f"自动保存失败：{exc}")
            except Exception:  # noqa: BLE001 — never break on the error path
                logger.debug("textbook autosave status_hook failed", exc_info=True)
