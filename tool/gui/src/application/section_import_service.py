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
            section = dict(section)
            section["id"] = new_id
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

        added = self.adapter.detect_changes()
        if added.get("vocab") or added.get("expressions") or added.get("grammar_points"):
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
