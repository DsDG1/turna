"""Container components: Card, TurnaDialog, ViewHeader, EmptyState."""
from __future__ import annotations

from PySide6.QtCore import Qt, Signal
from PySide6.QtWidgets import (
    QDialog,
    QFrame,
    QHBoxLayout,
    QLabel,
    QLayout,
    QVBoxLayout,
    QWidget,
)

from src.icons import pixmap as _pixmap
from src.theme_tokens import ELEVATION
from src.widgets.ui.buttons import TurnaButton


class Card(QFrame):
    """Elevated surface: ``bg_elevated`` + border + ``r_lg`` radius.

    ``shadow=True`` attaches an e1 drop shadow. Per the design rules, shadows
    are for cards/overlays only — never per-item rows.
    """

    def __init__(self, parent=None, *, shadow: bool = False) -> None:
        super().__init__(parent)
        self.setObjectName("TurnaCard")
        self.setFrameShape(QFrame.Shape.NoFrame)
        self._body = QVBoxLayout(self)
        self._body.setContentsMargins(12, 10, 12, 10)
        self._body.setSpacing(8)
        if shadow:
            self._apply_elevation("e1")

    def _apply_elevation(self, level: str) -> None:
        spec = ELEVATION.get(level)
        if not spec:
            return
        from src.theme import apply_shadow

        apply_shadow(
            self,
            blur_radius=int(spec.get("blur", 16)),
            dy=int(spec.get("dy", 2)),
            alpha=float(spec.get("alpha", 0.10)),
        )

    def body_layout(self) -> QVBoxLayout:
        return self._body

    def add_widget(self, widget: QWidget, stretch: int = 0) -> None:
        self._body.addWidget(widget, stretch)

    def add_layout(self, layout: QLayout, stretch: int = 0) -> None:
        self._body.addLayout(layout, stretch)


class ViewHeader(QWidget):
    """Uniform 44px header strip for each stacked view.

    Layout: ``[title (display)] [breadcrumb/context]  <stretch>  [actions…]``.
    Actions are appended right-to-left via :meth:`add_action`.
    """

    def __init__(self, title: str = "", parent=None) -> None:
        super().__init__(parent)
        self.setObjectName("ViewHeader")
        self.setFixedHeight(44)

        row = QHBoxLayout(self)
        row.setContentsMargins(12, 0, 12, 0)
        row.setSpacing(10)

        self._title = QLabel(title)
        self._title.setObjectName("ViewHeaderTitle")
        row.addWidget(self._title)

        self._context = QLabel("")
        self._context.setObjectName("ViewHeaderContext")
        self._context.setVisible(False)
        row.addWidget(self._context)

        row.addStretch(1)
        self._actions = QHBoxLayout()
        self._actions.setContentsMargins(0, 0, 0, 0)
        self._actions.setSpacing(6)
        row.addLayout(self._actions)

    def set_title(self, text: str) -> None:
        self._title.setText(text)

    def title(self) -> str:
        return self._title.text()

    def set_breadcrumb(self, crumbs: list[str] | str | None) -> None:
        """Show a breadcrumb trail (``A › B › C``) or arbitrary context text."""
        if crumbs is None:
            text = ""
        elif isinstance(crumbs, str):
            text = crumbs
        else:
            text = "  ›  ".join(c for c in crumbs if c)
        self._context.setText(text)
        self._context.setVisible(bool(text))

    def add_action(self, widget: QWidget) -> QWidget:
        """Append an action widget (button, menu, chip) at the right end."""
        self._actions.addWidget(widget)
        return widget

    def action_count(self) -> int:
        return self._actions.count()


