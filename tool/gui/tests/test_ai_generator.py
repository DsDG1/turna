"""Unit tests for the AI course generator backend and wish-mode attachments."""
from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.ai_generator import (
    AiApiConfig,
    AiCancelled,
    AiCourseSpec,
    ChatMessage,
    _build_local_regen_instruction,
    _distribute_genres_to_lessons,
    _splice_lesson,
    apply_genre_to_spec,
    build_alignment_prompt,
    build_prompt,
    detect_genre_from_spec,
    explain_course,
    fill_needs_review_resources,
    generate_from_chat,
    generate_with_validate_loop,
    parse_completion,
    regenerate_lesson_in_section,
    regenerate_unit_in_section,
    request_alignment_reply,
    request_chat,
    request_course_with_retry,
    request_item_transform,
    request_lesson_transform,
    structural_diff,
    verify_connection,
)
from src.backend.ai_genre import genre_prompt_block, parse_genre_tag


class TestAiApiConfig(unittest.TestCase):
    def test_is_complete_false_when_empty(self) -> None:
        self.assertFalse(AiApiConfig().is_complete)

    def test_is_complete_true_when_all_set(self) -> None:
        cfg = AiApiConfig(base_url="https://api.openai.com/v1", api_key="sk-x", model="gpt-4o")
        self.assertTrue(cfg.is_complete)

    def test_chat_completions_url_appends_path(self) -> None:
        cfg = AiApiConfig(base_url="https://api.openai.com/v1", api_key="k", model="m")
        self.assertEqual(cfg.chat_completions_url, "https://api.openai.com/v1/chat/completions")

    def test_chat_completions_url_no_double_append(self) -> None:
        cfg = AiApiConfig(
            base_url="https://api.openai.com/v1/chat/completions",
            api_key="k",
            model="m",
        )
        self.assertEqual(
            cfg.chat_completions_url,
            "https://api.openai.com/v1/chat/completions",
        )

    def test_chat_completions_url_strips_trailing_slash(self) -> None:
        cfg = AiApiConfig(base_url="https://api.deepseek.com/v1/", api_key="k", model="m")
        self.assertEqual(cfg.chat_completions_url, "https://api.deepseek.com/v1/chat/completions")

    def test_is_deepseek_true_for_deepseek_host(self) -> None:
        cfg = AiApiConfig(base_url="https://api.deepseek.com", api_key="k", model="m")
        self.assertTrue(cfg.is_deepseek)

    def test_is_deepseek_true_for_subdomain(self) -> None:
        cfg = AiApiConfig(base_url="https://api-cn.deepseek.com/v1", api_key="k", model="m")
        self.assertTrue(cfg.is_deepseek)

    def test_is_deepseek_false_for_non_deepseek_host(self) -> None:
        for url in (
            "https://api.openai.com/v1",
            "https://generativelanguage.googleapis.com/v1",
            "http://localhost:11434/v1",
        ):
            cfg = AiApiConfig(base_url=url, api_key="k", model="m")
            self.assertFalse(cfg.is_deepseek, url)

    def test_reasoning_enabled_falls_back_to_host_check(self) -> None:
        deepseek = AiApiConfig(base_url="https://api.deepseek.com", api_key="k", model="m")
        openai = AiApiConfig(base_url="https://api.openai.com/v1", api_key="k", model="m")
        self.assertTrue(deepseek.reasoning_enabled)
        self.assertFalse(openai.reasoning_enabled)

    def test_reasoning_enabled_honors_explicit_flag(self) -> None:
        # Explicit opt-in on a non-DeepSeek host overrides the host inference.
        forced = AiApiConfig(
            base_url="https://my-proxy.example.com/v1",
            api_key="k",
            model="m",
            supports_reasoning=True,
        )
        # Explicit opt-out on a DeepSeek host overrides the host inference.
        suppressed = AiApiConfig(
            base_url="https://api.deepseek.com",
            api_key="k",
            model="m",
            supports_reasoning=False,
        )
        self.assertTrue(forced.reasoning_enabled)
        self.assertFalse(suppressed.reasoning_enabled)


class TestAiApiConfigAdvanced(unittest.TestCase):
    """第三枪 批次①: dual-model + strict_schema on AiApiConfig."""

    def test_select_model_falls_back_to_model_when_blank(self) -> None:
        cfg = AiApiConfig(base_url="u", api_key="k", model="main-m")
        self.assertEqual(cfg.select_model("chat"), "main-m")
        self.assertEqual(cfg.select_model("json"), "main-m")
        self.assertEqual(cfg.select_model("unknown"), "main-m")

    def test_select_model_uses_specialised_models_when_set(self) -> None:
        cfg = AiApiConfig(
            base_url="u", api_key="k", model="main-m",
            model_chat="chat-m", model_json="json-m",
        )
        self.assertEqual(cfg.select_model("chat"), "chat-m")
        self.assertEqual(cfg.select_model("json"), "json-m")

    def test_select_model_trims_whitespace(self) -> None:
        cfg = AiApiConfig(
            base_url="u", api_key="k", model="main-m",
            model_chat="  ", model_json=" json-m ",
        )
        self.assertEqual(cfg.select_model("chat"), "main-m")
        self.assertEqual(cfg.select_model("json"), "json-m")

    def test_effective_strict_schema_explicit_on_and_off(self) -> None:
        on = AiApiConfig(strict_schema="on")
        off = AiApiConfig(strict_schema="off")
        self.assertEqual(on.effective_strict_schema(), "on")
        self.assertEqual(off.effective_strict_schema(), "off")

    def test_effective_strict_schema_auto_first_call_tries_on(self) -> None:
        auto = AiApiConfig(strict_schema="auto")
        # Probe is None -> first call tries "on"
        self.assertEqual(auto.effective_strict_schema(), "on")

    def test_effective_strict_schema_auto_falls_back_after_mark(self) -> None:
        auto = AiApiConfig(strict_schema="auto")
        auto.mark_json_schema_unsupported()
        self.assertEqual(auto.effective_strict_schema(), "off")

    def test_effective_strict_schema_auto_stays_on_after_success_mark(self) -> None:
        auto = AiApiConfig(strict_schema="auto")
        auto.mark_json_schema_supported()
        self.assertEqual(auto.effective_strict_schema(), "on")
        # Marking unsupported later flips it back off
        auto.mark_json_schema_unsupported()
        self.assertEqual(auto.effective_strict_schema(), "off")

class TestRequestChatReasoningPayload(unittest.TestCase):
    """reasoning_effort/thinking must be DeepSeek-only (mirrors the Dart side).

    Non-DeepSeek OpenAI-compatible endpoints reject unknown payload fields
    (OpenAI returns HTTP 400), so the fields are gated on the endpoint host.
    """

    @staticmethod
    def _capturing_fake(resp_body: str):
        captured: dict[str, object] = {}

        class _FakeResp:
            def __enter__(self):
                return self

            def __exit__(self, *exc):
                return False

            def read(self, n=-1):
                return resp_body.encode("utf-8")

        def _factory(req, *args, **kwargs):
            captured["body"] = json.loads(req.data.decode("utf-8"))
            return _FakeResp()

        return captured, _factory

    def test_deepseek_payload_includes_reasoning_fields(self) -> None:
        from unittest import mock

        captured, factory = self._capturing_fake(
            '{"choices": [{"message": {"content": "ok"}}]}'
        )
        cfg = AiApiConfig(
            base_url="https://api.deepseek.com", api_key="k", model="deepseek-v4-pro"
        )
        with mock.patch("src.backend.ai_generator.urllib.request.urlopen", side_effect=factory):
            request_chat(cfg, messages=[{"role": "user", "content": "hi"}])
        self.assertEqual(captured["body"]["reasoning_effort"], "high")
        self.assertEqual(captured["body"]["thinking"], {"type": "enabled"})

    def test_non_deepseek_payload_omits_reasoning_fields(self) -> None:
        from unittest import mock

        captured, factory = self._capturing_fake(
            '{"choices": [{"message": {"content": "ok"}}]}'
        )
        cfg = AiApiConfig(
            base_url="https://api.openai.com/v1", api_key="k", model="gpt-4o"
        )
        with mock.patch("src.backend.ai_generator.urllib.request.urlopen", side_effect=factory):
            request_chat(cfg, messages=[{"role": "user", "content": "hi"}])
        body = captured["body"]
        self.assertNotIn("reasoning_effort", body)
        self.assertNotIn("thinking", body)

    def test_supports_reasoning_override_sends_fields_on_non_deepseek_host(
        self,
    ) -> None:
        from unittest import mock

        captured, factory = self._capturing_fake(
            '{"choices": [{"message": {"content": "ok"}}]}'
        )
        cfg = AiApiConfig(
            base_url="https://my-proxy.example.com/v1",
            api_key="k",
            model="some-reasoning-model",
            supports_reasoning=True,
        )
        with mock.patch("src.backend.ai_generator.urllib.request.urlopen", side_effect=factory):
            request_chat(cfg, messages=[{"role": "user", "content": "hi"}])
        self.assertEqual(captured["body"]["reasoning_effort"], "high")
        self.assertEqual(captured["body"]["thinking"], {"type": "enabled"})

    def test_supports_reasoning_false_suppresses_fields_on_deepseek_host(
        self,
    ) -> None:
        from unittest import mock

        captured, factory = self._capturing_fake(
            '{"choices": [{"message": {"content": "ok"}}]}'
        )
        cfg = AiApiConfig(
            base_url="https://api.deepseek.com",
            api_key="k",
            model="deepseek-v4-pro",
            supports_reasoning=False,
        )
        with mock.patch("src.backend.ai_generator.urllib.request.urlopen", side_effect=factory):
            request_chat(cfg, messages=[{"role": "user", "content": "hi"}])
        body = captured["body"]
        self.assertNotIn("reasoning_effort", body)
        self.assertNotIn("thinking", body)


