"""Unit tests for App-parity Turkish answer grading, read-aloud scoring, and review sampling."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.answer_grading import (
    fold_turkish,
    matches_course_answer,
    normalize_course_answer,
    sample_review_pool,
    score_read_aloud,
)


class AnswerGradingParityTest(unittest.TestCase):
    def test_turkish_folding_matches_app(self) -> None:
        self.assertEqual(fold_turkish("İyi"), "iyi")
        self.assertEqual(fold_turkish("Işık"), "işik")
        self.assertEqual(fold_turkish("Hâlâ"), "hala")
        self.assertEqual(fold_turkish("Rüzgâr"), "rüzgar")

    def test_matches_course_answer_ignores_punctuation_and_uses_accepted(self) -> None:
        self.assertTrue(matches_course_answer("iyi gunler!", "İyi günler", ["İyi gunler"]))
        self.assertTrue(matches_course_answer("Bir çay, lütfen!", "Bir çay lütfen"))
        self.assertTrue(
            matches_course_answer(
                "Teşekkür ederim",
                "Teşekkürler",
                ["Teşekkür ederim", "Sağ ol"],
            )
        )
        self.assertFalse(matches_course_answer("", "Merhaba"))
        self.assertFalse(matches_course_answer("Kahve", "Çay", ["Su"]))
        self.assertEqual(normalize_course_answer("  Merhaba,   dünya!  "), "merhaba dünya")

    def test_read_aloud_scoring_matches_app_rules(self) -> None:
        # 2/3 words matched -> 0.667 >= 0.6 passes
        res = score_read_aloud("Bir çay lütfen", "1 çay")
        self.assertTrue(res.passed)
        self.assertAlmostEqual(res.ratio, 2 / 3, places=3)
        # Prefix extension (merhaba <-> merhabalar) + single edit distance (teşekkür <-> tesekkur)
        res2 = score_read_aloud("Merhaba arkadaşlar", "Merhabalar arkadaslar")
        self.assertTrue(res2.passed)
        self.assertEqual(res2.ratio, 1.0)
        # Non-Latin script yields 0
        res3 = score_read_aloud("Bir çay lütfen", "请给我一杯茶")
        self.assertFalse(res3.passed)
        self.assertEqual(res3.ratio, 0.0)

    def test_sample_review_pool_respects_bounds_and_no_duplicates(self) -> None:
        pool = [
            {"id": f"i-{n}", "runtimeType": "fillBlank" if n % 2 == 0 else "translateSentence"}
            for n in range(20)
        ]
        policy = {
            "minItems": 6,
            "maxItems": 10,
            "typeWeights": {"fillBlank": 2.0, "translateSentence": 1.0},
        }
        sampled = sample_review_pool(pool, policy, seed=42)
        self.assertGreaterEqual(len(sampled), 6)
        self.assertLessEqual(len(sampled), 10)
        ids = [item["id"] for item in sampled]
        self.assertEqual(len(ids), len(set(ids)))


if __name__ == "__main__":
    unittest.main()
