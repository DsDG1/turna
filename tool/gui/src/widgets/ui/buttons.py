"""TurnaButton — styled push button with semantic variants (UI kit)."""
from __future__ import annotations

from PySide6.QtCore import Qt
from PySide6.QtWidgets import QPushButton

from src.icons import icon

#: variant -> icon role (keeps glyph readable on filled backgrounds).
_VARIANT_ICON_ROLE = {
    "primary": "on_accent",
    "danger": "on_accent",
    "secondary": "default",
    "ghost": "default",
}

_ICON_SIZE = {"sm": 14, "md": 16}


class TurnaButton(QPushButton):
    """Push button with ``variant`` (primary/secondary/ghost/danger) and
    ``size`` (sm/md), optionally carrying a Lucide icon.

    All colors come from the global QSS via ``objectName`` + the ``variant``
    / ``btnSize`` dynamic properties — no inline styles.
    """

    def __init__(
        self,
        text: str = "",
        *,
        variant: str = "secondary",
        size: str = "md",
        icon_name: str | None = None,
        parent=None,
    ) -> None:
        super().__init__(text, parent)
        self.setObjectName("TurnaButton")
        self.setCursor(Qt.CursorShape.PointingHandCursor)
        self._icon_name: str | None = None
        self.set_variant(variant)
        self.set_size(size)
        if icon_name is not None:
            self.set_icon_name(icon_name)

    def set_variant(self, variant: str) -> None:
        if variant not in _VARIANT_ICON_ROLE:
            variant = "secondary"
        self.setProperty("variant", variant)
        self._reicon()

    def variant(self) -> str:
        return str(self.property("variant") or "secondary")

    def set_size(self, size: str) -> None:
        self.setProperty("btnSize", "sm" if size == "sm" else "md")
        self._reicon()

    def set_icon_name(self, name: str | None) -> None:
        self._icon_name = name
        self._reicon()

    def _reicon(self) -> None:
        """Re-render the icon at the current variant/size (theme-aware)."""
        if not self._icon_name:
            return
        role = _VARIANT_ICON_ROLE.get(self.variant(), "default")
        size = _ICON_SIZE.get(str(self.property("btnSize") or "md"), 16)
        self.setIcon(icon(self._icon_name, size=size, role=role))

    def refresh_icon(self) -> None:
        """Re-render after a palette switch (icon cache keys on color)."""
        self._reicon()