class TestParseCompletion(unittest.TestCase):
    def _body(self, content: str) -> str:
        return json.dumps(
            {
                "choices": [
                    {"message": {"role": "assistant", "content": content}}
                ]
            }
        )

    def test_parse_plain_json(self) -> None:
        course = {"id": "ai-x", "name": "X", "units": []}
        parsed = parse_completion(self._body(json.dumps(course)))
        self.assertEqual(parsed["id"], "ai-x")
        self.assertEqual(parsed["units"], [])

    def test_parse_strips_code_fences(self) -> None:
        course = {"id": "ai-y", "name": "Y", "units": [{"id": "u1", "lessons": []}]}
        fenced = f"```json\n{json.dumps(course)}\n```"
        parsed = parse_completion(self._body(fenced))
        self.assertEqual(parsed["id"], "ai-y")

    def test_parse_raises_on_missing_units(self) -> None:
        with self.assertRaises(ValueError):
            parse_completion(self._body(json.dumps({"id": "ai-z", "name": "Z"})))

    def test_parse_raises_on_empty_choices(self) -> None:
        with self.assertRaises(ValueError):
            parse_completion(json.dumps({"choices": []}))

    def test_parse_raises_on_bad_json(self) -> None:
        with self.assertRaises(ValueError):
            parse_completion("not json at all")

    def test_parse_normalizes_missing_resource_arrays(self) -> None:
        course = {"id": "ai-x", "name": "X", "units": []}
        parsed = parse_completion(self._body(json.dumps(course)))
        self.assertEqual(parsed["words"], [])
        self.assertEqual(parsed["expressions"], [])
        self.assertEqual(parsed["grammarPoints"], [])

    def test_parse_accepts_showWord_with_matching_word(self) -> None:
        course = {
            "id": "ai-x",
            "name": "X",
            "words": [{"id": "w-merhaba", "term": "Merhaba", "translation": "你好"}],
            "units": [
                {
                    "id": "u1",
                    "lessons": [
                        {
                            "id": "l1",
                            "content": {
                                "subLessons": [
                                    {
                                        "id": "sl1",
                                        "stages": [
                                            {
                                                "id": "st1",
                                                "items": [
                                                    {
                                                        "runtimeType": "showWord",
                                                        "id": "i1",
                                                        "wordId": "w-merhaba",
                                                    }
                                                ],
                                            }
                                        ],
                                    }
                                ]
                            },
                        }
                    ],
                }
            ],
        }
        parsed = parse_completion(self._body(json.dumps(course)))
        self.assertEqual(len(parsed["words"]), 1)

    def test_parse_auto_fixes_dangling_wordId(self) -> None:
        course = {
            "id": "ai-x",
            "name": "X",
            "words": [],
            "units": [
                {
                    "id": "u1",
                    "lessons": [
                        {
                            "id": "l1",
                            "content": {
                                "stages": [
                                    {
                                        "id": "st1",
                                        "items": [
                                            {
                                                "runtimeType": "showWord",
                                                "id": "i1",
                                                "wordId": "w-missing",
                                                "context": "Merhaba — 你好",
                                            }
                                        ],
                                    }
                                ]
                            },
                        }
                    ],
                }
            ],
        }
        parsed = parse_completion(self._body(json.dumps(course)))
        word_ids = [w["id"] for w in parsed["words"]]
        self.assertIn("w-missing", word_ids)
        stub = next(w for w in parsed["words"] if w["id"] == "w-missing")
        self.assertEqual(stub["term"], "Merhaba")
        self.assertEqual(stub["translation"], "你好")
        self.assertIn("auto-fix", stub.get("tags", []))

    def test_parse_auto_fixes_dangling_expressionId(self) -> None:
        course = {
            "id": "ai-x",
            "name": "X",
            "expressions": [],
            "units": [
                {
                    "id": "u1",
                    "lessons": [
                        {
                            "id": "l1",
                            "content": {
                                "stages": [
                                    {
                                        "id": "st1",
                                        "items": [
                                            {
                                                "runtimeType": "showExpression",
                                                "id": "i1",
                                                "expressionId": "e-missing",
                                            }
                                        ],
                                    }
                                ]
                            },
                        }
                    ],
                }
            ],
        }
        parsed = parse_completion(self._body(json.dumps(course)))
        expr_ids = [e["id"] for e in parsed["expressions"]]
        self.assertIn("e-missing", expr_ids)

    def test_parse_rejects_non_list_words(self) -> None:
        course = {"id": "ai-x", "name": "X", "words": "not a list", "units": []}
        with self.assertRaises(ValueError):
            parse_completion(self._body(json.dumps(course)))


class TestBuildPrompt(unittest.TestCase):
    def test_prompt_contains_topic_and_counts(self) -> None:
        prompt = build_prompt(
            AiCourseSpec(topic="Travel", unit_count=2, lessons_per_unit=4)
        )
        self.assertIn("Travel", prompt)
        self.assertIn("Units: 2", prompt)
        self.assertIn("each with 4 lessons", prompt)

    def test_prompt_includes_extra_instructions(self) -> None:
        prompt = build_prompt(
            AiCourseSpec(topic="Food", extra_instructions="Focus on polite forms.")
        )
        self.assertIn("Focus on polite forms.", prompt)

    def test_prompt_includes_template_schema(self) -> None:
        prompt = build_prompt(AiCourseSpec(template="listening"))
        self.assertIn("listeningPhases", prompt)
        self.assertIn("listenAndPick", prompt)

    def test_prompt_includes_source_language(self) -> None:
        prompt = build_prompt(AiCourseSpec(source_language="Chinese"))
        self.assertIn("Prompt/source language: Chinese", prompt)

    def test_prompt_single_template_mode_no_genre_block(self) -> None:
        prompt = build_prompt(AiCourseSpec(topic="Food", use_genre_batch=False))
        self.assertIn("Template for all lessons", prompt)
        self.assertNotIn(genre_prompt_block(), prompt)

    def test_prompt_genre_batch_mode_includes_genre_block(self) -> None:
        prompt = build_prompt(AiCourseSpec(topic="Food", use_genre_batch=True))
        self.assertIn("可用 genre 标签", prompt)
        self.assertIn("multi-template batch mode", prompt.lower())

    def test_prompt_without_course_resources_unchanged(self) -> None:
        """P0-5 regression guard: no injection → prompt has no reuse block."""
        prompt = build_prompt(AiCourseSpec(topic="Food"))
        self.assertNotIn("课程已有资源", prompt)
        self.assertNotIn("复用规则", prompt)

    def test_prompt_with_course_resources_includes_reuse_block(self) -> None:
        spec = AiCourseSpec(
            topic="Food",
            course_resources={
                "words": [
                    {"id": "w-merhaba", "term": "Merhaba", "translation": "你好"},
                    {"id": "w-ekmek", "term": "ekmek", "translation": "面包"},
                ],
                "expressions": [
                    {"id": "e-selam", "term": "Selam!", "translation": "嗨！"},
                ],
                "grammarPoints": [
                    {"id": "g-plural", "title": "复数", "explanation": "-lar/-ler"},
                ],
            },
        )
        prompt = build_prompt(spec)
        self.assertIn("课程已有资源", prompt)
        self.assertIn("w-merhaba | Merhaba | 你好", prompt)
        self.assertIn("e-selam | Selam! | 嗨！", prompt)
        self.assertIn("g-plural | 复数 | -lar/-ler", prompt)
        self.assertIn("复用规则", prompt)
        self.assertIn("ai- 前缀", prompt)

    def test_prompt_course_resources_empty_lists_omitted(self) -> None:
        spec = AiCourseSpec(
            topic="Food",
            course_resources={"words": [], "expressions": [], "grammarPoints": []},
        )
        prompt = build_prompt(spec)
        # Block header renders but no resource lines; keys with no entries are skipped.
        self.assertNotIn("  words:", prompt)
        self.assertNotIn("  expressions:", prompt)

    def test_grounded_prompt_injects_pool_and_rules(self) -> None:
        spec = AiCourseSpec(
            topic="Greetings",
            design_brief="前两章做 intro，语法单独 review",
            resource_pool=[
                {"id": "ch-1-w-merhaba", "term": "merhaba",
                 "translation": "hello", "tags": ["greeting"], "_kind": "word"},
                {"id": "ch-1-e-selam", "term": "Selam!",
                 "translation": "Hi!", "_kind": "expression"},
            ],
        )
        prompt = build_prompt(spec)
        self.assertIn("资源池", prompt)
        self.assertIn("ch-1-w-merhaba | merhaba | hello", prompt)
        self.assertIn("ch-1-e-selam | Selam! | Hi!", prompt)
        self.assertIn("编排规则", prompt)
        self.assertIn("原样复制", prompt)
        self.assertIn('"new" tag', prompt)
        self.assertIn("前两章做 intro，语法单独 review", prompt)

    def test_grounded_prompt_trims_resource_schema_block(self) -> None:
        spec = AiCourseSpec(
            topic="Greetings",
            resource_pool=[
                {"id": "w-1", "term": "merhaba", "translation": "hello"},
            ],
        )
        prompt = build_prompt(spec)
        self.assertNotIn("顶层资源数组（与 units 同级", prompt)
        # Free mode keeps the full resource schema.
        free = build_prompt(AiCourseSpec(topic="Greetings"))
        self.assertIn("顶层资源数组（与 units 同级", free)
        self.assertIn("输出顺序", free)

    def test_grounded_prompt_pool_truncation_note(self) -> None:
        big_pool = [
            {"id": f"w-{i}", "term": f"term{i}" * 10, "translation": "t" * 20}
            for i in range(1000)
        ]
        prompt = build_prompt(AiCourseSpec(topic="x", resource_pool=big_pool))
        self.assertIn("已按顺序截取", prompt)
        self.assertIn("共 1000 条", prompt)


