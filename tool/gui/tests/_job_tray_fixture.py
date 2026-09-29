"""Shared test double for the ``job_tray`` host attribute.

Handlers talk to the JobTray *widget* API (``start_job``/``finish_job``/
``is_busy_ai``), which wraps a backend ``JobRegistry``. Faking the host with a
bare ``JobRegistry`` silently re-opens the A1 API gap (registry has
``start``/``finish``), so dispatch tests must use this shim instead.
"""
from __future__ import annotations

from typing import Any

from src.backend.experience.job_registry import JobRegistry


class RegistryTray:
    """JobTray-shaped test double delegating to a real JobRegistry."""

    def __init__(self) -> None:
        self.registry = JobRegistry()

    def start_job(
        self, job_id: str, label: str, *, kind: str = "ai", **kwargs: Any
    ) -> bool:
        return self.registry.start(job_id, label, kind=kind, **kwargs)

    def finish_job(self, job_id: str) -> bool:
        return self.registry.finish(job_id)

    def clear(self) -> None:
        self.registry.clear()

    def is_busy(self) -> bool:
        return len(self.registry.active()) > 0

    def is_busy_ai(self) -> bool:
        return any(j.kind == "ai" for j in self.registry.active())
