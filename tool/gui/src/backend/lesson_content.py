"""Pure-Python lesson content operations (no PySide6 dependency).

Defines the 12 Interaction runtimeType schemas, the template->content shape
rules (guiplan §6.2), id generation, and new/delete helpers. This module is
the single source of truth for content-shape rules used by the widgets.
"""
from __future__ import annotations

import re
import uuid
from dataclasses import dataclass
from typing import Any

CONTENT_BY_TEMPLATE: dict[str, set[str]] = {
    "intro": {"subLessons"},
    "practice": {"subLessons"},
    "review": {"subLessons", "stages"},
    "listening": {"listeningPhases"},
    "reading": {"readingPassage", "stages"},
    "mastery": {"stages"},
    "legacy": {"stages", "subLessons", "listeningPhases"},
}

PRIMARY_CONTENT_KEY: dict[str, str] = {
    "intro": "subLessons",
    "practice": "subLessons",
    "review": "subLessons",
    "listening": "listeningPhases",
    "reading": "readingPassage",
    "mastery": "stages",
    "legacy": "stages",
}

LISTENING_PHASE_TYPES = ("wordPairing", "dialogue", "summary")

ALLOWED_RUNTIME_TYPES = (
    "showWord",
    "multipleChoice",
    "multiSelect",
    "fillBlank",
    "translateSentence",
    "listenAndPick",
    "typeTheWord",
    "listenOnly",
    "reorderSentence",
    "readingMcq",
    "readingTrueFalse",
    "readingShortAnswer",
)

INTERACTION_LABELS: dict[str, str] = {
    "showWord": "展示生词",
    "multipleChoice": "选择题",
    "multiSelect": "多选题",
    "fillBlank": "填空题",
    "translateSentence": "翻译题",
    "listenAndPick": "听音选词",
    "typeTheWord": "听写题",
    "listenOnly": "只听不答",
    "reorderSentence": "排序句子",
    "readingMcq": "阅读选择",
    "readingTrueFalse": "阅读判断",
    "readingShortAnswer": "阅读简答",
}

TEMPLATE_LABELS: dict[str, str] = {
    "intro": "认识新词",
    "practice": "巩固练习",
    "review": "复习",
    "listening": "听力训练",
    "reading": "阅读理解",
    "mastery": "综合测验",
    "legacy": "基础题",
}


@dataclass(frozen=True)
class FieldSpec:
    name: str
    required: bool
    kind: str  # 'string' | 'int' | 'bool' | 'string_list' | 'int_list' | 'ref_word' | 'ref_expression' | 'ref_grammar'
    default: Any = None


