"""Headless / offscreen UI guard (S-10 / v4.46 hang fixes).

Single source of truth for "may we show a modal dialog?" — offscreen
``QMessageBox.exec()`` / ``question`` blocks forever in CI.

P3/R2 immersive: ``auto_confirm_scope`` + :class:`AutoApplyToken` make
``safe_question`` return True and let PreviewHost auto-apply without a
visible strip. Tokens survive the sync dispatch frame for async workers;
demote bumps generation so stale tokens stop auto-applying.

Never raises. Safe to call without a QApplication.
"""
from __future__ import annotations

from contextlib import contextmanager
from contextvars import ContextVar
from typing import Any, Iterator

from src.backend.experience.auto_apply import AutoApplyToken
import logging
logger = logging.getLogger(__name__)

# Immersive full-auto: skip human Yes/No and preview strip (still Undo in handlers).
_auto_confirm: ContextVar[bool] = ContextVar("ui_guard_auto_confirm", default=False)
_suppress_ui: ContextVar[bool] = ContextVar("ui_guard_suppress_ui", default=False)
_auto_token: ContextVar[AutoApplyToken | None] = ContextVar(
    "ui_guard_auto_token", default=None
)


def is_auto_confirm() -> bool:
    """True when current ContextVar forces Yes **or** a live token is in scope."""
    try:
        if bool(_auto_confirm.get()):
            token = _auto_token.get()
            if token is None:
                return True
            return bool(token.still_valid())
        token = _auto_token.get()
        if token is not None and token.still_valid():
            return True
    except Exception:
        logger.debug("application/ui_guard.py:is_auto_confirm best-effort step failed", exc_info=True)
    return False


def is_suppress_ui() -> bool:
    """Opaque mode: avoid information/warning noise when possible."""
    try:
        if bool(_suppress_ui.get()):
            return True
        token = _auto_token.get()
        if token is not None and token.still_valid() and bool(token.opaque):
            return True
    except Exception:
        logger.debug("application/ui_guard.py:is_suppress_ui best-effort step failed", exc_info=True)
    return False


def current_auto_token() -> AutoApplyToken | None:
    """ContextVar token if still valid."""
    try:
        token = _auto_token.get()
        if token is not None and token.still_valid():
            return token
    except Exception:
        logger.debug("application/ui_guard.py:current_auto_token best-effort step failed", exc_info=True)
    return None


def resolve_auto_apply_state(widget: Any = None) -> tuple[bool, bool, AutoApplyToken | None]:
    """Resolve (should_auto, opaque, token) from ContextVar and/or host.

    Walks ``widget`` parents for ``_auto_apply_token`` so async
    ``PreviewHost.offer`` still works after the dispatch frame ends.
    Never raises.
    """
    try:
        token = current_auto_token()
        if token is not None:
            return True, bool(token.opaque), token
    except Exception:
        logger.debug("application/ui_guard.py:resolve_auto_apply_state best-effort step failed", exc_info=True)

    host_token = _find_host_token(widget)
    if host_token is not None:
        return True, bool(getattr(host_token, "opaque", True)), host_token

    try:
        if bool(_auto_confirm.get()):
            return True, bool(_suppress_ui.get()), None
    except Exception:
        logger.debug("application/ui_guard.py:resolve_auto_apply_state best-effort step failed", exc_info=True)
    return False, False, None


def _find_host_token(widget: Any) -> AutoApplyToken | None:
    """Walk Qt parent chain and window() for a valid auto token."""
    from src.backend.experience.auto_apply import host_auto_apply_token

    seen: set[int] = set()

    def _check(obj: Any) -> AutoApplyToken | None:
        if obj is None:
            return None
        try:
            ident = id(obj)
            if ident in seen:
                return None
            seen.add(ident)
        except Exception:
            return None
        return host_auto_apply_token(obj)

    cur = widget
    depth = 0
    while cur is not None and depth < 32:
        tok = _check(cur)
        if tok is not None:
            return tok
        nxt = None
        try:
            if hasattr(cur, "parentWidget") and callable(cur.parentWidget):
                nxt = cur.parentWidget()
            elif hasattr(cur, "parent") and callable(cur.parent):
                nxt = cur.parent()
        except Exception:
            nxt = None
        if nxt is None:
            break
        cur = nxt
        depth += 1
    # Final: top-level window (MainWindow usually holds the token).
    try:
        if widget is not None and hasattr(widget, "window") and callable(widget.window):
            tok = _check(widget.window())
            if tok is not None:
                return tok
    except Exception:
        logger.debug("application/ui_guard.py:_find_host_token best-effort step failed", exc_info=True)
    return None


