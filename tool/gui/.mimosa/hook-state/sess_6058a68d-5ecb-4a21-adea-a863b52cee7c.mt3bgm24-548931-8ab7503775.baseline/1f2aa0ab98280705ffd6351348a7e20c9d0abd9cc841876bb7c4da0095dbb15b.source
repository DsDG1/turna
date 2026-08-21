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

import json
from dataclasses import dataclass, field
from typing import Any

from src.backend.markdown_chopper import Chapter

# Conservative cap on the chapter markdown we send to the model. ~8000 chars
# keeps a single-chapter extraction well within a 1M-context window even when
# the textbook is dense; longer chapters get truncated with a notice.
_MAX_CHAPTER_CHARS = 8000

# Default system prompt for extraction. Mirrors ``ai_generator.SYSTEM_AUTHORING``
# but is kept as separate *data* (it is the default value of the
# ``KnowledgePromptTemplates.system`` template field, overridable per language
# pair via the prompt library) rather than shared code.
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

    def to_dict(self) -> dict[str, str]:
        return {
            "system": self.system,
            "schema_block": self.schema_block,
            "rules_block": self.rules_block,
            "vocab_schema_block": self.vocab_schema_block,
            "vocab_rules_block": self.vocab_rules_block,
            "intro": self.intro,
            "vocab_intro": self.vocab_intro,
        }

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "KnowledgePromptTemplates":
        """Build from a partial dict; missing keys fall back to defaults."""
        defaults = cls()
        return cls(
            system=data.get("system") or defaults.system,
            schema_block=data.get("schema_block") or defaults.schema_block,
            rules_block=data.get("rules_block") or defaults.rules_block,
            vocab_schema_block=data.get("vocab_schema_block") or defaults.vocab_schema_block,
            vocab_rules_block=data.get("vocab_rules_block") or defaults.vocab_rules_block,
            intro=data.get("intro") or defaults.intro,
            vocab_intro=data.get("vocab_intro") or defaults.vocab_intro,
        )


# Built-in per-language-pair template packs (aiEnhance.md P4-3). These sit
# between the library default and persisted/user overrides: lookup order in
# ``KnowledgePromptLibrary.templates_for`` is in-memory ``register`` >
# persisted overrides > these built-in packs > the library default. Pure
# wording - the JSON schema block is never altered per pair.
_TR_ZH_RULES_BLOCK = (
    _RULES_BLOCK
    + "\n- The target language is Turkish: when a word illustrates vowel "
    "harmony (元音和谐) or politeness/honorific usage (敬语, e.g. sen vs "
    "siz), keep the form that actually appears in the text and choose an "
    "accurate tag for it.\n"
    "- term/title must be Turkish only - never mix Chinese characters into "
    "them.\n"
    "- translation must be written in Simplified Chinese (简体中文)."
)

_TR_ZH_VOCAB_RULES_BLOCK = (
    _VOCAB_ONLY_RULES_BLOCK
    + "\n- term must be Turkish only - never mix Chinese characters into it.\n"
    "- translation must be written in Simplified Chinese (简体中文).\n"
    "- When a word illustrates vowel harmony (元音和谐) or is a politeness "
    "form (敬语), keep the form used in the text."
)

#: Built-in language-pair packs keyed by ``(language, source_language)``,
#: lower-case - same normalisation as ``KnowledgePromptLibrary._key``.
BUILTIN_PAIR_TEMPLATES: dict[tuple[str, str], KnowledgePromptTemplates] = {
    ("turkish", "chinese"): KnowledgePromptTemplates(
        rules_block=_TR_ZH_RULES_BLOCK,
        vocab_rules_block=_TR_ZH_VOCAB_RULES_BLOCK,
    ),
}


