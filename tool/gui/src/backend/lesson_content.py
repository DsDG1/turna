"""Pure-Python lesson content operations (no PySide6 dependency).

Defines the 14 Interaction runtimeType schemas, the template->content shape
rules (guiplan §6.2), id generation, and new/delete helpers. This module is
the single source of truth for content-shape rules used by the widgets.
"""
from __future__ import annotations

import copy
import re
import uuid
from dataclasses import dataclass
from typing import Any

from src.backend.api import course_pedagogy
from src.backend.schema_constants import (
    KEY_EXPRESSIONS,
    KEY_GRAMMAR,
    KEY_GRAMMAR_POINTS,
    KEY_ITEMS,
    KEY_LISTENING_PHASES,
    KEY_READING_PASSAGE,
    KEY_RUNTIME_TYPE,
    KEY_STAGES,
    KEY_SUB_LESSONS,
    KEY_VOCAB,
    ContentKey,
    CourseKey,
    InteractionType,
    ItemKey,
    ListeningPhaseType,
    ResourceKey,
    TemplateType,
)

CONTENT_BY_TEMPLATE: dict[str, set[str]] = {
    TemplateType.GUIDE: {ContentKey.PAGES},
    TemplateType.INTRO: {ContentKey.SUB_LESSONS},
    TemplateType.PRACTICE: {ContentKey.SUB_LESSONS},
    TemplateType.REVIEW: {
        ContentKey.SUB_LESSONS,
        ContentKey.STAGES,
        ContentKey.REVIEW_POLICY,
    },
    TemplateType.LISTENING: {ContentKey.LISTENING_PHASES},
    TemplateType.DIALOGUE: {ContentKey.DIALOGUE_SCENE, ContentKey.STAGES},
    TemplateType.READING: {ContentKey.READING_PASSAGE, ContentKey.STAGES},
    TemplateType.MASTERY: {ContentKey.STAGES},
    TemplateType.LEGACY: {ContentKey.STAGES, ContentKey.SUB_LESSONS, ContentKey.LISTENING_PHASES},
}

PRIMARY_CONTENT_KEY: dict[str, str] = {
    TemplateType.GUIDE: ContentKey.PAGES,
    TemplateType.INTRO: ContentKey.SUB_LESSONS,
    TemplateType.PRACTICE: ContentKey.SUB_LESSONS,
    TemplateType.REVIEW: ContentKey.SUB_LESSONS,
    TemplateType.LISTENING: ContentKey.LISTENING_PHASES,
    TemplateType.DIALOGUE: ContentKey.STAGES,
    TemplateType.READING: ContentKey.READING_PASSAGE,
    TemplateType.MASTERY: ContentKey.STAGES,
    TemplateType.LEGACY: ContentKey.STAGES,
}

LISTENING_PHASE_TYPES = (
    ListeningPhaseType.WORD_PAIRING,
    ListeningPhaseType.DIALOGUE,
    ListeningPhaseType.SUMMARY,
)

ALLOWED_RUNTIME_TYPES = tuple(t.value for t in InteractionType)

INTERACTION_LABELS: dict[str, str] = {
    InteractionType.SHOW_WORD: "展示生词",
    InteractionType.MULTIPLE_CHOICE: "选择题",
    InteractionType.MULTI_SELECT: "多选题",
    InteractionType.FILL_BLANK: "填空题",
    InteractionType.TRANSLATE_SENTENCE: "翻译题",
    InteractionType.LISTEN_AND_PICK: "听音选词",
    InteractionType.TYPE_THE_WORD: "听写题",
    InteractionType.LISTEN_ONLY: "只听不答",
    InteractionType.REORDER_SENTENCE: "排序句子",
    InteractionType.READING_MCQ: "阅读选择",
    InteractionType.READING_TRUE_FALSE: "阅读判断",
    InteractionType.READING_SHORT_ANSWER: "阅读简答",
    InteractionType.ANKI_CARD: "记忆卡片",
    InteractionType.ANKI_HTML_CARD: "记忆卡片 (HTML)",
    InteractionType.READ_ALOUD: "跟读",
    InteractionType.IMAGE_RECALL: "看图回忆",
    InteractionType.DICTATION: "纯音听写",
}

TEMPLATE_LABELS: dict[str, str] = {
    TemplateType.GUIDE: "分页导览",
    TemplateType.INTRO: "认识新词",
    TemplateType.PRACTICE: "巩固练习",
    TemplateType.REVIEW: "复习",
    TemplateType.LISTENING: "听力训练",
    TemplateType.DIALOGUE: "情景对话",
    TemplateType.READING: "阅读理解",
    TemplateType.MASTERY: "综合测验",
    TemplateType.LEGACY: "基础题",
}

#: Soft badge color per functional template. Shared by the course tree and the
#: overview window so they stay in sync. Keep here next to TEMPLATE_LABELS.
#: Theme-independent chips (white text); ``listening`` carries the Turna brand
#: teal — keep the hex in sync with ``theme_tokens.BRAND_TEAL`` (ADR 0033).
TEMPLATE_COLORS: dict[str, str] = {
    TemplateType.GUIDE: "#4A95A8",      # brandSky
    TemplateType.LISTENING: "#1F727E",  # ≡ theme_tokens.BRAND_TEAL
    TemplateType.DIALOGUE: "#B85C3F",   # anatolianClay
    TemplateType.READING: "#10B981",    # emerald
    TemplateType.MASTERY: "#F59E0B",    # amber
    TemplateType.INTRO: "#6366F1",      # indigo
    TemplateType.PRACTICE: "#8B5CF6",   # violet
    TemplateType.REVIEW: "#EC4899",     # rose
    TemplateType.LEGACY: "#6B7280",     # slate
}
TEMPLATE_COLOR_DEFAULT = "#6B7280"


@dataclass(frozen=True)
class FieldSpec:
    name: str
    required: bool
    kind: str  # 'string' | 'int' | 'bool' | 'string_list' | 'int_list' | 'ref_word' | 'ref_expression' | 'ref_grammar'
    default: Any = None


