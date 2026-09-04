"""E3-A/B1 Goal host orchestration (plan / sandbox / checklist merge).

Duck-types MainWindow. Pure helpers are Qt-free; dialogs need QWidget host.
Never writes the live course without an explicit host merge path + confirm.
"""
from __future__ import annotations

from typing import Any, Mapping
import logging
from src.application.experience_host import ExperienceHost
logger = logging.getLogger(__name__)


def _is_headless_ui() -> bool:
    """Delegate to ui_guard (v4.46 single source). Kept for import stability."""
    from src.application.ui_guard import is_headless_ui

    return is_headless_ui()


def is_goal_allowed(host: ExperienceHost) -> tuple[bool, str]:
    """Return (allowed, deny_reason) from policy + settings."""
    try:
        from src.backend.experience.policy import resolve_policy

        settings = getattr(host, "_settings_obj", None)
        usage = None
        exp = getattr(host, "experience", None)
        ctx = getattr(exp, "context", None) if exp is not None else None
        if ctx is not None:
            usage = getattr(ctx, "usage_today", None)
        pol = resolve_policy(settings, usage_today=usage)
        if not pol.allow_goal:
            if pol.is_observer:
                return False, "Observer 模式下 Goal 不可用"
            if not getattr(settings, "experience_goal_enabled", False):
                return False, "Goal 已关闭：设置 ▸ 体验 OS ▸ 启用 Goal 规划"
            if pol.budget_exceeded:
                return False, "今日 AI 预算已用尽，Goal 暂不可用"
            return False, "Goal 当前不可用"
        return True, ""
    except Exception as exc:
        return False, f"Goal 策略读取失败：{exc.__class__.__name__}"


def _build_goal_chat_fn(host: ExperienceHost) -> Any | None:
    """K-09: sync chat_fn wrapping ``request_chat`` (mirrors git_skill.run_git_skill).

    Returns None when AI config is incomplete or the M-08 daily budget gate
    denies AI skills. The returned callable never raises (→ None on error,
    which makes ``expand_goal_with_llm`` fall back to the local plan).
    """
    try:
        settings = getattr(host, "_settings_obj", None)
        exp = getattr(host, "experience", None)
        ctx = getattr(exp, "context", None) if exp is not None else None
        from src.backend.experience.policy import resolve_policy

        usage = getattr(ctx, "usage_today", None)
        pol = resolve_policy(settings, usage_today=usage)
        if getattr(pol, "budget_exceeded", False) or not getattr(
            pol, "allow_ai_skill", True
        ):
            return None
        config = getattr(host, "_ai_config", None)
        if config is None or not bool(getattr(config, "is_complete", False)):
            return None

        def _chat(prompt: str) -> str | None:
            try:
                from src.backend.ai_generator import content_text, request_chat

                messages = [
                    {
                        "role": "system",
                        "content": "你是课程目标拆解助手。只输出 JSON，不要解释。",
                    },
                    {"role": "user", "content": str(prompt or "")},
                ]
                body = request_chat(config, messages, temperature=0.3)
                choices = (body or {}).get("choices") or []
                if not choices:
                    return None
                msg = (choices[0].get("message") or {}).get("content")
                text = content_text(msg)
                return text if isinstance(text, str) else None
            except Exception:
                return None

        return _chat
    except Exception:
        return None


def build_plan_for_host(host: ExperienceHost, goal_text: str = "", *, expand: bool = False) -> Any:
    """Build GoalPlan from live Experience context. Never raises → empty plan."""
    from src.backend.experience.planner import GoalPlan, expand_goal_local, plan_from_context

    try:
        exp = getattr(host, "experience", None)
        ctx = getattr(exp, "context", None) if exp is not None else None
        settings = getattr(host, "_settings_obj", None)
        if expand:
            try:
                from src.backend.experience.goal_llm import (
                    expand_goal_with_llm,
                    is_goal_llm_enabled,
                )

                if is_goal_llm_enabled(settings):
                    return expand_goal_with_llm(
                        ctx,
                        goal_text or "",
                        settings=settings,
                        chat_fn=_build_goal_chat_fn(host),
                    )
            except Exception:
                logger.debug("application/goal_controller.py:build_plan_for_host best-effort step failed", exc_info=True)
            return expand_goal_local(ctx, goal_text=goal_text or "")
        return plan_from_context(ctx, goal_text=goal_text or "")
    except Exception:
        return GoalPlan(goal_text=goal_text or "", notes=["规划异常"])


