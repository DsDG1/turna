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


def field_label(field: str) -> str:
    """Return the teacher-facing label for an engineering field name."""
    return FIELD_LABELS.get(field, field)


def layer_label(layer: str) -> str:
    """Return the teacher-facing label for a nested content layer."""
    return NESTED_LAYER_LABELS.get(layer, layer)


def interaction_label(runtime_type: str) -> str:
    return INTERACTION_LABELS.get(runtime_type, runtime_type)


def template_label(template: str) -> str:
    return TEMPLATE_LABELS.get(template, template)


def is_hidden(field: str) -> bool:
    """Whether a field should be hidden from the teacher view entirely."""
    return field in HIDDEN_FIELDS
