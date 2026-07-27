"""ConflictGuard — serialize AI jobs per node (E2.0 / C-16).

Pure Python. Prevents two writers from targeting the same course node without
preview coordination. Not a full job queue (JobTray upgrade is later).
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Any


@dataclass(frozen=True)
class GuardHold:
    node_key: str
    job_id: str
    label: str = ""


class ConflictGuard:
    """Map node_key → active job. try_acquire fails if already busy."""

    def __init__(self) -> None:
        self._holds: dict[str, GuardHold] = {}

    def __len__(self) -> int:
        return len(self._holds)

    def is_busy(self, node_key: str) -> bool:
        return bool(node_key) and node_key in self._holds

    def holder(self, node_key: str) -> GuardHold | None:
        return self._holds.get(node_key)

    def try_acquire(
        self,
        node_key: str,
        job_id: str,
        *,
        label: str = "",
    ) -> bool:
        """Return True if acquired; False if another job holds the node."""
        key = str(node_key or "").strip()
        jid = str(job_id or "").strip()
        if not key or not jid:
            return False
        existing = self._holds.get(key)
        if existing is not None and existing.job_id != jid:
            return False
        self._holds[key] = GuardHold(node_key=key, job_id=jid, label=label or jid)
        return True

    def release(self, node_key: str, job_id: str | None = None) -> bool:
        """Release hold. If job_id given, only release matching holder."""
        key = str(node_key or "").strip()
        if not key or key not in self._holds:
            return False
        if job_id is not None and self._holds[key].job_id != job_id:
            return False
        del self._holds[key]
        return True

    def release_job(self, job_id: str) -> int:
        """Release all nodes held by *job_id*. Returns count released."""
        jid = str(job_id or "")
        keys = [k for k, h in self._holds.items() if h.job_id == jid]
        for k in keys:
            del self._holds[k]
        return len(keys)

    def clear(self) -> None:
        self._holds.clear()

    def holds(self) -> list[GuardHold]:
        """Snapshot of active holds (for FocusRing / JobTray)."""
        return list(self._holds.values())

    def busy_keys(self) -> list[str]:
        return list(self._holds.keys())

    def busy_summary(self) -> str:
        if not self._holds:
            return ""
        parts = [f"{h.node_key}（{h.label or h.job_id}）" for h in self._holds.values()]
        return "正在处理：" + "；".join(parts[:3])

    def status_line(self) -> str:
        return self.busy_summary() or "任务：无冲突"


def node_key(kind: str, node_id: str) -> str:
    """Canonical key for section/unit/lesson/item."""
    return f"{kind}:{node_id}"