def run_sandbox_for_host(host: ExperienceHost, plan: Any) -> tuple[Any | None, Any | None, str]:
    """Stage plan in CourseSandbox. Returns (sandbox, merge_plan, error).

    E3-B2 stub path (local, no LLM): used as the fallback when AI config is
    incomplete, and still the basis for non-``lesson.fill_empty`` steps.
    E3-B3 real generation lives in :func:`run_sandbox_real_fill_for_host`.
    """
    from src.backend.experience.sandbox import CourseSandbox

    try:
        adapter = getattr(host, "adapter", None)
        if adapter is None:
            return None, None, "无课程"
        lesson_ids = list(getattr(plan, "lesson_ids", None) or [])
        box = CourseSandbox.from_adapter(
            adapter, lesson_ids=lesson_ids if lesson_ids else None
        )
        box.run_plan_local(plan)
        mp = box.to_merge_plan()
        return box, mp, ""
    except Exception as exc:
        return None, None, str(exc) or exc.__class__.__name__


def _collect_fill_lesson_ids(plan: Any) -> list[str]:
    """Ordered unique lesson ids targeted by ``lesson.fill_empty`` steps."""
    seen: set[str] = set()
    out: list[str] = []
    for step in list(getattr(plan, "steps", None) or []):
        if getattr(step, "action_id", "") != "lesson.fill_empty":
            continue
        scope = getattr(step, "scope", None) or {}
        lid = str(scope.get("lesson_id") or scope.get("first_lesson_id") or "")
        if lid and lid not in seen:
            seen.add(lid)
            out.append(lid)
    return out


def run_sandbox_real_fill_for_host(
    host: ExperienceHost,
    plan: Any,
    *,
    on_complete: Any | None = None,
) -> tuple[Any | None, Any | None, str]:
    """E3-B3: stage REAL AI-generated lessons into the sandbox (id-preserving).

    Sequentially runs one ``AiRequestWorker`` per ``lesson.fill_empty`` step,
    mirroring :meth:`ExperienceSkillsMixin._run_fill_lesson_patch_flow`. Falls
    back to ``stage_stub_fill`` (local) when AI config is incomplete. Skips a
    lesson on AI failure (does not abort the batch). Never mutates the live
    adapter — generation runs on a deepcopy section and is staged into the
    sandbox's deepcopy lesson store.

    *on_complete(sandbox, merge_plan)* is invoked once the fill chain finishes
    (or immediately for the stub-fallback / no-fill path). The synchronous
    return value ``(sandbox, merge_plan, error)`` is only reliable for the
    stub-fallback path; for the real-AI path it returns ``(sandbox, None, "")``
    and the merge plan is delivered via *on_complete* after the chain runs.

    In tests, injecting ``host._goal_fill_worker_factory`` (a callable returning
    a fake worker that runs the target inline and emits ``result_ready``
    synchronously) makes the chain complete before this function returns, so
    *on_complete* fires inline and the merge plan is also staged immediately.
    """
    from src.backend.experience.sandbox import CourseSandbox

    try:
        adapter = getattr(host, "adapter", None)
        if adapter is None:
            return None, None, "无课程"
        lesson_ids = list(getattr(plan, "lesson_ids", None) or [])
        box = CourseSandbox.from_adapter(
            adapter, lesson_ids=lesson_ids if lesson_ids else None
        )

        fill_ids = _collect_fill_lesson_ids(plan)
        config = getattr(host, "_ai_config", None)
        ai_ready = config is not None and bool(getattr(config, "is_complete", False))

        if not fill_ids or not ai_ready:
            # Stub fallback (E3-B2 path) for all steps, or no fill targets.
            box.run_plan_local(plan)
            mp = box.to_merge_plan()
            if not ai_ready and fill_ids:
                _record_event_safe(
                    host,
                    "goal.fallback_stub",
                    "AI 配置不完整，回退 stub 占位",
                    action_id="goal.run",
                    scope={"lessons": len(fill_ids)},
                )
            if callable(on_complete):
                try:
                    on_complete(box, mp)
                except Exception:
                    logger.debug("application/goal_controller.py:run_sandbox_real_fill_for_host best-effort step failed", exc_info=True)
            return box, mp, ""

        # Real generation: stage non-fill steps synchronously first.
        for step in list(getattr(plan, "steps", None) or []):
            if getattr(step, "action_id", "") != "lesson.fill_empty":
                try:
                    box.mark_action(step)
                except Exception:
                    logger.debug("application/goal_controller.py:run_sandbox_real_fill_for_host best-effort step failed", exc_info=True)

        def _done() -> None:
            mp = box.to_merge_plan()
            if callable(on_complete):
                try:
                    on_complete(box, mp)
                except Exception:
                    logger.debug("application/goal_controller.py:_done best-effort step failed", exc_info=True)

        synchronous = _run_real_fill_chain(host, box, fill_ids, config, _done)
        if synchronous:
            # Tests: chain completed inline; mp is already staged.
            return box, box.to_merge_plan(), ""
        return box, None, ""
    except Exception as exc:
        return None, None, str(exc) or exc.__class__.__name__


