"""Unit tests for K08 SpiralVocabGenerator (Phase 3 Route A)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.experience.spiral_vocab_generator import SpiralVocabGenerator


class SpiralVocabGeneratorTests(unittest.TestCase):
    def setUp(self) -> None:
        self.generator = SpiralVocabGenerator(target_repetition=1)

    def test_evaluate_gaps_empty_section(self) -> None:
        report = self.generator.evaluate_gaps({"id": "s1", "units": [], "words": []})
        self.assertEqual(report["section_id"], "s1")
        self.assertEqual(report["unsurfaced_count"], 0)
        self.assertEqual(report["unsurfaced"], [])

    def test_evaluate_gaps_with_unsurfaced_vocab(self) -> None:
        section = {
            "id": "sec_01",
            "words": [
                {"id": "w1", "term": "elma"},
                {"id": "w2", "term": "su"},
            ],
            "units": [
                {
                    "id": "u1",
                    "lessons": [
                        {
                            "id": "l1",
                            "content": {
                                "stages": [
                                    {
                                        "id": "st1",
                                        "items": [
                                            {"id": "i1", "runtimeType": "showWord", "wordId": "w1"},
                                            {"id": "i2", "runtimeType": "showWord", "wordId": "w2"},
                                        ],
                                    }
                                ]
                            },
                        }
                    ],
                }
            ],
        }
        report = self.generator.evaluate_gaps(section)
        self.assertEqual(report["total_introduced"], 2)
        self.assertEqual(report["unsurfaced_count"], 2)

    def test_generate_review_lesson_patch(self) -> None:
        section = {
            "id": "sec_01",
            "words": [
                {"id": "w1", "term": "elma"},
                {"id": "w2", "term": "su"},
                {"id": "w3", "term": "ekmek"},
            ],
            "units": [
                {
                    "id": "u1",
                    "lessons": [
                        {
                            "id": "l1",
                            "content": {
                                "stages": [
                                    {
                                        "id": "st1",
                                        "items": [
                                            {"id": "i1", "runtimeType": "showWord", "wordId": "w1"},
                                            {"id": "i2", "runtimeType": "showWord", "wordId": "w2"},
                                            {"id": "i3", "runtimeType": "showWord", "wordId": "w3"},
                                        ],
                                    }
                                ]
                            },
                        }
                    ],
                }
            ],
        }
        patch = self.generator.generate_review_lesson_patch(section, lesson_id="lesson_spiral_01")
        self.assertEqual(patch["id"], "lesson_spiral_01")
        self.assertEqual(patch["template"], "review")

        stages = patch["content"]["stages"]
        self.assertEqual(len(stages), 1)
        items = stages[0]["items"]
        self.assertEqual(len(items), 3)

        # Check question types: multipleChoice, fillBlank, reorderSentence
        self.assertEqual(items[0]["runtimeType"], "multipleChoice")
        self.assertEqual(items[1]["runtimeType"], "fillBlank")
        self.assertEqual(items[2]["runtimeType"], "reorderSentence")


if __name__ == "__main__":
    unittest.main()
