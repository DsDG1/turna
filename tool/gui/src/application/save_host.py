"""Save host orchestration (S-10 final / v4.56).

Duck-types MainWindow. Soft / SavePipeline / yellow hints / brief stay here so
``app.py`` only delegates. Never calls close/quit (no recursion with closeEvent).
"""
from __future__ import annotations

from typing import Any
import contextlib
import logging
from src.application.experience_host import ExperienceHost
logger = logging.getLogger(__name__)


def want_save_brief(host: ExperienceHost) -> bool:
    """O-10: optional post-save brief when setting is on (default off)."""
    try:
        return bool(
            getattr(getattr(host, "_settings_obj", None), "experience_save_brief", False)
        )
    except Exception:
        return False


def apply_soft_before_save(host: ExperienceHost) -> int:
    """E2.1+ Soft Autopilot: apply whitelist hygiene via Undo when enabled.

    Returns number of fixes applied (0 when off / nothing to do).
    Observer / policy gates via ``resolve_policy.allow_soft``.
    """
    from src.backend.experience import resolve_policy

    settings = getattr(host, "_settings_obj", None)
    if not resolve_policy(settings).allow_soft:
        return 0
    from src.application.commands import SoftHygieneCommand
    from src.backend.experience.soft_autopilot import evaluate_soft_fixes

    adapter = getattr(host, "adapter", None)
    if adapter is None:
        return 0
    batch = evaluate_soft_fixes(adapter)
    if not batch.fixes:
        return 0
    cmd = SoftHygieneCommand(adapter, batch)
    host.undo_stack.push(cmd)
    try:
        host._record_experience_event(
            "soft_fix",
            f"规则规范化 {len(batch)} 项",
            action_id="soft.hygiene",
            scope={"count": len(batch)},
        )
    except Exception:
        logger.warning("application/save_host.py:apply_soft_before_save best-effort step failed", exc_info=True)
    return len(batch)


def after_save_quality_hints(host: ExperienceHost) -> str:
    """S-12: after successful save, surface yellow quality proposals.

    Returns a status-bar message when yellow hints exist, else \"\".
    Never raises, never blocks save, never runs AI.
    """
    try:
        from src.backend.experience.scope_format import yellow_quality_summary

        exp = getattr(host, "experience", None)
        ctx = getattr(exp, "context", None) if exp is not None else None
        summary = yellow_quality_summary(ctx)
        if not summary.get("has_hints"):
            return ""
        try:
            host._refresh_ambient()
        except Exception:
            logger.warning("application/save_host.py:after_save_quality_hints best-effort step failed", exc_info=True)
        try:
            host._record_experience_event(
                "save.yellow_hints",
                summary.get("message") or "保存后仍有可改善项",
                action_id="quality.campaign_worst_n",
                scope={
                    "warning_count": summary.get("warning_count", 0),
                    "empty_lesson_count": summary.get("empty_lesson_count", 0),
                    "weak_section_count": summary.get("weak_section_count", 0),
                },
            )
        except Exception:
            logger.warning("application/save_host.py:after_save_quality_hints best-effort step failed", exc_info=True)
        return str(summary.get("message") or "")
    except Exception:
        return ""


def on_save(host: ExperienceHost, *, reason: str = "menu") -> bool:
    """Toolbar / shortcut / palette save entry (E5-A → SavePipeline)."""
    from src.application.save_pipeline import REASON_PALETTE, SaveRequest

    req_reason = reason if reason else "menu"
    if req_reason == "palette":
        req_reason = REASON_PALETTE
    outcome = execute_save(
        host,
        SaveRequest(
            reason=req_reason,
            run_soft=True,
            show_validation_ui=True,
            want_ai_brief=want_save_brief(host),
        ),
    )
    return bool(outcome.ok)


