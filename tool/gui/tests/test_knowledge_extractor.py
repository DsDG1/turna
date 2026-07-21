"""Tests for knowledge_prompt + knowledge_extractor's pure parsing logic.

No monkeypatching of request_chat, no network. Covers:
- build_extraction_messages: system/user shape, language + chapter content, truncation.
- build_correction_prompt: error list text.
- _collect_errors: JSON parse + coerce success/failure paths.
"""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path
from unittest import mock

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.knowledge_extractor import (  # noqa: E402
    _collect_errors,
    extract_knowledge_points,
    extract_knowledge_points_windowed,
    merge_window_knowledge,
    reextract_knowledge_targeted,
)
from src.backend.knowledge_prompt import (  # noqa: E402
    _MAX_CHAPTER_CHARS,
    KnowledgePromptLibrary,
    KnowledgePromptTemplates,
    build_correction_prompt,
    build_extraction_messages,
    build_targeted_reextract_messages,
    _truncate_markdown,
)
from src.backend.knowledge_schema import coerce_knowledge_points  # noqa: E402
from src.backend.extraction_quality import QualityIssue  # noqa: E402
from src.backend.markdown_chopper import split_chapters  # noqa: E402
from src.backend.ai_generator import AiApiConfig, AiCancelled  # noqa: E402


def _chapter(title: str = "1 Merhaba", body: str = "merhaba means hello\n") -> "object":
    md = f"## {title}\n{body}"
    return split_chapters(md)[0]


# --------------------------------------------------------------------------- #
# build_extraction_messages
# --------------------------------------------------------------------------- #


class BuildExtractionMessagesTest(unittest.TestCase):
    def test_system_and_user_roles(self) -> None:
        msgs = build_extraction_messages("Turkish", "Chinese", _chapter())
        self.assertEqual([m["role"] for m in msgs], ["system", "user"])

    def test_system_enforces_json_only(self) -> None:
        msgs = build_extraction_messages("Turkish", "Chinese", _chapter())
        self.assertIn("JSON", msgs[0]["content"])

    def test_user_contains_languages_and_chapter(self) -> None:
        ch = _chapter(title="2 Aile", body="aile means family\n")
        msgs = build_extraction_messages("Turkish", "Chinese", ch)
        user = msgs[1]["content"]
        self.assertIn("Turkish", user)
        self.assertIn("Chinese", user)
        self.assertIn("2 Aile", user)
        self.assertIn("aile means family", user)

    def test_user_contains_schema_shape(self) -> None:
        user = build_extraction_messages("Turkish", "Chinese", _chapter())[1]["content"]
        for key in ("words", "expressions", "grammarPoints"):
            self.assertIn(f'"{key}"', user)
        for field in ("term", "translation", "title", "explanation"):
            self.assertIn(field, user)

    def test_user_does_not_request_units(self) -> None:
        user = build_extraction_messages("Turkish", "Chinese", _chapter())[1]["content"]
        # We deliberately avoid the units-bearing shape parse_completion requires.
        self.assertNotIn('"units"', user)

    def test_short_markdown_preserved_intact(self) -> None:
        body = "merhaba means hello\ngünaydın means good morning\n"
        ch = _chapter(body=body)
        user = build_extraction_messages("Turkish", "Chinese", ch)[1]["content"]
        self.assertIn(body.rstrip(), user)
        self.assertNotIn("已截断", user)

    def test_long_markdown_truncated_with_notice(self) -> None:
        body = "x" * (_MAX_CHAPTER_CHARS + 500) + "\n"
        ch = _chapter(body=body)
        user = build_extraction_messages("Turkish", "Chinese", ch)[1]["content"]
        self.assertIn("已截断", user)
        # The full oversized body must NOT be present verbatim.
        self.assertNotIn(body.rstrip(), user)


# --------------------------------------------------------------------------- #
# build_correction_prompt
# --------------------------------------------------------------------------- #


class BuildCorrectionPromptTest(unittest.TestCase):
    def test_lists_each_error(self) -> None:
        prompt = build_correction_prompt(["缺 term", "缺 title"])
        self.assertIn("缺 term", prompt)
        self.assertIn("缺 title", prompt)
        self.assertIn("完整的修正 JSON", prompt)

    def test_empty_errors_still_builds(self) -> None:
        # Defensive: should not crash on an empty list.
        prompt = build_correction_prompt([])
        self.assertIn("JSON", prompt)


