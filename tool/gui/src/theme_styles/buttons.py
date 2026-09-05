"""Button and tool button QSS styles."""
from __future__ import annotations

from src.theme_tokens import BRAND_CLAY, BRAND_SAND, is_dark


def build_button_qss(p: dict[str, str], border_w: str, theme: str) -> str:
    """Return QSS for push buttons, danger/secondary variants, and tool buttons."""
    secondary_hover_bg = BRAND_SAND if not is_dark(theme) else p["bg_elevated"]

    return f"""
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
    background-color: {secondary_hover_bg};
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
"""
