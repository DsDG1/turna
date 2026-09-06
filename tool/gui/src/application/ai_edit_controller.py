"""AI Edit Controller (Phase 3).

Orchestrates the AI course section/unit/lesson edit workflow,
conflict detection, conflict resolution UI, and command submission.
Extracted from MainWindow (src/app.py) to achieve clean separation of concerns.

Rule: Never import from src.app!
"""
from __future__ import annotations

import logging
from typing import Any

from PySide6.QtWidgets import QDialog, QMessageBox

from src.application.commands import (
    AiEditLessonCommand,
    AiEditUnitCommand,
    AppendLessonCommand,
    AppendUnitCommand,
    MergeAiSectionCommand,
)
from src.infrastructure.telemetry import telemetry

logger = logging.getLogger(__name__)


class AiEditController:
    """Controller for AI-assisted editing of section, unit, or lesson nodes."""

    @staticmethod
    def extract_unit(new_section: dict, unit_id: str) -> dict | None:
        """Find a unit by ID inside a section dictionary."""
        for u in new_section.get("units") or []:
            if isinstance(u, dict) and u.get("id") == unit_id:
                return u
        return None

    @staticmethod
    def extract_lesson(new_section: dict, lesson_id: str) -> dict | None:
        """Find a lesson by ID inside a section dictionary."""
        for u in new_section.get("units") or []:
            if not isinstance(u, dict):
                continue
            for l in u.get("lessons") or []:
                if isinstance(l, dict) and l.get("id") == lesson_id:
                    return l
        return None

    @staticmethod
    def detect_conflicts(
        adapter: Any, kind: str, node_id: str, new_node: dict
    ) -> list[tuple[str, str, str]]:
        """Return ``(id_type, id, detail)`` tuples for id conflicts between the
        AI-edited node and the rest of the course.
        """
        conflicts: list[tuple[str, str, str]] = []
        new_id = new_node.get("id", "")
        if new_id and new_id != node_id:
            conflicts.append((kind, new_id, f"AI 把 {kind} id 改成了「{new_id}」"))
        if kind == "unit":
            from src.backend.lesson_content import all_lesson_ids

            sections = getattr(adapter, "sections", None) or []
            other_lesson_ids = all_lesson_ids(sections)
            # Exclude lessons currently in the target unit - they get replaced.
            try:
                _s, cur_unit = adapter.find_unit(node_id)
                cur_lesson_ids = {l.get("id") for l in cur_unit.get("lessons", [])}
            except KeyError:
                cur_lesson_ids = set()
            other_lesson_ids -= cur_lesson_ids
            for lesson in new_node.get("lessons", []):
                if not isinstance(lesson, dict):
                    continue
                lid = lesson.get("id", "")
                if lid and lid in other_lesson_ids:
                    conflicts.append(
                        ("lesson", lid, f"lesson id「{lid}」与课程其他位置冲突")
                    )
        return conflicts

    @staticmethod
    def ask_conflict_resolution(
        parent: Any, kind: str, conflicts: list[tuple[str, str, str]]
    ) -> str:
        """Ask the user how to resolve an AI-edit id conflict.

        Returns ``"overwrite"``, ``"rename"`` or ``"cancel"``.
        """
        detail = "\n".join(f"· {c[2]}" for c in conflicts)
        msg = QMessageBox(parent)
        msg.setWindowTitle("ID 冲突")
        msg.setIcon(QMessageBox.Icon.Warning)
        msg.setText(f"AI 编辑的 {kind} 存在 id 冲突：\n\n{detail}")
        msg.setInformativeText(
            "覆盖：用 AI 内容替换原节点（保留原 id；unit 内子课时冲突仍可能导致保存时报错）\n"
            "重命名追加：生成新 id 作为新节点追加到同级（原节点保留，避免冲突）\n"
            "取消：放弃本次编辑"
        )
        overwrite = msg.addButton("覆盖", QMessageBox.ButtonRole.AcceptRole)
        rename = msg.addButton("重命名追加", QMessageBox.ButtonRole.ActionRole)
        msg.addButton("取消", QMessageBox.ButtonRole.RejectRole)
        msg.exec()
        clicked = msg.clickedButton()
        if clicked == overwrite:
            return "overwrite"
        if clicked == rename:
            return "rename"
        return "cancel"

    def handle_ai_edit(self, window: Any, kind: str, node_id: str) -> None:
        """Main flow for AI edit triggered from tree or commands."""
        from src.dialogs.ai.node_edit_dialog import NodeAiEditDialog

        telemetry.record_event("ai.edit.open", payload={"kind": kind, "node_id": node_id})
        if hasattr(window, "_show_beta_warning_once"):
            window._show_beta_warning_once(
                "ai_beta_warning_shown",
                "AI 编辑课程",
                "AI 编辑结果仅供参考，请作者自行审核。\n\n"
                "本功能会消耗大量 token，且建议模型支持 1M 上下文窗口。\n\n"
                "点击「确定」继续。",
            )

        if not getattr(window, "course_dir", None):
            QMessageBox.warning(window, "未加载课程目录", "请先打开课程目录。")
            return

        adapter = window.adapter
        try:
            if kind == "section":
                section = adapter.find_section(node_id)
            elif kind == "unit":
                section, _unit = adapter.find_unit(node_id)
            elif kind == "lesson":
                section, _unit, _lesson = adapter.find_lesson(node_id)
            else:
                return
        except KeyError as exc:
            QMessageBox.warning(window, "无法编辑", str(exc))
            return

        dlg = NodeAiEditDialog(
            adapter,
            window,
            scope=kind,
            scope_id=node_id,
            existing_section=section,
        )
        if not dlg.exec():
            telemetry.record_event("ai.edit.cancelled", payload={"kind": kind})
            return
        try:
            new_section = dlg.section_json()
        except ValueError as exc:
            QMessageBox.warning(window, "无法应用编辑", str(exc))
            return

        # U1-4: section-level apply-time structural guard.
        if kind == "section":
            try:
                from src.backend.ai_generator import structural_diff

                diff = structural_diff(section, new_section)
                removed = {
                    k: v
                    for k, v in diff.items()
                    if str(k).startswith("removed_") and v
                }
                if removed:
                    parts = [
                        f"{k}: {', '.join(sorted(list(v))[:6])}"
                        for k, v in removed.items()
                    ]
                    reply = QMessageBox.question(
                        window,
                        "结构保护",
                        "应用前检测到删除：\n"
                        + "\n".join(parts)
                        + "\n\n建议改用局部重生成 / 教师改题。是否仍继续应用？",
                        QMessageBox.StandardButton.Yes
                        | QMessageBox.StandardButton.No,
                        QMessageBox.StandardButton.No,
                    )
                    if reply != QMessageBox.StandardButton.Yes:
                        return
            except Exception:
                logger.debug("AiEditController.handle_ai_edit structural guard failed", exc_info=True)

        sid = section.get("id", "")
        on_applied = getattr(window, "_on_ai_edit_applied", None)

        if kind == "section":
            plan = adapter.plan_section_merge(sid, new_section)
            from src.dialogs.ai.ai_merge_preview_dialog import AiMergePreviewDialog

            preview = AiMergePreviewDialog(plan, parent=window)
            if preview.exec() != QDialog.DialogCode.Accepted:
                telemetry.record_event(
                    "ai.edit.merge.cancelled", payload={"kind": kind, "node_id": node_id}
                )
                return
            cmd = MergeAiSectionCommand(adapter, preview.plan())
            if on_applied:
                cmd.signals.changed.connect(on_applied)
            window.undo_stack.push(cmd)
            window.tree.select_section(sid)

        elif kind == "unit":
            new_unit = self.extract_unit(new_section, node_id)
            if new_unit is None:
                units = new_section.get("units") or []
                if units and isinstance(units[0], dict):
                    new_unit = units[0]
                else:
                    QMessageBox.warning(
                        window, "无法应用编辑", "AI 返回的 JSON 中找不到 unit。"
                    )
                    return
            problems = window._validate_node("unit", new_unit, check_existing_ids=False)
            errors = [p for p in problems if p.get("level") == "error"]
            if errors:
                QMessageBox.warning(window, "AI 编辑校验失败", "\n".join(p["message"] for p in errors))
                return
            if hasattr(window, "_detect_ai_edit_conflicts"):
                conflicts = window._detect_ai_edit_conflicts("unit", node_id, new_unit)
            else:
                conflicts = self.detect_conflicts(adapter, "unit", node_id, new_unit)
            if conflicts:
                if hasattr(window, "_ask_ai_edit_conflict_resolution"):
                    choice = window._ask_ai_edit_conflict_resolution("unit", conflicts)
                else:
                    choice = self.ask_conflict_resolution(window, "unit", conflicts)
                if choice == "cancel":
                    return
                if choice == "rename":
                    from src.backend.lesson_content import clone_unit_with_fresh_ids

                    fresh = clone_unit_with_fresh_ids(
                        new_unit, name=f"{new_unit.get('name', '')} 副本"
                    )
                    cmd = AppendUnitCommand(adapter, sid, fresh)
                    if on_applied:
                        cmd.signals.changed.connect(on_applied)
                    window.undo_stack.push(cmd)
                    window.tree.refresh_incremental()
                    telemetry.record_event(
                        "ai.edit.conflict.rename", payload={"kind": "unit"}
                    )
                    return
                new_unit["id"] = node_id
            cmd = AiEditUnitCommand(
                adapter, sid, node_id, new_unit, resource_section=new_section
            )
            if on_applied:
                cmd.signals.changed.connect(on_applied)
            window.undo_stack.push(cmd)
            window.tree.refresh_incremental()

        elif kind == "lesson":
            new_lesson = self.extract_lesson(new_section, node_id)
            if new_lesson is None:
                for u in new_section.get("units") or []:
                    if isinstance(u, dict):
                        lessons = u.get("lessons") or []
                        if lessons and isinstance(lessons[0], dict):
                            new_lesson = lessons[0]
                            break
                if new_lesson is None:
                    QMessageBox.warning(
                        window, "无法应用编辑", "AI 返回的 JSON 中找不到 lesson。"
                    )
                    return
            problems = window._validate_node("lesson", new_lesson, check_existing_ids=False)
            errors = [p for p in problems if p.get("level") == "error"]
            if errors:
                QMessageBox.warning(window, "AI 编辑校验失败", "\n".join(p["message"] for p in errors))
                return
            if hasattr(window, "_detect_ai_edit_conflicts"):
                conflicts = window._detect_ai_edit_conflicts("lesson", node_id, new_lesson)
            else:
                conflicts = self.detect_conflicts(adapter, "lesson", node_id, new_lesson)
            if conflicts:
                if hasattr(window, "_ask_ai_edit_conflict_resolution"):
                    choice = window._ask_ai_edit_conflict_resolution("lesson", conflicts)
                else:
                    choice = self.ask_conflict_resolution(window, "lesson", conflicts)
                if choice == "cancel":
                    return
                if choice == "rename":
                    from src.backend.lesson_content import clone_lesson_with_fresh_ids

                    fresh = clone_lesson_with_fresh_ids(
                        new_lesson, name=f"{new_lesson.get('name', '')} 副本"
                    )
                    fresh["prerequisiteLessonIds"] = []
                    _ls, _lu, _ll = adapter.find_lesson(node_id)
                    cmd = AppendLessonCommand(adapter, _lu.get("id", ""), fresh)
                    if on_applied:
                        cmd.signals.changed.connect(on_applied)
                    window.undo_stack.push(cmd)
                    window.tree.refresh_incremental()
                    telemetry.record_event(
                        "ai.edit.conflict.rename", payload={"kind": "lesson"}
                    )
                    return
                new_lesson["id"] = node_id
            cmd = AiEditLessonCommand(
                adapter, node_id, new_lesson, resource_section=new_section
            )
            if on_applied:
                cmd.signals.changed.connect(on_applied)
            window.undo_stack.push(cmd)
            window.tree.refresh_incremental()

        telemetry.record_event("ai.edit.applied", payload={"kind": kind, "node_id": node_id})
        current_ref = getattr(window, "_current_node_ref", None)
        if current_ref is not None and hasattr(window, "_on_node_selected"):
            window._on_node_selected(current_ref)
        if hasattr(window, "statusBar"):
            window.statusBar().showMessage(f"已应用 AI 编辑（{kind}），记得保存", 8000)
