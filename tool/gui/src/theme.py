"""Global Qt stylesheet and font setup for the Varnamala GUI course editor.

Theming is intentionally centralized so the desktop app feels like a modern
content-editing tool rather than a raw Qt form.  Call :func:`apply_theme` once
after the QApplication is created.
"""
from __future__ import annotations

import os
from typing import TYPE_CHECKING

from PySide6.QtGui import QFont, QFontDatabase
from PySide6.QtWidgets import QApplication

if TYPE_CHECKING:
    from src.application.settings import Settings


# Color palettes for the two built-in themes.
_DARK_PALETTE = {
    "bg": "#181A20",
    "bg_secondary": "#1F232C",
    "bg_input": "#232833",
    "bg_elevated": "#262C38",
    "bg_disabled": "#1C2028",
    "text": "#E8EAF0",
    "text_secondary": "#9CA3AF",
    "text_disabled": "#6B7280",
    "border": "#2C313C",
    "border_hover": "#3B82F6",
    "accent": "#3B82F6",
    "accent_hover": "#2563EB",
    "accent_pressed": "#1D4ED8",
    "accent_subtle": "#4D3B82F6",
    "accent_text": "#60A5FA",
    "danger": "#EF4444",
    "danger_hover": "#DC2626",
    "scrollbar": "#4B5563",
    "scrollbar_hover": "#6B7280",
    "success": "#27AE60",
    "warning": "#FF9F43",
    "error": "#E74C3C",
    # AI dialog semantic colors (guiplan2 P5.4) — drive the split widgets'
    # per-widget stylesheets instead of inline hexes.
    "ai_chat_bg": "#1A1D23",
    "ai_bubble_bg": "#2C313C",
    "ai_user_bubble": "#145A64",
    "ai_card_bg": "#1F232C",
    "ai_chip_bg": "#1F232C",
    "ai_accent": "#46D1BF",
    "ai_accent_border": "#1F727E",
    "ai_beta_bg": "#664400",
    "ai_beta_text": "#FFD93D",
}

_LIGHT_PALETTE = {
    "bg": "#F8F9FB",
    "bg_secondary": "#FFFFFF",
    "bg_input": "#FFFFFF",
    "bg_elevated": "#FFFFFF",
    "bg_disabled": "#F3F4F6",
    "text": "#1F2937",
    "text_secondary": "#6B7280",
    "text_disabled": "#9CA3AF",
    "border": "#E5E7EB",
    "border_hover": "#3B82F6",
    "accent": "#3B82F6",
    "accent_hover": "#2563EB",
    "accent_pressed": "#1D4ED8",
    "accent_subtle": "#263B82F6",
    "accent_text": "#2563EB",
    "danger": "#EF4444",
    "danger_hover": "#DC2626",
    "scrollbar": "#D1D5DB",
    "scrollbar_hover": "#9CA3AF",
    "success": "#27AE60",
    "warning": "#FF9F43",
    "error": "#E74C3C",
    # AI dialog semantic colors (light variants).
    "ai_chat_bg": "#F3F4F6",
    "ai_bubble_bg": "#FFFFFF",
    "ai_user_bubble": "#1F727E",
    "ai_card_bg": "#FFFFFF",
    "ai_chip_bg": "#EEF2F7",
    "ai_accent": "#1F727E",
    "ai_accent_border": "#145A64",
    "ai_beta_bg": "#FFF3D6",
    "ai_beta_text": "#7A5A00",
}


# The palette applied by the most recent ``apply_theme`` call. Widgets that
# build per-widget stylesheets (e.g. the AI dialog's split widgets) read this
# via :func:`current_palette` so they follow the active light/dark theme.
_ACTIVE_PALETTE: dict[str, str] = _DARK_PALETTE


def current_palette() -> dict[str, str]:
    """Return the palette applied by the last :func:`apply_theme` call."""
    return _ACTIVE_PALETTE