INTERACTION_SCHEMA: dict[str, list[FieldSpec]] = {
    "showWord": [
        FieldSpec("id", False, "string", ""),
        FieldSpec("wordId", True, "ref_word"),
        FieldSpec("context", False, "string", ""),
        FieldSpec("grammarPointId", False, "ref_grammar", ""),
        FieldSpec("expressionId", False, "ref_expression", ""),
    ],
    "multipleChoice": [
        FieldSpec("id", False, "string", ""),
        FieldSpec("prompt", True, "string", ""),
        FieldSpec("options", True, "string_list", []),
        FieldSpec("correctIndex", True, "int", 0),
        FieldSpec("imageAsset", False, "string", ""),
        FieldSpec("grammarPointId", False, "ref_grammar", ""),
    ],
    "multiSelect": [
        FieldSpec("id", False, "string", ""),
        FieldSpec("prompt", True, "string", ""),
        FieldSpec("options", True, "string_list", []),
        FieldSpec("correctIndices", True, "int_list", []),
        FieldSpec("minSelections", False, "int", 1),
        FieldSpec("maxSelections", False, "int", 2147483647),
        FieldSpec("imageAsset", False, "string", ""),
        FieldSpec("grammarPointId", False, "ref_grammar", ""),
    ],
    "fillBlank": [
        FieldSpec("id", False, "string", ""),
        FieldSpec("sentence", True, "string", ""),
        FieldSpec("answer", True, "string", ""),
        FieldSpec("hint", False, "string", ""),
        FieldSpec("grammarPointId", False, "ref_grammar", ""),
    ],
    "translateSentence": [
        FieldSpec("id", False, "string", ""),
        FieldSpec("source", True, "string", ""),
        FieldSpec("expected", True, "string", ""),
        FieldSpec("hints", False, "string_list", []),
        FieldSpec("grammarPointId", False, "ref_grammar", ""),
    ],
    "listenAndPick": [
        FieldSpec("id", False, "string", ""),
        FieldSpec("audioAsset", True, "string", ""),
        FieldSpec("prompt", True, "string", ""),
        FieldSpec("options", True, "string_list", []),
        FieldSpec("correctIndex", True, "int", 0),
        FieldSpec("grammarPointId", False, "ref_grammar", ""),
    ],
    "typeTheWord": [
        FieldSpec("id", False, "string", ""),
        FieldSpec("audioAsset", True, "string", ""),
        FieldSpec("prompt", True, "string", ""),
        FieldSpec("expected", True, "string", ""),
        FieldSpec("grammarPointId", False, "ref_grammar", ""),
    ],
    "listenOnly": [
        FieldSpec("id", False, "string", ""),
        FieldSpec("audioAsset", False, "string", ""),
        FieldSpec("transcript", False, "string", ""),
        FieldSpec("prompt", False, "string", "Listen to the summary"),
        FieldSpec("grammarPointId", False, "ref_grammar", ""),
    ],
    "reorderSentence": [
        FieldSpec("id", False, "string", ""),
        FieldSpec("scrambled", True, "string_list", []),
        FieldSpec("correct", True, "string_list", []),
        FieldSpec("grammarPointId", False, "ref_grammar", ""),
    ],
    "readingMcq": [
        FieldSpec("id", False, "string", ""),
        FieldSpec("prompt", True, "string", ""),
        FieldSpec("options", True, "string_list", []),
        FieldSpec("correctIndex", True, "int", 0),
        FieldSpec("grammarPointId", False, "ref_grammar", ""),
    ],
    "readingTrueFalse": [
        FieldSpec("id", False, "string", ""),
        FieldSpec("statement", True, "string", ""),
        FieldSpec("answer", True, "bool", False),
        FieldSpec("grammarPointId", False, "ref_grammar", ""),
    ],
    "readingShortAnswer": [
        FieldSpec("id", False, "string", ""),
        FieldSpec("prompt", True, "string", ""),
        FieldSpec("expectedAnswer", True, "string", ""),
        FieldSpec("grammarPointId", False, "ref_grammar", ""),
    ],
}


def default_interaction(runtime_type: str) -> dict[str, Any]:
    """Return a minimal valid item dict for the given runtimeType."""
    item: dict[str, Any] = {"runtimeType": runtime_type}
    for spec in INTERACTION_SCHEMA[runtime_type]:
        item[spec.name] = spec.default
    return item


def normalize_item(item: dict[str, Any]) -> dict[str, Any]:
    """Ensure item has every schema field (fill defaults for missing)."""
    rt = item.get("runtimeType")
    if rt not in INTERACTION_SCHEMA:
        raise ValueError(f"unknown runtimeType: {rt}")
    out = {"runtimeType": rt}
    for spec in INTERACTION_SCHEMA[rt]:
        if spec.name in item:
            out[spec.name] = item[spec.name]
        else:
            out[spec.name] = spec.default
    return out


def allowed_content_keys(template: str) -> set[str]:
    return CONTENT_BY_TEMPLATE.get(template, {"stages"})


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
    primary = PRIMARY_CONTENT_KEY.get(new_template, "stages")
    if primary == "readingPassage":
        if "readingPassage" not in content:
            content["readingPassage"] = _empty_reading_passage()
    elif primary and primary not in content:
        content[primary] = []


def _empty_reading_passage() -> dict[str, Any]:
    return {
        "title": "",
        "paragraphs": [],
        "difficulty": 1,
        "linkedWordIds": [],
        "linkedExpressionIds": [],
    }


def _mcq_options(term: str, pool: list[str]) -> list[str]:
    """Return [term, distractor1, distractor2] using other terms from pool."""
    others = [t for t in pool if t != term]
    distractors = (others + [f"{term}-alt1", f"{term}-alt2"])[:2]
    return [term, *distractors]