INTERACTION_SCHEMA: dict[str, list[FieldSpec]] = {
    InteractionType.SHOW_WORD: [
        FieldSpec("id", False, "string", ""),
        FieldSpec("wordId", True, "ref_word"),
        FieldSpec("context", False, "string", ""),
        FieldSpec("grammarPointId", False, "ref_grammar", ""),
        FieldSpec("expressionId", False, "ref_expression", ""),
        # Inline overrides: when non-empty they replace the vocab entry's
        # display value (mirrors ShowWord in interaction.dart). wordId stays
        # the only required field.
        FieldSpec("term", False, "string", ""),
        FieldSpec("translation", False, "string", ""),
        FieldSpec("pronunciation", False, "string", ""),
        FieldSpec("audioAsset", False, "string", ""),
        FieldSpec("imageAsset", False, "string", ""),
        FieldSpec("example", False, "string", ""),
    ],
    InteractionType.MULTIPLE_CHOICE: [
        FieldSpec("id", False, "string", ""),
        FieldSpec("prompt", True, "string", ""),
        FieldSpec("options", True, "string_list", []),
        FieldSpec("correctIndex", True, "int", 0),
        FieldSpec("imageAsset", False, "string", ""),
        FieldSpec("grammarPointId", False, "ref_grammar", ""),
        FieldSpec("audioAssets", False, "string_list", []),
    ],
    InteractionType.MULTI_SELECT: [
        FieldSpec("id", False, "string", ""),
        FieldSpec("prompt", True, "string", ""),
        FieldSpec("options", True, "string_list", []),
        FieldSpec("correctIndices", True, "int_list", []),
        FieldSpec("minSelections", False, "int", 1),
        FieldSpec("maxSelections", False, "int", 2147483647),
        FieldSpec("imageAsset", False, "string", ""),
        FieldSpec("grammarPointId", False, "ref_grammar", ""),
    ],
    InteractionType.FILL_BLANK: [
        FieldSpec("id", False, "string", ""),
        FieldSpec("sentence", True, "string", ""),
        FieldSpec("answer", True, "string", ""),
        FieldSpec("hint", False, "string", ""),
        FieldSpec("choices", False, "string_list", []),
        FieldSpec("grammarPointId", False, "ref_grammar", ""),
        FieldSpec("audioAssets", False, "string_list", []),
        FieldSpec("imageAssets", False, "string_list", []),
    ],
    InteractionType.TRANSLATE_SENTENCE: [
        FieldSpec("id", False, "string", ""),
        FieldSpec("source", True, "string", ""),
        FieldSpec("expected", True, "string", ""),
        FieldSpec("acceptedAnswers", False, "string_list", []),
        FieldSpec("hints", False, "string_list", []),
        FieldSpec("grammarPointId", False, "ref_grammar", ""),
    ],
    InteractionType.LISTEN_AND_PICK: [
        FieldSpec("id", False, "string", ""),
        FieldSpec("audioAsset", True, "string", ""),
        FieldSpec("prompt", True, "string", ""),
        FieldSpec("options", True, "string_list", []),
        FieldSpec("correctIndex", True, "int", 0),
        FieldSpec("grammarPointId", False, "ref_grammar", ""),
    ],
    InteractionType.TYPE_THE_WORD: [
        FieldSpec("id", False, "string", ""),
        FieldSpec("audioAsset", True, "string", ""),
        FieldSpec("prompt", True, "string", ""),
        FieldSpec("expected", True, "string", ""),
        FieldSpec("grammarPointId", False, "ref_grammar", ""),
    ],
    InteractionType.LISTEN_ONLY: [
        FieldSpec("id", False, "string", ""),
        FieldSpec("audioAsset", False, "string", ""),
        FieldSpec("transcript", False, "string", ""),
        FieldSpec("prompt", False, "string", "Listen to the summary"),
        FieldSpec("grammarPointId", False, "ref_grammar", ""),
    ],
    InteractionType.REORDER_SENTENCE: [
        FieldSpec("id", False, "string", ""),
        FieldSpec("scrambled", True, "string_list", []),
        FieldSpec("correct", True, "string_list", []),
        FieldSpec("acceptedAnswers", False, "string_list", []),
        FieldSpec("prompt", False, "string", ""),
        FieldSpec("grammarPointId", False, "ref_grammar", ""),
    ],
    InteractionType.READING_MCQ: [
        FieldSpec("id", False, "string", ""),
        FieldSpec("prompt", True, "string", ""),
        FieldSpec("options", True, "string_list", []),
        FieldSpec("correctIndex", True, "int", 0),
        FieldSpec("grammarPointId", False, "ref_grammar", ""),
    ],
    InteractionType.READING_TRUE_FALSE: [
        FieldSpec("id", False, "string", ""),
        FieldSpec("statement", True, "string", ""),
        FieldSpec("answer", True, "bool", False),
        FieldSpec("grammarPointId", False, "ref_grammar", ""),
    ],
    InteractionType.READING_SHORT_ANSWER: [
        FieldSpec("id", False, "string", ""),
        FieldSpec("prompt", True, "string", ""),
        FieldSpec("expectedAnswer", True, "string", ""),
        FieldSpec("acceptedAnswers", False, "string_list", []),
        FieldSpec("grammarPointId", False, "ref_grammar", ""),
    ],
    # Anki deck imports (app side: interaction.dart AnkiCard / AnkiHtmlCard).
    # Plain-text flip card produced by the GUI importer; sourceNoteId traces
    # back to the originating Anki note.
    InteractionType.ANKI_CARD: [
        FieldSpec("id", False, "string", ""),
        FieldSpec("front", True, "string", ""),
        FieldSpec("back", True, "string", ""),
        FieldSpec("audioAssets", False, "string_list", []),
        FieldSpec("imageAssets", False, "string_list", []),
        FieldSpec("frontAudioAssets", False, "string_list", []),
        FieldSpec("frontImageAssets", False, "string_list", []),
        FieldSpec("backAudioAssets", False, "string_list", []),
        FieldSpec("backImageAssets", False, "string_list", []),
        FieldSpec("hint", False, "string", ""),
        FieldSpec("sourceNoteId", False, "string", ""),
    ],
    # Fidelity-track flip card preserving the original Anki template HTML.
    # wordId is a synthetic anki-<importId>-c<cardId> key, deliberately NOT a
    # ref_word (it does not resolve into vocab.json).
    InteractionType.ANKI_HTML_CARD: [
        FieldSpec("id", False, "string", ""),
        FieldSpec("frontHtml", True, "string", ""),
        FieldSpec("backHtml", True, "string", ""),
        FieldSpec("css", False, "string", ""),
        FieldSpec("mediaBasePath", False, "string", ""),
        FieldSpec("allowJs", False, "bool", False),
        FieldSpec("audioAssets", False, "string_list", []),
        FieldSpec("sourceNoteId", False, "string", ""),
        FieldSpec("sourceCardId", False, "string", ""),
        FieldSpec("wordId", False, "string", ""),
    ],
    # 跟读 (ADR 0061): the learner reads targetText aloud; the app speaks it
    # via TTS as the model (no audioAsset) and scores word-level matching.
    InteractionType.READ_ALOUD: [
        FieldSpec("id", False, "string", ""),
        FieldSpec("targetText", True, "string", ""),
        FieldSpec("prompt", False, "string", "Read the sentence aloud"),
        FieldSpec("grammarPointId", False, "ref_grammar", ""),
    ],
    # 看图回忆 (ADR 0057 §4): prompt is image-only; learner reveals answerText.
    InteractionType.IMAGE_RECALL: [
        FieldSpec("id", False, "string", ""),
        FieldSpec("imageAssets", True, "string_list", []),
        FieldSpec("answerText", True, "string", ""),
        FieldSpec("hint", False, "string", ""),
        FieldSpec("sourceNoteId", False, "string", ""),
    ],
    # 纯音听写 (ADR 0057): prompt is audio-only; learner types expected.
    InteractionType.DICTATION: [
        FieldSpec("id", False, "string", ""),
        FieldSpec("audioAssets", True, "string_list", []),
        FieldSpec("expected", True, "string", ""),
        FieldSpec("hint", False, "string", ""),
        FieldSpec("sourceNoteId", False, "string", ""),
    ],
}