class TestGenreTagParsing(unittest.TestCase):
    def test_parse_intro_tag(self) -> None:
        self.assertEqual(parse_genre_tag("学习 [intro] 旅行词汇"), "[intro]")

    def test_parse_listening_tag(self) -> None:
        self.assertEqual(parse_genre_tag("[listening] 听力训练"), "[listening]")

    def test_parse_no_tag_returns_none(self) -> None:
        self.assertIsNone(parse_genre_tag("普通主题没有标签"))

    def test_genre_prompt_block_contains_templates(self) -> None:
        block = genre_prompt_block()
        self.assertIn("[intro]", block)
        self.assertIn("[listening]", block)
        self.assertIn("[reading]", block)


class TestBuildAlignmentPrompt(unittest.TestCase):
    def test_contains_level_and_language(self) -> None:
        prompt = build_alignment_prompt(AiCourseSpec(language="Turkish", level="A2"))
        self.assertIn("Turkish", prompt)
        self.assertIn("A2", prompt)

    def test_asks_for_topic_when_empty(self) -> None:
        prompt = build_alignment_prompt(AiCourseSpec(topic=""))
        self.assertIn("not specified yet", prompt)


class TestChatMessage(unittest.TestCase):
    def test_to_api_dict(self) -> None:
        msg = ChatMessage(role="user", content="hello")
        self.assertEqual(msg.to_api_dict(), {"role": "user", "content": "hello"})

    def test_to_api_dict_with_multimodal_content(self) -> None:
        content = [{"type": "text", "text": "hi"}, {"type": "image_url", "image_url": {"url": "data:..."}}]
        msg = ChatMessage(role="user", content=content)
        self.assertEqual(msg.to_api_dict(), {"role": "user", "content": content})


class TestGenerateFromChat(unittest.TestCase):
    def test_generate_from_chat_signature(self) -> None:
        # Ensure the function exists and accepts the expected arguments.
        import inspect

        sig = inspect.signature(generate_from_chat)
        params = list(sig.parameters.keys())
        self.assertEqual(
            params,
            [
                "config",
                "spec",
                "messages",
                "draft_json",
                "timeout",
                "temperature",
                "cancel_check",
                "on_chunk",
                "usage_callback",
                "validator",
                "max_retries",
                "fill_needs_review",
            ],
        )

    def test_explain_course_signature(self) -> None:
        import inspect

        sig = inspect.signature(explain_course)
        params = list(sig.parameters.keys())
        self.assertEqual(params, ["config", "spec", "section_json", "timeout", "temperature", "cancel_check", "on_chunk", "usage_callback"])

    def test_request_alignment_reply_signature(self) -> None:
        import inspect

        sig = inspect.signature(request_alignment_reply)
        params = list(sig.parameters.keys())
        self.assertEqual(params, ["config", "spec", "messages", "timeout", "temperature", "cancel_check", "on_chunk", "usage_callback"])


class TestRequestChatCancel(unittest.TestCase):
    """The cooperative cancel_check should raise AiCancelled mid-read."""

    def _config(self) -> AiApiConfig:
        return AiApiConfig(
            base_url="https://api.example.com/v1",
            api_key="sk-x",
            model="gpt-4o",
        )

    def test_cancel_raises_ai_cancelled(self) -> None:
        from unittest import mock

        class _FakeResp:
            def __enter__(self):
                return self

            def __exit__(self, *exc):
                return False

            def read(self, n=-1):
                # Return a chunk on the first call so the loop iterates and the
                # cancel_check fires on the next iteration.
                return b'{"choices": [{"message": {"content": "x"}}]}'

        with mock.patch("src.backend.ai_generator.urllib.request.urlopen", return_value=_FakeResp()):
            with self.assertRaises(AiCancelled):
                request_chat(
                    self._config(),
                    messages=[{"role": "user", "content": "hi"}],
                    cancel_check=lambda: True,
                )


class TestRequestChatStream(unittest.TestCase):
    """Streaming path: SSE fragments delivered to on_chunk, full body returned."""

    def _config(self) -> AiApiConfig:
        return AiApiConfig(base_url="https://api.example.com/v1", api_key="sk-x", model="gpt-4o")

    @staticmethod
    def _sse_lines(fragments: list[str]) -> list[bytes]:
        lines: list[bytes] = []
        for frag in fragments:
            payload = json.dumps({"choices": [{"delta": {"content": frag}}]})
            lines.append(f"data: {payload}\n".encode("utf-8"))
        lines.append(b"data: [DONE]\n")
        return lines

    def test_stream_delivers_fragments_and_assembles_body(self) -> None:
        from unittest import mock

        lines = self._sse_lines(["Hel", "lo", " world"])
        chunks: list[str] = []
        usage: dict = {}

        class _FakeResp:
            def __enter__(self):
                return self

            def __exit__(self, *exc):
                return False

            def __iter__(self):
                return iter(lines)

            def read(self, n=-1):
                return b""

        with mock.patch("src.backend.ai_generator.urllib.request.urlopen", return_value=_FakeResp()):
            body = request_chat(
                self._config(),
                messages=[{"role": "user", "content": "hi"}],
                stream=True,
                on_chunk=chunks.append,
                usage_callback=usage.update,
            )
        # Fragments were delivered in order to on_chunk.
        self.assertEqual(chunks, ["Hel", "lo", " world"])
        # The returned body has the full assembled content.
        self.assertEqual(body["choices"][0]["message"]["content"], "Hello world")

    def test_stream_usage_callback_invoked(self) -> None:
        from unittest import mock

        # Streaming path currently leaves usage empty (final-chunk usage not
        # parsed per-fragment), so usage_callback still fires with zeros.
        lines = self._sse_lines(["x"])
        usage: dict = {}

        class _FakeResp:
            def __enter__(self):
                return self

            def __exit__(self, *exc):
                return False

            def __iter__(self):
                return iter(lines)

            def read(self, n=-1):
                return b""

        with mock.patch("src.backend.ai_generator.urllib.request.urlopen", return_value=_FakeResp()):
            request_chat(
                self._config(),
                messages=[{"role": "user", "content": "hi"}],
                stream=True,
                on_chunk=lambda _: None,
                usage_callback=usage.update,
            )
        self.assertIn("total_tokens", usage)

    def test_stream_cancel_mid_stream_raises_ai_cancelled(self) -> None:
        from unittest import mock

        lines = self._sse_lines(["a", "b", "c"])

        class _FakeResp:
            def __enter__(self):
                return self

            def __exit__(self, *exc):
                return False

            def __iter__(self):
                return iter(lines)

            def read(self, n=-1):
                return b""

        with mock.patch("src.backend.ai_generator.urllib.request.urlopen", return_value=_FakeResp()):
            with self.assertRaises(AiCancelled):
                request_chat(
                    self._config(),
                    messages=[{"role": "user", "content": "hi"}],
                    stream=True,
                    on_chunk=lambda _: None,
                    cancel_check=lambda: True,
                )

    def test_non_sse_fallback_delivers_bulk_content(self) -> None:
        from unittest import mock

        # Endpoint ignores stream:true and returns a normal buffered body.
        bulk_body = json.dumps({"choices": [{"message": {"content": "bulk"}}], "usage": {"prompt_tokens": 5, "completion_tokens": 3, "total_tokens": 8}})
        chunks: list[str] = []
        usage: dict = {}

        class _FakeResp:
            def __enter__(self):
                return self

            def __exit__(self, *exc):
                return False

            def __iter__(self):
                # First (and only) line is not a data: line -> non-SSE fallback.
                return iter([bulk_body.encode("utf-8")])

            def read(self, n=-1):
                return bulk_body.encode("utf-8")

        with mock.patch("src.backend.ai_generator.urllib.request.urlopen", return_value=_FakeResp()):
            body = request_chat(
                self._config(),
                messages=[{"role": "user", "content": "hi"}],
                stream=True,
                on_chunk=chunks.append,
                usage_callback=usage.update,
            )
        # The whole message content was delivered to on_chunk as one chunk.
        self.assertEqual(chunks, ["bulk"])
        # usage_callback got the real usage from the body.
        self.assertEqual(usage["total_tokens"], 8)
        self.assertEqual(body["choices"][0]["message"]["content"], "bulk")

    def test_stream_flag_not_sent_without_on_chunk(self) -> None:
        from unittest import mock

        captured: dict[str, object] = {}

        class _FakeResp:
            def __enter__(self):
                return self

            def __exit__(self, *exc):
                return False

            def read(self, n=-1):
                return b'{"choices": [{"message": {"content": "ok"}}]}'

        def _factory(req, *args, **kwargs):
            captured["body"] = json.loads(req.data.decode("utf-8"))
            return _FakeResp()

        with mock.patch("src.backend.ai_generator.urllib.request.urlopen", side_effect=_factory):
            request_chat(
                self._config(),
                messages=[{"role": "user", "content": "hi"}],
                stream=True,  # but no on_chunk -> must NOT send stream:true
            )
        self.assertNotIn("stream", captured["body"])


class TestDetectGenreFromSpec(unittest.TestCase):
    def test_detects_single_tag(self) -> None:
        spec = AiCourseSpec(topic="旅行 [intro]", use_genre_batch=True)
        self.assertEqual(detect_genre_from_spec(spec), ["[intro]"])

    def test_detects_multiple_tags_in_order(self) -> None:
        spec = AiCourseSpec(
            topic="[intro] 问候",
            extra_instructions="然后 [listening] 听力",
            use_genre_batch=True,
        )
        self.assertEqual(detect_genre_from_spec(spec), ["[intro]", "[listening]"])

    def test_deduplicates_tags(self) -> None:
        spec = AiCourseSpec(topic="[intro] [intro]", use_genre_batch=True)
        self.assertEqual(detect_genre_from_spec(spec), ["[intro]"])

    def test_no_tags_returns_empty(self) -> None:
        spec = AiCourseSpec(topic="普通主题", use_genre_batch=True)
        self.assertEqual(detect_genre_from_spec(spec), [])


