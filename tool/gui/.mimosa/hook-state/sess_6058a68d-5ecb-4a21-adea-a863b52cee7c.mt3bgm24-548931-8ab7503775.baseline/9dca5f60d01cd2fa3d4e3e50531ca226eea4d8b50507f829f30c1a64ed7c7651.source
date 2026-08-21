"""Session timeline for Experience Dock (E1.7 / S-13).

Pure Python ring buffer — memory only, no disk, no secrets.
Records human-visible AI/editor events so authors can re-locate scope
and remember to Ctrl+Z; it is **not** a second undo stack.
"""
from __future__ import annotations

import time
from collections import deque
from dataclasses import asdict, dataclass, field
from typing import Any, Iterable


@dataclass(frozen=True)
class TimelineEvent:
    """One row in the Experience recent list."""

    kind: str
    summary: str
    action_id: str = ""
    scope: dict[str, Any] = field(default_factory=dict)
    undo_hint: str = "Ctrl+Z 可撤销"
    ts: float = 0.0

    def to_dict(self) -> dict[str, Any]:
        d = asdict(self)
        return d


def make_event(
    kind: str,
    summary: str,
    *,
    action_id: str = "",
    scope: dict[str, Any] | None = None,
    undo_hint: str = "Ctrl+Z 可撤销",
    ts: float | None = None,
) -> TimelineEvent:
    return TimelineEvent(
        kind=kind,
        summary=summary,
        action_id=action_id or "",
        scope=dict(scope or {}),
        undo_hint=undo_hint,
        ts=float(time.time() if ts is None else ts),
    )


class ExperienceTimeline:
    """Bounded FIFO of recent experience events (newest last)."""

    def __init__(self, maxlen: int = 50) -> None:
        self._maxlen = max(1, int(maxlen))
        self._events: deque[TimelineEvent] = deque(maxlen=self._maxlen)

    def __len__(self) -> int:
        return len(self._events)

    def append(self, event: TimelineEvent | dict[str, Any]) -> TimelineEvent:
        if isinstance(event, dict):
            event = make_event(
                str(event.get("kind") or "event"),
                str(event.get("summary") or ""),
                action_id=str(event.get("action_id") or ""),
                scope=dict(event.get("scope") or {}),
                undo_hint=str(event.get("undo_hint") or "Ctrl+Z 可撤销"),
                ts=event.get("ts"),
            )
        self._events.append(event)
        return event

    def record(
        self,
        kind: str,
        summary: str,
        *,
        action_id: str = "",
        scope: dict[str, Any] | None = None,
        undo_hint: str = "Ctrl+Z 可撤销",
    ) -> TimelineEvent:
        return self.append(
            make_event(
                kind,
                summary,
                action_id=action_id,
                scope=scope,
                undo_hint=undo_hint,
            )
        )

    def recent(self, n: int = 5) -> list[TimelineEvent]:
        """Return up to ``n`` newest events (newest last)."""
        n = max(0, int(n))
        if n == 0:
            return []
        items = list(self._events)
        return items[-n:]

    def recent_dicts(self, n: int = 5) -> list[dict[str, Any]]:
        return [e.to_dict() for e in self.recent(n)]

    def replayable(self, n: int = 3) -> list[TimelineEvent]:
        """Events that carry an action_id suitable for palette re-run."""
        out: list[TimelineEvent] = []
        for event in reversed(self._events):
            if event.action_id and not event.action_id.startswith("app."):
                out.append(event)
            if len(out) >= n:
                break
        out.reverse()
        return out

    def clear(self) -> None:
        self._events.clear()

    def all(self) -> list[TimelineEvent]:
        return list(self._events)

    def extend(self, events: Iterable[TimelineEvent | dict[str, Any]]) -> None:
        for event in events:
            self.append(event)
