"""K-05 node AI edit — Experience wrap of MainWindow._on_ai_edit (v4.61).

Does **not** copy generate_edit / NodeAiEditDialog; only resolves target and
delegates to the existing host path (preview + confirm + Undo in src/app.py).
"""
from __future__ import annotations

from typing import Any
import logging
from src.application.experience_host import ExperienceHost
logger = logging.getLogger(__name__)


_EDIT_KINDS = frozenset({"section", "unit", "lesson"})


def resolve_edit_target(
    host: ExperienceHost,
    scope: dict | None = None,
    *,
    action_id: str = "",
) -> tuple[str, str] | None:
    """Return (kind, id) from scope / action_id prefix / selection. Never raises."""
    try:
        scope = scope or {}
        kind = str(scope.get("kind") or "").strip()
        node_id = str(scope.get("id") or scope.get("node_id") or "").strip()
        if not kind and action_id:
            prefix = str(action_id).split(".", 1)[0]
            if prefix in _EDIT_KINDS:
                kind = prefix
        if not kind or not node_id:
            ref = getattr(host, "_current_node_ref", None)
            if ref and len(ref) >= 2:
                rk, rid = str(ref[0] or ""), str(ref[1] or "")
                if rk in _EDIT_KINDS:
                    kind = kind or rk
                    node_id = node_id or rid
        if kind not in _EDIT_KINDS or not node_id:
            return None
        return kind, node_id
    except Exception:
        return None


def handle_node_edit(host: ExperienceHost, scope: dict | None = None) -> None:
    """Dispatch funnel entry for section/unit/lesson.edit."""
    scope = scope if isinstance(scope, dict) else {}
    action_hint = str(scope.get("action_id") or "")
    # Prefer action from outer dispatch when present via host attribute.
    outer = str(getattr(host, "_dispatch_action_id", "") or "")
    action_id = outer or action_hint

    target = resolve_edit_target(host, scope, action_id=action_id)
    if target is None:
        try:
            host.statusBar().showMessage(
                "请先在课程树选中节 / 单元 / 课，再 AI 编辑", 5000
            )
        except Exception:
            logger.debug("application/experience_handlers/edit.py:handle_node_edit best-effort step failed", exc_info=True)
        return

    kind, node_id = target
    edit = getattr(host, "_on_ai_edit", None)
    if not callable(edit):
        try:
            host.statusBar().showMessage("AI 编辑入口不可用", 4000)
        except Exception:
            logger.debug("application/experience_handlers/edit.py:handle_node_edit best-effort step failed", exc_info=True)
        return

    metrics = getattr(host, "experience_metrics", None)
    aid = f"{kind}.edit"
    try:
        edit(kind, node_id)
    except Exception as exc:
        try:
            host.statusBar().showMessage(f"AI 编辑失败：{exc}", 5000)
        except Exception:
            logger.debug("application/experience_handlers/edit.py:handle_node_edit best-effort step failed", exc_info=True)
        if metrics is not None:
            try:
                metrics.inc_suggestion(aid, "error")
            except Exception:
                logger.debug("application/experience_handlers/edit.py:handle_node_edit best-effort step failed", exc_info=True)
        return

    record = getattr(host, "_record_experience_event", None)
    if callable(record):
        try:
            record(
                aid,
                f"打开 AI 编辑（{kind}）",
                action_id=aid,
                scope={"kind": kind, "id": node_id},
            )
        except Exception:
            logger.debug("application/experience_handlers/edit.py:handle_node_edit best-effort step failed", exc_info=True)


# Registry aliases (same body; resolve uses action_id when scope lacks kind).
handle_section_edit = handle_node_edit
handle_unit_edit = handle_node_edit
handle_lesson_edit = handle_node_edit
