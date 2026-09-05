"""Tree, list, header, and table QSS styles."""
from __future__ import annotations


def build_view_qss(p: dict[str, str], border_w: str, branch_selected: str) -> str:
    """Return QSS for list widgets, tree widgets, headers, and table views."""
    return f"""
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
"""
