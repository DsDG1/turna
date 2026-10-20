"""MainWindow closeEvent orchestration (S-10 final / v4.56).

Duck-types MainWindow. Preserves:
- auto_save_on_close → SavePipeline (Soft allowed)
- interactive Save/Discard/Cancel
- headless dirty → auto-Discard (never hang CI)
- save failure → ignore close + safe_warning
- accepted close → metrics flush / workshop+overview teardown / clear AI key
"""
from __future__ import annotations

from typing import Any
import logging
from src.application import runtime_context
from src.application.experience_host import ExperienceHost
logger = logging.getLogger(__name__)


def clear_ai_key_on_exit(host: ExperienceHost) -> None:
    """Wipe the API key from memory and storage when the window closes."""
    try:
        if getattr(host, "_ai_config", None) is not None:
            host._ai_config.api_key = ""
        if getattr(host, "_settings_obj", None) is not None:
            host._settings_obj.ai_api_key = ""
            host._settings_obj.save_to_qsettings(host._settings)
    except Exception:
        logger.debug("application/close_controller.py:clear_ai_key_on_exit best-effort step failed", exc_info=True)


def _cancel_in_flight_workers(host: ExperienceHost) -> None:
    """Cancel and join every background worker still running on ``host``.

    The window teardown destroys the widget tree, and Qt destroys child
    ``QThread`` objects with it. A thread that is still running at that
    moment makes Qt print "QThread: Destroyed while thread is still
    running" and abort the process. The keepalive registry in
    ``ai_request_worker`` only protects against Python-side garbage
    collection — it does not stop Qt's parent/child destruction.

    Only ``_save_worker`` was joined before (T18). The other workers —
    course open, AI fill / batch regenerate, background validate, command
    palette LLM, TTS, publish — were left running.

    Each worker gets a short bounded wait: an unresponsive thread must not
    hang the close forever, but giving it a moment lets cooperative
    cancellation (``cancel()``) actually take effect.
    """
    # Attribute names of workers the host may own. Missing attributes are
    # skipped, so this stays valid as features are added or removed. The
    # list is shared with the cancel path so both see the same workers.
    from src.application.ai_request_worker import IN_FLIGHT_WORKER_ATTRS

    for attr in IN_FLIGHT_WORKER_ATTRS:
        worker = getattr(host, attr, None)
        if worker is None:
            continue
        try:
            # ``is True`` on purpose: a test double (MagicMock) answers
            # truthy to ``isRunning()`` and would then be waited on for the
            # full timeout — turning every close into a multi-second stall.
            # A real QThread answers a bool.
            if worker.isRunning() is not True:
                continue
            cancel = getattr(worker, "cancel", None)
            if callable(cancel):
                cancel()
            # Bounded join — cooperative cancellation needs a moment to be
            # observed by the running call.
            worker.wait(2000)
        except Exception:
            logger.debug(
                "application/close_controller.py:_cancel_in_flight_workers "
                "best-effort step failed",
                exc_info=True,
            )


def _start_close_save(host: ExperienceHost, event: Any, reason: str) -> None:
    """Save asynchronously and close the window once the save succeeds.

    The close path used to call ``execute_save`` synchronously, which froze
    the window for the whole save chain (two full CLI validate/lint scans,
    two deep copies of the course, a full backup copy). On a large course
    that is seconds of a dead window right as the user tries to quit.

    The save now runs on a worker; the close is deferred until it finishes.
    ``event.ignore()`` keeps the window alive in the meantime, and a second
    close request while the save is in flight is refused with a message —
    the "reject a second close until the save completes" rule that the
    long-term backlog asked for.

    Never raises: a failure leaves the window open and shows the error.
    """
    from src.application.ai_request_worker import AiRequestWorker
    from src.application.save_host import execute_save, want_save_brief
    from src.application.save_pipeline import SaveRequest
    from src.application.ui_guard import safe_warning
    from src.infrastructure.telemetry import telemetry

    if getattr(host, "_close_save_pending", False):
        event.ignore()
        safe_warning(
            host,
            "正在保存",
            "保存仍在进行，窗口暂不关闭，请稍后重试。",
        )
        return

    request = SaveRequest(
        reason=reason,
        run_soft=True,
        show_validation_ui=False,
        want_ai_brief=want_save_brief(host),
    )

    host._close_save_pending = True
    try:
        host.statusBar().showMessage("正在保存…")
    except Exception:
        logger.debug(
            "application/close_controller.py:_start_close_save "
            "best-effort step failed",
            exc_info=True,
        )

    def _finish(ok: bool, message: str, errors: list[dict]) -> None:
        host._close_save_pending = False
        if ok:
            telemetry.record_event("app.close_saved")
            # The window is closed by the caller re-triggering the close;
            # calling ``close()`` here would re-enter this handler with the
            # course still marked dirty.
            host._close_after_save = True
            # Observable outcome for the close path: the save succeeded and
            # the window was asked to close. (``_close_after_save`` is
            # consumed by the re-entrant closeEvent, so it cannot be used
            # for this.)
            host._close_saved_ok = True
            try:
                host.close()
            except Exception:
                logger.debug(
                    "application/close_controller.py:_finish best-effort step failed",
                    exc_info=True,
                )
            return
        detail_text = "\n".join(
            f"[{e.get('level', 'error')}] {e.get('message', '')}" for e in (errors or [])
        )
        safe_warning(
            host,
            "自动保存失败（窗口未关闭）" if reason == "close_auto" else "保存失败（窗口未关闭）",
            detail_text or message or "未知错误",
        )

    def _on_result(result) -> None:
        outcome = execute_save(host, request, prefetched=result)
        _finish(
            bool(outcome.ok),
            outcome.message or "",
            list(outcome.errors or []),
        )

    def _on_error(message: str) -> None:
        _finish(False, message, [])

    worker = AiRequestWorker(host.adapter.save)
    worker.result_ready.connect(_on_result)
    worker.error_occurred.connect(_on_error)
    host._save_worker = worker
    event.ignore()
    worker.start()


