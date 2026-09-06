"""Fill / listening / validate-and-fix skill implementations (M7)."""
from __future__ import annotations

from typing import Any

from PySide6.QtWidgets import QDialog, QMessageBox

from src.application.commands import MergeAiSectionCommand
from src.application.ui_guard import safe_information, safe_question, safe_warning
from src.infrastructure.telemetry import telemetry

def _experience_validate_and_fix(host) -> None:
    """E1: validate locally; errors go straight into the AI batch-fix flow."""
    problems = host._run_local_validate()
    if problems is None:
        return
    errors = [p for p in problems if p.get("level") == "error"]
    if not errors:
        host.statusBar().showMessage("校验通过：无 error", 4000)
        if problems:
            host._show_validation_report(problems, title="校验结果（体验副驾驶）")
        return
    from src.backend.ai_fix_batch import selected_problems_with_refs

    pairs = selected_problems_with_refs(
        errors, getattr(host.adapter, "sections", None) or []
    )
    # _run_ai_fix_batch 内部逐批 AiFixDialog 预览，仍需人确认每批。
    host._run_ai_fix_batch(pairs)

handle_validate_and_fix = _experience_validate_and_fix

def _experience_fill_empty(host, scope: dict) -> None:
    """E1 / T-03: fill empty lesson via LessonPatch (P10), not helper dialog.

    Worker generates on a section deepcopy (``regenerate_lesson_in_section``);
    human confirms once via SectionDiffView; apply uses
    ``ApplyLessonPatchCommand`` so undo restores the empty shell.

    Failure / precondition paths use **statusBar only** (no modal
    QMessageBox) so headless tests never hang waiting for OK. Incomplete
    AI config falls back to ``_on_ai_edit`` (settings / legacy dialog).
    """
    first = str(scope.get("first_lesson_id") or "")
    if not first:
        host.statusBar().showMessage("没有可填充的空课", 4000)
        return
    extra_ids = [
        str(x)
        for x in (scope.get("lesson_ids") or scope.get("empty_lesson_ids") or [])
        if str(x) and str(x) != first
    ]
    host.tree.select_lesson(first)
    if not host.course_dir:
        # Non-modal: never QMessageBox here (offscreen tests hang on modal).
        host.statusBar().showMessage("请先打开课程目录", 4000)
        return
    deny = getattr(host, "_deny_ai_write_if_blocked", None)
    if callable(deny) and deny(label="填充空课"):
        return
    config = getattr(host, "_ai_config", None)
    if config is None or not getattr(config, "is_complete", False):
        # No key: keep legacy dialog path so author can still open settings.
        host._on_ai_edit("lesson", first)
        return
    if host.job_tray.is_busy_ai():
        host.statusBar().showMessage("当前有 AI 任务进行中，请稍候", 4000)
        return
    try:
        section, _unit, _lesson = host.adapter.find_lesson(first)
    except KeyError as exc:
        host.statusBar().showMessage(f"填充空课失败：{exc}", 5000)
        return
    # Single-lesson primary path; multi empty ids → sequential after first.
    host._run_fill_lesson_patch_flow(
        section=section,
        lesson_id=first,
        follow_up_ids=extra_ids,
    )

handle_fill_empty = _experience_fill_empty