@dataclass
class KnowledgePromptLibrary:
    """Per-language-pair prompt-template overrides (bookplan2 Phase 5).

    The default library returns ``DEFAULT_TEMPLATES`` for every pair. Register
    an override for a specific ``(language, source_language)`` to ship different
    extraction wording (e.g. reading-heavy vs grammar-heavy phrasing) without
    forking the module. Language matching is case-insensitive.

    Lookup order (connectplan P1-3 + aiEnhance P4-3): in-memory ``register``
    overrides (tests) win over persisted overrides loaded via
    ``load_overrides_from``, which win over the built-in language-pair packs
    (``BUILTIN_PAIR_TEMPLATES``), which win over the built-in defaults.
    """

    templates: KnowledgePromptTemplates = field(default_factory=KnowledgePromptTemplates)
    _overrides: dict[tuple[str, str], KnowledgePromptTemplates] = field(default_factory=dict)
    _persisted: dict[tuple[str, str], KnowledgePromptTemplates] = field(default_factory=dict)

    @staticmethod
    def _key(language: str, source_language: str) -> tuple[str, str]:
        return (language.strip().lower(), source_language.strip().lower())

    def register(
        self,
        language: str,
        source_language: str,
        templates: KnowledgePromptTemplates,
    ) -> None:
        self._overrides[self._key(language, source_language)] = templates

    def register_persisted(
        self,
        language: str,
        source_language: str,
        templates: KnowledgePromptTemplates,
    ) -> None:
        """Register an override loaded from persistent storage.

        Loses to a later in-memory ``register`` for the same pair.
        """
        self._persisted[self._key(language, source_language)] = templates

    def unregister_persisted(self, language: str, source_language: str) -> None:
        """Drop a persisted override (e.g. after the user deleted it)."""
        self._persisted.pop(self._key(language, source_language), None)

    def templates_for(
        self, language: str, source_language: str
    ) -> KnowledgePromptTemplates:
        key = self._key(language, source_language)
        if key in self._overrides:
            return self._overrides[key]
        if key in self._persisted:
            return self._persisted[key]
        if key in BUILTIN_PAIR_TEMPLATES:
            return BUILTIN_PAIR_TEMPLATES[key]
        return self.templates

    def clear(self) -> None:
        self._overrides.clear()
        self._persisted.clear()


#: Module-level default library used when callers do not pass one explicitly.
DEFAULT_LIBRARY = KnowledgePromptLibrary()


def default_library() -> KnowledgePromptLibrary:
    """Return the shared default prompt library."""
    return DEFAULT_LIBRARY


def load_overrides_from(library: Any) -> int:
    """Load persisted extraction overrides into the default library (P1-3).

    ``library`` is anything exposing ``list_extraction_overrides()`` returning
    ``{"lang|src": blocks}`` (e.g. ``AiPromptLibrary``); this module stays
    Qt-free by depending only on that duck-typed method. Returns the number of
    overrides registered. In-memory ``register`` overrides keep precedence.
    """
    count = 0
    for key, blocks in library.list_extraction_overrides().items():
        if "|" not in key or not isinstance(blocks, dict):
            continue
        language, _, source_language = key.partition("|")
        DEFAULT_LIBRARY.register_persisted(
            language, source_language, KnowledgePromptTemplates.from_dict(blocks)
        )
        count += 1
    return count


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


def build_targeted_reextract_messages(
    language: str,
    source_language: str,
    chapter: Chapter,
    kp: Any,
    issues: list[Any],
    *,
    max_chars: int = _MAX_CHAPTER_CHARS,
    library: KnowledgePromptLibrary | None = None,
) -> list[dict[str, str]]:
    """Build messages for a quality-driven targeted re-extraction (P4-4).

    Feeds the current extraction (``kp``, a ``KnowledgePoints``) plus the
    concrete quality ``issues`` (``QualityIssue``-shaped objects, read
    duck-typed via ``getattr`` so this module stays decoupled from
    ``extraction_quality``) back to the model - in the style of
    ``build_correction_prompt`` - and asks for a COMPLETE corrected
    knowledge-points JSON under the same schema as a fresh extraction, so the
    result can replace the old one wholesale.
    """
    lib = library or DEFAULT_LIBRARY
    tpl = lib.templates_for(language, source_language)
    current_json = json.dumps(
        {
            "words": kp.words,
            "expressions": kp.expressions,
            "grammarPoints": kp.grammarPoints,
        },
        ensure_ascii=False,
        indent=2,
    )
    issue_lines: list[str] = []
    for issue in issues:
        level = getattr(issue, "level", "warning")
        kind = getattr(issue, "kind", "")
        message = getattr(issue, "message", str(issue))
        where_parts: list[str] = []
        resource_type = getattr(issue, "resource_type", None)
        resource_index = getattr(issue, "resource_index", None)
        field_name = getattr(issue, "field", None)
        if resource_type is not None:
            where = str(resource_type)
            if resource_index is not None:
                where += f" #{resource_index}"
            where_parts.append(where)
        if field_name:
            where_parts.append(f"field: {field_name}")
        suffix = f"（{'，'.join(where_parts)}）" if where_parts else ""
        issue_lines.append(f"- [{level}/{kind}] {message}{suffix}")
    issues_block = "\n".join(issue_lines) or "- （无具体问题列表，请整体复查。）"

    user_prompt = "\n".join(
        [
            "The previous extraction for this chapter has quality problems. "
            "Produce a COMPLETE corrected knowledge-points JSON (same schema "
            "as before) that fixes every issue below while keeping all valid "
            "entries.",
            "",
            f"Target language (the language being taught): {language}",
            f"Source / prompt language (for translations): {source_language}",
            f"Chapter title: {chapter.title}",
            "",
            "Quality issues to fix:",
            issues_block,
            "",
            "Current extraction (correct it and return it in full):",
            current_json,
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