def _record_event_safe(host: ExperienceHost, kind: str, summary: str, **kwargs: Any) -> None:
    try:
        record = getattr(host, "_record_experience_event", None)
        if callable(record):
            record(kind, summary, **kwargs)
    except Exception:
        logger.debug("application/goal_controller.py:_record_event_safe best-effort step failed", exc_info=True)


def _sync_focus_ring_safe(host: ExperienceHost) -> None:
    fn = getattr(host, "_sync_focus_ring", None)
    if callable(fn):
        try:
            fn()
        except Exception:
            logger.debug("application/goal_controller.py:_sync_focus_ring_safe best-effort step failed", exc_info=True)


def _run_real_fill_chain(
    host: ExperienceHost,
    box: Any,
    fill_ids: list[str],
    config: Any,
    on_done: Any,
) -> bool:
    """Sequentially generate each empty lesson via ``AiRequestWorker``.

    Mirrors :meth:`ExperienceSkillsMixin._run_fill_lesson_patch_flow`'s
    single-flight chain: one worker at a time, next lesson starts only after
    the previous finishes (success or skip-on-fail). All host access is
    None-safe ``getattr`` so the controller stays headless-testable.

    Returns True when the whole chain completed synchronously (test fake
    worker that runs the target inline), in which case *on_done* has already
    been called and the sandbox is fully staged. Returns False when a real
    ``AiRequestWorker`` was started (chain continues asynchronously; *on_done*
    fires from the final worker callback).
    """
    import copy

    from src.backend.ai_generator import AiCourseSpec, regenerate_lesson_in_section

    adapter = getattr(host, "adapter", None)
    if adapter is None:
        try:
            on_done()
        except Exception:
            logger.debug("application/goal_controller.py:_run_real_fill_chain best-effort step failed", exc_info=True)
        return True
    metrics = getattr(host, "experience_metrics", None)
    guard = getattr(host, "conflict_guard", None)
    tray = getattr(host, "job_tray", None)
    spec = AiCourseSpec()
    instr = (
        "Fill this empty placeholder lesson with real, level-appropriate "
        "content for the course. Keep the lesson id unchanged. Prefer the "
        "lesson template already set on the lesson."
    )

    state = {"finished_inline": True}

    def _next(index: int) -> None:
        if index >= len(fill_ids):
            try:
                on_done()
            except Exception:
                logger.debug("application/goal_controller.py:_next best-effort step failed", exc_info=True)
            return
        lid = fill_ids[index]
        try:
            section, _u, _l = adapter.find_lesson(lid)
        except Exception:
            _next(index + 1)
            return
        guard_key = f"lesson:{lid}"
        job_id = f"goal-fill-{lid}"
        job_label = f"目标生成 {lid}"
        acquired = False
        if guard is not None:
            try:
                acquired = bool(guard.try_acquire(guard_key, job_id, label=job_label))
            except Exception:
                acquired = False
            if not acquired:
                try:
                    metrics.inc_guard("rejected")
                except Exception:
                    logger.debug("application/goal_controller.py:_next best-effort step failed", exc_info=True)
                _next(index + 1)
                return
        _sync_focus_ring_safe(host)
        try:
            if tray is not None:
                tray.start_job(job_id, f"{job_label}：正在生成 …", kind="ai", node_key=guard_key)
            if metrics is not None:
                metrics.inc_job("ai", "started")
        except Exception:
            logger.debug("application/goal_controller.py:_next best-effort step failed", exc_info=True)

        draft = copy.deepcopy(section)

        def _target() -> dict:
            return regenerate_lesson_in_section(
                config, spec, draft, lid, instruction=instr
            )

        factory = getattr(host, "_goal_fill_worker_factory", None)
        worker = factory(_target) if callable(factory) else None
        if worker is None:
            from src.dialogs.ai.worker import AiRequestWorker

            worker = AiRequestWorker(_target)
            state["finished_inline"] = False

        def _on_ok(result: object) -> None:
            try:
                if tray is not None:
                    tray.finish_job(job_id)
                if metrics is not None:
                    metrics.inc_job("ai", "finished")
            except Exception:
                logger.debug("application/goal_controller.py:_on_ok best-effort step failed", exc_info=True)
            if guard is not None:
                try:
                    guard.release(guard_key, job_id)
                    if metrics is not None:
                        metrics.inc_guard("released")
                except Exception:
                    logger.debug("application/goal_controller.py:_on_ok best-effort step failed", exc_info=True)
            _sync_focus_ring_safe(host)
            new_lesson = None
            if isinstance(result, dict):
                for u in result.get("units") or []:
                    for les in (u or {}).get("lessons") or []:
                        if isinstance(les, dict) and str(les.get("id") or "") == lid:
                            new_lesson = les
                            break
                    if new_lesson is not None:
                        break
                if new_lesson is None:
                    for u in result.get("units") or []:
                        lessons = (u or {}).get("lessons") or []
                        if lessons and isinstance(lessons[0], dict):
                            new_lesson = lessons[0]
                            break
            staged = False
            if new_lesson is not None:
                try:
                    staged = bool(box.stage_real_fill(lid, new_lesson=new_lesson))
                except Exception:
                    staged = False
            if not staged:
                _status(host, f"{lid} 生成不可用，已跳过")
            else:
                _record_event_safe(
                    host,
                    "goal.fill",
                    f"沙箱已生成 {lid}",
                    action_id="lesson.fill_empty",
                    scope={"lesson_id": lid},
                )
            _next(index + 1)

        def _on_err(msg: str) -> None:
            try:
                if tray is not None:
                    tray.finish_job(job_id)
                if metrics is not None:
                    metrics.inc_job("ai", "failed")
            except Exception:
                logger.debug("application/goal_controller.py:_on_err best-effort step failed", exc_info=True)
            if guard is not None:
                try:
                    guard.release(guard_key, job_id)
                except Exception:
                    logger.debug("application/goal_controller.py:_on_err best-effort step failed", exc_info=True)
            _sync_focus_ring_safe(host)
            # Skip-on-fail (decision 3): non-modal status, continue batch.
            _status(host, f"{lid} 生成失败，已跳过：{msg}")
            _next(index + 1)

        worker.result_ready.connect(_on_ok)
        worker.error_occurred.connect(_on_err)
        try:
            worker.start()
        except Exception:
            _on_err("worker 启动失败")
        try:
            setattr(host, "_experience_worker", worker)
        except Exception:
            logger.debug("application/goal_controller.py:_next best-effort step failed", exc_info=True)

    _next(0)
    return bool(state["finished_inline"])


