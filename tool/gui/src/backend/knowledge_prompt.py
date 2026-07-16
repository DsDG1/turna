"""Build the LLM prompts for per-chapter knowledge-point extraction.

Pure functions only - no I/O, no LLM calls. Used by
``knowledge_extractor.extract_knowledge_points`` (the ③->④ step of the
textbook-import pipeline, bookplan.md).

The returned JSON shape matches ``knowledge_schema.coerce_knowledge_points``
(words/expressions/grammarPoints) and the real entry shapes in
``assets/courses/turkish/``. We deliberately do NOT ask for a ``units`` array -
``parse_completion`` would reject anything without ``units``; instead the
downstream builds the lesson via ``build_intro_lesson``.

bookplan2 Phase 5 adds:
- ``KnowledgePromptLibrary``: per-language-pair prompt-template overrides so a
  Turkish/Chinese course and a Spanish/English course can ship different
  extraction wording without forking the module.
- paragraph-aware truncation: long chapters are cut at the last paragraph
  boundary near the cap instead of mid-sentence.
"""
from __future__ import annotations

from dataclasses import dataclass, field, replace
from typing import Any

from src.backend.markdown_chopper import Chapter

# Conservative cap on the chapter markdown we send to the model. ~8000 chars
# keeps a single-chapter extraction well within a 1M-context window even when
# the textbook is dense; longer chapters get truncated with a notice.
_MAX_CHAPTER_CHARS = 8000

_SYSTEM_PROMPT = (
    "You are a language-course authoring assistant. "
    "You output ONLY valid JSON, no prose, no markdown fences."
)

_SCHEMA_BLOCK = (
    "Return STRICT JSON with exactly this shape:\n"
    "{\n"
    '  "words": [{"id": "...", "term": "...", "translation": "...", '
    '"pronunciation": "...", "tags": ["..."]}],\n'
    '  "expressions": [{"id": "...", "term": "...", "translation": "...", '
    '"pronunciation": "...", "tags": ["..."]}],\n'
    '  "grammarPoints": [{"id": "...", "title": "...", "explanation": "...", '
    '"exampleExpressionIds": ["..."], "exampleSentenceIds": ["..."]}]\n'
    "}\n"
)

_RULES_BLOCK = (
    "Rules:\n"
    "- Extract only knowledge that genuinely appears in this chapter's text.\n"
    f"- term (for words/expressions) and title (for grammarPoints) are required "
    "and must be non-empty.\n"
    "- term/title are in the target language; translation is in the "
    "source/prompt language.\n"
    "- id may be left empty - it will be filled deterministically if omitted.\n"
    "- tags must come from: pronoun, greeting, verb, noun, animal, color, "
    "number, emotion, nature, travel, food, family, question, particle, "
    "adjective, adverb. Omit tags rather than inventing new ones.\n"
    "- pronunciation is optional; leave empty string if unsure.\n"
    "- exampleExpressionIds reference ids of expressions in the same output; "
    "leave empty if none.\n"
    "- Output ONLY the JSON object. No markdown fences, no commentary."
)

_VOCAB_ONLY_SCHEMA_BLOCK = (
    "Return STRICT JSON with exactly this shape:\n"
    "{\n"
    '  "words": [{"id": "...", "term": "...", "translation": "...", '
    '"pronunciation": "...", "tags": ["..."]}]\n'
    "}\n"
)

_VOCAB_ONLY_RULES_BLOCK = (
    "Rules:\n"
    "- Extract only vocabulary words that genuinely appear in this chapter's text.\n"
    "- term (target language) and translation (source language) are required "
    "and must be non-empty.\n"
    "- id may be left empty - it will be filled deterministically if omitted.\n"
    "- tags must come from: pronoun, greeting, verb, noun, animal, color, "
    "number, emotion, nature, travel, food, family, question, particle, "
    "adjective, adverb. Omit tags rather than inventing new ones.\n"
    "- pronunciation is optional; leave empty string if unsure.\n"
    "- Output ONLY the JSON object. No markdown fences, no commentary."
)

_TRUNCATION_NOTICE = "\n\n[…本章节正文过长，已截断。仅依据以上内容抽取知识点。…]\n"


@dataclass(frozen=True)
class KnowledgePromptTemplates:
    """The prompt blocks for one language pair (or the default)."""

    system: str = _SYSTEM_PROMPT
    schema_block: str = _SCHEMA_BLOCK
    rules_block: str = _RULES_BLOCK
    vocab_schema_block: str = _VOCAB_ONLY_SCHEMA_BLOCK
    vocab_rules_block: str = _VOCAB_ONLY_RULES_BLOCK
    intro: str = "Extract teachable knowledge points from the textbook chapter below."
    vocab_intro: str = "Extract only vocabulary words from the textbook chapter below."


