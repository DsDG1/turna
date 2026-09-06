"""Operation-log viewer tab for SettingsDialog (extracted)."""
from __future__ import annotations

import json
from typing import Any

from PySide6.QtCore import QTimer
from PySide6.QtWidgets import (
    QComboBox,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QMessageBox,
    QPushButton,
    QTextBrowser,
    QVBoxLayout,
    QWidget,
)

from src.infrastructure.operations_log import operations


def build_operation_log_tab(dlg) -> QWidget:
    """Detailed log of user actions, window durations, AI latency, errors."""
    tab = QWidget()
    layout = QVBoxLayout(tab)
    layout.setSpacing(10)
    layout.setContentsMargins(12, 12, 12, 12)

    # Filter row: event-type combo + search box + action buttons.
    filter_row = QHBoxLayout()
    filter_row.setSpacing(8)

    dlg.oplog_filter_combo = QComboBox()
    dlg.oplog_filter_combo.addItem("全部", "")
    dlg.oplog_filter_combo.addItem("点击 (ui.click)", "ui.click")
    dlg.oplog_filter_combo.addItem("输入 (ui.input)", "ui.input")
    dlg.oplog_filter_combo.addItem("窗口 (window.)", "window.")
    dlg.oplog_filter_combo.addItem("AI 耗时 (ai.)", "ai.")
    dlg.oplog_filter_combo.addItem("错误 (app.error)", "app.error")
    dlg.oplog_filter_combo.addItem("启动 (app.start)", "app.start")
    dlg.oplog_filter_combo.currentIndexChanged.connect(dlg._refresh_operation_log)
    filter_row.addWidget(QLabel("类别:"))
    filter_row.addWidget(dlg.oplog_filter_combo)

    dlg.oplog_search_edit = QLineEdit()
    dlg.oplog_search_edit.setPlaceholderText("搜索（子串，大小写不敏感）...")
    # Debounce: each refresh re-parses both log files; avoid doing that
    # per keystroke.
    dlg._oplog_search_timer = QTimer(dlg)
    dlg._oplog_search_timer.setSingleShot(True)
    dlg._oplog_search_timer.setInterval(300)
    dlg._oplog_search_timer.timeout.connect(dlg._refresh_operation_log)
    dlg.oplog_search_edit.textChanged.connect(dlg._oplog_search_timer.start)
    filter_row.addWidget(dlg.oplog_search_edit, 1)

    dlg.oplog_refresh_btn = QPushButton("刷新")
    dlg.oplog_refresh_btn.clicked.connect(dlg._refresh_operation_log)
    filter_row.addWidget(dlg.oplog_refresh_btn)
    dlg.oplog_open_dir_btn = QPushButton("打开日志目录")
    dlg.oplog_open_dir_btn.clicked.connect(dlg._on_open_telemetry_dir)
    filter_row.addWidget(dlg.oplog_open_dir_btn)
    dlg.oplog_clear_btn = QPushButton("清空操作日志")
    dlg.oplog_clear_btn.setObjectName("dangerButton")
    dlg.oplog_clear_btn.clicked.connect(dlg._on_clear_operation_log)
    filter_row.addWidget(dlg.oplog_clear_btn)
    layout.addLayout(filter_row)

    # Summary line.
    dlg.oplog_summary_label = QLabel("")
    dlg.oplog_summary_label.setObjectName("hintLabel")
    dlg.oplog_summary_label.setWordWrap(True)
    layout.addWidget(dlg.oplog_summary_label)

    # Read-only event view.
    dlg.oplog_view = QTextBrowser()
    dlg.oplog_view.setOpenExternalLinks(False)
    dlg.oplog_view.setLineWrapMode(QTextBrowser.LineWrapMode.NoWrap)
    font = dlg.oplog_view.font()
    font.setFamily("monospace")
    dlg.oplog_view.setFont(font)
    layout.addWidget(dlg.oplog_view, 1)

    note = QLabel(
        "记录最近 500 条操作（点击、输入、窗口运行时长、AI 回复耗时、启动时间、运行错误）。"
        "API Key 等敏感字段记为 <redacted>。日志位于 ~/.turna-gui/，按天轮转保留 7 天。"
    )
    note.setObjectName("hintLabel")
    note.setWordWrap(True)
    layout.addWidget(note)
    return tab



def refresh_operation_log(dlg) -> None:
    """Render the merged, filtered recent events into the log view."""
    try:
        from src.infrastructure.operations_log import operations as ops
        from src.infrastructure.telemetry import telemetry as tel

        prefix = dlg.oplog_filter_combo.currentData() or None
        search = dlg.oplog_search_edit.text().strip().lower()

        ops_events = ops.recent_events(500, event_prefix=prefix)
        tel_events = tel.recent_events(500, event_prefix=prefix)
        merged = sorted(
            ops_events + tel_events,
            key=lambda r: r.get("ts", ""),
        )

        if search:
            merged = [r for r in merged if search in json.dumps(r, ensure_ascii=False).lower()]

        dlg.oplog_view.setPlainText("\n".join(dlg._format_log_line(r) for r in merged))

        # Summary.
        counts: dict[str, int] = {}
        startup_ms: float | None = None
        ai_ms: float | None = None
        for r in merged:
            event = r.get("event", "")
            key = event.split(".")[0] if event else "?"
            counts[key] = counts.get(key, 0) + 1
            if event == "app.startup" and "duration_ms" in r:
                startup_ms = r["duration_ms"]
            if event == "ai.generate" and "duration_ms" in r:
                ai_ms = r["duration_ms"]
        parts = [f"共 {len(merged)} 条"]
        for key in sorted(counts):
            parts.append(f"{key}·{counts[key]}")
        if startup_ms is not None:
            parts.append(f"启动 {startup_ms:.0f}ms")
        if ai_ms is not None:
            parts.append(f"最近 AI {ai_ms:.0f}ms")
        dlg.oplog_summary_label.setText("　|　".join(parts))
    except Exception:
        dlg.oplog_view.setPlainText("（读取操作日志失败）")



def format_log_line(record: dict[str, Any]) -> str:
    ts = str(record.get("ts", ""))[11:19]  # time-of-day only
    event = record.get("event", "")
    payload = record.get("payload") or {}
    context = record.get("context") or {}
    target = payload.get("target") or payload.get("window") or ""
    window = context.get("window", "")
    dur = record.get("duration_ms")
    dur_text = f" [{dur:.0f}ms]" if dur is not None else ""
    text = payload.get("text", "")
    text_part = f" «{text}»" if text else ""
    return f"{ts} {event}{dur_text} {target}{text_part} @{window}".rstrip()



def confirm_clear(dlg, title: str, message: str) -> bool:
    """Ask a yes/no clear confirmation; return True when the user confirms."""
    reply = QMessageBox.question(
        dlg,
        title,
        message,
        QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
        QMessageBox.StandardButton.No,
    )
    return reply == QMessageBox.StandardButton.Yes



def on_clear_operation_log(dlg) -> None:
    if dlg._confirm_clear(
        "清空操作日志",
        "确定要清空 operations.log 吗？（仅清操作记录，保留 telemetry.log 的 AI 用量/错误/启动时间）此操作不可撤销。",
    ):
        operations.clear()
        dlg._refresh_operation_log()

