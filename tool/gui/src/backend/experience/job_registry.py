"""JobRegistry — multi-job active set for Experience JobTray (S-07).

Pure Python, no Qt. Tracks concurrent local / validate / AI jobs so the
status tray can show real counts instead of a single overwriteable busy flag.

Does **not** replace ConflictGuard (node write mutex) or QThread ownership.
"""
from __future__ import annotations

import time
from dataclasses import dataclass, field
from typing import Any, Iterable


# Canonical kinds for filtering (is_busy_ai, etc.).
JOB_KIND_LOCAL = "local"
JOB_KIND_AI = "ai"
JOB_KIND_VALIDATE = "validate"

# Legacy single-slot id used by JobTray.set_busy / set_idle compatibility.
LEGACY_JOB_ID = "_legacy"


@dataclass(frozen=True)
class JobRecord:
    """One active background / AI job."""

    job_id: str
    label: str
    kind: str = JOB_KIND_AI
    node_key: str = ""
    started_ts: float = 0.0

    def to_dict(self) -> dict[str, Any]:
        return {
            "job_id": self.job_id,
            "label": self.label,
            "kind": self.kind,
            "node_key": self.node_key,
            "started_ts": self.started_ts,
        }


@dataclass
class JobRegistry:
    """Ordered map of active jobs (insertion order preserved)."""

    _jobs: dict[str, JobRecord] = field(default_factory=dict)
    _order: list[str] = field(default_factory=list)
    # O-03 (v4.15): per-label finish durations (seconds, ring of last 20) for
    # "约 N 分钟" estimates. Session-memory only, survives clear() on purpose.
    _durations: dict[str, list[float]] = field(default_factory=dict)

    def __len__(self) -> int:
        return len(self._jobs)

    def count(self) -> int:
        return len(self._jobs)

    def clear(self) -> None:
        self._jobs.clear()
        self._order.clear()

    def start(
        self,
        job_id: str,
        label: str,
        *,
        kind: str = JOB_KIND_AI,
        node_key: str = "",
    ) -> bool:
        """Register or refresh a job. Empty id rejected. Returns True if ok."""
        jid = str(job_id or "").strip()
        if not jid:
            return False
        lab = str(label or jid).strip() or jid
        k = str(kind or JOB_KIND_AI).strip() or JOB_KIND_AI
        nk = str(node_key or "").strip()
        existing = self._jobs.get(jid)
        if existing is not None:
            # Idempotent refresh: keep original start time / order.
            self._jobs[jid] = JobRecord(
                job_id=jid,
                label=lab,
                kind=k,
                node_key=nk or existing.node_key,
                started_ts=existing.started_ts,
            )
            return True
        self._jobs[jid] = JobRecord(
            job_id=jid,
            label=lab,
            kind=k,
            node_key=nk,
            started_ts=time.time(),
        )
        self._order.append(jid)
        return True

    def finish(self, job_id: str) -> bool:
        """Remove one job. Returns True if it was present."""
        jid = str(job_id or "").strip()
        rec = self._jobs.get(jid)
        if rec is None:
            return False
        if rec.started_ts:
            hist = self._durations.setdefault(rec.label, [])
            hist.append(max(0.0, time.time() - rec.started_ts))
            del hist[:-20]
        del self._jobs[jid]
        self._order = [x for x in self._order if x != jid]
        return True

    def avg_duration_ms(self, label: str) -> int | None:
        """O-03: mean finish duration for *label* (ms); None without history."""
        hist = self._durations.get(str(label or ""))
        if not hist:
            return None
        return int(sum(hist) / len(hist) * 1000)

    def get(self, job_id: str) -> JobRecord | None:
        return self._jobs.get(str(job_id or "").strip())

    def active(self) -> list[JobRecord]:
        """Jobs in start order."""
        return [self._jobs[j] for j in self._order if j in self._jobs]

    def snapshots(self) -> list[dict[str, Any]]:
        """Context Bus / Dock friendly dicts."""
        return [r.to_dict() for r in self.active()]

    def is_busy(self, *, kinds: Iterable[str] | None = None) -> bool:
        if not self._jobs:
            return False
        if kinds is None:
            return True
        want = {str(k) for k in kinds}
        return any(r.kind in want for r in self._jobs.values())

    def is_busy_ai(self) -> bool:
        return self.is_busy(kinds=(JOB_KIND_AI,))

    def primary_label(self) -> str:
        """Newest job label (last started / refreshed in order)."""
        jobs = self.active()
        if not jobs:
            return ""
        return jobs[-1].label

    def summary_line(self, *, max_labels: int = 2) -> str:
        """Status-bar style line: idle or multi-job summary."""
        jobs = self.active()
        if not jobs:
            return "任务：空闲"
        n = len(jobs)
        labels = [j.label for j in jobs[-max_labels:]]
        # Show oldest of the tail first for reading order of recent pair.
        body = "；".join(labels)
        if n > max_labels:
            body = f"…；{body}" if max_labels else f"{n} 项"
        return f"任务：{body}（{n}）"