class TurnaDialog(QDialog):
    """Base dialog: header (title + description + close), body, footer.

    Footer buttons are right-aligned; ``add_button`` returns a
    :class:`TurnaButton`. Use :meth:`set_body` / :meth:`body_layout` for
    content. Escape / the header ✕ button both reject().
    """

    rejected = Signal()

    def __init__(
        self,
        parent=None,
        *,
        title: str = "",
        description: str = "",
    ) -> None:
        super().__init__(parent)
        self.setObjectName("TurnaDialog")
        if title:
            self.setWindowTitle(title)

        root = QVBoxLayout(self)
        root.setContentsMargins(0, 0, 0, 0)
        root.setSpacing(0)

        # --- header ---------------------------------------------------
        header = QWidget(self)
        header.setObjectName("TurnaDialogHeader")
        hrow = QHBoxLayout(header)
        hrow.setContentsMargins(16, 14, 10, 10)
        hrow.setSpacing(8)
        title_col = QVBoxLayout()
        title_col.setSpacing(2)
        self._title = QLabel(title)
        self._title.setObjectName("TurnaDialogTitle")
        title_col.addWidget(self._title)
        self._description = QLabel(description)
        self._description.setObjectName("TurnaDialogDescription")
        self._description.setWordWrap(True)
        self._description.setVisible(bool(description))
        title_col.addWidget(self._description)
        hrow.addLayout(title_col, stretch=1)
        self._close_btn = TurnaButton(
            "", variant="ghost", size="sm", icon_name="x", parent=header
        )
        self._close_btn.setToolTip("关闭（Esc）")
        self._close_btn.clicked.connect(self.reject)
        hrow.addWidget(self._close_btn, 0, Qt.AlignmentFlag.AlignTop)
        root.addWidget(header)

        # --- body -----------------------------------------------------
        self._body_host = QWidget(self)
        self._body_host.setObjectName("TurnaDialogBody")
        self._body = QVBoxLayout(self._body_host)
        self._body.setContentsMargins(16, 8, 16, 8)
        self._body.setSpacing(10)
        root.addWidget(self._body_host, stretch=1)

        # --- footer ---------------------------------------------------
        footer = QWidget(self)
        footer.setObjectName("TurnaDialogFooter")
        self._footer = QHBoxLayout(footer)
        self._footer.setContentsMargins(16, 8, 16, 12)
        self._footer.setSpacing(8)
        self._footer.addStretch(1)
        root.addWidget(footer)
        self._footer_host = footer
        footer.setVisible(False)

    # --- content ------------------------------------------------------

    def body_layout(self) -> QVBoxLayout:
        return self._body

    def add_widget(self, widget: QWidget, stretch: int = 0) -> QWidget:
        self._body.addWidget(widget, stretch)
        return widget

    def add_layout(self, layout: QLayout, stretch: int = 0) -> None:
        self._body.addLayout(layout, stretch)

    def set_description(self, text: str) -> None:
        self._description.setText(text)
        self._description.setVisible(bool(text))

    # --- footer -------------------------------------------------------

    def add_button(
        self,
        text: str,
        *,
        variant: str = "secondary",
        slot=None,
        icon_name: str | None = None,
        default: bool = False,
    ) -> TurnaButton:
        btn = TurnaButton(text, variant=variant, icon_name=icon_name, parent=self)
        if slot is not None:
            btn.clicked.connect(slot)
        if default:
            btn.setDefault(True)
        self._footer.addWidget(btn)
        self._footer_host.setVisible(True)
        return btn

    def add_standard_buttons(
        self,
        *,
        ok_text: str = "确定",
        cancel_text: str = "取消",
        on_accept=None,
        ok_variant: str = "primary",
    ) -> tuple[TurnaButton, TurnaButton]:
        """Conventional Cancel + OK pair wired to reject/accept."""
        cancel = self.add_button(cancel_text, slot=self.reject)
        ok = self.add_button(
            ok_text,
            variant=ok_variant,
            slot=on_accept if on_accept is not None else self.accept,
            default=True,
        )
        return cancel, ok

    def reject(self) -> None:
        self.rejected.emit()
        super().reject()


class EmptyState(QWidget):
    """Centered empty view: icon + title + description + optional CTA."""

    def __init__(
        self,
        *,
        icon_name: str = "folder-open",
        title: str = "",
        description: str = "",
        cta_text: str = "",
        on_cta=None,
        parent=None,
    ) -> None:
        super().__init__(parent)
        self.setObjectName("EmptyState")
        col = QVBoxLayout(self)
        col.setContentsMargins(24, 32, 24, 32)
        col.setSpacing(10)
        col.addStretch(1)

        self._icon_label = QLabel()
        self._icon_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.set_icon(icon_name)
        col.addWidget(self._icon_label)

        self._title = QLabel(title)
        self._title.setObjectName("EmptyStateTitle")
        self._title.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self._title.setWordWrap(True)
        col.addWidget(self._title)

        self._desc = QLabel(description)
        self._desc.setObjectName("EmptyStateDescription")
        self._desc.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self._desc.setWordWrap(True)
        self._desc.setVisible(bool(description))
        col.addWidget(self._desc)

        self._cta: TurnaButton | None = None
        if cta_text:
            self.set_cta(cta_text, on_cta)
        col.addStretch(2)

    def set_icon(self, name: str) -> None:
        self._icon_label.setPixmap(_pixmap(name, size=40, role="muted"))

    def set_cta(self, text: str, slot=None) -> TurnaButton:
        if self._cta is None:
            self._cta = TurnaButton(text, variant="primary", parent=self)
            self._cta.setFixedWidth(180)
            # Centered below the description.
            self.layout().insertWidget(
                self.layout().count() - 1, self._cta, 0, Qt.AlignmentFlag.AlignCenter
            )
        else:
            self._cta.setText(text)
        if slot is not None:
            self._cta.clicked.connect(slot)
        return self._cta
