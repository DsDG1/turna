"""Core and global widget QSS styles."""
from __future__ import annotations


def build_core_qss(p: dict[str, str], base_font_px: int, border_w: str) -> str:
    """Return QSS for global window, toolbar, menus, labels, and status bar."""
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

/* Dialogs */
QDialog {{
    background-color: {p['bg']};
}}

/* Tooltips */
QToolTip {{
    background-color: {p['bg_elevated']};
    color: {p['text']};
    border: {border_w} solid {p['border']};
    padding: 6px 8px;
    border-radius: 6px;
}}

/* Scroll areas: no frame, the content inside carries its own border */
QScrollArea {{
    border: none;
}}

/* Message boxes */
QMessageBox {{
    background-color: {p['bg']};
}}

QMessageBox QLabel {{
    color: {p['text']};
}}
"""
