#!/usr/bin/env python3
from __future__ import annotations

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


if __name__ == "__main__":
    unittest.main()
