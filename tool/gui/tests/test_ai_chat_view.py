"""Unit tests for the pure chat-rendering helpers (no PySide6 widgets needed)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.dialogs.ai.chat_view import (
    DEFAULT_PALETTE,
    ai_bubble_html,
    escape_html,
    format_message_content,
    render_chat_html,
    render_streaming_html,
    user_bubble_html,
    welcome_html,
)


PAL = DEFAULT_PALETTE


class _Msg:
    def __init__(self, role, content, timestamp=""):
        self.role = role
        self.content = content
        self.timestamp = timestamp


class TestEscapeHtml(unittest.TestCase):
    def test_escapes_special_chars_and_newlines(self) -> None:
        self.assertEqual(escape_html("a & <b> c\nd"), "a &amp; &lt;b&gt; c<br>d")

    def test_empty_string(self) -> None:
        self.assertEqual(escape_html(""), "")


class TestFormatMessageContent(unittest.TestCase):
    def test_string_passthrough(self) -> None:
        self.assertEqual(format_message_content("hello"), "hello")

    def test_text_and_image_pieces(self) -> None:
        content = [
            {"type": "text", "text": "look"},
            {"type": "image_url", "image_url": "x"},
            {"type": "text", "text": "here"},
        ]
        self.assertEqual(format_message_content(content), "look\n[图片]\nhere")

    def test_empty_list(self) -> None:
        self.assertEqual(format_message_content([]), "")


class TestBubbles(unittest.TestCase):
    def test_user_bubble_uses_palette_color_and_escapes(self) -> None:
        html = user_bubble_html("hi <b>", "09:00", PAL)
        self.assertIn(PAL["ai_user_bubble"], html)
        self.assertIn("hi &lt;b&gt;", html)
        self.assertIn("09:00", html)

    def test_ai_bubble_uses_palette_colors_and_escapes(self) -> None:
        html = ai_bubble_html("yo & me", "09:01", PAL)
        self.assertIn(PAL["ai_bubble_bg"], html)
        self.assertIn(PAL["text"], html)
        self.assertIn("yo &amp; me", html)
        self.assertIn("AI · 09:01", html)

    def test_no_timestamp_omits_ts_block(self) -> None:
        html = user_bubble_html("hi", "", PAL)
        self.assertNotIn("font-size: 10px", html)


class TestRenderChatHtml(unittest.TestCase):
    def test_empty_messages_shows_welcome(self) -> None:
        html = render_chat_html([], PAL)
        self.assertIn(welcome_html(PAL), html)

    def test_mixed_messages_preserve_order(self) -> None:
        msgs = [
            _Msg("user", "first"),
            _Msg("assistant", "second"),
            _Msg("user", "third"),
        ]
        html = render_chat_html(msgs, PAL)
        i_first = html.index("first")
        i_second = html.index("second")
        i_third = html.index("third")
        self.assertLess(i_first, i_second)
        self.assertLess(i_second, i_third)


class TestRenderStreamingHtml(unittest.TestCase):
    def test_appends_partial_ai_bubble(self) -> None:
        msgs = [_Msg("user", "q")]
        html = render_streaming_html(msgs, "partial answer", PAL)
        self.assertIn("partial answer", html)
        # The partial text must come after the user message.
        self.assertLess(html.index("q"), html.index("partial answer"))


class ChatViewStreamingFastPathTest(unittest.TestCase):
    """Widget-level: throttled flushes must not re-parse the whole history."""

    def setUp(self) -> None:
        from tests._qtapp import _App

        _App.get()
        from src.dialogs.ai.chat_view import ChatView

        self.view = ChatView()

    def _count_sethtml(self) -> tuple[list, object]:
        calls: list[str] = []
        orig = self.view.setHtml

        def _counting(html: str) -> None:
            calls.append(html)
            orig(html)

        self.view.setHtml = _counting
        return calls, orig

    def test_repeated_flushes_render_history_once(self) -> None:
        msgs = [_Msg("user", "q1"), _Msg("assistant", "a1")]
        self.view.render(msgs)
        calls, _orig = self._count_sethtml()
        self.view.render_streaming(msgs, "partial 1")
        self.view.render_streaming(msgs, "partial 2 longer")
        self.view.render_streaming(msgs, "partial 3 even longer")
        # Only the first flush lays out the document; later ones rewrite the
        # in-flight bubble via cursor selection instead of setHtml.
        self.assertEqual(len(calls), 1)
        text = self.view.toPlainText()
        self.assertIn("a1", text)
        self.assertIn("partial 3 even longer", text)

    def test_history_change_triggers_full_relayout(self) -> None:
        msgs = [_Msg("user", "q1")]
        self.view.render(msgs)
        self.view.render_streaming(msgs, "p1")
        msgs2 = [
            _Msg("user", "q1"),
            _Msg("assistant", "a1"),
            _Msg("user", "q2"),
        ]
        calls, _orig = self._count_sethtml()
        self.view.render_streaming(msgs2, "p3")
        self.assertEqual(len(calls), 1)
        text = self.view.toPlainText()
        for expected in ("a1", "q2", "p3"):
            self.assertIn(expected, text)
        self.assertNotIn("p1", text)

    def test_render_clears_stream_state(self) -> None:
        msgs = [_Msg("user", "q1")]
        self.view.render(msgs)
        self.view.render_streaming(msgs, "p1")
        self.view.render(msgs)
        self.assertNotIn("p1", self.view.toPlainText())
        # A new streaming turn after a full render still works.
        self.view.render_streaming(msgs, "p2")
        self.assertIn("p2", self.view.toPlainText())


if __name__ == "__main__":
    unittest.main()