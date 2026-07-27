"""ExperienceMetrics — in-process session counters for Experience OS (C-14).

Pure Python, no Qt. Tracks lightweight counters so the Dock / status bar can
surface observable ratios (intent interception M-09, suggestion apply rate,
Ambient shown/muted, ConflictGuard rejects, job counts, Soft outcomes).

红线 / invariants
------------------
- No Qt, no network, no disk in this module. Counters only — never alter the
  course tree, never gate a save, never change any judgment (``/why``,
  validate, etc.).
- **Writes never raise.** Mirrors the telemetry M10 invariant: a bad stage /
  kind / action_id is normalized or ignored, never propagated. Metrics must
  not crash the editor.
- In-memory counters live here. **C-15 persistence** (落盘 / 留存 / 会话归属)
  is owned by ``infrastructure.telemetry.record_experience_metrics``, which
  consumes :meth:`ExperienceMetrics.snapshot` plus the pure helpers below
  (``is_metrics_active``, ``course_attribution``, ``export_snapshot``).
  ``clear()`` still resets memory only; the owner (Shell / MainWindow)
  flushes via telemetry **before** clear on close-course / app-close.
- No external references held. ``action_id`` is recorded as a plain string
  key only if it normalizes to non-empty; we do not store suggestion dicts.

Counts are best-effort: a missed recording point degrades a ratio, never
breaks the editor. Prefer recording at the single funnel point to avoid
double-counting (see ``experienceai.md`` §12.1).
"""
from __future__ import annotations

import hashlib
from pathlib import Path
from typing import Any

from src.backend.experience.job_registry import (
    JOB_KIND_AI,
    JOB_KIND_LOCAL,
    JOB_KIND_VALIDATE,
)


# Closed stage vocabularies (mirrors the soft_autopilot whitelist discipline:
# explicit sets keep bad input out of the counter dicts).
_INTENT_STAGES: frozenset[str] = frozenset({"resolved", "fell_through"})
_SUGGESTION_STAGES: frozenset[str] = frozenset(
    {"shown", "accepted", "applied", "rejected"}
)
_AMBIENT_STAGES: frozenset[str] = frozenset(
    {"shown", "accepted", "muted", "dismissed", "deferred", "resurfaced"}
)
_GUARD_STAGES: frozenset[str] = frozenset({"rejected", "released"})
_JOB_STAGES: frozenset[str] = frozenset({"started", "finished", "failed"})
_SOFT_STAGES: frozenset[str] = frozenset({"evaluated", "applied", "skipped"})
# R2 immersive auto pipeline (closed set; no free-text).
_AUTO_STAGES: frozenset[str] = frozenset(
    {"scheduled", "applied", "failed", "invalidated"}
)
_JOB_KINDS: frozenset[str] = frozenset({JOB_KIND_LOCAL, JOB_KIND_AI, JOB_KIND_VALIDATE})


def _norm(value: Any) -> str:
    """Best-effort coerce to a non-empty stripped string; '' on any failure."""
    try:
        s = str(value or "").strip()
    except Exception:
        return ""
    return s