# --------------------------------------------------------------------------- #
# _collect_errors (parse + coerce, no network)
# --------------------------------------------------------------------------- #


class CollectErrorsTest(unittest.TestCase):
    def test_valid_extraction_returns_kp_no_errors(self) -> None:
        content = json.dumps(
            {
                "words": [{"term": "merhaba", "translation": "hello"}],
                "expressions": [{"term": "Selam!", "translation": "Hi!"}],
                "grammarPoints": [{"title": "Greetings", "explanation": "hi"}],
            },
            ensure_ascii=False,
        )
        errors, kp = _collect_errors(content, id_prefix="ch-1-merhaba-")
        self.assertEqual(errors, [])
        self.assertIsNotNone(kp)
        assert kp is not None  # for type checker
        self.assertEqual(kp.words[0]["id"], "ch-1-merhaba-w-merhaba")
        self.assertEqual(len(kp.expressions), 1)
        self.assertEqual(len(kp.grammarPoints), 1)

    def test_strips_markdown_fences(self) -> None:
        content = (
            "```json\n"
            + json.dumps({"words": [{"term": "ev", "translation": "house"}]})
            + "\n```"
        )
        errors, kp = _collect_errors(content, id_prefix="")
        self.assertEqual(errors, [])
        self.assertIsNotNone(kp)

    def test_empty_content_is_error(self) -> None:
        errors, kp = _collect_errors("   ", id_prefix="")
        self.assertTrue(errors)
        self.assertIsNone(kp)

    def test_non_json_content_is_error(self) -> None:
        errors, kp = _collect_errors("this is not json at all", id_prefix="")
        self.assertTrue(errors)
        self.assertIsNone(kp)

    def test_word_missing_term_is_error(self) -> None:
        # coerce raises ValueError on word without term -> surfaced as error.
        content = json.dumps({"words": [{"translation": "x"}]})
        errors, kp = _collect_errors(content, id_prefix="")
        self.assertTrue(errors)
        self.assertIsNone(kp)

    def test_grammar_point_missing_title_is_error(self) -> None:
        content = json.dumps({"grammarPoints": [{"explanation": "no title"}]})
        errors, kp = _collect_errors(content, id_prefix="")
        self.assertTrue(errors)
        self.assertIsNone(kp)

    def test_empty_extraction_is_not_error(self) -> None:
        # An all-empty-but-valid object coerces to empty groups; the GUI marks
        # empty chapters to skip. This is success, not an error.
        content = json.dumps({"words": [], "expressions": [], "grammarPoints": []})
        errors, kp = _collect_errors(content, id_prefix="")
        self.assertEqual(errors, [])
        self.assertIsNotNone(kp)
        assert kp is not None
        self.assertEqual(kp.words, [])


# --------------------------------------------------------------------------- #
# paragraph-aware truncation (bookplan2 Phase 5)
# --------------------------------------------------------------------------- #


class TruncationTest(unittest.TestCase):
    def test_short_markdown_unchanged(self) -> None:
        self.assertEqual(_truncate_markdown("short text", 100), "short text")

    def test_hard_cut_when_no_paragraph_boundary(self) -> None:
        body = "x" * 500
        out = _truncate_markdown(body, 100)
        self.assertIn("已截断", out)
        self.assertNotIn("x" * 500, out)
        # Falls back to a hard cut at the cap (no paragraph boundary to honour).
        self.assertTrue(out.startswith("x" * 100))

    def test_cuts_at_paragraph_boundary(self) -> None:
        # Two paragraphs; the boundary sits inside the back half of the window.
        para_a = "a" * 60
        para_b = "b" * 60
        md = f"{para_a}\n\n{para_b}"
        out = _truncate_markdown(md, 80)
        self.assertIn("已截断", out)
        # The first paragraph is preserved intact; the second is dropped at the
        # boundary rather than mid-word.
        self.assertIn(para_a, out)
        self.assertNotIn(para_b, out)

    def test_max_chars_param_overrides_default(self) -> None:
        body = "x" * 1000
        out = _truncate_markdown(body, 200)
        # Hard cut (no boundary) -> 200 chars then notice.
        self.assertTrue(out.startswith("x" * 200))


# --------------------------------------------------------------------------- #
# KnowledgePromptLibrary (bookplan2 Phase 5)
# --------------------------------------------------------------------------- #


