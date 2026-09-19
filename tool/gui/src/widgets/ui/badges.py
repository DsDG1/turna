"""Badge / Pill — count badges and type labels (UI kit)."""
from __future__ import annotations

from PySide6.QtCore import Qt
from PySide6.QtWidgets import QLabel


class Badge(QLabel):
    """Small pill-shaped count badge (activity-bar style corner chip).

    ``variant``: ``accent`` (counts) | ``danger`` (errors) | ``muted``.
    Shows up to ``max_count`` then ``99+``. ``set_count(0)`` hides the badge.
    """

    def __init__(
        self,
        count: int = 0,
        *,
        variant: str = "accent",
        max_count: int = 99,
        parent=None,
    ) -> None:
        super().__init__(parent)
        self.setObjectName("Badge")
        self.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self._max_count = max(1, int(max_count))
        self._count = 0
        self.set_variant(variant)
        self.set_count(count)

    def set_variant(self, variant: str) -> None:
        if variant not in ("accent", "danger", "muted"):
            variant = "accent"
        self.setProperty("variant", variant)

    def set_count(self, count: int) -> None:
        self._count = max(0, int(count))
        if self._count <= 0:
            self.setVisible(False)
            return
        text = str(self._count) if self._count <= self._max_count else f"{self._max_count}+"
        self.setText(text)
        self.setVisible(True)

    def count(self) -> int:
        return self._count


class Pill(QLabel):
    """Rounded type tag (``r_pill``).

    Two modes:
    * ``variant`` — semantic QSS variant (accent/success/warning/danger/muted).
    * ``color`` — explicit hex (e.g. a ``TEMPLATE_COLORS`` value) rendered as
      colored border + text on transparent bg. This is the sanctioned escape
      hatch for data-driven colors; semantic variants are preferred.
    """

    def __init__(
        self,
        text: str = "",
        *,
        variant: str = "muted",
        color: str | None = None,
        parent=None,
    ) -> None:
        super().__init__(text, parent)
        self.setObjectName("Pill")
        self.setAlignment(Qt.AlignmentFlag.AlignCenter)
        if color:
            self.set_color(color)
        else:
            self.set_variant(variant)

    def set_variant(self, variant: str) -> None:
        if variant not in ("accent", "success", "warning", "danger", "muted"):
            variant = "muted"
        self.setProperty("variant", variant)
        self.setStyleSheet("")

    def set_color(self, color: str) -> None:
        """Data-driven color (template badge / resource type)."""
        self.setProperty("variant", "custom")
        self.setStyleSheet(
            f"#Pill {{ color: {color}; border: 1px solid {color}; }}"
        )