def handle_close_event(host: ExperienceHost, event: Any) -> None:
    """Handle MainWindow closeEvent body (accept/ignore + teardown)."""
    from src.application.ui_guard import is_headless_ui, safe_warning
    from src.infrastructure.telemetry import telemetry

    telemetry.record_event("app.close_requested")
    # Wait out an in-flight background save so the save thread never races
    # shutdown (equivalent to the old synchronous save on close).
    save_worker = getattr(host, "_save_worker", None)
    if save_worker is not None and save_worker.isRunning():
        try:
            host.statusBar().showMessage("正在保存…")
        except Exception:
            logger.debug("application/close_controller.py:handle_close_event best-effort step failed", exc_info=True)
        # T18: bounded wait — an unresponsive save thread must not hang the
        # close forever; the user gets told and can retry.
        if not save_worker.wait(5000):
            event.ignore()
            safe_warning(
                host,
                "仍在保存",
                "保存仍在进行，窗口暂不关闭，请稍后重试。",
            )
            return
    # The close-after-save path re-enters this handler via ``host.close()``.
    # The course was just saved, so it is clean — fall through to the normal
    # teardown. This flag makes the second pass unambiguous even if the
    # save pipeline left the undo stack dirty.
    #
    # Read-and-clear at the very top: the flag is consumed by this pass, so
    # it must not be cleared again further down (the re-entrant call would
    # otherwise wipe it before the caller could observe it).
    _close_after_save = bool(getattr(host, "_close_after_save", False))
    if _close_after_save:
        host._close_after_save = False

    course_dir = getattr(host, "course_dir", None)
    adapter = getattr(host, "adapter", None)
    dirty = False
    try:
        dirty = bool(
            course_dir
            and adapter
            and any(adapter.detect_changes().values())
        )
    except Exception:
        dirty = False

    if _close_after_save:
        dirty = False

    if dirty:
        from src.application.save_pipeline import (
            REASON_CLOSE_AUTO,
            REASON_CLOSE_PROMPT,
        )

        settings = getattr(host, "_settings_obj", None)
        auto_save = bool(getattr(settings, "auto_save_on_close", False))

        if auto_save:
            # Async: the window stays open (event.ignore()) until the save
            # worker finishes, then closes itself.
            _start_close_save(host, event, REASON_CLOSE_AUTO)
        else:
            if is_headless_ui():
                telemetry.record_event("app.close_discarded")
                event.accept()
            else:
                # Three-way, so it could not use safe_question: routed through
                # safe_question3 so an immersive-auto run is not blocked by a
                # modal. auto_choice=YES because blocking the close would
                # strand the window, and saving preserves the user's work
                # where discarding it would not.
                from src.application.ui_guard import NO, YES, safe_question3

                reply = safe_question3(
                    host,
                    "未保存的更改",
                    "当前课程有未保存的更改，是否保存？",
                    auto_choice=YES,
                )
                if reply == YES:
                    _start_close_save(host, event, REASON_CLOSE_PROMPT)
                elif reply == NO:
                    telemetry.record_event("app.close_discarded")
                    event.accept()
                else:
                    telemetry.record_event("app.close_cancelled")
                    event.ignore()
    else:
        event.accept()

    if not event.isAccepted():
        return

    # Stop and join every background worker still running. This must happen
    # before the widget tree is torn down: Qt destroys child QThread objects
    # with their parent, and a still-running thread aborts the process.
    _cancel_in_flight_workers(host)

    # W2: persist shell layout (docks/splitter/last view) before teardown.
    try:
        save_state = getattr(host, "_save_shell_state", None)
        if callable(save_state):
            save_state()
    except Exception:
        logger.debug("application/close_controller.py:handle_close_event best-effort step failed", exc_info=True)

    # C-15: persist Experience metrics before process teardown.
    try:
        host._flush_experience_metrics("app_close")
    except Exception:
        logger.debug("application/close_controller.py:handle_close_event best-effort step failed", exc_info=True)

    try:
        ww = getattr(host, "_workshop_window", None)
        if ww is not None:
            ww.interrupt_and_save()
            ww.close()
            host._workshop_window = None
    except Exception:
        host._workshop_window = None

    try:
        ow = getattr(host, "_overview_window", None)
        if ow is not None:
            ow.close()
            host._overview_window = None
    except Exception:
        host._overview_window = None
    host._overview_widget = None

    runtime_context.clear_providers(host)
    clear_ai_key_on_exit(host)
    try:
        host._record_window_duration()
    except Exception:
        logger.debug("application/close_controller.py:handle_close_event best-effort step failed", exc_info=True)
