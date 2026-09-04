"""M-05 screenshot-explain controller (application layer; Qt-allowed).

Splits the Qt-touching capture out of the pure
``backend/experience/screenshot_skill.py`` to honour §7.4 (no Qt in the
``backend/experience`` pure-logic package). ``capture_widget_to_png_bytes``
uses ``QWidget.grab()``; ``explain_current`` mirrors K-24
``_experience_git_skill`` (read-only LLM flow: switch/config/window guards →
job → ``_make_ai_worker`` → ``_on_ok``/``_on_err`` → read-only preview).

红线：只读——不写课程树、无 ConflictGuard/sandbox/Undo；默认关
（``experience/screenshot_explain``）；offscreen/无窗/未开启→statusBar 非模态；
Timeline 只记 action_id + ``truncate_reply``（≤80），不记截图/回复原文（§14.5.3）。
"""
from __future__ import annotations

from typing import Any, Tuple
import logging
logger = logging.getLogger(__name__)

ACTION_ID = "app.screenshot_explain"
JOB_ID = "screenshot-explain"
JOB_LABEL = "截图解释"


def capture_widget_to_png_bytes(widget: Any) -> Tuple[bytes, str]:
    """Capture a QWidget to PNG bytes via ``grab()``.

    Returns ``(png_bytes, status)`` where status ∈ {"ok","no_window","failed"}.
    Never raises — Qt failures degrade to ("", "failed").
    """
    if widget is None:
        return b"", "no_window"
    try:
        from PySide6.QtCore import QBuffer, QIODevice
        from PySide6.QtGui import QImage

        pix = widget.grab()
        if pix is None:
            return b"", "failed"
        image = pix.toImage()
        if image is None or image.isNull():
            return b"", "failed"
        # Normalize format before encoding so all platforms produce valid PNG.
        if image.format() != QImage.Format.Format_RGBA8888:
            converted = image.convertToFormat(QImage.Format.Format_RGBA8888)
            if not converted.isNull():
                image = converted
        buf = QBuffer()
        buf.open(QIODevice.OpenModeFlag.WriteOnly)
        ok = image.save(buf, "PNG")
        buf.close()
        if not ok:
            return b"", "failed"
        data = bytes(buf.data())
        return data or b"", "ok" if data else "failed"
    except Exception:  # noqa: BLE001
        return b"", "failed"


def _enabled(win: Any) -> bool:
    from src.backend.experience.screenshot_skill import is_screenshot_explain_enabled

    return is_screenshot_explain_enabled(getattr(win, "_settings_obj", None))


def explain_current(win: Any) -> None:
    """M-05: capture the main window → LLM explanation → read-only preview.

    Read-only flow mirroring K-24 ``_experience_git_skill``. ``win`` duck-types
    the main window: ``_settings_obj``, ``_ai_config``, ``job_tray``,
    ``experience_metrics``, ``statusBar``, ``_make_ai_worker``,
    ``_record_experience_event``, ``_show_git_skill_result``,
    ``_experience_worker``.
    """
    if not _enabled(win):
        win.statusBar().showMessage(
            "截图解释未开启（设置 ▸ 体验 OS 勾选「截图解释」）", 6000
        )
        return
    # Offscreen / no live GUI: headless guard (mirror K-24 offscreen policy).
    try:
        from PySide6.QtWidgets import QApplication

        app = QApplication.instance()
        if app is None or app.platformName() == "offscreen":
            win.statusBar().showMessage("截图解释需在可视化窗口运行", 5000)
            return
    except Exception:  # noqa: BLE001
        win.statusBar().showMessage("截图解释：GUI 不可用", 5000)
        return

    config = getattr(win, "_ai_config", None)
    if config is None or not getattr(config, "is_complete", False):
        win.statusBar().showMessage("AI 配置不完整：设置 ▸ AI 填写 Key/Model", 5000)
        return

    png_bytes, status = capture_widget_to_png_bytes(win)
    if status != "ok" or not png_bytes:
        win.statusBar().showMessage(f"截图失败（{status}）", 6000)
        return

    from src.backend.experience.screenshot_skill import run_screenshot_skill

    tray = getattr(win, "job_tray", None)
    metrics = getattr(win, "experience_metrics", None)
    if tray is not None:
        tray.start(JOB_ID, f"{JOB_LABEL}：正在生成 …", kind="ai")
    if metrics is not None:
        metrics.inc_job("ai", "started")
        metrics.inc_suggestion(ACTION_ID, "accepted")
    if hasattr(win, "_refresh_experience"):
        try:
            win._refresh_experience(immediate=False, focus_only=True)
        except Exception:  # noqa: BLE001
            logger.debug("application/screenshot_controller.py:explain_current best-effort step failed", exc_info=True)

    worker = win._make_ai_worker(run_screenshot_skill, config, png_bytes, None)

    def _on_ok(text: object) -> None:
        if tray is not None:
            tray.finish(JOB_ID)
        if metrics is not None:
            metrics.inc_job("ai", "finished")
        reply = str(text) if text is not None else ""
        if not reply.strip():
            win.statusBar().showMessage(f"{JOB_LABEL}：AI 返回为空", 5000)
            return
        try:
            # §14.5.3: Timeline records only action_id + a fixed short label,
            # never the screenshot or the full reply body (mirrors K-24).
            win._record_experience_event(
                ACTION_ID,
                JOB_LABEL,
                action_id=ACTION_ID,
                scope={},
            )
        except Exception:  # noqa: BLE001
            logger.debug("application/screenshot_controller.py:_on_ok best-effort step failed", exc_info=True)
        if metrics is not None:
            metrics.inc_suggestion(ACTION_ID, "applied")
        # Reuse K-24 read-only preview (offscreen guard inside).
        win._show_git_skill_result(JOB_LABEL, reply)

    def _on_err(msg: str) -> None:
        if tray is not None:
            tray.finish(JOB_ID)
        if metrics is not None:
            metrics.inc_job("ai", "failed")
        # Non-modal: avoid hanging headless runners on unclicked MessageBox.
        win.statusBar().showMessage(f"{JOB_LABEL}失败：{msg}", 8000)

    worker.result_ready.connect(_on_ok)
    worker.error_occurred.connect(_on_err)
    worker.start()
    win._experience_worker = worker