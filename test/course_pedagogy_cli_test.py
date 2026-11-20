#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT / "tool"))

from course_pedagogy import (  # type: ignore
    arrange_choice,
    evaluate_lesson_pedagogy,
    phase_two_prompt_block,
)


def sub_lesson(items: list[dict]) -> dict:
    return {
        "id": "sl-test",
        "stages": [{"id": "st-test", "items": items}],
    }


def lesson(items: list[dict]) -> dict:
    return {
        "id": "l-test",
        "template": "intro",
        "content": {"subLessons": [sub_lesson(items)]},
    }


class PhaseTwoRecipeTest(unittest.TestCase):
    def test_prompt_carries_the_shared_contract(self) -> None:
        prompt = phase_two_prompt_block()
        self.assertIn("12–15", prompt)
        self.assertIn("reviewPolicy", prompt)
        self.assertIn("中文", prompt)

    def test_thin_sub_lesson_and_missing_production_are_reported(self) -> None:
        value = lesson([
            {"runtimeType": "showWord", "wordId": "w-1"},
            {"runtimeType": "multipleChoice", "options": ["A", "B"], "correctIndex": 0},
        ])
        codes = {finding.code for finding in evaluate_lesson_pedagogy(value)}
        self.assertIn("sublesson_length", codes)
        self.assertIn("production_missing", codes)

    def test_new_word_spacing_is_reported(self) -> None:
        items = [
            {"runtimeType": "showWord", "wordId": "w-1"},
            {"runtimeType": "translateSentence", "expected": "one"},
            {"runtimeType": "showWord", "wordId": "w-2"},
            *[
                {"runtimeType": "translateSentence", "expected": f"value {index}"}
                for index in range(9)
            ],
        ]
        codes = {finding.code for finding in evaluate_lesson_pedagogy(lesson(items))}
        self.assertIn("new_word_spacing", codes)

    def test_fixed_answer_position_is_reported(self) -> None:
        items = [
            {
                "runtimeType": "multipleChoice",
                "options": ["A", "B"],
                "correctIndex": 0,
            }
            for _ in range(3)
        ]
        codes = {finding.code for finding in evaluate_lesson_pedagogy(lesson(items))}
        self.assertIn("answer_position", codes)

    def test_choice_arrangement_is_deterministic_and_preserves_answer(self) -> None:
        first = arrange_choice(
            ["doğru", "yanlış 1", "yanlış 2"],
            0,
            seed="lesson-item",
            preferred_index=2,
        )
        second = arrange_choice(
            ["doğru", "yanlış 1", "yanlış 2"],
            0,
            seed="lesson-item",
            preferred_index=2,
        )
        self.assertEqual(first, second)
        self.assertEqual(first[0][first[1]], "doğru")
        self.assertEqual(first[1], 2)

    def test_pseudo_fill_blank_and_single_word_mcq_overload_are_reported(self) -> None:
        items = [
            {"runtimeType": "showWord", "wordId": "w-1"},
            {
                "runtimeType": "multipleChoice",
                "prompt": "çay 是什么意思？",
                "options": ["茶", "水", "咖啡"],
                "correctIndex": 0,
            },
            {
                "runtimeType": "multipleChoice",
                "prompt": "su 是什么意思？",
                "options": ["茶", "水", "咖啡"],
                "correctIndex": 1,
            },
            {
                "runtimeType": "multipleChoice",
                "prompt": "kahve 是什么意思？",
                "options": ["茶", "水", "咖啡"],
                "correctIndex": 2,
            },
            {
                "runtimeType": "fillBlank",
                "id": "fb-pseudo",
                "sentence": "「茶」= _____",
                "answer": "çay",
            },
            *[
                {
                    "runtimeType": "translateSentence",
                    "source": f"请给我一杯茶 {index}",
                    "expected": "Bir çay lütfen.",
                }
                for index in range(7)
            ],
        ]
        codes = {finding.code for finding in evaluate_lesson_pedagogy(lesson(items))}
        self.assertIn("pseudo_fill_blank", codes)
        self.assertIn("single_word_choice_overload", codes)

    def test_low_sentence_ratio_in_practice_is_reported(self) -> None:
        word_items = [
            {
                "runtimeType": "translateSentence",
                "source": f"词 {index}",
                "expected": "su",
            }
            for index in range(12)
        ]
        practice_bad = {
            "id": "l-practice-bad",
            "template": "practice",
            "content": {"subLessons": [sub_lesson(word_items)]},
        }
        codes = {finding.code for finding in evaluate_lesson_pedagogy(practice_bad)}
        self.assertIn("sentence_ratio_low", codes)

        sentence_items = [
            {
                "runtimeType": "translateSentence",
                "source": f"请给我一杯茶 {index}",
                "expected": "Bir çay lütfen.",
            }
            for index in range(12)
        ]
        practice_good = {
            "id": "l-practice-good",
            "template": "practice",
            "content": {"subLessons": [sub_lesson(sentence_items)]},
        }
        self.assertEqual(evaluate_lesson_pedagogy(practice_good), [])

    def test_duplicate_review_pool_items_are_reported(self) -> None:
        dup_item = {
            "runtimeType": "translateSentence",
            "source": "请给我一杯茶。",
            "expected": "Bir çay lütfen.",
        }
        review = {
            "id": "l-review-dup",
            "template": "review",
            "content": {
                "stages": [
                    {"id": "st-pool", "items": [dict(dup_item) for _ in range(12)]}
                ]
            },
        }
        codes = {finding.code for finding in evaluate_lesson_pedagogy(review)}
        self.assertIn("duplicate_pool_items", codes)

    def test_nouveau_turkish_section1_passes_pedagogy_zero_findings(self) -> None:
        course_dir = PROJECT_ROOT / "assets" / "courses" / "nouveau-turkish"
        section_path = course_dir / "sections" / "section1.json"
        vocab_path = course_dir / "vocab.json"
        section = json.loads(section_path.read_text(encoding="utf-8"))
        vocab = json.loads(vocab_path.read_text(encoding="utf-8")).get("words", [])
        all_findings = []
        for unit in section.get("units", []):
            for current_lesson in unit.get("lessons", []):
                findings = evaluate_lesson_pedagogy(
                    current_lesson, level="A1", vocab=vocab
                )
                for finding in findings:
                    all_findings.append((current_lesson.get("id"), finding.code, finding.message))
        self.assertEqual(all_findings, [])

    def test_ambiguous_fill_blank_and_unsupported_media_are_reported(self) -> None:
        vocab = [
            {"id": "w-cay", "term": "çay", "pos": "noun", "tags": ["noun"]},
            {"id": "w-kahve", "term": "kahve", "pos": "noun", "tags": ["noun"]},
            {"id": "w-su", "term": "su", "pos": "noun", "tags": ["noun"]},
            {"id": "w-buyuk", "term": "büyük", "pos": "adjective", "tags": ["adjective"]},
            {"id": "w-kucuk", "term": "küçük", "pos": "adjective", "tags": ["adjective"]},
        ]
        bad_items = [
            {
                "runtimeType": "fillBlank",
                "id": "fb-ambig",
                "sentence": "Merhaba! Bir _____ lütfen.",
                "answer": "çay",
                "choices": ["çay", "kahve", "su"],
                "imageAssets": ["assets/images/course/nt/cay.svg"],
            },
            *[
                {
                    "runtimeType": "translateSentence",
                    "source": f"请给我一杯咖啡 {idx}",
                    "expected": "Bir kahve lütfen.",
                }
                for idx in range(11)
            ],
        ]
        practice_bad = {
            "id": "l-practice-ambig",
            "template": "practice",
            "content": {"subLessons": [sub_lesson(bad_items)]},
        }
        codes = {
            finding.code
            for finding in evaluate_lesson_pedagogy(practice_bad, vocab=vocab)
        }
        self.assertIn("ambiguous_fill_blank", codes)
        self.assertIn("fill_blank_unsupported_media", codes)

        good_items = [
            {
                "runtimeType": "fillBlank",
                "id": "fb-contrast",
                "sentence": "— Büyük kahve?\n— Hayır, _____ kahve lütfen.",
                "answer": "küçük",
                "choices": ["küçük", "büyük"],
            },
            {
                "runtimeType": "fillBlank",
                "id": "fb-hinted",
                "sentence": "Merhaba! Bir _____ lütfen.",
                "answer": "çay",
                "hint": "点一杯茶",
                "choices": ["çay", "kahve", "su"],
            },
            *[
                {
                    "runtimeType": "translateSentence",
                    "source": f"请给我一杯咖啡 {idx}",
                    "expected": "Bir kahve lütfen.",
                }
                for idx in range(10)
            ],
        ]
        practice_good = {
            "id": "l-practice-clear",
            "template": "practice",
            "content": {"subLessons": [sub_lesson(good_items)]},
        }
        self.assertEqual(evaluate_lesson_pedagogy(practice_good, vocab=vocab), [])

    def test_ambiguous_listen_pick_is_reported(self) -> None:
        bad_listen = {
            "id": "l-listen-ambig",
            "template": "listening",
            "content": {
                "listeningPhases": [
                    {
                        "id": "lp-words",
                        "type": "wordPairing",
                        "transcript": "çay、kahve、su",
                        "items": [
                            {
                                "runtimeType": "listenAndPick",
                                "id": "pick-bad",
                                "audioAsset": "a-words",
                                "prompt": "你听到了哪个词？",
                                "options": ["su", "çay", "kahve"],
                                "correctIndex": 1,
                            }
                        ],
                    }
                ]
            },
        }
        codes = {finding.code for finding in evaluate_lesson_pedagogy(bad_listen)}
        self.assertIn("ambiguous_listen_pick", codes)

        good_listen = {
            "id": "l-listen-clear",
            "template": "listening",
            "content": {
                "listeningPhases": [
                    {
                        "id": "lp-words",
                        "type": "wordPairing",
                        "transcript": "çay、kahve、su",
                        "items": [
                            {
                                "runtimeType": "listenAndPick",
                                "id": "pick-good",
                                "audioAsset": "a-words",
                                "prompt": "按顺序听，你听到的第一个词是什么？",
                                "options": ["su", "çay", "kahve"],
                                "correctIndex": 1,
                            }
                        ],
                    }
                ]
            },
        }
        self.assertEqual(evaluate_lesson_pedagogy(good_listen), [])


if __name__ == "__main__":
    unittest.main()
