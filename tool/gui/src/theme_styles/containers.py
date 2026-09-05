"""Group box, splitter, scrollbar, progress bar, slider, and tab QSS styles."""
from __future__ import annotations


def build_container_qss(
    p: dict[str, str],
    border_w: str,
    card_border: str,
    base_font_px: int,
) -> str:
    """Return QSS for containers, splitters, scrollbars, progress bars, sliders, and tabs."""
    title_font_px = base_font_px - 1

    return f"""
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
    font-size: {title_font_px}px;
    font-weight: 600;
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
