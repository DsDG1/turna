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


if __name__ == "__main__":
    unittest.main()