class KnowledgePromptLibraryTest(unittest.TestCase):
    def test_default_templates_used_for_unknown_pair(self) -> None:
        lib = KnowledgePromptLibrary()
        tpl = lib.templates_for("Turkish", "Chinese")
        self.assertIn("JSON", tpl.system)
        self.assertIn("words", tpl.schema_block)

    def test_register_override_is_returned_for_pair(self) -> None:
        lib = KnowledgePromptLibrary()
        custom = KnowledgePromptTemplates(system="CUSTOM SYSTEM")
        lib.register("Spanish", "English", custom)
        self.assertEqual(lib.templates_for("Spanish", "English").system, "CUSTOM SYSTEM")
        # Other pairs keep the default.
        self.assertNotEqual(
            lib.templates_for("Turkish", "Chinese").system, "CUSTOM SYSTEM"
        )

    def test_register_is_case_insensitive(self) -> None:
        lib = KnowledgePromptLibrary()
        custom = KnowledgePromptTemplates(intro="Hola")
        lib.register("spanish", "english", custom)
        self.assertEqual(lib.templates_for("Spanish", "English").intro, "Hola")

    def test_override_flows_into_extraction_messages(self) -> None:
        lib = KnowledgePromptLibrary()
        lib.register(
            "Turkish",
            "Chinese",
            KnowledgePromptTemplates(system="TURKISH-ONLY SYSTEM"),
        )
        ch = _chapter()
        msgs = build_extraction_messages("Turkish", "Chinese", ch, library=lib)
        self.assertEqual(msgs[0]["content"], "TURKISH-ONLY SYSTEM")

    def test_max_chars_param_threads_into_truncation(self) -> None:
        body = "y" * 1000
        ch = _chapter(body=body)
        user = build_extraction_messages("Turkish", "Chinese", ch, max_chars=150)[
            1
        ]["content"]
        self.assertIn("已截断", user)

    def test_clear_removes_overrides(self) -> None:
        lib = KnowledgePromptLibrary()
        lib.register("Spanish", "English", KnowledgePromptTemplates(system="X"))
        lib.clear()
        self.assertNotEqual(lib.templates_for("Spanish", "English").system, "X")


# --------------------------------------------------------------------------- #
# extract_knowledge_points (loop integration, 第三枪 批次① P1-3)
# --------------------------------------------------------------------------- #


