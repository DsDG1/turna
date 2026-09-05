"""Global Qt stylesheet and font setup for the Turna GUI course editor.

Theming is intentionally centralized so the desktop app feels like a modern
content-editing tool rather than a raw Qt form.  Call :func:`apply_theme` once
after the QApplication is created.

Design language: **Turna** - aligned with the Flutter app's
``TurnaTheme`` (``lib/views/theme.dart``). The accent family is navy / teal /
reed. Four themes are supported: ``dark`` (default), ``light``,
``high-contrast-dark``, and ``high-contrast-light``.

Palette token tables live in :mod:`src.theme_tokens` (Qt-free, unit-testable).
This module owns the QSS generation, the ``QApplication`` wiring, and the
runtime ``current_palette`` / ``ai_color`` accessors used by widgets.
"""
from __future__ import annotations

from typing import TYPE_CHECKING

from PySide6.QtGui import QColor, QFont, QFontDatabase
from PySide6.QtWidgets import QApplication, QGraphicsDropShadowEffect, QWidget

from src.theme_tokens import (
    DEFAULT_THEME,
    PALETTES,
    palette_for,
    valid_themes,
)

if TYPE_CHECKING:
    from src.application.settings import Settings


# Backward-compatible aliases. Some widgets or tests may still reference the
# old module-level palette dicts directly.
_DARK_PALETTE = PALETTES["dark"]
_LIGHT_PALETTE = PALETTES["light"]


# The palette applied by the most recent ``apply_theme`` call. Widgets that
# build per-widget stylesheets (e.g. the AI dialog's split widgets) read this
# via :func:`current_palette` so they follow the active light/dark theme.
_ACTIVE_PALETTE: dict[str, str] = _DARK_PALETTE
_ACTIVE_THEME: str = DEFAULT_THEME


def current_palette() -> dict[str, str]:
    """Return the palette applied by the last :func:`apply_theme` call."""
    return _ACTIVE_PALETTE


def current_theme() -> str:
    """Return the theme name applied by the last :func:`apply_theme` call."""
    return _ACTIVE_THEME


def ai_color(name: str) -> str:
    """Return a single AI semantic color from the active palette."""
    return _ACTIVE_PALETTE[name]


def resolve_theme(theme: str | None) -> str:
    """Validate *theme* and fall back to the default when invalid."""
    if theme in valid_themes():
        return theme
    return DEFAULT_THEME


from src.theme_styles.builder import build_qss, opaque


def _opaque(color_aarrggbb: str, over_hex: str) -> str:
    """Pre-blend an ``#AARRGGBB`` color over an opaque ``#RRGGBB`` background.

    Delegated to :func:`src.theme_styles.builder.opaque`.
    """
    return opaque(color_aarrggbb, over_hex)


def _build_qss(palette: dict[str, str], base_font_px: int, theme: str) -> str:
    """Return a parameterized stylesheet string.

    Delegated to :func:`src.theme_styles.builder.build_qss`.
    """
    return build_qss(palette, base_font_px, theme)



def _system_font(base_point_size: int = 10) -> QFont:
    font = QFont()
    preferred = ["Segoe UI", "Microsoft YaHei UI", "PingFang SC", "Noto Sans CJK SC"]
    for family in preferred:
        if QFontDatabase.hasFamily(family):
            font.setFamily(family)
            break
    font.setPointSize(base_point_size)
    font.setStyleStrategy(QFont.StyleStrategy.PreferAntialias)
    return font


def _base_font_px_from_scale(ui_scale_percent: int) -> int:
    """Map a UI scale percentage to the global base font size in pixels.

    The original stylesheet used ``font-size: 14px`` as the 100% baseline.
    """
    scale = max(80, min(150, ui_scale_percent))
    return int(14 * scale / 100)


def apply_theme(app: QApplication, settings: "Settings | None" = None) -> None:
    """Apply theme and font scaling to the application.

    If ``settings`` is omitted, the default dark theme at 100% scale is used.
    Supported themes: ``dark``, ``light``, ``high-contrast-dark``,
    ``high-contrast-light``.
    """
    theme = DEFAULT_THEME
    scale = 100
    if settings is not None:
        theme = resolve_theme(settings.theme)
        scale = settings.ui_scale_percent

    palette = palette_for(theme)
    base_font_px = _base_font_px_from_scale(scale)

    global _ACTIVE_PALETTE, _ACTIVE_THEME
    _ACTIVE_PALETTE = palette
    _ACTIVE_THEME = theme

    app.setStyle("Fusion")
    app.setStyleSheet(_build_qss(palette, base_font_px, theme))

    # Scale the system font proportionally. Keep the point-size baseline at 10
    # for 100% scale.
    point_size = int(10 * scale / 100)
    app.setFont(_system_font(point_size))

    # High-DPI pixmaps are the default in Qt 6; no explicit attribute needed.


def apply_shadow(
    widget: QWidget,
    *,
    color_key: str = "shadow",
    blur_radius: int = 20,
    dy: int = 4,
    alpha: float = 0.15,
) -> QGraphicsDropShadowEffect | None:
    """Apply a soft Turna-tinted drop shadow to *widget*.

    QSS does not support ``box-shadow``; this helper bridges that gap by
    attaching a ``QGraphicsDropShadowEffect`` from code. The shadow color
    is drawn from the active palette (*color_key*), defaulting to the
    ``shadow`` token (pure black in dark themes, Turna teal in light).

    Returns the effect so callers can tweak it further, or ``None`` if the
    widget is ``None`` (defensive for partially-constructed widgets).

    Example::

        from src.theme import apply_shadow
        apply_shadow(self.core_button, color_key="glow", blur_radius=24, alpha=0.3)
    """
    if widget is None:
        return None
    pal = current_palette()
    base_hex = pal.get(color_key, "#000000")
    # Parse #RRGGBB and apply alpha.
    r = int(base_hex[1:3], 16)
    g = int(base_hex[3:5], 16)
    b = int(base_hex[5:7], 16)
    a = max(0.0, min(1.0, alpha))
    effect = QGraphicsDropShadowEffect(widget)
    effect.setBlurRadius(blur_radius)
    effect.setOffset(0, dy)
    effect.setColor(QColor(r, g, b, int(a * 255)))
    widget.setGraphicsEffect(effect)
    return effect
