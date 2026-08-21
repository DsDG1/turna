"""Textbook-type presets for the textbook-import extraction pipeline.

Distinct from ``ai_presets.py`` (which models *provider* configurations -
DeepSeek/OpenAI/Moonshot/Ollama). A ``TextbookPreset`` models the *content
type* of the source material (grammar book, dialogue book, reading material)
and controls how the knowledge extractor behaves for it: sampling temperature,
extraction strategy, response length cap, chapter-text cap, and the lesson
template the imported section is built with.

Pure Python, no PySide6 dependency, so it is unit-testable in the sandbox.
bookplan2 Phase 5.
"""
from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class TextbookPreset:
    """Extraction behaviour for one textbook content type.

    - ``temperature``: LLM sampling temperature for extraction. Grammar books
      benefit from lower temperature (deterministic rules); dialogue/reading
      from slightly higher (capture varied expressions).
    - ``strategy``: ``"standard"`` (words + expressions + grammar) or
      ``"vocab_only"`` (words only - useful for reading material where grammar
      is implicit).
    - ``max_tokens``: response cap forwarded to ``request_chat``; ``None`` lets
      the provider default apply.
    - ``max_chapter_chars``: cap on the chapter markdown sent to the model;
      longer chapters are truncated at a paragraph boundary (see
      ``knowledge_prompt._truncate_markdown``). Also used as the single-shot
      fallback cap for windowed extraction.
    - ``window_chars``: sliding-window size for over-long chapters
      (aiEnhance.md P4-1). Chapters longer than this are extracted in
      paragraph-aligned windows and merged with overlap dedup instead of being
      truncated; ``0`` disables windowing (old truncate-only behaviour).
      Chapters within the cap take the single-shot path unchanged.
    - ``overlap_chars``: how much of a window's tail is repeated at the start
      of the next window so seam knowledge is seen twice (dedup handles the
      repeats).
    - ``lesson_template``: lesson skeleton the imported section is built with.
      Only ``"intro"`` is meaningfully implemented today (it is the one builder
      that consumes extracted words); other values fall back to ``"intro"``.
    """

    name: str
    label: str
    description: str
    temperature: float = 0.3
    strategy: str = "standard"
    max_tokens: int | None = None
    max_chapter_chars: int = 8000
    window_chars: int = 8000
    overlap_chars: int = 500
    lesson_template: str = "intro"


#: Built-in textbook presets keyed by machine name.
BUILTIN_TEXTBOOK_PRESETS: dict[str, TextbookPreset] = {
    "general": TextbookPreset(
        name="general",
        label="通用教材",
        description="词汇 + 表达 + 语法，均衡抽取。适合大多数课本。",
        temperature=0.3,
        strategy="standard",
        max_chapter_chars=8000,
        lesson_template="intro",
    ),
    "grammar": TextbookPreset(
        name="grammar",
        label="语法书",
        description="低温抽取，侧重语法点与例句，规则更确定。",
        temperature=0.15,
        strategy="standard",
        max_tokens=4096,
        max_chapter_chars=8000,
        lesson_template="intro",
    ),
    "dialogue": TextbookPreset(
        name="dialogue",
        label="对话书",
        description="略高温抽取，侧重日常表达与口语词汇。",
        temperature=0.5,
        strategy="standard",
        max_chapter_chars=8000,
        lesson_template="intro",
    ),
    "reading": TextbookPreset(
        name="reading",
        label="阅读材料",
        description="仅抽词汇，忽略隐式语法；适合长篇阅读导入。",
        temperature=0.3,
        strategy="vocab_only",
        max_chapter_chars=10000,
        window_chars=10000,
        lesson_template="intro",
    ),
}


def preset_for(name: str) -> TextbookPreset:
    """Return the preset for ``name``, falling back to ``general``."""
    return BUILTIN_TEXTBOOK_PRESETS.get(name, BUILTIN_TEXTBOOK_PRESETS["general"])


def preset_names() -> list[str]:
    """Return built-in preset machine names in a stable display order."""
    return ["general", "grammar", "dialogue", "reading"]