def show_plan_dialog(host: ExperienceHost, plan: Any) -> str:
    """Show plan information only. Returns ``ok``."""
    from src.backend.experience.planner import format_plan_summary

    if _is_headless_ui():
        return "ok"
    try:
        from PySide6.QtWidgets import QMessageBox, QWidget

        parent = host if isinstance(host, QWidget) else None
        text = format_plan_summary(plan)
        QMessageBox.information(parent, "Goal 规划", text[:4000] if text else "（空计划）")
    except Exception:
        logger.debug("application/goal_controller.py:show_plan_dialog best-effort step failed", exc_info=True)
    return "ok"


def show_merge_checklist(host: ExperienceHost, plan: Any, merge_plan: Any) -> list[str] | None:
    """Show GoalMergeDialog; return selected keys or None if cancelled."""
    from src.backend.experience.planner import format_plan_summary

    if _is_headless_ui():
        # Headless/offscreen: no modal — treat as full selection (same as
        # the exception fallback below; tests may still mock this function).
        try:
            from src.backend.experience.sandbox import merge_item_key

            return [merge_item_key(it) for it in (getattr(merge_plan, "items", None) or [])]
        except Exception:
            return None
    try:
        from PySide6.QtWidgets import QWidget

        from src.widgets.goal_merge_dialog import GoalMergeDialog

        parent = host if isinstance(host, QWidget) else None
        dlg = GoalMergeDialog(
            merge_plan,
            parent,
            plan_summary=format_plan_summary(plan, max_lines=8),
        )
        if dlg.exec() != dlg.DialogCode.Accepted:
            return None
        return dlg.selected_keys()
    except Exception:
        # Headless / no Qt dialog: treat as full selection (tests may mock)
        try:
            from src.backend.experience.sandbox import merge_item_key

            return [merge_item_key(it) for it in (getattr(merge_plan, "items", None) or [])]
        except Exception:
            return None


