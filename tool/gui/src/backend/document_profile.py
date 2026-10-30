"""Detect what kind of teaching document a file is, and pick an import preset.

The textbook importer used to take the author's word for the document type
(general / grammar / dialogue / reading). Real projects mix a textbook, a
teaching syllabus (教学纲领 / ders izlencesi) and an exam outline in the same
folder, and picking the wrong extraction strategy silently produces the wrong
kind of knowledge points.

This module is the Qt-free seam for that decision:

- :func:`profile_document` is a deterministic keyword/structure heuristic. It
  always returns a usable profile, so the importer never blocks on the network.
- :func:`classify_document_with_ai` optionally asks the configured model to
  confirm or override the heuristic (JSON mode, tiny prompt). AI failures fall
  back to the heuristic instead of raising — classification is advisory.
- :func:`preset_for_profile` maps a profile to a ``TextbookPreset`` name.

Both layers return the same :class:`DocumentProfile`, so callers do not care
which one produced it.
"""
from __future__ import annotations

import json
from dataclasses import dataclass, field
from typing import Any
from collections.abc import Callable

from src.backend.ai.client import chat_json
from src.backend.ai.config import AiApiConfig, AiCancelled
from src.backend.ai.parse import extract_content, parse_json_obj
from src.backend.markdown_chopper import heading_style, plain_unit_titles
import logging

logger = logging.getLogger(__name__)

#: Kinds this module can detect. ``textbook`` is the neutral default.
DOCUMENT_KINDS: tuple[str, ...] = (
    "textbook",
    "grammar",
    "dialogue",
    "reading",
    "syllabus",
)

_KIND_LABELS = {
    "textbook": "教材",
    "grammar": "语法书",
    "dialogue": "对话书",
    "reading": "阅读材料",
    "syllabus": "教学纲领 / 课程大纲",
}

#: Keyword evidence per kind. Weights keep "教学目标" from being drowned out by
#: generic vocabulary in a long textbook.
_KEYWORDS: dict[str, tuple[tuple[str, float], ...]] = {
    "syllabus": (
        ("教学大纲", 3.0),
        ("教学纲领", 3.0),
        ("课程大纲", 3.0),
        ("课程标准", 3.0),
        ("教学目标", 2.5),
        ("学习目标", 2.5),
        ("课程目标", 2.5),
        ("单元目标", 1.5),
        ("考核", 1.5),
        ("学时", 1.5),
        ("学分", 1.5),
        ("课程安排", 2.0),
        ("syllabus", 3.0),
        ("curriculum", 2.0),
        ("learning outcome", 2.5),
        ("learning outcomes", 2.5),
        ("can-do", 2.0),
        ("assessment", 1.5),
        ("ders izlencesi", 3.0),
        ("öğrenme çıktısı", 2.5),
        ("ünite hedefleri", 2.0),
        ("haftalık", 1.0),
    ),
    "grammar": (
        ("语法", 2.0),
        ("时态", 2.0),
        ("变位", 2.5),
        ("词法", 2.0),
        ("句法", 2.0),
        ("grammar", 2.0),
        ("conjugation", 2.5),
        ("declension", 2.0),
        ("çekim", 2.0),
        ("ekler", 1.5),
    ),
    "dialogue": (
        ("对话", 2.0),
        ("diyalog", 2.0),
        ("情景会话", 2.5),
        ("口语", 1.5),
        ("dialogue", 2.0),
        ("conversation", 1.5),
    ),
    "reading": (
        ("阅读", 2.0),
        ("短文", 1.5),
        ("阅读材料", 2.5),
        ("reading passage", 2.0),
        ("okuma", 1.5),
    ),
}

#: Cap on the text handed to the classifier model — enough to see structure.
_MAX_CLASSIFY_CHARS = 6000

_SYSTEM = (
    "You classify language-teaching documents. "
    "You output ONLY valid JSON, no prose, no markdown fences."
)


@dataclass(frozen=True)
class DocumentProfile:
    """What kind of document this is, with the evidence behind the decision.

    - ``kind``: one of :data:`DOCUMENT_KINDS`.
    - ``preset``: suggested ``TextbookPreset`` machine name.
    - ``confidence``: 0..1; below ~0.45 the caller should keep the user's choice.
    - ``evidence``: short human-readable reasons, shown in the import log.
    - ``unit_count``: how many chapters/units the splitter found.
    - ``heading_style``: ``atx`` / ``unit`` / ``numbered`` / ``bold`` / ``none``.
    - ``source``: ``"heuristic"`` or ``"ai"`` — which layer produced it.
    """

    kind: str
    preset: str
    confidence: float
    evidence: tuple[str, ...] = ()
    unit_count: int = 0
    heading_style: str = "none"
    source: str = "heuristic"

    @property
    def label(self) -> str:
        return _KIND_LABELS.get(self.kind, self.kind)


