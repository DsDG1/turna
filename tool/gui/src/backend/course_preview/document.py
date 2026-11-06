from __future__ import annotations

import copy
import hashlib
import json
from collections.abc import Iterator
from dataclasses import dataclass
from typing import Any


_TYPE_LABELS = {
    "showWord": "展示生词",
    "multipleChoice": "选择题",
    "multiSelect": "多选题",
    "fillBlank": "填空题",
    "translateSentence": "翻译题",
    "listenAndPick": "听音选词",
    "typeTheWord": "听写题",
    "listenOnly": "听力展示",
    "reorderSentence": "句子排序",
    "readingMcq": "阅读选择",
    "readingTrueFalse": "阅读判断",
    "readingShortAnswer": "阅读简答",
    "ankiCard": "记忆卡片",
    "ankiHtmlCard": "原卡文本",
    "readAloud": "跟读",
    "dictation": "听写",
}


def _text(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, bool):
        return "正确" if value else "错误"
    if isinstance(value, (list, tuple)):
        return " / ".join(part for part in (_text(item) for item in value) if part)
    if isinstance(value, dict):
        for key in ("text", "term", "title", "value", "content", "html"):
            if key in value:
                result = _text(value.get(key))
                if result:
                    return result
        return ""
    return str(value).strip()


def _hash(value: Any, length: int = 16) -> str:
    raw = json.dumps(value, ensure_ascii=False, sort_keys=True, default=str)
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()[:length]


def _first(item: dict[str, Any], *keys: str) -> str:
    for key in keys:
        value = _text(item.get(key))
        if value:
            return value
    return ""


def _answer(item: dict[str, Any], runtime_type: str) -> str:
    options = item.get("options") if isinstance(item.get("options"), list) else []
    if runtime_type in {"multipleChoice", "readingMcq", "listenAndPick"}:
        index = item.get("correctIndex")
        if isinstance(index, int) and not isinstance(index, bool) and 0 <= index < len(options):
            return _text(options[index])
        return "答案配置无效"
    if runtime_type == "multiSelect":
        indices = item.get("correctIndices")
        if not isinstance(indices, list) or not indices:
            return "答案配置无效"
        answers = []
        for index in indices:
            if not isinstance(index, int) or isinstance(index, bool) or not 0 <= index < len(options):
                return "答案配置无效"
            answers.append(_text(options[index]))
        return "；".join(answers)
    if runtime_type == "reorderSentence":
        return _text(item.get("correct")) or "答案配置无效"
    if runtime_type == "readingTrueFalse":
        value = item.get("answer")
        return _text(value) if isinstance(value, bool) else "答案配置无效"
    return _first(
        item,
        "expectedAnswer",
        "expected",
        "answer",
        "back",
        "backHtml",
        "targetText",
        "transcript",
        "translation",
    )


def _prompt(item: dict[str, Any], runtime_type: str, words: dict[str, dict[str, Any]]) -> str:
    if runtime_type == "showWord":
        word = words.get(_text(item.get("wordId")), {})
        term = _first(item, "term") or _text(word.get("term"))
        translation = _first(item, "translation") or _text(word.get("translation"))
        pair = " — ".join(part for part in (term, translation) if part)
        return pair or _text(item.get("wordId")) or "未提供词条"
    if runtime_type == "reorderSentence":
        return _text(item.get("prompt")) or "请将下列词块排列成正确句子。"
    if runtime_type == "readAloud":
        return _first(item, "prompt", "targetText")
    return _first(
        item,
        "prompt",
        "sentence",
        "source",
        "statement",
        "targetText",
        "text",
        "front",
        "frontHtml",
        "transcript",
        "term",
    ) or "未提供题干"


def _options(item: dict[str, Any], runtime_type: str) -> tuple[str, ...]:
    if runtime_type == "reorderSentence":
        values = item.get("scrambled")
    else:
        values = item.get("options")
    if not isinstance(values, list):
        return ()
    return tuple(_text(value) for value in values)


def _notes(item: dict[str, Any], runtime_type: str) -> tuple[str, ...]:
    notes = []
    for key, label in (
        ("audioAsset", "音频"),
        ("audioAssets", "音频"),
        ("imageAsset", "图片"),
        ("imageAssets", "图片"),
        ("mediaBasePath", "媒体目录"),
    ):
        value = _text(item.get(key))
        if value:
            notes.append(f"{label}占位：{value}（网页版不加载本地资源）")
    if runtime_type == "ankiHtmlCard":
        notes.append("原卡 HTML/CSS/JS 不在粗预览中执行，仅显示转义文本。")
    return tuple(notes)


