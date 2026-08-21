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
    BRAND_CLAY,
    BRAND_SAND,
    DEFAULT_THEME,
    PALETTES,
    is_dark,
    is_high_contrast,
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


def _opaque(color_aarrggbb: str, over_hex: str) -> str:
    """Pre-blend an ``#AARRGGBB`` color over an opaque ``#RRGGBB`` background.

    Qt paints some regions (e.g. the tree branch/indent gutter of a selected
    row) without alpha blending; pre-blending keeps those regions visually
    identical to the alpha-blended ``::item`` backgrounds.
    """
    alpha = int(color_aarrggbb[1:3], 16) / 255.0
    r = int(color_aarrggbb[3:5], 16) * alpha + int(over_hex[1:3], 16) * (1 - alpha)
    g = int(color_aarrggbb[5:7], 16) * alpha + int(over_hex[3:5], 16) * (1 - alpha)
    b = int(color_aarrggbb[7:9], 16) * alpha + int(over_hex[5:7], 16) * (1 - alpha)
    return f"#{round(r):02X}{round(g):02X}{round(b):02X}"


def _build_qss(palette: dict[str, str], base_font_px: int, theme: str) -> str:
    """Return a parameterized stylesheet string.

    The ``theme`` argument controls high-contrast adjustments (thicker
    borders, stronger focus rings) that cannot be derived from the palette
    alone.
    """
    p = palette
    hc = is_high_contrast(theme)
    # Opaque stand-in for accent_subtle: the tree branch/indent gutter of a
    # selected row is painted without alpha blending (verified by pixel
    # sampling), so it needs the pre-blended color to match ::item:selected.
    branch_selected = _opaque(p["accent_subtle"], p["bg_secondary"])

    # High-contrast tokens: thicker borders, stronger focus rings.
    border_w = "2px" if hc else "1px"
    focus_w = "2.5px" if hc else "2px"
    card_border = f"border: {border_w} solid {p['border']};" if hc else "border: 1px solid {border};".format(border=p["border"])
    input_focus_border = f"border: {focus_w} solid {p['accent']};"

    return f"""
/* Global palette */
QWidget {{
    background-color: {p['bg']};
    color: {p['text']};
    font-family: "Segoe UI", "Microsoft YaHei UI", "PingFang SC", sans-serif;
    font-size: {base_font_px}px;
    selection-background-color: {p['accent']};
    selection-color: #FFFFFF;
}}

QMainWindow {{
    background-color: {p['bg']};
}}

/* Toolbar - subtle Turna gradient for brand identity */
QToolBar {{
    background-color: qlineargradient(x1:0, y1:0, x2:0, y2:1,
        stop:0 {p['toolbar_gradient_start']},
        stop:1 {p['toolbar_gradient_end']});
    border: none;
    border-bottom: 1px solid {p['border']};
    padding: 6px 10px;
    spacing: 8px;
}}

QToolBar QToolButton,
QToolBar QAction {{
    background-color: transparent;
    color: {p['text']};
    border: 1px solid transparent;
    border-radius: 6px;
    padding: 6px 12px;
}}

QToolBar QToolButton:hover,
QToolBar QAction:hover {{
    background-color: {p['accent_subtle']};
    border-color: {p['border_hover']};
    color: {p['accent_text']};
}}

QToolBar QToolButton:pressed,
QToolBar QAction:pressed {{
    background-color: {p['accent']};
    color: #FFFFFF;
}}

QToolBar QToolButton:checked {{
    background-color: {p['accent']};
    color: #FFFFFF;
}}

QToolBar::separator {{
    background-color: {p['border']};
    width: 1px;
    margin: 4px 8px;
}}

/* Buttons - Turna gradient on primary */
QPushButton {{
    background-color: qlineargradient(x1:0, y1:0, x2:1, y2:1,
        stop:0 {p['accent_gradient_start']},
        stop:1 {p['accent_gradient_end']});
    color: #FFFFFF;
    border: none;
    border-radius: 8px;
    padding: 7px 16px;
    min-height: 28px;
}}

QPushButton:hover {{
    background-color: {p['accent_hover']};
}}

QPushButton:pressed {{
    background-color: {p['accent_pressed']};
}}

QPushButton:disabled {{
    background-color: {p['border']};
    color: {p['text_disabled']};
}}

QPushButton#dangerButton {{
    background-color: {p['danger']};
}}
QPushButton#dangerButton:hover {{
    background-color: {p['danger_hover']};
}}

/* Secondary brand (clay) — does not replace primary teal CTA (ADR 0033).
   Light hover: warm sand fill. Dark hover: elevated surface (sand too bright). */
QPushButton#secondaryButton {{
    background-color: {p['bg_input']};
    color: {BRAND_CLAY};
    border: {border_w} solid {BRAND_CLAY};
}}
QPushButton#secondaryButton:hover {{
    background-color: {BRAND_SAND if not is_dark(theme) else p['bg_elevated']};
    color: {BRAND_CLAY};
    border-color: {BRAND_CLAY};
}}

/* Tool buttons outside toolbars (toolbar buttons are styled above) */
QToolButton {{
    background-color: transparent;
    color: {p['text']};
    border: 1px solid transparent;
    border-radius: 6px;
    padding: 4px 8px;
}}

QToolButton:hover {{
    background-color: {p['accent_subtle']};
    color: {p['accent_text']};
}}

QToolButton:pressed {{
    background-color: {p['accent']};
    color: #FFFFFF;
}}

QToolButton:disabled {{
    color: {p['text_disabled']};
}}

/* Inputs */
QLineEdit,
QTextEdit,
QPlainTextEdit,
QComboBox,
QSpinBox,
QDoubleSpinBox {{
    background-color: {p['bg_input']};
    color: {p['text']};
    border: {border_w} solid {p['border']};
    border-radius: 6px;
    padding: 6px 8px;
    selection-background-color: {p['accent']};
}}

QLineEdit:focus,
QTextEdit:focus,
QPlainTextEdit:focus,
QComboBox:focus,
QSpinBox:focus,
QDoubleSpinBox:focus {{
    {input_focus_border}
}}

QLineEdit:disabled,
QTextEdit:disabled,
QComboBox:disabled,
QSpinBox:disabled {{
    background-color: {p['bg_disabled']};
    color: {p['text_disabled']};
}}

QComboBox::drop-down {{
    border: none;
    width: 24px;
}}

QComboBox::down-arrow {{
    image: none;
    border-left: 4px solid transparent;
    border-right: 4px solid transparent;
    border-top: 5px solid {p['text']};
    width: 0px;
    height: 0px;
}}

QComboBox QAbstractItemView {{
    background-color: {p['bg_input']};
    border: {border_w} solid {p['border']};
    selection-background-color: {p['accent']};
}}

/* Spin box step buttons */
QAbstractSpinBox::up-button,
QAbstractSpinBox::down-button {{
    border: none;
    background-color: transparent;
    width: 18px;
}}

QAbstractSpinBox::up-button:hover,
QAbstractSpinBox::down-button:hover {{
    background-color: {p['accent_subtle']};
}}

QAbstractSpinBox::up-arrow {{
    image: none;
    border-left: 4px solid transparent;
    border-right: 4px solid transparent;
    border-bottom: 5px solid {p['text']};
    width: 0px;
    height: 0px;
}}

QAbstractSpinBox::down-arrow {{
    image: none;
    border-left: 4px solid transparent;
    border-right: 4px solid transparent;
    border-top: 5px solid {p['text']};
    width: 0px;
    height: 0px;
}}

/* Lists / Trees */
QListWidget,
QTreeWidget {{
    background-color: {p['bg_secondary']};
    border: {border_w} solid {p['border']};
    border-radius: 8px;
    padding: 6px;
    outline: none;
}}

QListWidget::item,
QTreeWidget::item {{
    color: {p['text']};
    border-radius: 6px;
    border-left: 2px solid transparent;
    padding: 6px 8px;
    margin: 2px 0px;
}}

QListWidget::item:selected,
QTreeWidget::item:selected {{
    background-color: {p['accent_subtle']};
    color: {p['accent_text']};
    border-left: 2px solid {p['accent']};
}}

QListWidget::item:hover,
QTreeWidget::item:hover {{
    background-color: {p['accent_subtle']};
}}

QTreeWidget::item:selected:hover,
QListWidget::item:selected:hover {{
    background-color: {p['accent_subtle']};
    color: {p['accent_text']};
}}

QHeaderView::section {{
    background-color: {p['bg_secondary']};
    color: {p['text_secondary']};
    padding: 6px 8px;
    border: none;
    border-bottom: 1px solid {p['border']};
    font-weight: 600;
}}

QTreeWidget::branch {{
    background-color: transparent;
}}

QTreeWidget::branch:selected {{
    background-color: {branch_selected};
}}

/* Tables */
QTableView,
QTableWidget {{
    background-color: {p['bg_secondary']};
    border: {border_w} solid {p['border']};
    border-radius: 8px;
    gridline-color: {p['border']};
    alternate-background-color: {p['bg']};
    selection-background-color: {p['accent_subtle']};
    selection-color: {p['accent_text']};
}}

QTableView::item,
QTableWidget::item {{
    padding: 6px;
    border: none;
}}

QTableView::item:selected,
QTableWidget::item:selected {{
    background-color: {p['accent_subtle']};
    color: {p['accent_text']};
}}

/* Group boxes / Cards - elevated surface with border */
QGroupBox {{
    background-color: {p['bg_secondary']};
    {card_border}
    border-radius: 10px;
    margin-top: 12px;
    padding: 24px 16px 16px;
    font-weight: 600;
}}

QGroupBox::title {{
    subcontrol-origin: margin;
    subcontrol-position: top left;
    left: 12px;
    top: 8px;
    color: {p['text_secondary']};
    font-size: {base_font_px - 1}px;
    font-weight: 600;
}}

/* Labels */
QLabel {{
    background-color: transparent;
    color: {p['text']};
}}

QLabel#titleLabel {{
    font-size: {base_font_px + 4}px;
    font-weight: 700;
    color: {p['text']};
}}

QLabel#breadcrumbLabel {{
    color: {p['text_secondary']};
    font-size: {base_font_px - 1}px;
}}

QLabel#hintLabel {{
    color: {p['text_disabled']};
    font-size: {base_font_px - 2}px;
}}

/* Status bar */
QStatusBar {{
    background-color: {p['bg_secondary']};
    color: {p['text_secondary']};
    border-top: 1px solid {p['border']};
}}

QStatusBar::item {{
    border: none;
}}

/* Menus */
QMenu {{
    background-color: {p['bg_secondary']};
    border: {border_w} solid {p['border']};
    border-radius: 8px;
    padding: 6px;
}}

QMenu::item {{
    border-radius: 6px;
    padding: 6px 20px;
}}

QMenu::item:selected {{
    background-color: {p['accent']};
    color: #FFFFFF;
}}

QMenu::separator {{
    background-color: {p['border']};
    height: 1px;
    margin: 4px 10px;
}}

/* Splitter */
QSplitter::handle {{
    background-color: {p['border']};
}}

QSplitter::handle:horizontal {{
    width: 2px;
}}

QSplitter::handle:vertical {{
    height: 2px;
}}

/* Scrollbars */
QScrollBar:vertical {{
    background-color: {p['bg']};
    width: 8px;
    border-radius: 4px;
}}

QScrollBar::handle:vertical {{
    background-color: {p['scrollbar']};
    border-radius: 4px;
    min-height: 30px;
}}

QScrollBar::handle:vertical:hover {{
    background-color: {p['scrollbar_hover']};
}}

QScrollBar::add-line:vertical,
QScrollBar::sub-line:vertical {{
    height: 0px;
}}

QScrollBar:horizontal {{
    background-color: {p['bg']};
    height: 8px;
    border-radius: 4px;
}}

QScrollBar::handle:horizontal {{
    background-color: {p['scrollbar']};
    border-radius: 4px;
    min-width: 30px;
}}

QScrollBar::handle:horizontal:hover {{
    background-color: {p['scrollbar_hover']};
}}

QScrollBar::add-line:horizontal,
QScrollBar::sub-line:horizontal {{
    width: 0px;
}}

/* Dialogs */
QDialog {{
    background-color: {p['bg']};
}}

/* Checkboxes */
QCheckBox {{
    spacing: 8px;
}}

QCheckBox::indicator {{
    width: 16px;
    height: 16px;
    border-radius: 4px;
    border: {border_w} solid {p['text_disabled']};
    background-color: {p['bg_input']};
}}

QCheckBox::indicator:checked {{
    background-color: {p['accent']};
    border-color: {p['accent']};
}}

QCheckBox::indicator:disabled {{
    background-color: {p['bg_disabled']};
}}

/* Radio buttons (round counterpart of the checkbox style) */
QRadioButton {{
    spacing: 8px;
}}

QRadioButton::indicator {{
    width: 16px;
    height: 16px;
    border-radius: 8px;
    border: {border_w} solid {p['text_disabled']};
    background-color: {p['bg_input']};
}}

QRadioButton::indicator:checked {{
    background-color: {p['accent']};
    border-color: {p['accent']};
}}

QRadioButton::indicator:disabled {{
    background-color: {p['bg_disabled']};
}}

/* Tooltips */
QToolTip {{
    background-color: {p['bg_elevated']};
    color: {p['text']};
    border: {border_w} solid {p['border']};
    padding: 6px 8px;
    border-radius: 6px;
}}

/* Progress bars - Turna gradient chunk */
QProgressBar {{
    background-color: {p['bg_input']};
    border: {border_w} solid {p['border']};
    border-radius: 6px;
    text-align: center;
    color: {p['text']};
}}

QProgressBar::chunk {{
    background-color: qlineargradient(x1:0, y1:0, x2:1, y2:0,
        stop:0 {p['accent_gradient_start']},
        stop:1 {p['accent_gradient_end']});
    border-radius: 5px;
}}

/* Scroll areas: no frame, the content inside carries its own border */
QScrollArea {{
    border: none;
}}

/* Sliders - accent handle with glow ring */
QSlider::groove:horizontal {{
    background-color: {p['bg_input']};
    height: 6px;
    border-radius: 3px;
}}

QSlider::handle:horizontal {{
    background-color: {p['accent']};
    width: 16px;
    height: 16px;
    margin: -5px 0;
    border-radius: 8px;
    border: 2px solid {p['bg_secondary']};
}}

QSlider::handle:horizontal:hover {{
    background-color: {p['accent_hover']};
    border: 2px solid {p['glow']};
}}

QSlider::groove:vertical {{
    background-color: {p['bg_input']};
    width: 6px;
    border-radius: 3px;
}}

QSlider::handle:vertical {{
    background-color: {p['accent']};
    width: 16px;
    height: 16px;
    margin: 0 -5px;
    border-radius: 8px;
    border: 2px solid {p['bg_secondary']};
}}

QSlider::handle:vertical:hover {{
    background-color: {p['accent_hover']};
    border: 2px solid {p['glow']};
}}

/* Message boxes */
QMessageBox {{
    background-color: {p['bg']};
}}

QMessageBox QLabel {{
    color: {p['text']};
}}

/* Tab widget - selected tab gets Turna underline */
QTabWidget::pane {{
    border: {border_w} solid {p['border']};
    border-radius: 8px;
    background-color: {p['bg_secondary']};
}}

QTabBar::tab {{
    background-color: {p['bg_secondary']};
    color: {p['text_secondary']};
    border: 1px solid {p['border']};
    border-bottom: none;
    border-top-left-radius: 6px;
    border-top-right-radius: 6px;
    padding: 8px 16px;
    margin-right: 2px;
}}

QTabBar::tab:selected {{
    background-color: {p['bg']};
    color: {p['accent_text']};
    border-bottom: 3px solid {p['accent']};
}}

QTabBar::tab:hover {{
    background-color: {p['accent_subtle']};
    color: {p['accent_text']};
}}
"""


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
