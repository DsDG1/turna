"""Structured telemetry logging for the Turna GUI.

All monitoring events (startup, user actions, durations, errors) go through a
single logger so the rest of the GUI does not scatter ad-hoc logging calls.
Events are written as single-line JSON to ``~/.turna-gui/telemetry.log`` with
daily rotation and a 7-day retention. The legacy ``~/.varnamala-gui`` dir is
read for compatibility on first launch.
"""
from __future__ import annotations

import json
import logging
import logging.handlers
import sys
import traceback
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

# Local imports must come after sys.path manipulation below.
_GUI_DIR = Path(__file__).resolve().parent.parent.parent
if str(_GUI_DIR) not in sys.path:
    sys.path.insert(0, str(_GUI_DIR))

from src.application.settings import app_data_dir

_LOG_DIR = app_data_dir()
_LOG_DIR.mkdir(parents=True, exist_ok=True)
_LOG_FILE = _LOG_DIR / "telemetry.log"

_RETENTION_DAYS = 7


class Telemetry:
    """Structured event logger.

    The instance is created lazily on first import. Callers can use the module
    singleton ``telemetry`` or construct their own instance for tests.
    """

    def __init__(self, log_file: Path | None = None) -> None:
        self._log_file = Path(log_file) if log_file else _LOG_FILE
        self._log_file.parent.mkdir(parents=True, exist_ok=True)
        # Each instance gets its own logger so two Telemetry instances writing
        # to different files do not clobber each other's handlers.
        logger_name = f"turna.telemetry.{self._log_file.name}"
        self._logger = logging.getLogger(logger_name)
        self._logger.setLevel(logging.INFO)
        self._logger.propagate = False
        # Track whether we've already warned the user that telemetry writes
        # are failing, so a permanently-unwritable log (full disk, read-only
        # home) doesn't spam stderr on every event. (M10)
        self._write_failed_warned = False
        self._setup_handler()

    def _setup_handler(self) -> None:
        # Remove (and close) any existing handlers to avoid duplicates when re-initialized.
        for handler in list(self._logger.handlers):
            try:
                handler.close()
            except Exception:
                pass
            self._logger.removeHandler(handler)
        handler = logging.handlers.TimedRotatingFileHandler(
            self._log_file,
            when="midnight",
            interval=1,
            backupCount=_RETENTION_DAYS,
            encoding="utf-8",
            utc=True,
        )
        handler.setFormatter(logging.Formatter("%(message)s"))
        self._logger.addHandler(handler)

    def close(self) -> None:
        """Close the underlying file handler. Safe to call multiple times."""
        for handler in list(self._logger.handlers):
            try:
                handler.close()
            except Exception:
                pass
            self._logger.removeHandler(handler)

    @staticmethod
    def _now_iso() -> str:
        return datetime.now(timezone.utc).isoformat()

    def _write(self, event: str, duration_ms: float | None, payload: dict[str, Any] | None, context: dict[str, Any] | None) -> None:
        line = {
            "ts": self._now_iso(),
            "event": event,
        }
        if duration_ms is not None:
            line["duration_ms"] = round(duration_ms, 3)
        if payload:
            line["payload"] = payload
        if context:
            line["context"] = context
        try:
            self._logger.info(json.dumps(line, ensure_ascii=False, sort_keys=True))
        except Exception:
            # Telemetry must never crash the application, but a permanently
            # unwritable log (full disk, read-only home) would otherwise be
            # completely invisible. Emit one stderr warning the first time a
            # write fails so the user has a chance to notice and fix it.
            if not self._write_failed_warned:
                self._write_failed_warned = True
                try:
                    print(
                        f"[turna] warning: telemetry log write failed "
                        f"({self._log_file}); subsequent failures will be silent.",
                        file=sys.stderr,
                    )
                except Exception:  # noqa: BLE001 — even stderr can fail in CI
                    pass

    def start_session(self) -> None:
        """Record application/session start."""
        self.record_event("app.start", payload={"python": sys.version})

    def record_event(
        self,
        name: str,
        payload: dict[str, Any] | None = None,
        context: dict[str, Any] | None = None,
    ) -> None:
        """Record a discrete event with optional payload and context."""
        self._write(name, None, payload, context)

    def record_action(
        self,
        action: str,
        target: str,
        payload: dict[str, Any] | None = None,
        context: dict[str, Any] | None = None,
    ) -> None:
        """Record a low-level user action (click / input commit / window open...).

        The event name is prefixed with ``ui.`` so operation-log events are
        easy to distinguish from the curated high-level telemetry stream.
        ``target`` is folded into the payload as ``target``.
        """
        body = {"target": target}
        if payload:
            body.update(payload)
        self._write(f"ui.{action}", None, body, context)

    def record_duration(
        self,
        name: str,
        duration_ms: float,
        payload: dict[str, Any] | None = None,
        context: dict[str, Any] | None = None,
    ) -> None:
        """Record a timed operation."""
        self._write(name, duration_ms, payload, context)

    def recent_events(
        self,
        n: int = 500,
        event_prefix: str | None = None,
    ) -> list[dict[str, Any]]:
        """Return the last ``n`` decoded events (newest last).

        Optionally filter by event prefix (e.g. ``"ai."``, ``"ui."``).
        Falls back to an empty list if the log is missing or unreadable.
        Used by the operation-log settings tab to render a merged view.
        """
        try:
            if not self._log_file.exists():
                return []
            with self._log_file.open("r", encoding="utf-8") as f:
                lines = f.readlines()
        except Exception:
            return []

        events: list[dict[str, Any]] = []
        for line in lines:
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                continue
            if event_prefix is not None and not record.get("event", "").startswith(event_prefix):
                continue
            events.append(record)
        return events[-n:]

    def record_error(
        self,
        exc: BaseException | None = None,
        context: dict[str, Any] | None = None,
    ) -> None:
        """Record an exception with traceback summary."""
        payload: dict[str, Any] = {}
        if exc is not None:
            payload["exception"] = f"{type(exc).__name__}: {exc}"
            payload["traceback"] = traceback.format_exc().splitlines()
        self._write("app.error", None, payload, context)

    def recent_lines(self, n: int = 200) -> list[str]:
        """Return the last ``n`` lines from the telemetry log file.

        Used by the AI error analyzer as conversation context. Falls back to
        an empty list if the log is missing or unreadable.
        """
        try:
            if not self._log_file.exists():
                return []
            with self._log_file.open("r", encoding="utf-8") as f:
                return f.readlines()[-n:]
        except Exception:
            return []

    def record_experience_metrics(
        self,
        snapshot: dict[str, Any],
        reason: str = "manual",
        course_dir: Any = None,
    ) -> None:
        from src.backend.experience.metrics import course_attribution, export_snapshot

        exported = export_snapshot(snapshot)
        payload: dict[str, Any] = {
            "reason": reason,
            "metrics": exported if exported is not None else snapshot,
        }
        attr = course_attribution(course_dir)
        if attr:
            payload.update(attr)
        self.record_event("experience.metrics", payload=payload)

    def recent_experience_metrics(self, limit: int = 50) -> list[dict[str, Any]]:
        out: list[dict[str, Any]] = []
        for line in reversed(self.recent_lines(max(limit * 3, 100))):
            try:
                rec = json.loads(line)
                if rec.get("event") == "experience.metrics":
                    out.append(rec)
                    if len(out) >= limit:
                        break
            except Exception:
                continue
        return list(reversed(out))

    def usage_summary(
        self, since: datetime | None = None
    ) -> dict[str, dict[str, Any]]:
        """Parse the telemetry log and return AI usage aggregates.

        Returns ``{"today": {...}, "total": {...}}`` where each bucket contains
        ``requests``, ``success``, ``failure``, ``prompt_tokens``,
        ``completion_tokens``, ``total_tokens``, ``estimated_cost``,
        ``currency``.

        Token counts are read from ``duration_ms`` payloads (when available) or
        from ``usage`` events. Costs are estimated locally via the pricing table.
        """
        from src.backend import ai_presets

        today = datetime.now(timezone.utc).date()
        buckets = {
            "today": self._empty_usage_bucket(),
            "total": self._empty_usage_bucket(),
        }
        if not self._log_file.exists():
            return buckets

        try:
            with self._log_file.open("r", encoding="utf-8") as f:
                lines = f.readlines()
        except Exception:
            return buckets

        for line in lines:
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                continue
            event = record.get("event", "")
            if not event.startswith("ai."):
                continue
            payload = record.get("payload") or {}
            ts = record.get("ts", "")
            if since is not None:
                try:
                    record_dt = datetime.fromisoformat(ts.replace("Z", "+00:00"))
                    if record_dt < since:
                        continue
                except Exception:
                    pass

            is_today = False
            try:
                record_date = datetime.fromisoformat(
                    ts.replace("Z", "+00:00")
                ).date()
                is_today = record_date == today
            except Exception:
                pass

            model = payload.get("model", "")
            usage = payload.get("usage") or {}
            prompt = int(usage.get("prompt_tokens", 0) or 0)
            completion = int(usage.get("completion_tokens", 0) or 0)
            total = int(usage.get("total_tokens", 0) or 0)
            if total == 0:
                total = prompt + completion

            for bucket in (buckets["total"], buckets["today"] if is_today else None):
                if bucket is None:
                    continue
                bucket["requests"] += 1
                if payload.get("success", event.endswith(".done")):
                    bucket["success"] += 1
                elif event.endswith(".error") or payload.get("success") is False:
                    bucket["failure"] += 1
                bucket["prompt_tokens"] += prompt
                bucket["completion_tokens"] += completion
                bucket["total_tokens"] += total
                cost, currency = ai_presets.estimate_cost(
                    {"prompt_tokens": prompt, "completion_tokens": completion},
                    model,
                )
                if cost is not None:
                    bucket["estimated_cost"] = (bucket.get("estimated_cost") or 0) + cost
                    bucket["currency"] = currency

        return buckets

    @staticmethod
    def _empty_usage_bucket() -> dict[str, Any]:
        return {
            "requests": 0,
            "success": 0,
            "failure": 0,
            "prompt_tokens": 0,
            "completion_tokens": 0,
            "total_tokens": 0,
            "estimated_cost": None,
            "currency": "CNY",
        }

    def clear(self) -> None:
        """Truncate the telemetry log file. Safe to call multiple times."""
        try:
            self._log_file.write_text("", encoding="utf-8")
        except Exception:
            pass


# Module singleton for production use.
telemetry = Telemetry()
