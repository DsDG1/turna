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


def handle_close_event(host: ExperienceHost, event: Any) -> None:
    """Handle MainWindow closeEvent body (accept/ignore + teardown)."""
    from src.application.ui_guard import is_headless_ui, safe_warning
    from src.infrastructure.telemetry import telemetry

    telemetry.record_event("app.close_requested")
    # Wait out an in-flight background save so the save thread never races
    # shutdown (equivalent to the old synchronous save on close).
    save_worker = getattr(host, "_save_worker", None)
    if save_worker is not None and save_worker.isRunning():
        save_worker.wait()
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

    if dirty:
        from src.application.save_host import execute_save
        from src.application.save_pipeline import (
            REASON_CLOSE_AUTO,
            REASON_CLOSE_PROMPT,
            SaveRequest,
        )

        settings = getattr(host, "_settings_obj", None)
        auto_save = bool(getattr(settings, "auto_save_on_close", False))

        if auto_save:
            outcome = execute_save(
                host,
                SaveRequest(
                    reason=REASON_CLOSE_AUTO,
                    run_soft=True,
                    show_validation_ui=False,
                ),
            )
            if outcome.ok:
                telemetry.record_event("app.close_saved")
                event.accept()
            else:
                event.ignore()
                detail_text = "\n".join(
                    f"[{e.get('level', 'error')}] {e.get('message', '')}"
                    for e in (outcome.errors or [])
                )
                safe_warning(
                    host,
                    "自动保存失败（窗口未关闭）",
                    detail_text or outcome.message or "未知错误",
                )
        else:
            if is_headless_ui():
                telemetry.record_event("app.close_discarded")
                event.accept()
            else:
                from PySide6.QtWidgets import QMessageBox

                reply = QMessageBox.question(
                    host,
                    "未保存的更改",
                    "当前课程有未保存的更改，是否保存？",
                    (
                        QMessageBox.StandardButton.Save
                        | QMessageBox.StandardButton.Discard
                        | QMessageBox.StandardButton.Cancel
                    ),
                    QMessageBox.StandardButton.Save,
                )
                if reply == QMessageBox.StandardButton.Save:
                    outcome = execute_save(
                        host,
                        SaveRequest(
                            reason=REASON_CLOSE_PROMPT,
                            run_soft=True,
                            show_validation_ui=False,
                        ),
                    )
                    if outcome.ok:
                        telemetry.record_event("app.close_saved")
                        event.accept()
                    else:
                        event.ignore()
                        detail_text = "\n".join(
                            f"[{e.get('level', 'error')}] {e.get('message', '')}"
                            for e in (outcome.errors or [])
                        )
                        safe_warning(
                            host,
                            "保存失败（窗口未关闭）",
                            detail_text or outcome.message or "未知错误",
                        )
                elif reply == QMessageBox.StandardButton.Discard:
                    telemetry.record_event("app.close_discarded")
                    event.accept()
                else:
                    telemetry.record_event("app.close_cancelled")
                    event.ignore()
    else:
        event.accept()

    if not event.isAccepted():
        return

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

    runtime_context.clear_providers(host)
    clear_ai_key_on_exit(host)
    try:
        host._record_window_duration()
    except Exception:
        logger.debug("application/close_controller.py:handle_close_event best-effort step failed", exc_info=True)