def default_interaction(runtime_type: str) -> dict[str, Any]:
    """Return a minimal valid item dict for the given runtimeType."""
    item: dict[str, Any] = {ItemKey.RUNTIME_TYPE: runtime_type}
    for spec in INTERACTION_SCHEMA[runtime_type]:
        # Deep-copy: defaults in the shared schema table are mutable (lists),
        # handing out the same object would alias state across items.
        item[spec.name] = copy.deepcopy(spec.default)
    return item


def normalize_item(item: dict[str, Any]) -> dict[str, Any]:
    """Ensure item has every schema field (fill defaults for missing)."""
    rt = item.get(ItemKey.RUNTIME_TYPE)
    if rt not in INTERACTION_SCHEMA:
        raise ValueError(f"unknown runtimeType: {rt}")
    out = {ItemKey.RUNTIME_TYPE: rt}
    for spec in INTERACTION_SCHEMA[rt]:
        if spec.name in item:
            out[spec.name] = item[spec.name]
        else:
            out[spec.name] = copy.deepcopy(spec.default)
    return out


#: Content-level metadata keys that survive any template switch (they are
#: resource links, not template-specific shape). switch_template drops keys
#: outside allowed_content_keys, so lesson-scoped links must be listed here.
_CONTENT_META_KEYS: frozenset[str] = frozenset({"linkedGrammarPointIds"})


def allowed_content_keys(template: str) -> set[str]:
    return CONTENT_BY_TEMPLATE.get(template, {ContentKey.STAGES}) | _CONTENT_META_KEYS


def switch_template(lesson: dict[str, Any], new_template: str) -> None:
    """Switch lesson template, keeping only content keys allowed for new template.

    Per guiplan §6.2: when switching template, content shapes not allowed for
    the new template are dropped. The primary content key is initialized empty
    if absent.
    """
    lesson["template"] = new_template
    content = lesson.setdefault("content", {})
    allowed = allowed_content_keys(new_template)
    for key in list(content.keys()):
        if key not in allowed:
            del content[key]
    primary = PRIMARY_CONTENT_KEY.get(new_template, ContentKey.STAGES)
    if primary == ContentKey.READING_PASSAGE:
        if ContentKey.READING_PASSAGE not in content:
            content[ContentKey.READING_PASSAGE] = _empty_reading_passage()
    elif primary and primary not in content:
        content[primary] = []
    if new_template == TemplateType.DIALOGUE and ContentKey.DIALOGUE_SCENE not in content:
        content[ContentKey.DIALOGUE_SCENE] = _empty_dialogue_scene()


def _empty_dialogue_scene() -> dict[str, Any]:
    return {
        "id": short_id("scene"),
        "title": "",
        "characters": [
            {"id": "speaker", "name": "角色", "imageAsset": ""},
            {"id": "learner", "name": "你"},
        ],
        "turns": [],
    }


def _empty_reading_passage() -> dict[str, Any]:
    return {
        "title": "",
        "paragraphs": [],
        "difficulty": 1,
        "linkedWordIds": [],
        "linkedExpressionIds": [],
        "wordFormMap": {},
        "imageAsset": "",
        "imageAlt": "",
    }


def _mcq_options(term: str, pool: list[str]) -> list[str]:
    others = [value for value in pool if value != term]
    distractors = [*others, f"{term}-alt1", f"{term}-alt2"][:2]
    return [term, *distractors]


def _word_groups(words: list[dict[str, Any]]) -> list[list[dict[str, Any]]]:
    return [words[start : start + 4] for start in range(0, len(words), 4)]