def execute_save(host: ExperienceHost, request: Any, *, prefetched: Any = None, prefetched_soft: int = 0) -> Any:
    """E5-A: single save orchestration for menu / palette / close paths.

    Never calls close/quit. Soft failures never block a valid save.

    *prefetched* (async path, #11): an already-computed ``adapter.save()``
    result from a background worker. Soft Autopilot ran on the GUI thread
    before that worker started (it pushes QUndoStack commands); the pipeline
    below then skips its own Soft/do-save side effects and only composes the
    outcome + runs the same UI hooks, so every entry behaves identically.
    """
    from src.application.save_pipeline import (
        CLOSE_REASONS,
        SaveOutcome,
        SaveRequest,
        compose_status_message,
        run_save_pipeline,
    )
    from src.infrastructure.telemetry import telemetry

    if not isinstance(request, SaveRequest):
        request = SaveRequest(
            reason=str(getattr(request, "reason", "menu") or "menu")
        )

    # Refuse to save while a course is still loading. The open runs
    # adapter.load() on a worker, which reassigns adapter.sections; a save
    # dispatched in that window would serialize a half-loaded course (and
    # races it outright). The toolbar/menu stay live during an open, so this
    # has to be checked here — the single funnel every save path goes through
    # — not only at the UI level.
    opener = getattr(host, "_open_worker", None)
    if opener is not None and getattr(opener, "isRunning", lambda: False)():
        from src.application.save_pipeline import SaveOutcome

        try:
            host.statusBar().showMessage("课程正在打开，请稍候再保存", 4000)
        except Exception:
            logger.warning(
                "application/save_host.py:save-during-open notice failed",
                exc_info=True,
            )
        return SaveOutcome(ok=False, message="课程正在打开，未保存。")

    def _on_triggered(_req: SaveRequest) -> None:
        telemetry.record_event(
            "repo.save.triggered",
            payload={"reason": _req.reason},
        )

    def _on_soft_error(exc: BaseException) -> None:
        try:
            host.statusBar().showMessage(f"Soft Autopilot 跳过：{exc}", 4000)
        except Exception:
            logger.warning("application/save_host.py:_on_soft_error best-effort step failed", exc_info=True)

    def _after_success(outcome: SaveOutcome) -> None:
        try:
            host.tree.refresh()
        except Exception:
            logger.warning("application/save_host.py:_after_success best-effort step failed", exc_info=True)
        try:
            host._sync_focus_ring()
        except Exception:
            logger.warning("application/save_host.py:_after_success best-effort step failed", exc_info=True)
        try:
            host.undo_stack.setClean()
        except Exception:
            logger.warning("application/save_host.py:_after_success best-effort step failed", exc_info=True)
        try:
            mark = getattr(host, "_mark_saved", None)
            if callable(mark):
                mark()
        except Exception:
            logger.warning("application/save_host.py:_after_success best-effort step failed", exc_info=True)
        # #13: the just-saved course may differ from what the overview's
        # cached validation counts describe — drop the cache and refetch.
        try:
            ow = getattr(host, "_overview_widget", None)
            if ow is not None and hasattr(ow, "invalidate_validation_cache"):
                ow.invalidate_validation_cache()
        except Exception:
            logger.warning("application/save_host.py:_after_success best-effort step failed", exc_info=True)
        # #16: a save can flip project imported flags — drop the badge cache.
        try:
            from src.application.shell_views import invalidate_workshop_badge_cache

            invalidate_workshop_badge_cache()
        except Exception:
            logger.warning("application/save_host.py:_after_success best-effort step failed", exc_info=True)
        if outcome.reason in CLOSE_REASONS:
            return
        try:
            host.experience.set_validate_problems(None)
            host._refresh_experience(immediate=True)
        except Exception:
            logger.warning("application/save_host.py:_after_success best-effort step failed", exc_info=True)
        yellow_msg = ""
        try:
            yellow_msg = after_save_quality_hints(host) or ""
        except Exception:
            yellow_msg = ""
        if yellow_msg:
            outcome.yellow_summary = yellow_msg
        brief = getattr(outcome, "brief", None)
        msg = compose_status_message(
            base=outcome.message or "保存成功",
            soft_count=outcome.soft_count,
            yellow_summary=yellow_msg or None,
            brief=brief,
        )
        outcome.message = msg
        try:
            host.statusBar().showMessage(msg, 6000)
        except Exception:
            logger.warning("application/save_host.py:_after_success best-effort step failed", exc_info=True)

    def _after_failure(outcome: SaveOutcome) -> None:
        try:
            host.tree.refresh()
        except Exception:
            logger.warning("application/save_host.py:_after_failure best-effort step failed", exc_info=True)
        try:
            host._sync_focus_ring()
        except Exception:
            logger.warning("application/save_host.py:_after_failure best-effort step failed", exc_info=True)
        try:
            host.statusBar().showMessage(
                outcome.message or "保存失败（已回滚）", 8000
            )
        except Exception:
            logger.warning("application/save_host.py:_after_failure best-effort step failed", exc_info=True)
        if outcome.errors:
            try:
                host.experience.set_validate_problems(outcome.errors)
                host._refresh_experience(immediate=True)
            except Exception:
                logger.warning("application/save_host.py:_after_failure best-effort step failed", exc_info=True)
            if request.show_validation_ui:
                try:
                    host._show_validation_report(
                        outcome.errors, title="校验失败（已回滚）"
                    )
                except Exception:
                    logger.warning("application/save_host.py:_after_failure best-effort step failed", exc_info=True)

    def _build_brief(outcome: SaveOutcome) -> str | None:
        try:
            from src.backend.experience.save_brief import (
                build_local_save_brief_from_context,
            )

            return build_local_save_brief_from_context(
                getattr(getattr(host, "experience", None), "context", None),
                soft_count=int(getattr(outcome, "soft_count", 0) or 0),
                yellow_summary=None,
            ) or None
        except Exception:
            return None

    adapter = host.adapter
    if prefetched is not None:
        # Phase 2 of the async path: the slow chain already ran on the
        # worker; feed the result through unchanged so composition and UI
        # hooks stay single-sourced. Soft ran pre-worker (count passed in),
        # and telemetry already recorded the trigger at that time.
        return run_save_pipeline(
            request,
            do_save=lambda: prefetched,
            apply_soft=lambda: prefetched_soft,
            after_success=_after_success,
            after_failure=_after_failure,
            build_brief=_build_brief if request.want_ai_brief else None,
        )
    return run_save_pipeline(
        request,
        do_save=adapter.save,
        apply_soft=lambda: apply_soft_before_save(host),
        on_soft_error=_on_soft_error,
        after_success=_after_success,
        after_failure=_after_failure,
        on_triggered=_on_triggered,
        build_brief=_build_brief if request.want_ai_brief else None,
    )