class ExtractKnowledgePointsLoopTest(unittest.TestCase):
    """第三枪 批次① Step 7: extract_knowledge_points routes through
    generate_with_validate_loop."""

    def _cfg(self) -> AiApiConfig:
        return AiApiConfig(
            base_url="https://api.example.com/v1",
            api_key="sk-x",
            model="m",
        )

    def _body(self, obj: dict) -> dict:
        return {"choices": [{"message": {"content": json.dumps(obj, ensure_ascii=False)}}]}

    def test_successful_first_attempt_no_retry(self) -> None:
        good = {
            "words": [{"term": "merhaba", "translation": "hello"}],
            "expressions": [],
            "grammarPoints": [],
        }
        with mock.patch(
            "src.backend.ai_generator.request_chat",
            return_value=self._body(good),
        ) as m:
            kp = extract_knowledge_points(
                self._cfg(),
                "Turkish",
                "Chinese",
                _chapter(),
            )
        self.assertEqual(m.call_count, 1)
        self.assertEqual(kp.words[0]["term"], "merhaba")

    def test_retry_on_coerce_failure_then_success(self) -> None:
        bad = {"words": [{"translation": "missing-term"}]}  # missing term -> coerce fails
        good = {
            "words": [{"term": "ev", "translation": "house"}],
            "expressions": [],
            "grammarPoints": [],
        }
        responses = [self._body(bad), self._body(good)]
        with mock.patch(
            "src.backend.ai_generator.request_chat",
            side_effect=lambda *a, **k: responses.pop(0),
        ) as m:
            kp = extract_knowledge_points(
                self._cfg(),
                "Turkish",
                "Chinese",
                _chapter(),
                max_retries=2,
            )
        self.assertEqual(m.call_count, 2)
        self.assertEqual(kp.words[0]["term"], "ev")

    def test_retry_exhausted_raises_runtime_error(self) -> None:
        bad = {"words": [{"translation": "missing-term"}]}  # always fails coerce
        with mock.patch(
            "src.backend.ai_generator.request_chat",
            return_value=self._body(bad),
        ):
            with self.assertRaises(RuntimeError) as ctx:
                extract_knowledge_points(
                    self._cfg(),
                    "Turkish",
                    "Chinese",
                    _chapter(),
                    max_retries=1,
                )
        self.assertIn("知识点抽取失败", str(ctx.exception))

    def test_vocab_only_strategy_clears_expressions_and_grammar(self) -> None:
        good = {
            "words": [{"term": "merhaba", "translation": "hello"}],
            "expressions": [{"term": "Selam", "translation": "Hi"}],
            "grammarPoints": [{"title": "Greet", "explanation": "x"}],
        }
        with mock.patch(
            "src.backend.ai_generator.request_chat",
            return_value=self._body(good),
        ):
            kp = extract_knowledge_points(
                self._cfg(),
                "Turkish",
                "Chinese",
                _chapter(),
                strategy="vocab_only",
            )
        self.assertEqual(len(kp.words), 1)
        self.assertEqual(kp.expressions, [])
        self.assertEqual(kp.grammarPoints, [])

    def test_max_tokens_forwarded_to_request_chat(self) -> None:
        good = {"words": [], "expressions": [], "grammarPoints": []}
        with mock.patch(
            "src.backend.ai_generator.request_chat",
            return_value=self._body(good),
        ) as m:
            extract_knowledge_points(
                self._cfg(),
                "Turkish",
                "Chinese",
                _chapter(),
                max_tokens=2048,
            )
        self.assertEqual(m.call_args.kwargs.get("max_tokens"), 2048)

    def test_model_json_routing_applied(self) -> None:
        cfg = AiApiConfig(
            base_url="https://api.example.com/v1",
            api_key="sk-x",
            model="main-m",
            model_json="json-m",
        )
        good = {"words": [], "expressions": [], "grammarPoints": []}
        with mock.patch(
            "src.backend.ai_generator.request_chat",
            return_value=self._body(good),
        ) as m:
            extract_knowledge_points(cfg, "Turkish", "Chinese", _chapter())
        self.assertEqual(m.call_args.kwargs.get("model"), "json-m")

    def test_response_format_is_json_object(self) -> None:
        """Knowledge extraction must force json_object, not the section schema."""
        good = {"words": [], "expressions": [], "grammarPoints": []}
        with mock.patch(
            "src.backend.ai_generator.request_chat",
            return_value=self._body(good),
        ) as m:
            extract_knowledge_points(self._cfg(), "Turkish", "Chinese", _chapter())
        rf = m.call_args.kwargs.get("response_format")
        self.assertEqual(rf, {"type": "json_object"})

    def test_markdown_fenced_response_is_parsed(self) -> None:
        """extract_json_object must strip fences before coerce."""
        body = {
            "choices": [
                {
                    "message": {
                        "content": "```json\n"
                        + json.dumps({"words": [{"term": "ev", "translation": "house"}]})
                        + "\n```"
                    }
                }
            ]
        }
        with mock.patch(
            "src.backend.ai_generator.request_chat",
            return_value=body,
        ):
            kp = extract_knowledge_points(
                self._cfg(),
                "Turkish",
                "Chinese",
                _chapter(),
            )
        self.assertEqual(kp.words[0]["term"], "ev")


# --------------------------------------------------------------------------- #
# merge_window_knowledge (第三枪 批次③ P4-1)
# --------------------------------------------------------------------------- #