def _run_fill_lesson_patch_flow(
    host,
    *,
    section: dict,
    lesson_id: str,
    follow_up_ids: list[str] | None = None,
    instruction: str | None = None,
) -> None:
    """T-03 / P10: regenerate one empty lesson → Diff → LessonPatch + Undo."""
    import copy

    from src.application.commands import ApplyLessonPatchCommand
    from src.backend.experience.patch import lesson_patch_from_replace

    sid = str(section.get("id") or "section")
    guard_key = f"lesson:{lesson_id}"
    job_id = f"fill-{lesson_id}"
    job_label = "填充空课"
    action_id = "lesson.fill_empty"
    if not host.conflict_guard.try_acquire(guard_key, job_id, label=job_label):
        host.experience_metrics.inc_guard("rejected")
        host.statusBar().showMessage(
            f"{job_label}：节点忙碌（{host.conflict_guard.busy_summary()}）", 5000
        )
        return
    host._sync_focus_ring()

    from src.backend.ai import AiCourseSpec, regenerate_lesson_in_section
    from src.application.ai_request_worker import AiRequestWorker

    config = host._ai_config
    if config is None or not getattr(config, "is_complete", False):
        host.conflict_guard.release(guard_key, job_id)
        host._sync_focus_ring()
        host._on_ai_edit("lesson", lesson_id)
        return
    spec = AiCourseSpec()
    draft = copy.deepcopy(section)
    instr = instruction or (
        "Fill this empty placeholder lesson with real, level-appropriate "
        "content for the course. Keep the lesson id unchanged. Prefer the "
        "lesson template already set on the lesson."
    )
    host.job_tray.start_job(
        job_id,
        f"{job_label}：正在生成 …",
        kind="ai",
        node_key=guard_key,
    )
    host.experience_metrics.inc_job("ai", "started")
    host.experience_metrics.inc_suggestion(action_id, "accepted")
    host._refresh_experience(immediate=False, focus_only=True)

    def _target() -> dict:
        return regenerate_lesson_in_section(
            config, spec, draft, lesson_id, instruction=instr
        )

    worker = AiRequestWorker(_target)

    def _on_ok(result: object) -> None:
        host.job_tray.finish_job(job_id)
        host.experience_metrics.inc_job("ai", "finished")
        host.conflict_guard.release(guard_key, job_id)
        host.experience_metrics.inc_guard("released")
        host._sync_focus_ring()
        if not isinstance(result, dict):
            host.statusBar().showMessage(f"{job_label}：AI 返回无法识别", 5000)
            return
        # Extract the regenerated lesson (id-preserving).
        new_lesson = None
        for u in result.get("units") or []:
            if not isinstance(u, dict):
                continue
            for les in u.get("lessons") or []:
                if isinstance(les, dict) and str(les.get("id") or "") == lesson_id:
                    new_lesson = les
                    break
            if new_lesson is not None:
                break
        if new_lesson is None:
            # Tolerate first lesson in first unit if id drifted (will force id).
            for u in result.get("units") or []:
                lessons = (u or {}).get("lessons") or []
                if lessons and isinstance(lessons[0], dict):
                    new_lesson = lessons[0]
                    break
        if new_lesson is None:
            host.statusBar().showMessage(f"{job_label}：AI 返回中找不到课时", 5000)
            return
        try:
            _s, _u, old_lesson = host.adapter.find_lesson(lesson_id)
        except KeyError as exc:
            host.statusBar().showMessage(f"{job_label}：{exc}", 5000)
            return
        from src.widgets.diff_view import SectionDiffView

        # Diff only the shell section with this lesson replaced for review.
        preview_before = copy.deepcopy(section)
        preview_after = copy.deepcopy(section)
        for u in preview_after.get("units") or []:
            for i, les in enumerate(u.get("lessons") or []):
                if str(les.get("id") or "") == lesson_id:
                    pinned = copy.deepcopy(new_lesson)
                    pinned["id"] = lesson_id
                    u["lessons"][i] = pinned
        dlg = SectionDiffView(
            preview_before,
            preview_after,
            host,
            confirm=True,
            title=f"{job_label}预览 — 确认后应用",
        )
        if dlg.exec() != QDialog.DialogCode.Accepted:
            host.experience_metrics.inc_suggestion(action_id, "rejected")
            return
        try:
            patch = lesson_patch_from_replace(
                old_lesson,
                new_lesson,
                section_id=sid,
                unit_id=str(_u.get("id") or ""),
            )
        except Exception as exc:
            host.statusBar().showMessage(
                f"{job_label}：无法构建 LessonPatch — {exc}", 6000
            )
            return
        cmd = ApplyLessonPatchCommand(host.adapter, patch)
        cmd.signals.changed.connect(host._on_ai_edit_applied)
        host.undo_stack.push(cmd)
        host.experience_metrics.inc_suggestion(action_id, "applied")
        host._record_experience_event(
            action_id,
            f"空课已填充：{lesson_id}",
            action_id=action_id,
            scope={"lesson_id": lesson_id, "section_id": sid},
        )
        host._refresh_validate_after_ai(f"{job_label}已应用，记得保存")
        # Chain remaining empty lessons one-by-one (AI single-flight).
        rest = list(follow_up_ids or [])
        if rest:
            nxt = rest.pop(0)
            host.statusBar().showMessage(
                f"继续填充下一空课（剩余 {len(rest) + 1}）…", 4000
            )
            try:
                sec2, _u2, _l2 = host.adapter.find_lesson(nxt)
            except KeyError:
                return
            host.tree.select_lesson(nxt)
            host._run_fill_lesson_patch_flow(
                section=sec2,
                lesson_id=nxt,
                follow_up_ids=rest,
            )

    def _on_err(msg: str) -> None:
        host.job_tray.finish_job(job_id)
        host.experience_metrics.inc_job("ai", "failed")
        host.conflict_guard.release(guard_key, job_id)
        host.experience_metrics.inc_guard("released")
        host._sync_focus_ring()
        # Non-modal: avoid hanging headless runners on unclicked MessageBox.
        host.statusBar().showMessage(f"{job_label}失败：{msg}", 8000)

    worker.result_ready.connect(_on_ok)
    worker.error_occurred.connect(_on_err)
    worker.start()
    host._experience_worker = worker

