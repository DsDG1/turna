"""FocusRing — visual target roles for Experience (E2.1+ / C-17).

Pure Python, no Qt. Maps ``node_key`` (same shape as ConflictGuard) to a
display role so the course tree can paint busy / AI scope / pin without
changing selection semantics.

Roles are layered; higher priority wins when the same node has multiple:

  busy > ai_scope > pin > selection
"""
from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from typing import Iterable, Mapping


class FocusRole(str, Enum):
    """Display role for a course node in the FocusRing."""

    SELECTION = "selection"
    PIN = "pin"
    AI_SCOPE = "ai_scope"
    BUSY = "busy"


# Higher number = wins when merging multi-source roles for one node.
_ROLE_PRIORITY: dict[FocusRole, int] = {
    FocusRole.SELECTION: 1,
    FocusRole.PIN: 2,
    FocusRole.AI_SCOPE: 3,
    FocusRole.BUSY: 4,
}


@dataclass(frozen=True)
class FocusEntry:
    node_key: str
    role: FocusRole
    label: str = ""


class FocusRing:
    """Mutable set of focus entries keyed by node_key.

    Selection / pin are often bulk-replaced; busy / ai_scope are set per job.
    """

    def __init__(self) -> None:
        self._entries: dict[str, FocusEntry] = {}

    def __len__(self) -> int:
        return len(self._entries)

    def clear(self) -> None:
        self._entries.clear()

    def clear_roles(self, *roles: FocusRole) -> None:
        """Drop all entries whose role is in *roles*."""
        drop = set(roles)
        if not drop:
            return
        self._entries = {
            k: e for k, e in self._entries.items() if e.role not in drop
        }

    def set(
        self,
        node_key: str,
        role: FocusRole | str,
        *,
        label: str = "",
    ) -> None:
        """Set or upgrade role for *node_key* (higher priority wins)."""
        key = str(node_key or "").strip()
        if not key:
            return
        role_e = FocusRole(role) if not isinstance(role, FocusRole) else role
        existing = self._entries.get(key)
        if existing is not None:
            if _ROLE_PRIORITY.get(existing.role, 0) > _ROLE_PRIORITY.get(role_e, 0):
                return
        self._entries[key] = FocusEntry(
            node_key=key, role=role_e, label=label or ""
        )

    def set_many(
        self,
        keys: Iterable[str],
        role: FocusRole | str,
        *,
        label: str = "",
    ) -> None:
        for k in keys:
            self.set(k, role, label=label)

    def remove(self, node_key: str) -> bool:
        key = str(node_key or "").strip()
        if key in self._entries:
            del self._entries[key]
            return True
        return False

    def get(self, node_key: str) -> FocusEntry | None:
        return self._entries.get(str(node_key or "").strip())

    def role_of(self, node_key: str) -> FocusRole | None:
        entry = self.get(node_key)
        return entry.role if entry else None

    def entries(self) -> list[FocusEntry]:
        return list(self._entries.values())

    def as_role_map(self) -> dict[str, FocusRole]:
        """node_key → role (for tree apply_focus_ring)."""
        return {k: e.role for k, e in self._entries.items()}

    def as_id_role_map(self) -> dict[str, FocusRole]:
        """node_id (without kind prefix) → role for tree id index.

        When multiple kinds share the same id (unlikely), higher priority wins.
        Keys like ``lesson:l2`` yield id ``l2``.
        """
        out: dict[str, FocusRole] = {}
        pri: dict[str, int] = {}
        for key, entry in self._entries.items():
            nid = key.split(":", 1)[-1] if ":" in key else key
            p = _ROLE_PRIORITY.get(entry.role, 0)
            if p >= pri.get(nid, 0):
                out[nid] = entry.role
                pri[nid] = p
        return out

    def replace_from_sources(
        self,
        *,
        selection: str | None = None,
        pins: Iterable[str] | None = None,
        ai_scope: Iterable[str] | Mapping[str, str] | None = None,
        busy: Iterable[str] | Mapping[str, str] | None = None,
    ) -> None:
        """Rebuild ring from explicit sources (full replace)."""
        self._entries.clear()
        if selection:
            self.set(selection, FocusRole.SELECTION)
        for p in pins or ():
            self.set(p, FocusRole.PIN)
        if isinstance(ai_scope, Mapping):
            for k, lab in ai_scope.items():
                self.set(k, FocusRole.AI_SCOPE, label=str(lab or ""))
        else:
            for k in ai_scope or ():
                self.set(k, FocusRole.AI_SCOPE)
        if isinstance(busy, Mapping):
            for k, lab in busy.items():
                self.set(k, FocusRole.BUSY, label=str(lab or ""))
        else:
            for k in busy or ():
                self.set(k, FocusRole.BUSY)
