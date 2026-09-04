"""Global QApplication event filter that records low-level user actions.

Installed once in ``main.py`` via ``app.installEventFilter(UserActionFilter(app))``.
Captures:

* ``MouseButtonPress`` → ``ui.click`` with the target widget's text/label and
  the active window title as context.
* ``FocusOut`` on ``QLineEdit``/``QTextEdit`` (and ``Enter/Return`` key commits
  on ``QLineEdit``) → ``ui.input.commit`` with the committed text.

Privacy: the AI API key field (``QLineEdit`` with ``EchoMode.Password`` or
``objectName == "ai_key_edit"``) is always recorded as ``<redacted>``; the real
value never reaches the log. Captured text is truncated to keep lines bounded.

The filter never raises and always returns ``False`` so normal event dispatch
continues uninterrupted (mirrors the "telemetry must never crash" invariant).
"""
from __future__ import annotations

from PySide6.QtCore import QElapsedTimer, QEvent, QObject
from PySide6.QtWidgets import (
    QApplication,
    QLineEdit,
    QTextEdit,
    QWidget,
)

from src.infrastructure.operations_log import operations
import logging
logger = logging.getLogger(__name__)

_MAX_TEXT = 200
_MAX_TARGET = 80
_REDACTED = "<redacted>"
_REDACTED_OBJECT_NAMES = {"ai_key_edit"}
# Dedupe rapid repeat clicks on the same (window, target): a burst of clicks
# within this window collapses to a single record. First click always records.
_CLICK_DEBOUNCE_MS = 300


def _window_name(widget: QWidget | None) -> str:
    """Best-effort human label for the active window."""
    try:
        app = QApplication.instance()
        window = app.activeWindow() if app is not None else None
        if window is not None:
            return window.windowTitle() or window.objectName() or type(window).__name__
    except Exception:
        logger.debug("infrastructure/user_action_filter.py:_window_name best-effort step failed", exc_info=True)
    if widget is not None:
        try:
            top = widget.window()
            return top.windowTitle() or top.objectName() or type(top).__name__
        except Exception:
            logger.debug("infrastructure/user_action_filter.py:_window_name best-effort step failed", exc_info=True)
    return ""


def _target_name(obj: QObject) -> str:
    """Best-effort label for the widget that was clicked/focused."""
    name = ""
    # For password/secret line edits, ``text()`` returns the secret value —
    # never use it as the target label.
    is_secret = False
    try:
        if isinstance(obj, QLineEdit) and (
            obj.echoMode() == QLineEdit.EchoMode.Password
            or obj.objectName() in _REDACTED_OBJECT_NAMES
        ):
            is_secret = True
    except Exception:
        logger.debug("infrastructure/user_action_filter.py:_target_name best-effort step failed", exc_info=True)

    getters = ("text", "windowTitle", "title") if not is_secret else ("windowTitle", "title")
    for getter in getters:
        try:
            method = getattr(obj, getter, None)
            if callable(method):
                value = method()
                if value:
                    name = str(value)
                    break
        except Exception:
            continue
    if not name:
        try:
            name = obj.objectName() or ""
        except Exception:
            name = ""
    if not name:
        name = type(obj).__name__
    return name[:_MAX_TARGET]


def _committed_text(widget: QWidget) -> str:
    """Return the committed text, redacting password/secret fields."""
    try:
        if isinstance(widget, QLineEdit):
            if (
                widget.echoMode() == QLineEdit.EchoMode.Password
                or widget.objectName() in _REDACTED_OBJECT_NAMES
            ):
                return _REDACTED
            return widget.text()[:_MAX_TEXT]
        if isinstance(widget, QTextEdit):
            return widget.toPlainText()[:_MAX_TEXT]
    except Exception:
        return _REDACTED
    return ""


class UserActionFilter(QObject):
    """Single global event filter recording clicks and input commits."""

    def __init__(self, parent: QObject | None = None) -> None:
        super().__init__(parent)
        # Dedupe key: (window_name, target_name) -> elapsed ms of last record.
        self._last_click: tuple[str, str] = ("", "")
        self._last_click_ts: int = -_CLICK_DEBOUNCE_MS
        self._click_clock = QElapsedTimer()
        self._click_clock.start()

    def eventFilter(self, obj: QObject, event: QEvent) -> bool:  # noqa: N802
        try:
            etype = event.type()
            if etype == QEvent.Type.MouseButtonPress and isinstance(obj, QWidget):
                target = _target_name(obj)
                if target:
                    window = _window_name(obj)
                    key = (window, target)
                    now = self._click_clock.elapsed()
                    if key == self._last_click and (now - self._last_click_ts) < _CLICK_DEBOUNCE_MS:
                        return False
                    self._last_click = key
                    self._last_click_ts = now
                    operations.record_action(
                        "click",
                        target,
                        context={"window": window, "widget": type(obj).__name__},
                    )
            elif etype == QEvent.Type.FocusOut and isinstance(obj, (QLineEdit, QTextEdit)):
                text = _committed_text(obj)
                # Skip empty commits to keep the log focused on real input.
                if text:
                    operations.record_action(
                        "input.commit",
                        _target_name(obj),
                        payload={"text": text},
                        context={"window": _window_name(obj), "widget": type(obj).__name__},
                    )
            elif etype == QEvent.Type.KeyPress and isinstance(obj, QLineEdit):
                key = event.key()
                if key in (QEvent.Key.Return, QEvent.Key.Enter):
                    text = _committed_text(obj)
                    if text:
                        operations.record_action(
                            "input.commit",
                            _target_name(obj),
                            payload={"text": text},
                            context={"window": _window_name(obj), "widget": type(obj).__name__},
                        )
        except Exception:
            # Telemetry must never crash the application.
            logger.debug("infrastructure/user_action_filter.py:eventFilter best-effort step failed", exc_info=True)
        return False