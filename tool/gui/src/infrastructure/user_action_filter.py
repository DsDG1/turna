"""Global QApplication event filter that records low-level user actions.

Installed once in ``main.py`` via ``app.installEventFilter(UserActionFilter(app))``.
Captures:

* ``MouseButtonPress`` → ``ui.click`` with the target widget's text/label and
  the active window title as context.
* ``FocusOut`` on ``QLineEdit``/``QTextEdit`` (and ``Enter/Return`` key commits
  on ``QLineEdit``) → ``ui.input.commit``.

Privacy
-------
Input commits record a **fingerprint, not the content**: ``{"chars": n,
"sha": "<8 hex>"}``. Enough to tell "an edit happened, it was 12 chars, and
it is/isn't the same edit as last time" — which is what the log is actually
used for — without copying course text, AI prompts or chat drafts onto disk.
The full text is only written when ``TURNA_GUI_LOG_INPUT_TEXT=1`` is set
explicitly, for the rare session that needs it.

Secret fields (AI API key: ``EchoMode.Password`` or ``objectName ==
"ai_key_edit"``) are recorded as ``{"text": "<redacted>"}`` and never
fingerprinted, so neither the value nor its length leaks.

The filter never raises and always returns ``False`` so normal event dispatch
continues uninterrupted (mirrors the "telemetry must never crash" invariant).
"""
from __future__ import annotations

import hashlib
import logging
import os

from PySide6.QtCore import QElapsedTimer, QEvent, QObject
from PySide6.QtWidgets import (
    QApplication,
    QLineEdit,
    QTextEdit,
    QWidget,
)

from src.infrastructure.operations_log import operations

logger = logging.getLogger(__name__)

_MAX_TEXT = 200
_MAX_TARGET = 80
_REDACTED = "<redacted>"
_REDACTED_OBJECT_NAMES = {"ai_key_edit"}
# Dedupe rapid repeat clicks on the same (window, target): a burst of clicks
# within this window collapses to a single record. First click always records.
_CLICK_DEBOUNCE_MS = 300

# Opt-in escape hatch: record committed text verbatim. Off by default because
# the log lands in the user data dir unencrypted and is included in bug
# reports. Set to "1" for a single debugging session.
_RECORD_TEXT = os.environ.get("TURNA_GUI_LOG_INPUT_TEXT", "").strip() == "1"


def _fingerprint(text: str) -> str:
    """Short, stable digest of an input value.

    Unsalted on purpose: the point is to correlate repeated commits within one
    local log, which a per-run salt would defeat.
    """
    return hashlib.sha256(text.encode("utf-8", "replace")).hexdigest()[:8]


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
    # never use it as the target label. The only realistic failure here is a
    # deleted C++ object, which PySide6 surfaces as RuntimeError; treat that
    # as "possibly secret" so an unreadable field fails closed.
    is_secret = False
    try:
        if isinstance(obj, QLineEdit) and (
            obj.echoMode() == QLineEdit.EchoMode.Password
            or obj.objectName() in _REDACTED_OBJECT_NAMES
        ):
            is_secret = True
    except RuntimeError:
        logger.debug("user_action_filter: secret probe on a dead object", exc_info=True)
        is_secret = True

    if isinstance(obj, (QLineEdit, QTextEdit)):
        # A text input's own text is the payload we refuse to record, so it
        # can never double as the label. Fall through to objectName / class.
        getters: tuple[str, ...] = ()
    elif is_secret:
        getters = ("windowTitle", "title")
    else:
        getters = ("text", "windowTitle", "title")
    for getter in getters:
        try:
            method = getattr(obj, getter, None)
            if callable(method):
                value = method()
                if value:
                    name = str(value)
                    break
        except Exception:
            logger.debug("user_action_filter: getter %s failed", getter, exc_info=True)
            continue
    if not name:
        try:
            name = obj.objectName() or ""
        except Exception:
            name = ""
    if not name:
        name = type(obj).__name__
    return name[:_MAX_TARGET]


def _is_secret(widget: QWidget) -> bool:
    """True for fields whose value must never be recorded, not even hashed.

    Narrows to ``RuntimeError`` on purpose: that is what PySide6 raises for a
    wrapped object whose C++ side is gone, and it is the only failure this
    probe can hit. Failing closed (treat as secret) keeps a dead widget from
    ever downgrading to "safe to log".
    """
    try:
        if isinstance(widget, QLineEdit):
            return (
                widget.echoMode() == QLineEdit.EchoMode.Password
                or widget.objectName() in _REDACTED_OBJECT_NAMES
            )
    except RuntimeError:
        logger.debug("user_action_filter: secret probe on a dead object", exc_info=True)
        return True
    return False


def _committed_payload(widget: QWidget) -> dict[str, object] | None:
    """Describe a committed edit, or ``None`` when there is nothing to record.

    Returns a fingerprint (``chars`` + ``sha``) rather than the text, unless
    ``TURNA_GUI_LOG_INPUT_TEXT=1`` opts in. Secret fields collapse to
    ``{"text": "<redacted>"}``.
    """
    if _is_secret(widget):
        return {"text": _REDACTED}
    try:
        if isinstance(widget, QLineEdit):
            value = widget.text()
        elif isinstance(widget, QTextEdit):
            value = widget.toPlainText()
        else:
            return None
    except RuntimeError:
        # Dead C++ object: we cannot read it, so we certainly do not log it.
        logger.debug("user_action_filter: read text on a dead object", exc_info=True)
        return {"text": _REDACTED}
    if not value:
        return None
    payload: dict[str, object] = {"chars": len(value), "sha": _fingerprint(value)}
    if _RECORD_TEXT:
        payload["text"] = value[:_MAX_TEXT]
    return payload


class UserActionFilter(QObject):
    """Single global event filter recording clicks and input commits."""

    def __init__(self, parent: QObject | None = None) -> None:
        super().__init__(parent)
        # Dedupe key: (window_name, target_name) -> elapsed ms of last record.
        self._last_click: tuple[str, str] = ("", "")
        self._last_click_ts: int = -_CLICK_DEBOUNCE_MS
        self._click_clock = QElapsedTimer()
        self._click_clock.start()

    def eventFilter(self, obj: QObject, event: QEvent) -> bool:
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
                payload = _committed_payload(obj)
                # Skip empty commits to keep the log focused on real input.
                if payload:
                    operations.record_action(
                        "input.commit",
                        _target_name(obj),
                        payload=payload,
                        context={"window": _window_name(obj), "widget": type(obj).__name__},
                    )
            elif etype == QEvent.Type.KeyPress and isinstance(obj, QLineEdit):
                key = event.key()
                if key in (QEvent.Key.Return, QEvent.Key.Enter):
                    payload = _committed_payload(obj)
                    if payload:
                        operations.record_action(
                            "input.commit",
                            _target_name(obj),
                            payload=payload,
                            context={"window": _window_name(obj), "widget": type(obj).__name__},
                        )
        except Exception:
            # Telemetry must never crash the application.
            logger.debug("infrastructure/user_action_filter.py:eventFilter best-effort step failed", exc_info=True)
        return False
