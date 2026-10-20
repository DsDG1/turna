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
import re
import sys
import traceback
from datetime import datetime, timezone, UTC
from pathlib import Path
from typing import Any

# Local imports must come after sys.path manipulation below.
_GUI_DIR = Path(__file__).resolve().parent.parent.parent
if str(_GUI_DIR) not in sys.path:
    sys.path.insert(0, str(_GUI_DIR))

from src.application.settings import app_data_dir
import logging
logger = logging.getLogger(__name__)

_LOG_DIR = app_data_dir()
_LOG_DIR.mkdir(parents=True, exist_ok=True)
_LOG_FILE = _LOG_DIR / "telemetry.log"

_RETENTION_DAYS = 7

# Size cap for a single log file. The handler rotates by *size* in addition to
# the daily rotation: a busy authoring session (AI generate / batch
# regenerate) can emit tens of thousands of events a day, and a day-only
# rotation let ``telemetry.log`` grow to hundreds of MB. That in turn made
# every full parse of the file (see ``usage_summary``) take seconds.
_MAX_LOG_BYTES = 8 * 1024 * 1024
# Rotated size-based backups kept per file (on top of the daily rotation).
_MAX_LOG_BACKUPS = 3


# ---------------------------------------------------------------------------
# T21: opt-out + path scrubbing
# ---------------------------------------------------------------------------
# Telemetry is a local-only JSONL log (never uploaded), but it recorded the
# user's absolute course paths, so the log identified both the user and the
# project on disk. Two mitigations:
#   1. ``telemetry_enabled`` (设置 ▸ 外观) lets the user turn recording off.
#   2. Every payload goes through scrub_payload(), which reduces an absolute
#      path to its basename and shortens the user-specific home prefix.

_TELEMETRY_ENABLED: bool | None = None  # None -> read Settings lazily


def set_telemetry_enabled(enabled: bool) -> None:
    """Force the telemetry switch for this process (used by the settings UI)."""
    global _TELEMETRY_ENABLED
    _TELEMETRY_ENABLED = bool(enabled)


def telemetry_is_enabled() -> bool:
    """Whether telemetry recording is currently enabled."""
    if _TELEMETRY_ENABLED is not None:
        return _TELEMETRY_ENABLED
    try:
        from src.application.settings import Settings

        return bool(Settings().telemetry_enabled)
    except Exception:
        # A broken settings layer must not silently disable diagnostics
        # forever; default to the shipped behaviour (on) and say so once.
        logger.debug(
            "infrastructure/telemetry.py:settings read failed, defaulting to on",
            exc_info=True,
        )
        return True


# Keys whose values are paths and therefore get basename-only treatment.
_PATH_KEYS = frozenset(
    {
        "path",
        "dir",
        "file",
        "course_dir",
        "lesson_path",
        "temp_path",
        "audio_path",
        "target",
        "course",
        "root",
    }
)

_MAX_PATH_DEPTH = 2


def _is_rooted(text: str) -> bool:
    """Platform-agnostic "starts at a root" check.

    ``Path.is_absolute()`` answers False for "/opt/x" on Windows, which would
    let POSIX-shaped absolute paths through unscrubbed. Judge the string.
    """
    t = text.replace("\\", "/")
    return t.startswith("/") or (len(t) > 1 and t[1] == ":")


#: C15: provider / SDK error messages sometimes echo the request's auth
#: header or key material verbatim. Mask the common secret shapes anywhere
#: in free text, before any path-shaped logic runs.
_SECRET_TEXT_PATTERN = re.compile(
    r"(?i)\b(?:"
    r"bearer\s+[A-Za-z0-9._~+/=-]{8,}"
    r"|sk-[A-Za-z0-9_-]{8,}"
    r"|api[_-]?key\s*[:=]\s*['\"]?[A-Za-z0-9._~+/=-]{8,}"
    r")"
)


