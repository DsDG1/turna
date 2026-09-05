"""Experience Copilot Dock (E0 shell + E1.7 memory).

Shows course health, local suggestions, pin control, and a recent timeline.
Suggestion / timeline clicks emit signals — MainWindow dispatches actions
with preview + confirm (no silent writes).
"""
from __future__ import annotations

import logging
logger = logging.getLogger(__name__)


from typing import Any

from PySide6.QtCore import QTimer, Qt, Signal
from PySide6.QtWidgets import (
    QFrame,
    QHBoxLayout,
    QLabel,
    QPushButton,
    QScrollArea,
    QSizePolicy,
    QVBoxLayout,
    QWidget,
)

from src.backend.experience import ExperienceContext
from src.theme import current_palette


def _pal(key: str) -> str:
    return current_palette().get(key, "#888")


def _short(text: str, limit: int = 48) -> str:
    text = (text or "").replace("\n", " ").strip()
    if len(text) <= limit:
        return text
    return text[: limit - 1] + "…"


def _budget_line(ctx: ExperienceContext | None) -> str:
    """M-08: compact daily AI budget line from usage_today + settings.

    Never raises. Empty when unlimited (limit 0) and no usage to show.
    """
    try:
        used = 0
        if ctx is not None:
            usage = getattr(ctx, "usage_today", None) or {}
            if isinstance(usage, dict):
                used = int(usage.get("requests") or 0)
        limit = 0
        try:
            from src.application.runtime_context import current_settings

            limit = int(
                getattr(current_settings(), "experience_daily_ai_budget", 0) or 0
            )
        except Exception:
            limit = 0
        if limit <= 0:
            if used <= 0:
                return ""
            return f"今日 AI {used} 次 · 不限"
        color = ""
        if used >= limit:
            color = " style='color:#dc2626'"
        return f"<span{color}>今日 AI {used}/{limit}</span>"
    except Exception:
        return ""


def _metrics_line(metrics: dict | None) -> str:
    """C-14: compact metrics readout from ExperienceMetrics.snapshot().

    Omit any segment whose value is missing / zero-denominator. Never raises.
    """
    if not metrics or not isinstance(metrics, dict):
        return ""
    parts: list[str] = []
    ir = metrics.get("interception_rate")
    if isinstance(ir, (int, float)):
        parts.append(f"意图拦截 {int(round(ir * 100))}%")
    totals = metrics.get("suggestion_totals") or {}
    if isinstance(totals, dict):
        shown = int(totals.get("shown", 0) or 0)
        applied = int(totals.get("applied", 0) or 0)
        accepted = int(totals.get("accepted", 0) or 0)
        if accepted or applied:
            parts.append(f"建议 应用 {applied}/{accepted}")
    ambient = metrics.get("ambient") or {}
    if isinstance(ambient, dict):
        muted = int(ambient.get("muted", 0) or 0)
        if muted:
            parts.append(f"Ambient 静音 {muted}")
    guard = metrics.get("guard") or {}
    if isinstance(guard, dict):
        rej = int(guard.get("rejected", 0) or 0)
        if rej:
            parts.append(f"Guard 拒 {rej}")
    return " · ".join(parts)


