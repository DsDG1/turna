"""Soft Autopilot — rule-safe limited auto-writes (E2.1+).

Pure Python, no Qt, no LLM. Default **off** at settings layer.

Whitelist only:
  - ``hygiene.trim_whitespace`` — strip term/translation/pronunciation ends
  - ``hygiene.collapse_repeated_spaces`` — fold internal runs of whitespace
    (≥2 spaces / tabs / newlines) into a single space; does not strip ends
  - ``hygiene.strip_surround_quotes`` — remove a single matched pair of
    surrounding quotes (``"`` / ``'`` / ``「」`` / ``『』``) when both ends pair
    and the inner content is non-empty; ignores escaped / unbalanced quotes
  - ``hygiene.drop_empty_tags`` — drop empty-string / non-string tags
  - ``hygiene.strip_zero_width`` — remove U+200B/U+FEFF/U+200C/U+200D (v4.62)

Never: Hard import, id changes, section merge, LLM calls.
"""
from __future__ import annotations

import re
from copy import deepcopy
from dataclasses import dataclass, field
from typing import Any, Iterable


# Fields eligible for trim on vocab / expression entries.
_TRIM_FIELDS = ("term", "translation", "pronunciation")
_RESOURCE_TYPES = ("vocab", "expressions")

# Surrounding quote pairs eligible for stripping. Each pair is (open, close).
_QUOTE_PAIRS = (('"', '"'), ("'", "'"), ("“", "”"), ("「", "」"), ("『", "』"))
_REPEATED_WS = re.compile(r"\s+")

# The closed set of rule_ids allowed in Soft. E1 gate G9 asserts every fix
# produced by evaluate_soft_fixes lives in this set, guarding against future
# semantic rules leaking into the whitelist.
SOFT_RULE_IDS = frozenset(
    {
        "hygiene.trim_whitespace",
        "hygiene.collapse_repeated_spaces",
        "hygiene.strip_surround_quotes",
        "hygiene.drop_empty_tags",
        "hygiene.strip_zero_width",
    }
)

# Zero-width / BOM characters safe to strip from resource text fields.
_ZERO_WIDTH_RE = re.compile("[\u200b\u200c\u200d\ufeff]")


@dataclass(frozen=True)
class SoftFix:
    """One atomic rule-safe fix description (does not mutate)."""

    rule_id: str
    row_type: str  # vocab | expressions
    entry_id: str
    field: str
    old_value: Any
    new_value: Any
    summary: str = ""


@dataclass
class SoftFixBatch:
    """Evaluated set of soft fixes for one pass."""

    fixes: list[SoftFix] = field(default_factory=list)

    def __len__(self) -> int:
        return len(self.fixes)

    def summaries(self, limit: int = 5) -> list[str]:
        out = [f.summary or f"{f.rule_id}:{f.entry_id}.{f.field}" for f in self.fixes]
        return out[:limit]


def summarize_soft_batch(batch: SoftFixBatch | None, *, limit: int = 8) -> str:
    """Human-readable multi-line summary for Soft preview skill (K-soft).

    Never raises. Empty batch → empty string.
    """
    try:
        if batch is None or not batch.fixes:
            return ""
        n = len(batch)
        lines = [f"将规则规范化 {n} 项（可撤销，零 LLM）："]
        for s in batch.summaries(limit=limit):
            lines.append(f"  · {s}")
        if n > limit:
            lines.append(f"  … 另有 {n - limit} 项")
        return "\n".join(lines)
    except Exception:
        return ""


def _entries(adapter: Any, row_type: str) -> list[dict[str, Any]]:
    if row_type == "vocab":
        return list(getattr(adapter, "vocab", None) or [])
    if row_type == "expressions":
        return list(getattr(adapter, "expressions", None) or [])
    return []


def _strip_zero_width(raw: str) -> str | None:
    """Remove zero-width / BOM chars. Returns new string or None if unchanged."""
    if not isinstance(raw, str) or not raw:
        return None
    cleaned = _ZERO_WIDTH_RE.sub("", raw)
    return cleaned if cleaned != raw else None


def _strip_surround_quotes(raw: str) -> str | None:
    """Return de-quoted value if *raw* is wrapped in a matched quote pair.

    Only acts when both ends form a known pair (see :data:`_QUOTE_PAIRS`) and
    the inner content is non-empty. Escaped quotes (a backslash before the
    opening quote, or a quote that also appears inside) are left alone.
    Returns the new value, or ``None`` when no change applies.
    """
    if len(raw) < 2:
        return None
    for opening, closing in _QUOTE_PAIRS:
        if raw.startswith(opening) and raw.endswith(closing):
            inner = raw[len(opening) : len(raw) - len(closing)]
            # Require non-empty inner and that the inner does not itself
            # contain the quote char (avoids stripping from "a"b" → a"b).
            if inner and opening not in inner and closing not in inner:
                # Skip when an escaped opening precedes the wrap.
                if len(raw) > len(opening) and raw[: len(opening)] == opening:
                    return inner
    return None


