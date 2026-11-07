from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass
from typing import Any

from src.backend.lesson_content import (
    build_intro_lesson,
    build_practice_lesson,
    default_interaction,
    short_id,
)


def _item(runtime_type: str, **overrides: Any) -> dict[str, Any]:
    item = default_interaction(runtime_type)
    item.update(overrides)
    if not item.get("id"):
        item["id"] = short_id(runtime_type[:2])
    return item


def _listening_three_phase(name: str) -> dict[str, Any]:
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
                            options=["Merhaba", "Teşekkürler", "Çay"],
                            correctIndex=0,
                            audioAsset="media/listening-greetings-word.mp3",
                        )
                    ],
                },
                {
                    "id": short_id("lp"),
                    "name": "对话理解",
                    "type": "dialogue",
                    "audioAsset": "media/listening-greetings-dialogue.mp3",
                    "transcript": "Ayşe: Merhaba! Müşteri: Merhaba!",
                    "items": [
                        _item(
                            "multipleChoice",
                            prompt="这段对话在讲什么？",
                            options=["点单", "问候", "告别"],
                            correctIndex=1,
                        )
                    ],
                },
                {
                    "id": short_id("lp"),
                    "name": "摘要回顾",
                    "type": "summary",
                    "audioAsset": "media/listening-greetings-summary.mp3",
                    "transcript": "我们用 Merhaba 互相问候。",
                },
            ]
        },
    }


def _reading_three_q(name: str) -> dict[str, Any]:
    return {
        "id": short_id("l"),
        "name": name or "阅读理解",
        "description": "阅读篇章 + 选择/判断/简答三类理解题。",
        "type": "reading",
        "template": "reading",
        "prerequisiteLessonIds": [],
        "content": {
            "readingPassage": {
                "title": "咖啡馆",
                "paragraphs": ["Ayşe: Merhaba!", "Müşteri: Merhaba! Teşekkürler."],
                "difficulty": 1,
                "linkedWordIds": [],
                "linkedExpressionIds": [],
            },
            "stages": [
                {
                    "id": short_id("st"),
                    "name": "理解",
                    "items": [
                        _item(
                            "readingMcq",
                            prompt="这段对话发生在哪里？",
                            options=["家里", "咖啡馆", "学校"],
                            correctIndex=1,
                        ),
                        _item(
                            "readingTrueFalse",
                            statement="两个人互相问候。",
                            answer=True,
                        ),
                        _item(
                            "readingShortAnswer",
                            prompt="顾客怎样道谢？",
                            expectedAnswer="Teşekkürler",
                        ),
                    ],
                }
            ],
        },
    }


def _mastery_mix(name: str) -> dict[str, Any]:
    return {
        "id": short_id("l"),
        "name": name or "综合测验",
        "description": "选择 + 填空 + 翻译的综合测验。",
        "type": "challenge",
        "template": "mastery",
        "prerequisiteLessonIds": [],
        "content": {
            "stages": [
                {
                    "id": short_id("st"),
                    "name": "真实任务",
                    "items": [
                        _item(
                            "multipleChoice",
                            prompt="进店时说什么？",
                            options=["Teşekkürler", "Çay", "Merhaba"],
                            correctIndex=2,
                        ),
                        _item(
                            "fillBlank",
                            sentence="接过饮品时说：_____",
                            answer="Teşekkürler",
                            hint="表示感谢",
                        ),
                        _item(
                            "translateSentence",
                            source="你好",
                            expected="Merhaba",
                            hints=[],
                        ),
                    ],
                }
            ]
        },
    }


def _intro_three_step(name: str) -> dict[str, Any]:
    return build_intro_lesson(
        name or "认识新词",
        "展示、识别和产出交错的完整新词课。",
        [
            {"id": "w-example-merhaba", "term": "Merhaba", "translation": "你好"},
            {"id": "w-example-tesekkurler", "term": "Teşekkürler", "translation": "谢谢"},
        ],
    )