class ExperienceDock(QWidget):
    """Right-edge health dashboard + suggestions + pin + timeline."""

    suggestion_clicked = Signal(dict)
    timeline_clicked = Signal(dict)
    pin_toggled = Signal()  # MainWindow toggles pin on current selection
    # M-07: clear cross-course author profile (privacy; no course write).
    clear_profile_clicked = Signal()

    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.setObjectName("ExperienceDock")
        self.setMinimumWidth(220)
        self.setMaximumWidth(360)
        self.setSizePolicy(QSizePolicy.Policy.Preferred, QSizePolicy.Policy.Expanding)

        root = QVBoxLayout(self)
        root.setContentsMargins(10, 10, 10, 10)
        root.setSpacing(8)

        title = QLabel("体验副驾驶")
        title.setStyleSheet("font-weight: 600; font-size: 13px;")
        root.addWidget(title)

        hint = QLabel("本地诊断 · 会话记忆仅内存")
        hint.setStyleSheet(f"color: {_pal('text_secondary')}; font-size: 11px;")
        root.addWidget(hint)

        sel_row = QHBoxLayout()
        self._selection_label = QLabel("未选中节点")
        self._selection_label.setWordWrap(True)
        self._selection_label.setStyleSheet(
            f"padding: 6px; border-radius: 6px; background: {_pal('bg_secondary')};"
        )
        sel_row.addWidget(self._selection_label, stretch=1)
        self._pin_btn = QPushButton("钉住")
        self._pin_btn.setToolTip("钉住当前选中，切换节点后仍保留在上下文中（最多 3）")
        self._pin_btn.setEnabled(False)
        self._pin_btn.clicked.connect(self.pin_toggled.emit)
        sel_row.addWidget(self._pin_btn)
        root.addLayout(sel_row)

        self._pinned_label = QLabel("")
        self._pinned_label.setWordWrap(True)
        self._pinned_label.setStyleSheet(
            f"color: {_pal('text_secondary')}; font-size: 11px;"
        )
        self._pinned_label.setVisible(False)
        root.addWidget(self._pinned_label)

        self._metrics = QLabel("打开课程后显示健康仪表")
        self._metrics.setWordWrap(True)
        self._metrics.setTextInteractionFlags(Qt.TextInteractionFlag.TextSelectableByMouse)
        root.addWidget(self._metrics)

        # M-07: author profile line + clear button (hidden when empty).
        profile_row = QHBoxLayout()
        profile_row.setSpacing(4)
        self._profile_label = QLabel("")
        self._profile_label.setWordWrap(True)
        self._profile_label.setStyleSheet(
            f"color: {_pal('text_secondary')}; font-size: 11px;"
        )
        self._profile_label.setVisible(False)
        profile_row.addWidget(self._profile_label, stretch=1)
        self._clear_profile_btn = QPushButton("清除画像")
        self._clear_profile_btn.setToolTip(
            "清除跨课风格提示与语言偏好（仅内存，不删课程文件）"
        )
        self._clear_profile_btn.setVisible(False)
        self._clear_profile_btn.clicked.connect(self.clear_profile_clicked.emit)
        profile_row.addWidget(self._clear_profile_btn)
        root.addLayout(profile_row)

        sep = QFrame()
        sep.setFrameShape(QFrame.Shape.HLine)
        sep.setStyleSheet(f"color: {_pal('border')};")
        root.addWidget(sep)

        sug_title = QLabel("建议（最多 3 条）")
        sug_title.setStyleSheet(f"color: {_pal('text_secondary')}; font-size: 11px;")
        root.addWidget(sug_title)

        self._sug_host = QWidget()
        self._sug_layout = QVBoxLayout(self._sug_host)
        self._sug_layout.setContentsMargins(0, 0, 0, 0)
        self._sug_layout.setSpacing(6)
        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setFrameShape(QFrame.Shape.NoFrame)
        scroll.setWidget(self._sug_host)
        root.addWidget(scroll, stretch=1)

        self._empty_sug = QLabel("暂无优先事项")
        self._empty_sug.setStyleSheet(f"color: {_pal('text_secondary')}; font-size: 12px;")
        self._sug_layout.addWidget(self._empty_sug)

        # E1.7 S-13: recent timeline
        tl_title = QLabel("最近")
        tl_title.setStyleSheet(f"color: {_pal('text_secondary')}; font-size: 11px;")
        root.addWidget(tl_title)
        self._tl_host = QWidget()
        self._tl_layout = QVBoxLayout(self._tl_host)
        self._tl_layout.setContentsMargins(0, 0, 0, 0)
        self._tl_layout.setSpacing(4)
        root.addWidget(self._tl_host)
        self._set_timeline([])

        self._footer = QLabel("点击建议将打开预览，确认后才修改课程")
        self._footer.setWordWrap(True)
        self._footer.setStyleSheet(f"color: {_pal('text_secondary')}; font-size: 10px;")
        root.addWidget(self._footer)

        self._ctx: ExperienceContext | None = None
        self._suggestion_payloads: list[dict[str, Any]] = []
        self._timeline_payloads: list[dict[str, Any]] = []
        self._suggestion_buttons: list[QPushButton] = []
        self._focused_suggestion: int | None = None
        self._metrics_base_style = (
            f"padding: 4px; border-radius: 6px; border: 1px solid transparent;"
        )
        self._metrics.setStyleSheet(self._metrics_base_style)
        self._pulse_timer = QTimer(self)
        self._pulse_timer.setSingleShot(True)
        self._pulse_timer.timeout.connect(self._end_metrics_pulse)

    def clear(self) -> None:
        self.apply_context(None)
        self._set_timeline([])

    def pulse_metrics(self) -> None:
        """O-05: brief highlight after AI apply re-validation refresh."""
        accent = _pal("accent")
        self._metrics.setStyleSheet(
            f"padding: 4px; border-radius: 6px; border: 1px solid {accent};"
            f" background: {_pal('bg_elevated')};"
        )
        self._pulse_timer.start(450)

    def _end_metrics_pulse(self) -> None:
        self._metrics.setStyleSheet(self._metrics_base_style)

    def apply_context(self, ctx: ExperienceContext | None) -> None:
        """Refresh metrics and selection/pin chrome from *ctx*."""
        self._ctx = ctx
        if ctx is None:
            self._selection_label.setText("未选中节点")
            self._pin_btn.setEnabled(False)
            self._pin_btn.setText("钉住")
            self._pinned_label.setVisible(False)
            self._metrics.setText("打开课程后显示健康仪表")
            self._set_suggestions([])
            return

        if ctx.selection is not None:
            sel = ctx.selection
            label = sel.label or sel.id
            self._selection_label.setText(f"选中 · {sel.kind} · {label}")
            self._pin_btn.setEnabled(True)
            pinned_keys = {(p.kind, p.id) for p in (ctx.pinned_refs or [])}
            if (sel.kind, sel.id) in pinned_keys:
                self._pin_btn.setText("取消钉住")
            else:
                self._pin_btn.setText("钉住")
        else:
            self._selection_label.setText("未选中节点")
            self._pin_btn.setEnabled(False)
            self._pin_btn.setText("钉住")

        if ctx.pinned_refs:
            parts = [
                f"{p.kind}:{p.label or p.id}" for p in ctx.pinned_refs[:3]
            ]
            self._pinned_label.setText("钉住 · " + " · ".join(parts))
            self._pinned_label.setVisible(True)
        else:
            self._pinned_label.setVisible(False)

        health = "健康" if ctx.healthy else "需关注"
        ph = int(ctx.hygiene.get("placeholder_count") or 0)
        nr = int(ctx.hygiene.get("needs_review_count") or 0)
        lines = [
            f"<b>{health}</b>",
            f"节 {ctx.section_count} · 单元 {ctx.unit_count} · 课 {ctx.lesson_count}",
            f"空课 {ctx.empty_lesson_count}",
            f"校验 错 {ctx.validate_error_count} / 警 {ctx.validate_warning_count}",
            f"资源 待补 {ph} · needs-review {nr}",
        ]
        if ctx.language:
            lines.append(
                f"语言 {ctx.language}"
                + (f" · {ctx.cefr_hint}" if ctx.cefr_hint else "")
            )
        # M-08: daily AI budget readout (usage_today.requests vs settings limit).
        budget_line = _budget_line(ctx)
        if budget_line:
            lines.append(budget_line)
        # S-07: surface active JobTray jobs when Context was rebuilt mid-flight.
        jobs = list(getattr(ctx, "active_jobs", None) or [])
        if jobs:
            labels = []
            for j in jobs[:3]:
                if isinstance(j, dict):
                    labels.append(str(j.get("label") or j.get("job_id") or "任务"))
                else:
                    labels.append(str(getattr(j, "label", j)))
            lines.append(f"进行中 {len(jobs)} · " + "；".join(labels))
        # E5/M3: workshop draft one-liner when authoring is in progress.
        try:
            from src.backend.experience.workshop_draft import format_workshop_draft_line

            wline = format_workshop_draft_line(getattr(ctx, "workshop_draft", None))
            if wline:
                lines.append(wline)
        except Exception:
            logger.debug("widgets/experience_dock.py:314 best-effort step failed", exc_info=True)
        # E4/M-01: attachment summary one-liner (closed shape; no raw content).
        try:
            from src.backend.experience.attachments import format_attachments_line

            aline = format_attachments_line(getattr(ctx, "attachments", None))
            if aline:
                lines.append(aline)
        except Exception:
            logger.debug("widgets/experience_dock.py:323 best-effort step failed", exc_info=True)
        # C-13: compact recent intents from SessionMemory.
        try:
            intents = list(getattr(ctx, "recent_intents", None) or [])
            if intents:
                last = intents[-1]
                if isinstance(last, dict):
                    aid = str(last.get("label") or last.get("action_id") or "")
                else:
                    aid = str(getattr(last, "label", None) or getattr(last, "action_id", "") or "")
                aid = _short(aid, 36)
                if aid:
                    lines.append(f"最近意图 · {aid}" + (f"（{len(intents)}）" if len(intents) > 1 else ""))
        except Exception:
            logger.debug("widgets/experience_dock.py:337 best-effort step failed", exc_info=True)
        # C-14: one compact metrics line (interception / apply / ambient / guard).
        mline = _metrics_line(getattr(ctx, "metrics", None))
        if mline:
            lines.append(f"<i>{mline}</i>")
        self._metrics.setText("<br/>".join(lines))

        # M-07: author profile summary + clear button visibility.
        try:
            from src.backend.experience.memory import format_author_profile_line

            pline = format_author_profile_line(getattr(ctx, "author_profile", None))
        except Exception:
            pline = ""
        if pline:
            self._profile_label.setText(pline)
            self._profile_label.setVisible(True)
            self._clear_profile_btn.setVisible(True)
        else:
            self._profile_label.setText("")
            self._profile_label.setVisible(False)
            self._clear_profile_btn.setVisible(False)

    def apply_suggestions(self, suggestions: list[dict[str, Any]]) -> None:
        self._set_suggestions(suggestions)

    def apply_context_and_suggestions(
        self,
        ctx: ExperienceContext | None,
        suggestions: list[dict[str, Any]] | None = None,
    ) -> None:
        self.apply_context(ctx)
        if suggestions is None and ctx is not None:
            from src.backend.experience import local_suggestions

            suggestions = local_suggestions(ctx, limit=3)
        self._set_suggestions(suggestions or [])

    def set_timeline(self, events: list[dict[str, Any]] | list[Any]) -> None:
        """Show up to 5 newest timeline events (dicts or TimelineEvent)."""
        rows: list[dict[str, Any]] = []
        for event in events or []:
            if hasattr(event, "to_dict"):
                rows.append(event.to_dict())
            elif isinstance(event, dict):
                rows.append(dict(event))
        self._set_timeline(rows[-5:])

    def _set_suggestions(self, suggestions: list[dict[str, Any]]) -> None:
        while self._sug_layout.count():
            item = self._sug_layout.takeAt(0)
            w = item.widget()
            if w is not None:
                w.deleteLater()

        self._suggestion_payloads = []
        self._suggestion_buttons = []
        self._focused_suggestion = None

        if not suggestions:
            empty = QLabel("暂无优先事项")
            empty.setStyleSheet(f"color: {_pal('text_secondary')}; font-size: 12px;")
            self._sug_layout.addWidget(empty)
            self._sug_layout.addStretch(1)
            return

        for idx, sug in enumerate(suggestions[:3]):
            title = str(sug.get("title") or sug.get("action_id") or "建议")
            btn = QPushButton(title)
            btn.setToolTip(
                f"{sug.get('action_id') or ''}\n教师模式: [ / ] 导航 · Enter 激活".strip()
            )
            btn.setCursor(Qt.CursorShape.PointingHandCursor)
            btn.setProperty("suggestion_idx", idx)
            btn.clicked.connect(self._on_suggestion_btn_clicked)
            self._sug_layout.addWidget(btn)
            self._suggestion_payloads.append(dict(sug))
            self._suggestion_buttons.append(btn)
        self._sug_layout.addStretch(1)
        self._apply_suggestion_focus_style()

    def _on_suggestion_btn_clicked(self) -> None:
        sender = self.sender()
        if not sender:
            return
        idx = sender.property("suggestion_idx")
        if idx is not None and 0 <= int(idx) < len(self._suggestion_payloads):
            self.suggestion_clicked.emit(self._suggestion_payloads[int(idx)])

    # --- R-04 suggestion keyboard navigation ----------------------------

    def suggestion_count(self) -> int:
        return len(self._suggestion_payloads)

    def focused_suggestion_index(self) -> int | None:
        return self._focused_suggestion

    def navigate_suggestions(self, delta: int) -> int | None:
        """Move keyboard focus among Dock suggestions; wraps. Returns index."""
        from src.teacher.keyboard import next_suggestion_index

        idx = next_suggestion_index(
            self._focused_suggestion, self.suggestion_count(), delta=delta
        )
        self._focused_suggestion = idx
        self._apply_suggestion_focus_style()
        return idx

    def activate_focused_suggestion(self) -> bool:
        """Emit suggestion_clicked for the focused row (or first if none)."""
        n = self.suggestion_count()
        if n <= 0:
            return False
        idx = self._focused_suggestion if self._focused_suggestion is not None else 0
        idx = max(0, min(n - 1, int(idx)))
        self._focused_suggestion = idx
        self._apply_suggestion_focus_style()
        self.suggestion_clicked.emit(dict(self._suggestion_payloads[idx]))
        return True

    def _apply_suggestion_focus_style(self) -> None:
        accent = _pal("accent")
        normal = (
            f"text-align: left; padding: 4px 8px; border-radius: 6px; "
            f"border: 1px solid {_pal('border')};"
        )
        focused = (
            f"text-align: left; padding: 4px 8px; border-radius: 6px; "
            f"border: 2px solid {accent}; background: {_pal('bg_elevated')};"
        )
        for i, btn in enumerate(self._suggestion_buttons):
            btn.setStyleSheet(
                focused if self._focused_suggestion == i else normal
            )

    def _set_timeline(self, events: list[dict[str, Any]]) -> None:
        while self._tl_layout.count():
            item = self._tl_layout.takeAt(0)
            w = item.widget()
            if w is not None:
                w.deleteLater()

        if not events:
            empty = QLabel("尚无 AI 操作记录")
            empty.setStyleSheet(f"color: {_pal('text_secondary')}; font-size: 11px;")
            self._tl_layout.addWidget(empty)
            return

        self._timeline_payloads = []
        # Newest last in data → show newest first in UI.
        for idx, event in enumerate(reversed(events[-5:])):
            summary = _short(str(event.get("summary") or event.get("kind") or "事件"))
            btn = QPushButton(summary)
            tip = str(event.get("undo_hint") or "Ctrl+Z 可撤销")
            if event.get("action_id"):
                tip = f"{event.get('action_id')} · {tip}"
            btn.setToolTip(tip)
            btn.setCursor(Qt.CursorShape.PointingHandCursor)
            btn.setStyleSheet("text-align: left; font-size: 11px;")
            btn.setProperty("timeline_idx", idx)
            btn.clicked.connect(self._on_timeline_btn_clicked)
            self._timeline_payloads.append(dict(event))
            self._tl_layout.addWidget(btn)

    def _on_timeline_btn_clicked(self) -> None:
        sender = self.sender()
        if not sender:
            return
        idx = sender.property("timeline_idx")
        if idx is not None and 0 <= int(idx) < len(self._timeline_payloads):
            self.timeline_clicked.emit(self._timeline_payloads[int(idx)])
