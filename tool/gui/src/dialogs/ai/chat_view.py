"""Chat rendering for wish-mode conversation.

Extracted from the original monolithic ``ai_generator_dialog.py`` (guiplan2 P5).
The HTML-building helpers are **pure functions** that take a ``palette`` dict
(semantic color name -> hex string) so they can be unit-tested without PySide6.
``ChatView`` is a thin ``QTextBrowser`` that renders a shared message list.
"""
from __future__ import annotations

from typing import Any

from PySide6.QtGui import QTextCursor
from PySide6.QtWidgets import QTextBrowser

from src.theme_tokens import BRAND_REED, BRAND_TEAL, BRAND_TEAL_DARK

# A fallback palette used until theme.py provides one (and by unit tests).
# Keys mirror the ``ai_*`` palette keys in src/theme_tokens.py.
# Values are kept in sync with the ``dark`` palette so chat rendering looks
# correct before apply_theme() is called. Brand hex equals ADR 0033 contract.
DEFAULT_PALETTE: dict[str, str] = {
    "ai_chat_bg": "#142129",
    "ai_bubble_bg": "#20323D",
    "ai_user_bubble": BRAND_TEAL,
    "ai_card_bg": "#182832",
    "ai_chip_bg": "#142129",
    "ai_accent": BRAND_REED,
    "ai_accent_border": BRAND_TEAL,
    "ai_beta_bg": "#664400",
    "ai_beta_text": "#FFD93D",
    "text": "#E8EAF0",
    "text_secondary": "#B6C4CB",
    "text_disabled": "#7D929C",
    "success": "#27AE60",
    "error": "#E74C3C",
}


def escape_html(text: str) -> str:
    """Escape HTML-special characters and convert newlines to <br>."""
    return (
        text.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace("\n", "<br>")
    )


def format_message_content(content: str | list[dict[str, Any]]) -> str:
    """Render a message body (plain string or list of content pieces) to text."""
    if isinstance(content, str):
        return content
    parts: list[str] = []
    for piece in content or []:
        if isinstance(piece, dict):
            if piece.get("type") == "text":
                parts.append(str(piece.get("text", "")))
            elif piece.get("type") == "image_url":
                parts.append("[图片]")
    return "\n".join(parts)


def user_bubble_html(
    content: str | list[dict[str, Any]], ts: str, palette: dict[str, str]
) -> str:
    """Build the HTML for a right-aligned user message bubble."""
    text = format_message_content(content)
    muted = palette.get("text_disabled", "#6B7280")
    ts_html = (
        f'<div style="font-size: 10px; color: {muted}; text-align: right; '
        f'margin-bottom: 2px;">{escape_html(ts)}</div>'
        if ts
        else ""
    )
    bg = palette.get("ai_user_bubble", BRAND_TEAL_DARK)
    return (
        '<div style="display: flex; justify-content: flex-end; margin: 12px 0;">'
        '<div style="max-width: 75%;">'
        f"{ts_html}"
        f'<div style="display: inline-block; background-color: {bg}; '
        'color: #FFFFFF; padding: 10px 14px; border-radius: 12px 12px 2px 12px; '
        'text-align: left; line-height: 1.6;">'
        f"{escape_html(text)}</div>"
        "</div></div>"
    )


def ai_bubble_html(
    content: str | list[dict[str, Any]], ts: str, palette: dict[str, str]
) -> str:
    """Build the HTML for a left-aligned AI message bubble."""
    text = format_message_content(content)
    muted = palette.get("text_disabled", "#6B7280")
    ts_html = (
        f'<div style="font-size: 10px; color: {muted}; margin-bottom: 2px;">'
        f"AI · {escape_html(ts)}</div>"
        if ts
        else ""
    )
    bg = palette.get("ai_bubble_bg", "#2C313C")
    fg = palette.get("text", "#E8EAF0")
    return (
        '<div style="display: flex; justify-content: flex-start; margin: 12px 0;">'
        '<div style="max-width: 80%;">'
        f"{ts_html}"
        f'<div style="display: inline-block; background-color: {bg}; '
        f'color: {fg}; padding: 10px 14px; border-radius: 12px 12px 12px 2px; '
        'text-align: left; line-height: 1.6;">'
        f"{escape_html(text)}</div>"
        "</div></div>"
    )


