"""Pure-Python answer grading, read-aloud scoring, and review-pool sampling.

Mirrors the Flutter app's runtime grading logic so the desktop preview grades
answers identically to the mobile app:
- ``fold_turkish`` mirrors ``lib/core/turkish_text.dart``
- ``normalize_course_answer`` / ``matches_course_answer`` mirror
  ``lib/core/course_answer.dart``
- ``score_read_aloud`` mirrors ``lib/core/read_aloud_scoring.dart``
- ``sample_review_pool`` mirrors ``ReviewPolicy`` weighted sampling (ADR 0071)

Zero Qt dependency so it is unit-testable headless and reusable across layers.
"""
from __future__ import annotations

import random
import re
from collections.abc import Iterable, Sequence
from dataclasses import dataclass
from typing import Any

_IGNORED_PUNCTUATION = frozenset(".,!?;:\"'’‘“”«»()[]{}…—–-")

K_READ_ALOUD_PASS_RATIO = 0.6

_NUMBER_TO_WORD: dict[str, str] = {
    "0": "sıfır",
    "1": "bir",
    "2": "iki",
    "3": "üç",
    "4": "dört",
    "5": "beş",
    "6": "altı",
    "7": "yedi",
    "8": "sekiz",
    "9": "dokuz",
    "10": "on",
}


def fold_turkish(value: str) -> str:
    """Turkish-aware folding for symmetric answer grading.

    Mirrors ``foldTurkish`` in ``lib/core/turkish_text.dart``:
    - strips combining diacritical marks (U+0300–U+036F)
    - folds ``İ``, ``I``, ``ı`` to plain ``i``
    - folds circumflex vowels ``â/Â`` -> ``a``, ``î/Î`` -> ``i``, ``û/Û`` -> ``u``
    - lowercases the result
    """
    out: list[str] = []
    for ch in value:
        code = ord(ch)
        if 0x0300 <= code <= 0x036F:
            continue
        if code in (0x0130, 0x0049, 0x0131):
            out.append("i")
            continue
        if code in (0x00C2, 0x00E2):
            out.append("a")
            continue
        if code in (0x00CE, 0x00EE):
            out.append("i")
            continue
        if code in (0x00DB, 0x00FB):
            out.append("u")
            continue
        out.append(ch)
    return "".join(out).lower()


def normalize_course_answer(value: str) -> str:
    """Normalize a typed answer for grading (mirrors ``normalizeCourseAnswer``)."""
    out: list[str] = []
    pending_space = False
    for ch in fold_turkish(value.strip()):
        if ch in _IGNORED_PUNCTUATION:
            continue
        if ch.isspace():
            pending_space = bool(out)
            continue
        if pending_space:
            out.append(" ")
        out.append(ch)
        pending_space = False
    return "".join(out)


def matches_course_answer(
    user_input: str,
    canonical: str,
    accepted_answers: Iterable[str] = (),
) -> bool:
    """Return True when ``user_input`` matches ``canonical`` or any accepted alternative."""
    normalized = normalize_course_answer(user_input)
    if not normalized:
        return False
    if normalize_course_answer(canonical) == normalized:
        return True
    return any(
        normalize_course_answer(str(ans)) == normalized
        for ans in accepted_answers
        if ans
    )


@dataclass(frozen=True)
class ReadAloudWordOutcome:
    word: str
    matched: bool
    heard: str | None


@dataclass(frozen=True)
class ReadAloudScore:
    ratio: float
    passed: bool
    words: tuple[ReadAloudWordOutcome, ...]


@dataclass(frozen=True)
class _ReadAloudToken:
    raw: str
    folded: str


def _is_word_rune(code: int) -> bool:
    return (
        (0x0041 <= code <= 0x005A)
        or (0x0061 <= code <= 0x007A)
        or (0x0030 <= code <= 0x0039)
        or (0x00C0 <= code <= 0x024F)
        or (0x1E00 <= code <= 0x1EFF)
        or code in (0x0027, 0x2019)
    )


def _normalize_folded(token: str) -> str:
    return fold_turkish(token).replace("'", "").replace("’", "")


def _tokenize_read_aloud(text: str) -> list[_ReadAloudToken]:
    cleaned = "".join(ch if _is_word_rune(ord(ch)) else " " for ch in text)
    return [
        _ReadAloudToken(raw=word, folded=_normalize_folded(word))
        for word in re.split(r"\s+", cleaned)
        if word
    ]


