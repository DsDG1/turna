from __future__ import annotations

import hashlib
from dataclasses import dataclass
from typing import Any

MIN_SUB_LESSON_ITEMS = 12
MAX_SUB_LESSON_ITEMS = 15
MIN_NEW_WORD_DISTANCE = 3
REVIEW_POOL_SIZE = 18
REVIEW_MIN_ITEMS = 15
REVIEW_MAX_ITEMS = 16

LEVEL_RULES = {
    "A1": {"new_words": (4, 8), "sentence_words": 8},
    "A2": {"new_words": (6, 12), "sentence_words": 12},
    "B1": {"new_words": (8, 15), "sentence_words": 18},
    "B2": {"new_words": (10, 18), "sentence_words": 24},
    "C1": {"new_words": (10, 20), "sentence_words": 30},
    "C2": {"new_words": (10, 24), "sentence_words": 40},
}

PRODUCTION_TYPES = {
    "fillBlank",
    "translateSentence",
    "reorderSentence",
    "readAloud",
}
CHOICE_TYPES = {"multipleChoice", "listenAndPick", "readingMcq"}


@dataclass(frozen=True)
class PedagogyFinding:
    code: str
    message: str
    severity: str = "warning"


def lesson_sub_lessons(lesson: dict[str, Any]) -> list[dict[str, Any]]:
    content = lesson.get("content") or {}
    return [entry for entry in content.get("subLessons") or [] if isinstance(entry, dict)]


def sub_lesson_items(sub_lesson: dict[str, Any]) -> list[dict[str, Any]]:
    return [
        item
        for stage in sub_lesson.get("stages") or []
        if isinstance(stage, dict)
        for item in stage.get("items") or []
        if isinstance(item, dict)
    ]


def lesson_items(lesson: dict[str, Any]) -> list[dict[str, Any]]:
    content = lesson.get("content") or {}
    items = [
        item
        for sub_lesson in lesson_sub_lessons(lesson)
        for item in sub_lesson_items(sub_lesson)
    ]
    items.extend(
        item
        for stage in content.get("stages") or []
        if isinstance(stage, dict)
        for item in stage.get("items") or []
        if isinstance(item, dict)
    )
    items.extend(
        item
        for phase in content.get("listeningPhases") or []
        if isinstance(phase, dict)
        for item in phase.get("items") or []
        if isinstance(item, dict)
    )
    return items


def evaluate_lesson_pedagogy(
    lesson: dict[str, Any], *, level: str = "A1"
) -> list[PedagogyFinding]:
    findings: list[PedagogyFinding] = []
    lesson_id = str(lesson.get("id") or "<unknown>")
    template = lesson.get("template")
    if template in {"intro", "practice"}:
        for sub_lesson in lesson_sub_lessons(lesson):
            sub_id = str(sub_lesson.get("id") or "<unknown>")
            items = sub_lesson_items(sub_lesson)
            if not MIN_SUB_LESSON_ITEMS <= len(items) <= MAX_SUB_LESSON_ITEMS:
                findings.append(
                    PedagogyFinding(
                        "sublesson_length",
                        f"SubLesson {sub_id} in lesson {lesson_id} has {len(items)} items; "
                        f"target is {MIN_SUB_LESSON_ITEMS}–{MAX_SUB_LESSON_ITEMS}",
                    )
                )
            introduced: dict[str, int] = {}
            for index, item in enumerate(items):
                if item.get("runtimeType") != "showWord":
                    continue
                word_id = str(item.get("wordId") or "")
                if not word_id or word_id in introduced:
                    continue
                if introduced and index - max(introduced.values()) < MIN_NEW_WORD_DISTANCE:
                    findings.append(
                        PedagogyFinding(
                            "new_word_spacing",
                            f"SubLesson {sub_id} introduces {word_id} fewer than "
                            f"{MIN_NEW_WORD_DISTANCE - 1} items after the previous new word",
                        )
                    )
                introduced[word_id] = index
            if items and not any(item.get("runtimeType") in PRODUCTION_TYPES for item in items):
                findings.append(
                    PedagogyFinding(
                        "production_missing",
                        f"SubLesson {sub_id} has no direct production item",
                    )
                )

    items = lesson_items(lesson)
    positions = [
        item.get("correctIndex")
        for item in items
        if item.get("runtimeType") in CHOICE_TYPES and type(item.get("correctIndex")) is int
    ]
    if len(positions) >= 3 and len(set(positions)) == 1:
        findings.append(
            PedagogyFinding(
                "answer_position",
                f"Lesson {lesson_id} puts every choice answer at index {positions[0]}",
            )
        )

    rules = LEVEL_RULES.get(str(level).upper(), LEVEL_RULES["A1"])
    introduced_ids = {
        str(item.get("wordId"))
        for item in items
        if item.get("runtimeType") == "showWord" and item.get("wordId")
    }
    maximum_new_words = rules["new_words"][1]
    if template == "intro" and len(introduced_ids) > maximum_new_words:
        findings.append(
            PedagogyFinding(
                "level_word_budget",
                f"Lesson {lesson_id} introduces {len(introduced_ids)} words; "
                f"{level} target maximum is {maximum_new_words}",
            )
        )
    sentence_cap = rules["sentence_words"]
    for item in items:
        if item.get("runtimeType") != "translateSentence":
            continue
        expected = str(item.get("expected") or "")
        if len(expected.split()) > sentence_cap:
            findings.append(
                PedagogyFinding(
                    "level_sentence_length",
                    f"Translation {item.get('id') or '<unknown>'} exceeds the "
                    f"{level} sentence guide of {sentence_cap} words",
                )
            )
    return findings


def arrange_choice(
    options: list[str],
    correct_index: int,
    *,
    seed: str,
    preferred_index: int,
) -> tuple[list[str], int]:
    if not options or not 0 <= correct_index < len(options):
        raise ValueError("options and correctIndex must describe one correct option")
    target = preferred_index % len(options)
    correct = options[correct_index]
    distractors = [option for index, option in enumerate(options) if index != correct_index]
    if distractors:
        digest = hashlib.sha256(seed.encode("utf-8")).digest()
        shift = digest[0] % len(distractors)
        distractors = distractors[shift:] + distractors[:shift]
    arranged = list(distractors)
    arranged.insert(target, correct)
    return arranged, target


def phase_two_prompt_block() -> str:
    return (
        "Phase Two 教学配方（硬约束）：\n"
        f"1. 每个独立子课 {MIN_SUB_LESSON_ITEMS}–{MAX_SUB_LESSON_ITEMS} 个 items；"
        "不要把一个词拆成一个三题子课。\n"
        "2. 以真实句子的直接运用为主，展示、识别和产出交错；"
        "每个子课至少包含 fillBlank / translateSentence / reorderSentence 之一。\n"
        f"3. 两个首次新词之间至少隔 {MIN_NEW_WORD_DISTANCE - 1} 个 items，禁止连续甩词卡。\n"
        "4. 单选与多选的正确选项位置要分散，并同步重算 correctIndex/correctIndices。\n"
        "5. 教学说明使用中文；复习只使用前置课已经学过的词和结构。\n"
        f"6. 随机复习使用平铺 stages + reviewPolicy，题池约 {REVIEW_POOL_SIZE} 题，"
        f"每次抽 {REVIEW_MIN_ITEMS}–{REVIEW_MAX_ITEMS} 题，不与 subLessons 混用。"
    )
