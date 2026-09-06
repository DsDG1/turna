"""AI usage / telemetry tab for SettingsDialog (extracted)."""
from __future__ import annotations

from typing import Any

from PySide6.QtWidgets import (
    QGroupBox,
    QHBoxLayout,
    QLabel,
    QPushButton,
    QTextBrowser,
    QVBoxLayout,
    QWidget,
)

from src.application.settings import app_data_dir
from src.backend import ai_presets
from src.infrastructure.telemetry import telemetry


def build_ai_usage_tab(dlg) -> QWidget:
    tab, layout = dlg._make_tab()

    summary_group = QGroupBox("本地用量概览")
    summary_layout = QVBoxLayout(summary_group)
    summary_layout.setSpacing(10)

    dlg.ai_usage_label = QLabel("正在读取本地 telemetry 日志...")
    dlg.ai_usage_label.setWordWrap(True)
    summary_layout.addWidget(dlg.ai_usage_label)

    dlg.ai_usage_detail = QTextBrowser()
    dlg.ai_usage_detail.setMaximumHeight(220)
    summary_layout.addWidget(dlg.ai_usage_detail)

    buttons = QHBoxLayout()
    buttons.setSpacing(8)
    dlg.ai_usage_refresh_btn = QPushButton("刷新")
    dlg.ai_usage_refresh_btn.clicked.connect(dlg._refresh_ai_usage)
    buttons.addWidget(dlg.ai_usage_refresh_btn)

    dlg.ai_usage_open_dir_btn = QPushButton("打开日志目录")
    dlg.ai_usage_open_dir_btn.clicked.connect(dlg._on_open_telemetry_dir)
    buttons.addWidget(dlg.ai_usage_open_dir_btn)

    dlg.ai_usage_clear_btn = QPushButton("清空本地记录")
    dlg.ai_usage_clear_btn.setObjectName("dangerButton")
    dlg.ai_usage_clear_btn.clicked.connect(dlg._on_clear_telemetry)
    buttons.addWidget(dlg.ai_usage_clear_btn)
    buttons.addStretch(1)
    summary_layout.addLayout(buttons)

    layout.addWidget(summary_group)

    note = QLabel(
        "说明：token 与成本为本地估算，仅供参考，不作为计费依据。"
    )
    note.setObjectName("hintLabel")
    note.setWordWrap(True)
    layout.addWidget(note)
    layout.addStretch(1)
    return tab


def refresh_ai_usage(dlg) -> None:
    summary = telemetry.usage_summary()
    today = summary.get("today", {})
    total = summary.get("total", {})

    today_text = dlg._format_usage_bucket(today)
    total_text = dlg._format_usage_bucket(total)
    dlg.ai_usage_label.setText(
        f"今日：{today_text}　|　累计：{total_text}"
    )

    dlg.ai_usage_detail.setHtml("<br>".join([
        "<b>今日</b>", dlg._usage_bucket_html(today),
        "<b>累计</b>", dlg._usage_bucket_html(total),
    ]))



def format_usage_bucket(bucket: dict[str, Any]) -> str:
    tokens = bucket.get("total_tokens", 0)
    requests = bucket.get("requests", 0)
    cost = bucket.get("estimated_cost")
    currency = bucket.get("currency", "CNY")
    symbol = ai_presets.currency_symbol(currency)
    cost_text = f"{symbol}{cost:.2f}" if cost is not None else "—"
    return f"{tokens} tokens · {requests} 次请求 · 约 {cost_text}"



def usage_bucket_html(bucket: dict[str, Any]) -> str:
    ok = bucket.get("success", 0)
    failed = bucket.get("failure", 0)
    cost = bucket.get("estimated_cost")
    currency = bucket.get("currency", "CNY")
    symbol = ai_presets.currency_symbol(currency)
    cost_text = f"{symbol}{cost:.2f}" if cost is not None else "—"
    return (
        f"tokens: {bucket.get('total_tokens', 0)} "
        f"(in {bucket.get('prompt_tokens', 0)} / out {bucket.get('completion_tokens', 0)})<br>"
        f"请求: {bucket.get('requests', 0)}（成功 {ok} / 失败 {failed}）<br>"
        f"估算成本: {cost_text} ({currency})"
    )



def on_open_telemetry_dir(dlg) -> None:
    from pathlib import Path

    from PySide6.QtCore import QUrl
    from PySide6.QtGui import QDesktopServices

    QDesktopServices.openUrl(QUrl.fromLocalFile(str(app_data_dir())))



def on_clear_telemetry(dlg) -> None:
    if dlg._confirm_clear("清空本地 AI 用量记录", "确定要清空本地 telemetry 日志吗？此操作不可撤销。"):
        telemetry.clear()
        dlg._refresh_ai_usage()