handle_run_fill_lesson_patch_flow = _run_fill_lesson_patch_flow

def _experience_fill_stubs(host) -> None:
    """E1: fill [待补]/needs-review resources on the current section.

    The LLM call runs on a deepcopy; the patched draft only enters the
    course after a SectionDiffView confirmation + undo command (红线).
    """
    import copy

    if not host.course_dir:
        safe_warning(host, "未加载课程目录", "请先打开课程目录。")
        return
    deny = getattr(host, "_deny_ai_write_if_blocked", None)
    if callable(deny) and deny(label="清待补"):
        return
    if host.job_tray.is_busy_ai():
        safe_information(host, "清待补", "当前有 AI 任务进行中，请稍候。")
        return
    section = host._current_section_for_experience()
    if section is None:
        safe_information(host, "清待补", "没有可用的 section。")
        return

    from src.backend.ai import fill_needs_review_resources
    from src.application.ai_request_worker import AiRequestWorker

    sid = str(section.get("id") or "section")
    guard_key = f"section:{sid}"
    job_id = f"stubs-{sid}"
    if not host.conflict_guard.try_acquire(guard_key, job_id, label="清待补"):
        host.experience_metrics.inc_guard("rejected")
        safe_information(host, "清待补", f"节点忙碌：{host.conflict_guard.busy_summary()}"
        )
        return
    host._sync_focus_ring()

    config = host._ai_config
    draft = copy.deepcopy(section)
    host.job_tray.start_job(
        job_id,
        "清待补：正在补全词条 …",
        kind="ai",
        node_key=guard_key,
    )
    host.experience_metrics.inc_job("ai", "started")
    host._refresh_experience(immediate=False, focus_only=True)

    def _target() -> dict:
        return fill_needs_review_resources(config, draft)

    worker = AiRequestWorker(_target)

    def _on_ok(result: object) -> None:
        host.job_tray.finish_job(job_id)
        host.experience_metrics.inc_job("ai", "finished")
        host.conflict_guard.release(guard_key, job_id)
        host.experience_metrics.inc_guard("released")
        host._sync_focus_ring()
        if not isinstance(result, dict):
            safe_warning(host, "清待补", "AI 返回了无法识别的结果。")
            return
        if result == section:
            host.statusBar().showMessage("没有需要补全的待补词条", 4000)
            return
        from src.widgets.diff_view import SectionDiffView

        dlg = SectionDiffView(
            section,
            result,
            host,
            confirm=True,
            title="清待补预览 — 确认后应用",
        )
        if dlg.exec() != QDialog.DialogCode.Accepted:
            host.experience_metrics.inc_suggestion(
                "resource.fill_stubs", "rejected"
            )
            return
        sid = section.get("id", "")
        plan = host.adapter.plan_section_merge(sid, result)
        cmd = MergeAiSectionCommand(host.adapter, plan)
        cmd.signals.changed.connect(host._on_ai_edit_applied)
        host.undo_stack.push(cmd)
        host.experience_metrics.inc_suggestion(
            "resource.fill_stubs", "applied"
        )
        host._record_experience_event(
            "resource.fill_stubs",
            "清待补已应用",
            action_id="resource.fill_stubs",
            scope={"section_id": sid},
        )
        # O-05: hygiene / validate counters should update after stubs clear.
        host._refresh_validate_after_ai("清待补已应用，记得保存")

    def _on_err(msg: str) -> None:
        host.job_tray.finish_job(job_id)
        host.experience_metrics.inc_job("ai", "failed")
        host.conflict_guard.release(guard_key, job_id)
        host.experience_metrics.inc_guard("released")
        host._sync_focus_ring()
        safe_warning(host, "清待补失败", msg)

    worker.result_ready.connect(_on_ok)
    worker.error_occurred.connect(_on_err)
    worker.start()
    # Keep a reference so GC doesn't kill the QThread mid-flight.
    host._experience_worker = worker

handle_fill_stubs = _experience_fill_stubs

