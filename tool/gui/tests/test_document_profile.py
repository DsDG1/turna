"""Tests for the document-kind profiler (heuristic + AI coercion)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.document_profile import (
    DocumentProfile,
    build_classify_messages,
    coerce_classification,
    preset_for_profile_kind,
    profile_document,
    profile_summary,
    profile_to_json,
)

_SYLLABUS = """# Türkçe A1-A2 Ders İzlencesi

## 教学大纲说明
本课程依据欧洲语言共同参考框架编写，教学纲领规定 6 个单元，每单元 6 课时。

Ünite 1: Tanışma ve selamlaşma
- 教学目标：能进行简单的自我介绍
- 语法：kişi zamirleri

Ünite 2: Aile
- 学习目标：能介绍家庭成员
- 语法：iyelik ekleri

Ünite 3: Günlük rutin
- 能说出日常活动与时间

考核：单元小测 40%，期末口试 60%。
词汇量：800
"""

_DIALOGUE = """A: Merhaba, nasılsın?
B: İyiyim, teşekkürler. Sen nasılsın?
A: Ben de iyiyim.
B: Bugün ne yapıyorsun?
A: Ders çalışıyorum.
B: Kolay gelsin.
A: Teşekkür ederim.
— Görüşürüz.
— Hoşça kal.
"""

_READING = (
    "İstanbul, Türkiye'nin en kalabalık şehridir. "
    "Boğaz'ın iki yakasında kurulmuş olan şehir, tarih boyunca birçok medeniyete ev sahipliği yapmıştır. "
    "Şehirde ulaşım vapur, metro ve otobüsle sağlanır. "
) * 6


class HeuristicProfileTest(unittest.TestCase):
    def test_syllabus_detected(self) -> None:
        profile = profile_document(_SYLLABUS)
        self.assertEqual(profile.kind, "syllabus")
        self.assertEqual(profile.preset, "syllabus")
        self.assertGreaterEqual(profile.confidence, 0.45)
        self.assertGreater(profile.unit_count, 0)

    def test_dialogue_detected(self) -> None:
        profile = profile_document(_DIALOGUE)
        self.assertEqual(profile.kind, "dialogue")
        self.assertEqual(profile.preset, "dialogue")

    def test_long_prose_reads_as_reading(self) -> None:
        profile = profile_document(_READING)
        self.assertEqual(profile.kind, "reading")

    def test_empty_text_is_low_confidence_textbook(self) -> None:
        profile = profile_document("")
        self.assertEqual(profile.kind, "textbook")
        self.assertLess(profile.confidence, 0.5)

    def test_summary_and_json_are_stable(self) -> None:
        profile = profile_document(_SYLLABUS)
        self.assertIn("教学纲领", profile_summary(profile))
        payload = profile_to_json(profile)
        self.assertIn('"kind": "syllabus"', payload)

    def test_preset_for_profile_kind_falls_back(self) -> None:
        self.assertEqual(preset_for_profile_kind("unknown-kind"), "general")


class CoerceClassificationTest(unittest.TestCase):
    def setUp(self) -> None:
        self.fallback = DocumentProfile(
            kind="textbook",
            preset="general",
            confidence=0.4,
            evidence=("heuristic",),
            unit_count=3,
            heading_style="atx",
        )

    def test_valid_ai_answer_wins(self) -> None:
        profile = coerce_classification(
            {"kind": "syllabus", "confidence": 0.8, "reason": "unit ladder"},
            self.fallback,
        )
        self.assertEqual(profile.kind, "syllabus")
        self.assertEqual(profile.source, "ai")
        self.assertAlmostEqual(profile.confidence, 0.8)
        self.assertIn("AI：unit ladder", profile.evidence)

    def test_unknown_kind_falls_back(self) -> None:
        profile = coerce_classification({"kind": "comic"}, self.fallback)
        self.assertEqual(profile.kind, "textbook")

    def test_out_of_range_confidence_uses_fallback(self) -> None:
        profile = coerce_classification(
            {"kind": "grammar", "confidence": 42}, self.fallback
        )
        self.assertEqual(profile.kind, "grammar")
        self.assertAlmostEqual(profile.confidence, 0.4)

    def test_classify_prompt_lists_all_kinds(self) -> None:
        messages = build_classify_messages("Turkish", "Chinese", _SYLLABUS)
        user = messages[1]["content"]
        for kind in ("textbook", "grammar", "dialogue", "reading", "syllabus"):
            self.assertIn(kind, user)


if __name__ == "__main__":
    unittest.main()
