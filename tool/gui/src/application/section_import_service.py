"""Orchestration of section imports into a ``CourseAdapter`` (connectplan P1-2).

Extracted from ``MainWindow._import_section_dict_result`` /
``_on_textbook_sections`` so the textbook-import, AI-generation, and (later)
workshop-design flows share one import pipeline. UI concerns are injected as
callbacks, keeping the service testable without a MainWindow:

- ``show_error`` / ``show_info``: message display (QMessageBox in production).
- ``merge_resolver``: decide one merge plan interactively (None → cancel).
- ``bulk_merge_resolver``: decide many merge plans at once (D7); returning
  None cancels all merges, per-plan None skips that section.
- ``on_command_pushed``: fired after each undo-command push (MainWindow uses
  it to connect change signals and select the section in the tree).
- ``on_status``: transient status text (status bar in production).
"""
from __future__ import annotations

import copy
from typing import Any, Callable

from src.application.commands import (
    AiEditSectionCommand,
    ImportAiSectionCommand,
    MergeAiSectionCommand,
)
from src.backend.course_adapter import CourseAdapter, SectionMergePlan
from src.backend.import_step_result import ImportStepResult
from src.backend.import_strategy import (
    ImportStrategy,
    plan_bulk_import,
    resolve_action,
    unique_section_id,
)
from src.backend.textbook_to_course import rewrite_ids_deterministic
from src.infrastructure.telemetry import telemetry

#: Sentinel for "no pre-resolved merge decision was supplied" — distinct from
#: ``None`` which means "the bulk resolver said skip this section".
_UNSET = object()