def _context(item: dict[str, Any]) -> tuple[str, ...]:
    values = []
    for key in ("context", "example", "hint", "transcript"):
        value = _text(item.get(key))
        if value and value != _first(item, "prompt", "sentence", "source", "statement"):
            values.append(value)
    return tuple(values)


def _containers(content: dict[str, Any]) -> Iterator[tuple[str, dict[str, Any], list[Any]]]:
    questions = content.get("questions")
    if isinstance(questions, list) and not isinstance(content.get("stages"), list):
        yield "questions", {"id": "questions", "name": "题目"}, questions
    stages = content.get("stages")
    if isinstance(stages, list):
        for stage in stages:
            if isinstance(stage, dict) and isinstance(stage.get("items"), list):
                yield "stages", stage, stage["items"]
    sub_lessons = content.get("subLessons")
    if isinstance(sub_lessons, list):
        for sub in sub_lessons:
            if not isinstance(sub, dict):
                continue
            for stage in sub.get("stages") or []:
                if isinstance(stage, dict) and isinstance(stage.get("items"), list):
                    yield "subLessons", {**stage, "subLessonId": sub.get("id"), "subLessonName": sub.get("name")}, stage["items"]
    phases = content.get("listeningPhases")
    if isinstance(phases, list):
        for phase in phases:
            if isinstance(phase, dict) and isinstance(phase.get("items"), list):
                yield "listeningPhases", phase, phase["items"]


def _reading_context(content: dict[str, Any]) -> tuple[str, ...]:
    passage = content.get("readingPassage")
    if not isinstance(passage, dict):
        return ()
    result = []
    title = _text(passage.get("title"))
    if title:
        result.append(title)
    for key in ("text", "paragraphs", "passage", "content"):
        value = passage.get(key)
        if isinstance(value, list):
            result.extend(part for part in (_text(item) for item in value) if part)
        else:
            text = _text(value)
            if text:
                result.append(text)
    return tuple(result)


def _dialogue_context(content: dict[str, Any]) -> tuple[str, ...]:
    scene = content.get("dialogueScene")
    if not isinstance(scene, dict):
        return ()
    speakers = {
        _text(character.get("id")): _text(character.get("name"))
        for character in scene.get("characters") or []
        if isinstance(character, dict)
    }
    result = [_text(scene.get("title"))]
    for turn in scene.get("turns") or []:
        if not isinstance(turn, dict):
            continue
        speaker = speakers.get(_text(turn.get("speakerId")), _text(turn.get("speakerId")))
        text = _text(turn.get("text")) or "（学习者回应）"
        result.append(f"{speaker}：{text}")
    return tuple(part for part in result if part)


@dataclass(frozen=True)
class PreviewItem:
    key: str
    location: str
    runtime_type: str
    type_label: str
    prompt: str
    options: tuple[str, ...]
    answer: str
    context: tuple[str, ...]
    notes: tuple[str, ...]
    raw: dict[str, Any]

    @property
    def anchor(self) -> str:
        return f"q-{_hash(self.key, 12)}"

    def snapshot(self) -> dict[str, Any]:
        return {
            "key": self.key,
            "location": self.location,
            "runtimeType": self.runtime_type,
            "prompt": self.prompt,
            "options": list(self.options),
            "answer": self.answer,
            "context": list(self.context),
            "raw": copy.deepcopy(self.raw),
        }


@dataclass(frozen=True)
class PreviewLesson:
    ref: str
    unit_id: str
    lesson_id: str
    name: str
    template: str
    context: tuple[str, ...]
    items: tuple[PreviewItem, ...]


@dataclass(frozen=True)
class PreviewUnit:
    unit_id: str
    name: str
    lessons: tuple[PreviewLesson, ...]


@dataclass(frozen=True)
class PreviewDocument:
    section_id: str
    name: str
    description: str
    units: tuple[PreviewUnit, ...]
    warnings: tuple[str, ...]

    @property
    def lessons(self) -> tuple[PreviewLesson, ...]:
        return tuple(lesson for unit in self.units for lesson in unit.lessons)

    @property
    def item_count(self) -> int:
        return sum(len(lesson.items) for lesson in self.lessons)

    def lesson(self, ref: str) -> PreviewLesson | None:
        return next((lesson for lesson in self.lessons if lesson.ref == ref), None)

    def item(self, key: str) -> PreviewItem | None:
        for lesson in self.lessons:
            for item in lesson.items:
                if item.key == key:
                    return item
        return None


