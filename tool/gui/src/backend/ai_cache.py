"""Optional in-process cache for AI JSON responses.

第三枪 批次① (P6-3). Pure-Python, no Qt dependency, fully unittestable.

Design:
- Cache key = ``sha256(model | serialised messages | response_format)``. The
  API key is deliberately NOT part of the key material (so a key rotation does
  not invalidate useful draft cache), and the cache never stores the API key
  or any headers - only the parsed JSON body returned by the model.
- In-memory LRU with a configurable ceiling (default 128 entries). When the
  optional ``disk_dir`` is supplied, every ``put`` also writes a JSON file
  named ``<hash>.json`` so the cache survives a process restart. Disk files
  contain ONLY the model response body.
- Thread-safe via a single ``threading.Lock``. The cache is intended for
  low-concurrency GUI use (a few parallel lesson-generation workers at most).
- ``enabled`` flag mirrors ``Settings.ai_cache_enabled``; when ``False`` the
  cache is a no-op (``get`` always returns ``None``, ``put`` is a no-op).
- ``stats()`` exposes ``hits``/``misses``/``entries`` for telemetry.

Security notes (per aiEnhance.md §1.3 #6 "密钥不落盘"):
- The cache file content is the model's JSON body only - no headers, no auth.
- The cache key is a SHA-256 hash; the pre-image (messages) is not stored.
- Disk persistence is opt-in via ``disk_dir``; in-memory only is the default.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import threading
from collections import OrderedDict
from pathlib import Path
from typing import Any

# Disk files are named ``<key>.json``; keys must stay SHA-256 hex digests so a
# future key-format change cannot escape ``disk_dir`` via path segments.
_KEY_PATTERN = re.compile(r"[0-9a-f]{64}")


def _stable_hash(model: str, messages: list[dict[str, Any]], response_format: dict | None) -> str:
    """Stable SHA-256 key for a (model, messages, response_format) triple.

    Messages are JSON-serialised with ``sort_keys=True`` and ``ensure_ascii=False``
    so reordering keys in a message dict does not invalidate the entry. The
    API key is intentionally excluded.
    """
    payload = json.dumps(
        {
            "m": (model or "").strip(),
            "msg": messages or [],
            "rf": response_format or None,
        },
        sort_keys=True,
        ensure_ascii=False,
        separators=(",", ":"),
    )
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


class AiCacheStats:
    """Snapshot of cache counters (immutable view for telemetry)."""

    __slots__ = ("hits", "misses", "entries", "disk_writes", "disk_errors")

    def __init__(
        self,
        *,
        hits: int = 0,
        misses: int = 0,
        entries: int = 0,
        disk_writes: int = 0,
        disk_errors: int = 0,
    ) -> None:
        self.hits = hits
        self.misses = misses
        self.entries = entries
        self.disk_writes = disk_writes
        self.disk_errors = disk_errors

    def as_dict(self) -> dict[str, int]:
        return {
            "hits": self.hits,
            "misses": self.misses,
            "entries": self.entries,
            "disk_writes": self.disk_writes,
            "disk_errors": self.disk_errors,
        }

    def __repr__(self) -> str:  # pragma: no cover - debug helper
        return (
            f"AiCacheStats(hits={self.hits}, misses={self.misses}, "
            f"entries={self.entries}, disk_writes={self.disk_writes}, "
            f"disk_errors={self.disk_errors})"
        )


class AiCache:
    """In-memory LRU cache of AI JSON responses, with optional disk mirror.

    Construction:
        ``AiCache(maxsize=128, disk_dir=None, enabled=True)``
    - ``maxsize``: in-memory LRU ceiling. ``0`` disables caching (``enabled`` is
      also forced to ``False``).
    - ``disk_dir``: optional directory for persistent cache files. Created if
      missing. ``None`` = memory-only.
    - ``enabled``: master toggle. When ``False``, ``get`` returns ``None`` and
      ``put`` is a no-op (counters still track misses).
    """

    def __init__(
        self,
        *,
        maxsize: int = 128,
        disk_dir: str | Path | None = None,
        enabled: bool = True,
    ) -> None:
        self._maxsize = max(0, int(maxsize))
        self._enabled = bool(enabled) and self._maxsize > 0
        self._mem: OrderedDict[str, dict[str, Any]] = OrderedDict()
        self._lock = threading.Lock()
        self._hits = 0
        self._misses = 0
        self._disk_writes = 0
        self._disk_errors = 0
        self._disk_dir: Path | None
        if disk_dir is not None and self._enabled:
            self._disk_dir = Path(disk_dir)
            self._disk_dir.mkdir(parents=True, exist_ok=True)
        else:
            self._disk_dir = None

    # --- configuration --------------------------------------------------
    @property
    def enabled(self) -> bool:
        return self._enabled

    def set_enabled(self, value: bool) -> None:
        """Toggle the cache at runtime. Disabling does NOT clear entries."""
        with self._lock:
            self._enabled = bool(value) and self._maxsize > 0

    @property
    def maxsize(self) -> int:
        return self._maxsize

    @property
    def disk_dir(self) -> Path | None:
        return self._disk_dir

    # --- core API -------------------------------------------------------
    @staticmethod
    def make_key(
        model: str,
        messages: list[dict[str, Any]],
        response_format: dict | None = None,
    ) -> str:
        """Public key helper (exposed for tests and telemetry)."""
        return _stable_hash(model, messages, response_format)

    def get(
        self,
        model: str,
        messages: list[dict[str, Any]],
        response_format: dict | None = None,
    ) -> dict[str, Any] | None:
        """Return the cached body or ``None`` on miss / when disabled."""
        if not self._enabled:
            with self._lock:
                self._misses += 1
            return None
        key = _stable_hash(model, messages, response_format)
        with self._lock:
            entry = self._mem.get(key)
            if entry is not None:
                self._mem.move_to_end(key)
                self._hits += 1
                return entry
        # Not in memory; try disk (outside the lock to minimise contention).
        if self._disk_dir is not None:
            disk_entry = self._load_from_disk(key)
            if disk_entry is not None:
                with self._lock:
                    # Re-check in case another thread populated memory.
                    if key in self._mem:
                        self._hits += 1
                        return self._mem[key]
                    self._put_locked(key, disk_entry)
                    self._hits += 1
                return disk_entry
        with self._lock:
            self._misses += 1
        return None

    def put(
        self,
        model: str,
        messages: list[dict[str, Any]],
        response_format: dict | None,
        value: dict[str, Any],
    ) -> None:
        """Store ``value`` under the cache key. No-op when disabled."""
        if not self._enabled or value is None:
            return
        key = _stable_hash(model, messages, response_format)
        with self._lock:
            self._put_locked(key, value)
        if self._disk_dir is not None:
            self._save_to_disk(key, value)

    def clear(self) -> None:
        """Drop all in-memory entries. Disk files are left untouched."""
        with self._lock:
            self._mem.clear()

    def clear_disk(self) -> None:
        """Remove every ``*.json`` cache file from ``disk_dir``.

        No-op when no ``disk_dir`` is configured. Best-effort: errors are
        counted in ``stats().disk_errors`` but not raised.
        """
        if self._disk_dir is None:
            return
        try:
            for f in self._disk_dir.glob("*.json"):
                try:
                    f.unlink()
                except OSError:
                    with self._lock:
                        self._disk_errors += 1
        except OSError:
            with self._lock:
                self._disk_errors += 1

    def stats(self) -> AiCacheStats:
        with self._lock:
            return AiCacheStats(
                hits=self._hits,
                misses=self._misses,
                entries=len(self._mem),
                disk_writes=self._disk_writes,
                disk_errors=self._disk_errors,
            )

    # --- internals ------------------------------------------------------
    def _put_locked(self, key: str, value: dict[str, Any]) -> None:
        """Insert/refresh an entry, evicting LRU when over capacity.

        Caller holds ``self._lock``.
        """
        self._mem[key] = value
        self._mem.move_to_end(key)
        while len(self._mem) > self._maxsize:
            self._mem.popitem(last=False)

    def _save_to_disk(self, key: str, value: dict[str, Any]) -> None:
        assert self._disk_dir is not None
        if not _KEY_PATTERN.fullmatch(key):
            raise ValueError(f"invalid cache key: {key!r}")
        target = self._disk_dir / f"{key}.json"
        tmp = self._disk_dir / f"{key}.json.tmp"
        try:
            with open(tmp, "w", encoding="utf-8") as f:
                json.dump(value, f, ensure_ascii=False, separators=(",", ":"))
                f.flush()
                os.fsync(f.fileno())
            os.replace(tmp, target)
            with self._lock:
                self._disk_writes += 1
        except OSError:
            with self._lock:
                self._disk_errors += 1
            # Best-effort cleanup of the temp file.
            try:
                if tmp.exists():
                    tmp.unlink()
            except OSError:
                pass

    def _load_from_disk(self, key: str) -> dict[str, Any] | None:
        if self._disk_dir is None:
            return None
        if not _KEY_PATTERN.fullmatch(key):
            raise ValueError(f"invalid cache key: {key!r}")
        path = self._disk_dir / f"{key}.json"
        try:
            with open(path, "r", encoding="utf-8") as f:
                data = json.load(f)
            if isinstance(data, dict):
                return data
        except (OSError, json.JSONDecodeError):
            with self._lock:
                self._disk_errors += 1
        return None


# Module-level singleton accessor. ``ai_generator`` calls ``get_default_cache``
# to fetch the shared cache bound to ``Settings.ai_cache_enabled``. The app
# shell (``src/app.py``) is responsible for calling ``set_default_cache`` on
# startup and whenever the user toggles the setting.
_default_cache: AiCache | None = None
_default_lock = threading.Lock()


def get_default_cache() -> AiCache | None:
    """Return the process-wide cache, or ``None`` if not configured."""
    global _default_cache
    with _default_lock:
        return _default_cache


def set_default_cache(cache: AiCache | None) -> None:
    """Install (or clear) the process-wide cache."""
    global _default_cache
    with _default_lock:
        _default_cache = cache
