"""P0-2: course plan normalization / validation / section-spec mapping."""
from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.application.course_plan_service import CoursePlanService

from src.backend.ai.config import AiApiConfig
from src.backend.ai.course_plan import (
    CoursePlanSpec,
    build_plan_prompt,
    generate_course_plan,
    normalize_plan,
    plan_section_to_spec,
    resolve_review_words,
    validate_plan,
)
from src.backend.course_plan_store import CoursePlanStore


def _raw_plan() -> dict:
    return {
        "title": "Turkish Starter",
        "description": "A short A1 course",
        "sections": [
            {
                "name": "问候",
                "description": "打招呼与自我介绍",
                "level": "A1",
                "unit_count": 2,
                "lessons_per_unit": 3,
                "template_mix": ["intro", "practice"],
                "can_do": ["能问候", "能说我叫什么"],
                "brief": "先呈现 merhaba / ben，再做对话练习。",
                "new_words": [
                    {"term": "merhaba", "translation": "你好", "pos": "interj"},
                    {"term": "ben", "translation": "我", "pos": "pron"},
                ],
                "review_terms": [],
            },
            {
                "name": "食物",
                "description": "点餐与基本食物",
                "level": "A1",
                "unit_count": 2,
                "lessons_per_unit": 3,
                "template_mix": ["intro", "listening", "practice"],
                "can_do": ["能点一种食物"],
                "brief": "用 menu 场景复现问候词，再引入食物词。",
                "new_words": [
                    {"term": "ekmek", "translation": "面包", "pos": "noun"},
                    {"term": "su", "translation": "水", "pos": "noun"},
                ],
                "review_terms": ["merhaba"],
            },
        ],
    }


class _PlanAdapter:
    """Minimal adapter surface used by the plan service."""

    def __init__(self) -> None:
        self.sections = []
        self.vocab = []
        self.expressions = []
        self.grammar_points = []
        self.index = {"level": "A1"}
        self.course_dir = None

    @staticmethod
    def validate_section_json(_draft, *, check_existing_ids: bool = True) -> list:
        return []


def _spec(**overrides) -> CoursePlanSpec:
    data = {
        "language": "Turkish",
        "source_language": "Chinese",
        "topic": "日常土耳其语",
        "level_from": "A1",
        "level_to": "A1",
        "section_count": 2,
        "lessons_per_section": 6,
        "word_budget": 4,
    }
    data.update(overrides)
    return CoursePlanSpec(**data)


class NormalizePlanTest(unittest.TestCase):
    def test_ids_are_local_and_deterministic(self) -> None:
        first = normalize_plan(_raw_plan(), _spec())
        second = normalize_plan(_raw_plan(), _spec())

        self.assertEqual([s.section_id for s in first.sections], ["sec-01", "sec-02"])
        self.assertEqual(
            [w.id for w in first.lexicon],
            ["w-merhaba-001", "w-ben-002", "w-ekmek-003", "w-su-004"],
        )
        self.assertEqual(
            [w.id for w in first.lexicon], [w.id for w in second.lexicon]
        )
        self.assertEqual(
            first.sections[1].review_terms, ["merhaba"]
        )

    def test_terms_are_not_trusted_as_ids(self) -> None:
        raw = _raw_plan()
        raw["sections"][0]["new_words"][0]["id"] = "hacked-id"

        plan = normalize_plan(raw, _spec())

        self.assertEqual(plan.lexicon[0].id, "w-merhaba-001")

    def test_invalid_level_falls_back(self) -> None:
        raw = _raw_plan()
        raw["sections"][0]["level"] = "Z9"

        plan = normalize_plan(raw, _spec(level_from="A2"))

        self.assertEqual(plan.sections[0].level, "A2")


