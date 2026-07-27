"""Non-modal AI preview strip (E1.5 / S-09).

Lives in the main window (above the status bar). Enter / 「应用」 applies the
pending action; Esc / 「丢弃」 cancels. Never auto-writes the course tree.
"""
from __future__ import annotations

from typing import Any, Callable

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

        # Shortcuts only active while visible (enabled in offer/clear).
        self._enter_sc = QShortcut(QKeySequence(Qt.Key.Key_Return), self)
        self._enter_sc2 = QShortcut(QKeySequence(Qt.Key.Key_Enter), self)
        self._esc_sc = QShortcut(QKeySequence(Qt.Key.Key_Escape), self)
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
            from src.application.ui_guard import resolve_auto_apply_state

            should_auto, opaque, token = resolve_auto_apply_state(self)
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
                    apply_fn()
                    self.applied.emit(payload)
                    self._note_auto_result(
                        ok=True, action_id=action_id, opaque=opaque
                    )
                except Exception as exc:
                    self._note_auto_result(
                        ok=False,
                        action_id=action_id,
                        opaque=opaque,
                        error=exc,
                    )
                return
        except Exception:
            pass
        self._title.setText(title or "预览")
        self._summary.setText(summary or "")
        self._apply_btn.setEnabled(True)
        self._discard_btn.setText("丢弃 Esc")
        self._set_details(details)
        self.setVisible(True)
        self._set_shortcuts_enabled(True)
        self._apply_btn.setFocus(Qt.FocusReason.OtherFocusReason)

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
            pass
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
            pass
        if ok or opaque:
            return
        try:
            msg = f"自动应用失败：{action_id or 'action'}"
            if error is not None:
                msg = f"{msg}（{error}）"[:240]
            sb = getattr(host, "statusBar", None) if host else None
            if callable(sb):
                bar = sb()
                if bar is not None and hasattr(bar, "showMessage"):
                    bar.showMessage(msg, 6000)
        except Exception:
            pass

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
        fn = self._discard_fn
        self.clear()
        if fn is not None:
            try:
                fn()
            except Exception:
                pass
        self.discarded.emit()