@contextmanager
def auto_confirm_scope(
    *,
    opaque: bool = False,
    token: AutoApplyToken | None = None,
) -> Iterator[None]:
    """Force confirmations to Yes for the duration of immersive auto-apply.

    When *token* is provided, validity is re-checked on each
    ``is_auto_confirm`` / ``safe_question`` call (demote invalidates).
    """
    use_token = token
    if use_token is not None and not use_token.still_valid():
        # Stale token: do not force auto.
        yield
        return
    opaque_flag = bool(opaque)
    if use_token is not None:
        opaque_flag = bool(use_token.opaque)

    t1 = _auto_confirm.set(True)
    t2 = _suppress_ui.set(opaque_flag)
    t3 = _auto_token.set(use_token)
    try:
        yield
    finally:
        try:
            _auto_confirm.reset(t1)
        except Exception:
            logger.debug("application/ui_guard.py:auto_confirm_scope best-effort step failed", exc_info=True)
        try:
            _suppress_ui.reset(t2)
        except Exception:
            logger.debug("application/ui_guard.py:auto_confirm_scope best-effort step failed", exc_info=True)
        try:
            _auto_token.reset(t3)
        except Exception:
            logger.debug("application/ui_guard.py:auto_confirm_scope best-effort step failed", exc_info=True)


def is_headless_ui() -> bool:
    """True when no modal dialog may be shown (no QApplication or offscreen).

    Offscreen ``exec()``/QMessageBox blocks forever — codebase rule:
    "offscreen tests hang on modal". Never raises.
    """
    try:
        from PySide6.QtWidgets import QApplication

        app = QApplication.instance()
        return app is None or app.platformName() == "offscreen"
    except Exception:
        return True


def _status_fallback(parent: Any, text: str, ms: int = 6000) -> None:
    """Best-effort statusBar message when headless; never raises."""
    try:
        if parent is None:
            return
        sb = getattr(parent, "statusBar", None)
        if callable(sb):
            bar = sb()
            if bar is not None and hasattr(bar, "showMessage"):
                bar.showMessage(str(text or "")[:240], ms)
    except Exception:
        logger.debug("application/ui_guard.py:_status_fallback best-effort step failed", exc_info=True)


def safe_information(
    parent: Any,
    title: str,
    text: str,
    *,
    status_fallback: bool = True,
) -> None:
    """Show information dialog, or statusBar when headless. Never raises."""
    if is_suppress_ui():
        return
    if is_headless_ui():
        if status_fallback:
            _status_fallback(parent, f"{title}: {text}" if title else text)
        return
    try:
        from PySide6.QtWidgets import QMessageBox

        QMessageBox.information(parent, title, text)
    except Exception:
        if status_fallback:
            _status_fallback(parent, f"{title}: {text}" if title else text)


def safe_warning(
    parent: Any,
    title: str,
    text: str,
    *,
    status_fallback: bool = True,
) -> None:
    """Show warning dialog, or statusBar when headless. Never raises."""
    if is_suppress_ui():
        return
    if is_headless_ui():
        if status_fallback:
            _status_fallback(parent, f"{title}: {text}" if title else text, ms=8000)
        return
    try:
        from PySide6.QtWidgets import QMessageBox

        QMessageBox.warning(parent, title, text)
    except Exception:
        if status_fallback:
            _status_fallback(parent, f"{title}: {text}" if title else text, ms=8000)


def safe_question(
    parent: Any,
    title: str,
    text: str,
    *,
    default_yes: bool = False,
) -> bool:
    """Yes/No question. Headless returns *default_yes* without modal.

    Immersive ``auto_confirm_scope`` / live token forces True (P3/R2 full auto).
    Returns True when the user (or headless default) chooses Yes.
    Never raises.
    """
    auto, _opaque, _token = resolve_auto_apply_state(parent)
    if auto:
        return True
    if is_headless_ui():
        return bool(default_yes)
    try:
        from PySide6.QtWidgets import QMessageBox

        reply = QMessageBox.question(
            parent,
            title,
            text,
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
            QMessageBox.StandardButton.Yes
            if default_yes
            else QMessageBox.StandardButton.No,
        )
        return reply == QMessageBox.StandardButton.Yes
    except Exception:
        return bool(default_yes)
