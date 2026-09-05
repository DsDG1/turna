"""AI Validation Fix controller.

Coordinates validation error auto-fixes across sections, units, and lessons.
Decoupled from MainWindow to keep src/app.py lean and testable.
"""
from __future__ import annotations

from typing import Any
from PySide6.QtWidgets import QDialog, QMessageBox

from src.infrastructure.telemetry import telemetry
from src.backend.ai_fix_batch import FixBatch, group_problems_for_fix
from src.application.commands import (
    AiEditLessonCommand,
    AiEditUnitCommand,
    MergeAiSectionCommand,
)


class AiFixController:
    """Controller for running AI-assisted validation auto-fixes."""

    def handle_ai_fix_from_tree(self, window: Any, kind: str, node_id: str) -> None:
        """Handle AI fix request from the course tree context menu."""
        try:
            if kind == "section":
                node_json = window.adapter.find_section(node_id)
            elif kind == "unit":
                _section, node_json = window.adapter.find_unit(node_id)
            elif kind == "lesson":
                _section, _unit, node_json = window.adapter.find_lesson(node_id)
            else:
                return
            validate_fn = getattr(window, "_validate_node", None)
            problems = validate_fn(kind, node_json) if validate_fn else []
        except KeyError:
            QMessageBox.warning(window, "无法定位节点", f"找不到节点：{kind}/{node_id}")
            return

        if not problems:
            QMessageBox.information(window, "无需修正", "当前节点没有检测到校验问题。")
            return

        pairs = [(p, (kind, node_id)) for p in problems]
        if hasattr(window, "_on_ai_batch_fix_requested"):
            window._on_ai_batch_fix_requested(pairs)
        else:
            self.run_ai_fix_batch(window, pairs)

    def run_ai_fix_batch(
        self,
        window: Any,
        pairs: list[tuple[dict[str, Any], tuple[str, str] | None]],
    ) -> None:
        """Group problems by node and run AiFixDialog once per node (sequential)."""
        problems = [p for p, _ref in pairs if isinstance(p, dict)]
        fallback: tuple[str, str] | None = None
        for _p, ref in pairs:
            if ref is not None:
                fallback = ref
                break

        batches = group_problems_for_fix(
            problems,
            getattr(window.adapter, "sections", None) or [],
            fallback_ref=fallback,
        )
        if not batches:
            by_ref: dict[tuple[str, str], list[dict[str, Any]]] = {}
            order: list[tuple[str, str]] = []
            for problem, ref in pairs:
                if ref is None or not isinstance(problem, dict):
                    continue
                if ref not in by_ref:
                    by_ref[ref] = []
                    order.append(ref)
                by_ref[ref].append(problem)

            batches = [
                FixBatch(kind=k, node_id=i, problems=by_ref[(k, i)])
                for k, i in order
            ]

        if not batches:
            QMessageBox.information(
                window, "AI 自动修正", "所选问题无法定位到课程节点，请双击跳转后从树菜单修复。"
            )
            return

        if len(batches) > 1:
            QMessageBox.information(
                window,
                "AI 批量修正",
                f"已按节点分成 {len(batches)} 批，将依次修复（每批确认一次）。",
            )

        apply_fn = getattr(window, "_apply_ai_fix_for_node", None)
        if apply_fn is None:
            apply_fn = lambda k, nid, prb: self.apply_ai_fix_for_node(window, k, nid, prb)

        applied = 0
        for batch in batches:
            if apply_fn(batch.kind, batch.node_id, batch.problems):
                applied += 1

        if applied:
            curr_ref = getattr(window, "_current_node_ref", None)
            if curr_ref is not None and hasattr(window, "_on_node_selected"):
                window._on_node_selected(curr_ref)
            if hasattr(window, "statusBar") and window.statusBar():
                window.statusBar().showMessage(
                    f"AI 自动修正已应用 {applied}/{len(batches)} 批，记得保存", 5000
                )

    def apply_ai_fix_for_node(
        self,
        window: Any,
        kind: str,
        node_id: str,
        problems: list[dict[str, Any]],
    ) -> bool:
        """Run one AiFixDialog + merge for a single node. Returns True if applied."""
        from src.dialogs.ai_fix_dialog import AiFixDialog
        from src.dialogs.ai.ai_merge_preview_dialog import AiMergePreviewDialog

        try:
            if kind == "section":
                node_json = window.adapter.find_section(node_id)
            elif kind == "unit":
                _section, node_json = window.adapter.find_unit(node_id)
            elif kind == "lesson":
                _section, _unit, node_json = window.adapter.find_lesson(node_id)
            else:
                return False
        except KeyError:
            QMessageBox.warning(window, "无法定位节点", f"找不到节点：{kind}/{node_id}")
            return False

        vocab = getattr(window.adapter, "vocab", []) or []
        expressions = getattr(window.adapter, "expressions", []) or []
        grammar_points = getattr(window.adapter, "grammar_points", []) or []
        index = getattr(window.adapter, "index", {}) or {}

        course_context = {
            "node_kind": kind,
            "node_id": node_id,
            "language": index.get("language", "en"),
            "existing_resource_ids": {
                "vocab": [w.get("id") for w in vocab if isinstance(w, dict) and w.get("id")],
                "expressions": [e.get("id") for e in expressions if isinstance(e, dict) and e.get("id")],
                "grammar_points": [g.get("id") for g in grammar_points if isinstance(g, dict) and g.get("id")],
            },
        }

        ai_config = getattr(window, "_ai_config", None)
        dlg = AiFixDialog(
            problems,
            node_json,
            course_context,
            ai_config,
            parent=window,
        )
        if dlg.exec() != QDialog.DialogCode.Accepted:
            return False
        corrected = dlg.corrected_node()
        if corrected is None:
            return False

        # Validate the corrected node locally before applying.
        validate_fn = getattr(window, "_validate_node", None)
        post = validate_fn(kind, corrected, check_existing_ids=False) if validate_fn else []
        errors = [p for p in post if isinstance(p, dict) and p.get("level") == "error"]
        if errors:
            detail = "\n".join(f"[{p['level']}] {p['message']}" for p in errors)
            QMessageBox.warning(window, "AI 修正后仍有问题", detail)
            return False

        applied_callback = getattr(window, "_on_ai_edit_applied", None)

        # Apply via undo stack.
        if kind == "section":
            plan = window.adapter.plan_section_merge(node_id, corrected)
            preview = AiMergePreviewDialog(plan, parent=window)
            if preview.exec() != QDialog.DialogCode.Accepted:
                telemetry.record_event(
                    "ai.fix.merge.cancelled",
                    payload={"kind": kind, "node_id": node_id},
                )
                return False
            cmd = MergeAiSectionCommand(window.adapter, preview.plan())
            if applied_callback:
                cmd.signals.changed.connect(applied_callback)
            window.undo_stack.push(cmd)
            if hasattr(window, "tree") and hasattr(window.tree, "select_section"):
                window.tree.select_section(node_id)
        elif kind == "unit":
            section, _ = window.adapter.find_unit(node_id)
            cmd = AiEditUnitCommand(
                window.adapter,
                section.get("id", ""),
                node_id,
                corrected,
                resource_section=corrected,
            )
            if applied_callback:
                cmd.signals.changed.connect(applied_callback)
            window.undo_stack.push(cmd)
            if hasattr(window, "tree") and hasattr(window.tree, "refresh_incremental"):
                window.tree.refresh_incremental()
        elif kind == "lesson":
            cmd = AiEditLessonCommand(
                window.adapter, node_id, corrected, resource_section=corrected
            )
            if applied_callback:
                cmd.signals.changed.connect(applied_callback)
            window.undo_stack.push(cmd)
            if hasattr(window, "tree") and hasattr(window.tree, "refresh_incremental"):
                window.tree.refresh_incremental()
        else:
            return False
        return True