def _count_keywords(low_text: str) -> dict[str, float]:
    scores: dict[str, float] = {}
    for kind, keywords in _KEYWORDS.items():
        score = 0.0
        for word, weight in keywords:
            occurrences = low_text.count(word)
            if occurrences:
                # Diminishing returns: a repeated phrase is not 20x evidence.
                score += weight * min(occurrences, 3) / (1 + 0.25 * (occurrences - 1))
        scores[kind] = score
    return scores


def _is_speaker_line(line: str) -> bool:
    """True when ``line`` starts like a dialogue turn (``A:`` / ``—`` / ``-``)."""
    stripped = line.strip()
    if not stripped:
        return False
    if stripped[:2].upper() in ("A:", "B:", "A-", "B-"):
        return True
    return stripped[0] in ("—", "–", "…")


def _structural_signals(text: str, style: str, units: int) -> dict[str, float]:
    """Structure-based nudges that keyword counts cannot see."""
    scores: dict[str, float] = {kind: 0.0 for kind in DOCUMENT_KINDS}
    lines = [line for line in text.splitlines() if line.strip()]
    if not lines:
        return scores
    # Ordered lists with short entries read like an outline, not a textbook.
    bullet_lines = sum(
        1 for line in lines if line.lstrip()[:2] in ("- ", "* ") or line.lstrip()[:1].isdigit()
    )
    bullet_ratio = bullet_lines / len(lines)
    if bullet_ratio > 0.45:
        scores["syllabus"] += 1.5
    # Dialogue scripts repeat a speaker marker at line starts ("A:", "B:",
    # an em dash) and keep lines short.
    speaker_lines = sum(
        1
        for line in lines
        if len(line) < 120 and _is_speaker_line(line)
    )
    if speaker_lines >= 8:
        scores["dialogue"] += 2.0
    # Long paragraphs with few list markers read like reading material.
    paragraphs = [p for p in text.split("\n\n") if len(p.strip()) > 120]
    if paragraphs and bullet_ratio < 0.15:
        avg = sum(len(p) for p in paragraphs) / len(paragraphs)
        if avg > 260:
            scores["reading"] += 1.5
    # A numbered/unit ladder with many units is outline-shaped.
    if style in ("numbered", "unit") and units >= 4:
        scores["syllabus"] += 1.0
    return scores


def profile_document(text: str) -> DocumentProfile:
    """Classify ``text`` with the deterministic heuristic.

    Always returns a profile. When nothing matches, the result is ``textbook``
    with low confidence so the caller keeps whatever the author picked.
    """
    body = text or ""
    style = heading_style(body)
    units = len(plain_unit_titles(body))
    low = body.lower()
    keyword_scores = _count_keywords(low)
    structure_scores = _structural_signals(body, style, units)
    combined = {
        kind: keyword_scores.get(kind, 0.0) + structure_scores.get(kind, 0.0)
        for kind in DOCUMENT_KINDS
    }
    best_kind = max(combined, key=lambda k: combined[k])
    best = combined[best_kind]
    total = sum(combined.values())

    evidence: list[str] = []
    for kind in sorted(combined, key=lambda k: combined[k], reverse=True):
        if combined[kind] <= 0:
            continue
        evidence.append(f"{_KIND_LABELS.get(kind, kind)}：{combined[kind]:.1f}")
        if len(evidence) >= 3:
            break
    if style != "none":
        evidence.append(f"标题形态：{style}（{units} 个单元）")

    if best <= 0:
        return DocumentProfile(
            kind="textbook",
            preset="general",
            confidence=0.3,
            evidence=tuple(evidence) or ("未命中类型关键词，按通用教材处理。",),
            unit_count=units,
            heading_style=style,
        )

    confidence = best / total if total else 0.3
    # A one-horse race is trustworthy; a photo finish is not.
    confidence = max(0.35, min(0.95, 0.45 + 0.5 * confidence))
    return DocumentProfile(
        kind=best_kind,
        preset=preset_for_profile_kind(best_kind),
        confidence=confidence,
        evidence=tuple(evidence),
        unit_count=units,
        heading_style=style,
        source="heuristic",
    )


def preset_for_profile_kind(kind: str) -> str:
    """Map a detected kind to a ``TextbookPreset`` name (never raises)."""
    from src.backend.textbook_presets import preset_for_kind

    return preset_for_kind(kind).name


