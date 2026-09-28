"""Appearance tab for SettingsDialog (extracted, api-preserving)."""
from __future__ import annotations

from PySide6.QtWidgets import (
    QCheckBox,
    QComboBox,
    QFormLayout,
    QGroupBox,
    QLabel,
    QVBoxLayout,
    QWidget,
)


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

    # T21: the telemetry log is local-only, but it used to record absolute
    # paths and had no way to be turned off. Paths are now scrubbed, and this
    # switch stops recording altogether.
    privacy_group = QGroupBox("隐私")
    privacy_form = QFormLayout(privacy_group)
    privacy_form.setSpacing(10)
    dlg.telemetry_check = QCheckBox("记录本地使用日志（telemetry）")
    dlg.telemetry_check.setToolTip(
        "只写入本机应用数据目录下的 telemetry.log，不联网、不上传。\n"
        "用于排查崩溃与统计功能使用频率；绝对路径在写入前会被脱敏。\n"
        "关闭后不再记录任何事件。"
    )
    privacy_form.addRow(dlg.telemetry_check)
    privacy_note = QLabel("日志仅保留 7 天，可在应用数据目录中直接删除。")
    privacy_note.setObjectName("hintLabel")
    privacy_note.setWordWrap(True)
    privacy_form.addRow(privacy_note)
    layout.addWidget(privacy_group)

    layout.addStretch(1)
    return tab