class TestDistributeGenresToLessons(unittest.TestCase):
    def test_no_tags_uses_mixed(self) -> None:
        result = _distribute_genres_to_lessons([], 2, 2)
        self.assertEqual(result, [["mixed", "mixed"], ["mixed", "mixed"]])

    def test_single_tag_used_everywhere(self) -> None:
        result = _distribute_genres_to_lessons(["[intro]"], 2, 2)
        self.assertEqual(result, [["intro", "intro"], ["intro", "intro"]])

    def test_multiple_tags_cycle_per_unit(self) -> None:
        result = _distribute_genres_to_lessons(["[intro]", "[listening]"], 3, 2)
        self.assertEqual(
            result,
            [["intro", "intro"], ["listening", "listening"], ["intro", "intro"]],
        )


class TestApplyGenreToSpec(unittest.TestCase):
    def test_no_genre_batch_returns_spec_unchanged(self) -> None:
        spec = AiCourseSpec(topic="Travel", use_genre_batch=False, template="mixed")
        result = apply_genre_to_spec(spec)
        self.assertIs(result, spec)

    def test_genre_tag_returns_new_spec_with_template(self) -> None:
        # "[practice]" is a recognized genre tag (see ai_genre.GENRE_TEMPLATES).
        spec = AiCourseSpec(
            topic="Travel",
            extra_instructions="[practice]",
            use_genre_batch=True,
            template="mixed",
        )
        result = apply_genre_to_spec(spec)
        self.assertIsNotNone(result)
        # The returned spec is a new instance (no in-place mutation).
        self.assertIsNot(result, spec)
        # And the original spec is left untouched.
        self.assertEqual(spec.template, "mixed")
        # The new template is derived from the genre ("practice"), not "mixed".
        self.assertEqual(result.template, "practice")

    def test_multiple_tags_leave_template_unchanged(self) -> None:
        spec = AiCourseSpec(
            topic="[intro] [listening]",
            use_genre_batch=True,
            template="mixed",
        )
        result = apply_genre_to_spec(spec)
        self.assertEqual(result.template, "mixed")

    def test_does_not_mutate_input_across_calls(self) -> None:
        # Regression: apply_genre_to_spec used to mutate the spec in place, so
        # reusing one spec object with a different genre tag would leak the
        # first tag's template into the second call. Now it returns a new spec.
        spec = AiCourseSpec(
            topic="Travel",
            extra_instructions="[practice]",
            use_genre_batch=True,
            template="mixed",
        )
        first = apply_genre_to_spec(spec)
        self.assertEqual(first.template, "practice")
        # Reuse the same spec object — its template must still be "mixed".
        self.assertEqual(spec.template, "mixed")
        second = apply_genre_to_spec(spec)
        self.assertEqual(second.template, "practice")

    def test_prompt_includes_distribution_for_multiple_tags(self) -> None:
        spec = AiCourseSpec(
            topic="[intro] [listening]",
            use_genre_batch=True,
            unit_count=2,
            lessons_per_unit=2,
            template="mixed",
        )
        prompt = build_prompt(spec)
        self.assertIn("Genre tag distribution", prompt)
        self.assertIn("Unit 1: Lesson 1=intro", prompt)
        self.assertIn("Unit 2: Lesson 1=listening", prompt)


class TestVerifyConnection(unittest.TestCase):
    def test_verify_connection_reports_failure_for_bad_config(self) -> None:
        config = AiApiConfig(base_url="", api_key="", model="")
        result = verify_connection(config, timeout=1.0)
        self.assertFalse(result["ok"])
        self.assertIn("不完整", result["error"])

    def test_verify_connection_ok_when_request_succeeds(self) -> None:
        config = AiApiConfig(
            base_url="https://api.example.com",
            api_key="sk-test",
            model="gpt-test",
        )
        fake_body = {
            "choices": [{"message": {"content": "hi"}}],
            "model": "gpt-test",
            "usage": {"prompt_tokens": 2, "completion_tokens": 1, "total_tokens": 3},
        }
        with mock.patch(
            "src.backend.ai_generator.request_chat", return_value=fake_body
        ) as mock_chat:
            result = verify_connection(config, timeout=1.0)
        self.assertTrue(result["ok"])
        self.assertEqual(result["model"], "gpt-test")
        self.assertEqual(result["usage"]["total_tokens"], 3)
        mock_chat.assert_called_once()
        call_kwargs = mock_chat.call_args.kwargs
        self.assertEqual(call_kwargs["max_tokens"], 1)
        self.assertEqual(call_kwargs["temperature"], 0.0)

    def test_verify_connection_error_when_choices_empty(self) -> None:
        config = AiApiConfig(
            base_url="https://api.example.com",
            api_key="sk-test",
            model="gpt-test",
        )
        with mock.patch(
            "src.backend.ai_generator.request_chat",
            return_value={"choices": [], "model": "gpt-test"},
        ):
            result = verify_connection(config, timeout=1.0)
        self.assertFalse(result["ok"])


class TestRequestTransforms(unittest.TestCase):
    """Tests for request_lesson_transform and request_item_transform."""

    def _chat_config(self) -> AiApiConfig:
        return AiApiConfig(
            base_url="https://api.example.com/v1", api_key="sk-x", model="gpt-4o"
        )

    def _minimal_lesson(self) -> dict:
        return {
            "id": "l-test",
            "name": "Test Lesson",
            "description": "",
            "type": "normal",
            "template": "intro",
            "prerequisiteLessonIds": [],
            "content": {
                "subLessons": [
                    {
                        "id": "sl-1",
                        "name": "SL1",
                        "stages": [
                            {
                                "id": "st-1",
                                "name": "Stage 1",
                                "items": [
                                    {
                                        "runtimeType": "multipleChoice",
                                        "id": "i-1",
                                        "prompt": "Q1",
                                        "options": ["A", "B", "C"],
                                        "correctIndex": 0,
                                        "imageAsset": "",
                                        "grammarPointId": "",
                                    }
                                ],
                            }
                        ],
                    }
                ]
            },
        }

    def test_request_lesson_transform_preserves_identity_and_validates(self) -> None:
        lesson = self._minimal_lesson()
        ai_return = dict(lesson)
        ai_return["name"] = "AI Changed Name"
        ai_return["content"]["subLessons"][0]["name"] = "AI Changed Sub"

        from unittest.mock import patch

        with patch(
            "src.backend.ai_generator.request_chat",
            return_value={
                "choices": [
                    {
                        "message": {
                            "content": json.dumps(ai_return, ensure_ascii=False)
                        }
                    }
                ]
            },
        ):
            result = request_lesson_transform(
                self._chat_config(), lesson, "make it harder"
            )
        # Identity fields are preserved from the original lesson.
        self.assertEqual(result["id"], "l-test")
        self.assertEqual(result["name"], "Test Lesson")
        self.assertEqual(result["template"], "intro")
        # AI-edited content is kept.
        self.assertEqual(result["content"]["subLessons"][0]["name"], "AI Changed Sub")

    def test_request_lesson_transform_raises_on_invalid_content(self) -> None:
        lesson = self._minimal_lesson()
        ai_return = dict(lesson)
        # Remove subLessons so the intro template validation fails.
        ai_return["content"] = {}

        from unittest.mock import patch

        with patch(
            "src.backend.ai_generator.request_chat",
            return_value={
                "choices": [
                    {
                        "message": {
                            "content": json.dumps(ai_return, ensure_ascii=False)
                        }
                    }
                ]
            },
        ):
            with self.assertRaises(ValueError):
                request_lesson_transform(self._chat_config(), lesson, "clear content")

    def test_request_item_transform_preserves_id_and_runtime_type(self) -> None:
        item = {
            "runtimeType": "multipleChoice",
            "id": "i-1",
            "prompt": "Old prompt",
            "options": ["A", "B"],
            "correctIndex": 0,
            "imageAsset": "",
            "grammarPointId": "",
        }
        ai_return = dict(item)
        ai_return["prompt"] = "New prompt"

        from unittest.mock import patch

        with patch(
            "src.backend.ai_generator.request_chat",
            return_value={
                "choices": [
                    {
                        "message": {
                            "content": json.dumps(ai_return, ensure_ascii=False)
                        }
                    }
                ]
            },
        ):
            result = request_item_transform(
                self._chat_config(), item, "rewrite the prompt"
            )
        self.assertEqual(result["id"], "i-1")
        self.assertEqual(result["runtimeType"], "multipleChoice")
        self.assertEqual(result["prompt"], "New prompt")
        # normalize_item fills missing fields with defaults.
        self.assertIn("options", result)

    def test_request_item_transform_rejects_dangling_word_id(self) -> None:
        item = {
            "runtimeType": "showWord",
            "id": "sw-1",
            "wordId": "w-existing",
            "context": "",
            "grammarPointId": "",
            "expressionId": "",
        }
        ai_return = dict(item)
        ai_return["wordId"] = "w-missing"

        from unittest.mock import patch

        with patch(
            "src.backend.ai_generator.request_chat",
            return_value={
                "choices": [
                    {
                        "message": {
                            "content": json.dumps(ai_return, ensure_ascii=False)
                        }
                    }
                ]
            },
        ):
            result = request_item_transform(
                self._chat_config(),
                item,
                "change word",
                vocab_ids={"w-existing"},
            )
        self.assertEqual(result["wordId"], "")