@dataclass
class KnowledgePromptLibrary:
    """Per-language-pair prompt-template overrides (bookplan2 Phase 5).

    The default library returns ``DEFAULT_TEMPLATES`` for every pair. Register
    an override for a specific ``(language, source_language)`` to ship different
    extraction wording (e.g. reading-heavy vs grammar-heavy phrasing) without
    forking the module. Language matching is case-insensitive.
    """

    templates: KnowledgePromptTemplates = field(default_factory=KnowledgePromptTemplates)
    _overrides: dict[tuple[str, str], KnowledgePromptTemplates] = field(default_factory=dict)

    def register(
        self,
        language: str,
        source_language: str,
        templates: KnowledgePromptTemplates,
    ) -> None:
        self._overrides[
            (language.strip().lower(), source_language.strip().lower())
        ] = templates

    def templates_for(
        self, language: str, source_language: str
    ) -> KnowledgePromptTemplates:
        return self._overrides.get(
            (language.strip().lower(), source_language.strip().lower()),
            self.templates,
        )

    def clear(self) -> None:
        self._overrides.clear()


#: Module-level default library used when callers do not pass one explicitly.
DEFAULT_LIBRARY = KnowledgePromptLibrary()


def default_library() -> KnowledgePromptLibrary:
    """Return the shared default prompt library."""
    return DEFAULT_LIBRARY


def _truncate_markdown(md: str, max_chars: int = _MAX_CHAPTER_CHARS) -> str:
    """Return the chapter markdown, capped at ``max_chars``.

    Cuts at the last paragraph boundary (blank line) at or before ``max_chars``
    so the truncation does not split a sentence; if no such boundary exists in
    the back half of the window, falls back to a hard cut. A notice is appended
    so the model knows the chapter was shortened.
    """
    if len(md) <= max_chars:
        return md
    cut = md[:max_chars]
    boundary = cut.rfind("\n\n")
    # Only honour a paragraph boundary in the back half of the window; an early
    # boundary would discard most of the allowed budget.
    if boundary >= max_chars // 2:
        truncated = md[:boundary]
    else:
        truncated = cut
    return truncated + _TRUNCATION_NOTICE


def build_extraction_messages(
    language: str,
    source_language: str,
    chapter: Chapter,
    *,
    max_chars: int = _MAX_CHAPTER_CHARS,
    library: KnowledgePromptLibrary | None = None,
) -> list[dict[str, str]]:
    """Build the [system, user] messages for a per-chapter extraction call.

    The user message names the target + source languages and embeds the
    chapter's Markdown (truncated to a conservative cap). The expected JSON
    shape and extraction rules mirror ``knowledge_schema.coerce_knowledge_points``.
    """
    lib = library or DEFAULT_LIBRARY
    tpl = lib.templates_for(language, source_language)
    user_prompt = "\n".join(
        [
            tpl.intro,
            "",
            f"Target language (the language being taught): {language}",
            f"Source / prompt language (for translations): {source_language}",
            f"Chapter title: {chapter.title}",
            "",
            tpl.schema_block,
            tpl.rules_block,
            "",
            "Chapter Markdown:",
            _truncate_markdown(chapter.markdown, max_chars),
        ]
    )
    return [
        {"role": "system", "content": tpl.system},
        {"role": "user", "content": user_prompt},
    ]


def build_vocab_only_extraction_messages(
    language: str,
    source_language: str,
    chapter: Chapter,
    *,
    max_chars: int = _MAX_CHAPTER_CHARS,
    library: KnowledgePromptLibrary | None = None,
) -> list[dict[str, str]]:
    """Build a reduced extraction prompt that asks for vocabulary only.

    Used as a fallback when the full extraction fails or when the teacher
    explicitly chooses the vocabulary-only strategy.
    """
    lib = library or DEFAULT_LIBRARY
    tpl = lib.templates_for(language, source_language)
    user_prompt = "\n".join(
        [
            tpl.vocab_intro,
            "",
            f"Target language (the language being taught): {language}",
            f"Source / prompt language (for translations): {source_language}",
            f"Chapter title: {chapter.title}",
            "",
            tpl.vocab_schema_block,
            tpl.vocab_rules_block,
            "",
            "Chapter Markdown:",
            _truncate_markdown(chapter.markdown, max_chars),
        ]
    )
    return [
        {"role": "system", "content": tpl.system},
        {"role": "user", "content": user_prompt},
    ]


def build_correction_prompt(errors: list[str]) -> str:
    """Build the user turn appended on a retry, mirroring request_course_with_retry.

    Lists the validation errors and asks for the full corrected JSON only.
    """
    bullet = "\n".join(f"- {e}" for e in errors)
    return (
        "上一版抽取结果有以下校验错误，请修正后只输出完整的修正 JSON：\n"
        f"{bullet}"
    )