class SectionImportService:
    """Shared section-import pipeline for all section-producing features."""

    def __init__(
        self,
        adapter: CourseAdapter | None,
        undo_stack: Any,
        *,
        adapter_fn: Callable[[], CourseAdapter] | None = None,
        show_error: Callable[[str, str], None] | None = None,
        show_info: Callable[[str, str], None] | None = None,
        merge_resolver: Callable[[SectionMergePlan], SectionMergePlan | None] | None = None,
        bulk_merge_resolver: Callable[
            [list[SectionMergePlan]], list[SectionMergePlan | None] | None
        ]
        | None = None,
        on_command_pushed: Callable[[Any, str], None] | None = None,
        on_status: Callable[[str], None] | None = None,
    ) -> None:
        self._adapter = adapter
        self._adapter_fn = adapter_fn
        self.undo_stack = undo_stack
        self._show_error = show_error or (lambda _t, _m: None)
        self._show_info = show_info or (lambda _t, _m: None)
        self._merge_resolver = merge_resolver
        self._bulk_merge_resolver = bulk_merge_resolver
        self._on_command_pushed = on_command_pushed or (lambda _cmd, _sid: None)
        self._on_status = on_status or (lambda _msg: None)

    @property
    def adapter(self) -> CourseAdapter:
        """The current adapter. ``adapter_fn`` (if given) lets hosts swap the
        adapter instance after construction (e.g. tests, course reload)."""
        if self._adapter_fn is not None:
            return self._adapter_fn()
        return self._adapter

    # ------------------------------------------------------------------ single
    def import_section(
        self,
        section: dict,
        *,
        strategy: str = ImportStrategy.MERGE.value,
        _merge_decision: Any = _UNSET,
    ) -> ImportStepResult:
        """Import one section dict via undo commands.

        Returns an ``ImportStepResult`` whose ``details["outcome"]`` is one of
        ``imported`` / ``merged`` / ``replaced`` / ``skipped`` / ``blocked``
        and whose ``details["section_id"]`` is the final id (rewritten when
        ``append_as_new`` fires).
        """
        sid = section.get("id") or ""
        if not sid:
            self._show_error("缺少 section id", "生成的 JSON 缺少顶层 id 字段。")
            return ImportStepResult.error(
                "import", "缺少 section id", details={"outcome": "blocked"}
            )

        # Format-only validation: the AI may intentionally reuse existing ids.
        problems = self.adapter.validate_section_json(section, check_existing_ids=False)
        errors = [p for p in problems if p["level"] == "error"]
        warnings = [p for p in problems if p["level"] == "warning"]
        if errors:
            detail = "\n".join(f"[{p['level']}] {p['message']}" for p in errors)
            self._show_error("AI section 校验失败", detail)
            return ImportStepResult.error(
                "import", "校验失败", details={"outcome": "blocked", "errors": errors}
            )
        if warnings:
            detail = "\n".join(f"[{p['level']}] {p['message']}" for p in warnings)
            self._show_info("AI section 导入警告", f"存在警告，但仍可导入：\n\n{detail}")

        existing_ids = {s.get("id") for s in self.adapter.sections}
        existing_index_ids = {
            e.get("id") for e in self.adapter.index.get("sections", [])
        }
        exists = sid in existing_ids or sid in existing_index_ids
        action = resolve_action(exists, strategy)

        if action == "skip":
            self._on_status(f"已跳过「{section.get('name', sid)}」（同 id section 已存在）")
            return ImportStepResult.success(
                "import",
                message="跳过已存在 section",
                details={"outcome": "skipped", "section_id": sid},
            )

        if action == "replace":
            cmd = AiEditSectionCommand(self.adapter, sid, section, resource_section=section)
            self.undo_stack.push(cmd)
            self._on_command_pushed(cmd, sid)
            self._on_status(f"已覆盖「{section.get('name', sid)}」，记得保存")
            outcome = "replaced"
        elif action == "append_new":
            new_id = unique_section_id(self.adapter, sid)
            # Deep copy + rewrite every nested id: unit/lesson ids are derived
            # from the section id, so keeping the originals would collide with
            # the existing section and make the course fail validation on save.
            section = copy.deepcopy(section)
            section["id"] = new_id
            rewrite_ids_deterministic(section, new_id)
            section.setdefault("prerequisiteSectionIds", [])
            cmd = ImportAiSectionCommand(self.adapter, section)
            self.undo_stack.push(cmd)
            self._on_command_pushed(cmd, new_id)
            self._on_status(
                f"已作为新 section「{new_id}」导入（原 id {sid} 已存在），记得保存"
            )
            sid = new_id
            outcome = "imported"
        elif action == "merge":
            plan = _merge_decision
            if plan is _UNSET:
                planned = self.adapter.plan_section_merge(sid, section)
                if self._merge_resolver is None:
                    return ImportStepResult(
                        step="import",
                        outcome="cancelled",
                        message="没有可用的合并决策器",
                        details={"outcome": "skipped", "section_id": sid},
                    )
                plan = self._merge_resolver(planned)
            if plan is None:
                return ImportStepResult(
                    step="import",
                    outcome="cancelled",
                    message="用户取消了合并预览",
                    details={"outcome": "skipped", "section_id": sid},
                )
            cmd = MergeAiSectionCommand(self.adapter, plan)
            self.undo_stack.push(cmd)
            self._on_command_pushed(cmd, sid)
            self._on_status(f"已将 AI 生成内容合并到「{section.get('name', sid)}」，记得保存")
            outcome = "merged"
        else:  # "append" - brand new section
            section.setdefault("prerequisiteSectionIds", [])
            cmd = ImportAiSectionCommand(self.adapter, section)
            self.undo_stack.push(cmd)
            self._on_command_pushed(cmd, sid)
            self._on_status(f"已通过 AI 生成课程「{section.get('name', sid)}」并已选中，记得保存")
            outcome = "imported"

        # Use the deltas the command already recorded during redo() instead of
        # re-hashing the whole course via detect_changes() per section.
        if cmd.added_vocab_ids or cmd.added_expression_ids or cmd.added_grammar_ids:
            self._on_status("（资源已合并到词库/表达/语法，记得保存）")
        return ImportStepResult.success(
            "import",
            message=f"section {outcome}",
            details={"outcome": outcome, "section_id": sid},
        )

    # ------------------------------------------------------------------ bulk
    def import_bulk(
        self,
        sections: list[dict],
        *,
        strategy: str = ImportStrategy.MERGE.value,
    ) -> tuple[list[ImportStepResult], dict[str, int]]:
        """Import many sections, returning per-section results and counts.

        Under the interactive ``merge`` strategy, colliding sections are first
        resolved in one batch via ``bulk_merge_resolver`` (when more than one
        collision exists); a section the resolver maps to None is skipped,
        and without a bulk resolver each section falls back to the per-section
        ``merge_resolver``. Each result's details carry ``source_id`` (the id
        before any ``append_as_new`` rewrite) for ``import_map`` bookkeeping.
        """
        plans = plan_bulk_import(sections, self.adapter, strategy)
        counts = {"imported": 0, "merged": 0, "replaced": 0, "skipped": 0, "blocked": 0}

        # Pre-resolve interactive merges in one shot (D7).
        merge_decisions: dict[int, SectionMergePlan | None] = {}
        merge_candidates: list[tuple[int, SectionMergePlan]] = []
        if strategy == ImportStrategy.MERGE.value:
            for i, (section, plan) in enumerate(zip(sections, plans)):
                if plan.action == "merge":
                    merge_candidates.append(
                        (i, self.adapter.plan_section_merge(plan.target_id, section))
                    )
            if len(merge_candidates) > 1 and self._bulk_merge_resolver is not None:
                resolved = self._bulk_merge_resolver([p for _, p in merge_candidates])
                if resolved is None:
                    # Whole-batch cancel → every merge candidate skipped.
                    for i, _ in merge_candidates:
                        merge_decisions[i] = None
                else:
                    for (i, _), decision in zip(merge_candidates, resolved):
                        merge_decisions[i] = decision

        results: list[ImportStepResult] = []
        for i, (section, plan) in enumerate(zip(sections, plans)):
            source_id = section.get("id", "")
            # For append_as_new, use the planned target id so the section is
            # imported under the non-colliding id the preview promised.
            if plan.action == "append_new" and plan.target_id != source_id:
                section = dict(section)
                section["id"] = plan.target_id
            decision = merge_decisions.get(i, _UNSET)
            result = self.import_section(
                section, strategy=strategy, _merge_decision=decision
            )
            details = result.details or {}
            details["source_id"] = source_id
            result.details = details
            outcome = details.get("outcome", "blocked")
            counts[outcome] = counts.get(outcome, 0) + 1
            sid = details.get("section_id", source_id)
            if outcome == "imported":
                telemetry.record_event(
                    "textbook.import.imported", payload={"section_id": sid}
                )
            elif outcome == "merged":
                telemetry.record_event(
                    "textbook.import.merged", payload={"section_id": sid}
                )
            elif outcome == "replaced":
                telemetry.record_event(
                    "textbook.import.replaced", payload={"section_id": sid}
                )
            elif outcome == "skipped":
                telemetry.record_event(
                    "textbook.import.merge.cancelled", payload={"section_id": sid}
                )
            results.append(result)
        return results, counts