class TestRequestCourseWithRetry(unittest.TestCase):
    """P2.1/B5: request_course_with_retry accepts Problem dicts and retries."""

    def _chat_config(self) -> AiApiConfig:
        return AiApiConfig(
            base_url="https://api.example.com/v1", api_key="sk-x", model="gpt-4o"
        )

    def _spec(self) -> AiCourseSpec:
        return AiCourseSpec(language="Turkish", topic="greetings", level="A1")

    def _body(self, obj: dict) -> dict:
        return {"choices": [{"message": {"content": json.dumps(obj, ensure_ascii=False)}}]}

    def test_request_course_with_retry_fixes_problem_dicts(self) -> None:
        """B5: validator returns Problem dicts; retry must join .message, not the dict."""
        bad = {"id": "s1", "name": "S", "units": []}  # missing units -> error
        good = {"id": "s1", "name": "S", "units": [{"id": "u1", "lessons": []}]}
        responses = [self._body(bad), self._body(good)]

        def validator(section):
            # Real validator shape: list[dict] with level/message, incl. a warning.
            if not section.get("units"):
                return [
                    {"level": "warning", "message": "units 为空，建议补充", "path": ""},
                    {"level": "error", "message": "units 不能为空", "path": "units"},
                ]
            return []

        captured_corrections: list[str] = []

        def fake_request_chat(config, messages, **kwargs):
            # The last user turn is the correction prompt when retrying.
            last = messages[-1]
            if last["role"] == "user" and "校验错误" in last["content"]:
                captured_corrections.append(last["content"])
            return responses.pop(0)

        with mock.patch("src.backend.ai_generator.request_chat", side_effect=fake_request_chat):
            result = request_course_with_retry(
                self._chat_config(), self._spec(), validator, max_retries=1
            )
        # Returned the corrected section.
        self.assertEqual([u["id"] for u in result["units"]], ["u1"])
        # Exactly one retry happened and the correction text used the error
        # message, NOT the dict repr, and excluded the warning.
        self.assertEqual(len(captured_corrections), 1)
        self.assertIn("units 不能为空", captured_corrections[0])
        self.assertNotIn("units 为空", captured_corrections[0])
        self.assertNotIn("{'level'", captured_corrections[0])

    def test_request_course_with_retry_accepts_str_validator(self) -> None:
        """Backward compat: a list[str] validator still works."""
        bad = {"id": "s1", "name": "S", "units": []}
        good = {"id": "s1", "name": "S", "units": [{"id": "u1", "lessons": []}]}
        responses = [self._body(bad), self._body(good)]

        def validator(section):
            return ["units is empty"] if not section.get("units") else []

        with mock.patch(
            "src.backend.ai_generator.request_chat",
            side_effect=lambda *a, **k: responses.pop(0),
        ):
            result = request_course_with_retry(
                self._chat_config(), self._spec(), validator, max_retries=1
            )
        self.assertEqual([u["id"] for u in result["units"]], ["u1"])

    def test_request_course_with_retry_no_errors_no_retry(self) -> None:
        """When validation passes first time, only one request_chat call."""
        good = {"id": "s1", "name": "S", "units": [{"id": "u1", "lessons": []}]}
        calls = {"n": 0}

        def validator(section):
            return []

        def fake_request_chat(*a, **k):
            calls["n"] += 1
            return self._body(good)

        with mock.patch("src.backend.ai_generator.request_chat", side_effect=fake_request_chat):
            result = request_course_with_retry(
                self._chat_config(), self._spec(), validator, max_retries=2
            )
        self.assertEqual(calls["n"], 1)
        self.assertEqual(result["id"], "s1")

    def test_correction_includes_path_when_present(self) -> None:
        bad = {"id": "s1", "name": "S", "units": []}
        good = {"id": "s1", "name": "S", "units": [{"id": "u1", "lessons": []}]}
        responses = [self._body(bad), self._body(good)]
        captured: list[str] = []

        def validator(section):
            if not section.get("units"):
                return [{"level": "error", "message": "units 不能为空", "path": "units"}]
            return []

        def fake_request_chat(config, messages, **kwargs):
            last = messages[-1]
            if last["role"] == "user" and "校验错误" in last["content"]:
                captured.append(last["content"])
            return responses.pop(0)

        with mock.patch("src.backend.ai_generator.request_chat", side_effect=fake_request_chat):
            request_course_with_retry(
                self._chat_config(), self._spec(), validator, max_retries=1
            )
        self.assertEqual(len(captured), 1)
        self.assertIn("units: units 不能为空", captured[0])


class TestGenerateWithValidateLoop(unittest.TestCase):
    def _cfg(self) -> AiApiConfig:
        return AiApiConfig(
            base_url="https://api.example.com/v1", api_key="sk-x", model="gpt-4o"
        )

    def _body(self, obj: dict) -> dict:
        return {"choices": [{"message": {"content": json.dumps(obj, ensure_ascii=False)}}]}

    def test_no_validator_single_shot(self) -> None:
        good = {"id": "s1", "units": []}
        with mock.patch(
            "src.backend.ai_generator.request_chat",
            return_value=self._body(good),
        ) as m:
            result = generate_with_validate_loop(
                self._cfg(),
                [{"role": "user", "content": "x"}],
                None,
                max_retries=3,
            )
        self.assertEqual(result["id"], "s1")
        self.assertEqual(m.call_count, 1)

    def test_max_retries_zero_skips_validate(self) -> None:
        good = {"id": "s1", "units": []}
        calls = {"v": 0}

        def validator(_section):
            calls["v"] += 1
            return ["should not run"]

        with mock.patch(
            "src.backend.ai_generator.request_chat",
            return_value=self._body(good),
        ):
            generate_with_validate_loop(
                self._cfg(),
                [{"role": "user", "content": "x"}],
                validator,
                max_retries=0,
            )
        self.assertEqual(calls["v"], 0)

    def test_retries_until_clean(self) -> None:
        bad = {"id": "s1", "units": []}
        good = {"id": "s1", "units": [{"id": "u1", "lessons": []}]}
        responses = [self._body(bad), self._body(good)]

        def validator(section):
            return ["empty"] if not section.get("units") else []

        with mock.patch(
            "src.backend.ai_generator.request_chat",
            side_effect=lambda *a, **k: responses.pop(0),
        ):
            result = generate_with_validate_loop(
                self._cfg(),
                [{"role": "user", "content": "x"}],
                validator,
                max_retries=2,
            )
        self.assertEqual(result["units"][0]["id"], "u1")


class TestGenerateWithValidateLoopCache(unittest.TestCase):
    """第三枪 批次① Step 4: cache integration in generate_with_validate_loop."""

    def _cfg(self) -> AiApiConfig:
        return AiApiConfig(
            base_url="https://api.example.com/v1", api_key="sk-x", model="gpt-4o"
        )

    def _body(self, obj: dict) -> dict:
        return {"choices": [{"message": {"content": json.dumps(obj, ensure_ascii=False)}}]}

    @staticmethod
    def _passthrough_parse(body: dict) -> dict:
        """Bypass parse_completion's section normalization for cache tests."""
        import json as _json

        content = body["choices"][0]["message"]["content"]
        return _json.loads(content)

    def test_cache_hit_skips_network_no_validator(self) -> None:
        from src.backend.ai_cache import AiCache

        cache = AiCache(maxsize=4, enabled=True)
        good = {"id": "s1", "units": []}
        rf = {"type": "json_object"}
        # Pre-warm the cache
        cache.put("gpt-4o", [{"role": "user", "content": "x"}], rf, good)
        with mock.patch("src.backend.ai_generator.request_chat") as m:
            result = generate_with_validate_loop(
                self._cfg(),
                [{"role": "user", "content": "x"}],
                None,
                max_retries=0,
                cache=cache,
                response_format=rf,
                parse=self._passthrough_parse,
            )
        m.assert_not_called()
        self.assertEqual(result, good)
        self.assertEqual(cache.stats().hits, 1)

    def test_cache_hit_with_validator_passes_skips_network(self) -> None:
        from src.backend.ai_cache import AiCache

        cache = AiCache(maxsize=4, enabled=True)
        good = {"id": "s1", "units": [{"id": "u1", "lessons": []}]}
        rf = {"type": "json_object"}
        cache.put("gpt-4o", [{"role": "user", "content": "x"}], rf, good)

        def validator(section):
            return [] if section.get("units") else ["empty"]

        with mock.patch("src.backend.ai_generator.request_chat") as m:
            result = generate_with_validate_loop(
                self._cfg(),
                [{"role": "user", "content": "x"}],
                validator,
                max_retries=2,
                cache=cache,
                response_format=rf,
                parse=self._passthrough_parse,
            )
        m.assert_not_called()
        self.assertEqual(result["units"][0]["id"], "u1")

    def test_cache_hit_with_invalid_cached_body_falls_through_to_live(self) -> None:
        from src.backend.ai_cache import AiCache

        cache = AiCache(maxsize=4, enabled=True)
        # Cached body fails validator -> must issue live request
        bad_cached = {"id": "s1", "units": []}
        good_live = {"id": "s1", "units": [{"id": "u1", "lessons": []}]}
        rf = {"type": "json_object"}
        cache.put("gpt-4o", [{"role": "user", "content": "x"}], rf, bad_cached)

        def validator(section):
            return [] if section.get("units") else ["empty"]

        with mock.patch(
            "src.backend.ai_generator.request_chat",
            return_value=self._body(good_live),
        ) as m:
            result = generate_with_validate_loop(
                self._cfg(),
                [{"role": "user", "content": "x"}],
                validator,
                max_retries=2,
                cache=cache,
                response_format=rf,
                parse=self._passthrough_parse,
            )
        # Live request was issued because cached body failed validator
        self.assertEqual(m.call_count, 1)
        self.assertEqual(result["units"][0]["id"], "u1")

    def test_cache_writes_back_on_success(self) -> None:
        from src.backend.ai_cache import AiCache

        cache = AiCache(maxsize=4, enabled=True)
        good = {"id": "s1", "units": []}

        with mock.patch(
            "src.backend.ai_generator.request_chat",
            return_value=self._body(good),
        ):
            result = generate_with_validate_loop(
                self._cfg(),
                [{"role": "user", "content": "x"}],
                None,
                max_retries=0,
                cache=cache,
                parse=self._passthrough_parse,
            )
        self.assertEqual(result, good)
        self.assertEqual(cache.stats().entries, 1)
        # Second call should hit cache
        with mock.patch("src.backend.ai_generator.request_chat") as m:
            generate_with_validate_loop(
                self._cfg(),
                [{"role": "user", "content": "x"}],
                None,
                max_retries=0,
                cache=cache,
                parse=self._passthrough_parse,
            )
        m.assert_not_called()
        self.assertEqual(cache.stats().hits, 1)

    def test_cache_does_not_write_invalid_retry_result(self) -> None:
        from src.backend.ai_cache import AiCache

        cache = AiCache(maxsize=4, enabled=True)
        bad = {"id": "s1", "units": []}

        def validator(section):
            return ["always-bad"]

        with mock.patch(
            "src.backend.ai_generator.request_chat",
            return_value=self._body(bad),
        ):
            generate_with_validate_loop(
                self._cfg(),
                [{"role": "user", "content": "x"}],
                validator,
                max_retries=1,
                cache=cache,
                parse=self._passthrough_parse,
            )
        # Invalid result must NOT be cached
        self.assertEqual(cache.stats().entries, 0)

    def test_disabled_cache_falls_through_to_live(self) -> None:
        from src.backend.ai_cache import AiCache

        cache = AiCache(maxsize=4, enabled=False)
        good = {"id": "s1", "units": []}
        with mock.patch(
            "src.backend.ai_generator.request_chat",
            return_value=self._body(good),
        ) as m:
            result = generate_with_validate_loop(
                self._cfg(),
                [{"role": "user", "content": "x"}],
                None,
                max_retries=0,
                cache=cache,
                parse=self._passthrough_parse,
            )
        self.assertEqual(m.call_count, 1)
        self.assertEqual(result, good)
        self.assertEqual(cache.stats().entries, 0)

    def test_model_override_passes_to_request_chat(self) -> None:
        good = {"id": "s1", "units": []}
        with mock.patch(
            "src.backend.ai_generator.request_chat",
            return_value=self._body(good),
        ) as m:
            generate_with_validate_loop(
                self._cfg(),
                [{"role": "user", "content": "x"}],
                None,
                max_retries=0,
                model="json-m",
                parse=self._passthrough_parse,
            )
        # request_chat must be called with the model override
        self.assertEqual(m.call_count, 1)
        kwargs = m.call_args.kwargs
        self.assertEqual(kwargs.get("model"), "json-m")

    def test_cache_uses_model_override_for_key(self) -> None:
        from src.backend.ai_cache import AiCache

        cache = AiCache(maxsize=4, enabled=True)
        good = {"id": "s1", "units": []}
        rf = {"type": "json_object"}
        # Pre-warm with model="json-m"
        cache.put("json-m", [{"role": "user", "content": "x"}], rf, good)
        with mock.patch("src.backend.ai_generator.request_chat") as m:
            result = generate_with_validate_loop(
                self._cfg(),
                [{"role": "user", "content": "x"}],
                None,
                max_retries=0,
                cache=cache,
                model="json-m",
                response_format=rf,
                parse=self._passthrough_parse,
            )
        m.assert_not_called()
        self.assertEqual(result, good)