def apply_sandbox_lessons_to_host(host: ExperienceHost, merge_plan: Any) -> int:
    """E3-B2: apply mergeable lesson payloads via Batch LessonPatch + Undo.

    Returns number of lessons patched. Does not dispatch AI skills.
    Never raises to caller (returns 0 on failure).
    """
    from src.backend.experience.goal_generate import (
        force_lesson_id,
        is_lesson_payload_mergeable,
    )
    from src.backend.experience.patch import (
        BatchPatch,
        LessonPatch,
        batch_patch,
        lesson_patch_from_replace,
    )

    adapter = getattr(host, "adapter", None)
    if adapter is None or merge_plan is None:
        return 0
    items = list(getattr(merge_plan, "items", None) or [])
    patches: list[LessonPatch] = []
    for it in items:
        payload = getattr(it, "sandbox_payload", None)
        if not is_lesson_payload_mergeable(payload):
            continue
        lid = str(
            (getattr(it, "scope", None) or {}).get("lesson_id")
            or getattr(it, "id", "")
            or ""
        )
        if not lid:
            continue
        try:
            _section, _unit, old_lesson = adapter.find_lesson(lid)
        except Exception:
            continue
        try:
            new_lesson = force_lesson_id(payload, lid)
            patch = lesson_patch_from_replace(
                dict(old_lesson),
                new_lesson,
                section_id=str((getattr(it, "scope", None) or {}).get("section_id") or ""),
            )
            patches.append(patch)
        except Exception:
            continue
    if not patches:
        return 0
    try:
        from src.application.commands import ApplyBatchPatchCommand

        batch = batch_patch(patches, label=f"Goal 合并 {len(patches)} 课")
        stack = getattr(host, "undo_stack", None)
        if stack is None:
            return 0
        cmd = ApplyBatchPatchCommand(
            adapter=adapter,
            batch=batch,
            text=f"Goal 沙箱合并 {len(patches)} 课",
        )
        # Wire tree refresh if command emits changed
        try:
            tree = getattr(host, "tree", None)
            if tree is not None and hasattr(cmd, "signals"):
                cmd.signals.changed.connect(tree.refresh_incremental)
        except Exception:
            logger.debug("application/goal_controller.py:apply_sandbox_lessons_to_host best-effort step failed", exc_info=True)
        stack.push(cmd)
        try:
            inv = getattr(adapter, "invalidate_node_index", None)
            if callable(inv):
                inv()
        except Exception:
            logger.debug("application/goal_controller.py:apply_sandbox_lessons_to_host best-effort step failed", exc_info=True)
        try:
            host._refresh_experience(immediate=True)
        except Exception:
            logger.debug("application/goal_controller.py:apply_sandbox_lessons_to_host best-effort step failed", exc_info=True)
        return len(patches)
    except Exception:
        return 0


