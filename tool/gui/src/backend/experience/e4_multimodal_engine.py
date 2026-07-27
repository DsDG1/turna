"""E4 Multimodal Grounding Engine (Phase 4 Direction 1).

Extracts Grounded SLA vocabulary, key phrases, and audio anchors from attachments (PDF, Word, Text, Images),
building strict Grounded Context constraints for lesson generation.
"""
from __future__ import annotations

import logging
import re
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Set, Tuple

logger = logging.getLogger("varnamala.e4_multimodal")


@dataclass
class GroundedContext:
    """Closed-shape Grounded Context snapshot for LLM lesson generation."""

    ref_ids: List[str] = field(default_factory=list)
    grounded_vocab: List[str] = field(default_factory=list)
    grounded_phrases: List[str] = field(default_factory=list)
    audio_anchors: List[str] = field(default_factory=list)
    grounding_score: float = 1.0


class E4MultimodalEngine:
    """Engine for processing attachment records and constructing Grounded LLM Contexts."""

    def __init__(self, min_word_length: int = 2) -> None:
        self._min_word_length = min_word_length

    def extract_grounded_terms(self, text_content: str) -> Set[str]:
        """Extract unique vocabulary terms from text content."""
        if not text_content:
            return set()
        # Unicode word extraction (supports Turkish, European, and Latin scripts)
        words = re.findall(r"\b[\w'-]+\b", text_content.lower())
        return {w for w in words if len(w) >= self._min_word_length}

    def build_grounded_context(self, attachment_records: List[Dict[str, Any]]) -> GroundedContext:
        """Construct a GroundedContext from attachment records (closing the multimodal loop)."""
        ref_ids: List[str] = []
        all_vocab: Set[str] = set()
        all_phrases: Set[str] = set()
        all_audio: Set[str] = set()

        for rec in attachment_records:
            if not isinstance(rec, dict):
                continue

            ref_id = str(rec.get("ref_id") or rec.get("id") or "")
            if ref_id:
                ref_ids.append(ref_id)

            content = str(rec.get("content") or rec.get("text") or "")
            kind = str(rec.get("kind") or "").lower()

            if content:
                extracted = self.extract_grounded_terms(content)
                all_vocab.update(extracted)

                # Extract key phrases (sentences or lines <= 10 words)
                lines = [line.strip() for line in content.splitlines() if line.strip()]
                for line in lines:
                    words_in_line = line.split()
                    if 2 <= len(words_in_line) <= 10:
                        all_phrases.add(line)

            # Collect audio slugs if kind == 'audio' or has audio_path
            audio_path = str(rec.get("audio_path") or "")
            if kind == "audio" or audio_path:
                slug = str(rec.get("name") or rec.get("audio_slug") or ref_id)
                all_audio.add(slug)

        vocab_list = sorted(list(all_vocab))
        phrases_list = sorted(list(all_phrases))[:20]  # Cap top 20 phrases
        audio_list = sorted(list(all_audio))

        grounding_score = 1.0 if vocab_list else 0.0

        ctx = GroundedContext(
            ref_ids=ref_ids,
            grounded_vocab=vocab_list,
            grounded_phrases=phrases_list,
            audio_anchors=audio_list,
            grounding_score=grounding_score,
        )

        logger.info(
            "E4MultimodalEngine built GroundedContext: %d ref_ids, %d vocab terms, %d phrases",
            len(ref_ids),
            len(vocab_list),
            len(phrases_list),
        )
        return ctx

    def evaluate_grounding_fidelity(
        self, generated_items: List[Dict[str, Any]], context: GroundedContext
    ) -> Tuple[float, List[str]]:
        """Evaluate what percentage of vocabulary in generated items is grounded in the attachment context.

        Returns (fidelity_score, ungrounded_terms).
        """
        if not context.grounded_vocab:
            return 1.0, []  # Unconstrained when no grounded context present

        grounded_set = set(context.grounded_vocab)
        used_terms: Set[str] = set()

        for item in generated_items:
            if not isinstance(item, dict):
                continue
            text_fields = [
                str(item.get("expected") or ""),
                str(item.get("source") or ""),
                str(item.get("prompt") or ""),
                *[str(o) for o in (item.get("options") or []) if isinstance(o, str)],
            ]
            combined = " ".join(text_fields)
            terms = self.extract_grounded_terms(combined)
            used_terms.update(terms)

        if not used_terms:
            return 1.0, []

        grounded_count = sum(1 for t in used_terms if t in grounded_set)
        ungrounded = sorted(list(used_terms - grounded_set))
        fidelity = round(grounded_count / max(1, len(used_terms)), 3)

        logger.info(
            "Grounded fidelity evaluated: %.2f (%d/%d grounded terms, %d ungrounded)",
            fidelity,
            grounded_count,
            len(used_terms),
            len(ungrounded),
        )
        return fidelity, ungrounded