def ai_color(name: str) -> str:
    """Return a single AI semantic color from the active palette."""
    return _ACTIVE_PALETTE[name]


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


def _build_qss(palette: dict[str, str], base_font_px: int) -> str:
    """Return a parameterized stylesheet string."""
    p = palette
    # Opaque stand-in for accent_subtle: the tree branch/indent gutter of a
    # selected row is painted without alpha blending (verified by pixel
    # sampling), so it needs the pre-blended color to match ::item:selected.
    branch_selected = _opaque(p["accent_subtle"], p["bg_secondary"])
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

/* Toolbar */
QToolBar {{
    background-color: {p['bg_secondary']};
    border: none;
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
    background-color: {p['border']};
    border-color: {p['border_hover']};
}}

QToolBar QToolButton:pressed,
QToolBar QAction:pressed {{
    background-color: {p['accent']};
    color: #FFFFFF;
}}

QToolBar QToolButton:checked {{
    background-color: {p['accent_hover']};
    color: #FFFFFF;
}}

QToolBar::separator {{
    background-color: {p['border']};
    width: 1px;
    margin: 4px 8px;
}}

/* Buttons */
QPushButton {{
    background-color: {p['accent']};
    color: #FFFFFF;
    border: none;
    border-radius: 6px;
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

QPushButton#secondaryButton {{
    background-color: {p['border']};
    color: {p['text']};
    border: 1px solid {p['border_hover']};
}}
QPushButton#secondaryButton:hover {{
    background-color: {p['accent']};
    color: #FFFFFF;
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
    background-color: {p['border']};
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
    border: 1px solid {p['border']};
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
    border-color: {p['border_hover']};
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
    border: 1px solid {p['border']};
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
    background-color: {p['border']};
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
    border: 1px solid {p['border']};
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
    background-color: {p['border']};
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
    border: 1px solid {p['border']};
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

/* Group boxes / Cards */
QGroupBox {{
    background-color: {p['bg_secondary']};
    border: 1px solid {p['border']};
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
    border: 1px solid {p['border']};
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
    border: 1px solid {p['text_disabled']};
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
    border: 1px solid {p['text_disabled']};
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
    border: 1px solid {p['border']};
    padding: 6px 8px;
    border-radius: 6px;
}}

/* Progress bars */
QProgressBar {{
    background-color: {p['bg_input']};
    border: 1px solid {p['border']};
    border-radius: 6px;
    text-align: center;
    color: {p['text']};
}}

QProgressBar::chunk {{
    background-color: {p['accent']};
    border-radius: 5px;
}}

/* Scroll areas: no frame, the content inside carries its own border */
QScrollArea {{
    border: none;
}}

/* Sliders */
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
}}

QSlider::handle:horizontal:hover {{
    background-color: {p['accent_hover']};
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
}}

QSlider::handle:vertical:hover {{
    background-color: {p['accent_hover']};
}}

/* Message boxes */
QMessageBox {{
    background-color: {p['bg']};
}}

QMessageBox QLabel {{
    color: {p['text']};
}}

/* Tab widget */
QTabWidget::pane {{
    border: 1px solid {p['border']};
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
    color: {p['text']};
}}

QTabBar::tab:hover {{
    background-color: {p['border']};
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
    """
    theme = "dark"
    scale = 100
    if settings is not None:
        theme = settings.theme if settings.theme in {"dark", "light"} else "dark"
        scale = settings.ui_scale_percent

    palette = _LIGHT_PALETTE if theme == "light" else _DARK_PALETTE
    base_font_px = _base_font_px_from_scale(scale)

    global _ACTIVE_PALETTE
    _ACTIVE_PALETTE = palette

    app.setStyle("Fusion")
    app.setStyleSheet(_build_qss(palette, base_font_px))

    # Scale the system font proportionally. Keep the point-size baseline at 10
    # for 100% scale.
    point_size = int(10 * scale / 100)
    app.setFont(_system_font(point_size))

    # High-DPI pixmaps are the default in Qt 6; no explicit attribute needed.
