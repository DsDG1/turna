"""Tests for AI provider/model presets and local pricing table."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.ai_presets import (
    PRICING,
    apply_preset,
    estimate_cost,
    preset_for_provider,
    pricing_for_model,
    provider_names,
)


class AiPresetsTest(unittest.TestCase):
    def test_provider_names_includes_builtin(self) -> None:
        names = provider_names()
        self.assertIn("deepseek", names)
        self.assertIn("openai", names)
        self.assertIn("moonshot", names)
        self.assertIn("ollama", names)
        self.assertIn("custom", names)

    def test_preset_for_deepseek(self) -> None:
        preset = preset_for_provider("deepseek")
        self.assertEqual(preset.name, "deepseek")
        self.assertEqual(preset.base_url, "https://api.deepseek.com")
        self.assertTrue(preset.supports_reasoning)

    def test_preset_for_unknown_returns_custom(self) -> None:
        preset = preset_for_provider("unknown")
        self.assertEqual(preset.name, "custom")

    def test_apply_preset_fills_defaults(self) -> None:
        url, model, reasoning = apply_preset("", "", False, "deepseek")
        self.assertEqual(url, "https://api.deepseek.com")
        self.assertEqual(model, "deepseek-v4-pro")
        self.assertTrue(reasoning)

    def test_apply_preset_custom_preserves_values(self) -> None:
        url, model, reasoning = apply_preset(
            "https://my-proxy.example.com", "my-model", True, "custom"
        )
        self.assertEqual(url, "https://my-proxy.example.com")
        self.assertEqual(model, "my-model")
        self.assertTrue(reasoning)

    def test_pricing_for_known_model(self) -> None:
        entry = pricing_for_model("deepseek-v4-pro")
        self.assertIsNotNone(entry)
        self.assertEqual(entry["currency"], "CNY")

    def test_pricing_for_unknown_model_returns_none(self) -> None:
        self.assertIsNone(pricing_for_model("ollama-local-model"))

    def test_estimate_cost_known_model(self) -> None:
        usage = {"prompt_tokens": 1_000_000, "completion_tokens": 500_000}
        cost, currency = estimate_cost(usage, "deepseek-chat")
        self.assertEqual(cost, 3.0)  # 1*1 + 0.5*4 = 3.0
        self.assertEqual(currency, "CNY")

    def test_estimate_cost_unknown_model(self) -> None:
        usage = {"prompt_tokens": 1000, "completion_tokens": 1000}
        cost, currency = estimate_cost(usage, "unknown-model")
        self.assertIsNone(cost)
        self.assertEqual(currency, "")

    def test_pricing_export_matches_module_table(self) -> None:
        self.assertIn("deepseek-v4-pro", PRICING)
        self.assertIn("gpt-4o", PRICING)


if __name__ == "__main__":
    unittest.main()
