"""Global Qt stylesheet and font setup for the Varnamala GUI course editor.

Theming is intentionally centralized so the desktop app feels like a modern
content-editing tool rather than a raw Qt form.  Call :func:`apply_theme` once
after the QApplication is created.
"""
from __future__ import annotations

import os
import sys

from PySide6.QtCore import Qt
from PySide6.QtGui import QFont, QFontDatabase, QIcon
from PySide6.QtWidgets import QApplication


_DARK_QSS = """
/* Global palette */
QWidget {
    background-color: #181A20;
    color: #E8EAF0;
    font-family: "Segoe UI", "Microsoft YaHei UI", "PingFang SC", sans-serif;
    font-size: 14px;
    selection-background-color: #3B82F6;
    selection-color: #FFFFFF;
}

QMainWindow {
    background-color: #181A20;
}

/* Toolbar */
QToolBar {
    background-color: #1F232C;
    border: none;
    padding: 6px 10px;
    spacing: 8px;
}

QToolBar QToolButton,
QToolBar QAction {
    background-color: transparent;
    color: #E8EAF0;
    border: 1px solid transparent;
    border-radius: 6px;
    padding: 6px 12px;
}

QToolBar QToolButton:hover,
QToolBar QAction:hover {
    background-color: #2C313C;
    border-color: #3B82F6;
}

QToolBar QToolButton:pressed,
QToolBar QAction:pressed {
    background-color: #3B82F6;
    color: #FFFFFF;
}

QToolBar QToolButton:checked {
    background-color: #2563EB;
    color: #FFFFFF;
}

QToolBar::separator {
    background-color: #2C313C;
    width: 1px;
    margin: 4px 8px;
}

/* Buttons */
QPushButton {
    background-color: #3B82F6;
    color: #FFFFFF;
    border: none;
    border-radius: 6px;
    padding: 7px 16px;
    min-height: 28px;
}

QPushButton:hover {
    background-color: #2563EB;
}

QPushButton:pressed {
    background-color: #1D4ED8;
}

QPushButton:disabled {
    background-color: #2C313C;
    color: #6B7280;
}

QPushButton#dangerButton {
    background-color: #EF4444;
}
QPushButton#dangerButton:hover {
    background-color: #DC2626;
}

QPushButton#secondaryButton {
    background-color: #2C313C;
    color: #E8EAF0;
    border: 1px solid #3B82F6;
}
QPushButton#secondaryButton:hover {
    background-color: #3B82F6;
    color: #FFFFFF;
}

/* Inputs */
QLineEdit,
QTextEdit,
QPlainTextEdit,
QComboBox,
QSpinBox,
QDoubleSpinBox {
    background-color: #232833;
    color: #E8EAF0;
    border: 1px solid #2C313C;
    border-radius: 6px;
    padding: 6px 8px;
    selection-background-color: #3B82F6;
}

QLineEdit:focus,
QTextEdit:focus,
QPlainTextEdit:focus,
QComboBox:focus,
QSpinBox:focus,
QDoubleSpinBox:focus {
    border-color: #3B82F6;
}

QLineEdit:disabled,
QTextEdit:disabled,
QComboBox:disabled,
QSpinBox:disabled {
    background-color: #1C2028;
    color: #6B7280;
}

QComboBox::drop-down {
    border: none;
    width: 24px;
}

QComboBox::down-arrow {
    image: none;
    border-left: 4px solid transparent;
    border-right: 4px solid transparent;
    border-top: 5px solid #E8EAF0;
    width: 0px;
    height: 0px;
}

QComboBox QAbstractItemView {
    background-color: #232833;
    border: 1px solid #2C313C;
    selection-background-color: #3B82F6;
}

/* Lists / Trees */
QListWidget,
QTreeWidget {
    background-color: #1F232C;
    border: 1px solid #2C313C;
    border-radius: 8px;
    padding: 6px;
    outline: none;
}

QListWidget::item,
QTreeWidget::item {
    color: #E8EAF0;
    border-radius: 6px;
    padding: 6px 8px;
    margin: 2px 0px;
}

QListWidget::item:selected,
QTreeWidget::item:selected {
    background-color: #3B82F6;
    color: #FFFFFF;
}

QListWidget::item:hover,
QTreeWidget::item:hover {
    background-color: #2C313C;
}

QTreeWidget::item:selected:hover,
QListWidget::item:selected:hover {
    background-color: #2563EB;
}

QHeaderView::section {
    background-color: #1F232C;
    color: #9CA3AF;
    padding: 6px 8px;
    border: none;
    border-bottom: 1px solid #2C313C;
}

QTreeWidget::branch {
    background-color: transparent;
}

/* Group boxes / Cards */
QGroupBox {
    background-color: #1F232C;
    border: 1px solid #2C313C;
    border-radius: 10px;
    margin-top: 12px;
    padding-top: 24px;
    padding: 16px;
    font-weight: 600;
}

QGroupBox::title {
    subcontrol-origin: margin;
    subcontrol-position: top left;
    left: 12px;
    top: 8px;
    color: #9CA3AF;
    font-size: 13px;
    font-weight: 600;
}

/* Labels */
QLabel {
    background-color: transparent;
    color: #E8EAF0;
}

QLabel#titleLabel {
    font-size: 18px;
    font-weight: 700;
    color: #FFFFFF;
}

QLabel#breadcrumbLabel {
    color: #9CA3AF;
    font-size: 13px;
}

QLabel#hintLabel {
    color: #6B7280;
    font-size: 12px;
}

/* Status bar */
QStatusBar {
    background-color: #1F232C;
    color: #9CA3AF;
    border-top: 1px solid #2C313C;
}

QStatusBar::item {
    border: none;
}

/* Menus */
QMenu {
    background-color: #1F232C;
    border: 1px solid #2C313C;
    border-radius: 8px;
    padding: 6px;
}

QMenu::item {
    border-radius: 6px;
    padding: 6px 20px;
}

QMenu::item:selected {
    background-color: #3B82F6;
    color: #FFFFFF;
}

QMenu::separator {
    background-color: #2C313C;
    height: 1px;
    margin: 4px 10px;
}

/* Splitter */
QSplitter::handle {
    background-color: #2C313C;
}

QSplitter::handle:horizontal {
    width: 2px;
}

QSplitter::handle:vertical {
    height: 2px;
}

/* Scrollbars */
QScrollBar:vertical {
    background-color: #181A20;
    width: 8px;
    border-radius: 4px;
}

QScrollBar::handle:vertical {
    background-color: #4B5563;
    border-radius: 4px;
    min-height: 30px;
}

QScrollBar::handle:vertical:hover {
    background-color: #6B7280;
}

QScrollBar::add-line:vertical,
QScrollBar::sub-line:vertical {
    height: 0px;
}

QScrollBar:horizontal {
    background-color: #181A20;
    height: 8px;
    border-radius: 4px;
}

QScrollBar::handle:horizontal {
    background-color: #4B5563;
    border-radius: 4px;
    min-width: 30px;
}

QScrollBar::handle:horizontal:hover {
    background-color: #6B7280;
}

QScrollBar::add-line:horizontal,
QScrollBar::sub-line:horizontal {
    width: 0px;
}

/* Dialogs */
QDialog {
    background-color: #181A20;
}

/* Checkboxes */
QCheckBox {
    spacing: 8px;
}

QCheckBox::indicator {
    width: 16px;
    height: 16px;
    border-radius: 4px;
    border: 1px solid #4B5563;
    background-color: #232833;
}

QCheckBox::indicator:checked {
    background-color: #3B82F6;
    border-color: #3B82F6;
}

QCheckBox::indicator:disabled {
    background-color: #1C2028;
}

/* Message boxes */
QMessageBox {
    background-color: #181A20;
}

QMessageBox QLabel {
    color: #E8EAF0;
}
"""


def _system_font() -> QFont:
    font = QFont()
    preferred = ["Segoe UI", "Microsoft YaHei UI", "PingFang SC", "Noto Sans CJK SC"]
    for family in preferred:
        if QFontDatabase.hasFamily(family):
            font.setFamily(family)
            break
    font.setPointSize(10)
    font.setStyleStrategy(QFont.StyleStrategy.PreferAntialias)
    return font


def apply_theme(app: QApplication) -> None:
    """Apply a modern dark theme and consistent font to the application."""
    app.setStyle("Fusion")
    app.setStyleSheet(_DARK_QSS)
    app.setFont(_system_font())

    # High-DPI / fractional scaling on supported platforms.
    app.setAttribute(Qt.ApplicationAttribute.AA_UseHighDpiPixmaps, True)

    # Optional light-mode override for debugging or user preference.
    if os.environ.get("VARNAMALA_LIGHT_THEME") == "1":
        # Light theme can be added later if needed; keep dark as default.
        pass


def set_window_icon() -> QIcon | None:
    """Return a simple built-in icon; None if no icon is available."""
    return None