class MergeWindowKnowledgeTest(unittest.TestCase):
    def test_dedups_by_normalised_key_and_regenerates_ids(self) -> None:
        w1 = coerce_knowledge_points(
            {
                "words": [
                    {"term": "merhaba", "translation": "hello"},
                    {"term": "ev", "translation": "house"},
                ],
                "grammarPoints": [{"title": "Greetings", "explanation": "x"}],
            },
            id_prefix="ch-1-merhaba#w1-",
        )
        w2 = coerce_knowledge_points(
            {
                "words": [
                    # Same key as w1's first word, different case -> duplicate.
                    {"term": "Merhaba", "translation": "hello"},
                    {"term": "aile", "translation": "family"},
                ],
                # Same normalised title as w1's grammar point -> duplicate.
                "grammarPoints": [{"title": "greetings", "explanation": "y"}],
            },
            id_prefix="ch-1-merhaba#w2-",
        )
        merged = merge_window_knowledge([w1, w2], id_prefix="ch-1-merhaba-")
        self.assertEqual(
            [w["term"] for w in merged.words], ["merhaba", "ev", "aile"]
        )
        # First occurrence wins for the duplicated grammar point.
        self.assertEqual(len(merged.grammarPoints), 1)
        self.assertEqual(merged.grammarPoints[0]["explanation"], "x")
        # Ids are regenerated under the parent chapter prefix, window-free.
        for entry in (*merged.words, *merged.grammarPoints):
            self.assertTrue(entry["id"].startswith("ch-1-merhaba-"))
            self.assertNotIn("#w", entry["id"])

    def test_ids_are_deterministic_across_runs(self) -> None:
        def _build():
            w = coerce_knowledge_points(
                {"words": [{"term": "merhaba", "translation": "hello"}]},
                id_prefix="ch-1-merhaba#w1-",
            )
            return merge_window_knowledge([w], id_prefix="ch-1-merhaba-")

        self.assertEqual(
            _build().words[0]["id"], _build().words[0]["id"]
        )
        self.assertEqual(_build().words[0]["id"], "ch-1-merhaba-w-merhaba")


# --------------------------------------------------------------------------- #
# extract_knowledge_points_windowed (第三枪 批次③ P4-1)
# --------------------------------------------------------------------------- #


class ExtractKnowledgePointsWindowedTest(unittest.TestCase):
    def _cfg(self) -> AiApiConfig:
        return AiApiConfig(
            base_url="https://api.example.com/v1",
            api_key="sk-x",
            model="m",
        )

    def _body(self, obj: dict) -> dict:
        return {"choices": [{"message": {"content": json.dumps(obj, ensure_ascii=False)}}]}

    def _long_chapter(self) -> "object":
        paras = [f"para{i} " + "x" * 50 for i in range(4)]
        return _chapter(body="\n\n".join(paras))

    def test_short_chapter_delegates_to_single_shot(self) -> None:
        good = {"words": [{"term": "merhaba", "translation": "hello"}]}
        with mock.patch(
            "src.backend.ai_generator.request_chat",
            return_value=self._body(good),
        ) as m:
            kp = extract_knowledge_points_windowed(
                self._cfg(),
                "Turkish",
                "Chinese",
                _chapter(),
                max_window_chars=8000,
            )
        self.assertEqual(m.call_count, 1)
        self.assertEqual(kp.words[0]["id"], "ch-1-merhaba-w-merhaba")

    def test_windowing_disabled_uses_single_shot(self) -> None:
        good = {"words": [{"term": "merhaba", "translation": "hello"}]}
        with mock.patch(
            "src.backend.ai_generator.request_chat",
            return_value=self._body(good),
        ) as m:
            extract_knowledge_points_windowed(
                self._cfg(),
                "Turkish",
                "Chinese",
                self._long_chapter(),
                max_window_chars=None,
            )
        self.assertEqual(m.call_count, 1)

    def test_long_chapter_extracts_per_window_and_merges(self) -> None:
        responses = [
            self._body(
                {
                    "words": [
                        {"term": "merhaba", "translation": "hello"},
                        {"term": "ev", "translation": "house"},
                    ]
                }
            ),
            # Overlap seam: "merhaba" re-extracted by the second window.
            self._body(
                {
                    "words": [
                        {"term": "merhaba", "translation": "hello"},
                        {"term": "aile", "translation": "family"},
                    ]
                }
            ),
            self._body({"words": [{"term": "okul", "translation": "school"}]}),
        ]
        with mock.patch(
            "src.backend.ai_generator.request_chat",
            side_effect=lambda *a, **k: responses.pop(0),
        ) as m:
            kp = extract_knowledge_points_windowed(
                self._cfg(),
                "Turkish",
                "Chinese",
                self._long_chapter(),
                max_window_chars=120,
                overlap_chars=0,
            )
        self.assertEqual(m.call_count, 3)
        self.assertEqual(
            [w["term"] for w in kp.words], ["merhaba", "ev", "aile", "okul"]
        )
        for w in kp.words:
            self.assertTrue(w["id"].startswith("ch-1-merhaba-"))
            self.assertNotIn("#w", w["id"])

    def test_single_window_failure_is_tolerated(self) -> None:
        responses: list = [
            self._body({"words": [{"term": "merhaba", "translation": "hello"}]}),
            RuntimeError("window 2 boom"),
            self._body({"words": [{"term": "okul", "translation": "school"}]}),
        ]

        def fake_request(*_a, **_k):
            item = responses.pop(0)
            if isinstance(item, Exception):
                raise item
            return item

        with mock.patch(
            "src.backend.ai_generator.request_chat", side_effect=fake_request
        ):
            kp = extract_knowledge_points_windowed(
                self._cfg(),
                "Turkish",
                "Chinese",
                self._long_chapter(),
                max_window_chars=120,
                overlap_chars=0,
            )
        self.assertEqual([w["term"] for w in kp.words], ["merhaba", "okul"])

    def test_all_windows_failing_raises_runtime_error(self) -> None:
        with mock.patch(
            "src.backend.ai_generator.request_chat",
            side_effect=RuntimeError("boom"),
        ):
            with self.assertRaises(RuntimeError) as ctx:
                extract_knowledge_points_windowed(
                    self._cfg(),
                    "Turkish",
                    "Chinese",
                    self._long_chapter(),
                    max_window_chars=120,
                    overlap_chars=0,
                )
        self.assertIn("知识点抽取失败", str(ctx.exception))

    def test_cancel_propagates_immediately(self) -> None:
        with mock.patch(
            "src.backend.ai_generator.request_chat",
            side_effect=AiCancelled("用户取消了请求。"),
        ):
            with self.assertRaises(AiCancelled):
                extract_knowledge_points_windowed(
                    self._cfg(),
                    "Turkish",
                    "Chinese",
                    self._long_chapter(),
                    max_window_chars=120,
                    overlap_chars=0,
                )

    def test_usage_callback_accumulates_across_windows(self) -> None:
        usages: list[dict[str, int]] = []

        def fake_request(*_args, **kwargs):
            cb = kwargs.get("usage_callback")
            if cb is not None:
                cb({"prompt_tokens": 10, "completion_tokens": 5, "total_tokens": 15})
            return self._body({"words": [{"term": "ev", "translation": "house"}]})

        with mock.patch(
            "src.backend.ai_generator.request_chat", side_effect=fake_request
        ) as m:
            extract_knowledge_points_windowed(
                self._cfg(),
                "Turkish",
                "Chinese",
                self._long_chapter(),
                max_window_chars=120,
                overlap_chars=0,
                usage_callback=usages.append,
            )
        self.assertEqual(len(usages), m.call_count)
        self.assertGreater(len(usages), 1)
        self.assertEqual(sum(u["total_tokens"] for u in usages), 15 * m.call_count)


