"""ActivityBar — fixed 48px icon rail on the window's left edge (UI kit).

Sections (top → bottom): app-menu button, view items (exclusive check),
separator, toggle items (e.g. Copilot), stretch, utility items
(teacher mode / settings). Each item is an :class:`ActivityBarItem` with an
optional corner :class:`Badge`.

Colors come from the global QSS via ``objectName``/properties; the active
item shows a 2px accent indicator on its left edge.
"""
from __future__ import annotations

import functools

from PySide6.QtCore import QSize, Qt, Signal
from PySide6.QtWidgets import (
    QButtonGroup,
    QFrame,
    QHBoxLayout,
    QMenu,
    QToolButton,
    QVBoxLayout,
    QWidget,
)

from src.icons import icon
from src.widgets.ui.badges import Badge


class ActivityBarItem(QToolButton):
    """One 48x48 rail button: Lucide icon + optional count badge.

    ``key`` is a stable identifier (``"edit"`` / ``"workshop"`` / …) used by
    :class:`ActivityBar` for badge routing and exclusive checking.
    """

    def __init__(
        self,
        key: str,
        icon_name: str,
        tooltip: str,
        *,
        checkable: bool = True,
        parent=None,
    ) -> None:
        super().__init__(parent)
        self._key = key
        self._icon_name = icon_name
        self.setObjectName("ActivityBarItem")
        self.setCheckable(checkable)
        self.setToolTip(tooltip)
        self.setFixedSize(40, 40)
        self.setIconSize(self._icon_qsize())
        self.setCursor(Qt.CursorShape.PointingHandCursor)
        self._refresh_icon()
        # Re-polish when the checked state flips so the icon color follows.
        self.toggled.connect(self._refresh_icon)

        self._badge = Badge(0, variant="accent", parent=self)
        self._badge.move(self.width() - 16, 2)

    def key(self) -> str:
        return self._key

    def _icon_qsize(self):
        from PySide6.QtCore import QSize

        return QSize(20, 20)

    def _refresh_icon(self) -> None:
        role = "accent" if self.isChecked() else "muted"
        self.setIcon(icon(self._icon_name, size=20, role=role))

    def refresh_icon(self) -> None:
        self._refresh_icon()

    def set_badge(self, count: int, *, danger: bool = False) -> None:
        """Show/update the corner count badge (0 hides it)."""
        self._badge.set_variant("danger" if danger else "accent")
        self._badge.set_count(count)

    def badge_count(self) -> int:
        return self._badge.count()

    def resizeEvent(self, event) -> None:
        super().resizeEvent(event)
        self._badge.move(self.width() - self._badge.width() - 2, 2)


class ActivityBar(QWidget):
    """The rail itself. Owns an exclusive :class:`QButtonGroup` for view items."""

    #: Emitted with the item ``key`` when a view item is checked on.
    view_activated = Signal(str)
    #: Emitted with the item ``key`` when any item is clicked.
    item_clicked = Signal(str)

    WIDTH = 48

    def __init__(self, parent=None) -> None:
        super().__init__(parent)
        self.setObjectName("ActivityBar")
        self.setFixedWidth(self.WIDTH)

        self._layout = QVBoxLayout(self)
        self._layout.setContentsMargins(0, 8, 0, 8)
        self._layout.setSpacing(4)
        self._layout.setAlignment(Qt.AlignmentFlag.AlignHCenter)

        self._view_group = QButtonGroup(self)
        self._view_group.setExclusive(True)
        self._items: dict[str, ActivityBarItem] = {}
        self._view_keys: list[str] = []

    # --- building -------------------------------------------------------

    def add_menu_button(self, tooltip: str = "菜单") -> QToolButton:
        """Top hamburger button hosting the application menu."""
        btn = QToolButton(self)
        btn.setObjectName("ActivityBarItem")
        btn.setToolTip(tooltip)
        btn.setFixedSize(40, 40)
        btn.setIconSize(QSize(20, 20))
        btn.setIcon(icon("menu", size=20, role="default"))
        btn.setPopupMode(QToolButton.ToolButtonPopupMode.InstantPopup)
        btn.setCursor(Qt.CursorShape.PointingHandCursor)
        btn.setMenu(QMenu(btn))
        self._layout.addWidget(btn, 0, Qt.AlignmentFlag.AlignHCenter)
        self.menu_button = btn
        return btn

    def add_separator(self) -> None:
        sep = QFrame(self)
        sep.setObjectName("ActivityBarSeparator")
        sep.setFrameShape(QFrame.Shape.HLine)
        sep.setFixedSize(28, 1)
        self._layout.addWidget(sep, 0, Qt.AlignmentFlag.AlignHCenter)

    def add_stretch(self) -> None:
        self._layout.addStretch(1)

    def add_item(
        self,
        key: str,
        icon_name: str,
        tooltip: str,
        *,
        checkable: bool = True,
        view: bool = False,
    ) -> ActivityBarItem:
        """Append an item. ``view=True`` puts it in the exclusive view group."""
        item = ActivityBarItem(key, icon_name, tooltip, checkable=checkable, parent=self)
        item.clicked.connect(functools.partial(self._on_item_clicked, key))
        if view:
            self._view_group.addButton(item)
            self._view_keys.append(key)

            def _emit_view(checked: bool, k: str = key) -> None:
                if checked:
                    self.view_activated.emit(k)

            item.toggled.connect(_emit_view)
        self._items[key] = item
        self._layout.addWidget(item, 0, Qt.AlignmentFlag.AlignHCenter)
        return item

    # --- state -----------------------------------------------------------

    def item(self, key: str) -> ActivityBarItem | None:
        return self._items.get(key)

    def set_current(self, key: str) -> None:
        """Check a view item (and uncheck the others)."""
        item = self._items.get(key)
        if item is not None and item.isCheckable():
            item.setChecked(True)

    def current_view_key(self) -> str | None:
        for key in self._view_keys:
            item = self._items.get(key)
            if item is not None and item.isChecked():
                return key
        return None

    def set_badge(self, key: str, count: int, *, danger: bool = False) -> None:
        item = self._items.get(key)
        if item is not None:
            item.set_badge(count, danger=danger)

    def set_item_checked(self, key: str, checked: bool) -> None:
        item = self._items.get(key)
        if item is not None and item.isCheckable():
            item.setChecked(checked)

    def refresh_icons(self) -> None:
        """Re-render item icons (call after a palette switch if needed)."""
        for item in self._items.values():
            item.refresh_icon()

    def _on_item_clicked(self, key: str, _c: bool = False) -> None:
        self.item_clicked.emit(key)
