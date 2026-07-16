"""Dedicated low-level operation log.

Separate from ``telemetry.log``: the curated high-level telemetry stream
(session, startup, repo, AI durations, errors, usage) is low-frequency and
parsed line-by-line by ``Telemetry.usage_summary()`` on every refresh.
Per-click / per-input-commit events are high-frequency noise that would
bloat that parse and drown the signal, so they go to their own file. Both
are JSON-line logs written by the same ``Telemetry`` class.
"""
from __future__ import annotations

from src.infrastructure.telemetry import Telemetry, _LOG_DIR

# Module singleton mirroring ``telemetry`` but pointed at operations.log.
operations = Telemetry(_LOG_DIR / "operations.log")