def apply_merge_plan_on_host(host: ExperienceHost, merge_plan: Any) -> int:
    """E3-B2: LessonPatch batch for sandbox payloads + skill dispatch for rest.

    Returns total operations (patches + skill dispatches).
    """
    if merge_plan is None:
        return 0
    from src.backend.experience.goal_generate import is_lesson_payload_mergeable

    items = list(getattr(merge_plan, "items", None) or [])
    patch_items = []
    skill_items = []
    for it in items:
        payload = getattr(it, "sandbox_payload", None)
        if getattr(it, "kind", "") == "lesson" and is_lesson_payload_mergeable(payload):
            patch_items.append(it)
        else:
            skill_items.append(it)

    n = 0
    if patch_items:
        from types import SimpleNamespace

        sub = SimpleNamespace(
            items=patch_items,
            goal_text=getattr(merge_plan, "goal_text", ""),
        )
        n += apply_sandbox_lessons_to_host(host, sub)

    suggest = getattr(host, "_on_experience_suggestion", None)
    if not callable(suggest):
        return n
    seen: set[str] = set()
    for it in skill_items:
        aid = str(getattr(it, "action_id", "") or "")
        if not aid:
            continue
        # Skip fill if we already patched that lesson
        scope = dict(getattr(it, "scope", None) or {})
        lid = str(scope.get("lesson_id") or scope.get("first_lesson_id") or it.id or "")
        if aid == "lesson.fill_empty" and lid:
            # already handled via patch path if payload was mergeable
            continue
        key = f"{aid}:{lid}"
        if key in seen:
            continue
        seen.add(key)
        try:
            suggest(
                {
                    "action_id": aid,
                    "scope": scope,
                    "title": getattr(it, "summary", aid),
                }
            )
            n += 1
        except Exception:
            continue
    return n


def _plan_goal_async(host: ExperienceHost, goal_text: str, on_plan: Any) -> bool:
    """K-09: run the LLM expand path on a background worker.

    Returns True when the request was dispatched (``on_plan`` will fire on the
    UI thread with the built plan); False when the caller should fall back to
    the synchronous local/未启用 path. Headless (no Qt UI) always falls back
    so pure tests and CLI keep synchronous semantics.
    """
    try:
        from src.backend.experience.goal_llm import is_goal_llm_enabled

        if not is_goal_llm_enabled(getattr(host, "_settings_obj", None)):
            return False
        if _is_headless_ui():
            return False
        from src.dialogs.ai.worker import AiRequestWorker

        _status(host, "Goal 规划中（AI 扩展）…")
        worker = AiRequestWorker(build_plan_for_host, host, goal_text, expand=True)
        worker.result_ready.connect(lambda plan: on_plan(plan))
        worker.error_occurred.connect(
            lambda msg: _status(host, f"Goal 规划失败：{msg}")
        )
        worker.start()
        return True
    except Exception:
        return False


def _record_plan_built(host: ExperienceHost, plan: Any) -> None:
    """Telemetry/metrics for a freshly built plan (never raises)."""
    try:
        record = getattr(host, "_record_experience_event", None)
        if callable(record):
            record(
                "goal.plan",
                f"Goal 规划 {len(plan)} 步",
                action_id="goal.plan",
                scope={"steps": len(plan)},
            )
        metrics = getattr(host, "experience_metrics", None)
        if metrics is not None and hasattr(metrics, "inc_suggestion"):
            metrics.inc_suggestion("goal.plan", "applied")
    except Exception:
        logger.debug("application/goal_controller.py:_record_plan_built best-effort step failed", exc_info=True)


def experience_goal_plan(host: ExperienceHost, scope: Mapping[str, Any] | None = None) -> None:
    """goal.plan entry: build + show plan (no sandbox write)."""
    ok, reason = is_goal_allowed(host)
    if not ok:
        _status(host, reason)
        _info(host, "Goal 不可用", reason)
        return
    goal_text = ""
    expand = False
    if scope:
        goal_text = str(scope.get("goal_text") or scope.get("text") or "")
        expand = bool(scope.get("expand"))

    def _done(plan: Any) -> None:
        host._goal_last_plan = plan  # type: ignore[attr-defined]
        _record_plan_built(host, plan)
        show_plan_dialog(host, plan)
        _status(host, f"Goal 规划完成 · {len(plan)} 步")

    # LLM expand can block for the full HTTP timeout — run it on a worker.
    if expand and _plan_goal_async(host, goal_text, _done):
        return
    plan = build_plan_for_host(host, goal_text, expand=expand)
    _done(plan)


def experience_goal_expand(host: ExperienceHost, scope: Mapping[str, Any] | None = None) -> None:
    """goal.expand: local (or optional LLM) richer plan."""
    scope = dict(scope or {})
    scope["expand"] = True
    experience_goal_plan(host, scope)


