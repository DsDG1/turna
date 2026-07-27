"""Proactive Ambient engine (E2.0 / C-12).

Pure Python, no Qt. Turns ExperienceContext + local_suggestions into at most
one ambient proposal, honoring mute and archive. Never writes the course tree.
"""
from __future__ import annotations

from dataclasses import asdict, dataclass, field
from datetime import date, datetime, timezone
from typing import Any, Iterable, Mapping, Sequence

from src.backend.experience.context_bus import ExperienceContext, local_suggestions

# Mute levels persisted in settings (string values).
MUTE_OFF = "off"
MUTE_HOURS4 = "hours4"
MUTE_TODAY = "today"
MUTE_PERMANENT = "permanent"
MUTE_LEVELS = frozenset({MUTE_OFF, MUTE_HOURS4, MUTE_TODAY, MUTE_PERMANENT})


@dataclass(frozen=True)
class MuteState:
    """When Ambient should stay silent."""

    level: str = MUTE_OFF
    # ISO timestamp or empty; used for hours4 / today anchors.
    until_iso: str = ""
    set_on_date: str = ""  # YYYY-MM-DD for "today" mute

    def is_active(self, now: datetime | None = None) -> bool:
        """True when Ambient must not show proposals."""
        level = (self.level or MUTE_OFF).strip() or MUTE_OFF
        if level not in MUTE_LEVELS:
            level = MUTE_OFF
        if level == MUTE_OFF:
            return False
        if level == MUTE_PERMANENT:
            return True
        now = now or datetime.now(timezone.utc)
        if level == MUTE_TODAY:
            day = self.set_on_date or _date_str(now)
            return _date_str(now) == day
        if level == MUTE_HOURS4:
            if not self.until_iso:
                return False
            try:
                until = datetime.fromisoformat(self.until_iso)
                if until.tzinfo is None:
                    until = until.replace(tzinfo=timezone.utc)
                return now < until
            except ValueError:
                return False
        return False

    def to_dict(self) -> dict[str, str]:
        return {"level": self.level, "until_iso": self.until_iso, "set_on_date": self.set_on_date}

    @classmethod
    def from_dict(cls, data: Mapping[str, Any] | None) -> "MuteState":
        if not data:
            return cls()
        level = str(data.get("level") or MUTE_OFF)
        if level not in MUTE_LEVELS:
            level = MUTE_OFF
        return cls(
            level=level,
            until_iso=str(data.get("until_iso") or ""),
            set_on_date=str(data.get("set_on_date") or ""),
        )


def make_mute(
    level: str,
    *,
    now: datetime | None = None,
) -> MuteState:
    """Build a MuteState for the given level relative to *now*."""
    now = now or datetime.now(timezone.utc)
    level = (level or MUTE_OFF).strip() or MUTE_OFF
    if level not in MUTE_LEVELS:
        level = MUTE_OFF
    if level == MUTE_HOURS4:
        until = now.timestamp() + 4 * 3600
        until_dt = datetime.fromtimestamp(until, tz=timezone.utc)
        return MuteState(level=MUTE_HOURS4, until_iso=until_dt.isoformat(), set_on_date="")
    if level == MUTE_TODAY:
        return MuteState(level=MUTE_TODAY, until_iso="", set_on_date=_date_str(now))
    if level == MUTE_PERMANENT:
        return MuteState(level=MUTE_PERMANENT)
    return MuteState(level=MUTE_OFF)


@dataclass(frozen=True)
class AmbientProposal:
    """One proactive suggestion shown in the AmbientBanner."""

    id: str
    title: str
    body: str
    action_id: str
    scope: dict[str, Any] = field(default_factory=dict)
    priority: int = 99
    source: str = "local_suggestions"

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)

    @classmethod
    def from_dict(cls, data: Mapping[str, Any]) -> "AmbientProposal":
        return cls(
            id=str(data.get("id") or ""),
            title=str(data.get("title") or ""),
            body=str(data.get("body") or ""),
            action_id=str(data.get("action_id") or ""),
            scope=dict(data.get("scope") or {}),
            priority=int(data.get("priority") or 99),
            source=str(data.get("source") or "local_suggestions"),
        )


def proposal_id_for(action_id: str, scope: Mapping[str, Any] | None = None) -> str:
    """Stable id for archive filtering (not a secret)."""
    scope = scope or {}
    bits = [action_id]
    for key in ("section_id", "first_lesson_id", "error_count", "weak_count"):
        if key in scope and scope[key] not in (None, ""):
            bits.append(f"{key}={scope[key]}")
    return "|".join(bits)


def suggestion_to_proposal(sug: Mapping[str, Any]) -> AmbientProposal:
    action_id = str(sug.get("action_id") or "")
    scope = dict(sug.get("scope") or {})
    title = str(sug.get("title") or action_id or "建议")
    # priority may be 0 (P0) — do not use ``or 99`` which treats 0 as missing.
    raw_pri = sug.get("priority", 99)
    try:
        priority = int(raw_pri)  # type: ignore[arg-type]
    except (TypeError, ValueError):
        priority = 99
    body = _body_for(action_id, scope, title)
    return AmbientProposal(
        id=proposal_id_for(action_id, scope),
        title=title,
        body=body,
        action_id=action_id,
        scope=scope,
        priority=priority,
        source="local_suggestions",
    )


