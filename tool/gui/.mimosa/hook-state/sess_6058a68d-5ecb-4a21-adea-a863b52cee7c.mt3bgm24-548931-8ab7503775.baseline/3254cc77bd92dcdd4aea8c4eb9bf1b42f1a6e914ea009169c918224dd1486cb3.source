"""Tests for generation summary (aiEnhance perception U0)."""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

_GUI_ROOT = Path(__file__).resolve().parents[1]
if str(_GUI_ROOT) not in sys.path:
    sys.path.insert(0, str(_GUI_ROOT))

from src.backend.ai_summary import (  # noqa: E402
    build_generation_summary,
    format_ai_status_line,
    format_summary_card,
)
from src.backend.content_quality import (  # noqa: E402
    build_quality_fix_hint_for_dimension,
    issues_for_dimension,
    score_section,
)

_GOLDENS = Path(__file__).resolve().parent / "ai_goldens"


def _load(name: str) -> dict:
    return json.loads((_GOLDENS / name).read_text(encoding="utf-8"))


class BuildGenerationSummaryTest(unittest.TestCase):
    def test_clean_golden_ok(self) -> None:
        section = _load("a1_greetings_clean.json")
        summary = build_generation_summary(
            section,
            level="A1",
            structural=[],
            usage={"total_tokens": 1200},
            cache_hit=False,
            model_json="gpt-test",
            mode="fast",
        )
        self.assertTrue(summary.ok)
        self.assertEqual(summary.error_count, 0)
        self.assertIsNotNone(summary.quality_mean)
        self.assertGreaterEqual(summary.quality_mean or 0, 0.5)
        self.assertEqual(summary.placeholders, 0)
        self.assertEqual(summary.model_json, "gpt-test")
        self.assertEqual(summary.mode, "fast")
        self.assertGreater(summary.word_count, 0)
        card = format_summary_card(summary)
        self.assertIn("生成摘要", card)
        self.assertIn("结构校验通过", card)
        self.assertIn("建议性", card)

    def test_placeholders_surface_in_summary(self) -> None:
        section = _load("a1_with_placeholders.json")
        summary = build_generation_summary(section, level="A1", structural=[])
        self.assertGreater(summary.placeholders, 0)
        card = format_summary_card(summary)
        self.assertIn("待补", card)

    def test_structural_errors_set_ok_false(self) -> None:
        section = _load("a1_greetings_clean.json")
        structural = [
            {"level": "error", "path": "units/0", "message": "bad unit"},
            {"level": "warning", "path": "words/0", "message": "soft"},
        ]
        summary = build_generation_summary(
            section, level="A1", structural=structural
        )
        self.assertFalse(summary.ok)
        self.assertEqual(summary.error_count, 1)
        self.assertEqual(summary.warning_count, 1)
        self.assertTrue(any("bad unit" in str(i.get("message")) for i in summary.top_issues))

    def test_grounded_coverage_when_pool(self) -> None:
        section = _load("a1_grounded_pool.json")
        pool = [
            {"id": "w-merhaba", "term": "Merhaba", "_kind": "word"},
            {"id": "w-other", "term": "x", "_kind": "word"},
        ]
        # Use whatever ids exist in the golden
        words = section.get("words") or []
        if words:
            pool = [{"id": words[0]["id"], "term": "t", "_kind": "word"}]
        summary = build_generation_summary(
            section, level="A1", resource_pool=pool, structural=[]
        )
        self.assertIsNotNone(summary.grounded_coverage)
        card = format_summary_card(summary)
        self.assertIn("Grounded", card)

    def test_none_section(self) -> None:
        summary = build_generation_summary(None)
        self.assertFalse(summary.ok)
        self.assertIn("无有效", format_summary_card(summary))

    def test_cache_hit_in_card(self) -> None:
        section = _load("a1_greetings_clean.json")
        summary = build_generation_summary(
            section, structural=[], cache_hit=True, model_json="m1"
        )
        self.assertIn("缓存命中", format_summary_card(summary))


class FormatAiStatusLineTest(unittest.TestCase):
    def test_status_bits(self) -> None:
        line = format_ai_status_line(
            model_json="deepseek-chat",
            model_chat="deepseek-chat",
            cache_hit=True,
            usage={"total_tokens": 42},
            mode="refine",
        )
        self.assertIn("精修", line)
        self.assertIn("json:deepseek-chat", line)
        self.assertIn("缓存✓", line)
        self.assertIn("42 tok", line)

    def test_empty(self) -> None:
        self.assertEqual(format_ai_status_line(), "")


class DimensionDrillTest(unittest.TestCase):
    def test_issues_for_dimension_and_hint(self) -> None:
        section = _load("mcq_dup_options.json")
        report = score_section(section, level="A1")
        issues = issues_for_dimension(report, "distractor")
        # MCQ dup golden should produce distractor-related findings or low score
        hint = build_quality_fix_hint_for_dimension(report, "distractor")
        self.assertIn("distractor", hint)
        self.assertIn("id 不变", hint)
        # Filtering never raises
        self.assertIsInstance(issues, list)
        empty = issues_for_dimension(report, "nonexistent_dim")
        self.assertEqual(empty, [])


if __name__ == "__main__":
    unittest.main()