def scrub_value(key: str, value: Any) -> Any:
    """Reduce one payload value to something that does not identify a file."""
    if isinstance(value, Path):
        return scrub_value(key, str(value))
    if isinstance(value, dict):
        # Recurse: a nested structure (metrics, scope blobs) reached the log
        # verbatim before this, so payload["outer"]["path"] was a way around
        # the whole scrubber.
        return {str(k): scrub_value(str(k), v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [scrub_value(key, v) for v in value]
    if isinstance(value, bool) or not isinstance(value, str):
        return value
    text = _SECRET_TEXT_PATTERN.sub("<redacted>", value)
    # Order matters: a remote URL also contains "/", so _looks_like_path would
    # claim it first and leave its query string untouched.
    lowered = text[:12].casefold()
    if key in _PATH_KEYS or lowered.startswith("file://") or _looks_like_path(text):
        if "://" in text and not lowered.startswith("file://"):
            # A remote URL has no local path to shorten; the only thing to
            # hide is a credential in its query. (Running the local-path pass
            # over it would eat the hostname as if it were a directory.)
            return _scrub_url_query(text)
        return _scrub_pathish(text)
    if "?" in text and "://" in text:
        text = _scrub_url_query(text)
    # Not a bare path, but prose can still carry one — an exception message
    # like "[Errno 2] No such file: '/home/bob/course.json'" would otherwise
    # write the whole path to the log. Scrub rooted tokens in place.
    scrubbed, n = _ROOTED_TOKEN.subn(_scrub_token_match, text)
    return scrubbed if n else text


# Query parameters whose values are credentials, not diagnostics.
_SECRET_QUERY_KEYS = frozenset(
    {
        "key",
        "api_key",
        "apikey",
        "access_token",
        "token",
        "auth",
        "authorization",
        "password",
        "secret",
        "sig",
        "signature",
    }
)


def _scrub_url_query(url: str) -> str:
    """Replace secret-looking query values with ``***``, keeping the URL."""
    try:
        base, sep, query = url.partition("?")
        if not sep or not query:
            return url
        kept: list[str] = []
        for chunk in query.split("&"):
            name, has_eq, _value = chunk.partition("=")
            if has_eq and name.strip().casefold() in _SECRET_QUERY_KEYS:
                kept.append(f"{name}=***")
            else:
                kept.append(chunk)
        return f"{base}?{'&'.join(kept)}"
    except Exception:
        # Never let scrubbing break a log line.
        return url


# A rooted path token inside a larger string: "/opt/x/y", "C:/Users/me", and
# their backslash forms. Stops at whitespace and at the quoting characters
# that usually delimit a path inside a message.
_ROOTED_TOKEN = re.compile(
    r"(?<![A-Za-z0-9])(?:[A-Za-z]:)?[/\\][^\s'\"<>|,;)\]}]*"
)


def _tail_parts(parts: list[str]) -> list[str]:
    """Pick the trailing components worth keeping, dropping user identity.

    Keeping the last two components is usually enough to say which project
    and file, but the component above them is frequently the user name
    ("/home/<user>/course.json", "C:/Users/<user>/notes.md"), so keeping
    two would keep exactly the thing we must not write. Drop a leading
    home-name segment (this machine's home, or anything under a "home" /
    "Users" root) before taking the tail.
    """
    home_name = Path.home().name.casefold()
    # A drive letter ("C:") is the first component of a Windows path; look
    # past it when deciding whether the next segment is a "home"/"Users" root.
    scan_from = 1 if parts and len(parts[0]) == 2 and parts[0][1] == ":" else 0
    if len(parts) > scan_from and parts[scan_from].casefold() in (
        "home",
        "users",
        "user",
    ):
        parts = parts[:scan_from] + parts[scan_from + 2 :]
    # Then drop this machine's user name wherever it appears, so a path that
    # does not start at the root still cannot reintroduce it in the tail.
    if home_name:
        parts = [p for p in parts if p.casefold() != home_name]
    return parts[-_MAX_PATH_DEPTH:]


def _scrub_token_match(match: re.Match[str]) -> str:
    """Reduce one embedded path token to its last two components."""
    token = match.group(0).replace("\\", "/")
    parts = [p for p in token.rstrip("/").split("/") if p]
    kept = _tail_parts(parts)
    if not kept:
        # C15: "/home/<user>" (and its Windows twin) scrubs down to nothing —
        # returning the original here wrote the user name into the log.
        return "<path>"
    if len(kept) >= len(parts):
        return match.group(0)
    sep = "\\" if "\\" in match.group(0) else "/"
    return sep + sep.join(kept)


def _scrub_pathish(text: str) -> str:
    """Strip the identifying parts of a path-shaped string."""
    normalized = text.replace("\\", "/")
    # A file:// URL carries the same local path as the bare form; reduce it
    # to its path part so the scheme cannot smuggle the path past us.
    for scheme in ("file://", "file:///"):
        if normalized.lower().startswith(scheme):
            normalized = normalized[len(scheme) :]
            text = text[len(scheme) :]
            break
    home_normalized = str(Path.home()).replace("\\", "/").rstrip("/")
    if (
        home_normalized
        and home_normalized != "/"
        and normalized.startswith(home_normalized)
    ):
        text = "~" + normalized[len(home_normalized) :]
        normalized = text
    if _is_rooted(normalized):
        # Keep the last _MAX_PATH_DEPTH components: enough to tell
        # "courses/turkish" from "courses/german", not enough to find it.
        parts = [p for p in normalized.rstrip("/").split("/") if p]
        kept = _tail_parts(parts)
        if not kept:
            # C15: a bare home path must degrade to a placeholder, not round-
            # trip the user name via the `or normalized` fallback.
            return "<path>"
        return "/".join(kept)
    if len(text) > 120:
        return text[:117] + "..."
    return text


def _looks_like_path(text: str) -> bool:
    """Does this string look like a path (so its tail should be reduced)?

    Being rooted is enough on its own: a string starting with "/" or a drive
    letter is a path, not prose — and Windows paths routinely contain spaces
    (``C:/Users/Alice Smith/...``), which an earlier space guard let through.
    The space / newline guard applies only to the non-rooted heuristic.
    """
    if len(text) < 4 or len(text) > 4096:
        return False
    if "\n" in text:
        return False
    if _is_rooted(text) or text.lower().startswith("file://"):
        return True
    if " " in text:
        return False
    return "/" in text or "\\" in text


def scrub_payload(payload: dict[str, Any]) -> dict[str, Any]:
    """Return *payload* with every value scrubbed. Never raises."""
    try:
        return {k: scrub_value(str(k), v) for k, v in payload.items()}
    except Exception:
        logger.debug("infrastructure/telemetry.py:scrub_payload failed", exc_info=True)
        return {}


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
        # Incremental-parse cursor for ``usage_summary``: (inode, byte
        # offset). The summary is recomputed on every UI refresh, and the
        # log can be tens of MB — re-reading and re-parsing it whole made
        # every tree navigation in the GUI slow. The cursor lets a refresh
        # parse only the bytes appended since the last one.
        self._usage_cursor: tuple[int, int] | None = None
        self._usage_cache: dict[str, dict[str, Any]] | None = None
        self._setup_handler()

    def _setup_handler(self) -> None:
        # Remove (and close) any existing handlers to avoid duplicates when re-initialized.
        for handler in list(self._logger.handlers):
            try:
                handler.close()
            except Exception:
                logger.debug("infrastructure/telemetry.py:_setup_handler best-effort step failed", exc_info=True)
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
                logger.debug("infrastructure/telemetry.py:close best-effort step failed", exc_info=True)
            self._logger.removeHandler(handler)

    @staticmethod
    def _now_iso() -> str:
        return datetime.now(UTC).isoformat()

    def _write(self, event: str, duration_ms: float | None, payload: dict[str, Any] | None, context: dict[str, Any] | None) -> None:
        # T21: honour the opt-out before doing any work at all.
        if not telemetry_is_enabled():
            return
        line = {
            "ts": self._now_iso(),
            "event": event,
        }
        if duration_ms is not None:
            line["duration_ms"] = round(duration_ms, 3)
        if payload:
            line["payload"] = scrub_payload(payload)
        if context:
            line["context"] = scrub_payload(context)
        try:
            self._rotate_if_oversized()
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
                except Exception:
                    logger.debug("infrastructure/telemetry.py:_write best-effort step failed", exc_info=True)

    def _rotate_if_oversized(self) -> None:
        """Roll the current log file over once it passes ``_MAX_LOG_BYTES``.

        ``TimedRotatingFileHandler`` only rotates by day, so a busy authoring
        session could grow one day-file to hundreds of MB — and every full
        parse of that file (see :meth:`usage_summary`) then took seconds on
        the GUI thread.

        The roll is done here, before the record is written, because the
        handler holds the file open; rotating underneath it would leave the
        handler writing to the old inode.
        """
        try:
            if not self._log_file.exists():
                return
            if self._log_file.stat().st_size < _MAX_LOG_BYTES:
                return
            # Shift existing size-backups down, then move the live file to
            # ``.1``. The handler reopens on the next write.
            for i in range(_MAX_LOG_BACKUPS - 1, 0, -1):
                src = self._log_file.with_name(self._log_file.name + f".{i}")
                dst = self._log_file.with_name(self._log_file.name + f".{i + 1}")
                if src.exists():
                    if dst.exists():
                        dst.unlink()
                    src.replace(dst)
            backup = self._log_file.with_name(self._log_file.name + ".1")
            if backup.exists():
                backup.unlink()
            self._log_file.replace(backup)
            # Force the handler to reopen the (now absent) live file.
            for handler in list(self._logger.handlers):
                if isinstance(handler, logging.handlers.TimedRotatingFileHandler):
                    handler.close()
        except Exception:
            logger.debug(
                "infrastructure/telemetry.py:_rotate_if_oversized "
                "best-effort step failed",
                exc_info=True,
            )

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
            # A10: format_exc() needs an *active* exception — in sys.excepthook
            # there is none, so it would record "NoneType: None". Prefer the
            # traceback carried by the exception object itself.
            if exc.__traceback__ is not None:
                tb_text = "".join(
                    traceback.format_exception(type(exc), exc, exc.__traceback__)
                )
            else:
                tb_text = traceback.format_exc()
            payload["traceback"] = tb_text.splitlines()
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
                logger.debug("telemetry: skip malformed log line", exc_info=True)
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

        Incremental: the log is parsed once and then only the bytes appended
        since the previous call. The summary is recomputed on every UI
        refresh (tree navigation included) and the log can reach tens of MB,
        so re-reading it whole made the GUI sluggish on long-lived
        sessions. The cursor resets automatically when the file is rotated
        (its inode changes) or truncated (the size shrinks).
        """
        today = datetime.now(UTC).date()
        if not self._log_file.exists():
            self._usage_cursor = None
            self._usage_cache = None
            return {
                "today": self._empty_usage_bucket(),
                "total": self._empty_usage_bucket(),
            }

        try:
            stat = self._log_file.stat()
        except OSError:
            return {
                "today": self._empty_usage_bucket(),
                "total": self._empty_usage_bucket(),
            }

        cursor = self._usage_cursor
        cache = self._usage_cache
        if since is not None:
            # An explicit time filter needs a full re-scan; the incremental
            # cursor only tracks "everything appended so far".
            cache = None
            cursor = None
        if cache is None or cursor is None:
            # First call: parse the whole file.
            cache = {
                "today": self._empty_usage_bucket(),
                "total": self._empty_usage_bucket(),
                "day": today.isoformat(),
            }
            start_offset = 0
        elif cursor[0] != stat.st_ino or stat.st_size < cursor[1]:
            # The file was rotated or truncated: start over.
            cache = {
                "today": self._empty_usage_bucket(),
                "total": self._empty_usage_bucket(),
                "day": today.isoformat(),
            }
            start_offset = 0
        else:
            start_offset = cursor[1]
            if cache.get("day") != today.isoformat():
                # A new UTC day: the "today" bucket must be rebuilt from
                # scratch, so fall back to a full parse.
                cache = {
                    "today": self._empty_usage_bucket(),
                    "total": self._empty_usage_bucket(),
                    "day": today.isoformat(),
                }
                start_offset = 0

        if start_offset >= stat.st_size:
            # Nothing new to parse.
            self._usage_cursor = (stat.st_ino, stat.st_size)
            self._usage_cache = cache
            return {
                "today": dict(cache["today"]),
                "total": dict(cache["total"]),
            }

        try:
            with self._log_file.open("r", encoding="utf-8") as f:
                f.seek(start_offset)
                chunk = f.read()
                end_offset = f.tell()
        except Exception:
            return {
                "today": dict(cache["today"]),
                "total": dict(cache["total"]),
            }

        # A partial trailing line means the writer was mid-append; stop at
        # the last complete line and leave the cursor there.
        last_nl = chunk.rfind("\n")
        if last_nl < 0:
            # No complete line yet — nothing to consume.
            self._usage_cursor = (stat.st_ino, start_offset)
            self._usage_cache = cache
            return {
                "today": dict(cache["today"]),
                "total": dict(cache["total"]),
            }
        complete = chunk[: last_nl + 1]
        end_offset = start_offset + len(complete.encode("utf-8"))

        buckets = {"today": cache["today"], "total": cache["total"]}
        for line in complete.splitlines():
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
                    logger.debug(
                        "infrastructure/telemetry.py:usage_summary "
                        "best-effort step failed",
                        exc_info=True,
                    )

            is_today = False
            try:
                record_date = datetime.fromisoformat(
                    ts.replace("Z", "+00:00")
                ).date()
                is_today = record_date == today
            except Exception:
                logger.debug("infrastructure/telemetry.py:usage_summary best-effort step failed", exc_info=True)

            model = payload.get("model", "")
            usage = payload.get("usage")
            if not isinstance(usage, dict):
                # A8: the producer (generator_worker_hub.on_worker_usage)
                # writes tokens flat on the payload; the nested ``usage`` dict
                # shape only exists in old records/tests. Accept both.
                usage = payload
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
                cost, currency = self._estimate_cost(payload, model)
                if cost is not None:
                    bucket["estimated_cost"] = (bucket.get("estimated_cost") or 0) + cost
                    bucket["currency"] = currency

        self._usage_cursor = (stat.st_ino, end_offset)
        self._usage_cache = cache
        return {
            "today": dict(buckets["today"]),
            "total": dict(buckets["total"]),
        }

    @staticmethod
    def _estimate_cost(
        payload: dict[str, Any], model: str
    ) -> tuple[float | None, str | None]:
        """Local cost estimate for one AI record. Never raises."""
        try:
            from src.backend import ai_presets

            usage = payload.get("usage")
            if not isinstance(usage, dict):
                usage = payload
            return ai_presets.estimate_cost(
                {
                    "prompt_tokens": int(usage.get("prompt_tokens", 0) or 0),
                    "completion_tokens": int(usage.get("completion_tokens", 0) or 0),
                },
                model,
            )
        except Exception:
            logger.debug(
                "infrastructure/telemetry.py:_estimate_cost best-effort step failed",
                exc_info=True,
            )
            return None, None

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
            logger.debug("infrastructure/telemetry.py:clear best-effort step failed", exc_info=True)
        # The incremental cursor points past the old content; drop it so the
        # next summary re-reads from the start.
        self._usage_cursor = None
        self._usage_cache = None


# Module singleton for production use.
telemetry = Telemetry()
