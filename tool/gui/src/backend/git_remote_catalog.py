"""Saved git remotes catalog.

A lightweight catalog of named git course remotes the user has connected to
before, persisted in QSettings as a JSON blob. Distinct from
``Settings.recent_repos`` (which tracks *opened course directories*) — this
tracks *git remote definitions* (name + URL + local clone dir + language code)
so the user can one-click reconnect without re-entering the URL each time.
"""
from __future__ import annotations

import json
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from typing import Any

from PySide6.QtCore import QSettings

_QSETTINGS_KEY = "git/saved_remotes"


@dataclass
class SavedRemote:
    """One saved git remote definition."""

    name: str
    url: str
    local_dir: str
    lang: str = ""
    last_synced_at: str = ""  # ISO 8601, empty if never synced

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "SavedRemote":
        return cls(
            name=str(data.get("name", "")),
            url=str(data.get("url", "")),
            local_dir=str(data.get("local_dir", "")),
            lang=str(data.get("lang", "")),
            last_synced_at=str(data.get("last_synced_at", "")),
        )


def load_remotes() -> list[SavedRemote]:
    """Load all saved remotes from QSettings."""
    qsettings = QSettings("Turna", "CourseEditor")
    raw = qsettings.value(_QSETTINGS_KEY, "[]")
    if not isinstance(raw, str):
        return []
    try:
        parsed = json.loads(raw)
        if not isinstance(parsed, list):
            return []
        return [
            SavedRemote.from_dict(item)
            for item in parsed
            if isinstance(item, dict) and item.get("name") and item.get("url")
        ]
    except Exception:
        return []


def save_remotes(remotes: list[SavedRemote]) -> None:
    """Persist the full list of saved remotes."""
    qsettings = QSettings("Turna", "CourseEditor")
    qsettings.setValue(
        _QSETTINGS_KEY,
        json.dumps([r.to_dict() for r in remotes], ensure_ascii=False),
    )


def add_remote(remote: SavedRemote) -> list[SavedRemote]:
    """Add or update (by name) a saved remote. Returns the new list."""
    remotes = load_remotes()
    remotes = [r for r in remotes if r.name != remote.name]
    remotes.append(remote)
    remotes.sort(key=lambda r: r.name.lower())
    save_remotes(remotes)
    return remotes


def remove_remote(name: str) -> list[SavedRemote]:
    """Remove a saved remote by name. Returns the new list."""
    remotes = [r for r in load_remotes() if r.name != name]
    save_remotes(remotes)
    return remotes


def update_remote(name: str, **changes: Any) -> list[SavedRemote]:
    """Update fields on a saved remote identified by ``name``.

    If ``name`` itself is changed via ``new_name``, the remote is renamed.
    Returns the new list.
    """
    remotes = load_remotes()
    new_name = changes.pop("new_name", None)
    for r in remotes:
        if r.name == name:
            if new_name:
                r.name = new_name
            for key, value in changes.items():
                if hasattr(r, key):
                    setattr(r, key, value)
            break
    remotes.sort(key=lambda r: r.name.lower())
    save_remotes(remotes)
    return remotes


def mark_synced(name: str) -> None:
    """Record that ``name`` was just synced (updates ``last_synced_at``)."""
    now = datetime.now(timezone.utc).isoformat()
    update_remote(name, last_synced_at=now)


def find_by_url(url: str) -> SavedRemote | None:
    """Return the saved remote matching ``url`` (or None)."""
    for r in load_remotes():
        if r.url == url:
            return r
    return None
