"""Stub-entry selector for resource.fill_stubs_batch (pure Python, no Qt).

A "stub" (待补) resource entry is one that needs a second-pass AI fill:
tagged ``needs-review`` / ``auto-fix``, or carrying an empty / ``[待补]``
translation (vocab / expressions) or an empty ``explanation`` (grammarPoints).

This adapts the per-section rule in ``src/backend/ai/section_ops.py``
(``needs_review_entries``) to scan the adapter's **global** resource pools
(flat ``vocab`` / ``expressions`` / ``grammar_points`` lists) and returns
dicts shaped for ``resource_batch_skill.run_batch_polish``.

红线（experienceai.md §14.5.3）：
* 纯函数；无 Qt、不写树、不写盘、永不抛。
* term / translation 原文只在返回的 entry dict 中供 LLM prompt / 确认文案用，
  本模块自身不写 Context / Timeline / telemetry。
* grammar 排除默认（``include_grammar=False``）：POLISH_FIELDS 白名单无
  ``explanation``，v1 只覆盖 words/expressions。
"""
from __future__ import annotations

from typing import Any, Iterable

ACTION_ID = "resource.fill_stubs_batch"

# Tags that mark an entry as needing a second-pass fill.
STUB_TAGS: tuple[str, ...] = ("needs-review", "auto-fix")

# Placeholder marker used by the authoring pipeline (mirrors ai_bench).
PLACEHOLDER = "[待补]"


def _tags(entry: dict[str, Any]) -> set[str]:
    try:
        return {str(t).strip().lower() for t in (entry.get("tags") or [])}
    except Exception:
        return set()


def _has_stub_tag(tags: set[str]) -> bool:
    return any(t in tags for t in STUB_TAGS)


def is_stub_vocab_entry(entry: Any) -> bool:
    """True when a vocab / expressions entry is a stub. Never raises."""
    try:
        if not isinstance(entry, dict):
            return False
        if _has_stub_tag(_tags(entry)):
            return True
        return str(entry.get("translation") or "").strip() in ("", PLACEHOLDER)
    except Exception:
        return False


def is_stub_grammar_entry(entry: Any) -> bool:
    """True when a grammarPoints entry is a stub. Never raises."""
    try:
        if not isinstance(entry, dict):
            return False
        if _has_stub_tag(_tags(entry)):
            return True
        return str(entry.get("explanation") or "").strip() == ""
    except Exception:
        return False


def _shaped(entry: dict[str, Any], kind: str) -> dict[str, Any] | None:
    """Shape a live entry into the run_batch_polish input form; None if no id."""
    try:
        rid = str(entry.get("id") or "").strip()
        if not rid:
            return None
        return {
            "id": rid,
            "kind": kind,
            "term": str(entry.get("term") or entry.get("title") or ""),
            "translation": str(entry.get("translation") or ""),
            "pronunciation": str(entry.get("pronunciation") or ""),
            "pos": str(entry.get("pos") or "") if kind == "vocab" else "",
        }
    except Exception:
        return None


def select_stub_entries(
    vocab: Iterable[dict[str, Any]] | None,
    expressions: Iterable[dict[str, Any]] | None,
    grammar_points: Iterable[dict[str, Any]] | None = None,
    *,
    include_grammar: bool = False,
) -> list[dict[str, Any]]:
    """Scan the global resource pools and return stub entries.

    Returns run_batch_polish-shaped dicts (see ``_shaped``). grammarPoints are
    excluded unless ``include_grammar`` (v1 default off: the polish whitelist
    has no ``explanation``). Never raises.
    """
    out: list[dict[str, Any]] = []
    try:
        for entry in (vocab or []):
            if is_stub_vocab_entry(entry):
                shaped = _shaped(entry, "vocab")
                if shaped is not None:
                    out.append(shaped)
    except Exception:
        pass
    try:
        for entry in (expressions or []):
            if is_stub_vocab_entry(entry):
                shaped = _shaped(entry, "expressions")
                if shaped is not None:
                    out.append(shaped)
    except Exception:
        pass
    if include_grammar:
        try:
            for entry in (grammar_points or []):
                if is_stub_grammar_entry(entry):
                    shaped = _shaped(entry, "grammar")
                    if shaped is not None:
                        out.append(shaped)
        except Exception:
            pass
    return out


def without_stub_tags(entry: Any) -> list[str] | None:
    """Return ``entry``'s tags with stub tags removed (pure, no mutation).

    Returns ``None`` when there is nothing to strip (no list tags, or no stub
    tag present), so callers can skip building a no-op FieldPatch. The entry
    itself is left untouched — the caller snapshots old tags and writes the
    new list via a FieldPatch so the change is Undo-able. Never raises.
    """
    try:
        if not isinstance(entry, dict):
            return None
        tags = entry.get("tags")
        if not isinstance(tags, list):
            return None
        kept = [t for t in tags if str(t).strip().lower() not in STUB_TAGS]
        if len(kept) == len(tags):
            return None
        return kept
    except Exception:
        return None


def strip_stub_tags(entry: Any) -> bool:
    """Remove needs-review / auto-fix tags from ``entry`` in place.

    Returns True when the tags list changed. Prefer ``without_stub_tags`` when
    building an Undo-able FieldPatch (it does not mutate before the patch
    captures its old value). Never raises.
    """
    try:
        kept = without_stub_tags(entry)
        if kept is None:
            return False
        entry["tags"] = kept
        return True
    except Exception:
        return False