class ValidatePlanTest(unittest.TestCase):
    def test_valid_plan_passes(self) -> None:
        plan = normalize_plan(_raw_plan(), _spec())

        errors = validate_plan(plan, _spec())

        self.assertEqual(errors, [])
        self.assertEqual(plan.warnings, [])

    def test_section_count_mismatch(self) -> None:
        plan = normalize_plan(_raw_plan(), _spec(section_count=3))

        errors = validate_plan(plan, _spec(section_count=3))

        self.assertTrue(any("section 数不符" in e for e in errors))

    def test_level_inversion_is_an_error(self) -> None:
        raw = _raw_plan()
        raw["sections"][0]["level"] = "A2"
        raw["sections"][1]["level"] = "A1"
        plan = normalize_plan(raw, _spec())

        errors = validate_plan(plan, _spec())

        self.assertTrue(any("等级倒挂" in e for e in errors))

    def test_duplicate_terms_are_an_error(self) -> None:
        raw = _raw_plan()
        raw["sections"][1]["new_words"][0]["term"] = "merhaba"
        plan = normalize_plan(raw, _spec())

        errors = validate_plan(plan, _spec())

        self.assertTrue(any("新词在课程内重复" in e for e in errors))

    def test_review_term_must_come_from_an_earlier_section(self) -> None:
        raw = _raw_plan()
        raw["sections"][0]["review_terms"] = ["ekmek"]  # introduced later
        plan = normalize_plan(raw, _spec())

        errors = validate_plan(plan, _spec())

        self.assertTrue(any("复习词未在前面章节出现" in e for e in errors))

    def test_budget_drift_is_a_warning(self) -> None:
        plan = normalize_plan(_raw_plan(), _spec(word_budget=40))

        errors = validate_plan(plan, _spec(word_budget=40))

        self.assertEqual(errors, [])
        self.assertTrue(any("偏差较大" in w for w in plan.warnings))

    def test_validation_is_repeatable(self) -> None:
        plan = normalize_plan(_raw_plan(), _spec())

        first = validate_plan(plan, _spec())
        second = validate_plan(plan, _spec())

        self.assertEqual(first, second)
        self.assertEqual(plan.sections[1].review_terms, ["merhaba"])


class ReviewResolutionTest(unittest.TestCase):
    def test_review_word_resolves_to_earlier_lexicon_entry(self) -> None:
        plan = normalize_plan(_raw_plan(), _spec())
        section = plan.sections[1]

        resolved, unresolved = resolve_review_words(plan, section)

        self.assertEqual(unresolved, [])
        self.assertEqual([w.term for w in resolved], ["merhaba"])
        self.assertEqual(resolved[0].section_id, "sec-01")


class SectionSpecTest(unittest.TestCase):
    def test_pool_contains_new_and_review_words(self) -> None:
        plan = normalize_plan(_raw_plan(), _spec())
        section = plan.sections[1]

        spec = plan_section_to_spec(plan, section.section_id)

        pool_terms = {item["term"] for item in (spec.resource_pool or [])}
        self.assertEqual(pool_terms, {"merhaba", "ekmek", "su"})
        self.assertEqual(spec.level, "A1")
        self.assertEqual(spec.unit_count, 2)
        self.assertEqual(spec.lessons_per_unit, 3)
        self.assertEqual(spec.template, "mixed")
        self.assertIn("merhaba", spec.design_brief)

    def test_prior_words_are_passed_as_course_resources(self) -> None:
        plan = normalize_plan(_raw_plan(), _spec())

        spec = plan_section_to_spec(plan, "sec-02")

        vocab_ids = {item["id"] for item in (spec.course_resources or {}).get("vocab", [])}
        self.assertIn("w-merhaba-001", vocab_ids)
        self.assertIn("w-ben-002", vocab_ids)
        self.assertNotIn("w-ekmek-003", vocab_ids)

    def test_single_template_is_preserved(self) -> None:
        plan = normalize_plan(_raw_plan(), _spec())
        plan.sections[0].template_mix = ["listening"]

        spec = plan_section_to_spec(plan, "sec-01")

        self.assertEqual(spec.template, "listening")

    def test_unknown_section_raises(self) -> None:
        plan = normalize_plan(_raw_plan(), _spec())

        with self.assertRaises(KeyError):
            plan_section_to_spec(plan, "sec-99")


