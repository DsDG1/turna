"""Appearance tab for SettingsDialog (extracted, api-preserving)."""
from __future__ import annotations

from PySide6.QtWidgets import QComboBox, QFormLayout, QGroupBox, QLabel, QVBoxLayout, QWidget


def build_appearance_tab(dlg) -> QWidget:
    tab, layout = dlg._make_tab()

    group = QGroupBox("外观")
    form = QFormLayout(group)
    form.setSpacing(10)

    dlg.theme_combo = QComboBox()
    dlg.theme_combo.addItem("深色", "dark")
    dlg.theme_combo.addItem("浅色", "light")
    dlg.theme_combo.addItem("高对比度-深", "high-contrast-dark")
    dlg.theme_combo.addItem("高对比度-浅", "high-contrast-light")
    form.addRow("主题:", dlg.theme_combo)

    dlg.scale_combo = QComboBox()
    for percent in range(80, 160, 10):
        dlg.scale_combo.addItem(f"{percent}%", percent)
    form.addRow("UI 字体缩放:", dlg.scale_combo)

    dlg.scale_hint = QLabel("调整全局字体大小。整体窗口缩放由系统 DPI 设置控制。")
    dlg.scale_hint.setObjectName("hintLabel")
    form.addRow(dlg.scale_hint)

    layout.addWidget(group)
    layout.addStretch(1)
    return tab