def build_document(section: dict[str, Any]) -> PreviewDocument:
    if not isinstance(section, dict):
        raise ValueError("课程草稿顶层必须是 JSON 对象。")
    raw_units = section.get("units")
    if not isinstance(raw_units, list):
        raise ValueError("课程草稿必须包含 units 数组。")
    section_id = _text(section.get("id")) or "section"
    words = {
        _text(word.get("id")): word
        for word in section.get("words") or []
        if isinstance(word, dict) and _text(word.get("id"))
    }
    warnings: list[str] = []
    units: list[PreviewUnit] = []
    used_refs: set[str] = set()
    used_item_keys: set[str] = set()
    for unit_index, raw_unit in enumerate(raw_units):
        if not isinstance(raw_unit, dict):
            warnings.append(f"第 {unit_index + 1} 个单元不是对象，已跳过。")
            continue
        unit_id = _text(raw_unit.get("id")) or f"unit-{unit_index + 1}"
        unit_name = _text(raw_unit.get("name")) or unit_id
        raw_lessons = raw_unit.get("lessons")
        if not isinstance(raw_lessons, list):
            warnings.append(f"单元 {unit_name} 缺少 lessons 数组，已跳过。")
            continue
        lessons: list[PreviewLesson] = []
        for lesson_index, raw_lesson in enumerate(raw_lessons):
            if not isinstance(raw_lesson, dict):
                warnings.append(f"{unit_name} 的第 {lesson_index + 1} 课不是对象，已跳过。")
                continue
            lesson_id = _text(raw_lesson.get("id")) or f"lesson-{lesson_index + 1}"
            lesson_name = _text(raw_lesson.get("name")) or lesson_id
            content = raw_lesson.get("content")
            if not isinstance(content, dict):
                warnings.append(f"课时 {lesson_name} 缺少 content 对象，已跳过。")
                continue
            items: list[PreviewItem] = []
            for container_kind, container, raw_items in _containers(content):
                container_id = _text(container.get("id")) or f"{container_kind}-{_hash({k: v for k, v in container.items() if k != 'items'}, 10)}"
                container_name = _text(container.get("name") or container.get("subLessonName"))
                for item_index, raw_item in enumerate(raw_items):
                    if not isinstance(raw_item, dict):
                        warnings.append(f"{lesson_name} 的第 {item_index + 1} 个题项不是对象，已跳过。")
                        continue
                    runtime_type = _text(raw_item.get("runtimeType")) or "unknown"
                    item_token = _text(raw_item.get("id")) or f"hash-{_hash(raw_item)}"
                    base_key = f"section:{section_id}/unit:{unit_id}/lesson:{lesson_id}/{container_kind}:{container_id}/item:{item_token}"
                    key = base_key
                    duplicate = 2
                    while key in used_item_keys:
                        key = f"{base_key}~{duplicate}"
                        duplicate += 1
                    used_item_keys.add(key)
                    location = " › ".join(
                        part
                        for part in (unit_name, lesson_name, container_name, f"第 {item_index + 1} 项")
                        if part
                    )
                    items.append(
                        PreviewItem(
                            key=key,
                            location=location,
                            runtime_type=runtime_type,
                            type_label=_TYPE_LABELS.get(runtime_type, f"未知题型（{runtime_type}）"),
                            prompt=_prompt(raw_item, runtime_type, words),
                            options=_options(raw_item, runtime_type),
                            answer=_answer(raw_item, runtime_type),
                            context=_context(raw_item),
                            notes=_notes(raw_item, runtime_type),
                            raw=copy.deepcopy(raw_item),
                        )
                    )
            ref_base = _hash(f"{unit_id}\0{lesson_id}", 24)
            ref = ref_base
            duplicate = 2
            while ref in used_refs:
                ref = f"{ref_base}-{duplicate}"
                duplicate += 1
            used_refs.add(ref)
            lessons.append(
                PreviewLesson(
                    ref=ref,
                    unit_id=unit_id,
                    lesson_id=lesson_id,
                    name=lesson_name,
                    template=_text(raw_lesson.get("template") or raw_lesson.get("type")),
                    context=(*_reading_context(content), *_dialogue_context(content)),
                    items=tuple(items),
                )
            )
        units.append(PreviewUnit(unit_id=unit_id, name=unit_name, lessons=tuple(lessons)))
    if not any(unit.lessons for unit in units):
        raise ValueError("课程草稿里没有可预览的课时。")
    return PreviewDocument(
        section_id=section_id,
        name=_text(section.get("name")) or section_id,
        description=_text(section.get("description")),
        units=tuple(units),
        warnings=tuple(warnings),
    )