# --- Interactive async saves (moved from src/app.py, P2-A) ---


def run_async_pipeline_save(host, *, reason: str = "menu") -> None:
    """Interactive save on a worker, but through the FULL SavePipeline (#11).

    Ctrl+S / 菜单保存 / 命令面板 used to call ``run_async_direct_save`` — a
    bare ``adapter.save`` with none of the pipeline's Soft Autopilot, yellow
    hints, composed status or brief — so the same course saved differently
    depending on the entry point. This runs Soft on the GUI thread (it
    pushes QUndoStack commands), the slow adapter.save chain on an
    ``AiRequestWorker``, then finalizes through ``execute_save`` so the
    outcome and UI hooks are single-sourced with the close path.

    Structural edits are frozen for the duration (same contract as the old
    direct save): the save thread iterates the in-memory model.
    """
    from src.application.ai_request_worker import AiRequestWorker
    from src.application.save_pipeline import REASON_PALETTE, SaveRequest
    from src.infrastructure.telemetry import telemetry

    prev = getattr(host, "_save_worker", None)
    if prev is not None and prev.isRunning():
        host.statusBar().showMessage("正在保存…", 2000)
        return
    if host.adapter is None:
        return

    req_reason = reason if reason else "menu"
    if req_reason == "palette":
        req_reason = REASON_PALETTE
    request = SaveRequest(
        reason=req_reason,
        run_soft=True,
        show_validation_ui=True,
        want_ai_brief=want_save_brief(host),
    )

    telemetry.record_event(
        "repo.save.triggered", payload={"reason": request.reason}
    )
    soft_n = 0
    if request.run_soft:
        try:
            soft_n = apply_soft_before_save(host)
        except Exception as exc:
            soft_n = 0
            try:
                host.statusBar().showMessage(f"Soft Autopilot 跳过：{exc}", 4000)
            except Exception:
                logger.warning("application/save_host.py:run_async_pipeline_save best-effort step failed", exc_info=True)

    host.save_action.setEnabled(False)
    host.centralWidget().setEnabled(False)
    host.statusBar().showMessage("保存中…")

    worker = AiRequestWorker(host.adapter.save)

    def _unfreeze() -> None:
        host.save_action.setEnabled(True)
        host.centralWidget().setEnabled(True)
        host._save_worker = None

    def _on_result(result) -> None:
        _unfreeze()
        execute_save(host, request, prefetched=result, prefetched_soft=soft_n)

    def _on_error(message: str) -> None:
        _unfreeze()
        host.statusBar().showMessage(f"保存失败：{message}", 8000)

    worker.result_ready.connect(_on_result)
    worker.error_occurred.connect(_on_error)
    host._save_worker = worker
    worker.start()


