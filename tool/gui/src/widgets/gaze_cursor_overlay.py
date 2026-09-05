"""AI secondary cursor overlay (R1) — follows the real mouse pointer.

Naming history: "GazeCursor" / Lockout Gaze. This is **not** eye tracking;
it is a secondary reticle that tracks the system mouse when immersive /
sovereign presence is active, plus optional job lockout chrome.

Invariants:
- Transparent for mouse events unless lockout is active.
- Timer only runs while tracking is enabled (no idle CPU in copilot).
- Never raises into the editor.
"""
from __future__ import annotations

import logging
logger = logging.getLogger(__name__)


from typing import Optional

from PySide6.QtCore import QPoint, QRect, QTimer, Qt
from PySide6.QtGui import QColor, QFont, QPainter, QPen
from PySide6.QtWidgets import QWidget


class GazeCursorOverlay(QWidget):
    """Transparent overlay: secondary cursor + optional job lockout."""

    def __init__(self, parent: Optional[QWidget] = None) -> None:
        super().__init__(parent)
        self.setAttribute(Qt.WA_TransparentForMouseEvents, True)
        self.setAttribute(Qt.WA_NoSystemBackground, True)
        self.setAttribute(Qt.WA_TranslucentBackground, True)
        self.setFocusPolicy(Qt.FocusPolicy.NoFocus)

        self._enabled: bool = False
        self._cursor_pos: QPoint = QPoint(-100, -100)
        self._target_pos: QPoint = QPoint(-100, -100)
        self._is_locked: bool = False
        self._locked_rect: Optional[QRect] = None
        self._lock_text: str = ""
        self._snap_pos: Optional[QPoint] = None  # job attractor (optional)

        self._anim_timer = QTimer(self)
        # P1: ~14 fps — enough for a secondary cue, less main-thread load.
        self._anim_timer.setInterval(70)
        self._anim_timer.timeout.connect(self._on_tick)
        # Do not start until enable_tracking(True).
        self._poll_system_cursor: bool = True
        self._last_paint_pos: QPoint = QPoint(-9999, -9999)

        self.hide()

    # --- lifecycle -------------------------------------------------------

    def enable_tracking(self, on: bool) -> None:
        """Start/stop mouse following. Off → hide + stop timer."""
        want = bool(on)
        if want == self._enabled and (want is False or self._anim_timer.isActive()):
            if not want:
                self._stop_idle()
            return
        self._enabled = want
        if want:
            self.show()
            self.raise_()
            if not self._anim_timer.isActive():
                self._anim_timer.start()
            self.update()
        else:
            self._stop_idle()

    def is_tracking_enabled(self) -> bool:
        return bool(self._enabled)

    def _stop_idle(self) -> None:
        try:
            if self._anim_timer.isActive():
                self._anim_timer.stop()
        except Exception:
            logger.debug("widgets/gaze_cursor_overlay.py:75 best-effort step failed", exc_info=True)
        self._is_locked = False
        self._locked_rect = None
        self._lock_text = ""
        self._snap_pos = None
        self.hide()

    # --- mouse / target --------------------------------------------------

    def set_mouse_global(self, global_pos: QPoint) -> None:
        """Update target from a global mouse position (main path)."""
        if not self._enabled:
            return
        try:
            local = self.mapFromGlobal(global_pos)
            self._target_pos = QPoint(local)
            if self._snap_pos is not None and self._is_locked:
                # Soft attract toward job target while locked.
                sx, sy = self._snap_pos.x(), self._snap_pos.y()
                mx, my = local.x(), local.y()
                self._target_pos = QPoint(
                    int(mx * 0.35 + sx * 0.65),
                    int(my * 0.35 + sy * 0.65),
                )
        except Exception:
            logger.debug("widgets/gaze_cursor_overlay.py:100 best-effort step failed", exc_info=True)

    def set_gaze_target(self, pos: QPoint) -> None:
        """Legacy API: set target in overlay-local coordinates."""
        if not self._enabled:
            return
        try:
            self._target_pos = QPoint(pos)
        except Exception:
            logger.debug("widgets/gaze_cursor_overlay.py:109 best-effort step failed", exc_info=True)

    # --- lockout ---------------------------------------------------------

    def set_lockout(
        self,
        rect: Optional[QRect],
        text: str = "[LOCKOUT] AI working",
        *,
        snap_to_center: bool = True,
    ) -> None:
        """Visually mark a node rect; intercept presses inside it."""
        self._locked_rect = rect
        self._is_locked = bool(rect is not None and not rect.isNull())
        self._lock_text = str(text or "")
        if self._is_locked and rect is not None and snap_to_center:
            self._snap_pos = rect.center()
            self._target_pos = QPoint(self._snap_pos)
        else:
            self._snap_pos = None
        # Only capture mouse when locked so normal UI stays clickable.
        self.setAttribute(Qt.WA_TransparentForMouseEvents, not self._is_locked)
        if self._enabled:
            self.show()
            self.raise_()
            self.update()

    def clear_lockout(self) -> None:
        """Release input lockout chrome."""
        self._is_locked = False
        self._locked_rect = None
        self._lock_text = ""
        self._snap_pos = None
        self.setAttribute(Qt.WA_TransparentForMouseEvents, True)
        self.update()

    def is_locked(self) -> bool:
        return bool(self._is_locked)

    # --- animation / paint -----------------------------------------------

    def _on_tick(self) -> None:
        """Poll system cursor (reliable) then lerp the secondary reticle."""
        if not self._enabled:
            self._anim_timer.stop()
            return
        try:
            if self._poll_system_cursor:
                from PySide6.QtGui import QCursor

                self.set_mouse_global(QCursor.pos())
        except Exception:
            logger.debug("widgets/gaze_cursor_overlay.py:161 best-effort step failed", exc_info=True)
        if self._cursor_pos == self._target_pos and not self._is_locked:
            return
        try:
            dx = self._target_pos.x() - self._cursor_pos.x()
            dy = self._target_pos.y() - self._cursor_pos.y()
            # Fast follow (~mouse lag feel without being sticky).
            nx = int(self._cursor_pos.x() + dx * 0.45)
            ny = int(self._cursor_pos.y() + dy * 0.45)
            self._cursor_pos.setX(nx)
            self._cursor_pos.setY(ny)
            # P1: skip full repaint when movement is sub-pixel noise.
            if not self._is_locked:
                pdx = abs(nx - self._last_paint_pos.x())
                pdy = abs(ny - self._last_paint_pos.y())
                if pdx < 2 and pdy < 2:
                    return
            self._last_paint_pos = QPoint(nx, ny)
            self.update()
        except Exception:
            logger.debug("widgets/gaze_cursor_overlay.py:181 best-effort step failed", exc_info=True)

    def mousePressEvent(self, event) -> None:  # noqa: N802
        try:
            if (
                self._is_locked
                and self._locked_rect is not None
                and self._locked_rect.contains(event.position().toPoint())
            ):
                event.accept()
                return
            event.ignore()
        except Exception:
            try:
                event.ignore()
            except Exception:
                logger.debug("widgets/gaze_cursor_overlay.py:197 best-effort step failed", exc_info=True)

    def paintEvent(self, event) -> None:  # noqa: N802
        del event
        if not self._enabled and not self._is_locked:
            return
        try:
            painter = QPainter(self)
            painter.setRenderHint(QPainter.RenderHint.Antialiasing)

            if self._is_locked:
                # Mild dim — not full-window blackout.
                painter.fillRect(self.rect(), QColor(0, 0, 0, 40))

            if self._is_locked and self._locked_rect is not None:
                pen = QPen(QColor(255, 60, 60, 220), 2, Qt.PenStyle.DashLine)
                painter.setPen(pen)
                painter.setBrush(QColor(255, 60, 60, 40))
                painter.drawRoundedRect(self._locked_rect, 6, 6)
                painter.setPen(QColor(255, 80, 80))
                font = QFont("Sans-Serif", 9, QFont.Weight.Bold)
                painter.setFont(font)
                painter.drawText(
                    self._locked_rect.left() + 8,
                    self._locked_rect.top() + 18,
                    self._lock_text[:64],
                )

            if self._enabled and not self._cursor_pos.isNull():
                if self._cursor_pos.x() < -50 and self._cursor_pos.y() < -50:
                    painter.end()
                    return
                gaze_color = (
                    QColor(255, 60, 60, 220)
                    if self._is_locked
                    else QColor(0, 180, 255, 180)
                )
                painter.setPen(QPen(gaze_color, 2))
                painter.setBrush(
                    QColor(gaze_color.red(), gaze_color.green(), gaze_color.blue(), 40)
                )
                painter.drawEllipse(self._cursor_pos, 12, 12)
                painter.setBrush(gaze_color)
                painter.drawEllipse(self._cursor_pos, 3, 3)

            painter.end()
        except Exception:
            logger.debug("widgets/gaze_cursor_overlay.py:244 best-effort step failed", exc_info=True)