def _example_parts(word: dict[str, Any]) -> tuple[str, str]:
    raw = str(word.get("example") or word.get("context") or "").strip()
    if not raw:
        return "", ""
    parts = re.split(r"\s*[—–|]\s*", raw, maxsplit=1)
    target = parts[0].strip()
    meaning = parts[1].strip() if len(parts) > 1 else ""
    return target, meaning


def _word_item(
    runtime_type: str,
    word: dict[str, Any],
    terms: list[str],
    sequence: int,
    *,
    partner_word: dict[str, Any] | None = None,
    choice_slot: int | None = None,
) -> dict[str, Any]:
    wid = word["id"]
    term = word.get("term", wid)
    translation = word.get("translation", "")
    partner_term = str(partner_word.get("term") or "").strip() if partner_word else ""
    partner_tr = str(partner_word.get("translation") or "").strip() if partner_word else ""
    has_partner = bool(partner_term and partner_term != term)
    item: dict[str, Any] = {"runtimeType": runtime_type, "id": short_id(runtime_type[:2])}
    if runtime_type == "multipleChoice":
        preferred = choice_slot if choice_slot is not None else sequence
        options, correct_index = course_pedagogy.arrange_choice(
            _mcq_options(term, terms),
            0,
            seed=f"{wid}:{sequence}",
            preferred_index=preferred,
        )
        item.update(
            {
                "prompt": f"{translation} 是什么意思？",
                "options": options,
                "correctIndex": correct_index,
                "imageAsset": "",
                "grammarPointId": "",
            }
        )
    elif runtime_type == "fillBlank":
        example_target, example_meaning = _example_parts(word)
        blanked = ""
        hint_text = ""
        if example_target and term:
            replaced, count = re.subn(
                rf"(?<!\w){re.escape(term)}(?!\w)",
                "_____",
                example_target,
                count=1,
                flags=re.IGNORECASE,
            )
            if count == 1 and len(course_pedagogy.latin_tokens(re.sub(r"_+", " ", replaced))) >= 1:
                blanked = replaced
                hint_text = example_meaning or translation
        if not blanked:
            if has_partner:
                blanked = f"— {partner_term}!\n— _____!（{translation}）"
            else:
                blanked = f"{term} → _____（{translation}）"
        choices = (
            [term, partner_term]
            if has_partner
            else ([term, *[t for t in terms if t != term][:1]] if len(terms) >= 2 else [])
        )
        if len(choices) >= 2:
            choices, _ = course_pedagogy.arrange_choice(
                choices,
                0,
                seed=f"{wid}:fb:{sequence}",
                preferred_index=sequence,
            )
        payload: dict[str, Any] = {
            "sentence": blanked,
            "answer": term,
            "hint": hint_text,
            "grammarPointId": "",
        }
        if len(choices) >= 2:
            payload["choices"] = choices
        item.update(payload)
    elif runtime_type == "typeTheWord" and word.get("audioAsset"):
        item.update(
            {
                "audioAsset": word["audioAsset"],
                "prompt": translation,
                "expected": term,
                "grammarPointId": "",
            }
        )
    elif runtime_type == "reorderSentence" and (len(term.split()) > 1 or has_partner):
        if len(term.split()) > 1:
            correct = term.split()
            prompt_text = translation
        else:
            correct = [f"{partner_term},", term]
            prompt_text = f"{partner_tr}，{translation}" if partner_tr else translation
        item.update(
            {
                "prompt": prompt_text,
                "scrambled": list(reversed(correct)),
                "correct": correct,
                "grammarPointId": "",
            }
        )
    else:
        if has_partner and (len(term.split()) == 1):
            source_text = f"{partner_tr}，{translation}" if partner_tr else translation
            expected_text = f"{partner_term}, {term}"
        else:
            source_text = translation
            expected_text = term
        item.update(
            {
                "runtimeType": "translateSentence",
                "source": source_text,
                "expected": expected_text,
                "hints": [],
                "grammarPointId": "",
            }
        )
    return item


def _sub_lesson(name: str, items: list[dict[str, Any]]) -> dict[str, Any]:
    return {
        "id": short_id("sl"),
        "name": name,
        "stages": [{"id": short_id("st"), "name": name, "items": items}],
    }


def build_intro_lesson(
    name: str,
    description: str,
    words: list[dict[str, Any]],
) -> dict[str, Any]:
    sub_lessons: list[dict[str, Any]] = []
    for group_index, group in enumerate(_word_groups(words)):
        terms = [word.get("term", word["id"]) for word in group]
        items: list[dict[str, Any]] = []
        mc_count = 0
        for word_index, word in enumerate(group):
            partner = group[(word_index + 1) % len(group)] if len(group) >= 2 else None
            items.append(
                {
                    "runtimeType": "showWord",
                    "id": short_id("sw"),
                    "wordId": word["id"],
                    "context": word.get("example", ""),
                    "grammarPointId": "",
                    "expressionId": "",
                }
            )
            if mc_count < course_pedagogy.INTRO_MAX_WORD_MEANING_MCQ:
                items.append(
                    _word_item(
                        "multipleChoice",
                        word,
                        terms,
                        len(items),
                        partner_word=partner,
                        choice_slot=mc_count,
                    )
                )
                mc_count += 1
                items.append(
                    _word_item(
                        "fillBlank" if word_index % 2 == 0 else "translateSentence",
                        word,
                        terms,
                        len(items),
                        partner_word=partner,
                    )
                )
            else:
                for runtime_type in ("fillBlank", "translateSentence"):
                    items.append(
                        _word_item(
                            runtime_type,
                            word,
                            terms,
                            len(items),
                            partner_word=partner,
                        )
                    )
        target = 15 if len(group) == 4 else course_pedagogy.MIN_SUB_LESSON_ITEMS
        while len(items) < target:
            index = len(items)
            word = group[index % len(group)]
            partner = group[(index + 1) % len(group)] if len(group) >= 2 else None
            if mc_count < course_pedagogy.INTRO_MAX_WORD_MEANING_MCQ:
                runtime_type = "multipleChoice"
                choice_slot: int | None = mc_count
                mc_count += 1
            else:
                runtime_type = "fillBlank" if index % 2 == 0 else "translateSentence"
                choice_slot = None
            items.append(
                _word_item(
                    runtime_type,
                    word,
                    terms,
                    index,
                    partner_word=partner,
                    choice_slot=choice_slot,
                )
            )
        sub_name = name or "认识新词"
        if len(_word_groups(words)) > 1:
            sub_name = f"{sub_name} {group_index + 1}"
        sub_lessons.append(_sub_lesson(sub_name, items))
    return {
        "id": short_id("l"),
        "name": name or "新认识新词课",
        "description": description,
        "type": "normal",
        "template": "intro",
        "prerequisiteLessonIds": [],
        "content": {"subLessons": sub_lessons},
    }


