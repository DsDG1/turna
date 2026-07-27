"""AI edit / batch-fix handlers (E5.1).

Mixin extracted from ``MainWindow`` to thin ``app.py``. Methods keep the same
names and rely on MainWindow attributes (adapter, conflict_guard, tree, …).

No Qt subclassing required — mix into ``MainWindow`` before ``QMainWindow``.
Zero behavior change vs pre-extract implementation.
"""
from __future__ import annotations

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


class AiEditMixin:
    """AI edit (section/unit/lesson) and AI batch-fix handlers."""

    def _validate_node(self, kind: str, node_json: dict, *, check_existing_ids: bool = True) -> list[dict]:
        """Validate a section/unit/lesson node by wrapping it in a temp section."""
        if kind == "section":
            return self.adapter.validate_section_json(node_json, check_existing_ids=check_existing_ids)
        if kind == "unit":
            wrapper = {"id": "temp", "name": "temp", "units": [node_json]}
        elif kind == "lesson":
            wrapper = {"id": "temp", "name": "temp", "units": [{"id": "temp", "lessons": [node_json]}]}
        else:
            return []
        return self.adapter.validate_section_json(wrapper, check_existing_ids=check_existing_ids)

    def _on_ai_edit(self, kind: str, node_id: str) -> None:
        from src.backend.experience.conflict_guard import node_key as make_node_key
        from src.dialogs.ai.node_edit_dialog import NodeAiEditDialog

        telemetry.record_event("ai.edit.open", payload={"kind": kind, "node_id": node_id})
        # M-08: budget / observer gate before any dialog (non-modal deny).
        deny = getattr(self, "_deny_ai_write_if_blocked", None)
        if callable(deny) and deny(label="AI 编辑"):
            return

        self._show_beta_warning_once(
            "ai_beta_warning_shown",
            "AI 编辑课程",
            "AI 编辑结果仅供参考，请作者自行审核。\n\n"
            "本功能会消耗大量 token，且建议模型支持 1M 上下文窗口。\n\n"
            "点击「确定」继续。",
        )

        if not self.course_dir:
            QMessageBox.warning(self, "未加载课程目录", "请先打开课程目录。")
            return

        # C-16: serialize AI write against the target node (dialog lifetime).
        guard_key = make_node_key(kind, node_id)
        job_id = f"edit-{kind}-{node_id}"
        if not self.conflict_guard.try_acquire(guard_key, job_id, label="AI 编辑"):
            if hasattr(self, "experience_metrics"):
                self.experience_metrics.inc_guard("rejected")
            QMessageBox.warning(
                self,
                "AI 编辑",
                f"节点忙碌：{self.conflict_guard.busy_summary()}",
            )
            return
        self._sync_focus_ring()

        new_section = None
        try:
            try:
                if kind == "section":
                    section = self.adapter.find_section(node_id)
                elif kind == "unit":
                    section, _unit = self.adapter.find_unit(node_id)
                elif kind == "lesson":
                    section, _unit, _lesson = self.adapter.find_lesson(node_id)
                else:
                    return
            except KeyError as exc:
                QMessageBox.warning(self, "无法编辑", str(exc))
                return

            edit_mode = {
                "scope": kind,
                "scope_id": node_id,
                "existing_section": section,
            }
            # M5: slim node editor (no monolithic AiGeneratorDialog).
            dlg = NodeAiEditDialog(
                self.adapter,
                edit_mode,
                parent=self,
                ai_config=getattr(self, "_ai_config", None),
                settings_fn=lambda: getattr(self, "_settings_obj", None),
            )
            if not dlg.exec():
                telemetry.record_event("ai.edit.cancelled", payload={"kind": kind})
                return
            try:
                new_section = dlg.section_json()
            except ValueError as exc:
                QMessageBox.warning(self, "无法应用编辑", str(exc))
                return
        finally:
            # C-16: always release dialog hold (cancel / error / success).
            self.conflict_guard.release(guard_key, job_id)
            if hasattr(self, "experience_metrics"):
                self.experience_metrics.inc_guard("released")
            self._sync_focus_ring()

        if new_section is None:
            return

        # Note: hold is released after dialog so merge commands below are free.
        # Concurrent AI on same node is still blocked while the dialog is open.

        # U1-4: section-level apply-time structural guard. Unit/lesson edits
        # intentionally return a *partial* section shell from the model, so a
        # full-section structural_diff would false-positive every time; those
        # scopes keep the dialog-side guard + id-conflict flow instead.
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
                        self,
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
                pass

        sid = section.get("id", "")
        if kind == "section":
            plan = self.adapter.plan_section_merge(sid, new_section)
            from src.dialogs.ai.ai_merge_preview_dialog import AiMergePreviewDialog

            preview = AiMergePreviewDialog(plan, parent=self)
            if preview.exec() != QDialog.DialogCode.Accepted:
                telemetry.record_event("ai.edit.merge.cancelled", payload={"kind": kind, "node_id": node_id})
                return
            cmd = MergeAiSectionCommand(self.adapter, preview.plan())
            cmd.signals.changed.connect(self._on_ai_edit_applied)
            self.undo_stack.push(cmd)
            self.tree.select_section(sid)
        elif kind == "unit":
            new_unit = self._extract_unit(new_section, node_id)
            if new_unit is None:
                # AI did not return a unit with the same id - tolerate it by
                # taking the first unit, then surface it as an id conflict.
                units = new_section.get("units") or []
                if units and isinstance(units[0], dict):
                    new_unit = units[0]
                else:
                    QMessageBox.warning(
                        self, "无法应用编辑", "AI 返回的 JSON 中找不到 unit。"
                    )
                    return
            problems = self._validate_node("unit", new_unit, check_existing_ids=False)
            errors = [p for p in problems if p.get("level") == "error"]
            if errors:
                QMessageBox.warning(self, "AI 编辑校验失败", "\n".join(p["message"] for p in errors))
                return
            conflicts = self._detect_ai_edit_conflicts("unit", node_id, new_unit)
            if conflicts:
                choice = self._ask_ai_edit_conflict_resolution("unit", conflicts)
                if choice == "cancel":
                    return
                if choice == "rename":
                    from src.backend.lesson_content import clone_unit_with_fresh_ids

                    fresh = clone_unit_with_fresh_ids(
                        new_unit, name=f"{new_unit.get('name', '')} 副本"
                    )
                    cmd = AppendUnitCommand(self.adapter, sid, fresh)
                    cmd.signals.changed.connect(self._on_ai_edit_applied)
                    self.undo_stack.push(cmd)
                    self.tree.refresh_incremental()
                    telemetry.record_event(
                        "ai.edit.conflict.rename", payload={"kind": "unit"}
                    )
                    return
                # overwrite: pin the id back to node_id and replace in place.
                new_unit["id"] = node_id
            cmd = AiEditUnitCommand(
                self.adapter, sid, node_id, new_unit, resource_section=new_section
            )
            cmd.signals.changed.connect(self._on_ai_edit_applied)
            self.undo_stack.push(cmd)
            self.tree.refresh_incremental()
        elif kind == "lesson":
            new_lesson = self._extract_lesson(new_section, node_id)
            if new_lesson is None:
                # AI did not return a lesson with the same id - tolerate it by
                # taking the first lesson, then surface it as an id conflict.
                for u in new_section.get("units") or []:
                    if isinstance(u, dict):
                        lessons = u.get("lessons") or []
                        if lessons and isinstance(lessons[0], dict):
                            new_lesson = lessons[0]
                            break
                if new_lesson is None:
                    QMessageBox.warning(
                        self, "无法应用编辑", "AI 返回的 JSON 中找不到 lesson。"
                    )
                    return
            problems = self._validate_node("lesson", new_lesson, check_existing_ids=False)
            errors = [p for p in problems if p.get("level") == "error"]
            if errors:
                QMessageBox.warning(self, "AI 编辑校验失败", "\n".join(p["message"] for p in errors))
                return
            conflicts = self._detect_ai_edit_conflicts("lesson", node_id, new_lesson)
            if conflicts:
                choice = self._ask_ai_edit_conflict_resolution("lesson", conflicts)
                if choice == "cancel":
                    return
                if choice == "rename":
                    from src.backend.lesson_content import clone_lesson_with_fresh_ids

                    fresh = clone_lesson_with_fresh_ids(
                        new_lesson, name=f"{new_lesson.get('name', '')} 副本"
                    )
                    fresh["prerequisiteLessonIds"] = []
                    _ls, _lu, _ll = self.adapter.find_lesson(node_id)
                    cmd = AppendLessonCommand(self.adapter, _lu.get("id", ""), fresh)
                    cmd.signals.changed.connect(self._on_ai_edit_applied)
                    self.undo_stack.push(cmd)
                    self.tree.refresh_incremental()
                    telemetry.record_event(
                        "ai.edit.conflict.rename", payload={"kind": "lesson"}
                    )
                    return
                # overwrite: pin the id back to node_id and replace in place.
                new_lesson["id"] = node_id
            cmd = AiEditLessonCommand(
                self.adapter, node_id, new_lesson, resource_section=new_section
            )
            cmd.signals.changed.connect(self._on_ai_edit_applied)
            self.undo_stack.push(cmd)
            self.tree.refresh_incremental()

        telemetry.record_event("ai.edit.applied", payload={"kind": kind, "node_id": node_id})
        if self._current_node_ref is not None:
            self._on_node_selected(self._current_node_ref)
        self.statusBar().showMessage(
            f"已应用 AI 编辑（{kind}），记得保存", 8000
        )

    def _detect_ai_edit_conflicts(
        self, kind: str, node_id: str, new_node: dict
    ) -> list[tuple[str, str, str]]:
        """Return ``(id_type, id, detail)`` tuples for id conflicts between the
        AI-edited node and the rest of the course.

        A conflict exists when the AI changed the node's own id, or (for a
        unit) a lesson inside the new unit reuses a lesson id that already
        exists elsewhere in the course.
        """
        conflicts: list[tuple[str, str, str]] = []
        new_id = new_node.get("id", "")
        if new_id and new_id != node_id:
            conflicts.append((kind, new_id, f"AI 把 {kind} id 改成了「{new_id}」"))
        if kind == "unit":
            from src.backend.lesson_content import all_lesson_ids

            other_lesson_ids = all_lesson_ids(self.adapter.sections)
            # Exclude lessons currently in the target unit - they get replaced.
            try:
                _s, cur_unit = self.adapter.find_unit(node_id)
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

    def _ask_ai_edit_conflict_resolution(
        self, kind: str, conflicts: list[tuple[str, str, str]]
    ) -> str:
        """Ask the user how to resolve an AI-edit id conflict.

        Returns ``"overwrite"``, ``"rename"`` or ``"cancel"``.
        """
        detail = "\n".join(f"· {c[2]}" for c in conflicts)
        msg = QMessageBox(self)
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

    def _on_ai_fix_from_tree(self, kind: str, node_id: str) -> None:
        """Handle AI fix request from the course tree context menu."""
        # Validate the node to collect concrete problems for the prompt.
        try:
            if kind == "section":
                node_json = self.adapter.find_section(node_id)
            elif kind == "unit":
                section, node_json = self.adapter.find_unit(node_id)
            elif kind == "lesson":
                _section, _unit, node_json = self.adapter.find_lesson(node_id)
            else:
                return
            problems = self._validate_node(kind, node_json)
        except KeyError:
            QMessageBox.warning(self, "无法定位节点", f"找不到节点：{kind}/{node_id}")
            return
        if not problems:
            QMessageBox.information(self, "无需修正", "当前节点没有检测到校验问题。")
            return
        # U1-2: pass *all* problems on this node (not only the first).
        pairs = [(p, (kind, node_id)) for p in problems]
        self._on_ai_batch_fix_requested(pairs)

    @staticmethod
    def _extract_unit(new_section: dict, unit_id: str) -> dict | None:
        for u in new_section.get("units") or []:
            if isinstance(u, dict) and u.get("id") == unit_id:
                return u
        return None

    @staticmethod
    def _extract_lesson(new_section: dict, lesson_id: str) -> dict | None:
        for u in new_section.get("units") or []:
            if not isinstance(u, dict):
                continue
            for l in u.get("lessons") or []:
                if isinstance(l, dict) and l.get("id") == lesson_id:
                    return l
        return None

    def _on_ai_fix_requested(
        self, problem: dict[str, Any], node_ref: tuple[str, str] | None
    ) -> None:
        """Handle single AI auto-fix request (legacy signal)."""
        if node_ref is None:
            return
        self._run_ai_fix_batch([(problem, node_ref)])

    def _on_ai_fix_single(
        self, problem: dict[str, Any], node_ref: tuple[str, str] | None
    ) -> None:
        """K-15: per-row single-error fix from ValidationReport context menu.

        Same machine as the batch path (``_run_ai_fix_batch`` →
        ``_apply_ai_fix_for_node`` → ``AiFixDialog`` 1-item checkable list →
        undo), but tagged ``granularity="single"`` for timeline / telemetry so
        single-error fixes are distinguishable from multi-select batches.
        """
        if node_ref is None:
            return
        self._ai_fix_granularity = "single"
        try:
            self._run_ai_fix_batch([(problem, node_ref)])
        finally:
            self._ai_fix_granularity = "batch"

    def _on_ai_batch_fix_requested(self, pairs: list) -> None:
        """Handle multi-select AI fix from ValidationReport (U1-2)."""
        if not pairs:
            return
        self._run_ai_fix_batch(list(pairs))

    def _run_ai_fix_batch(
        self,
        pairs: list[tuple[dict[str, Any], tuple[str, str] | None]],
    ) -> None:
        """Group problems by node and run AiFixDialog once per node (sequential)."""
        from src.backend.ai_fix_batch import group_problems_for_fix

        deny = getattr(self, "_deny_ai_write_if_blocked", None)
        if callable(deny) and deny(label="AI 批修"):
            return

        problems = [p for p, _ref in pairs if isinstance(p, dict)]
        # Prefer explicit refs from the UI when path mapping fails.
        fallback: tuple[str, str] | None = None
        for _p, ref in pairs:
            if ref is not None:
                fallback = ref
                break
        batches = group_problems_for_fix(
            problems,
            getattr(self.adapter, "sections", None) or [],
            fallback_ref=fallback,
        )
        if not batches:
            # Fall back: group by provided node_ref pairs.
            by_ref: dict[tuple[str, str], list[dict[str, Any]]] = {}
            order: list[tuple[str, str]] = []
            for problem, ref in pairs:
                if ref is None or not isinstance(problem, dict):
                    continue
                if ref not in by_ref:
                    by_ref[ref] = []
                    order.append(ref)
                by_ref[ref].append(problem)
            from src.backend.ai_fix_batch import FixBatch

            batches = [
                FixBatch(kind=k, node_id=i, problems=by_ref[(k, i)])
                for k, i in order
            ]
        if not batches:
            QMessageBox.information(
                self, "AI 自动修正", "所选问题无法定位到课程节点，请双击跳转后从树菜单修复。"
            )
            return
        if len(batches) > 1:
            QMessageBox.information(
                self,
                "AI 批量修正",
                f"已按节点分成 {len(batches)} 批，将依次修复（每批确认一次）。",
            )
        applied = 0
        for batch in batches:
            if self._apply_ai_fix_for_node(
                batch.kind, batch.node_id, batch.problems
            ):
                applied += 1
        if applied:
            if self._current_node_ref is not None:
                self._on_node_selected(self._current_node_ref)
            granularity = getattr(self, "_ai_fix_granularity", "batch")
            kind_label = "单错" if granularity == "single" else "批"
            self._record_experience_event(
                "ai_fix_single" if granularity == "single" else "validate.fix",
                f"AI {kind_label}修已应用 {applied}/{len(batches)} 批",
                action_id="validate.open_and_fix",
                scope={"granularity": granularity, "batches": len(batches)},
            )
            # O-05: re-validate so Dock error counts refresh without a second click.
            self._refresh_validate_after_ai(
                f"AI 自动修正已应用 {applied}/{len(batches)} 批，记得保存"
            )

    def _apply_ai_fix_for_node(
        self,
        kind: str,
        node_id: str,
        problems: list[dict[str, Any]],
    ) -> bool:
        """Run one AiFixDialog + merge for a single node. Returns True if applied.

        C-16: holds ConflictGuard for the whole dialog/merge path; always
        releases in ``finally`` (cancel / error / success).
        """
        from src.backend.experience.conflict_guard import node_key as make_node_key

        guard_key = make_node_key(kind, node_id)
        job_id = f"fix-{kind}-{node_id}"
        if not self.conflict_guard.try_acquire(guard_key, job_id, label="AI 批修"):
            if hasattr(self, "experience_metrics"):
                self.experience_metrics.inc_guard("rejected")
            QMessageBox.warning(
                self,
                "AI 批修",
                f"节点忙碌：{self.conflict_guard.busy_summary()}",
            )
            return False
        self._sync_focus_ring()
        try:
            try:
                if kind == "section":
                    node_json = self.adapter.find_section(node_id)
                elif kind == "unit":
                    _section, node_json = self.adapter.find_unit(node_id)
                elif kind == "lesson":
                    _section, _unit, node_json = self.adapter.find_lesson(node_id)
                else:
                    return False
            except KeyError:
                QMessageBox.warning(
                    self, "无法定位节点", f"找不到节点：{kind}/{node_id}"
                )
                return False

            course_context = {
                "node_kind": kind,
                "node_id": node_id,
                "language": self.adapter.index.get("language", "en"),
                "existing_resource_ids": {
                    "vocab": [w.get("id") for w in self.adapter.vocab if w.get("id")],
                    "expressions": [
                        e.get("id") for e in self.adapter.expressions if e.get("id")
                    ],
                    "grammar_points": [
                        g.get("id") for g in self.adapter.grammar_points if g.get("id")
                    ],
                },
            }
            from src.dialogs.ai_fix_dialog import AiFixDialog

            dlg = AiFixDialog(
                problems,
                node_json,
                course_context,
                self._ai_config,
                parent=self,
                settings_fn=lambda: getattr(self, "_settings_obj", None),
            )
            if dlg.exec() != QDialog.DialogCode.Accepted:
                return False
            corrected = dlg.corrected_node()
            if corrected is None:
                return False

            # Validate the corrected node locally before applying.
            post = self._validate_node(kind, corrected, check_existing_ids=False)
            errors = [p for p in post if p.get("level") == "error"]
            if errors:
                detail = "\n".join(f"[{p['level']}] {p['message']}" for p in errors)
                QMessageBox.warning(self, "AI 修正后仍有问题", detail)
                return False

            # Apply via undo stack.
            if kind == "section":
                plan = self.adapter.plan_section_merge(node_id, corrected)
                from src.dialogs.ai.ai_merge_preview_dialog import AiMergePreviewDialog

                preview = AiMergePreviewDialog(plan, parent=self)
                if preview.exec() != QDialog.DialogCode.Accepted:
                    telemetry.record_event(
                        "ai.fix.merge.cancelled",
                        payload={"kind": kind, "node_id": node_id},
                    )
                    return False
                cmd = MergeAiSectionCommand(self.adapter, preview.plan())
                cmd.signals.changed.connect(self._on_ai_edit_applied)
                self.undo_stack.push(cmd)
                self.tree.select_section(node_id)
            elif kind == "unit":
                section, _ = self.adapter.find_unit(node_id)
                cmd = AiEditUnitCommand(
                    self.adapter,
                    section.get("id", ""),
                    node_id,
                    corrected,
                    resource_section=corrected,
                )
                cmd.signals.changed.connect(self._on_ai_edit_applied)
                self.undo_stack.push(cmd)
                self.tree.refresh_incremental()
            elif kind == "lesson":
                cmd = AiEditLessonCommand(
                    self.adapter, node_id, corrected, resource_section=corrected
                )
                cmd.signals.changed.connect(self._on_ai_edit_applied)
                self.undo_stack.push(cmd)
                self.tree.refresh_incremental()
            else:
                return False
            return True
        finally:
            self.conflict_guard.release(guard_key, job_id)
            if hasattr(self, "experience_metrics"):
                self.experience_metrics.inc_guard("released")
            self._sync_focus_ring()
