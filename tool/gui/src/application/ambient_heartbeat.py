"""A3 Ambient Background Heartbeat Service & DeferStore Backfill.

Provides 15s background heartbeat for recalculating Ambient proposals and
handling silent DeferStore backfill when presence_level >= 2 (active/immersive/sovereign).
"""
from __future__ import annotations

import logging
from typing import Any, Optional

from PySide6.QtCore import QObject, QTimer

from src.backend.experience.policy import resolve_policy

logger = logging.getLogger("varnamala.ambient_heartbeat")


class AmbientHeartbeatService(QObject):
    """Background service for driving Ambient suggestions and DeferStore processing."""

    # Align with MainWindow / presence_drive HEARTBEAT_IDLE_INTERVAL_MS.
    HEARTBEAT_INTERVAL_MS = 15_000

    def __init__(self, host: Any, parent: Optional[QObject] = None) -> None:
        super().__init__(parent)
        self._host = host
        self._timer = QTimer(self)
        self._timer.setInterval(self.HEARTBEAT_INTERVAL_MS)
        self._timer.timeout.connect(self._on_heartbeat_tick)

    def start(self) -> None:
        """Start the background heartbeat timer."""
        if not self._timer.isActive():
            self._timer.start()
            logger.debug("AmbientHeartbeatService started.")

    def stop(self) -> None:
        """Stop the background heartbeat timer."""
        if self._timer.isActive():
            self._timer.stop()
            logger.debug("AmbientHeartbeatService stopped.")

    def _on_heartbeat_tick(self) -> None:
        """Executed every 15s tick."""
        if self._host is None:
            return
        try:
            settings = getattr(self._host, "_settings_obj", None)
            policy = resolve_policy(settings)
            if not getattr(policy, "allow_ambient_live", False):
                return

            # Trigger Ambient suggestions update on active/immersive/sovereign
            exp = getattr(self._host, "experience", None)
            if exp is not None and hasattr(exp, "refresh_ambient_proposals"):
                exp.refresh_ambient_proposals()

            # Process DeferStore backfill if enabled and level >= 3
            if getattr(policy, "allow_defer_resurface", False) and policy.presence_level >= 3:
                if exp is not None and hasattr(exp, "process_defer_backfill"):
                    exp.process_defer_backfill()

        except Exception as err:
            logger.warning("Error in AmbientHeartbeatService tick: %s", err)
