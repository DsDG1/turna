"""Job tray — multi-job status strip (E0 shell + S-07 true queue).

Owns a pure :class:`JobRegistry` and paints a one-line summary for the
status bar. The label is click-aware and pops up a flyout (E5 slice) listing
each active job with a "定位" (locate) action. "取消" is intentionally a
no-op stub today — worker cancellation is cooperative per-AiRequestWorker
and not yet routed through the registry; the menu entry is shown disabled
with an explanatory tooltip rather than silently killing workers (§14.5.2).
"""
from __future__ import annotations

import logging
logger = logging.getLogger(__name__)


from typing import Any

from PySide6.QtCore import Qt, Signal
from PySide6.QtGui import QAction
from PySide6.QtWidgets import QLabel, QMenu, QVBoxLayout, QWidget

from src.backend.experience.job_registry import (
    JOB_KIND_AI,
    JOB_KIND_LOCAL,
    JOB_KIND_VALIDATE,
    LEGACY_JOB_ID,
    JobRegistry,
)
from src.theme import current_palette


class JobTray(QWidget):
    """Status-bar tray backed by a multi-job :class:`JobRegistry`."""

    # E5 slice: emitted when the user asks to locate a job's node.
    # Payload is the job_id (the owner resolves node_key via the registry).
    job_activated = Signal(str)
    # E5 slice: emitted when the user asks to cancel a job. Today this is
    # surfaced disabled in the flyout; the signal is reserved for when
    # cooperative worker cancellation is routed through the registry.
    job_cancel_requested = Signal(str)
    # Perf/P2: True when any AI-kind job is running; False when none remain.
    ai_busy_changed = Signal(bool)

    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.setObjectName("JobTray")
        layout = QVBoxLayout(self)
        layout.setContentsMargins(4, 2, 4, 2)
        self._label = QLabel("任务：空闲")
        self._label.setStyleSheet(
            f"color: {current_palette().get('text_secondary', '#888')}; font-size: 11px;"
        )
        # Click-aware label: a left click pops up the job flyout.
        self._label.setTextInteractionFlags(Qt.TextInteractionFlag.NoTextInteraction)
        self._label.mousePressEvent = self._on_label_clicked
        layout.addWidget(self._label)
        self._registry = JobRegistry()
        self._last_ai_busy: bool = False
        self._refresh_ui()

    # --- true queue API (S-07) -------------------------------------------

    @property
    def registry(self) -> JobRegistry:
        return self._registry

    def start_job(
        self,
        job_id: str,
        label: str,
        *,
        kind: str = JOB_KIND_AI,
        node_key: str = "",
    ) -> bool:
        ok = self._registry.start(
            job_id, label, kind=kind, node_key=node_key
        )
        self._refresh_ui()
        self._emit_ai_busy_if_changed()
        return ok

    def finish_job(self, job_id: str) -> bool:
        ok = self._registry.finish(job_id)
        self._refresh_ui()
        self._emit_ai_busy_if_changed()
        return ok

    def clear(self) -> None:
        """Drop all jobs (course close / emergency)."""
        self._registry.clear()
        self._refresh_ui()
        self._emit_ai_busy_if_changed()

    def _emit_ai_busy_if_changed(self) -> None:
        try:
            busy = bool(self.is_busy_ai())
            if busy == bool(getattr(self, "_last_ai_busy", False)):
                return
            self._last_ai_busy = busy
            self.ai_busy_changed.emit(busy)
        except Exception:
            logger.debug("widgets/job_tray.py:98 best-effort step failed", exc_info=True)

    def active_jobs(self) -> list[dict[str, Any]]:
        return self._registry.snapshots()

    def job_count(self) -> int:
        return self._registry.count()

    def is_busy(self) -> bool:
        return self._registry.is_busy()

    def is_busy_ai(self) -> bool:
        """True when at least one AI-kind job is running."""
        return self._registry.is_busy_ai()

    # --- legacy single-slot API (backward compatible) --------------------

    def set_busy(self, message: str, *, job_count: int = 1) -> None:
        """Legacy: register/update the single ``_legacy`` slot.

        ``job_count`` is ignored for the registry (real count is authoritative);
        kept for call-site compatibility.
        """
        _ = job_count
        self.start_job(LEGACY_JOB_ID, message or "进行中…", kind=JOB_KIND_LOCAL)

    def set_idle(self, *, all_jobs: bool = False) -> None:
        """Legacy: finish only the ``_legacy`` slot unless *all_jobs*."""
        if all_jobs:
            self.clear()
            return
        self.finish_job(LEGACY_JOB_ID)

    # --- UI --------------------------------------------------------------

    def _estimate_suffix(self, label: str) -> str:
        """O-03: '（约 N 分钟）' from per-label history, else ''."""
        ms = self._registry.avg_duration_ms(label)
        if ms is None:
            return ""
        minutes = max(1, round(ms / 60000))
        return f"（约 {minutes} 分钟）"

    def _refresh_ui(self) -> None:
        line = self._registry.summary_line()
        self._label.setText(line)
        jobs = self._registry.active()
        if not jobs:
            self._label.setToolTip("无后台任务（点击查看）")
            return
        tip_lines = [
            f"· [{j.kind}] {j.label}"
            + (f" ({j.node_key})" if j.node_key else "")
            + self._estimate_suffix(j.label)
            for j in jobs
        ]
        self._label.setToolTip("进行中（点击查看）：\n" + "\n".join(tip_lines))

    def emit_locate(self, job_id: str) -> None:
        """Emit :attr:`job_activated` for a flyout "定位" action. Test hook."""
        self.job_activated.emit(job_id)

    def _on_label_clicked(self, _event) -> None:
        """Pop up the job flyout (QMenu) listing active jobs with actions."""
        menu = QMenu(self)
        jobs = self._registry.active()
        if not jobs:
            empty = QAction("无任务", menu)
            empty.setEnabled(False)
            menu.addAction(empty)
        else:
            for job in jobs:
                title = f"[{job.kind}] {job.label}"
                if job.node_key:
                    title += f"  · {job.node_key}"
                title += self._estimate_suffix(job.label)
                head = QAction(title, menu)
                head.setEnabled(False)
                menu.addAction(head)

                loc = QAction("  定位此节点", menu)
                loc.setEnabled(bool(job.node_key))
                loc.setToolTip(
                    "在课程树定位此任务的目标节点"
                    if job.node_key
                    else "该任务无关联节点，无法定位"
                )
                # Capture job_id by value via default arg.
                loc.triggered.connect(
                    lambda _checked=False, jid=job.job_id: self.emit_locate(jid)
                )
                menu.addAction(loc)

                cancel = QAction("  取消", menu)
                # Cooperative cancellation is not yet routed here; surface as
                # disabled rather than silently killing workers.
                cancel.setEnabled(False)
                cancel.setToolTip("该任务暂不可取消（协作式取消待接）")
                menu.addAction(cancel)
                menu.addSeparator()
        menu.exec(self._label.mapToGlobal(self._label.rect().bottomLeft()))


# Re-export kinds for call sites that prefer importing from the widget.
__all__ = [
    "JobTray",
    "JOB_KIND_AI",
    "JOB_KIND_LOCAL",
    "JOB_KIND_VALIDATE",
    "LEGACY_JOB_ID",
]
