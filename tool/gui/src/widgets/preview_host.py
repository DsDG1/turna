"""Non-modal AI preview strip (E1.5 / S-09).

Lives in the main window (above the status bar). Enter / 「应用」 applies the
pending action; Esc / 「丢弃」 cancels. Never auto-writes the course tree.
"""
from __future__ import annotations

import logging
logger = logging.getLogger(__name__)


from typing import Any
from collections.abc import Callable

from PySide6.QtCore import Qt, Signal
from PySide6.QtGui import QKeySequence, QShortcut
from PySide6.QtWidgets import (
    QHBoxLayout,
    QLabel,
    QPushButton,
    QSizePolicy,
    QVBoxLayout,
    QWidget,
)

from src.theme import current_palette


class PreviewHost(QWidget):
    """Thin bar: title + summary + Apply / Discard.

    ``offer(apply_fn=...)`` stores the pending action; callers never need a
    modal dialog for the common chip path.
    """

    applied = Signal(object)
    discarded = Signal()

    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.setObjectName("PreviewHost")
        self.setVisible(False)
        self.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Fixed)

        pal = current_palette()
        self.setStyleSheet(
            f"""
            #PreviewHost {{
                background: {pal.get('surface_raised', pal.get('bg_secondary', '#1a2a28'))};
                border-top: 1px solid {pal.get('border', '#2a3f3c')};
            }}
            """
        )

        layout = QVBoxLayout(self)
        layout.setContentsMargins(12, 6, 12, 6)
        layout.setSpacing(4)

        row = QHBoxLayout()
        row.setSpacing(10)

        self._title = QLabel("预览")
        self._title.setStyleSheet("font-weight: 600;")
        row.addWidget(self._title)

        self._summary = QLabel("")
        self._summary.setWordWrap(True)
        self._summary.setStyleSheet(
            f"color: {pal.get('text_secondary', '#888')}; font-size: 12px;"
        )
        self._summary.setSizePolicy(
            QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Preferred
        )
        row.addWidget(self._summary, stretch=1)

        # A2: optional per-field diff toggle (hidden unless details offered).
        self._details_btn = QPushButton("详情 ▾")
        self._details_btn.setFlat(True)
        self._details_btn.setToolTip("展开/收起逐字段差异")
        self._details_btn.setVisible(False)
        self._details_btn.clicked.connect(self._toggle_details)
        row.addWidget(self._details_btn)

        self._apply_btn = QPushButton("应用 ↵")
        self._apply_btn.setToolTip("应用预览变更（Enter）")
        self._apply_btn.clicked.connect(self._on_apply)
        row.addWidget(self._apply_btn)

        self._discard_btn = QPushButton("丢弃 Esc")
        self._discard_btn.setToolTip("丢弃预览（Esc）")
        self._discard_btn.setFlat(True)
        self._discard_btn.clicked.connect(self._on_discard)
        row.addWidget(self._discard_btn)

        layout.addLayout(row)

        # A2: hidden per-field diff area (one "field: old → new" per line).
        self._details = QLabel("")
        self._details.setWordWrap(True)
        self._details.setStyleSheet(
            f"color: {pal.get('text_secondary', '#888')}; font-size: 12px; "
            "font-family: monospace; padding-left: 4px;"
        )
        self._details.setVisible(False)
        layout.addWidget(self._details)

        self._payload: Any = None
        self._apply_fn: Callable[[], None] | None = None
        self._discard_fn: Callable[[], None] | None = None
        self._busy = False

        # Shortcuts only active while visible (enabled in offer/clear) AND
        # strip-scoped (T13): WindowShortcut would fire Enter/Esc anywhere in
        # the window — including while the user types in a chat/edit field —
        # silently applying or discarding the pending AI action.
        sc_ctx = Qt.ShortcutContext.WidgetWithChildrenShortcut
        self._enter_sc = QShortcut(QKeySequence(Qt.Key.Key_Return), self)
        self._enter_sc2 = QShortcut(QKeySequence(Qt.Key.Key_Enter), self)
        self._esc_sc = QShortcut(QKeySequence(Qt.Key.Key_Escape), self)
        for sc in (self._enter_sc, self._enter_sc2, self._esc_sc):
            sc.shortcutContext = sc_ctx
        self._enter_sc.activated.connect(self._on_apply)
        self._enter_sc2.activated.connect(self._on_apply)
        self._esc_sc.activated.connect(self._on_discard)
        self._set_shortcuts_enabled(False)

    def is_busy(self) -> bool:
        return self._busy

    def has_pending(self) -> bool:
        return self.isVisible() and self._apply_fn is not None and not self._busy

    def set_busy(self, message: str = "生成中…") -> None:
        """Show an in-progress state (no apply yet)."""
        self._busy = True
        self._apply_fn = None
        self._discard_fn = None
        self._payload = None
        self._title.setText("AI 工作中")
        self._summary.setText(message)
        self._apply_btn.setEnabled(False)
        self._discard_btn.setText("取消 Esc")
        self._reset_details()
        self.setVisible(True)
        self._set_shortcuts_enabled(True)

    def offer(
        self,
        *,
        title: str,
        summary: str,
        apply_fn: Callable[[], None],
        discard_fn: Callable[[], None] | None = None,
        payload: Any = None,
        details: list[str] | None = None,
    ) -> None:
        """Present a pending change for human confirmation.

        ``details`` (A2) is an optional list of per-field ``field: old → new``
        lines; when provided, a 「详情 ▾」 toggle reveals them below the strip.
        Small lists (≤4) auto-expand. Callers that pass only ``summary`` see no
        visual change (backward compatible).
        """
        self._busy = False
        self._apply_fn = apply_fn
        self._discard_fn = discard_fn
        self._payload = payload
        # R2 immersive auto: apply immediately when ContextVar **or** host token
        # is still valid (async workers finish after dispatch scope ends).
        try:
            from src.application.ui_guard import (
                auto_confirm_scope,
                resolve_auto_apply_for_offer,
            )

            should_auto, opaque, token = resolve_auto_apply_for_offer(self)
            if should_auto and apply_fn is not None:
                self._apply_fn = None
                self._discard_fn = None
                self.setVisible(False)
                self._set_shortcuts_enabled(False)
                action_id = ""
                try:
                    action_id = str(getattr(token, "action_id", "") or "")
                except Exception:
                    action_id = ""
                try:
                    # Keep inner confirms of the apply chain auto as well (the
                    # sync-frame ContextVar is gone by the time we land here).
                    if token is not None:
                        with auto_confirm_scope(opaque=opaque, token=token):
                            apply_fn()
                    else:
                        apply_fn()
                    self.applied.emit(payload)
                    self._note_auto_result(
                        ok=True, action_id=action_id, opaque=opaque
                    )
                except Exception as exc:
                    logger.debug(
                        "src/widgets/preview_host.py:199 best-effort step failed",
                        exc_info=True,
                    )
                    self._note_auto_result(
                        ok=False,
                        action_id=action_id,
                        opaque=opaque,
                        error=exc,
                    )
                finally:
                    # The offer consumed the token: never let it outlive its
                    # offer and auto-answer later manual confirms (#6).
                    self._unbind_host_token()
                return
        except Exception:
            logger.debug("widgets/preview_host.py:187 best-effort step failed", exc_info=True)
        self._title.setText(title or "预览")
        self._summary.setText(summary or "")
        self._apply_btn.setEnabled(True)
        self._discard_btn.setText("丢弃 Esc")
        self._set_details(details)
        self.setVisible(True)
        self._set_shortcuts_enabled(True)
        # No setFocus here (T13): grabbing focus on every offer yanked the
        # cursor out of whatever the user was typing. Focus — and with it the
        # strip-scoped Enter/Esc — arrives when the user clicks the strip.

    def mousePressEvent(self, event) -> None:
        # Clicking anywhere on the strip moves focus onto the apply button so
        # the strip-scoped shortcuts activate for the keyboard user.
        if self._apply_btn.isEnabled():
            self._apply_btn.setFocus(Qt.FocusReason.MouseFocusReason)
        super().mousePressEvent(event)

    def _note_auto_result(
        self,
        *,
        ok: bool,
        action_id: str = "",
        opaque: bool = True,
        error: BaseException | None = None,
    ) -> None:
        """Audit + metrics + optional status for auto apply outcome."""
        kind = "auto_applied" if ok else "auto_failed"
        host = None
        try:
            host = self.window() if hasattr(self, "window") else None
        except Exception:
            host = None
        try:
            from src.backend.experience.auto_apply import (
                ensure_audit_ring,
                record_audit,
            )

            ring = ensure_audit_ring(host)
            record_audit(
                ring,
                action_id or "unknown",
                count=1,
                kind=kind,
            )
        except Exception:
            logger.debug("widgets/preview_host.py:226 best-effort step failed", exc_info=True)
        try:
            metrics = getattr(host, "experience_metrics", None) if host else None
            if metrics is not None:
                if hasattr(metrics, "inc_auto"):
                    metrics.inc_auto("applied" if ok else "failed")
                elif hasattr(metrics, "inc_suggestion") and action_id:
                    metrics.inc_suggestion(
                        action_id, "applied" if ok else "rejected"
                    )
        except Exception:
            logger.debug("widgets/preview_host.py:237 best-effort step failed", exc_info=True)
        if ok or opaque:
            return
        try:
            if ok:
                msg = f"已自动：{action_id or 'AI 变更'}（Ctrl+Z 可撤）"
            else:
                msg = f"自动应用失败：{action_id or 'action'}"
                if error is not None:
                    msg = f"{msg}（{error}）"[:240]
            sb = getattr(host, "statusBar", None) if host else None
            if callable(sb):
                bar = sb()
                if bar is not None and hasattr(bar, "showMessage"):
                    bar.showMessage(msg, 6000)
        except Exception:
            logger.debug("widgets/preview_host.py:250 best-effort step failed", exc_info=True)

    def _unbind_host_token(self) -> None:
        """Drop the host-bound auto token (the offer owns and consumed it)."""
        try:
            from src.backend.experience.auto_apply import bind_auto_apply_token

            bind_auto_apply_token(self.window(), None)
        except Exception:
            logger.debug("widgets/preview_host.py:_unbind_host_token best-effort step failed", exc_info=True)

    def clear(self) -> None:
        self._busy = False
        self._apply_fn = None
        self._discard_fn = None
        self._payload = None
        self._summary.setText("")
        self._apply_btn.setEnabled(False)
        self._reset_details()
        self._set_shortcuts_enabled(False)
        self.setVisible(False)
        # #6: a token bound for this offer must not outlive it.
        self._unbind_host_token()

    # --- A2 details ------------------------------------------------------

    def _set_details(self, details: list[str] | None) -> None:
        lines = [str(d) for d in (details or []) if str(d).strip()]
        if not lines:
            self._reset_details()
            return
        self._details.setText("\n".join(lines))
        self._details_btn.setVisible(True)
        # Auto-expand small diffs so the common single-field case needs no click.
        expand = len(lines) <= 4
        self._details.setVisible(expand)
        self._details_btn.setText("详情 ▴" if expand else "详情 ▾")

    def _reset_details(self) -> None:
        self._details.setText("")
        self._details.setVisible(False)
        self._details_btn.setVisible(False)
        self._details_btn.setText("详情 ▾")

    def _toggle_details(self) -> None:
        show = not self._details.isVisible()
        self._details.setVisible(show)
        self._details_btn.setText("详情 ▴" if show else "详情 ▾")

    def _set_shortcuts_enabled(self, enabled: bool) -> None:
        self._enter_sc.setEnabled(enabled)
        self._enter_sc2.setEnabled(enabled)
        self._esc_sc.setEnabled(enabled)

    def _on_apply(self) -> None:
        if self._busy or self._apply_fn is None:
            return
        fn = self._apply_fn
        payload = self._payload
        self.clear()
        try:
            fn()
        finally:
            self.applied.emit(payload)

    def _on_discard(self) -> None:
        was_busy = self._busy
        fn = self._discard_fn
        self.clear()
        if was_busy:
            # C9: in the busy state Esc means "cancel the request", not just
            # "hide the strip" — the worker's late result would pop the
            # preview right back up otherwise.
            try:
                from src.application.main_window_shell import cancel_in_flight_ai_jobs

                cancel_in_flight_ai_jobs(self.window())
            except Exception:
                logger.debug(
                    "widgets/preview_host.py:busy-esc cancel best-effort failed",
                    exc_info=True,
                )
        if fn is not None:
            try:
                fn()
            except Exception:
                logger.debug("widgets/preview_host.py:311 best-effort step failed", exc_info=True)
        self.discarded.emit()