def welcome_html(palette: dict[str, str]) -> str:
    """Empty-state placeholder shown when the conversation is empty."""
    muted = palette.get("text_disabled", "#6B7280")
    return (
        f'<div style="color: {muted}; text-align: center; padding: 32px 16px;">'
        "欢迎使用许愿模式！告诉我你想做什么课程，我会一步步帮你设计。<br>"
        "你可以直接拖拽图片、PDF、Word 或文本到窗口作为参考。"
        "</div>"
    )


def render_chat_html(messages, palette: dict[str, str]) -> str:
    """Render the full conversation to an HTML string (no widget calls)."""
    parts: list[str] = [
        '<div style="font-family: system-ui, sans-serif; font-size: 14px; padding: 8px;">'
    ]
    if not messages:
        parts.append(welcome_html(palette))
    for msg in messages:
        if msg.role == "user":
            parts.append(user_bubble_html(msg.content, msg.timestamp, palette))
        elif msg.role == "assistant":
            parts.append(ai_bubble_html(msg.content, msg.timestamp, palette))
    parts.append("</div>")
    return "\n".join(parts)


def render_streaming_html(messages, partial_text: str, palette: dict[str, str]) -> str:
    """Render the conversation with an in-flight assistant turn appended."""
    parts: list[str] = ['<div style="font-family: sans-serif;">']
    for msg in messages:
        if msg.role == "user":
            parts.append(user_bubble_html(msg.content, msg.timestamp, palette))
        elif msg.role == "assistant":
            parts.append(ai_bubble_html(msg.content, msg.timestamp, palette))
    parts.append(ai_bubble_html(partial_text, "", palette))
    parts.append("</div>")
    return "\n".join(parts)


class ChatView(QTextBrowser):
    """Thin chat surface that renders a shared message list into HTML.

    The view does NOT own the messages list; the dialog holds ``_messages`` and
    calls ``render``/``render_streaming`` whenever it changes. This keeps a
    single source of truth and lets an expand sub-window share the same list.

    Streaming uses an append-only fast path: history is laid out once per
    message-count change and each throttled flush rewrites only the in-flight
    assistant bubble (select anchor→end, remove, insertHtml). A full-document
    setHtml per flush would re-parse the whole conversation every 120 ms (O(n²)
    over the stream length).
    """

    def __init__(self, parent=None) -> None:
        super().__init__(parent)
        self.setOpenExternalLinks(True)
        # Streaming fast-path state; invalidated by render().
        self._stream_msg_count: int | None = None
        self._stream_anchor: int | None = None

    def render(self, messages, palette: dict[str, str] | None = None) -> None:
        pal = palette or DEFAULT_PALETTE
        self._stream_msg_count = None
        self._stream_anchor = None
        self.setHtml(render_chat_html(messages, pal))
        self._scroll_to_bottom()

    def render_streaming(
        self, messages, partial_text: str, palette: dict[str, str] | None = None
    ) -> None:
        pal = palette or DEFAULT_PALETTE
        count = len(messages)
        if self._stream_msg_count != count or self._stream_anchor is None:
            # History changed (first flush of a new turn): one full layout,
            # then record where the in-flight bubble starts.
            self.setHtml(render_chat_html(messages, pal))
            cursor = self.textCursor()
            cursor.movePosition(QTextCursor.MoveOperation.End)
            anchor = cursor.position()
            cursor.insertHtml(ai_bubble_html(partial_text, "", pal))
            self._stream_msg_count = count
            self._stream_anchor = anchor
        else:
            # Fast path: replace only the in-flight bubble. Everything before
            # the anchor is untouched, so positions before it stay valid.
            cursor = self.textCursor()
            cursor.setPosition(self._stream_anchor)
            cursor.movePosition(
                QTextCursor.MoveOperation.End, QTextCursor.MoveMode.KeepAnchor
            )
            cursor.removeSelectedText()
            cursor.insertHtml(ai_bubble_html(partial_text, "", pal))
        self._scroll_to_bottom()

    def restyle(self, palette: dict[str, str]) -> None:
        """Apply theme colors to the chat background."""
        self.setStyleSheet(
            f"QTextBrowser {{ background-color: {palette.get('ai_chat_bg', '#1A1D23')}; "
            f"border: 1px solid {palette.get('ai_bubble_bg', '#2C313C')}; "
            "border-radius: 8px; padding: 6px; }}"
        )

    def _scroll_to_bottom(self) -> None:
        scrollbar = self.verticalScrollBar()
        scrollbar.setValue(scrollbar.maximum())