# --------------------------------------------------------------------------- #
# Built-in language-pair overrides (第三枪 批次③ P4-3)
# --------------------------------------------------------------------------- #


class BuiltinPairOverrideTest(unittest.TestCase):
    def test_turkish_chinese_builtin_pack_hit(self) -> None:
        lib = KnowledgePromptLibrary()
        tpl = lib.templates_for("Turkish", "Chinese")
        self.assertIn("元音和谐", tpl.rules_block)
        self.assertIn("敬语", tpl.rules_block)
        self.assertIn("简体中文", tpl.rules_block)
        # Schema wording is untouched by the pair pack.
        self.assertIn("words", tpl.schema_block)

    def test_unknown_pair_keeps_default_rules(self) -> None:
        lib = KnowledgePromptLibrary()
        tpl = lib.templates_for("Spanish", "English")
        self.assertNotIn("元音和谐", tpl.rules_block)

    def test_builtin_pack_flows_into_extraction_messages(self) -> None:
        lib = KnowledgePromptLibrary()
        user = build_extraction_messages("Turkish", "Chinese", _chapter(), library=lib)[
            1
        ]["content"]
        self.assertIn("元音和谐", user)
        # Other pairs are unaffected.
        user_es = build_extraction_messages(
            "Spanish", "English", _chapter(), library=lib
        )[1]["content"]
        self.assertNotIn("元音和谐", user_es)

    def test_register_wins_over_builtin_pack(self) -> None:
        lib = KnowledgePromptLibrary()
        lib.register(
            "Turkish", "Chinese", KnowledgePromptTemplates(rules_block="CUSTOM")
        )
        self.assertEqual(lib.templates_for("turkish", "chinese").rules_block, "CUSTOM")

    def test_persisted_wins_over_builtin_pack(self) -> None:
        lib = KnowledgePromptLibrary()
        lib.register_persisted(
            "Turkish", "Chinese", KnowledgePromptTemplates(rules_block="PERSISTED")
        )
        self.assertEqual(
            lib.templates_for("Turkish", "Chinese").rules_block, "PERSISTED"
        )


