"""Teacher-view field name mapping (guiplan §15.2, T.1).

Maps engineering field names to teacher-facing teaching language. This is a
pure display-layer mapping; it never alters the JSON contract (§15.13). The
runtime-type and template labels are re-exported from lesson_content so there
is a single source of truth, then extended with nested-layer names and
per-field display rules.
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
    "tags": "标签",
    "wordId": "词",
    "expressionId": "表达",
    "grammarPointId": "语法点",
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
}

LEVEL_LABELS: dict[str, str] = {
    "A1": "入门",
    "A2": "初级",
    "B1": "中级",
    "B2": "中高级",
}

# English mirror for teacher-facing labels (C4 locale groundwork).
# ``zh`` remains the default to preserve backward compatibility; pass
# ``locale="en"`` to access the English forms.
FIELD_LABELS_EN: dict[str, str] = {
    "id": "ID",
    "name": "Name",
    "description": "Description",
    "term": "Word",
    "translation": "Translation",
    "pronunciation": "Pronunciation",
    "audioAsset": "Audio",
    "tags": "Tags",
    "wordId": "Word",
    "expressionId": "Expression",
    "grammarPointId": "Grammar point",
    "prompt": "Prompt",
    "options": "Options",
    "correctIndex": "Correct answer",
    "correctIndices": "Correct answers",
    "sentence": "Sentence",
    "answer": "Answer",
    "source": "Source text",
    "expected": "Expected translation",
    "hints": "Hints",
    "scrambled": "Scrambled",
    "correct": "Correct order",
    "statement": "Statement",
    "expectedAnswer": "Expected answer",
    "transcript": "Transcript",
    "context": "Context",
    "prerequisiteLessonIds": "Prerequisite lessons",
    "prerequisiteSectionIds": "Prerequisite sections",
    "title": "Title",
    "explanation": "Explanation",
    "exampleExpressionIds": "Example expressions",
    "exampleSentenceIds": "Example sentences",
}

NESTED_LAYER_LABELS_EN: dict[str, str] = {
    "section": "Section",
    "unit": "Unit",
    "lesson": "Lesson",
    "subLessons": "Teaching segments",
    "subLesson": "Teaching segment",
    "stages": "Teaching steps",
    "stage": "Teaching step",
    "items": "Questions",
    "item": "Question",
    "listeningPhases": "Listening phases",
    "readingPassage": "Reading passage",
}

LEVEL_LABELS_EN: dict[str, str] = {
    "A1": "Beginner",
    "A2": "Elementary",
    "B1": "Intermediate",
    "B2": "Upper-intermediate",
}

_LOCALE_TABLES = {
    "zh": (FIELD_LABELS, NESTED_LAYER_LABELS, LEVEL_LABELS),
    "en": (FIELD_LABELS_EN, NESTED_LAYER_LABELS_EN, LEVEL_LABELS_EN),
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