def build_classify_messages(
    language: str,
    source_language: str,
    text: str,
    *,
    max_chars: int = _MAX_CLASSIFY_CHARS,
) -> list[dict[str, str]]:
    """Build the [system, user] messages for the AI document classifier."""
    excerpt = (text or "")[:max_chars]
    user = "\n".join(
        [
            "Classify the teaching document below into exactly one kind:",
            "- textbook: a coursebook chapter with vocabulary, texts and exercises",
            "- grammar: a grammar reference (rules, tables, conjugation)",
            "- dialogue: a phrasebook / dialogue collection",
            "- reading: long reading passages, few exercises",
            "- syllabus: a teaching syllabus / curriculum outline "
            "(objectives, unit list, assessment, few example sentences)",
            "",
            f"Target language: {language}",
            f"Source language: {source_language}",
            "",
            "Return STRICT JSON: "
            '{"kind": "...", "confidence": 0.0-1.0, "reason": "<= 40 chars"}',
            "",
            "Document excerpt:",
            excerpt,
        ]
    )
    return [
        {"role": "system", "content": _SYSTEM},
        {"role": "user", "content": user},
    ]


def coerce_classification(
    raw: dict[str, Any], fallback: DocumentProfile
) -> DocumentProfile:
    """Validate a model classification, falling back on anything unexpected."""
    kind = str(raw.get("kind") or "").strip().lower()
    if kind not in DOCUMENT_KINDS:
        return fallback
    try:
        confidence = float(raw.get("confidence", 0.0))
    except (TypeError, ValueError):
        confidence = 0.0
    if not 0.0 <= confidence <= 1.0:
        confidence = 0.0
    reason = str(raw.get("reason") or "").strip()
    evidence = list(fallback.evidence)
    if reason:
        evidence.insert(0, f"AI：{reason}")
    return DocumentProfile(
        kind=kind,
        preset=preset_for_profile_kind(kind),
        confidence=confidence or fallback.confidence,
        evidence=tuple(evidence[:4]),
        unit_count=fallback.unit_count,
        heading_style=fallback.heading_style,
        source="ai",
    )


def classify_document_with_ai(
    config: AiApiConfig,
    language: str,
    source_language: str,
    text: str,
    *,
    timeout: float = 60.0,
    cancel_check: Callable[[], bool] | None = None,
    on_chunk: Callable[[str], None] | None = None,
    usage_callback: Callable[[dict[str, int]], None] | None = None,
) -> DocumentProfile:
    """Ask the model to confirm the heuristic classification.

    Any failure (network, parse, unknown kind) returns the heuristic profile:
    classification is an optimisation, never a blocker, so this function does
    not raise ``RuntimeError`` the way extraction does. ``AiCancelled`` still
    propagates so a user cancel stops the run instead of silently continuing.
    """
    heuristic = profile_document(text)
    messages = build_classify_messages(language, source_language, text)
    try:
        body = chat_json(
            config,
            messages,
            temperature=0.0,
            timeout=timeout,
            cancel_check=cancel_check,
            on_chunk=on_chunk,
            usage_callback=usage_callback,
            model=config.select_model("chat"),
        )
        raw = parse_json_obj(extract_content(body, strip=True))
    except AiCancelled:
        raise
    except (RuntimeError, ValueError, KeyError, TypeError, OSError):
        # Advisory path: keep the heuristic and log the reason at debug level.
        logger.debug(
            "document_profile: AI classification unavailable, using heuristic",
            exc_info=True,
        )
        return heuristic
    if not isinstance(raw, dict):
        return heuristic
    profile = coerce_classification(raw, heuristic)
    logger.debug(
        "document_profile: %s (conf=%.2f, source=%s)",
        profile.kind,
        profile.confidence,
        profile.source,
    )
    return profile


def profile_summary(profile: DocumentProfile) -> str:
    """One-line human summary for the import log / status bar."""
    evidence = "；".join(profile.evidence[:2])
    suffix = f"（{evidence}）" if evidence else ""
    return (
        f"识别为 {profile.label}，置信度 {profile.confidence:.0%}，"
        f"建议预设「{profile.preset}」{suffix}"
    )


def profile_to_json(profile: DocumentProfile) -> str:
    """Serialize a profile for telemetry payloads."""
    return json.dumps(
        {
            "kind": profile.kind,
            "preset": profile.preset,
            "confidence": round(profile.confidence, 3),
            "units": profile.unit_count,
            "heading_style": profile.heading_style,
            "source": profile.source,
        },
        ensure_ascii=False,
    )
