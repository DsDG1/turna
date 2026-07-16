"""Unit tests for token usage + cost estimation (src.backend.ai_usage).

Pure-Python, no PySide6 dependency — runnable in the sandbox.
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.ai_usage import (
    PRICING,
    estimate_cost,
    estimate_usage,
    format_usage_line,
)


class TestEstimateUsage(unittest.TestCase):
    def test_extracts_tokens(self) -> None:
        body = {"usage": {"prompt_tokens": 100, "completion_tokens": 50, "total_tokens": 150}}
        usage = estimate_usage(body)
        self.assertEqual(usage, {"prompt_tokens": 100, "completion_tokens": 50, "total_tokens": 150})

    def test_missing_usage_returns_zeros(self) -> None:
        self.assertEqual(
            estimate_usage({"choices": []}),
            {"prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0},
        )

    def test_none_body_returns_zeros(self) -> None:
        self.assertEqual(
            estimate_usage(None),
            {"prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0},
        )

    def test_derives_total_when_absent(self) -> None:
        body = {"usage": {"prompt_tokens": 10, "completion_tokens": 5}}
        usage = estimate_usage(body)
        self.assertEqual(usage["total_tokens"], 15)


class TestEstimateCost(unittest.TestCase):
    def test_known_model(self) -> None:
        usage = {"prompt_tokens": 1_000_000, "completion_tokens": 1_000_000, "total_tokens": 2_000_000}
        # deepseek-chat: in=1.0, out=4.0 per 1M -> (1*1 + 1*4) = 5.0 CNY
        cost, currency = estimate_cost(usage, "deepseek-chat")
        self.assertAlmostEqual(cost, 5.0, places=2)
        self.assertEqual(currency, "CNY")

    def test_unknown_model_returns_none(self) -> None:
        usage = {"prompt_tokens": 100, "completion_tokens": 50, "total_tokens": 150}
        cost, currency = estimate_cost(usage, "zz-unknown-model")
        self.assertIsNone(cost)
        self.assertEqual(currency, "")

    def test_unknown_deepseek_prefix_uses_fallback(self) -> None:
        usage = {"prompt_tokens": 1_000_000, "completion_tokens": 0, "total_tokens": 1_000_000}
        # deepseek-foo not in table -> prefix fallback in=1.0, out=4.0 -> 1.0
        cost, currency = estimate_cost(usage, "deepseek-foo")
        self.assertAlmostEqual(cost, 1.0, places=2)
        self.assertEqual(currency, "CNY")

    def test_empty_model_returns_none(self) -> None:
        cost, _ = estimate_cost({"prompt_tokens": 10, "completion_tokens": 0, "total_tokens": 10}, "")
        self.assertIsNone(cost)


class TestFormatUsageLine(unittest.TestCase):
    def test_known_model_shows_cost(self) -> None:
        usage = {"prompt_tokens": 8000, "completion_tokens": 4300, "total_tokens": 12300}
        line = format_usage_line(usage, "deepseek-v4-pro")
        # 12.3k tokens, cost present with ¥ and 估算 marker.
        self.assertIn("12.3k tokens", line)
        self.assertIn("¥", line)
        self.assertIn("估算", line)

    def test_unknown_model_shows_no_price(self) -> None:
        usage = {"prompt_tokens": 0, "completion_tokens": 12300, "total_tokens": 12300}
        line = format_usage_line(usage, "zz-unknown-model")
        self.assertIn("12.3k tokens", line)
        self.assertIn("无价目表", line)
        self.assertNotIn("¥", line)

    def test_zero_usage(self) -> None:
        usage = {"prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0}
        self.assertEqual(format_usage_line(usage, "deepseek-chat"), "≈ 0 tokens")

    def test_millions_compact(self) -> None:
        usage = {"prompt_tokens": 800_000, "completion_tokens": 400_000, "total_tokens": 1_200_000}
        line = format_usage_line(usage, "deepseek-chat")
        self.assertIn("1.2M tokens", line)


if __name__ == "__main__":
    unittest.main()