class ExperienceMetrics:
    """Mutable in-memory session counter.

    All ``inc_*`` methods are total — they never raise on bad input. Unknown
    stage / kind values are dropped silently (the counter stays consistent).
    """

    def __init__(self) -> None:
        self.clear()

    # --- intent (M-09 interception rate) ---------------------------------

    def inc_intent_resolved(self) -> None:
        self._intent["resolved"] += 1

    def inc_intent_fell_through(self) -> None:
        self._intent["fell_through"] += 1

    # --- suggestions -----------------------------------------------------

    def inc_suggestion(self, action_id: Any, stage: str) -> None:
        """Per-action suggestion stage counter.

        action_id is the dict key (normalized); unknown stage is dropped.
        ``shown`` is recorded per suggestion rendered; ``accepted`` at the
        single suggestion funnel; ``applied`` / ``rejected`` at the preview
        gate (see ``experienceai.md`` §9.1).
        """
        st = _norm(stage)
        if st not in _SUGGESTION_STAGES:
            return
        key = _norm(action_id) or "unknown"
        self._suggestion.setdefault(key, {})
        self._suggestion[key][st] = self._suggestion[key].get(st, 0) + 1

    # --- ambient --------------------------------------------------------

    def inc_ambient(self, stage: str) -> None:
        st = _norm(stage)
        if st not in _AMBIENT_STAGES:
            return
        self._ambient[st] += 1

    # --- ConflictGuard ---------------------------------------------------

    def inc_guard(self, stage: str) -> None:
        st = _norm(stage)
        if st not in _GUARD_STAGES:
            return
        self._guard[st] += 1

    # --- jobs ------------------------------------------------------------

    def inc_job(self, kind: str, stage: str) -> None:
        k = _norm(kind)
        if k not in _JOB_KINDS:
            return
        st = _norm(stage)
        if st not in _JOB_STAGES:
            return
        self._job.setdefault(k, {})
        self._job[k][st] = self._job[k].get(st, 0) + 1

    # --- soft autopilot --------------------------------------------------

    def inc_soft(self, stage: str) -> None:
        st = _norm(stage)
        if st not in _SOFT_STAGES:
            return
        self._soft[st] += 1

    # --- immersive auto (R2) ---------------------------------------------

    def inc_auto(self, stage: str) -> None:
        """Immersive auto-apply pipeline stage counter."""
        st = _norm(stage)
        if st not in _AUTO_STAGES:
            return
        self._auto[st] += 1

    # --- reads -----------------------------------------------------------

    def interception_rate(self) -> float | None:
        """resolved / (resolved + fell_through); None when denominator is 0."""
        r = self._intent["resolved"]
        f = self._intent["fell_through"]
        denom = r + f
        if denom <= 0:
            return None
        return r / denom

    def apply_rate(self) -> float | None:
        """applied / accepted across all suggestions; None when 0 accepted."""
        accepted = 0
        applied = 0
        for counts in self._suggestion.values():
            accepted += int(counts.get("accepted", 0))
            applied += int(counts.get("applied", 0))
        if accepted <= 0:
            return None
        return min(1.0, applied / accepted)

    def suggestion_totals(self) -> dict[str, int]:
        """Per-stage totals collapsed across all action_ids."""
        totals = {st: 0 for st in _SUGGESTION_STAGES}
        for counts in self._suggestion.values():
            for st in _SUGGESTION_STAGES:
                totals[st] += int(counts.get(st, 0))
        return totals

    def snapshot(self) -> dict[str, Any]:
        """Flat JSON-safe snapshot for Dock / status readout.

        Includes raw counters plus the two derived ratios. Ratios are null
        when their denominator is 0 (callers omit those segments).
        """
        sug_totals = self.suggestion_totals()
        ir = self.interception_rate()
        ar = self.apply_rate()
        return {
            "intent": dict(self._intent),
            "suggestion_by_action": {
                a: dict(c) for a, c in self._suggestion.items()
            },
            "suggestion_totals": sug_totals,
            "ambient": dict(self._ambient),
            "guard": dict(self._guard),
            "job": {k: dict(c) for k, c in self._job.items()},
            "soft": dict(self._soft),
            "auto": dict(self._auto),
            "interception_rate": (round(ir, 4) if ir is not None else None),
            "apply_rate": (round(ar, 4) if ar is not None else None),
        }

    # --- reset ----------------------------------------------------------

    def clear(self) -> None:
        self._intent: dict[str, int] = {"resolved": 0, "fell_through": 0}
        self._suggestion: dict[str, dict[str, int]] = {}
        self._ambient: dict[str, int] = {st: 0 for st in _AMBIENT_STAGES}
        self._guard: dict[str, int] = {st: 0 for st in _GUARD_STAGES}
        self._job: dict[str, dict[str, int]] = {}
        self._soft: dict[str, int] = {st: 0 for st in _SOFT_STAGES}
        self._auto: dict[str, int] = {st: 0 for st in _AUTO_STAGES}

    # --- convenience for tests / debugging ------------------------------

    def __len__(self) -> int:
        """Total non-zero counter cells (rough activity indicator)."""
        total = sum(self._intent.values()) + sum(self._ambient.values())
        total += sum(self._guard.values()) + sum(self._soft.values())
        total += sum(self._auto.values())
        for counts in self._suggestion.values():
            total += sum(counts.values())
        for counts in self._job.values():
            total += sum(counts.values())
        return total


# ---------------------------------------------------------------------------
# C-15 pure helpers (no IO) — used by telemetry.record_experience_metrics
# ---------------------------------------------------------------------------


