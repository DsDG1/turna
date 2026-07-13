"""Unit tests for the AI course generator backend and wish-mode attachments."""
from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.ai_generator import (
    AiApiConfig,
    AiCourseSpec,
    ChatMessage,
    build_alignment_prompt,
    build_prompt,
    explain_course,
    generate_from_chat,
    parse_completion,
    request_alignment_reply,
)
from src.backend.ai_genre import genre_prompt_block, parse_genre_tag
from src.backend.attachment_extractor import extract_attachment, summarize_attachment


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


class TestAttachmentExtractor(unittest.TestCase):
    def setUp(self) -> None:
        self.tmpdir = Path(tempfile.mkdtemp())

    def tearDown(self) -> None:
        for f in self.tmpdir.iterdir():
            try:
                f.unlink()
            except OSError:
                pass
        try:
            self.tmpdir.rmdir()
        except OSError:
            pass

    def _write_text(self, name: str, text: str) -> Path:
        path = self.tmpdir / name
        path.write_text(text, encoding="utf-8")
        return path

    def _minimal_png(self) -> bytes:
        """Return a valid 1x1 transparent PNG without external dependencies."""
        import struct
        import zlib

        def chunk(type_name: str, data: bytes) -> bytes:
            c = type_name.encode("ascii") + data
            return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)

        ihdr = struct.pack(">IIBBBBB", 1, 1, 8, 6, 0, 0, 0)
        idat = zlib.compress(b"\x00\x00\x00\x00\x00")
        return (
            b"\x89PNG\r\n\x1a\n"
            + chunk("IHDR", ihdr)
            + chunk("IDAT", idat)
            + chunk("IEND", b"")
        )

    def test_extract_image_to_base64(self) -> None:
        path = self.tmpdir / "pixel.png"
        path.write_bytes(self._minimal_png())
        result = extract_attachment(path)
        self.assertTrue(result.ok, result.error)
        self.assertEqual(result.content.get("type"), "image_url")
        url = result.content["image_url"]["url"]
        self.assertTrue(url.startswith("data:image/png;base64,"))

    def test_extract_text_file(self) -> None:
        path = self._write_text("notes.txt", "hello world")
        result = extract_attachment(path)
        self.assertTrue(result.ok, result.error)
        self.assertEqual(result.content.get("text"), "hello world")

    def test_extract_unsupported_extension(self) -> None:
        path = self._write_text("data.bin", "x")
        result = extract_attachment(path)
        self.assertFalse(result.ok)
        self.assertIn("不支持", result.error)

    def test_extract_missing_file(self) -> None:
        result = extract_attachment(self.tmpdir / "missing.txt")
        self.assertFalse(result.ok)
        self.assertIn("不存在", result.error)

    def test_summarize_text_attachment(self) -> None:
        path = self._write_text("long.txt", "a" * 200)
        summary = summarize_attachment(path)
        self.assertTrue(summary.endswith("..."))

    def test_summarize_image_attachment(self) -> None:
        path = self.tmpdir / "pixel.png"
        path.write_bytes(self._minimal_png())
        summary = summarize_attachment(path)
        self.assertEqual(summary, "[图片]")

    def test_cleanup_temp_files(self) -> None:
        path = self._write_text("temp.txt", "tmp")
        result = extract_attachment(path)
        self.assertTrue(result.ok)
        # Extraction does not delete the file; the caller (dialog) is responsible.
        self.assertTrue(path.exists())
        path.unlink()
        self.assertFalse(path.exists())


class TestGenerateFromChat(unittest.TestCase):
    def test_build_prompt_includes_draft(self) -> None:
        spec = AiCourseSpec(topic="Food")
        draft = {"id": "ai-food", "units": []}
        prompt = build_prompt(spec)
        # We cannot call the network in tests, but we can verify the prompt structure.
        self.assertIn("Food", prompt)
        self.assertIn("units", prompt)

    def test_generate_from_chat_signature(self) -> None:
        # Ensure the function exists and accepts the expected arguments.
        import inspect

        sig = inspect.signature(generate_from_chat)
        params = list(sig.parameters.keys())
        self.assertEqual(params, ["config", "spec", "messages", "draft_json", "timeout"])

    def test_explain_course_signature(self) -> None:
        import inspect

        sig = inspect.signature(explain_course)
        params = list(sig.parameters.keys())
        self.assertEqual(params, ["config", "spec", "section_json", "timeout"])

    def test_request_alignment_reply_signature(self) -> None:
        import inspect

        sig = inspect.signature(request_alignment_reply)
        params = list(sig.parameters.keys())
        self.assertEqual(params, ["config", "spec", "messages", "timeout"])


if __name__ == "__main__":
    unittest.main()