class TestDualModelRouting(unittest.TestCase):
    """第三枪 批次① Step 5: dual-model routing (model_chat vs model_json)."""

    def _cfg(self, *, model_chat: str = "", model_json: str = "") -> AiApiConfig:
        return AiApiConfig(
            base_url="https://api.example.com/v1",
            api_key="sk-x",
            model="main-m",
            model_chat=model_chat,
            model_json=model_json,
        )

    def _body(self, obj: dict | str) -> dict:
        content = obj if isinstance(obj, str) else json.dumps(obj, ensure_ascii=False)
        return {"choices": [{"message": {"content": content}}]}

    def test_request_alignment_reply_uses_model_chat(self) -> None:
        cfg = self._cfg(model_chat="chat-m")
        with mock.patch(
            "src.backend.ai_generator.request_chat",
            return_value=self._body("hello"),
        ) as m:
            request_alignment_reply(
                cfg,
                AiCourseSpec(
                    topic="t", language="Turkish", source_language="Chinese",
                    level="A1", unit_count=1, lessons_per_unit=1, template="intro",
                ),
                [],
            )
        kwargs = m.call_args.kwargs
        self.assertEqual(kwargs.get("model"), "chat-m")

    def test_explain_course_uses_model_chat(self) -> None:
        cfg = self._cfg(model_chat="chat-m")
        with mock.patch(
            "src.backend.ai_generator.request_chat",
            return_value=self._body("explanation"),
        ) as m:
            explain_course(
                cfg,
                AiCourseSpec(
                    topic="t", language="Turkish", source_language="Chinese",
                    level="A1", unit_count=1, lessons_per_unit=1, template="intro",
                ),
                {"name": "n", "description": "d"},
            )
        kwargs = m.call_args.kwargs
        self.assertEqual(kwargs.get("model"), "chat-m")

    def test_request_course_with_retry_uses_model_json(self) -> None:
        cfg = self._cfg(model_json="json-m")
        good = {"id": "s1", "units": [], "words": [], "expressions": [], "grammarPoints": []}
        with mock.patch(
            "src.backend.ai_generator.request_chat",
            return_value=self._body(good),
        ) as m:
            request_course_with_retry(
                cfg,
                AiCourseSpec(
                    topic="t", language="Turkish", source_language="Chinese",
                    level="A1", unit_count=1, lessons_per_unit=1, template="intro",
                ),
                validator=None,
            )
        kwargs = m.call_args.kwargs
        self.assertEqual(kwargs.get("model"), "json-m")

    def test_dual_model_falls_back_to_main_when_blank(self) -> None:
        cfg = self._cfg()  # both model_chat and model_json empty
        good = {"id": "s1", "units": [], "words": [], "expressions": [], "grammarPoints": []}
        with mock.patch(
            "src.backend.ai_generator.request_chat",
            return_value=self._body(good),
        ) as m:
            request_course_with_retry(
                cfg,
                AiCourseSpec(
                    topic="t", language="Turkish", source_language="Chinese",
                    level="A1", unit_count=1, lessons_per_unit=1, template="intro",
                ),
                validator=None,
            )
        kwargs = m.call_args.kwargs
        self.assertEqual(kwargs.get("model"), "main-m")

    def test_request_correction_uses_model_json(self) -> None:
        from src.backend.ai_generator import request_correction

        cfg = self._cfg(model_json="json-m")
        with mock.patch(
            "src.backend.ai_generator.request_chat",
            return_value=self._body('{"fixed": true}'),
        ) as m:
            request_correction(cfg, "fix this")
        kwargs = m.call_args.kwargs
        self.assertEqual(kwargs.get("model"), "json-m")


class TestBuildResponseFormat(unittest.TestCase):
    """第三枪 批次① Step 6: build_response_format resolution."""

    def test_off_returns_json_object(self) -> None:
        from src.backend.ai_generator import build_response_format

        cfg = AiApiConfig(strict_schema="off")
        self.assertEqual(build_response_format(cfg), {"type": "json_object"})

    def test_on_returns_json_schema(self) -> None:
        from src.backend.ai_generator import build_response_format

        cfg = AiApiConfig(strict_schema="on")
        rf = build_response_format(cfg)
        self.assertEqual(rf["type"], "json_schema")
        self.assertEqual(rf["json_schema"]["name"], "section")
        self.assertTrue(rf["json_schema"]["strict"])
        # Schema must be closed and require all top-level fields
        schema = rf["json_schema"]["schema"]
        self.assertFalse(schema["additionalProperties"])
        self.assertIn("units", schema["required"])
        self.assertIn("words", schema["required"])

    def test_auto_first_call_returns_json_schema(self) -> None:
        from src.backend.ai_generator import build_response_format

        cfg = AiApiConfig(strict_schema="auto")  # probe is None
        rf = build_response_format(cfg)
        self.assertEqual(rf["type"], "json_schema")

    def test_auto_after_unsupported_mark_returns_json_object(self) -> None:
        from src.backend.ai_generator import build_response_format

        cfg = AiApiConfig(strict_schema="auto")
        cfg.mark_json_schema_unsupported()
        self.assertEqual(build_response_format(cfg), {"type": "json_object"})

    def test_auto_after_supported_mark_returns_json_schema(self) -> None:
        from src.backend.ai_generator import build_response_format

        cfg = AiApiConfig(strict_schema="auto")
        cfg.mark_json_schema_supported()
        self.assertEqual(build_response_format(cfg)["type"], "json_schema")

    def test_use_schema_false_forces_json_object(self) -> None:
        from src.backend.ai_generator import build_response_format

        cfg = AiApiConfig(strict_schema="on")
        self.assertEqual(
            build_response_format(cfg, use_schema=False),
            {"type": "json_object"},
        )

    def test_non_section_schema_name_uses_permissive_object_schema(self) -> None:
        from src.backend.ai_generator import build_response_format

        cfg = AiApiConfig(strict_schema="on")
        rf = build_response_format(cfg, schema_name="lesson")
        self.assertEqual(rf["json_schema"]["name"], "lesson")
        # Permissive schema: additionalProperties True (no required list)
        schema = rf["json_schema"]["schema"]
        self.assertTrue(schema["additionalProperties"])
        self.assertNotIn("required", schema)


class TestJsonSchemaRejectionHeuristic(unittest.TestCase):
    """第三枪 批次① Step 6: _looks_like_json_schema_rejection."""

    def _http_error(self, code: int, body: str) -> "urllib.error.HTTPError":
        import urllib.error
        from io import BytesIO

        return urllib.error.HTTPError(
            url="https://x",
            code=code,
            msg="Bad Request",
            hdrs=None,
            fp=BytesIO(body.encode("utf-8")),
        )

    def test_matches_400_with_schema_marker(self) -> None:
        from src.backend.ai_generator import _looks_like_json_schema_rejection

        exc = self._http_error(400, '{"error":"response_format schema unsupported"}')
        self.assertTrue(_looks_like_json_schema_rejection(exc, "response_format schema unsupported"))

    def test_matches_400_with_unknown_field_marker(self) -> None:
        from src.backend.ai_generator import _looks_like_json_schema_rejection

        exc = self._http_error(400, "unknown field: json_schema")
        self.assertTrue(_looks_like_json_schema_rejection(exc, "unknown field: json_schema"))

    def test_does_not_match_400_without_schema_marker(self) -> None:
        from src.backend.ai_generator import _looks_like_json_schema_rejection

        exc = self._http_error(400, "invalid api key")
        self.assertFalse(_looks_like_json_schema_rejection(exc, "invalid api key"))

    def test_does_not_match_500(self) -> None:
        from src.backend.ai_generator import _looks_like_json_schema_rejection

        exc = self._http_error(500, "schema error")
        self.assertFalse(_looks_like_json_schema_rejection(exc, "schema error"))


