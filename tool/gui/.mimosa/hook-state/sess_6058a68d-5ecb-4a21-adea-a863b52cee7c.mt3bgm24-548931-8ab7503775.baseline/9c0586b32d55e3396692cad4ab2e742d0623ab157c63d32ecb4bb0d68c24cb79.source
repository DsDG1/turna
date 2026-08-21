"""POS (part-of-speech) closed-set constants for vocab words (K-21 / v4.43).

Single source of truth for the GUI side. Flutter mirrors this in
``lib/domain/course/pos_tag.dart`` (enum PosTag) — the two closed sets must
stay aligned (a cross-stack test asserts identical names).

POS is **optional** everywhere: a vocab word may omit ``pos`` (old assets
and un-curated words). The closed set only constrains non-empty values so
that ``course_cli`` round-trips and the resource editor combo stay valid.
Pure Python, no Qt, never raises.
"""
from __future__ import annotations

from typing import Any

# Closed POS tag set (10 universal classes, Turkish-applicable).
POS_TAGS: tuple[str, ...] = (
    "noun",
    "verb",
    "adjective",
    "adverb",
    "pronoun",
    "preposition",
    "conjunction",
    "interjection",
    "numeral",
    "determiner",
)

POS_TAG_SET: frozenset[str] = frozenset(POS_TAGS)

# Short Chinese labels for the resource editor combo + confirmation dialog.
POS_LABELS: dict[str, str] = {
    "noun": "名词",
    "verb": "动词",
    "adjective": "形容词",
    "adverb": "副词",
    "pronoun": "代词",
    "preposition": "介词",
    "conjunction": "连词",
    "interjection": "叹词",
    "numeral": "数词",
    "determiner": "限定词",
}


def is_valid_pos(value: Any) -> bool:
    """True when *value* normalizes to a member of :data:`POS_TAG_SET`."""
    return normalize_pos(value) is not None


def normalize_pos(value: Any) -> str | None:
    """Normalize a POS value to a canonical closed-set member, else ``None``.

    Trims + lowercases; empty / non-string / out-of-set -> ``None``. Never raises.
    A valid ``pos`` is always one of :data:`POS_TAGS`; ``None`` means "unset".
    """
    try:
        if value is None:
            return None
        s = str(value).strip().lower()
        if not s or s not in POS_TAG_SET:
            return None
        return s
    except Exception:
        return None