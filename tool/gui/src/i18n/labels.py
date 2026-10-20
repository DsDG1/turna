"""Teacher-view field name mapping (guiplan §15.2, T.1).

Maps engineering field names to teacher-facing teaching language. This is a
pure display-layer mapping; it never alters the JSON contract (§15.13). The
runtime-type and template labels are re-exported from lesson_content so there
is a single source of truth, then extended with nested-layer names and
per-field display rules.

**Scope — this is NOT an i18n layer.** It covers *domain field names*
(``frontHtml`` → 「正面 HTML」) only. UI chrome copy (button labels, tooltips,
dialog titles) is Chinese literals inline at the call site — this tool is a
single-language internal creator tool, and a full i18n sweep is not planned.
Do not look here to change button or dialog copy; grep for the literal
instead. The package is named ``i18n`` for historical reasons.
"""
from __future__ import annotations

from src.backend.lesson_content import INTERACTION_LABELS, TEMPLATE_LABELS

NESTED_LAYER_LABELS: dict[str, str] = {
    "section": "章节",
    "unit": "单元",
    "lesson": "课",
    "subLessons": "教学环节",
    "subLesson": "教学环节",
    "stages": "教学步骤",
    "stage": "教学步骤",
    "items": "题目",
    "item": "题目",
    "listeningPhases": "听力阶段",
    "readingPassage": "阅读材料",
}

FIELD_LABELS: dict[str, str] = {
    "id": "编号",
    "name": "名称",
    "description": "描述",
    "term": "词",
    "translation": "翻译",
    "pronunciation": "发音",
    "audioAsset": "音频",
    "audioAssets": "音频列表",
    "imageAssets": "图片列表",
    "tags": "标签",
    "wordId": "词",
    "expressionId": "表达",
    "grammarPointId": "语法点",
    "linkedGrammarPointIds": "关联语法点",
    "prompt": "题干",
    "options": "选项",
    "correctIndex": "正确答案",
    "correctIndices": "正确答案",
    "sentence": "句子",
    "answer": "答案",
    "source": "原文",
    "expected": "期望译文",
    "hints": "提示",
    "scrambled": "打乱顺序",
    "correct": "正确顺序",
    "statement": "陈述",
    "expectedAnswer": "参考答案",
    "transcript": "原文",
    "context": "上下文",
    "example": "例句",
    "front": "正面",
    "back": "背面",
    "frontHtml": "正面 HTML",
    "backHtml": "背面 HTML",
    "pos": "词性",
    "prerequisiteLessonIds": "先修课",
    "prerequisiteSectionIds": "先修章节",
    "title": "标题",
    "explanation": "解释",
    "exampleExpressionIds": "示例表达",
    "exampleSentenceIds": "示例句子",
}

HIDDEN_FIELDS: set[str] = {
    "id",
    "grammarPointId",
    "imageAsset",
    "minSelections",
    "maxSelections",
    "runtimeType",
    # Anki provenance / WebView plumbing — noise for the teacher view.
    "sourceNoteId",
    "sourceCardId",
    "mediaBasePath",
    "allowJs",
}

LEVEL_LABELS: dict[str, str] = {
    "A1": "入门",
    "A2": "初级",
    "B1": "中级",
    "B2": "中高级",
}


# T22: the English mirrors (FIELD_LABELS_EN / NESTED_LAYER_LABELS_EN /
# LEVEL_LABELS_EN, ~60 lines) were removed. No settings entry, CLI flag or
# caller could ever reach them — every call site uses the zh default — so
# they were dead weight that read like a working feature. If English is ever
# wanted, build it as a real feature with a locale setting behind it; the
# ``locale`` parameter below is kept so that wiring has somewhere to land.
_LOCALE_TABLES = {
    "zh": (FIELD_LABELS, NESTED_LAYER_LABELS, LEVEL_LABELS),
}


def _resolve_locale(locale: str) -> str:
    return locale if locale in _LOCALE_TABLES else "zh"


def field_label(field: str, locale: str = "zh") -> str:
    """Return the teacher-facing label for an engineering field name."""
    table = _LOCALE_TABLES.get(_resolve_locale(locale), _LOCALE_TABLES["zh"])[0]
    return table.get(field, field)


def layer_label(layer: str, locale: str = "zh") -> str:
    """Return the teacher-facing label for a nested content layer."""
    table = _LOCALE_TABLES.get(_resolve_locale(locale), _LOCALE_TABLES["zh"])[1]
    return table.get(layer, layer)


def interaction_label(runtime_type: str) -> str:
    return INTERACTION_LABELS.get(runtime_type, runtime_type)


def template_label(template: str) -> str:
    return TEMPLATE_LABELS.get(template, template)


def is_hidden(field: str) -> bool:
    """Whether a field should be hidden from the teacher view entirely."""
    return field in HIDDEN_FIELDS