def _practice_mix(name: str) -> dict[str, Any]:
    return build_practice_lesson(
        name or "巩固练习",
        "选择、填空、翻译和拼句的混合练习。",
        [
            {"id": "w-example-merhaba", "term": "Merhaba", "translation": "你好"},
            {"id": "w-example-tesekkurler", "term": "Teşekkürler", "translation": "谢谢"},
        ],
        ("multipleChoice", "fillBlank", "translateSentence", "reorderSentence"),
    )


def _dialogue_scene(name: str) -> dict[str, Any]:
    items = [
        _item(
            "fillBlank",
            sentence="— Merhaba!\n— _____",
            answer="Merhaba",
            choices=["Merhaba", "Teşekkürler"],
        ),
        _item(
            "translateSentence",
            source="谢谢",
            expected="Teşekkürler",
            hints=[],
        ),
        _item("readAloud", targetText="Teşekkürler!", prompt="读出这句道谢"),
    ]
    return {
        "id": short_id("l"),
        "name": name or "情景对话",
        "description": "问候、回应并道谢。",
        "type": "dialogue",
        "template": "dialogue",
        "prerequisiteLessonIds": [],
        "content": {
            "dialogueScene": {
                "id": short_id("scene"),
                "title": name or "情景对话",
                "characters": [
                    {"id": "ayse", "name": "Ayşe"},
                    {"id": "learner", "name": "你"},
                ],
                "turns": [
                    {"id": short_id("turn"), "speakerId": "ayse", "text": "Merhaba!"},
                    {"id": short_id("turn"), "speakerId": "learner", "interactionId": items[0]["id"]},
                    {"id": short_id("turn"), "speakerId": "ayse", "text": "Buyurun!"},
                    {"id": short_id("turn"), "speakerId": "learner", "interactionId": items[1]["id"]},
                    {"id": short_id("turn"), "speakerId": "learner", "interactionId": items[2]["id"]},
                ],
            },
            "stages": [{"id": short_id("st"), "name": "回应", "items": items}],
        },
    }


@dataclass(frozen=True)
class LessonPreset:
    id: str
    label: str
    template: str
    description: str
    build: Callable[[str], dict[str, Any]]


FUNCTIONAL_PRESETS: list[LessonPreset] = [
    LessonPreset("listening-3phase", "听力三阶段", "listening", "听音选词、对话理解和摘要", _listening_three_phase),
    LessonPreset("reading-3q", "阅读理解·三类题", "reading", "阅读篇章、选择、判断和简答", _reading_three_q),
    LessonPreset("mastery-mix", "综合测验·混合", "mastery", "选择、填空和翻译", _mastery_mix),
    LessonPreset("intro-3step", "认识新词·混合", "intro", "12 题展示、识别与产出骨架", _intro_three_step),
    LessonPreset("practice-mix", "巩固练习·混合", "practice", "12 题混合产出骨架", _practice_mix),
    LessonPreset("dialogue-scene", "情景对话·回应", "dialogue", "角色轮次与既有题型回应", _dialogue_scene),
]

FUNCTIONAL_TEMPLATES: tuple[str, ...] = ("listening", "reading", "mastery", "dialogue")
PRESET_BY_ID: dict[str, LessonPreset] = {preset.id: preset for preset in FUNCTIONAL_PRESETS}


def presets_for_template(template: str) -> list[LessonPreset]:
    return [preset for preset in FUNCTIONAL_PRESETS if preset.template == template]


def build_preset_lesson(preset_id: str, name: str = "") -> dict[str, Any]:
    return PRESET_BY_ID[preset_id].build(name)


def apply_preset_to_lesson(lesson: dict[str, Any], preset_id: str) -> dict[str, Any]:
    preset = PRESET_BY_ID[preset_id]
    fresh = preset.build(lesson.get("name", ""))
    lesson["template"] = fresh["template"]
    lesson["type"] = fresh.get("type", lesson["type"])
    lesson["content"] = fresh["content"]
    return lesson
