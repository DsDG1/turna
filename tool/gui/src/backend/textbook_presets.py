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

    - ``document_kind``: coarse document class (``textbook`` / ``grammar`` /
      ``dialogue`` / ``reading`` / ``syllabus``). ``document_profile`` maps a
      detected kind back to a preset through ``preset_for_kind``.
    - ``prompt_addendum``: extra extraction rules appended to the built-in
      rules block. This is how a syllabus (objectives + grammar topics, few
      example sentences) tells the model to stay inside the document instead of
      inventing vocabulary.
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
    document_kind: str = "textbook"
    prompt_addendum: str = ""


#: Extra rules for a teaching syllabus / curriculum outline: the document names
#: objectives and grammar topics but rarely shows the target-language forms.
_SYLLABUS_ADDENDUM = (
    "\n- This document is a TEACHING SYLLABUS / curriculum outline, not a "
    "textbook chapter. Its entries are objectives, functions, grammar topics "
    "and assessment notes; example sentences are sparse.\n"
    "- Extract only what the syllabus explicitly names. Never invent a target-"
    "language form for an objective that is written only in the source "
    "language; skip that entry instead.\n"
    "- Expand a stated objective into at most 3-5 concrete words or fixed "
    "expressions that a teacher would obviously need first, and tag them by "
    "the objective they serve.\n"
    "- Grammar topics named in the syllabus become grammarPoints even when no "
    "example sentence is present; put the syllabus wording into "
    "``explanation`` and leave example ids empty."
)


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
        document_kind="textbook",
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
        document_kind="grammar",
    ),
    "dialogue": TextbookPreset(
        name="dialogue",
        label="对话书",
        description="略高温抽取，侧重日常表达与口语词汇。",
        temperature=0.5,
        strategy="standard",
        max_chapter_chars=8000,
        lesson_template="intro",
        document_kind="dialogue",
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
        document_kind="reading",
    ),
    "syllabus": TextbookPreset(
        name="syllabus",
        label="教学纲领 / 课程大纲",
        description=(
            "按纲领条目抽取：目标、语法主题、必备词汇；不编造纲领没写的词形。"
        ),
        temperature=0.2,
        strategy="standard",
        max_tokens=4096,
        max_chapter_chars=12000,
        window_chars=12000,
        lesson_template="intro",
        document_kind="syllabus",
        prompt_addendum=_SYLLABUS_ADDENDUM,
    ),
}


def preset_for(name: str) -> TextbookPreset:
    """Return the preset for ``name``, falling back to ``general``."""
    return BUILTIN_TEXTBOOK_PRESETS.get(name, BUILTIN_TEXTBOOK_PRESETS["general"])


def preset_for_kind(kind: str) -> TextbookPreset:
    """Return the preset matching a detected document ``kind``.

    ``document_profile`` detects ``textbook`` / ``grammar`` / ``dialogue`` /
    ``reading`` / ``syllabus``; an unknown kind falls back to ``general`` so a
    mis-detection never blocks the import.
    """
    key = (kind or "").strip().lower()
    for preset in BUILTIN_TEXTBOOK_PRESETS.values():
        if preset.document_kind == key:
            return preset
    return BUILTIN_TEXTBOOK_PRESETS["general"]


def preset_names() -> list[str]:
    """Return built-in preset machine names in a stable display order."""
    return ["general", "grammar", "dialogue", "reading", "syllabus"]