def run_async_direct_save(host) -> None:
    """Legacy bare ``adapter.save`` worker (pre-#11 Ctrl+S path).

    Kept as a compatibility shim for direct callers that really want a raw
    save with no pipeline semantics; interactive entries now use
    :func:`run_async_pipeline_save`. Structural edits are frozen for the
    duration: the save thread iterates the in-memory model, and blocking
    input keeps the same data-safety guarantee the old synchronous freeze
    provided, while the UI thread stays responsive.
    """
    from src.application.ai_request_worker import AiRequestWorker

    prev = getattr(host, "_save_worker", None)
    if prev is not None and prev.isRunning():
        host.statusBar().showMessage("正在保存…", 2000)
        return
    if host.adapter is None:
        return

    host.save_action.setEnabled(False)
    host.centralWidget().setEnabled(False)
    host.statusBar().showMessage("保存中…")

    worker = AiRequestWorker(host.adapter.save)

    def _unfreeze() -> None:
        host.save_action.setEnabled(True)
        host.centralWidget().setEnabled(True)
        host._save_worker = None

    def _on_result(result) -> None:
        _unfreeze()
        host.tree.refresh()
        if result.ok:
            host.undo_stack.setClean()
            mark = getattr(host, "_mark_saved", None)
            if callable(mark):
                with contextlib.suppress(Exception):
                    mark()
            # #13: keep the overview's validation badge honest after a save.
            ow = getattr(host, "_overview_widget", None)
            if ow is not None and hasattr(ow, "invalidate_validation_cache"):
                with contextlib.suppress(Exception):
                    ow.invalidate_validation_cache()
            host.statusBar().showMessage(result.message or "保存成功", 5000)
        else:
            host.statusBar().showMessage(result.message or "保存失败（已回滚）", 8000)
            if result.errors:
                host._show_validation_report(result.errors, title="校验失败（已回滚）")

    def _on_error(message: str) -> None:
        _unfreeze()
        host.statusBar().showMessage(f"保存失败：{message}", 8000)

    worker.result_ready.connect(_on_result)
    worker.error_occurred.connect(_on_error)
    host._save_worker = worker
    worker.start()
