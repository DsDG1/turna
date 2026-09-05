"""Input field, combo box, spin box, checkbox, and radio button QSS styles."""
from __future__ import annotations


def build_input_qss(p: dict[str, str], border_w: str, focus_w: str) -> str:
    """Return QSS for inputs, dropdowns, spin boxes, checkboxes, and radio buttons."""
    return f"""
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
    border: {focus_w} solid {p['accent']};
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
"""