def show_batch_diff_for_merge(host: ExperienceHost, merge_plan: Any) -> bool:
    """E3-B3: one consolidated SectionDiffView confirm for all selected lessons.

    Builds a before/after section pair by splicing each mergeable
    ``sandbox_payload`` into a deepcopy of its host section, then shows a
    single :class:`SectionDiffView` with ``confirm=True``. Headless /
    offscreen: auto-confirm (no blocking dialog). Returns True when the
    author confirms (or cannot show a dialog).
    """
    import copy

    from src.backend.experience.goal_generate import is_lesson_payload_mergeable

    try:
        adapter = getattr(host, "adapter", None)
        if adapter is None:
            return True
        # Group mergeable items by section_id for one diff per section.
        by_section: dict[str, list[tuple[str, dict]]] = {}
        for it in list(getattr(merge_plan, "items", None) or []):
            if getattr(it, "kind", "") != "lesson":
                continue
            payload = getattr(it, "sandbox_payload", None)
            if not is_lesson_payload_mergeable(payload):
                continue
            scope = getattr(it, "scope", None) or {}
            sid = str(scope.get("section_id") or "")
            lid = str(scope.get("lesson_id") or getattr(it, "id", "") or "")
            if not sid or not lid:
                continue
            by_section.setdefault(sid, []).append((lid, dict(payload)))
        if not by_section:
            return True

        # Headless guard: never construct a QWidget without a QApplication
        # (Qt fatal), and never exec() a modal on offscreen (blocks forever).
        if _is_headless_ui():
            return True
        try:
            from PySide6.QtWidgets import QWidget
        except Exception:
            return True

        from src.widgets.diff_view import SectionDiffView

        parent = host if isinstance(host, QWidget) else None
        confirmed_all = True
        for sid, pairs in by_section.items():
            try:
                section = adapter.find_section(sid)
            except Exception:
                continue
            before = copy.deepcopy(section)
            after = copy.deepcopy(section)
            for u in after.get("units") or []:
                for i, les in enumerate(u.get("lessons") or []):
                    lid = str(les.get("id") or "")
                    match = next((p for p in pairs if p[0] == lid), None)
                    if match is None:
                        continue
                    pinned = copy.deepcopy(match[1])
                    pinned["id"] = lid
                    u["lessons"][i] = pinned
            dlg = SectionDiffView(
                before,
                after,
                parent,
                confirm=True,
                title="目标合并预览 — 确认后应用",
            )
            if dlg.exec() != dlg.DialogCode.Accepted:
                confirmed_all = False
                break
        return confirmed_all
    except Exception:
        # Headless / no Qt: auto-confirm (matches _confirm_merge strategy).
        return True