def is_metrics_active(snapshot: Any) -> bool:
    """True when a metrics snapshot has at least one non-zero counter.

    Used to skip empty flushes (open → close with no Experience activity).
    Never raises.
    """
    try:
        if not isinstance(snapshot, dict):
            return False
        intent = snapshot.get("intent") or {}
        if any(int(intent.get(k) or 0) for k in ("resolved", "fell_through")):
            return True
        totals = snapshot.get("suggestion_totals") or {}
        if any(int(v or 0) for v in totals.values()):
            return True
        ambient = snapshot.get("ambient") or {}
        if any(int(v or 0) for v in ambient.values()):
            return True
        guard = snapshot.get("guard") or {}
        if any(int(v or 0) for v in guard.values()):
            return True
        soft = snapshot.get("soft") or {}
        if any(int(v or 0) for v in soft.values()):
            return True
        auto = snapshot.get("auto") or {}
        if any(int(v or 0) for v in auto.values()):
            return True
        jobs = snapshot.get("job") or {}
        for counts in jobs.values():
            if isinstance(counts, dict) and any(int(v or 0) for v in counts.values()):
                return True
        return False
    except Exception:
        return False


def course_attribution(course_dir: Any = None) -> dict[str, str]:
    """Privacy-friendly course attribution for telemetry (no full path).

    Returns ``{"course_name": basename, "course_key": sha256[:12]}`` or ``{}``.
    Never raises; never includes user home path segments.
    """
    try:
        if course_dir is None or course_dir == "":
            return {}
        path = Path(str(course_dir))
        name = path.name or ""
        try:
            resolved = str(path.resolve())
        except Exception:
            resolved = str(path)
        if not name and not resolved:
            return {}
        key = hashlib.sha256(resolved.encode("utf-8", errors="replace")).hexdigest()[:12]
        out: dict[str, str] = {"course_key": key}
        if name:
            out["course_name"] = name
        return out
    except Exception:
        return {}


def export_snapshot(snapshot: Any) -> dict[str, Any] | None:
    """Return a JSON-safe, closed-key copy of a metrics snapshot for export.

    Drops unknown top-level keys (defense in depth). Returns ``None`` when
    the input is unusable. Never raises; never includes secrets (snapshot
    itself never holds keys/prompts).
    """
    try:
        if not isinstance(snapshot, dict):
            return None
        allowed = (
            "intent",
            "suggestion_by_action",
            "suggestion_totals",
            "ambient",
            "guard",
            "job",
            "soft",
            "auto",
            "interception_rate",
            "apply_rate",
        )
        out: dict[str, Any] = {}
        for key in allowed:
            if key not in snapshot:
                continue
            val = snapshot[key]
            if key in ("interception_rate", "apply_rate"):
                if val is None:
                    out[key] = None
                else:
                    out[key] = float(val)
            elif isinstance(val, dict):
                # shallow copy nested dicts (suggestion_by_action / job)
                out[key] = {
                    str(k): (dict(v) if isinstance(v, dict) else v)
                    for k, v in val.items()
                }
            else:
                out[key] = val
        return out
    except Exception:
        return None


def usage_today_from_summary(summary: Any) -> dict[str, int]:
    """Map ``Telemetry.usage_summary()`` today/total bucket → int dict for Context.

    Aligns ExperienceContext.usage_today with ai_usage / telemetry aggregates.
    Never raises; never includes model names or prompts.
    """
    try:
        if not isinstance(summary, dict):
            return {}
        bucket = summary.get("today")
        if not isinstance(bucket, dict):
            bucket = summary
        keys = (
            "requests",
            "success",
            "failure",
            "prompt_tokens",
            "completion_tokens",
            "total_tokens",
        )
        out: dict[str, int] = {}
        for k in keys:
            try:
                out[k] = int(bucket.get(k) or 0)
            except Exception:
                out[k] = 0
        return out
    except Exception:
        return {}


def aggregate_interception_rate(events: Any) -> float | None:
    """Aggregate local intent interception rate across persisted metrics events (E4).

    Each event is a ``experience.metrics`` telemetry dict whose
    ``payload.metrics.intent`` carries ``{resolved, fell_through}`` counters.
    This sums those buckets across every supplied event and returns
    ``resolved / (resolved + fell_through)`` — the cross-event local
    interception rate the E4 gate samples against the ≥40% target.

    Never raises; returns ``None`` when the denominator is 0 (no usable
    intent data). Events missing the bucket contribute nothing.
    """
    resolved = 0
    fell = 0
    try:
        for ev in events or []:
            if not isinstance(ev, dict):
                continue
            payload = ev.get("payload")
            if not isinstance(payload, dict):
                continue
            metrics = payload.get("metrics")
            if not isinstance(metrics, dict):
                continue
            intent = metrics.get("intent")
            if not isinstance(intent, dict):
                continue
            try:
                resolved += int(intent.get("resolved") or 0)
                fell += int(intent.get("fell_through") or 0)
            except Exception:
                continue
    except Exception:
        return None
    denom = resolved + fell
    if denom <= 0:
        return None
    return resolved / denom