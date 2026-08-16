"""Consolidated tests for AI presets, prompt library, and natural-language edit scope."""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))
from tests._qsettings_mock import make_qsettings  # noqa: E402

from src.backend.ai_generator import AiCourseSpec
from src.backend.ai_presets import (
    PRICING,
    apply_preset,
    estimate_cost,
    preset_for_provider,
    pricing_for_model,
    provider_names,
)
from src.backend.ai_prompt_library import (
    AiPromptLibrary,
    AiPromptTemplate,
)
from src.backend.ai_scope import (  # noqa: E402
    format_scope_resolution,
    resolve_edit_scope,
)

_GOLDENS = Path(__file__).resolve().parent / "ai_goldens"


def _load(name: str) -> dict:
    return json.loads((_GOLDENS / name).read_text(encoding="utf-8"))


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


class AiPromptTemplateTest(unittest.TestCase):
    def test_from_spec_round_trip(self) -> None:
        spec = AiCourseSpec(
            topic="旅行",
            level="A1",
            unit_count=2,
            lessons_per_unit=3,
            template="mixed",
            use_genre_batch=True,
            extra_instructions="加听力",
        )
        tpl = AiPromptTemplate.from_spec("旅行模板", spec)
        self.assertEqual(tpl.topic, "旅行")
        self.assertEqual(tpl.use_genre_batch, True)
        applied = tpl.apply_to_spec(AiCourseSpec())
        self.assertEqual(applied.topic, "旅行")
        self.assertEqual(applied.level, "A1")


class AiPromptLibraryTest(unittest.TestCase):
    def test_save_and_list_templates(self) -> None:
        qs = make_qsettings()
        lib = AiPromptLibrary(qs)
        tpl = AiPromptTemplate(name="test", topic="旅行")
        lib.save_template(tpl)
        templates = lib.list_templates()
        self.assertEqual(len(templates), 1)
        self.assertEqual(templates[0].name, "test")

    def test_save_overwrites_same_name(self) -> None:
        qs = make_qsettings()
        lib = AiPromptLibrary(qs)
        lib.save_template(AiPromptTemplate(name="x", topic="a"))
        lib.save_template(AiPromptTemplate(name="x", topic="b"))
        self.assertEqual(len(lib.list_templates()), 1)
        self.assertEqual(lib.list_templates()[0].topic, "b")

    def test_delete_template(self) -> None:
        qs = make_qsettings()
        lib = AiPromptLibrary(qs)
        lib.save_template(AiPromptTemplate(name="x"))
        self.assertTrue(lib.delete_template("x"))
        self.assertFalse(lib.delete_template("x"))

    def test_record_history_deduplicates_and_caps(self) -> None:
        qs = make_qsettings()
        lib = AiPromptLibrary(qs)
        spec = AiCourseSpec(topic="a")
        for _ in range(22):
            lib.record_history(spec)
        self.assertEqual(len(lib.recent_history()), 1)

    def test_history_differentiated_by_fields(self) -> None:
        qs = make_qsettings()
        lib = AiPromptLibrary(qs)
        lib.record_history(AiCourseSpec(topic="a"))
        lib.record_history(AiCourseSpec(topic="b"))
        self.assertEqual(len(lib.recent_history()), 2)


class ResolveEditScopeTest(unittest.TestCase):
    def test_ordinal_lesson(self) -> None:
        section = _load("a1_greetings_clean.json")
        res = resolve_edit_scope("请改写第 1 课的填空", section)
        self.assertTrue(res.targets)
        self.assertEqual(res.targets[0].kind, "lesson")
        self.assertGreaterEqual(res.confidence, 0.8)

    def test_all_mcq(self) -> None:
        section = _load("mcq_dup_options.json")
        res = resolve_edit_scope("加强所有选择题的干扰项", section)
        self.assertTrue(res.targets)
        kinds = {t.kind for t in res.targets}
        self.assertTrue("item" in kinds or "lesson" in kinds or "section" in kinds)

    def test_empty_instruction(self) -> None:
        res = resolve_edit_scope("", _load("a1_greetings_clean.json"))
        self.assertTrue(res.needs_confirm)
        self.assertEqual(res.targets, [])

    def test_fallback_section(self) -> None:
        section = _load("a1_greetings_clean.json")
        res = resolve_edit_scope("整体润色一下", section)
        self.assertEqual(res.targets[0].kind, "section")
        self.assertTrue(res.needs_confirm)
        text = format_scope_resolution(res)
        self.assertIn("将修改", text)


if __name__ == "__main__":
    unittest.main()
