"""Presence visual host (R1 / P0-a) — job lockout only; no mouse-follow cursor.

P0-a: continuous secondary-cursor tracking is **off by default and not auto-
enabled by immersive/sovereign**. It was decorative, expensive, and did not
drive AI. Optional debug follow remains behind settings flag only.

Job begin/end may still show a light lockout rect when
``experience_job_lockout_visual`` is true (default True).
"""
from __future__ import annotations

from typing import Any, Optional

from src.backend.experience.policy import resolve_policy


def presence_level_of(host: Any) -> int:
    try:
        settings = getattr(host, "_settings_obj", None)
        return int(resolve_policy(settings).presence_level)
    except Exception:
        return 1


def _settings_flag(host: Any, name: str, default: bool = False) -> bool:
    try:
        s = getattr(host, "_settings_obj", None)
        if s is None:
            return default
        return bool(getattr(s, name, default))
    except Exception:
        return default


def should_follow_mouse(host: Any) -> bool:
    """Continuous mouse reticle — opt-in debug only (default False)."""
    try:
        if presence_level_of(host) < 1:
            return False
        return _settings_flag(host, "experience_gaze_cursor", False)
    except Exception:
        return False


def should_show_secondary_cursor(host: Any) -> bool:
    """Back-compat name: means continuous mouse tracking (almost always False)."""
    return should_follow_mouse(host)


def should_job_lockout_visual(host: Any) -> bool:
    """Light lockout chrome during AI jobs (default True)."""
    return _settings_flag(host, "experience_job_lockout_visual", True)


def sync_secondary_cursor(host: Any) -> None:
    """Enable/disable mouse-follow tracking only. Never raises."""
    if host is None:
        return
    try:
        overlay = getattr(host, "_gaze_overlay", None)
        if overlay is None:
            return
        want = should_follow_mouse(host)
        if hasattr(overlay, "enable_tracking"):
            overlay.enable_tracking(want)
        if want:
            try:
                overlay.setGeometry(host.rect())
                overlay.raise_()
            except Exception:
                pass
        _sync_mouse_filter(host, want)
    except Exception:
        pass


def ensure_secondary_cursor(host: Any) -> Any:
    """Create overlay if missing; sync mouse-follow (usually off)."""
    if host is None:
        return None
    try:
        overlay = getattr(host, "_gaze_overlay", None)
        if overlay is None:
            from src.widgets.gaze_cursor_overlay import GazeCursorOverlay

            overlay = GazeCursorOverlay(host)
            host._gaze_overlay = overlay
            try:
                overlay.setGeometry(host.rect())
            except Exception:
                pass
        sync_secondary_cursor(host)
        return overlay
    except Exception:
        try:
            host._gaze_overlay = None
        except Exception:
            pass
        return None


def on_mouse_global(host: Any, global_pos: Any) -> None:
    """Forward global mouse position only when follow is explicitly on."""
    try:
        if not should_follow_mouse(host):
            return
        overlay = getattr(host, "_gaze_overlay", None)
        if overlay is None:
            return
        if hasattr(overlay, "is_tracking_enabled") and not overlay.is_tracking_enabled():
            return
        if hasattr(overlay, "set_mouse_global"):
            overlay.set_mouse_global(global_pos)
    except Exception:
        pass


def begin_job(
    host: Any,
    *,
    node_id: str = "",
    label: str = "AI working",
    target_widget: Any = None,
) -> None:
    """Optional lockout chrome around target; does not start mouse-follow."""
    del node_id
    try:
        if not should_job_lockout_visual(host):
            return
        overlay = ensure_secondary_cursor(host)
        if overlay is None:
            return
        # Never enable continuous tracking for a job.
        if hasattr(overlay, "enable_tracking"):
            if not should_follow_mouse(host):
                overlay.enable_tracking(False)
        rect = _resolve_job_rect(host, target_widget)
        text = f"[AI] {label}"[:64]
        try:
            overlay.setGeometry(host.rect())
            overlay.show()
            overlay.raise_()
        except Exception:
            pass
        if hasattr(overlay, "set_lockout"):
            overlay.set_lockout(rect, text)
        if target_widget is not None:
            try:
                if not hasattr(host, "_presence_lock_widgets"):
                    host._presence_lock_widgets = []
                prior = (
                    bool(target_widget.isEnabled())
                    if hasattr(target_widget, "isEnabled")
                    else True
                )
                host._presence_lock_widgets.append((target_widget, prior))
                if hasattr(target_widget, "setEnabled"):
                    target_widget.setEnabled(False)
            except Exception:
                pass
        try:
            sb = getattr(host, "statusBar", None)
            if callable(sb):
                bar = sb()
                if bar is not None and hasattr(bar, "showMessage"):
                    bar.showMessage(f"AI 处理中：{label}", 4000)
        except Exception:
            pass
    except Exception:
        pass