def build_practice_lesson(
    name: str,
    description: str,
    words: list[dict[str, Any]],
    mix_types: tuple[str, ...] = ("multipleChoice", "fillBlank"),
) -> dict[str, Any]:
    allowed = {
        "multipleChoice",
        "fillBlank",
        "translateSentence",
        "typeTheWord",
        "reorderSentence",
    }
    types = [value for value in mix_types if value in allowed] or ["fillBlank"]
    sub_lessons: list[dict[str, Any]] = []
    groups = _word_groups(words)
    for group_index, group in enumerate(groups):
        terms = [word.get("term", word["id"]) for word in group]
        items: list[dict[str, Any]] = []
        while len(items) < course_pedagogy.MIN_SUB_LESSON_ITEMS:
            index = len(items)
            runtime_type = types[index % len(types)]
            word_idx = (index // len(types)) % len(group)
            word = group[word_idx]
            partner = group[(word_idx + 1) % len(group)] if len(group) >= 2 else None
            items.append(_word_item(runtime_type, word, terms, index, partner_word=partner))
        sub_name = name or "巩固练习"
        if len(groups) > 1:
            sub_name = f"{sub_name} {group_index + 1}"
        sub_lessons.append(_sub_lesson(sub_name, items))
    return {
        "id": short_id("l"),
        "name": name or "新巩固练习课",
        "description": description,
        "type": "normal",
        "template": "practice",
        "prerequisiteLessonIds": [],
        "content": {"subLessons": sub_lessons},
    }


def build_review_lesson(
    name: str,
    description: str,
    source_words: list[dict[str, Any]],
    source_expressions: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    expressions = source_expressions or []
    resources: list[tuple[str, dict[str, Any]]] = [
        *[("word", word) for word in source_words]
    ]
    resources.extend(("expression", expression) for expression in expressions)
    if not resources:
        content: dict[str, Any] = {"stages": []}
    else:
        terms = [word.get("term", word["id"]) for word in source_words]
        items: list[dict[str, Any]] = []
        runtime_types = ("fillBlank", "translateSentence", "reorderSentence")
        for index in range(course_pedagogy.REVIEW_POOL_SIZE):
            kind, resource = resources[index % len(resources)]
            partner = (
                source_words[(index + 1) % len(source_words)]
                if len(source_words) >= 2
                else None
            )
            if partner is resource:
                partner = source_words[(index + 2) % len(source_words)] if len(source_words) >= 2 else None
            if kind == "word":
                items.append(
                    _word_item(
                        runtime_types[index % len(runtime_types)],
                        resource,
                        terms,
                        index,
                        partner_word=partner,
                    )
                )
                continue
            term = resource.get("term", resource["id"])
            items.append(
                _word_item(
                    "reorderSentence" if index % 2 else "translateSentence",
                    {"id": resource["id"], "term": term, "translation": resource.get("translation", "")},
                    terms,
                    index,
                    partner_word=partner,
                )
            )
        content = {
            "reviewPolicy": {
                "minItems": course_pedagogy.REVIEW_MIN_ITEMS,
                "maxItems": course_pedagogy.REVIEW_MAX_ITEMS,
                "typeWeights": dict.fromkeys(
                    sorted({item["runtimeType"] for item in items}), 1.0
                ),
            },
            "stages": [
                {"id": short_id("st"), "name": "混合复习题池", "items": items}
            ],
        }
    return {
        "id": short_id("l"),
        "name": name or "新复习课",
        "description": description,
        "type": "review",
        "template": "review",
        "prerequisiteLessonIds": [],
        "content": content,
    }


def short_id(prefix: str) -> str:
    return f"{prefix}-{uuid.uuid4().hex[:8]}"


def new_lesson_from_template(
    template: str,
    unit: dict[str, Any],
    lesson_id: str | None = None,
) -> dict[str, Any]:
    """Clone a template lesson into the unit with a fresh unique id."""
    skeleton = _template_skeleton(template)
    lid = lesson_id or short_id("l")
    skeleton["id"] = lid
    skeleton["name"] = f"New {template} lesson"
    skeleton["description"] = ""
    skeleton["prerequisiteLessonIds"] = []
    if skeleton.get("template") != template:
        switch_template(skeleton, template)
    # Default-inject on new lessons only (never on load/save of existing
    # ones — round-trip must stay byte-identical for untouched lessons).
    skeleton.setdefault("content", {}).setdefault("linkedGrammarPointIds", [])
    unit.setdefault("lessons", []).append(skeleton)
    return skeleton


_TEMPLATE_CACHE: dict[str, dict[str, Any]] = {}


def _template_skeleton(template: str) -> dict[str, Any]:
    import copy
    import json
    from pathlib import Path

    repo = Path(__file__).resolve().parents[4]
    templates_dir = repo / "docs" / "authoring" / "templates"
    file_name = template if template != "legacy" else "review"
    path = templates_dir / f"lesson-{file_name}.json"
    if not path.exists():
        path = templates_dir / "lesson-review.json"
    with path.open("r", encoding="utf-8") as f:
        data = json.load(f)
    return copy.deepcopy(data)


def clone_lesson_with_fresh_ids(
    lesson: dict[str, Any], name: str | None = None
) -> dict[str, Any]:
    """Deep-copy a lesson and regenerate all structural ids so the copy can
    coexist with the original (workshop2 P1 duplicate-lesson support).

    Regenerated: lesson id, subLessons, stages, items, listeningPhases, and
    dialogue scene/turn ids. Dialogue interaction references follow the new
    item ids. External resource and prerequisite references are preserved.
    """
    import copy

    clone = copy.deepcopy(lesson)
    clone["id"] = short_id("l")
    if name is not None:
        clone["name"] = name
    content = clone.get("content", {})
    interaction_ids: dict[str, str] = {}

    def _renew_items(items: list[dict[str, Any]]) -> None:
        for item in items:
            rt = item.get("runtimeType")
            if rt:
                old_id = item.get("id", "")
                item["id"] = short_id(rt[:2])
                if old_id:
                    interaction_ids[old_id] = item["id"]

    for sub in content.get("subLessons", []):
        sub["id"] = short_id("sl")
        for st in sub.get("stages", []):
            st["id"] = short_id("st")
            _renew_items(st.get("items", []))
    for st in content.get("stages", []):
        st["id"] = short_id("st")
        _renew_items(st.get("items", []))
    for ph in content.get("listeningPhases", []):
        ph["id"] = short_id("lp")
        _renew_items(ph.get("items", []))
    scene = content.get(ContentKey.DIALOGUE_SCENE)
    if isinstance(scene, dict):
        scene["id"] = short_id("scene")
        for turn in scene.get("turns", []):
            turn["id"] = short_id("turn")
            old_interaction = turn.get("interactionId")
            if old_interaction in interaction_ids:
                turn["interactionId"] = interaction_ids[old_interaction]
    for page in content.get(ContentKey.PAGES, []):
        if not isinstance(page, dict):
            continue
        page["id"] = short_id("gp")
        for block in page.get("blocks", []):
            if not isinstance(block, dict):
                continue
            block["id"] = short_id("gb")
            if block.get("runtimeType") == "classification":
                cat_map: dict[str, str] = {}
                for category in block.get("categories", []):
                    if isinstance(category, dict):
                        old_cat = str(category.get("id") or "")
                        new_cat = short_id("gc")
                        category["id"] = new_cat
                        if old_cat:
                            cat_map[old_cat] = new_cat
                for card in block.get("cards", []):
                    if isinstance(card, dict):
                        card["id"] = short_id("gcard")
                        old_ref = str(card.get("categoryId") or "")
                        if old_ref in cat_map:
                            card["categoryId"] = cat_map[old_ref]
            elif block.get("runtimeType") == "suffixBuilder":
                for example in block.get("examples", []):
                    if isinstance(example, dict):
                        example["id"] = short_id("gex")
            elif block.get("runtimeType") == "wordOrder":
                for token in block.get("tokens", []):
                    if isinstance(token, dict):
                        token["id"] = short_id("gtok")
    return clone


def clone_unit_with_fresh_ids(
    unit: dict[str, Any], name: str | None = None
) -> dict[str, Any]:
    """Deep-copy a unit and regenerate its id + every lesson's structural ids
    so the copy can coexist with the original.

    Regenerated: unit id, and (via ``clone_lesson_with_fresh_ids``) every
    lesson's id + sub-lesson/stage/item/listeningPhase ids. Preserved (external
    references): ``wordId``, ``expressionId``, ``grammarPointId``. Cleared:
    ``prerequisiteUnitIds`` and each lesson's ``prerequisiteLessonIds`` - a
    freshly-appended unit should not inherit the original's prerequisite chain.
    """
    import copy

    clone = copy.deepcopy(unit)
    clone["id"] = short_id("u")
    if name is not None:
        clone["name"] = name
    clone["prerequisiteUnitIds"] = []
    clone["lessons"] = [
        clone_lesson_with_fresh_ids(lesson) for lesson in clone.get("lessons", [])
    ]
    for lesson in clone["lessons"]:
        lesson["prerequisiteLessonIds"] = []
    return clone


def all_lesson_ids(sections: list[dict[str, Any]]) -> set[str]:
    return {
        lesson["id"]
        for section in sections
        for unit in section.get("units", [])
        for lesson in unit.get("lessons", [])
        if lesson.get("id")
    }


def all_unit_ids(sections: list[dict[str, Any]]) -> set[str]:
    return {
        unit["id"]
        for section in sections
        for unit in section.get("units", [])
        if unit.get("id")
    }


def add_sub_lesson(stage_container: dict[str, Any], name: str = "New sub-lesson") -> dict[str, Any]:
    sub = {
        "id": short_id("sl"),
        "name": name,
        ContentKey.STAGES: [
            {"id": short_id("st"), "name": "Stage 1", ContentKey.ITEMS: []},
        ],
    }
    stage_container.setdefault(ContentKey.SUB_LESSONS, []).append(sub)
    return sub


def add_stage(stage_container: dict[str, Any], name: str = "New stage") -> dict[str, Any]:
    stage = {"id": short_id("st"), "name": name, ContentKey.ITEMS: []}
    stage_container.setdefault(ContentKey.STAGES, []).append(stage)
    return stage


def add_item(stage: dict[str, Any], runtime_type: str) -> dict[str, Any]:
    item = default_interaction(runtime_type)
    item["id"] = short_id(runtime_type[:2])
    stage.setdefault(ContentKey.ITEMS, []).append(item)
    return item


def delete_item(stage: dict[str, Any], item_id: str) -> bool:
    """Remove the item with the given id from the stage. Returns True if found."""
    items = stage.get(ContentKey.ITEMS, [])
    for i, item in enumerate(items):
        if item.get("id") == item_id:
            del items[i]
            return True
    return False


def move_item(stage: dict[str, Any], from_idx: int, to_idx: int) -> None:
    """Move an item within its stage by index."""
    items = stage.get(ContentKey.ITEMS, [])
    if not (0 <= from_idx < len(items) and 0 <= to_idx < len(items)):
        return
    item = items.pop(from_idx)
    items.insert(to_idx, item)


def move_stage(sub_lesson: dict[str, Any], from_idx: int, to_idx: int) -> None:
    """Move a stage within a sub-lesson by index."""
    stages = sub_lesson.get(ContentKey.STAGES, [])
    if not (0 <= from_idx < len(stages) and 0 <= to_idx < len(stages)):
        return
    stage = stages.pop(from_idx)
    stages.insert(to_idx, stage)


def move_sub_lesson(content: dict[str, Any], from_idx: int, to_idx: int) -> None:
    """Move a sub-lesson within the lesson content by index."""
    subs = content.get(ContentKey.SUB_LESSONS, [])
    if not (0 <= from_idx < len(subs) and 0 <= to_idx < len(subs)):
        return
    sub = subs.pop(from_idx)
    subs.insert(to_idx, sub)


def rename_sub_lesson(sub_lesson: dict[str, Any], name: str) -> None:
    """Update the display name of a sub-lesson."""
    sub_lesson["name"] = name


def rename_stage(stage: dict[str, Any], name: str) -> None:
    """Update the display name of a stage."""
    stage["name"] = name


def delete_stage(sub_lesson: dict[str, Any], stage_id: str) -> bool:
    """Remove the stage with the given id from the sub-lesson. Returns True if found."""
    stages = sub_lesson.get(ContentKey.STAGES, [])
    for i, stage in enumerate(stages):
        if stage.get("id") == stage_id:
            del stages[i]
            return True
    return False


def delete_sub_lesson(content: dict[str, Any], sub_lesson_id: str) -> bool:
    """Remove the sub-lesson with the given id from the lesson content. Returns True if found."""
    subs = content.get(ContentKey.SUB_LESSONS, [])
    for i, sub in enumerate(subs):
        if sub.get("id") == sub_lesson_id:
            del subs[i]
            return True
    return False


# Mapping of semantically equivalent fields when switching runtimeType.
# Each tuple lists fields that represent the same concept across different types.
# front/frontHtml join the prompt group and back/backHtml the answer group so
# anki flip cards keep their faces when converted to/from regular types (the
# bool-typed readingTrueFalse.answer stays compatible via switch_runtime_type's
# kind-coercion branch).
_SEMANTIC_FIELD_GROUPS: tuple[tuple[str, ...], ...] = (
    ("prompt", "sentence", "source", "statement", "front", "frontHtml"),
    ("expected", "answer", "expectedAnswer", "answerText", "targetText", "back", "backHtml"),
    ("correctIndex", "correctIndices"),
    ("options",),
    ("choices",),
    ("acceptedAnswers",),
    ("wordId",),
    ("audioAsset",),
    ("audioAssets",),
    ("imageAsset",),
    ("imageAssets",),
    ("context",),
    ("transcript",),
    ("hints",),
    ("hint",),
    ("grammarPointId",),
    ("id",),
)


def _field_to_group(field: str) -> str | None:
    for group in _SEMANTIC_FIELD_GROUPS:
        if field in group:
            return group[0]
    return None


def switch_runtime_type(item: dict[str, Any], new_runtime_type: str) -> dict[str, Any]:
    """Switch an item to a new runtimeType, preserving common/semantic fields.

    The returned dict is a new item; the caller is responsible for replacing the
    old item in the containing list.  The original ``id`` is always kept so
    that references (e.g. from a lesson wizard) remain stable.
    """
    if new_runtime_type not in INTERACTION_SCHEMA:
        raise ValueError(f"unknown runtimeType: {new_runtime_type}")

    new_item = default_interaction(new_runtime_type)
    new_schema = INTERACTION_SCHEMA[new_runtime_type]
    new_field_names = {spec.name for spec in new_schema}

    # Build a mapping from the new item's canonical field name to the best old value.
    semantic_values: dict[str, Any] = {}
    for old_field, old_value in item.items():
        if old_field == ItemKey.RUNTIME_TYPE:
            continue
        if old_field in new_field_names:
            semantic_values[old_field] = old_value
            continue
        group = _field_to_group(old_field)
        if group is None:
            continue
        # Capture under the group's canonical name (first field in the group
        # wins); the apply phase resolves it onto whichever group member the
        # new schema actually has.
        if group not in semantic_values:
            semantic_values[group] = old_value

    # Apply preserved values, but only if the type is compatible.
    for spec in new_schema:
        name = spec.name
        if name == ItemKey.RUNTIME_TYPE:
            continue
        if name == "id":
            new_item[name] = item.get("id") or new_item[name]
            continue
        # Resolve the value: same-named field first, otherwise the semantic
        # group's captured value (so front -> sentence lands even though the
        # group's canonical name is "prompt" and fillBlank has no such field).
        value: Any = None
        if name in semantic_values:
            value = semantic_values[name]
        else:
            group = _field_to_group(name)
            if group is not None:
                value = semantic_values.get(group)
        if value is None:
            continue
        if spec.kind == "string_list" and not isinstance(value, list):
            continue
        if spec.kind == "int_list" and not isinstance(value, list):
            continue
        if spec.kind == "int" and not isinstance(value, int):
            try:
                value = int(value)
            except (TypeError, ValueError):
                continue
        if spec.kind == "bool" and not isinstance(value, bool):
            if isinstance(value, str):
                value = value.lower() in ("true", "1", "yes")
            else:
                continue
        new_item[name] = value

    return normalize_item(new_item)


def add_listening_phase(
    lesson: dict[str, Any],
    phase_type: str = ListeningPhaseType.WORD_PAIRING,
    name: str = "New phase",
) -> dict[str, Any]:
    phase: dict[str, Any] = {
        "id": short_id("lp"),
        "name": name,
        "type": phase_type,
    }
    if phase_type in (ListeningPhaseType.WORD_PAIRING, ListeningPhaseType.DIALOGUE):
        phase[ContentKey.ITEMS] = []
    if phase_type in (ListeningPhaseType.DIALOGUE, ListeningPhaseType.SUMMARY):
        phase["audioAsset"] = ""
        phase["transcript"] = ""
    lesson.setdefault("content", {}).setdefault(ContentKey.LISTENING_PHASES, []).append(phase)
    return phase


def delete_listening_phase(lesson: dict[str, Any], phase_id: str) -> bool:
    """Remove the listening phase with the given id. Returns True if found."""
    phases = lesson.get("content", {}).get(ContentKey.LISTENING_PHASES, [])
    for i, phase in enumerate(phases):
        if phase.get("id") == phase_id:
            del phases[i]
            return True
    return False


def move_listening_phase(lesson: dict[str, Any], from_idx: int, to_idx: int) -> None:
    """Move a listening phase by index."""
    phases = lesson.get("content", {}).get(ContentKey.LISTENING_PHASES, [])
    if not (0 <= from_idx < len(phases) and 0 <= to_idx < len(phases)):
        return
    phase = phases.pop(from_idx)
    phases.insert(to_idx, phase)


def rename_listening_phase(phase: dict[str, Any], name: str) -> None:
    """Update the display name of a listening phase."""
    phase["name"] = name


def listening_phase_has_items(phase_type: str) -> bool:
    """Return True if the listening phase type supports items."""
    return phase_type in (ListeningPhaseType.WORD_PAIRING, ListeningPhaseType.DIALOGUE)


GUIDE_BLOCK_TYPES: tuple[str, ...] = (
    "text",
    "terms",
    "classification",
    "suffixBuilder",
    "wordOrder",
)

GUIDE_BLOCK_LABELS: dict[str, str] = {
    "text": "说明文本",
    "terms": "点读词卡",
    "classification": "互动分类",
    "suffixBuilder": "词缀拼接",
    "wordOrder": "语序探索",
}


def default_guide_block(block_type: str) -> dict[str, Any]:
    """Return a minimal valid GuideBlock dict matching ``lib/domain/course/guide_page.dart``."""
    bid = short_id("gb")
    if block_type == "text":
        return {"runtimeType": "text", "id": bid, "title": "", "body": "请输入说明内容。"}
    if block_type == "terms":
        return {
            "runtimeType": "terms",
            "id": bid,
            "title": "词汇与例词",
            "compact": False,
            "items": [
                {"text": "Merhaba", "translation": "你好", "note": "", "speechText": None, "wordId": None}
            ],
        }
    if block_type == "classification":
        c1, c2 = short_id("gc"), short_id("gc")
        return {
            "runtimeType": "classification",
            "id": bid,
            "title": "分类体验",
            "instruction": "把下面的卡片分到对应类别。",
            "categories": [
                {"id": c1, "label": "类别 A", "description": ""},
                {"id": c2, "label": "类别 B", "description": ""},
            ],
            "cards": [
                {"id": short_id("gcard"), "text": "示例词", "categoryId": c1, "hint": "", "highlight": ""}
            ],
            "completionNote": "",
        }
    if block_type == "suffixBuilder":
        return {
            "runtimeType": "suffixBuilder",
            "id": bid,
            "title": "词缀拼接",
            "instruction": "点击逐步加上词尾，观察含义变化。",
            "examples": [
                {
                    "id": short_id("gex"),
                    "root": "ev",
                    "rootMeaning": "家",
                    "label": "",
                    "steps": [
                        {"suffix": "-ler", "result": "evler", "meaning": "房子们"}
                    ],
                }
            ],
        }
    if block_type == "wordOrder":
        return {
            "runtimeType": "wordOrder",
            "id": bid,
            "title": "语序结构",
            "translation": "我喝茶。",
            "tokens": [
                {"id": short_id("gtok"), "text": "Ben", "role": "主语", "meaning": "我", "optional": True},
                {"id": short_id("gtok"), "text": "çay", "role": "宾语", "meaning": "茶", "optional": False},
                {"id": short_id("gtok"), "text": "içiyorum", "role": "动词", "meaning": "喝", "optional": False},
            ],
            "optionalToggleLabel": "省略主语代词",
            "note": "",
        }
    raise ValueError(f"unknown guide block runtimeType: {block_type}")


def add_guide_page(content: dict[str, Any], title: str = "新导览页") -> dict[str, Any]:
    page: dict[str, Any] = {
        "id": short_id("gp"),
        "title": title,
        "kicker": "",
        "intro": "",
        "blocks": [default_guide_block("text")],
    }
    content.setdefault(ContentKey.PAGES, []).append(page)
    return page


def delete_guide_page(content: dict[str, Any], page_id: str) -> bool:
    pages = content.get(ContentKey.PAGES, [])
    for idx, page in enumerate(pages):
        if page.get("id") == page_id:
            del pages[idx]
            return True
    return False


def move_guide_page(content: dict[str, Any], from_idx: int, to_idx: int) -> None:
    pages = content.get(ContentKey.PAGES, [])
    if not (0 <= from_idx < len(pages) and 0 <= to_idx < len(pages)):
        return
    page = pages.pop(from_idx)
    pages.insert(to_idx, page)


def add_guide_block(page: dict[str, Any], block_type: str = "text") -> dict[str, Any]:
    block = default_guide_block(block_type)
    page.setdefault("blocks", []).append(block)
    return block


def delete_guide_block(page: dict[str, Any], block_id: str) -> bool:
    blocks = page.get("blocks", [])
    for idx, block in enumerate(blocks):
        if block.get("id") == block_id:
            del blocks[idx]
            return True
    return False


def move_guide_block(page: dict[str, Any], from_idx: int, to_idx: int) -> None:
    blocks = page.get("blocks", [])
    if not (0 <= from_idx < len(blocks) and 0 <= to_idx < len(blocks)):
        return
    block = blocks.pop(from_idx)
    blocks.insert(to_idx, block)


SLUG_RE = re.compile(r"[^a-z0-9]+")


def slugify(text: str) -> str:
    return SLUG_RE.sub("-", text.lower()).strip("-")
