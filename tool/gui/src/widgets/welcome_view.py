"""Welcome view (GUI 焕新 W2).

Shown on the central stack when no course repository is loaded — replaces
the old "screen of disabled buttons". Brand block, 新建/打开 actions, and
a clickable recent-repository list fed by ``Settings.recent_repos``.

The widget is deliberately dumb: callers pass data + callbacks, no host
imports, so it is trivially testable headlessly.
"""
from __future__ import annotations

from collections.abc import Callable
from typing import Any

from PySide6.QtCore import Qt
from PySide6.QtWidgets import (
    QFrame,
    QHBoxLayout,
    QLabel,
    QPushButton,
    QVBoxLayout,
    QWidget,
)

from src.icons import icon, pixmap
from src.widgets.ui.buttons import TurnaButton


def _relative_time(iso: str) -> str:
    """Human '3 天前'-style label for an ISO timestamp; '' on failure."""
    from datetime import UTC, datetime

    try:
        then = datetime.fromisoformat(str(iso).replace("Z", "+00:00"))
        if then.tzinfo is None:
            then = then.replace(tzinfo=UTC)
        delta = datetime.now(UTC) - then
        days = delta.days
        if days >= 30:
            months = days // 30
            return f"{months} 个月前"
        if days >= 7:
            return f"{days // 7} 周前"
        if days >= 1:
            return f"{days} 天前"
        hours = int(delta.total_seconds() // 3600)
        if hours >= 1:
            return f"{hours} 小时前"
        return "刚刚"
    except Exception:
        return ""


class _RecentRepoRow(QPushButton):
    """One recent-repo row: folder icon + name + path + relative time."""

    def __init__(self, repo: dict[str, Any], on_open: Callable[[str], None]) -> None:
        super().__init__()
        self.setObjectName("WelcomeRecentItem")
        self.setCursor(Qt.CursorShape.PointingHandCursor)
        path = str(repo.get("path", "") or "")
        name = path.replace("\\", "/").rstrip("/").rsplit("/", 1)[-1] or path
        when = _relative_time(str(repo.get("opened_at", "") or ""))
        text = f"{name}\n{path}"
        if when:
            text += f"   ·   {when}"
        self.setText(text)
        self.setIcon(icon("folder", size=18, role="muted"))
        self.setToolTip(f"打开 {path}")
        self._path = path
        self._on_open = on_open
        self.clicked.connect(self._clicked)

    def _clicked(self) -> None:
        if self._path:
            self._on_open(self._path)


class WelcomeView(QWidget):
    """No-repo landing page for the central stack."""

    def __init__(
        self,
        *,
        on_new: Callable[[], None],
        on_open: Callable[[], None],
        on_open_recent: Callable[[str], None],
        parent: QWidget | None = None,
    ) -> None:
        super().__init__(parent)
        self.setObjectName("WelcomeView")
        self._on_open_recent = on_open_recent

        root = QVBoxLayout(self)
        root.setContentsMargins(32, 48, 32, 32)
        root.setSpacing(10)
        root.addStretch(2)

        brand = QLabel()
        brand.setPixmap(pixmap("graduation-cap", size=56, role="accent"))
        brand.setAlignment(Qt.AlignmentFlag.AlignCenter)
        root.addWidget(brand)

        title = QLabel("Turna")
        title.setObjectName("WelcomeBrand")
        title.setAlignment(Qt.AlignmentFlag.AlignCenter)
        root.addWidget(title)

        subtitle = QLabel("语言课程编辑器 — 打开或新建一个课程目录开始")
        subtitle.setObjectName("WelcomeSubtitle")
        subtitle.setAlignment(Qt.AlignmentFlag.AlignCenter)
        subtitle.setWordWrap(True)
        root.addWidget(subtitle)

        btn_row = QHBoxLayout()
        btn_row.setSpacing(10)
        btn_row.addStretch(1)
        self.new_btn = TurnaButton(
            "新建课程目录…", variant="primary", icon_name="plus", parent=self
        )
        self.new_btn.clicked.connect(on_new)
        btn_row.addWidget(self.new_btn)
        self.open_btn = TurnaButton(
            "打开课程目录…", variant="secondary", icon_name="folder-open", parent=self
        )
        self.open_btn.clicked.connect(on_open)
        btn_row.addWidget(self.open_btn)
        btn_row.addStretch(1)
        root.addLayout(btn_row)
        root.addSpacing(18)

        self._recent_header = QLabel("最近仓库")
        self._recent_header.setObjectName("WelcomeRecentHeader")
        self._recent_header.setAlignment(Qt.AlignmentFlag.AlignCenter)
        root.addWidget(self._recent_header)

        self._recent_host = QFrame(self)
        self._recent_host.setObjectName("WelcomeRecentList")
        self._recent_layout = QVBoxLayout(self._recent_host)
        self._recent_layout.setContentsMargins(0, 0, 0, 0)
        self._recent_layout.setSpacing(6)
        # Cap list width so rows read as cards, not full-bleed strips.
        self._recent_host.setMaximumWidth(560)
        row_wrap = QHBoxLayout()
        row_wrap.addStretch(1)
        row_wrap.addWidget(self._recent_host)
        row_wrap.addStretch(1)
        root.addLayout(row_wrap)

        self._empty_hint = QLabel("（暂无最近仓库）")
        self._empty_hint.setObjectName("WelcomeSubtitle")
        self._empty_hint.setAlignment(Qt.AlignmentFlag.AlignCenter)
        root.addWidget(self._empty_hint)

        root.addStretch(3)
        self.refresh_repos([])

    def refresh_repos(self, repos: list[dict[str, Any]]) -> None:
        """Rebuild the recent-repos list (called on show / repo change)."""
        while self._recent_layout.count():
            child = self._recent_layout.takeAt(0)
            w = child.widget()
            if w is not None:
                w.setParent(None)
                w.deleteLater()
        shown = [r for r in (repos or []) if isinstance(r, dict) and r.get("path")]
        for repo in shown[:6]:
            self._recent_layout.addWidget(
                _RecentRepoRow(repo, self._on_open_recent)
            )
        has = len(shown) > 0
        self._recent_header.setVisible(has)
        self._empty_hint.setVisible(not has)