def end_job(host: Any, node_id: str = "") -> None:
    """Clear lockout and restore disabled widgets."""
    del node_id
    try:
        overlay = getattr(host, "_gaze_overlay", None)
        if overlay is not None and hasattr(overlay, "clear_lockout"):
            overlay.clear_lockout()
        if overlay is not None and not should_follow_mouse(host):
            try:
                if hasattr(overlay, "enable_tracking"):
                    overlay.enable_tracking(False)
                overlay.hide()
            except Exception:
                pass
        locked = getattr(host, "_presence_lock_widgets", None) or []
        host._presence_lock_widgets = []
        for widget, prior in locked:
            try:
                if widget is not None and hasattr(widget, "setEnabled"):
                    widget.setEnabled(bool(prior))
            except Exception:
                pass
    except Exception:
        pass


def _resolve_job_rect(host: Any, target_widget: Any) -> Any:
    """Best-effort QRect in host coordinates for lockout chrome."""
    from PySide6.QtCore import QRect

    if target_widget is not None:
        try:
            top_left = target_widget.mapTo(host, target_widget.rect().topLeft())
            return QRect(top_left, target_widget.rect().size())
        except Exception:
            pass
    try:
        tree = getattr(host, "tree", None)
        tree_widget = getattr(tree, "tree", tree) if tree is not None else None
        if tree_widget is not None and hasattr(tree_widget, "currentItem"):
            item = tree_widget.currentItem()
            if item is not None:
                vrect = tree_widget.visualItemRect(item)
                top_left = tree_widget.mapTo(host, vrect.topLeft())
                return QRect(top_left, vrect.size())
    except Exception:
        pass
    return QRect(12, 40, 180, 36)


class _PresenceMouseFilter:
    """QObject event filter: forward mouse moves only when follow is on."""

    def __init__(self, host: Any) -> None:
        self._host = host

    def eventFilter(self, obj: Any, event: Any) -> bool:  # noqa: N802
        del obj
        try:
            from PySide6.QtCore import QEvent

            if event is None:
                return False
            et = event.type()
            if et in (QEvent.Type.MouseMove, QEvent.Type.HoverMove):
                if hasattr(event, "globalPosition"):
                    gp = event.globalPosition().toPoint()
                elif hasattr(event, "globalPos"):
                    gp = event.globalPos()
                else:
                    return False
                on_mouse_global(self._host, gp)
        except Exception:
            pass
        return False


def _sync_mouse_filter(host: Any, want: bool) -> None:
    """Install app-level mouse filter only while continuous follow is on."""
    try:
        from PySide6.QtCore import QObject
        from PySide6.QtWidgets import QApplication

        app = QApplication.instance()
        if app is None:
            return
        filt = getattr(host, "_presence_mouse_filter", None)
        if want:
            if filt is None:

                class _Filter(QObject):
                    def __init__(self, h: Any) -> None:
                        super().__init__()
                        self._impl = _PresenceMouseFilter(h)

                    def eventFilter(self, obj, event):  # noqa: N802
                        return self._impl.eventFilter(obj, event)

                filt = _Filter(host)
                host._presence_mouse_filter = filt
                app.installEventFilter(filt)
                try:
                    host.setMouseTracking(True)
                except Exception:
                    pass
        else:
            if filt is not None:
                try:
                    app.removeEventFilter(filt)
                except Exception:
                    pass
                try:
                    host._presence_mouse_filter = None
                except Exception:
                    pass
    except Exception:
        pass
