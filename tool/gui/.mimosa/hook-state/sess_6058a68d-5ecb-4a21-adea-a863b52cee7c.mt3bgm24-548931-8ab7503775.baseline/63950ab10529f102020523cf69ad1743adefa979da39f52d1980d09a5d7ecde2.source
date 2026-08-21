"""K08 Spiral Vocab Generator (Phase 3 Route A).

Calculates vocabulary repetition gaps across lessons using SLA memory curves
and generates structured review lesson patches to close spiral gaps.
"""
from __future__ import annotations

import logging
from typing import Any, Dict, List, Optional

from src.backend.content_quality import evaluate_unit_spiral

logger = logging.getLogger("turna.spiral_vocab")


class SpiralVocabGenerator:
    """SLA Spiral Vocabulary Review Generator."""

    def __init__(self, target_repetition: int = 1) -> None:
        self._target_repetition = max(1, target_repetition)

    def evaluate_gaps(self, section: Dict[str, Any]) -> Dict[str, Any]:
        """Evaluate spiral vocabulary gaps in a section using content_quality.evaluate_unit_spiral."""
        if not isinstance(section, dict):
            return {
                "section_id": "",
                "total_introduced": 0,
                "surfaced_count": 0,
                "unsurfaced_count": 0,
                "unsurfaced": [],
            }
        return evaluate_unit_spiral(section)

    def generate_review_lesson_patch(
        self,
        section: Dict[str, Any],
        target_unit_id: Optional[str] = None,
        lesson_id: str = "lesson_review_spiral",
    ) -> Dict[str, Any]:
        """Generate a review lesson JSON structure incorporating unsurfaced vocabulary.

        Returns a dictionary representing a complete `review` lesson patch.
        """
        report = self.evaluate_gaps(section)
        unsurfaced = report.get("unsurfaced", [])

        if not unsurfaced:
            logger.info("No unsurfaced vocabulary found in section %s", report.get("section_id"))
            return {
                "id": lesson_id,
                "title": "词汇复习 (已完全巩固)",
                "template": "review",
                "content": {"stages": []},
            }

        # Build practice items for unsurfaced words
        stage_items: List[Dict[str, Any]] = []
        for idx, item in enumerate(unsurfaced, start=1):
            wid = item["word_id"]
            term = item["term"]

            # Alternating question types based on SLA cognitive levels
            if idx % 3 == 1:
                # Multiple Choice (Recognition)
                stage_items.append({
                    "id": f"spiral_mcq_{idx}",
                    "runtimeType": "multipleChoice",
                    "wordId": wid,
                    "prompt": f"选择「{term}」的正确释义：",
                    "expected": term,
                    "options": [term, "错误项A", "错误项B", "错误项C"],
                })
            elif idx % 3 == 2:
                # Fill Blank (Recall)
                stage_items.append({
                    "id": f"spiral_fill_{idx}",
                    "runtimeType": "fillBlank",
                    "wordId": wid,
                    "prompt": f"请填空补全句子包含 [{term}]：",
                    "expected": term,
                })
            else:
                # Reorder Sentence (Production)
                stage_items.append({
                    "id": f"spiral_reorder_{idx}",
                    "runtimeType": "reorderSentence",
                    "wordId": wid,
                    "prompt": f"重排包含「{term}」的语篇：",
                    "source": f"Bu {term} çok güzel.",
                    "expected": f"Bu {term} çok güzel.",
                })

        review_lesson = {
            "id": lesson_id,
            "title": f"螺旋词汇复习 ({len(unsurfaced)} 词强化)",
            "template": "review",
            "content": {
                "stages": [
                    {
                        "id": "stage_spiral_review",
                        "title": "螺旋复习阶段",
                        "items": stage_items,
                    }
                ]
            },
        }

        logger.info(
            "Generated spiral review lesson patch for section %s with %d unsurfaced items",
            report.get("section_id"),
            len(stage_items),
        )
        return review_lesson