def evaluate_soft_fixes(adapter: Any) -> SoftFixBatch:
    """Scan adapter resources for whitelist hygiene issues. No mutation."""
    fixes: list[SoftFix] = []
    for row_type in _RESOURCE_TYPES:
        for entry in _entries(adapter, row_type):
            if not isinstance(entry, dict):
                continue
            eid = str(entry.get("id") or "")
            if not eid:
                continue
            for fld in _TRIM_FIELDS:
                if fld not in entry:
                    continue
                raw = entry.get(fld)
                if not isinstance(raw, str):
                    continue
                trimmed = raw.strip()
                if trimmed != raw:
                    fixes.append(
                        SoftFix(
                            rule_id="hygiene.trim_whitespace",
                            row_type=row_type,
                            entry_id=eid,
                            field=fld,
                            old_value=raw,
                            new_value=trimmed,
                            summary=f"trim {row_type}:{eid}.{fld}",
                        )
                    )
                # Collapse internal whitespace runs. Operates on the
                # end-trimmed value so that when trim_whitespace is also
                # present both rules converge on the same string regardless
                # of apply order. Fires only when the trimmed value still
                # contains an internal whitespace run.
                stripped_ws = raw.strip()
                collapsed = _REPEATED_WS.sub(" ", stripped_ws)
                if collapsed != stripped_ws:
                    fixes.append(
                        SoftFix(
                            rule_id="hygiene.collapse_repeated_spaces",
                            row_type=row_type,
                            entry_id=eid,
                            field=fld,
                            old_value=raw,
                            new_value=collapsed,
                            summary=f"collapse spaces {row_type}:{eid}.{fld}",
                        )
                    )
                dequoted = _strip_surround_quotes(raw)
                if dequoted is not None and dequoted != raw:
                    fixes.append(
                        SoftFix(
                            rule_id="hygiene.strip_surround_quotes",
                            row_type=row_type,
                            entry_id=eid,
                            field=fld,
                            old_value=raw,
                            new_value=dequoted,
                            summary=f"strip quotes {row_type}:{eid}.{fld}",
                        )
                    )
                zws = _strip_zero_width(raw)
                if zws is not None and zws != raw:
                    fixes.append(
                        SoftFix(
                            rule_id="hygiene.strip_zero_width",
                            row_type=row_type,
                            entry_id=eid,
                            field=fld,
                            old_value=raw,
                            new_value=zws,
                            summary=f"strip zero-width {row_type}:{eid}.{fld}",
                        )
                    )
            tags = entry.get("tags")
            if isinstance(tags, list) and any(
                (not isinstance(t, str)) or (isinstance(t, str) and not t.strip())
                for t in tags
            ):
                cleaned = [
                    t
                    for t in tags
                    if isinstance(t, str) and t.strip()
                ]
                if cleaned != tags:
                    fixes.append(
                        SoftFix(
                            rule_id="hygiene.drop_empty_tags",
                            row_type=row_type,
                            entry_id=eid,
                            field="tags",
                            old_value=list(tags),
                            new_value=cleaned,
                            summary=f"drop empty tags {row_type}:{eid}",
                        )
                    )
    return SoftFixBatch(fixes=fixes)


def apply_soft_fixes(
    adapter: Any,
    fixes: Iterable[SoftFix] | SoftFixBatch | None = None,
) -> SoftFixBatch:
    """Apply fixes in-place on adapter resource dicts.

    If *fixes* is None, evaluate first. Returns the batch that was applied.
    Does **not** call save / validate. Caller owns Undo / Timeline.
    """
    if fixes is None:
        batch = evaluate_soft_fixes(adapter)
    elif isinstance(fixes, SoftFixBatch):
        batch = fixes
    else:
        batch = SoftFixBatch(fixes=list(fixes))

    # Index entries by (row_type, id) for O(1) apply.
    index: dict[tuple[str, str], dict[str, Any]] = {}
    for row_type in _RESOURCE_TYPES:
        for entry in _entries(adapter, row_type):
            if isinstance(entry, dict) and entry.get("id"):
                index[(row_type, str(entry["id"]))] = entry

    for fix in batch.fixes:
        entry = index.get((fix.row_type, fix.entry_id))
        if entry is None:
            continue
        if fix.rule_id == "hygiene.trim_whitespace":
            if fix.field in entry and isinstance(entry.get(fix.field), str):
                entry[fix.field] = fix.new_value
        elif fix.rule_id == "hygiene.collapse_repeated_spaces":
            if fix.field in entry and isinstance(entry.get(fix.field), str):
                entry[fix.field] = fix.new_value
        elif fix.rule_id == "hygiene.strip_surround_quotes":
            if fix.field in entry and isinstance(entry.get(fix.field), str):
                entry[fix.field] = fix.new_value
        elif fix.rule_id == "hygiene.strip_zero_width":
            if fix.field in entry and isinstance(entry.get(fix.field), str):
                entry[fix.field] = fix.new_value
        elif fix.rule_id == "hygiene.drop_empty_tags":
            if "tags" in entry:
                entry["tags"] = list(fix.new_value)
    notify = getattr(adapter, "notify_resources_changed", None)
    if callable(notify) and batch.fixes:
        try:
            notify()
        except Exception:
            pass
    return batch


def snapshot_resources(adapter: Any) -> dict[str, list[dict[str, Any]]]:
    """Deep copy of vocab + expressions for undo."""
    return {
        "vocab": deepcopy(list(getattr(adapter, "vocab", None) or [])),
        "expressions": deepcopy(
            list(getattr(adapter, "expressions", None) or [])
        ),
    }


def restore_resources(adapter: Any, snap: dict[str, list[dict[str, Any]]]) -> None:
    """Restore vocab/expressions lists from :func:`snapshot_resources`."""
    if "vocab" in snap and hasattr(adapter, "vocab"):
        adapter.vocab = deepcopy(snap["vocab"])
    if "expressions" in snap and hasattr(adapter, "expressions"):
        adapter.expressions = deepcopy(snap["expressions"])
    notify = getattr(adapter, "notify_resources_changed", None)
    if callable(notify):
        try:
            notify()
        except Exception:
            pass