def _experience_fill_listening_gaps(
    host, scope: dict, *, action_id: str = "listening.fill_gaps"
) -> None:
    """E2.1: fill listening items missing audioAsset/transcript.

    Data source is ``content_quality._score_audio_ready`` gaps surfaced via
    ``ExperienceContext.listening_gaps`` → ``local_suggestions``. The LLM
    runs on a section deepcopy; the patched draft only enters the course
    after a SectionDiffView confirmation + undo command (红线：禁止静默写).
    Structurally identical to ``_experience_fill_stubs``.

    v4.39 K-17: ``action_id`` 参数化使 ``listening.transcript_gap`` 复用本
    路径（同一 ``fill_listening_gaps`` 引擎，填谓词已扩为 audio-缺-或-transcript-缺），
    仅 metrics/timeline 归到正确 action。
    """
    import copy

    if not host.course_dir:
        safe_warning(host, "未加载课程目录", "请先打开课程目录。")
        return
    gaps = scope.get("gaps") or []
    if not gaps:
        host.statusBar().showMessage("没有听力缺口需要补全", 4000)
        return
    if host.job_tray.is_busy_ai():
        safe_information(host, "补全听力", "当前有 AI 任务进行中，请稍候。")
        return
    # 缺口来自 quality 评分;按 section_id 取首个 section(建议只覆盖单节)。
    sid = str(scope.get("section_id") or "")
    section = None
    if sid:
        try:
            section = host.adapter.find_section(sid)
        except Exception:
            section = None
    if section is None:
        section = host._current_section_for_experience()
    if section is None:
        safe_information(host, "补全听力", "没有可用的 section。")
        return

    from src.backend.ai import fill_listening_gaps
    from src.application.ai_request_worker import AiRequestWorker

    sid = str(section.get("id") or "section")
    guard_key = f"section:{sid}"
    job_id = f"listening-{sid}"
    if not host.conflict_guard.try_acquire(guard_key, job_id, label="补全听力"):
        host.experience_metrics.inc_guard("rejected")
        safe_information(host, "补全听力", f"节点忙碌：{host.conflict_guard.busy_summary()}"
        )
        return
    host._sync_focus_ring()

    config = host._ai_config
    draft = copy.deepcopy(section)
    # v4.x: derive the human-readable target-language name from the loaded course
    # (index.displayName or index.language code) so the LLM prompt is not
    # hardcoded to Turkish. Mirrors textbook.py's language derivation.
    try:
        _idx = getattr(host.adapter, "index", None) or {}
        lang_name = str(
            _idx.get("displayName") or _idx.get("language") or "Turkish"
        )
    except Exception:
        lang_name = "Turkish"
    host.job_tray.start_job(
        job_id,
        "补全听力：正在生成 audioAsset/transcript …",
        kind="ai",
        node_key=guard_key,
    )
    host.experience_metrics.inc_job("ai", "started")
    host._refresh_experience(immediate=False, focus_only=True)

    def _target() -> dict:
        return fill_listening_gaps(
            config, draft, language=lang_name, source_language="Chinese"
        )

    worker = AiRequestWorker(_target)

    def _on_ok(result: object) -> None:
        host.job_tray.finish_job(job_id)
        host.experience_metrics.inc_job("ai", "finished")
        host.conflict_guard.release(guard_key, job_id)
        host.experience_metrics.inc_guard("released")
        host._sync_focus_ring()
        if not isinstance(result, dict):
            safe_warning(host, "补全听力", "AI 返回了无法识别的结果。")
            return
        if result == section:
            host.statusBar().showMessage("没有需要补全的听力缺口", 4000)
            return
        from src.widgets.diff_view import SectionDiffView

        dlg = SectionDiffView(
            section,
            result,
            host,
            confirm=True,
            title="补全听力预览 — 确认后应用",
        )
        if dlg.exec() != QDialog.DialogCode.Accepted:
            host.experience_metrics.inc_suggestion(action_id, "rejected")
            return
        plan = host.adapter.plan_section_merge(sid, result)
        cmd = MergeAiSectionCommand(host.adapter, plan)
        cmd.signals.changed.connect(host._on_ai_edit_applied)
        host.undo_stack.push(cmd)
        host.experience_metrics.inc_suggestion(action_id, "applied")
        host._record_experience_event(
            action_id,
            "补全听力已应用",
            action_id=action_id,
            scope={"section_id": sid, "gap_count": int(scope.get("gap_count") or scope.get("count") or 0)},
        )
        host._refresh_validate_after_ai("补全听力已应用，记得保存")

    def _on_err(msg: str) -> None:
        host.job_tray.finish_job(job_id)
        host.experience_metrics.inc_job("ai", "failed")
        host.conflict_guard.release(guard_key, job_id)
        host.experience_metrics.inc_guard("released")
        host._sync_focus_ring()
        safe_warning(host, "补全听力失败", msg)

    worker.result_ready.connect(_on_ok)
    worker.error_occurred.connect(_on_err)
    worker.start()
    host._experience_worker = worker

handle_fill_listening_gaps = _experience_fill_listening_gaps