# --------------------------------------------------------------------------- #
# build_targeted_reextract_messages + reextract_knowledge_targeted (P4-4)
# --------------------------------------------------------------------------- #


def _issue(**overrides) -> QualityIssue:
    base = {
        "level": "warning",
        "kind": "lang_check",
        "message": "translation 为空。",
        "chapter_index": 0,
        "resource_type": "word",
        "resource_index": 0,
        "field": "translation",
    }
    base.update(overrides)
    return QualityIssue(**base)


class BuildTargetedReextractMessagesTest(unittest.TestCase):
    def _kp(self):
        return coerce_knowledge_points(
            {"words": [{"term": "merhaba", "translation": ""}]},
            id_prefix="ch-1-merhaba-",
        )

    def test_contains_issues_current_json_and_schema(self) -> None:
        msgs = build_targeted_reextract_messages(
            "Turkish", "Chinese", _chapter(), self._kp(), [_issue()]
        )
        self.assertEqual([m["role"] for m in msgs], ["system", "user"])
        user = msgs[1]["content"]
        self.assertIn("translation 为空。", user)
        self.assertIn("word #0", user)
        self.assertIn("field: translation", user)
        # Current extraction is embedded for correction…
        self.assertIn('"merhaba"', user)
        # …and the full schema is requested back.
        self.assertIn('"grammarPoints"', user)
        self.assertIn("COMPLETE corrected", user)

    def test_issue_without_location_still_builds(self) -> None:
        issue = _issue(
            kind="coverage",
            message="覆盖率偏低。",
            resource_type=None,
            resource_index=None,
            field=None,
        )
        user = build_targeted_reextract_messages(
            "Turkish", "Chinese", _chapter(), self._kp(), [issue]
        )[1]["content"]
        self.assertIn("覆盖率偏低。", user)


class ReextractKnowledgeTargetedTest(unittest.TestCase):
    def _cfg(self) -> AiApiConfig:
        return AiApiConfig(
            base_url="https://api.example.com/v1",
            api_key="sk-x",
            model="m",
        )

    def _body(self, obj: dict) -> dict:
        return {"choices": [{"message": {"content": json.dumps(obj, ensure_ascii=False)}}]}

    def test_replaces_with_corrected_result(self) -> None:
        old = coerce_knowledge_points(
            {"words": [{"term": "merhaba", "translation": ""}]},
            id_prefix="ch-1-merhaba-",
        )
        corrected = {"words": [{"term": "merhaba", "translation": "hello"}]}
        with mock.patch(
            "src.backend.ai_generator.request_chat",
            return_value=self._body(corrected),
        ) as m:
            kp = reextract_knowledge_targeted(
                self._cfg(),
                "Turkish",
                "Chinese",
                _chapter(),
                old,
                [_issue()],
            )
        self.assertEqual(m.call_count, 1)
        self.assertEqual(kp.words[0]["translation"], "hello")
        # Ids keep the deterministic chapter prefix.
        self.assertEqual(kp.words[0]["id"], "ch-1-merhaba-w-merhaba")
        # The issue text reached the model prompt.
        messages = m.call_args.args[1] if len(m.call_args.args) > 1 else None
        if messages is None:
            messages = m.call_args.kwargs.get("messages")
        self.assertIn("translation 为空。", messages[1]["content"])

    def test_retry_exhausted_raises_runtime_error(self) -> None:
        old = coerce_knowledge_points(
            {"words": [{"term": "merhaba", "translation": ""}]},
            id_prefix="ch-1-merhaba-",
        )
        bad = {"words": [{"translation": "missing-term"}]}
        with mock.patch(
            "src.backend.ai_generator.request_chat",
            return_value=self._body(bad),
        ):
            with self.assertRaises(RuntimeError) as ctx:
                reextract_knowledge_targeted(
                    self._cfg(),
                    "Turkish",
                    "Chinese",
                    _chapter(),
                    old,
                    [_issue()],
                    max_retries=1,
                )
        self.assertIn("知识点抽取失败", str(ctx.exception))


if __name__ == "__main__":
    unittest.main()