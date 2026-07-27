"""A3 ② DeferStore - persistent "稍后" cooldown + resurface (v4.66 P2).

Pure Python, no Qt / network. Stores deferred Ambient proposal ids with an
escalating cooldown so a deferred suggestion re-surfaces only after it cools
down AND its issue is still current. Never raises; records are a closed set
(``proposal_id`` is built from action_id + id/count scope bits by
``proactive.proposal_id_for`` - no title/body/raw content, §14.5.3 redaction).

Persistence mirrors ``proactive.MuteState``: the host keeps a DeferStore
instance session-resident and the app persists it via the
``experience_defer_json`` QSettings key.
"""
from __future__ import annotations

from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from typing import Any, Iterable, Mapping, Sequence

# Escalating cooldown (seconds): 15min -> 30min -> 60min -> permanent.
COOLDOWN_BASE = 15 * 60
MAX_DISMISS = 3  # >=3 defers -> permanent archive (no resurface).
STORE_CAP = 20  # FIFO cap on retained records.


@dataclass(frozen=True)
class DeferRecord:
    """One deferred proposal (closed-set, no raw content)."""

    proposal_id: str
    action_id: str
    deferred_at_iso: str
    re_surface_after_iso: str  # "" -> permanent (never resurface)
    dismiss_count: int = 1

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)

    @classmethod
    def from_dict(cls, data: Mapping[str, Any]) -> "DeferRecord":
        return cls(
            proposal_id=str(data.get("proposal_id") or ""),
            action_id=str(data.get("action_id") or ""),
            deferred_at_iso=str(data.get("deferred_at_iso") or ""),
            re_surface_after_iso=str(data.get("re_surface_after_iso") or ""),
            dismiss_count=int(data.get("dismiss_count") or 1),
        )


def _now(now: datetime | None) -> datetime:
    return now or datetime.now(timezone.utc)


def _iso(dt: datetime) -> str:
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.isoformat()


def _parse_iso(s: str) -> datetime | None:
    if not s:
        return None
    try:
        dt = datetime.fromisoformat(s)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt
    except ValueError:
        return None


class DeferStore:
    """Bounded list of DeferRecords with escalating cooldown resurface logic.

    All methods are total - they never raise on bad input.
    """

    def __init__(self, records: Iterable[DeferRecord] | None = None) -> None:
        self._records: list[DeferRecord] = []
        try:
            if records:
                for r in records:
                    if isinstance(r, DeferRecord) and r.proposal_id:
                        self._records.append(r)
        except Exception:
            self._records = []
        self._dedup()

    # --- access ---------------------------------------------------------

    @property
    def records(self) -> list[DeferRecord]:
        return list(self._records)

    def get(self, proposal_id: str) -> DeferRecord | None:
        pid = str(proposal_id or "")
        for r in self._records:
            if r.proposal_id == pid:
                return r
        return None

    def __len__(self) -> int:
        return len(self._records)

    # --- mutation -------------------------------------------------------

    def add(
        self,
        proposal_id: str,
        action_id: str = "",
        *,
        now: datetime | None = None,
    ) -> DeferRecord:
        """Defer (or re-defer) a proposal with escalating cooldown.

        Repeated defers of the same id bump ``dismiss_count`` and push the
        re-surface time out (15 -> 30 -> 60 min). At ``MAX_DISMISS`` the
        record is dropped from the store and a permanent marker (empty
        ``re_surface_after_iso``) is returned so the caller moves the id into
        session-level permanent archive. When ``action_id`` is empty, the
        existing record's action_id is reused (re-defer by id only).
        """
        pid = str(proposal_id or "")
        if not pid:
            return DeferRecord("", "", "", "", 0)
        now = _now(now)
        existing = self.get(pid)
        if existing and not action_id:
            action_id = existing.action_id
        dismiss = (existing.dismiss_count + 1) if existing else 1
        if dismiss >= MAX_DISMISS:
            # Escalate to permanent: drop from store; caller archives.
            self._records = [r for r in self._records if r.proposal_id != pid]
            return DeferRecord(
                proposal_id=pid,
                action_id=str(action_id or ""),
                deferred_at_iso=_iso(now),
                re_surface_after_iso="",
                dismiss_count=dismiss,
            )
        cooldown = COOLDOWN_BASE * (2 ** max(0, min(dismiss - 1, 3)))
        re_after = datetime.fromtimestamp(now.timestamp() + cooldown, tz=timezone.utc)
        record = DeferRecord(
            proposal_id=pid,
            action_id=str(action_id or ""),
            deferred_at_iso=_iso(now),
            re_surface_after_iso=_iso(re_after),
            dismiss_count=dismiss,
        )
        self._records = [r for r in self._records if r.proposal_id != pid]
        self._records.append(record)
        self._trim()
        return record

    def is_cooled_down(self, proposal_id: str, *, now: datetime | None = None) -> bool:
        rec = self.get(proposal_id)
        if rec is None or not rec.re_surface_after_iso:
            return False  # unknown or permanent -> not a resurface candidate
        dt = _parse_iso(rec.re_surface_after_iso)
        if dt is None:
            return False
        return _now(now) >= dt

    def should_permanent_archive(self, proposal_id: str) -> bool:
        rec = self.get(proposal_id)
        if rec is None:
            return False
        return rec.dismiss_count >= MAX_DISMISS or not rec.re_surface_after_iso

    def resurface_candidates(
        self,
        current_proposal_ids: Iterable[str],
        *,
        now: datetime | None = None,
    ) -> list[str]:
        """Ids that may re-surface: cooled down AND still in current suggestions."""
        try:
            current = {str(x) for x in (current_proposal_ids or []) if x}
        except Exception:
            current = set()
        out: list[str] = []
        for r in self._records:
            if r.proposal_id not in current:
                continue  # issue resolved -> do not resurface
            if self.is_cooled_down(r.proposal_id, now=now):
                out.append(r.proposal_id)
        return out

    def purge_resolved(self, current_proposal_ids: Iterable[str]) -> None:
        """Drop defers whose issue is no longer present (resolved)."""
        try:
            current = {str(x) for x in (current_proposal_ids or []) if x}
        except Exception:
            current = set()
        self._records = [r for r in self._records if r.proposal_id in current]

    # --- persistence ----------------------------------------------------

    def to_dict(self) -> dict[str, Any]:
        return {"records": [r.to_dict() for r in self._records]}

    @classmethod
    def from_dict(cls, data: Mapping[str, Any] | None) -> "DeferStore":
        if not data:
            return cls()
        raw = data.get("records") if isinstance(data, Mapping) else None
        records: list[DeferRecord] = []
        if isinstance(raw, Sequence):
            for item in raw:
                try:
                    if isinstance(item, Mapping):
                        records.append(DeferRecord.from_dict(item))
                except Exception:
                    continue
        return cls(records)

    # --- internals ------------------------------------------------------

    def _dedup(self) -> None:
        seen: set[str] = set()
        out: list[DeferRecord] = []
        for r in self._records:
            if r.proposal_id and r.proposal_id not in seen:
                seen.add(r.proposal_id)
                out.append(r)
        self._records = out
        self._trim()

    def _trim(self) -> None:
        if len(self._records) > STORE_CAP:
            self._records = self._records[-STORE_CAP:]