class TestRequestChatAutoFallback(unittest.TestCase):
    """第三枪 批次① Step 6: request_chat auto-fallback on json_schema rejection."""

    def _make_urlopen_side_effect(self, responses):
        """Build a side_effect that yields HTTPError or returns a context mgr.

        ``responses`` is a list of either:
        - ``("error", HTTPError_instance)`` -> raises the error
        - ``("ok", body_str)`` -> returns a context manager whose read()
          returns body bytes.
        """
        calls = {"i": 0}

        def _side_effect(req, timeout=None):
            i = calls["i"]
            calls["i"] += 1
            if i >= len(responses):
                raise AssertionError(f"unexpected extra urlopen call #{i + 1}")
            kind, payload = responses[i]
            if kind == "error":
                raise payload
            # payload is a body string
            return _FakeResp(payload)

        return _side_effect

    def test_auto_fallback_retries_with_json_object_after_400(self) -> None:
        import urllib.error
        from io import BytesIO

        from src.backend.ai_generator import request_chat

        cfg = AiApiConfig(
            base_url="https://api.example.com/v1",
            api_key="sk-x",
            model="m",
            strict_schema="auto",
        )
        # Probe is None -> first call sends json_schema
        http_err = urllib.error.HTTPError(
            url="https://x",
            code=400,
            msg="Bad Request",
            hdrs=None,
            fp=BytesIO(b'{"error":"response_format schema unsupported"}'),
        )
        ok_body = json.dumps(
            {"choices": [{"message": {"content": '{"x": 1}'}}]}
        )
        side = self._make_urlopen_side_effect([
            ("error", http_err),
            ("ok", ok_body),
        ])
        with mock.patch("urllib.request.urlopen", side_effect=side):
            body = request_chat(
                cfg,
                [{"role": "user", "content": "hi"}],
                response_format={
                    "type": "json_schema",
                    "json_schema": {"name": "section", "schema": {}, "strict": True},
                },
            )
        # Probe must be flipped to False
        self.assertEqual(cfg.effective_strict_schema(), "off")
        # And the call succeeded
        self.assertEqual(body["choices"][0]["message"]["content"], '{"x": 1}')

    def test_on_does_not_fallback_raises_runtime_error(self) -> None:
        import urllib.error
        from io import BytesIO

        from src.backend.ai_generator import request_chat

        cfg = AiApiConfig(
            base_url="https://api.example.com/v1",
            api_key="sk-x",
            model="m",
            strict_schema="on",
        )
        http_err = urllib.error.HTTPError(
            url="https://x",
            code=400,
            msg="Bad Request",
            hdrs=None,
            fp=BytesIO(b'{"error":"response_format schema unsupported"}'),
        )
        with mock.patch("urllib.request.urlopen", side_effect=http_err):
            with self.assertRaises(RuntimeError) as ctx:
                request_chat(
                    cfg,
                    [{"role": "user", "content": "hi"}],
                    response_format={
                        "type": "json_schema",
                        "json_schema": {"name": "section", "schema": {}, "strict": True},
                    },
                )
        self.assertIn("HTTP 400", str(ctx.exception))
        # Probe must NOT be flipped when strict_schema="on"
        self.assertEqual(cfg.effective_strict_schema(), "on")

    def test_non_schema_400_does_not_fallback(self) -> None:
        import urllib.error
        from io import BytesIO

        from src.backend.ai_generator import request_chat

        cfg = AiApiConfig(
            base_url="https://api.example.com/v1",
            api_key="sk-x",
            model="m",
            strict_schema="auto",
        )
        http_err = urllib.error.HTTPError(
            url="https://x",
            code=400,
            msg="Bad Request",
            hdrs=None,
            fp=BytesIO(b'{"error":"invalid api key"}'),
        )
        with mock.patch("urllib.request.urlopen", side_effect=http_err):
            with self.assertRaises(RuntimeError):
                request_chat(
                    cfg,
                    [{"role": "user", "content": "hi"}],
                    response_format={
                        "type": "json_schema",
                        "json_schema": {"name": "section", "schema": {}, "strict": True},
                    },
                )
        # Probe untouched (still None -> "on")
        self.assertEqual(cfg.effective_strict_schema(), "on")


class _FakeResp:
    """Minimal context-manager mock for urlopen's return value."""

    def __init__(self, body: str) -> None:
        self._body = body.encode("utf-8")

    def __enter__(self) -> "_FakeResp":
        return self

    def __exit__(self, *args) -> None:
        return None

    def read(self, n: int | None = None) -> bytes:
        if n is None:
            return self._body
        out = self._body[:n]
        self._body = self._body[n:]
        return out


class TestFillNeedsReviewResources(unittest.TestCase):
    def _cfg(self) -> AiApiConfig:
        return AiApiConfig(
            base_url="https://api.example.com/v1", api_key="sk-x", model="gpt-4o"
        )

    def test_no_targets_no_request(self) -> None:
        section = {
            "id": "s",
            "words": [{"id": "w1", "term": "a", "translation": "b", "tags": []}],
            "units": [],
        }
        with mock.patch("src.backend.ai_generator.request_chat") as m:
            out = fill_needs_review_resources(self._cfg(), section)
        m.assert_not_called()
        self.assertEqual(out["words"][0]["translation"], "b")

    def test_fills_placeholder(self) -> None:
        section = {
            "id": "s",
            "words": [
                {
                    "id": "w-missing",
                    "term": "merhaba",
                    "translation": "[待补]",
                    "tags": ["auto-fix", "needs-review"],
                }
            ],
            "units": [],
        }
        reply = {
            "choices": [
                {
                    "message": {
                        "content": json.dumps(
                            {
                                "entries": [
                                    {
                                        "id": "w-missing",
                                        "term": "Merhaba",
                                        "translation": "你好",
                                    }
                                ]
                            },
                            ensure_ascii=False,
                        )
                    }
                }
            ]
        }
        with mock.patch("src.backend.ai_generator.request_chat", return_value=reply):
            out = fill_needs_review_resources(self._cfg(), section)
        w = out["words"][0]
        self.assertEqual(w["translation"], "你好")
        self.assertEqual(w["term"], "Merhaba")
        self.assertNotIn("needs-review", w.get("tags", []))
        self.assertNotIn("auto-fix", w.get("tags", []))

    def test_request_failure_keeps_section(self) -> None:
        section = {
            "id": "s",
            "words": [
                {
                    "id": "w-missing",
                    "term": "x",
                    "translation": "[待补]",
                    "tags": ["needs-review"],
                }
            ],
            "units": [],
        }
        with mock.patch(
            "src.backend.ai_generator.request_chat",
            side_effect=RuntimeError("network"),
        ):
            out = fill_needs_review_resources(self._cfg(), section)
        self.assertEqual(out["words"][0]["translation"], "[待补]")

    def test_course_retry_opt_in_fill(self) -> None:
        good = {
            "id": "s1",
            "name": "S",
            "words": [
                {
                    "id": "w1",
                    "term": "a",
                    "translation": "[待补]",
                    "tags": ["needs-review"],
                }
            ],
            "units": [{"id": "u1", "lessons": []}],
        }
        fill_reply = {
            "choices": [
                {
                    "message": {
                        "content": json.dumps(
                            {
                                "entries": [
                                    {"id": "w1", "term": "A", "translation": "译"}
                                ]
                            },
                            ensure_ascii=False,
                        )
                    }
                }
            ]
        }
        bodies = [
            {"choices": [{"message": {"content": json.dumps(good, ensure_ascii=False)}}]},
            fill_reply,
        ]

        def fake_request_chat(*a, **k):
            return bodies.pop(0)

        with mock.patch(
            "src.backend.ai_generator.request_chat", side_effect=fake_request_chat
        ):
            result = request_course_with_retry(
                AiApiConfig(
                    base_url="https://api.example.com/v1",
                    api_key="sk-x",
                    model="gpt-4o",
                ),
                AiCourseSpec(language="Turkish", topic="t", level="A1"),
                lambda _s: [],
                max_retries=0,
                fill_needs_review=True,
            )
        self.assertEqual(result["words"][0]["translation"], "译")


class TestStructuralDiff(unittest.TestCase):
    """P2.4/B3: structural_diff detects silent AI removals."""

    def _section(self, unit_ids, lesson_ids_by_unit, words=None, expressions=None):
        units = []
        for uid in unit_ids:
            units.append(
                {
                    "id": uid,
                    "lessons": [{"id": lid, "content": {}} for lid in lesson_ids_by_unit.get(uid, [])],
                }
            )
        return {
            "id": "s1",
            "units": units,
            "words": [{"id": w} for w in (words or [])],
            "expressions": [{"id": e} for e in (expressions or [])],
        }

    def test_structural_diff_detects_removed_units_lessons(self) -> None:
        existing = self._section(["u1", "u2"], {"u1": ["l1", "l2"], "u2": ["l3"]})
        parsed = self._section(["u1"], {"u1": ["l1"]})  # dropped u2 + l2 + l3
        diff = structural_diff(existing, parsed)
        self.assertEqual(diff["removed_units"], {"u2"})
        self.assertEqual(diff["removed_lessons"], {"l2", "l3"})

    def test_structural_diff_no_removals_empty(self) -> None:
        existing = self._section(["u1"], {"u1": ["l1"]}, words=["w1"])
        # rename + add: u1 kept, l1 kept, w1 kept, add l2/w2
        parsed = self._section(["u1"], {"u1": ["l1", "l2"]}, words=["w1", "w2"])
        diff = structural_diff(existing, parsed)
        self.assertFalse(any(diff.values()))

    def test_structural_diff_removed_words_expressions(self) -> None:
        existing = self._section(
            ["u1"], {"u1": ["l1"]}, words=["w1", "w2"], expressions=["e1"]
        )
        parsed = self._section(["u1"], {"u1": ["l1"]}, words=["w1"])  # dropped w2, e1
        diff = structural_diff(existing, parsed)
        self.assertEqual(diff["removed_words"], {"w2"})
        self.assertEqual(diff["removed_expressions"], {"e1"})
        self.assertEqual(diff["removed_grammar"], set())