def experience_goal_run(host: ExperienceHost, scope: Mapping[str, Any] | None = None) -> None:
    """goal.run: plan → sandbox(real-fill) → checklist → batch Diff → merge."""
    from src.backend.experience.sandbox import filter_merge_plan

    ok, reason = is_goal_allowed(host)
    if not ok:
        _status(host, reason)
        _info(host, "Goal 不可用", reason)
        return
    goal_text = ""
    expand = False
    if scope:
        goal_text = str(scope.get("goal_text") or scope.get("text") or "")
        expand = bool(scope.get("expand"))
    plan = getattr(host, "_goal_last_plan", None)
    need_build = plan is None or (
        goal_text and getattr(plan, "goal_text", "") != goal_text
    )

    def _after_sandbox(box: Any, mp: Any) -> None:
        if mp is None:
            _status(host, "沙箱失败：无法生成合并草案")
            _info(host, "Goal 沙箱", "无法生成合并草案")
            return
        host._goal_sandbox = box  # type: ignore[attr-defined]
        host._goal_merge_plan = mp  # type: ignore[attr-defined]

        try:
            record = getattr(host, "_record_experience_event", None)
            if callable(record):
                record(
                    "goal.run",
                    getattr(mp, "summary", None) or f"沙箱 {len(mp)} 项",
                    action_id="goal.run",
                    scope={"items": len(mp)},
                )
        except Exception:
            logger.debug("application/goal_controller.py:_after_sandbox best-effort step failed", exc_info=True)

        selected = show_merge_checklist(host, plan, mp)
        if selected is None:
            _status(host, "已取消 Goal 合并（主课未改）")
            try:
                if callable(record):
                    record(
                        "goal.cancelled",
                        "取消合并清单",
                        action_id="goal.run",
                        scope={},
                    )
            except Exception:
                logger.debug("application/goal_controller.py:_after_sandbox best-effort step failed", exc_info=True)
            return

        filtered = filter_merge_plan(mp, selected)
        if len(filtered) == 0:
            _status(host, "未选择任何步骤（主课未改）")
            return

        # E3-B3 batch Diff confirm (decision 1); headless auto-confirms.
        if not show_batch_diff_for_merge(host, filtered):
            _status(host, "已取消 Goal 合并（主课未改）")
            return

        n = apply_merge_plan_on_host(host, filtered)
        _status(
            host,
            f"Goal 已合并/调度 {n} 项（LessonPatch 可 Ctrl+Z；skill 仍可能再确认）",
        )
        try:
            if callable(record):
                record(
                    "goal.merged",
                    f"合并/调度 {n} 项",
                    action_id="goal.run",
                    scope={"dispatched": n},
                )
        except Exception:
            logger.debug("application/goal_controller.py:_after_sandbox best-effort step failed", exc_info=True)

    def _start_sandbox() -> None:
        try:
            box, mp, err = run_sandbox_real_fill_for_host(
                host, plan, on_complete=_after_sandbox
            )
        except Exception as exc:
            _status(host, f"沙箱失败：{exc}")
            return
        if err:
            _status(host, f"沙箱失败：{err}")
            _info(host, "Goal 沙箱", err or "无法生成合并草案")
            return
        # For the async real-fill path mp is None and _after_sandbox is called via
        # the worker callback. For the stub fallback _after_sandbox was already
        # invoked synchronously by run_sandbox_real_fill_for_host's on_complete.

    if need_build:
        def _plan_ready(built: Any) -> None:
            nonlocal plan
            plan = built
            host._goal_last_plan = built  # type: ignore[attr-defined]
            _start_sandbox()

        # The (re)build forces the expand path (expand or True), which may hit
        # the LLM — run it on a worker instead of freezing the UI thread.
        if _plan_goal_async(host, goal_text, _plan_ready):
            return
        plan = build_plan_for_host(host, goal_text, expand=expand or True)
        host._goal_last_plan = plan  # type: ignore[attr-defined]
    _start_sandbox()


def clear_goal_state(host: ExperienceHost) -> None:
    """Lifecycle: drop sandbox / last plan on course close."""
    for attr in ("_goal_sandbox", "_goal_merge_plan", "_goal_last_plan"):
        try:
            if hasattr(host, attr):
                setattr(host, attr, None)
        except Exception:
            logger.debug("application/goal_controller.py:clear_goal_state best-effort step failed", exc_info=True)


def _status(host: ExperienceHost, msg: str) -> None:
    try:
        host.statusBar().showMessage(msg, 6000)
    except Exception:
        logger.debug("application/goal_controller.py:_status best-effort step failed", exc_info=True)


def _info(host: ExperienceHost, title: str, body: str) -> None:
    if _is_headless_ui():
        return
    try:
        from PySide6.QtWidgets import QMessageBox, QWidget

        parent = host if isinstance(host, QWidget) else None
        QMessageBox.information(parent, title, body)
    except Exception:
        logger.debug("application/goal_controller.py:_info best-effort step failed", exc_info=True)


def _confirm_merge(host: ExperienceHost, merge_plan: Any) -> bool:
    if _is_headless_ui():
        # Headless/offscreen: auto-confirm (same as the exception fallback).
        return True
    try:
        from PySide6.QtWidgets import QMessageBox, QWidget

        parent = host if isinstance(host, QWidget) else None
        n = len(getattr(merge_plan, "items", None) or [])
        r = QMessageBox.question(
            parent,
            "确认 Goal 合并清单",
            f"将调度 {n} 项既有 skill（仍可能弹出预览/Diff）。\n"
            "主课仅在各 skill 确认后改写；可 Undo。\n\n继续？",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
            QMessageBox.StandardButton.No,
        )
        return r == QMessageBox.StandardButton.Yes
    except Exception:
        # Headless tests: auto-confirm
        return True
