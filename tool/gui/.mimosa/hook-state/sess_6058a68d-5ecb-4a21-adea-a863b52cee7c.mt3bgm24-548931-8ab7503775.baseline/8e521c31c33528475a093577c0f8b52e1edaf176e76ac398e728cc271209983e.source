"""AmbientBanner - non-modal proactive strip (E2.0 / S-05; A3 ① companion queue).

Renders up to N (<=3) proposals: the highest-priority one expanded (accept /
archive / mute) and the rest as collapsed single-line rows (archive each).
Pure view - queue mutation lives in the app handler via ``show_proposals``.
Never auto-writes JSON; never steals focus.
"""
from __future__ import annotations

from typing import Any

from PySide6.QtCore import Signal
from PySide6.QtWidgets import (
    QHBoxLayout,
    QLabel,
    QMenu,
    QPushButton,
    QSizePolicy,
    QVBoxLayout,
    QWidget,
)

from src.backend.experience.proactive import (
    MUTE_HOURS4,
    MUTE_PERMANENT,
    MUTE_TODAY,
    AmbientProposal,
)
from src.theme import current_palette

# A3 ①: companion queue cap (mirrors local_suggestions default limit).
QUEUE_LIMIT = 3


class AmbientBanner(QWidget):
    """Top-of-editor ambient proposal bar (companion queue)."""

    accepted = Signal(object)  # AmbientProposal or dict (expanded top item)
    archived = Signal(str)  # proposal id (expanded top or collapsed row)
    mute_changed = Signal(str)  # mute level string

    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.setObjectName("AmbientBanner")
        self.setVisible(False)
        self.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Fixed)

        pal = current_palette()
        self.setStyleSheet(
            f"""
            #AmbientBanner {{
                background: {pal.get('surface_raised', pal.get('bg_secondary', '#1a2a28'))};
                border-bottom: 1px solid {pal.get('border', '#2a3f3c')};
            }}
            """
        )

        outer = QVBoxLayout(self)
        outer.setContentsMargins(12, 6, 12, 6)
        outer.setSpacing(2)

        # --- expanded row (top proposal) ---
        self._row = QWidget(self)
        row_layout = QHBoxLayout(self._row)
        row_layout.setContentsMargins(0, 0, 0, 0)
        row_layout.setSpacing(8)

        self._badge = QLabel("建议")
        self._badge.setStyleSheet("font-weight: 600; font-size: 11px;")
        row_layout.addWidget(self._badge)

        self._title = QLabel("")
        self._title.setWordWrap(True)
        self._title.setSizePolicy(
            QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Preferred
        )
        row_layout.addWidget(self._title, stretch=1)

        self._accept_btn = QPushButton("去处理")
        self._accept_btn.clicked.connect(self._on_accept)
        row_layout.addWidget(self._accept_btn)

        self._later_btn = QPushButton("稍后")
        self._later_btn.setFlat(True)
        self._later_btn.setToolTip("本会话内不再显示这条提案")
        self._later_btn.clicked.connect(self._on_archive)
        row_layout.addWidget(self._later_btn)

        self._mute_btn = QPushButton("静音 ▾")
        self._mute_btn.setFlat(True)
        self._mute_btn.setToolTip("暂停主动提案（Dock 被动建议仍可用）")
        mute_menu = QMenu(self)
        mute_menu.addAction("静音 4 小时").triggered.connect(
            lambda: self._on_mute(MUTE_HOURS4)
        )
        mute_menu.addAction("静音今日").triggered.connect(
            lambda: self._on_mute(MUTE_TODAY)
        )
        mute_menu.addAction("永久静音").triggered.connect(
            lambda: self._on_mute(MUTE_PERMANENT)
        )
        self._mute_btn.setMenu(mute_menu)
        row_layout.addWidget(self._mute_btn)
        outer.addWidget(self._row)

        # --- collapsed rows (queue[1:]) ---
        self._collapsed_box = QWidget(self)
        self._collapsed_layout = QVBoxLayout(self._collapsed_box)
        self._collapsed_layout.setContentsMargins(0, 0, 0, 0)
        self._collapsed_layout.setSpacing(1)
        self._collapsed_box.setVisible(False)
        outer.addWidget(self._collapsed_box)

        self._queue: list[AmbientProposal] = []
        self._collapsed_rows: list[QWidget] = []

    def proposal(self) -> AmbientProposal | None:
        """The expanded (top) proposal, or None when empty."""
        return self._queue[0] if self._queue else None

    def proposals(self) -> list[AmbientProposal]:
        """Current queue snapshot (defensive copy)."""
        return list(self._queue)

    def show_proposal(self, proposal: AmbientProposal | dict[str, Any] | None) -> None:
        """Single-proposal convenience (A3 ① backward compat)."""
        self.show_proposals([proposal] if proposal else [])

    def show_proposals(
        self, proposals: list[AmbientProposal | dict[str, Any]] | None
    ) -> None:
        """Render up to ``QUEUE_LIMIT`` proposals (A3 ① companion queue).

        Empty / None -> clear. The first proposal is expanded; the rest are
        collapsed single-line rows with an archive (✕) button. Never steals
        focus.
        """
        norms: list[AmbientProposal] = []
        for p in proposals or []:
            if isinstance(p, dict):
                p = AmbientProposal.from_dict(p)
            if p is not None and getattr(p, "id", ""):
                norms.append(p)
        # Dedup by id (stable order) and cap.
        seen: set[str] = set()
        deduped: list[AmbientProposal] = []
        for p in norms:
            if p.id in seen:
                continue
            seen.add(p.id)
            deduped.append(p)
        self._queue = deduped[:QUEUE_LIMIT]
        self._render()

    def clear(self) -> None:
        self._queue = []
        self._teardown_collapsed()
        self._title.setText("")
        self._collapsed_box.setVisible(False)
        self.setVisible(False)

    # --- internals -------------------------------------------------------

    def _render(self) -> None:
        self._teardown_collapsed()
        if not self._queue:
            self.setVisible(False)
            return
        top = self._queue[0]
        body = top.body or top.title
        self._title.setText(f"<b>{top.title}</b>  {body}")
        self._title.setToolTip(body)
        for p in self._queue[1:]:
            row = self._make_collapsed_row(p)
            self._collapsed_layout.addWidget(row)
            self._collapsed_rows.append(row)
        self._collapsed_box.setVisible(len(self._queue) > 1)
        self.setVisible(True)

    def _make_collapsed_row(self, proposal: AmbientProposal) -> QWidget:
        row = QWidget(self._collapsed_box)
        lay = QHBoxLayout(row)
        lay.setContentsMargins(0, 0, 0, 0)
        lay.setSpacing(6)
        dot = QLabel("•")
        lbl = QLabel(proposal.title)
        lbl.setToolTip(proposal.body or proposal.title)
        xbtn = QPushButton("✕")
        xbtn.setFlat(True)
        xbtn.setFixedSize(20, 20)
        xbtn.setToolTip("归档此条")
        pid = proposal.id
        xbtn.clicked.connect(lambda _checked=False, pid=pid: self._archive_pid(pid))
        lay.addWidget(dot)
        lay.addWidget(lbl, stretch=1)
        lay.addWidget(xbtn)
        return row

    def _teardown_collapsed(self) -> None:
        for w in self._collapsed_rows:
            w.setParent(None)
            w.deleteLater()
        self._collapsed_rows = []

    def _on_accept(self) -> None:
        if not self._queue:
            return
        self.accepted.emit(self._queue[0])

    def _on_archive(self) -> None:
        """稍后 button on the expanded top proposal."""
        if not self._queue:
            return
        self.archived.emit(self._queue[0].id)

    def _archive_pid(self, proposal_id: str) -> None:
        """Collapsed-row ✕ (or any pid) - archive a specific proposal."""
        if proposal_id:
            self.archived.emit(str(proposal_id))

    def _on_mute(self, level: str) -> None:
        self.mute_changed.emit(level)