class TestSpliceAndRegenerate(unittest.TestCase):
    """P2.3/C5: local regeneration splices a single lesson back."""

    def _chat_config(self) -> AiApiConfig:
        return AiApiConfig(
            base_url="https://api.example.com/v1", api_key="sk-x", model="gpt-4o"
        )

    def _section_with_lessons(self, lessons):
        return {
            "id": "s1",
            "units": [
                {"id": "u1", "lessons": lessons},
            ],
        }

    def _minimal_lesson(self, lid="l1"):
        return {
            "id": lid,
            "name": "Lesson " + lid,
            "description": "",
            "type": "normal",
            "template": "intro",
            "prerequisiteLessonIds": [],
            "content": {
                "subLessons": [
                    {
                        "id": "sl-1",
                        "name": "SL1",
                        "stages": [
                            {
                                "id": "st-1",
                                "name": "Stage 1",
                                "items": [
                                    {
                                        "runtimeType": "multipleChoice",
                                        "id": "i-1",
                                        "prompt": "Q1",
                                        "options": ["A", "B", "C"],
                                        "correctIndex": 0,
                                        "imageAsset": "",
                                        "grammarPointId": "",
                                    }
                                ],
                            }
                        ],
                    }
                ]
            },
        }

    def test_splice_lesson_replaces_by_id(self) -> None:
        section = self._section_with_lessons(
            [self._minimal_lesson("l1"), self._minimal_lesson("l2")]
        )
        new_l1 = self._minimal_lesson("l1")
        new_l1["name"] = "Replaced"
        result = _splice_lesson(section, "l1", new_l1)
        ids = [lesson["id"] for lesson in result["units"][0]["lessons"]]
        self.assertEqual(ids, ["l1", "l2"])
        replaced = result["units"][0]["lessons"][0]
        self.assertEqual(replaced["name"], "Replaced")
        # Original section untouched (deep copy).
        self.assertEqual(section["units"][0]["lessons"][0]["name"], "Lesson l1")

    def test_splice_lesson_appends_when_missing(self) -> None:
        section = self._section_with_lessons([self._minimal_lesson("l1")])
        new_l9 = self._minimal_lesson("l9")
        result = _splice_lesson(section, "l9", new_l9)
        ids = [lesson["id"] for lesson in result["units"][0]["lessons"]]
        self.assertEqual(ids, ["l1", "l9"])

    def test_regenerate_lesson_in_section_splices(self) -> None:
        section = self._section_with_lessons(
            [self._minimal_lesson("l1"), self._minimal_lesson("l2")]
        )
        ai_lesson = self._minimal_lesson("l1")
        ai_lesson["content"]["subLessons"][0]["name"] = "AI Changed"

        sent_lessons = []

        def fake_request_chat(config, messages, **kwargs):
            # Capture the lesson sent to the model: it must be ONLY l1.
            content = messages[-1]["content"]
            sent_lessons.append(content)
            return {"choices": [{"message": {"content": json.dumps(ai_lesson, ensure_ascii=False)}}]}

        with mock.patch("src.backend.ai_generator.request_chat", side_effect=fake_request_chat):
            result = regenerate_lesson_in_section(
                self._chat_config(),
                AiCourseSpec(language="Turkish", topic="greetings", level="A1"),
                section,
                "l1",
            )
        # l1's content replaced (sublesson name kept from AI), l2 preserved.
        l1 = next(l for l in result["units"][0]["lessons"] if l["id"] == "l1")
        l2 = next(l for l in result["units"][0]["lessons"] if l["id"] == "l2")
        self.assertEqual(l1["content"]["subLessons"][0]["name"], "AI Changed")
        self.assertEqual(l2["content"]["subLessons"][0]["name"], "SL1")
        # request_lesson_transform preserves identity fields from the original.
        self.assertEqual(l1["id"], "l1")
        # Only one request, and the prompt carried the single lesson (not l2).
        self.assertEqual(len(sent_lessons), 1)
        self.assertIn("l1", sent_lessons[0])
        self.assertNotIn("Lesson l2", sent_lessons[0])

    def test_regenerate_lesson_in_section_missing_raises(self) -> None:
        section = self._section_with_lessons([self._minimal_lesson("l1")])
        with self.assertRaises(ValueError):
            regenerate_lesson_in_section(
                self._chat_config(),
                AiCourseSpec(language="Turkish", topic="t", level="A1"),
                section,
                "nope",
            )

    def test_regenerate_unit_in_section_iterates_lessons(self) -> None:
        section = self._section_with_lessons(
            [self._minimal_lesson("l1"), self._minimal_lesson("l2")]
        )

        def make_response(messages, **kwargs):
            # Echo back the lesson unchanged but mark its sublesson name.
            content = messages[-1]["content"]
            # The lesson JSON is embedded in the prompt; just return a tweaked
            # copy derived from whichever lesson id appears.
            for lid in ("l1", "l2"):
                if f'"{lid}"' in content:
                    out = self._minimal_lesson(lid)
                    out["content"]["subLessons"][0]["name"] = f"AI-{lid}"
                    return {"choices": [{"message": {"content": json.dumps(out, ensure_ascii=False)}}]}
            raise AssertionError("no lesson id found in prompt")

        call_count = {"n": 0}

        def fake_request_chat(config, messages, **kwargs):
            call_count["n"] += 1
            return make_response(messages, **kwargs)

        with mock.patch("src.backend.ai_generator.request_chat", side_effect=fake_request_chat):
            result = regenerate_unit_in_section(
                self._chat_config(),
                AiCourseSpec(language="Turkish", topic="t", level="A1"),
                section,
                "u1",
            )
        # Two lessons -> two requests, both spliced.
        self.assertEqual(call_count["n"], 2)
        names = [lesson["content"]["subLessons"][0]["name"] for lesson in result["units"][0]["lessons"]]
        self.assertEqual(names, ["AI-l1", "AI-l2"])


class TestBuildLocalRegenInstruction(unittest.TestCase):
    """P2.3: instruction builder is a pure function of the spec."""

    def test_includes_topic_and_extra(self) -> None:
        spec = AiCourseSpec(language="Turkish", topic="greetings", level="A1", extra_instructions="add audio")
        instr = _build_local_regen_instruction(spec, "重写该课时")
        self.assertIn("重写该课时", instr)
        self.assertIn("greetings", instr)
        self.assertIn("add audio", instr)

    def test_minimal_when_empty(self) -> None:
        spec = AiCourseSpec(language="Turkish", topic="", level="A1")
        instr = _build_local_regen_instruction(spec, "重写该单元内的课时")
        self.assertIn("重写该单元内的课时", instr)


class TestAutoFixStubQuality(unittest.TestCase):
    """P2.5/B4: stub words never carry an empty translation."""

    def _body(self, content: str) -> str:
        return json.dumps({"choices": [{"message": {"content": content}}]})

    def _section_with_showword(self, item_extra):
        item = {"runtimeType": "showWord", "id": "i1", "wordId": "w-missing"}
        item.update(item_extra)
        return {
            "id": "ai-x",
            "name": "X",
            "words": [],
            "units": [
                {
                    "id": "u1",
                    "lessons": [
                        {
                            "id": "l1",
                            "content": {"stages": [{"id": "st1", "items": [item]}]},
                        }
                    ],
                }
            ],
        }

    def test_auto_fix_stub_no_emdash_uses_placeholder_translation(self) -> None:
        course = self._section_with_showword({"context": "merhaba"})  # no em-dash
        parsed = parse_completion(self._body(json.dumps(course)))
        stub = next(w for w in parsed["words"] if w["id"] == "w-missing")
        self.assertEqual(stub["term"], "merhaba")
        self.assertEqual(stub["translation"], "[待补]")
        self.assertIn("needs-review", stub.get("tags", []))

    def test_auto_fix_stub_uses_expected_when_no_context(self) -> None:
        course = self._section_with_showword({"expected": "merhaba", "expectedAnswer": "hello"})
        parsed = parse_completion(self._body(json.dumps(course)))
        stub = next(w for w in parsed["words"] if w["id"] == "w-missing")
        self.assertEqual(stub["term"], "merhaba")
        self.assertEqual(stub["translation"], "hello")
        self.assertIn("needs-review", stub.get("tags", []))

    def test_auto_fix_stub_emdash_path_unchanged(self) -> None:
        course = self._section_with_showword({"context": "Merhaba — 你好"})
        parsed = parse_completion(self._body(json.dumps(course)))
        stub = next(w for w in parsed["words"] if w["id"] == "w-missing")
        self.assertEqual(stub["term"], "Merhaba")
        self.assertEqual(stub["translation"], "你好")
        # Happy path no longer degrades to the placeholder.
        self.assertNotEqual(stub["translation"], "[待补]")

    def test_auto_fix_expression_placeholder_when_empty(self) -> None:
        course = {
            "id": "ai-x",
            "name": "X",
            "expressions": [],
            "units": [
                {
                    "id": "u1",
                    "lessons": [
                        {
                            "id": "l1",
                            "content": {
                                "stages": [
                                    {
                                        "id": "st1",
                                        "items": [
                                            {
                                                "runtimeType": "showExpression",
                                                "id": "i1",
                                                "expressionId": "e-missing",
                                            }
                                        ],
                                    }
                                ]
                            },
                        }
                    ],
                }
            ],
        }
        parsed = parse_completion(self._body(json.dumps(course)))
        stub = next(e for e in parsed["expressions"] if e["id"] == "e-missing")
        self.assertEqual(stub["translation"], "[待补]")
        self.assertIn("needs-review", stub.get("tags", []))


if __name__ == "__main__":
    unittest.main()
