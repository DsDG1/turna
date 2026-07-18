"""Functional-lesson preset library (workshop2 P1).

Opinionated, out-of-the-box lesson skeletons for the functional templates
(listening / reading / mastery) plus convenience presets for intro/practice.
Each preset builds a complete, validator-passing lesson dict with fresh ids,
suitable for seeding a new lesson directly or feeding the functional-lesson
wizard (P2).

Pure-Python (no PySide6) so it is unit-testable without a display, mirroring
``lesson_content.build_intro_lesson``.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Callable

from src.backend.lesson_content import default_interaction, short_id


def _item(runtime_type: str, **overrides: Any) -> dict[str, Any]:
    """A schema-valid interaction with the given fields overridden.

    ``default_interaction`` guarantees every schema field exists with a valid
    default; we then apply the meaningful overrides and ensure a fresh id so
    the item is ready to drop into a stage.
    """
    item = default_interaction(runtime_type)
    item.update(overrides)
    if not item.get("id"):
        item["id"] = short_id(runtime_type[:2])
    return item


def _listening_three_phase(name: str) -> dict[str, Any]:
    """听力三阶段: wordPairing -> dialogue -> summary."""
    return {
        "id": short_id("l"),
        "name": name or "听力训练",
        "description": "三阶段听力课：听音选词 -> 对话理解 -> 摘要回顾。",
        "type": "listening",
        "template": "listening",
        "prerequisiteLessonIds": [],
        "content": {
            "listeningPhases": [
                {
                    "id": short_id("lp"),
                    "name": "听音选词",
                    "type": "wordPairing",
                    "items": [
                        _item(
                            "listenAndPick",
                            prompt="你听到的是哪个词？",
                            options=["选项A", "选项B", "选项C"],
                            correctIndex=0,
                            audioAsset="",
                        )
                    ],
                },
                {
                    "id": short_id("lp"),
                    "name": "对话理解",
                    "type": "dialogue",
                    "audioAsset": "",
                    "transcript": "",
                    "items": [
                        _item(
                            "multipleChoice",
                            prompt="这段对话在讲什么？",
                            options=["选项A", "选项B", "选项C"],
                            correctIndex=0,
                        )
                    ],
                },
                {
                    "id": short_id("lp"),
                    "name": "摘要回顾",
                    "type": "summary",
                    "audioAsset": "",
                    "transcript": "",
                },
            ]
        },
    }


def _reading_three_q(name: str) -> dict[str, Any]:
    """阅读理解·三类题: passage + readingMcq + readingTrueFalse + readingShortAnswer."""
    return {
        "id": short_id("l"),
        "name": name or "阅读理解",
        "description": "阅读篇章 + 选择/判断/简答三类理解题。",
        "type": "reading",
        "template": "reading",
        "prerequisiteLessonIds": [],
        "content": {
            "readingPassage": {
                "title": "阅读篇章标题",
                "paragraphs": ["在此填写第一段。", "在此填写第二段。"],
                "difficulty": 1,
                "linkedWordIds": [],
                "linkedExpressionIds": [],
            },
            "stages": [
                {
                    "id": short_id("st"),
                    "name": "Comprehension",
                    "items": [
                        _item(
                            "readingMcq",
                            prompt="这篇文章主要讲什么？",
                            options=["选项A", "选项B", "选项C"],
                            correctIndex=0,
                        ),
                        _item(
                            "readingTrueFalse",
                            statement="请填写一个判断句。",
                            answer=True,
                        ),
                        _item(
                            "readingShortAnswer",
                            prompt="请填写一道简答题。",
                            expectedAnswer="",
                        ),
                    ],
                }
            ],
        },
    }


def _mastery_mix(name: str) -> dict[str, Any]:
    """综合测验: single stage with a mixed-question set."""
    return {
        "id": short_id("l"),
        "name": name or "综合测验",
        "description": "单步骤综合测验：选择 + 填空 + 翻译。",
        "type": "challenge",
        "template": "mastery",
        "prerequisiteLessonIds": [],
        "content": {
            "stages": [
                {
                    "id": short_id("st"),
                    "name": "Check",
                    "items": [
                        _item(
                            "multipleChoice",
                            prompt="请填写选择题题干",
                            options=["选项A", "选项B", "选项C"],
                            correctIndex=0,
                        ),
                        _item(
                            "fillBlank",
                            sentence="___ 请填写填空题",
                            answer="",
                            hint="",
                        ),
                        _item(
                            "translateSentence",
                            source="请填写待翻译句",
                            expected="",
                            hints=[],
                        ),
                    ],
                }
            ]
        },
    }


def _intro_three_step(name: str) -> dict[str, Any]:
    """认识新词·三步: one sub-lesson, showWord -> translate -> fillBlank."""
    return {
        "id": short_id("l"),
        "name": name or "认识新词",
        "description": "认识新词课骨架：展示 -> 翻译 -> 填空。",
        "type": "normal",
        "template": "intro",
        "prerequisiteLessonIds": [],
        "content": {
            "subLessons": [
                {
                    "id": short_id("sl"),
                    "name": "新词 1",
                    "stages": [
                        {
                            "id": short_id("st"),
                            "name": "展示",
                            "items": [_item("showWord", wordId="")],
                        },
                        {
                            "id": short_id("st"),
                            "name": "翻译",
                            "items": [
                                _item(
                                    "translateSentence",
                                    source="",
                                    expected="",
                                    hints=[],
                                )
                            ],
                        },
                        {
                            "id": short_id("st"),
                            "name": "填空",
                            "items": [_item("fillBlank", sentence="___", answer="", hint="")],
                        },
                    ],
                }
            ]
        },
    }


def _practice_mix(name: str) -> dict[str, Any]:
    """巩固练习: one sub-lesson with a mixed practice stage."""
    return {
        "id": short_id("l"),
        "name": name or "巩固练习",
        "description": "巩固练习课骨架：选择 + 填空 + 听写。",
        "type": "normal",
        "template": "practice",
        "prerequisiteLessonIds": [],
        "content": {
            "subLessons": [
                {
                    "id": short_id("sl"),
                    "name": "练习 1",
                    "stages": [
                        {
                            "id": short_id("st"),
                            "name": "练习",
                            "items": [
                                _item(
                                    "multipleChoice",
                                    prompt="请填写题干",
                                    options=["A", "B", "C"],
                                    correctIndex=0,
                                ),
                                _item("fillBlank", sentence="___", answer="", hint=""),
                                _item(
                                    "typeTheWord",
                                    prompt="听写",
                                    expected="",
                                    audioAsset="",
                                ),
                            ],
                        }
                    ],
                }
            ]
        },
    }


@dataclass(frozen=True)
class LessonPreset:
    """A named, buildable lesson skeleton tied to one template."""

    id: str
    label: str
    template: str
    description: str
    build: Callable[[str], dict[str, Any]]


FUNCTIONAL_PRESETS: list[LessonPreset] = [
    LessonPreset(
        "listening-3phase", "听力三阶段", "listening",
        "wordPairing -> dialogue -> summary 三阶段听力课", _listening_three_phase,
    ),
    LessonPreset(
        "reading-3q", "阅读理解·三类题", "reading",
        "阅读篇章 + 选择/判断/简答", _reading_three_q,
    ),
    LessonPreset(
        "mastery-mix", "综合测验·混合题", "mastery",
        "单步骤选择 + 填空 + 翻译", _mastery_mix,
    ),
    LessonPreset(
        "intro-3step", "认识新词·三步", "intro",
        "展示 -> 翻译 -> 填空 骨架", _intro_three_step,
    ),
    LessonPreset(
        "practice-mix", "巩固练习·混合", "practice",
        "选择 + 填空 + 听写 骨架", _practice_mix,
    ),
]

#: Functional templates the wizard treats as "功能课" (P2 entry point).
FUNCTIONAL_TEMPLATES: tuple[str, ...] = ("listening", "reading", "mastery")

PRESET_BY_ID: dict[str, LessonPreset] = {p.id: p for p in FUNCTIONAL_PRESETS}


def presets_for_template(template: str) -> list[LessonPreset]:
    """Return presets whose template matches (for the wizard's preset picker)."""
    return [p for p in FUNCTIONAL_PRESETS if p.template == template]


def build_preset_lesson(preset_id: str, name: str = "") -> dict[str, Any]:
    """Build a fresh lesson dict from a preset. Raises KeyError if unknown."""
    preset = PRESET_BY_ID[preset_id]
    return preset.build(name)


def apply_preset_to_lesson(lesson: dict[str, Any], preset_id: str) -> dict[str, Any]:
    """Replace an existing lesson's template + content with a preset's, keeping
    its id / name / description / prerequisites (workshop2 P5 bulk-apply).

    Returns the same lesson dict (mutated in place) for convenience.
    """
    preset = PRESET_BY_ID[preset_id]
    fresh = preset.build(lesson.get("name", ""))
    lesson["template"] = fresh["template"]
    lesson["type"] = fresh.get("type", lesson.get("type", "normal"))
    lesson["content"] = fresh["content"]
    return lesson