# --- Host-coupled builder (moved from src/app.py, P2-A) ---


def build_import_service(host):
    """Build the shared section-import pipeline with UI callbacks wired."""
    from src.application.section_import_service import SectionImportService

    def _merge_resolver(plan):
        from src.dialogs.ai.ai_merge_preview_dialog import AiMergePreviewDialog

        preview = AiMergePreviewDialog(plan, parent=host)
        if preview.exec() != QDialog.DialogCode.Accepted:
            return None
        return preview.plan()

    def _bulk_merge_resolver(plans):
        from src.widgets.bulk_merge_resolve_panel import BulkMergeResolveDialog

        return BulkMergeResolveDialog.resolve(plans, parent=host)

    def _on_status(msg: str) -> None:
        # Resource notes are suffixes to the action message, not replacements.
        if msg.startswith("（"):
            host.statusBar().showMessage(
                host.statusBar().currentMessage() + msg, 8000
            )
        else:
            host.statusBar().showMessage(msg, 8000)

    return SectionImportService(
        None,
        host.undo_stack,
        adapter_fn=lambda: host.adapter,
        show_error=lambda title, msg: QMessageBox.warning(host, title, msg),
        show_info=lambda title, msg: QMessageBox.information(host, title, msg),
        merge_resolver=_merge_resolver,
        bulk_merge_resolver=_bulk_merge_resolver,
        on_command_pushed=host._on_import_command_pushed,
        on_status=_on_status,
    )