def _edit_distance_at_most_1(a: str, b: str) -> bool:
    if abs(len(a) - len(b)) > 1:
        return False
    i = j = edits = 0
    while i < len(a) and j < len(b):
        if a[i] == b[j]:
            i += 1
            j += 1
            continue
        edits += 1
        if edits > 1:
            return False
        if len(a) == len(b):
            i += 1
            j += 1
        elif len(a) < len(b):
            j += 1
        else:
            i += 1
    edits += (len(a) - i) + (len(b) - j)
    return edits <= 1


def matches_read_aloud_word(reference: str, heard: str) -> bool:
    """Fuzzy word-level equality mirroring ``matchesWord`` in ``read_aloud_scoring.dart``."""
    if reference == heard:
        return True
    if _NUMBER_TO_WORD.get(reference) == heard or _NUMBER_TO_WORD.get(heard) == reference:
        return True
    if len(reference) < 4 or len(heard) < 4:
        return False
    short, long = (reference, heard) if len(reference) <= len(heard) else (heard, reference)
    if long.startswith(short) and len(short) >= 4:
        return True
    return _edit_distance_at_most_1(reference, heard)


def score_read_aloud(reference: str, transcript: str) -> ReadAloudScore:
    """Score a read-aloud transcript against reference text using LCS alignment."""
    ref_words = _tokenize_read_aloud(reference)
    heard_words = _tokenize_read_aloud(transcript)

    n = len(ref_words)
    m = len(heard_words)
    dp = [[0] * (m + 1) for _ in range(n + 1)]
    for i in range(n - 1, -1, -1):
        for j in range(m - 1, -1, -1):
            skip = dp[i + 1][j] if dp[i + 1][j] > dp[i][j + 1] else dp[i][j + 1]
            pair = (
                1 + dp[i + 1][j + 1]
                if matches_read_aloud_word(ref_words[i].folded, heard_words[j].folded)
                else 0
            )
            dp[i][j] = pair if pair > skip else skip

    outcomes: list[ReadAloudWordOutcome] = []
    i = j = 0
    while i < n:
        if (
            j < m
            and matches_read_aloud_word(ref_words[i].folded, heard_words[j].folded)
            and 1 + dp[i + 1][j + 1] == dp[i][j]
        ):
            outcomes.append(
                ReadAloudWordOutcome(
                    word=ref_words[i].raw, matched=True, heard=heard_words[j].raw
                )
            )
            i += 1
            j += 1
        elif dp[i + 1][j] == dp[i][j]:
            outcomes.append(
                ReadAloudWordOutcome(word=ref_words[i].raw, matched=False, heard=None)
            )
            i += 1
        else:
            j += 1

    matched_count = sum(1 for w in outcomes if w.matched)
    ratio = 1.0 if n == 0 else matched_count / n
    return ReadAloudScore(
        ratio=ratio,
        passed=ratio >= K_READ_ALOUD_PASS_RATIO,
        words=tuple(outcomes),
    )


def sample_review_pool(
    items: Sequence[dict[str, Any]],
    review_policy: dict[str, Any] | None,
    *,
    seed: int | None = None,
) -> list[dict[str, Any]]:
    """Sample a subset of review-pool items according to ``review_policy``.

    Uses weighted sampling without replacement keyed by ``typeWeights``.
    """
    pool = list(items)
    if not pool or not isinstance(review_policy, dict):
        return pool
    rng = random.Random(seed)
    min_items = max(1, int(review_policy.get("minItems") or 1))
    max_items = max(min_items, int(review_policy.get("maxItems") or len(pool)))
    target = min(len(pool), rng.randint(min_items, max_items))
    raw_weights = review_policy.get("typeWeights") or {}

    remaining = list(pool)
    selected: list[dict[str, Any]] = []
    for _ in range(target):
        weights: list[float] = []
        for item in remaining:
            rt = str(item.get("runtimeType") or "")
            raw_w = raw_weights.get(rt, 1.0)
            try:
                w = float(raw_w)
            except (TypeError, ValueError):
                w = 1.0
            weights.append(w if w > 0 else 1.0)
        total = sum(weights)
        if total <= 0:
            idx = rng.randrange(len(remaining))
        else:
            pick = rng.uniform(0, total)
            acc = 0.0
            idx = len(remaining) - 1
            for cand_idx, w in enumerate(weights):
                acc += w
                if pick <= acc:
                    idx = cand_idx
                    break
        selected.append(remaining.pop(idx))
    return selected
