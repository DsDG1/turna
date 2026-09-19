"""Global QApplication event filter keeping top-level windows on-screen.

Installed once in ``main.py`` via ``install_screen_clamp(app)``. Dialogs and
sub-windows ship hard-coded ``resize()`` calls sized for large desktops
(e.g. 1180×860); on small laptops, at 150% UI font scale, or with tall
taskbars they exceed the screen and their bottom half becomes unreachable.
On every :class:`QDialog` / :class:`QMainWindow` ``Show`` the filter clamps
the window to its screen's available geometry and — only when a clamp was
needed — re-centers it. Windows already inside the screen keep their
user-chosen position and size; maximized / full-screen windows are skipped.

The filter never raises; on any internal error normal dispatch continues.
"""
from __future__ import annotations

import logging

from PySide6.QtCore import QEvent, QObject
from PySide6.QtWidgets import QApplication, QDialog, QMainWindow, QWidget

logger = logging.getLogger(__name__)


class ScreenClampFilter(QObject):
    """Clamps top-level dialogs/windows into the available screen area."""

    def eventFilter(self, obj: QObject, event: QEvent) -> bool:
        if event.type() != QEvent.Type.Show:
            return False
        try:
            if not isinstance(obj, (QDialog, QMainWindow)):
                return False
            if obj.parentWidget() is not None:  # embedded pages only
                return False
            if obj.isMaximized() or obj.isFullScreen():
                return False
            clamp_to_screen(obj)
        except Exception:
            logger.debug("screen_fit: clamp step failed", exc_info=True)
        return False


def clamp_to_screen(widget: QWidget) -> bool:
    """Resize *widget* into its screen's available area; recenter if resized.

    Window-frame margins are reserved so the *frame* (not just the client
    area) fits the screen. ``resize`` cannot go below the layout's minimum
    size — for pathological minimums pair this filter with layout fixes
    (FlowLayout / word-wrapped labels) so windows *can* shrink.
    """
    screen = widget.screen()
    if screen is None:
        app = QApplication.instance()
        if app is None:
            return False
        screen = app.primaryScreen()
        if screen is None:
            return False
    avail = screen.availableGeometry()

    frame = widget.frameGeometry()
    frame_w = max(0, frame.width() - widget.width())
    frame_h = max(0, frame.height() - widget.height())
    width = max(1, min(widget.width(), avail.width() - frame_w))
    height = max(1, min(widget.height(), avail.height() - frame_h))
    changed = (width, height) != (widget.width(), widget.height())
    if changed:
        widget.resize(width, height)
        # Center the frame in the available area; keep the client offset
        # inside its frame (offscreen/WMs may draw asymmetric borders).
        left_border = widget.x() - frame.left()
        top_border = widget.y() - frame.top()
        frame_x = avail.center().x() - (width + frame_w) // 2
        frame_y = avail.center().y() - (height + frame_h) // 2
        widget.move(
            max(avail.left() - left_border,
                min(frame_x + left_border, avail.right() + 1 - left_border - width)),
            max(avail.top() - top_border,
                min(frame_y + top_border, avail.bottom() + 1 - top_border - height)),
        )
    else:
        # Fits already; just nudge back if the frame drifted off any edge.
        dx = 0
        if frame.left() < avail.left():
            dx = avail.left() - frame.left()
        elif frame.right() > avail.right():
            dx = avail.right() - frame.right()
        dy = 0
        if frame.top() < avail.top():
            dy = avail.top() - frame.top()
        elif frame.bottom() > avail.bottom():
            dy = avail.bottom() - frame.bottom()
        if dx or dy:
            widget.move(widget.x() + dx, widget.y() + dy)
            changed = True
    return changed


def install_screen_clamp(app: QApplication) -> ScreenClampFilter:
    """Install the app-wide screen clamp; safe to call once per process."""
    guard = ScreenClampFilter(app)
    app.installEventFilter(guard)
    return guard
