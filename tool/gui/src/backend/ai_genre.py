"""Genre tag mapping and template helpers for the AI course generator.

This module keeps the mapping between user-facing genre tags like ``[intro]``
and the internal lesson templates, so both the prompt builder and the UI can
share the same source of truth.
"""
from __future__ import annotations

import re
from typing import Any


GENRE_TEMPLATES: dict[str, dict[str, Any]] = {
    "[intro]": {
        "template": "intro",
        "label": "认识新词",
        "primary_key": "subLessons",
        "description": "通过展示新词、翻译句子和填空引导学生认识生词。",
        "suggested_types": ["showWord", "translateSentence", "fillBlank"],
    },
    "[practice]": {
        "template": "practice",
        "label": "巩固练习",
        "primary_key": "subLessons",
        "description": "通过多轮互动练习巩固词汇和句型。",
        "suggested_types": ["multipleChoice", "translateSentence", "fillBlank", "reorderSentence"],
    },
    "[review]": {
        "template": "review",
        "label": "复习",
        "primary_key": "subLessons",
        "description": "复习已学内容，可混合使用 subLessons 和 stages。",
        "suggested_types": ["multipleChoice", "fillBlank", "translateSentence"],
    },
    "[listening]": {
        "template": "listening",
        "label": "听力训练",
        "primary_key": "listeningPhases",
        "description": "通过听力阶段训练学生的听力理解。",
        "suggested_types": ["listenAndPick", "typeTheWord", "listenOnly"],
    },
    "[reading]": {
        "template": "reading",
        "label": "阅读理解",
        "primary_key": "readingPassage",
        "description": "提供阅读材料并配合阅读理解题目。",
        "suggested_types": ["readingMcq", "readingTrueFalse", "readingShortAnswer"],
    },
    "[mastery]": {
        "template": "mastery",
        "label": "综合测验",
        "primary_key": "stages",
        "description": "单元末综合测验，覆盖多种题型。",
        "suggested_types": ["multipleChoice", "translateSentence", "fillBlank", "multiSelect"],
    },
    "[mixed]": {
        "template": "mixed",
        "label": "混合",
        "primary_key": "",
        "description": "在一个 section 中混合使用多种模板，适合综合课程。",
        "suggested_types": [],
    },
}


TEMPLATE_LABELS: dict[str, str] = {
    "intro": "认识新词",
    "practice": "巩固练习",
    "review": "复习",
    "listening": "听力训练",
    "reading": "阅读理解",
    "mastery": "综合测验",
    "mixed": "混合",
}


TAG_RE = re.compile(r"\[([a-zA-Z]+)\]")


def genre_to_template(genre: str) -> str:
    """Map a genre tag (with or without brackets) to a template name."""
    key = genre.lower().strip()
    if not key.startswith("["):
        key = f"[{key}]"
    meta = GENRE_TEMPLATES.get(key)
    return meta["template"] if meta else "mixed"


def template_label(template: str) -> str:
    """Return the human-readable label for a template."""
    return TEMPLATE_LABELS.get(template, template)


def parse_genre_tag(text: str) -> str | None:
    """Return the first recognized genre tag from ``text``, or None."""
    if not text:
        return None
    for match in TAG_RE.finditer(text):
        tag = f"[{match.group(1).lower()}]"
        if tag in GENRE_TEMPLATES:
            return tag
    return None


def all_genre_tags() -> list[str]:
    """Return all recognized genre tags including brackets."""
    return list(GENRE_TEMPLATES.keys())


def genre_prompt_block() -> str:
    """Return a prompt block that explains available genre tags to the model."""
    lines = ["可用 genre 标签（用户可在主题或额外指令中插入这些标签来指定模板）："]
    for tag, meta in GENRE_TEMPLATES.items():
        lines.append(
            f"{tag} → {meta['label']}（template={meta['template']}，"
            f"主键={meta['primary_key'] or '混合'}）：{meta['description']}"
        )
    lines.append(
        "规则：如果用户在主题或额外指令中插入了 genre 标签，"
        "请按标签为对应单元或课时生成相应模板结构；未标注的部分回退到默认模板。"
    )
    return "\n".join(lines)


def genre_tags_in_text(text: str) -> list[str]:
    """Return all recognized genre tags found in ``text``, in order."""
    found: list[str] = []
    for match in TAG_RE.finditer(text):
        tag = f"[{match.group(1).lower()}]"
        if tag in GENRE_TEMPLATES and tag not in found:
            found.append(tag)
    return found