def evaluate_ambient_batch(
    ctx: ExperienceContext | None,
    *,
    mute: MuteState | Mapping[str, Any] | None = None,
    now: datetime | None = None,
    archived_ids: Iterable[str] | None = None,
    suggestions: Sequence[Mapping[str, Any]] | None = None,
    limit: int = 3,
    defer_store: Any = None,
) -> list[AmbientProposal]:
    """Return up to ``limit`` ambient proposals (A3 ① companion queue).

    Empty list when muted / no ctx / nothing to say. Proposals are deduped by
    stable id and sorted by priority (P0 first); archived ids are skipped.
    Never mutates *ctx*.

    ``defer_store`` (A3 ②, ``DeferStore | None``): when provided, cooled-down
    deferred proposals whose issue is still current are re-admitted as
    resurface candidates (tagged ``source="deferred_resurface"``). When None,
    legacy filter applies. Soft autopilot is **not** applied - only proposals.
    """
    if ctx is None:
        return []
    state = mute if isinstance(mute, MuteState) else MuteState.from_dict(mute)
    if state.is_active(now):
        return []

    archived = set(archived_ids or ())
    cap = max(0, int(limit))
    sugs = list(suggestions) if suggestions is not None else local_suggestions(ctx, limit=3)
    sugs.sort(key=lambda s: int(s.get("priority", 99)))

    # A3 ②: classify deferred ids - hidden while in cooldown, re-tagged when
    # cooled down (so a deferred proposal that is still current re-surfaces and
    # metrics can count it). Never raises.
    in_cooldown: set[str] = set()
    cooled_defer: set[str] = set()
    if defer_store is not None:
        try:
            for r in defer_store.records:
                if defer_store.is_cooled_down(r.proposal_id, now=now):
                    cooled_defer.add(r.proposal_id)
                else:
                    in_cooldown.add(r.proposal_id)
        except Exception:
            pass

    out: list[AmbientProposal] = []
    seen: set[str] = set()
    for sug in sugs:
        if len(out) >= cap:
            break
        if not isinstance(sug, Mapping):
            continue
        prop = suggestion_to_proposal(sug)
        if not prop.action_id or not prop.id:
            continue
        if prop.id in archived or prop.id in seen:
            continue
        if prop.id in in_cooldown:
            continue  # deferred, not yet cooled down -> hidden
        seen.add(prop.id)
        if prop.id in cooled_defer:
            # Re-surfaced after cooldown - keep its real priority, tag source
            # so metrics counts it as a resurface rather than a fresh show.
            prop = AmbientProposal(
                id=prop.id,
                title=prop.title,
                body=prop.body,
                action_id=prop.action_id,
                scope=prop.scope,
                priority=prop.priority,
                source="deferred_resurface",
            )
        out.append(prop)
    return out


def evaluate_ambient(
    ctx: ExperienceContext | None,
    *,
    mute: MuteState | Mapping[str, Any] | None = None,
    now: datetime | None = None,
    archived_ids: Iterable[str] | None = None,
    suggestions: Sequence[Mapping[str, Any]] | None = None,
) -> AmbientProposal | None:
    """Return at most one ambient proposal, or None when muted/nothing to say.

    Thin wrapper over :func:`evaluate_ambient_batch` (A3 ①) kept for backward
    compatibility - single-proposal call sites (tests, D3 adversarial,
    observer guard) are unchanged. Never mutates *ctx*.
    """
    batch = evaluate_ambient_batch(
        ctx,
        mute=mute,
        now=now,
        archived_ids=archived_ids,
        suggestions=suggestions,
        limit=1,
    )
    return batch[0] if batch else None


def _body_for(action_id: str, scope: Mapping[str, Any], title: str) -> str:
    if action_id == "validate.open_and_fix":
        n = scope.get("error_count", "")
        return f"检测到校验错误（{n}）。可一键进入批量修复预览，确认后才写入。"
    if action_id == "lesson.fill_empty":
        n = scope.get("empty_count", "")
        return f"有 {n} 节空课。可从第一节开始 AI 填充（预览确认，不进工坊亦可）。"
    if action_id == "resource.fill_stubs":
        return "词库存在待补 / needs-review。清待补会生成草稿，经 Diff 确认后合并。"
    if action_id == "quality.campaign_worst_n":
        sid = scope.get("section_id", "")
        return f"节 {sid} 质量偏低。可打开战役队列，逐课改善（需确认）。"
    return title


def _date_str(now: datetime) -> str:
    if now.tzinfo is None:
        return now.date().isoformat()
    return now.astimezone().date().isoformat()
