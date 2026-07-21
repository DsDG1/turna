"""Pedagogy / CEFR / distractor prompt blocks for AI course generation.

Pure strings and small tables — no Qt. Injected into ``build_prompt`` so the
model produces more lesson-like gradients and better multiple-choice options.
"""
from __future__ import annotations

# Soft caps used only in prompt text (not enforced by the validator).
_LEVEL_GUIDE: dict[str, dict[str, str]] = {
    "A1": {
        "new_words": "每课新词建议 4–8 个",
        "sentence": "句子短（约 3–8 词），现在时为主，少从句",
        "focus": "认读与跟说：showWord / listenAndPick / 简单 translate",
    },
    "A2": {
        "new_words": "每课新词建议 6–12 个",
        "sentence": "可出现简单复合句与常用时态对比",
        "focus": "巩固产出：fillBlank / reorderSentence / 对话 listening",
    },
    "B1": {
        "new_words": "每课新词建议 8–15 个",
        "sentence": "中等句长，可含原因/条件从句",
        "focus": "综合运用：reading + multiSelect + 情境 translate",
    },
    "B2": {
        "new_words": "每课新词建议 10–18 个",
        "sentence": "较长语篇与抽象话题，注意语域",
        "focus": "mastery 综合与阅读推断题",
    },
}

_TEMPLATE_GRADIENT: dict[str, str] = {
    "intro": "intro：先 showWord 展示，再轻量识别/翻译，避免一上来高产出。",
    "practice": "practice：以练习为主（选择、填空、翻译、排序），复现本课词。",
    "review": "review：以复现与对比为主，少引入全新词。",
    "listening": "listening：wordPairing → dialogue → summary 递进；听前有提示。",
    "reading": "reading：短文 + 理解题（MCQ/判断/简答），生词先在文中可猜。",
    "mastery": "mastery：综合测验，题型多样，覆盖本单元核心词与结构。",
    "mixed": "mixed：单元内按 intro→practice→listening/reading→mastery 梯度排布。",
    "legacy": "legacy：保持题型自洽，优先可教性。",
}

_LANGUAGE_PACKS: dict[str, str] = {
    "turkish": (
        "目标语 Turkish 注意：\n"
        "1. 专名与问候保持正确大小写（如 Merhaba、Teşekkürler）。\n"
        "2. 元音和谐：后缀形式与词干元音一致（不要混用错误变体当干扰项的唯一手段）。\n"
        "3. 敬语/通称：A1 可用 sen；涉及礼貌场景可出现 siz，并在题干说明。\n"
        "4. 干扰项优先用同词性近义/近形词，避免无意义的乱码拼写。"
    ),
    "default": (
        "目标语通用注意：\n"
        "1. term 必须是目标语正确形式；translation 用源语言（提示语言）。\n"
        "2. 干扰项与正确项词性、长度接近；禁止四个选项里三个明显荒谬。\n"
        "3. 不要输出无法朗读的乱码或空 translation。"
    ),
}


def _normalize_level(level: str) -> str:
    raw = (level or "A1").strip().upper()
    if raw.startswith("A1"):
        return "A1"
    if raw.startswith("A2"):
        return "A2"
    if raw.startswith("B1"):
        return "B1"
    if raw.startswith("B2"):
        return "B2"
    return "A1"


def _normalize_language(language: str) -> str:
    key = (language or "").strip().lower()
    if key in ("turkish", "tr", "türkçe", "turkce"):
        return "turkish"
    return "default"


def distractor_rules_block() -> str:
    return (
        "选择题干扰项规则：\n"
        "1. 提供 4 个选项时，正确项唯一；options 内不要重复字符串。\n"
        "2. 干扰项与正确项词性相近、长度接近，优先近义/主题相关词。\n"
        "3. 不要用明显错误编码、空串或与题干语言不一致的乱码当唯一干扰策略。\n"
        "4. correctIndex / correctIndices 必须指向真实正确选项。"
    )


def language_pack_block(language: str) -> str:
    return _LANGUAGE_PACKS[_normalize_language(language)]


def level_guide_block(level: str) -> str:
    guide = _LEVEL_GUIDE[_normalize_level(level)]
    return (
        f"CEFR {_normalize_level(level)} 约束（软性，尽量遵守）：\n"
        f"- 词汇量：{guide['new_words']}\n"
        f"- 句子：{guide['sentence']}\n"
        f"- 重点：{guide['focus']}"
    )


def template_gradient_block(template: str) -> str:
    tpl = (template or "mixed").strip() or "mixed"
    line = _TEMPLATE_GRADIENT.get(tpl, _TEMPLATE_GRADIENT["mixed"])
    return f"课型梯度：{line}"


def pedagogy_prompt_block(
    *,
    level: str = "A1",
    language: str = "Turkish",
    template: str = "mixed",
) -> str:
    """Full pedagogy block for generation / edit prompts."""
    parts = [
        "## 教学法与质量约束",
        level_guide_block(level),
        "",
        template_gradient_block(template),
        "",
        distractor_rules_block(),
        "",
        language_pack_block(language),
        "",
        "复现：本课新词应在至少一道练习题中再次出现（不仅 showWord）。",
    ]
    return "\n".join(parts)