def build_intro_lesson(
    name: str,
    description: str,
    words: list[dict[str, Any]],
) -> dict[str, Any]:
    """Generate an intro lesson from selected vocab words.

    Each word becomes one sub-lesson with three stages:
    1. showWord - present the new word
    2. translateSentence - translate the word's meaning
    3. fillBlank - reinforce with a fill-in-the-blank
    """
    sub_lessons: list[dict[str, Any]] = []
    for w in words:
        wid = w["id"]
        term = w.get("term", wid)
        translation = w.get("translation", "")
        sub_lessons.append(
            {
                "id": short_id("sl"),
                "name": f"认识 {term}",
                "stages": [
                    {
                        "id": short_id("st"),
                        "name": "展示",
                        "items": [
                            {
                                "runtimeType": "showWord",
                                "id": short_id("sw"),
                                "wordId": wid,
                                "context": "",
                                "grammarPointId": "",
                                "expressionId": "",
                            }
                        ],
                    },
                    {
                        "id": short_id("st"),
                        "name": "翻译",
                        "items": [
                            {
                                "runtimeType": "translateSentence",
                                "id": short_id("ts"),
                                "source": translation,
                                "expected": term,
                                "hints": [],
                                "grammarPointId": "",
                            }
                        ],
                    },
                    {
                        "id": short_id("st"),
                        "name": "填空",
                        "items": [
                            {
                                "runtimeType": "fillBlank",
                                "id": short_id("fb"),
                                "sentence": f"___ -> {translation}",
                                "answer": term,
                                "hint": "",
                                "grammarPointId": "",
                            }
                        ],
                    },
                ],
            }
        )
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
    """Generate a practice lesson from selected words.

    Each word becomes one sub-lesson. Stages are created for each selected
    ``mix_types`` in order. Supported types: multipleChoice, fillBlank,
    translateSentence, typeTheWord.
    """
    allowed = {"multipleChoice", "fillBlank", "translateSentence", "typeTheWord"}
    types = [t for t in mix_types if t in allowed]
    if not types:
        types = ["fillBlank"]

    terms = [w.get("term", w["id"]) for w in words]
    sub_lessons: list[dict[str, Any]] = []
    for w in words:
        wid = w["id"]
        term = w.get("term", wid)
        translation = w.get("translation", "")
        stages: list[dict[str, Any]] = []
        for rt in types:
            item: dict[str, Any] = {"runtimeType": rt, "id": short_id(rt[:2])}
            if rt == "multipleChoice":
                item.update(
                    {
                        "prompt": f"{translation} 是什么意思？",
                        "options": _mcq_options(term, terms),
                        "correctIndex": 0,
                        "imageAsset": "",
                        "grammarPointId": "",
                    }
                )
            elif rt == "fillBlank":
                item.update(
                    {
                        "sentence": f"___ -> {translation}",
                        "answer": term,
                        "hint": "",
                        "grammarPointId": "",
                    }
                )
            elif rt == "translateSentence":
                item.update(
                    {
                        "source": translation,
                        "expected": term,
                        "hints": [],
                        "grammarPointId": "",
                    }
                )
            elif rt == "typeTheWord":
                item.update(
                    {
                        "audioAsset": "",
                        "prompt": translation,
                        "expected": term,
                        "grammarPointId": "",
                    }
                )
            stages.append(
                {
                    "id": short_id("st"),
                    "name": INTERACTION_LABELS.get(rt, rt),
                    "items": [item],
                }
            )
        sub_lessons.append(
            {
                "id": short_id("sl"),
                "name": f"练习 {term}",
                "stages": stages,
            }
        )
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
    """Generate a review lesson from previously seen words/expressions.

    Creates one sub-lesson per word with a mixed set of recognition and recall
    stages, plus one sub-lesson per expression for translation practice.
    """
    expressions = source_expressions or []
    terms = [w.get("term", w["id"]) for w in source_words]
    sub_lessons: list[dict[str, Any]] = []

    for w in source_words:
        wid = w["id"]
        term = w.get("term", wid)
        translation = w.get("translation", "")
        sub_lessons.append(
            {
                "id": short_id("sl"),
                "name": f"复习 {term}",
                "stages": [
                    {
                        "id": short_id("st"),
                        "name": "再看一眼",
                        "items": [
                            {
                                "runtimeType": "showWord",
                                "id": short_id("sw"),
                                "wordId": wid,
                                "context": "",
                                "grammarPointId": "",
                                "expressionId": "",
                            }
                        ],
                    },
                    {
                        "id": short_id("st"),
                        "name": "选择",
                        "items": [
                            {
                                "runtimeType": "multipleChoice",
                                "id": short_id("mc"),
                                "prompt": f"{translation} 是什么意思？",
                                "options": _mcq_options(term, terms),
                                "correctIndex": 0,
                                "imageAsset": "",
                                "grammarPointId": "",
                            }
                        ],
                    },
                    {
                        "id": short_id("st"),
                        "name": "填空",
                        "items": [
                            {
                                "runtimeType": "fillBlank",
                                "id": short_id("fb"),
                                "sentence": f"___ -> {translation}",
                                "answer": term,
                                "hint": "",
                                "grammarPointId": "",
                            }
                        ],
                    },
                ],
            }
        )

    for e in expressions:
        eid = e["id"]
        term = e.get("term", eid)
        translation = e.get("translation", "")
        sub_lessons.append(
            {
                "id": short_id("sl"),
                "name": f"复习表达 {term}",
                "stages": [
                    {
                        "id": short_id("st"),
                        "name": "翻译",
                        "items": [
                            {
                                "runtimeType": "translateSentence",
                                "id": short_id("ts"),
                                "source": translation,
                                "expected": term,
                                "hints": [],
                                "grammarPointId": "",
                            }
                        ],
                    }
                ],
            }
        )

    return {
        "id": short_id("l"),
        "name": name or "新复习课",
        "description": description,
        "type": "normal",
        "template": "review",
        "prerequisiteLessonIds": [],
        "content": {"subLessons": sub_lessons},
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


def all_lesson_ids(sections: list[dict[str, Any]]) -> set[str]:
    ids: set[str] = set()
    for section in sections:
        for unit in section.get("units", []):
            for lesson in unit.get("lessons", []):
                if lesson.get("id"):
                    ids.add(lesson["id"])
    return ids


def all_unit_ids(sections: list[dict[str, Any]]) -> set[str]:
    ids: set[str] = set()
    for section in sections:
        for unit in section.get("units", []):
            if unit.get("id"):
                ids.add(unit["id"])
    return ids


def add_sub_lesson(stage_container: dict[str, Any], name: str = "New sub-lesson") -> dict[str, Any]:
    sub = {
        "id": short_id("sl"),
        "name": name,
        "stages": [
            {"id": short_id("st"), "name": "Stage 1", "items": []},
        ],
    }
    stage_container.setdefault("subLessons", []).append(sub)
    return sub


def add_stage(stage_container: dict[str, Any], name: str = "New stage") -> dict[str, Any]:
    stage = {"id": short_id("st"), "name": name, "items": []}
    stage_container.setdefault("stages", []).append(stage)
    return stage


def add_item(stage: dict[str, Any], runtime_type: str) -> dict[str, Any]:
    item = default_interaction(runtime_type)
    item["id"] = short_id(runtime_type[:2])
    stage.setdefault("items", []).append(item)
    return item


def delete_item(stage: dict[str, Any], item_id: str) -> bool:
    """Remove the item with the given id from the stage. Returns True if found."""
    items = stage.get("items", [])
    for i, item in enumerate(items):
        if item.get("id") == item_id:
            del items[i]
            return True
    return False


def move_item(stage: dict[str, Any], from_idx: int, to_idx: int) -> None:
    """Move an item within its stage by index."""
    items = stage.get("items", [])
    if not (0 <= from_idx < len(items) and 0 <= to_idx < len(items)):
        return
    item = items.pop(from_idx)
    items.insert(to_idx, item)


def move_stage(sub_lesson: dict[str, Any], from_idx: int, to_idx: int) -> None:
    """Move a stage within a sub-lesson by index."""
    stages = sub_lesson.get("stages", [])
    if not (0 <= from_idx < len(stages) and 0 <= to_idx < len(stages)):
        return
    stage = stages.pop(from_idx)
    stages.insert(to_idx, stage)


def move_sub_lesson(content: dict[str, Any], from_idx: int, to_idx: int) -> None:
    """Move a sub-lesson within the lesson content by index."""
    subs = content.get("subLessons", [])
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
    stages = sub_lesson.get("stages", [])
    for i, stage in enumerate(stages):
        if stage.get("id") == stage_id:
            del stages[i]
            return True
    return False


def delete_sub_lesson(content: dict[str, Any], sub_lesson_id: str) -> bool:
    """Remove the sub-lesson with the given id from the lesson content. Returns True if found."""
    subs = content.get("subLessons", [])
    for i, sub in enumerate(subs):
        if sub.get("id") == sub_lesson_id:
            del subs[i]
            return True
    return False


# Mapping of semantically equivalent fields when switching runtimeType.
# Each tuple lists fields that represent the same concept across different types.
_SEMANTIC_FIELD_GROUPS: tuple[tuple[str, ...], ...] = (
    ("prompt", "sentence", "source", "statement"),
    ("expected", "answer", "expectedAnswer"),
    ("correctIndex", "correctIndices"),
    ("options",),
    ("wordId",),
    ("audioAsset",),
    ("context",),
    ("transcript",),
    ("hints",),
    ("imageAsset",),
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
    old_rt = item.get("runtimeType", "")
    old_schema = INTERACTION_SCHEMA.get(old_rt, [])
    new_schema = INTERACTION_SCHEMA[new_runtime_type]
    new_field_names = {spec.name for spec in new_schema}
    old_field_names = {spec.name for spec in old_schema}

    # Build a mapping from the new item's canonical field name to the best old value.
    semantic_values: dict[str, Any] = {}
    for old_field, old_value in item.items():
        if old_field == "runtimeType":
            continue
        if old_field in new_field_names:
            semantic_values[old_field] = old_value
            continue
        group = _field_to_group(old_field)
        if group is None:
            continue
        # Prefer same-named field, otherwise take the first field in the group.
        if group in new_field_names and group not in semantic_values:
            semantic_values[group] = old_value

    # Apply preserved values, but only if the type is compatible.
    for spec in new_schema:
        name = spec.name
        if name == "runtimeType":
            continue
        if name == "id":
            new_item[name] = item.get("id") or new_item[name]
            continue
        if name not in semantic_values:
            continue
        value = semantic_values[name]
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
    phase_type: str = "wordPairing",
    name: str = "New phase",
) -> dict[str, Any]:
    phase: dict[str, Any] = {
        "id": short_id("lp"),
        "name": name,
        "type": phase_type,
    }
    if phase_type in ("wordPairing", "dialogue"):
        phase["items"] = []
    if phase_type in ("dialogue", "summary"):
        phase["audioAsset"] = ""
        phase["transcript"] = ""
    lesson.setdefault("content", {}).setdefault("listeningPhases", []).append(phase)
    return phase


def delete_listening_phase(lesson: dict[str, Any], phase_id: str) -> bool:
    """Remove the listening phase with the given id. Returns True if found."""
    phases = lesson.get("content", {}).get("listeningPhases", [])
    for i, phase in enumerate(phases):
        if phase.get("id") == phase_id:
            del phases[i]
            return True
    return False


def move_listening_phase(lesson: dict[str, Any], from_idx: int, to_idx: int) -> None:
    """Move a listening phase by index."""
    phases = lesson.get("content", {}).get("listeningPhases", [])
    if not (0 <= from_idx < len(phases) and 0 <= to_idx < len(phases)):
        return
    phase = phases.pop(from_idx)
    phases.insert(to_idx, phase)


def rename_listening_phase(phase: dict[str, Any], name: str) -> None:
    """Update the display name of a listening phase."""
    phase["name"] = name


def listening_phase_has_items(phase_type: str) -> bool:
    """Return True if the listening phase type supports items."""
    return phase_type in ("wordPairing", "dialogue")


SLUG_RE = re.compile(r"[^a-z0-9]+")


def slugify(text: str) -> str:
    return SLUG_RE.sub("-", text.lower()).strip("-")