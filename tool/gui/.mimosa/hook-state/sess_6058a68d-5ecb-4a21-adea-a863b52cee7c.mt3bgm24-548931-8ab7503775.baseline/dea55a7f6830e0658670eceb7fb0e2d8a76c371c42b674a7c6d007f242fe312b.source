"""Unit tests for the SSE streaming parser (src.backend.ai_stream).

Pure-Python, no PySide6 dependency — runnable in the sandbox.
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

from src.backend import ai_stream
from src.backend.ai_generator import AiApiConfig, request_chat


class _FakeStreamResp:
    """Fake urllib response that yields lines when iterated."""

    def __init__(self, lines: list[str]):
        # Each line should already include its trailing newline as bytes.
        self._lines = [
            ln.encode("utf-8") if isinstance(ln, str) else ln for ln in lines
        ]

    def __iter__(self):
        return iter(self._lines)

    def read(self, n: int = -1):
        return b"".join(self._lines)


class TestParseSseLine(unittest.TestCase):
    def test_content_fragment(self) -> None:
        line = 'data: {"choices":[{"delta":{"content":"hello"}}]}'
        self.assertEqual(ai_stream.parse_sse_line(line), "hello")

    def test_empty_delta_skipped(self) -> None:
        # role-only delta (first chunk often has no content).
        line = 'data: {"choices":[{"delta":{"role":"assistant"}}]}'
        self.assertIsNone(ai_stream.parse_sse_line(line))

    def test_done_sentinel(self) -> None:
        self.assertEqual(ai_stream.parse_sse_line("data: [DONE]"), ai_stream.DONE)

    def test_non_data_line_is_none(self) -> None:
        self.assertIsNone(ai_stream.parse_sse_line(": keep-alive"))
        self.assertIsNone(ai_stream.parse_sse_line(""))
        self.assertIsNone(ai_stream.parse_sse_line("event: ping"))

    def test_malformed_json_is_none(self) -> None:
        self.assertIsNone(ai_stream.parse_sse_line("data: {not json"))

    def test_no_choices_is_none(self) -> None:
        line = 'data: {"id":"x"}'
        self.assertIsNone(ai_stream.parse_sse_line(line))


class TestLooksLikeSse(unittest.TestCase):
    def test_first_data_line(self) -> None:
        self.assertTrue(ai_stream.looks_like_sse("data: {"))

    def test_plain_body(self) -> None:
        self.assertFalse(ai_stream.looks_like_sse('{"choices":'))
        self.assertFalse(ai_stream.looks_like_sse(""))


class TestIterSse(unittest.TestCase):
    def test_yields_fragments_in_order(self) -> None:
        resp = _FakeStreamResp([
            'data: {"choices":[{"delta":{"content":"Hel"}}]}\n',
            'data: {"choices":[{"delta":{"content":"lo"}}]}\n',
            "data: [DONE]\n",
        ])
        out = list(ai_stream.iter_sse(resp))
        self.assertEqual(out, ["Hel", "lo", ai_stream.DONE])

    def test_skips_non_content_lines(self) -> None:
        resp = _FakeStreamResp([
            ": ping\n",
            'data: {"choices":[{"delta":{"content":"x"}}]}\n',
            "data: [DONE]\n",
        ])
        out = list(ai_stream.iter_sse(resp))
        self.assertEqual(out, ["x", ai_stream.DONE])

    def test_cancel_mid_stream(self) -> None:
        resp = _FakeStreamResp([
            'data: {"choices":[{"delta":{"content":"a"}}]}\n',
            'data: {"choices":[{"delta":{"content":"b"}}]}\n',
        ])
        gen = ai_stream.iter_sse(resp, cancel_check=lambda: True)
        with self.assertRaises(ai_stream._CancelInterrupt):
            list(gen)

    def test_done_stops_iteration(self) -> None:
        # Content after [DONE] must not be yielded.
        resp = _FakeStreamResp([
            'data: {"choices":[{"delta":{"content":"first"}}]}\n',
            "data: [DONE]\n",
            'data: {"choices":[{"delta":{"content":"after"}}]}\n',
        ])
        out = list(ai_stream.iter_sse(resp))
        self.assertEqual(out, ["first", ai_stream.DONE])


class TestReadAll(unittest.TestCase):
    def test_reads_bytes(self) -> None:
        resp = _FakeStreamResp(["abc"])
        # read_all calls resp.read(); _FakeStreamResp.read returns joined bytes.
        self.assertEqual(ai_stream.read_all(resp), "abc")


class TestParseSseUsage(unittest.TestCase):
    def test_terminal_usage_chunk(self) -> None:
        line = 'data: {"choices": [], "usage": {"prompt_tokens": 11, "completion_tokens": 22, "total_tokens": 33}}'
        self.assertEqual(
            ai_stream.parse_sse_usage(line),
            {"prompt_tokens": 11, "completion_tokens": 22, "total_tokens": 33},
        )

    def test_content_chunk_has_no_usage(self) -> None:
        line = 'data: {"choices":[{"delta":{"content":"hi"}}]}'
        self.assertIsNone(ai_stream.parse_sse_usage(line))

    def test_done_and_garbage(self) -> None:
        self.assertIsNone(ai_stream.parse_sse_usage("data: [DONE]"))
        self.assertIsNone(ai_stream.parse_sse_usage("data: {not json"))
        self.assertIsNone(ai_stream.parse_sse_usage(""))
        self.assertIsNone(ai_stream.parse_sse_usage(": keep-alive"))


class _FakeSseResp:
    """Context-manager urllib-response stand-in yielding byte lines."""

    def __init__(self, lines: list[str]):
        self._lines = [ln.encode("utf-8") for ln in lines]

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False

    def __iter__(self):
        return iter(self._lines)


def _streaming_config() -> AiApiConfig:
    return AiApiConfig(base_url="https://api.openai.com/v1", api_key="k", model="gpt-4o")


class TestStreamingUsage(unittest.TestCase):
    """P0-6: streaming responses must not silently report zero usage."""

    def _request(self, lines: list[str]) -> dict[str, int]:
        captured: dict[str, int] = {}
        chunks: list[str] = []
        with mock.patch(
            "src.backend.ai_generator.urllib.request.urlopen",
            side_effect=lambda *a, **kw: _FakeSseResp(lines),
        ):
            request_chat(
                _streaming_config(),
                messages=[{"role": "user", "content": "讲一讲土耳其语问候语"}],
                stream=True,
                on_chunk=chunks.append,
                usage_callback=lambda u: captured.update(u),
            )
        self.assertTrue(chunks)  # stream path actually engaged
        return captured

    def test_stream_without_usage_gets_estimate(self) -> None:
        usage = self._request([
            'data: {"choices":[{"delta":{"content":"Merhaba"}}]}\n',
            'data: {"choices":[{"delta":{"content":" dünya"}}]}\n',
            "data: [DONE]\n",
        ])
        self.assertGreater(usage["prompt_tokens"], 0)
        self.assertGreater(usage["completion_tokens"], 0)
        self.assertEqual(
            usage["total_tokens"],
            usage["prompt_tokens"] + usage["completion_tokens"],
        )

    def test_stream_with_terminal_usage_uses_real_values(self) -> None:
        usage = self._request([
            'data: {"choices":[{"delta":{"content":"Merhaba"}}]}\n',
            'data: {"choices": [], "usage": {"prompt_tokens": 11, "completion_tokens": 22, "total_tokens": 33}}\n',
            "data: [DONE]\n",
        ])
        self.assertEqual(
            usage,
            {"prompt_tokens": 11, "completion_tokens": 22, "total_tokens": 33},
        )

    def test_non_streaming_usage_untouched(self) -> None:
        captured: dict[str, int] = {}

        class _Resp:
            def __enter__(self):
                return self

            def __exit__(self, *exc):
                return False

            def read(self, n=-1):
                return json.dumps({
                    "choices": [{"message": {"content": "ok"}}],
                    "usage": {"prompt_tokens": 5, "completion_tokens": 7, "total_tokens": 12},
                }).encode("utf-8")

        with mock.patch(
            "src.backend.ai_generator.urllib.request.urlopen",
            side_effect=lambda *a, **kw: _Resp(),
        ):
            request_chat(
                _streaming_config(),
                messages=[{"role": "user", "content": "hi"}],
                usage_callback=lambda u: captured.update(u),
            )
        self.assertEqual(
            captured,
            {"prompt_tokens": 5, "completion_tokens": 7, "total_tokens": 12},
        )


if __name__ == "__main__":
    unittest.main()