class PromptTest(unittest.TestCase):
    def test_prompt_carries_counts_and_no_id_instruction(self) -> None:
        prompt = build_plan_prompt(_spec(section_count=7))

        self.assertIn("章节数：7", prompt)
        self.assertIn("不要 id", prompt)
        self.assertIn("template_mix", prompt)


class GeneratePlanTest(unittest.TestCase):
    @staticmethod
    def _completion(raw: dict) -> dict:
        return {
            "choices": [
                {"message": {"content": json.dumps(raw, ensure_ascii=False)}}
            ]
        }

    def test_generates_and_records_model(self) -> None:
        config = AiApiConfig(model="test-model")
        with patch(
            "src.backend.ai.course_plan.chat_json",
            return_value=self._completion(_raw_plan()),
        ) as chat:
            plan = generate_course_plan(config, _spec(), max_retries=0)

        self.assertEqual([s.section_id for s in plan.sections], ["sec-01", "sec-02"])
        self.assertEqual(plan.model, "test-model")
        chat.assert_called_once()
        self.assertEqual(chat.call_args.kwargs["temperature"], 0.4)

    def test_retries_with_validation_feedback(self) -> None:
        config = AiApiConfig(model="test-model")
        bad = _raw_plan()
        bad["sections"] = bad["sections"][:1]
        calls: list[list[dict]] = []

        def fake(_config, messages, **_kwargs):
            calls.append(messages)
            raw = bad if len(calls) == 1 else _raw_plan()
            return self._completion(raw)

        with patch("src.backend.ai.course_plan.chat_json", side_effect=fake):
            plan = generate_course_plan(config, _spec(), max_retries=1)

        self.assertEqual(len(calls), 2)
        self.assertEqual(len(plan.sections), 2)
        self.assertIn("上次输出未通过校验", calls[1][1]["content"])

    def test_persistent_invalid_output_raises(self) -> None:
        config = AiApiConfig(model="test-model")
        bad = _raw_plan()
        bad["sections"] = bad["sections"][:1]

        with patch(
            "src.backend.ai.course_plan.chat_json",
            return_value=self._completion(bad),
        ), self.assertRaises(RuntimeError):
            generate_course_plan(config, _spec(), max_retries=1)


class PlanStoreTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.store = CoursePlanStore(Path(self.tmp.name))

    def test_save_load_roundtrip(self) -> None:
        plan = normalize_plan(_raw_plan(), _spec())

        plan_id = self.store.save_plan(plan)
        loaded = self.store.load_plan(plan_id)

        self.assertTrue(plan_id)
        self.assertIsNotNone(loaded)
        assert loaded is not None
        self.assertEqual(loaded.title, plan.title)
        self.assertEqual(
            [s.section_id for s in loaded.sections], ["sec-01", "sec-02"]
        )
        self.assertEqual([w.id for w in loaded.lexicon], [w.id for w in plan.lexicon])

    def test_list_summaries(self) -> None:
        plan = normalize_plan(_raw_plan(), _spec())
        self.store.save_plan(plan)

        rows = self.store.list_summaries()

        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["section_count"], 2)
        self.assertEqual(rows[0]["word_count"], 4)

    def test_corrupt_file_returns_none(self) -> None:
        plan = normalize_plan(_raw_plan(), _spec())
        plan_id = self.store.save_plan(plan)
        self.store.plan_file(plan_id).write_text("{not json", encoding="utf-8")

        self.assertIsNone(self.store.load_plan(plan_id))

    def test_delete_only_beneath_base_dir(self) -> None:
        plan = normalize_plan(_raw_plan(), _spec())
        plan_id = self.store.save_plan(plan)

        self.assertFalse(self.store.delete_plan(".."))
        self.assertTrue(self.store.delete_plan(plan_id))
        self.assertFalse(self.store.plan_file(plan_id).exists())

    def test_saved_json_is_human_editable(self) -> None:
        plan = normalize_plan(_raw_plan(), _spec())
        plan_id = self.store.save_plan(plan)

        data = json.loads(self.store.plan_file(plan_id).read_text(encoding="utf-8"))

        self.assertEqual(data["version"], 1)
        self.assertIn("sections", data)
        self.assertIn("lexicon", data)

    def test_progress_and_draft_roundtrip(self) -> None:
        plan = normalize_plan(_raw_plan(), _spec())
        plan.token_budget = 5000
        plan.usage_total = 123
        plan.progress["sec-01"] = {"status": "draft", "usage": 123}
        draft = {"id": "sec-01", "name": "问候", "units": []}

        plan_id = self.store.save_plan(plan)
        self.store.save_draft(plan_id, "sec-01", draft)
        loaded = self.store.load_plan(plan_id)

        assert loaded is not None
        self.assertEqual(loaded.usage_total, 123)
        self.assertEqual(loaded.progress["sec-01"]["status"], "draft")
        self.assertEqual(self.store.load_draft(plan_id, "sec-01"), draft)
        self.assertTrue(self.store.has_draft(plan_id, "sec-01"))
        self.assertTrue(self.store.delete_draft(plan_id, "sec-01"))
        self.assertFalse(self.store.has_draft(plan_id, "sec-01"))

    def test_missing_draft_returns_none(self) -> None:
        plan = normalize_plan(_raw_plan(), _spec())
        plan_id = self.store.save_plan(plan)

        self.assertIsNone(self.store.load_draft(plan_id, "sec-02"))
        self.assertFalse(self.store.delete_draft(plan_id, "sec-02"))


class SectionGenerationTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.store = CoursePlanStore(Path(self.tmp.name))
        self.adapter = _PlanAdapter()
        self.service = CoursePlanService(self.adapter, self.store)
        self.plan = normalize_plan(_raw_plan(), _spec())

    def test_generate_section_uses_grounded_pool(self) -> None:
        seen = {}

        def fake_generate(_config, spec, **kwargs):
            seen["spec"] = spec
            seen["kwargs"] = kwargs
            return SimpleNamespace(draft={"id": "sec-01", "units": []})

        config = AiApiConfig(model="test-model")
        with patch(
            "src.application.course_plan_service.generate_course",
            side_effect=fake_generate,
        ):
            draft = self.service.generate_section(config, self.plan, "sec-01")

        self.assertEqual(draft, {"id": "sec-01", "units": []})
        pool_terms = {item["term"] for item in (seen["spec"].resource_pool or [])}
        self.assertEqual(pool_terms, {"merhaba", "ben"})
        self.assertEqual(seen["spec"].level, "A1")
        self.assertEqual(seen["spec"].unit_count, 2)
        self.assertEqual(seen["kwargs"]["mode"], "fast")
        self.assertTrue(callable(seen["kwargs"]["validator"]))

    def test_generate_section_raises_without_draft(self) -> None:
        config = AiApiConfig(model="test-model")
        with patch(
            "src.application.course_plan_service.generate_course",
            return_value=SimpleNamespace(draft=None, error="boom"),
        ), self.assertRaises(RuntimeError):
            self.service.generate_section(config, self.plan, "sec-01")

    def test_progress_accumulates_usage(self) -> None:
        self.service.mark_progress(
            self.plan, "sec-01", status="draft", usage=40
        )
        self.service.mark_progress(
            self.plan, "sec-02", status="draft", usage=60
        )

        self.assertEqual(self.plan.usage_total, 100)
        self.assertEqual(self.plan.progress["sec-02"]["usage"], 60)


if __name__ == "__main__":
    unittest.main()
