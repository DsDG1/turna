"""Adapter bridging the GUI to the stable backend API.

The GUI no longer imports ``course_cli`` directly; all loading, saving,
validating and linting goes through ``src.backend.api``. JSON remains the
single source of truth; this adapter only holds an in-memory working copy.
"""
from __future__ import annotations

import json
import logging
import os
import shutil
import tempfile
import time
import hashlib
from copy import deepcopy
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Any

logger = logging.getLogger(__name__)

from src.backend import api
from src.infrastructure.telemetry import telemetry
from src.backend.lesson_content import (  # noqa: E402
    all_lesson_ids,
    all_unit_ids,
    slugify,
)

# Kept for backwards compatibility with git_library.py.
_REPO_ROOT = Path(__file__).resolve().parents[4]


@dataclass
class SaveResult:
    ok: bool
    errors: list[dict[str, str]] = field(default_factory=list)
    warnings: list[dict[str, str]] = field(default_factory=list)
    message: str = ""


@dataclass
class MergeAction:
    """A single unit/lesson merge decision.

    ``action`` is one of "add", "replace" or "skip".
    ``target_index`` is the position of the existing unit/lesson in the target
    section/unit; it is ``None`` for additions.
    """

    kind: str
    action: str
    incoming: dict[str, Any]
    target_index: int | None = None


@dataclass
class SectionMergePlan:
    """Planned merge of an AI-generated section into an existing section."""

    target_section_id: str | None
    incoming_section: dict[str, Any]
    added_units: list[MergeAction] = field(default_factory=list)
    replaced_units: list[MergeAction] = field(default_factory=list)
    added_lessons_by_unit: dict[str, list[MergeAction]] = field(default_factory=dict)
    replaced_lessons_by_unit: dict[str, list[MergeAction]] = field(default_factory=dict)


class CourseAdapter:
    """In-memory working copy of a course directory with save/validate/lint."""

    def __init__(self) -> None:
        self.course_dir: Path | None = None
        self.index: dict[str, Any] = {}
        self.sections: list[dict[str, Any]] = []
        self.vocab: list[dict[str, Any]] = []
        self.expressions: list[dict[str, Any]] = []
        self.grammar_points: list[dict[str, Any]] = []
        self.expressions_version: int = 1
        self._snapshot: dict[str, Any] | None = None
        self._hash_cache: dict[str, int] = {}
        self._resource_listeners: list = []
        # id -> (section, unit) and id -> (section, unit, lesson) indexes
        # used by find_unit/find_lesson to avoid full-tree scans on every
        # command. Lazily rebuilt when ``_node_index_dirty`` is set.
        self._unit_index: dict[str, tuple[dict[str, Any], dict[str, Any]]] = {}
        self._lesson_index: dict[str, tuple[dict[str, Any], dict[str, Any], dict[str, Any]]] = {}
        self._node_index_dirty: bool = True

    # --- Resource change notification (A3) --------------------------------

    def add_resource_listener(self, callback) -> None:
        """Register a callable invoked whenever in-memory resources change.

        The callback receives no arguments; listeners re-query
        ``vocab_options`` / ``expression_options`` / ``grammar_options`` to
        refresh their reference dropdowns in place.
        """
        if callable(callback) and callback not in self._resource_listeners:
            self._resource_listeners.append(callback)

    def remove_resource_listener(self, callback) -> None:
        try:
            self._resource_listeners.remove(callback)
        except ValueError:
            logger.warning("Tried to remove a resource listener that was not registered")

    def notify_resources_changed(self) -> None:
        """Fire resource listeners. Called by the resource editor after any
        in-memory vocab/expressions/grammar mutation."""
        for cb in list(self._resource_listeners):
            try:
                cb()
            except Exception:
                logger.exception("Resource listener failed")

    def load(self, course_dir: Path) -> None:
        self.course_dir = Path(course_dir)
        start = time.perf_counter()
        try:
            bundle = api.load_course(self.course_dir)
            self.index = bundle.index
            self.sections = bundle.sections
            self.vocab = bundle.vocab
            self.expressions = bundle.expressions
            self.grammar_points = bundle.grammar_points
            self.expressions_version = bundle.expressions_version
            self._snapshot = self._deep_snapshot()
            self._refresh_hash_cache()
            self.invalidate_node_index()
        except Exception:
            telemetry.record_error(
                context={"action": "repo.load", "course_dir": str(self.course_dir)},
            )
            raise
        finally:
            telemetry.record_duration(
                "repo.load",
                (time.perf_counter() - start) * 1000,
                payload={"course_dir": str(self.course_dir)},
            )

    def _refresh_hash_cache(self) -> None:
        """Cache hashes of the last-saved snapshot."""
        snap = self._snapshot or self._deep_snapshot()
        self._hash_cache = {
            "index": self._state_hash({"index": snap["index"]}),
            "sections": self._state_hash({"sections": snap["sections"]}),
            "vocab": self._state_hash({"vocab": snap["vocab"]}),
            "expressions": self._state_hash({"expressions": snap["expressions"]}),
            "grammar_points": self._state_hash({"grammar_points": snap["grammar_points"]}),
        }

    def invalidate_node_index(self) -> None:
        """Mark the id->node index as stale.

        Call after any mutation that reorders, adds, removes, or replaces
        entries in ``self.sections`` (or sub-lists). The next ``find_unit``
        / ``find_lesson`` will rebuild lazily. Cheap if nothing queries.
        """
        self._node_index_dirty = True

    def _rebuild_node_indexes(self) -> None:
        """Rebuild ``_unit_index`` and ``_lesson_index`` from ``self.sections``."""
        self._unit_index = {}
        self._lesson_index = {}
        for section in self.sections:
            for unit in section.get("units") or []:
                if not isinstance(unit, dict):
                    continue
                uid = unit.get("id")
                if uid:
                    self._unit_index[uid] = (section, unit)
                for lesson in unit.get("lessons") or []:
                    if not isinstance(lesson, dict):
                        continue
                    lid = lesson.get("id")
                    if lid:
                        self._lesson_index[lid] = (section, unit, lesson)
        self._node_index_dirty = False

    def _ensure_node_index(self) -> None:
        if self._node_index_dirty:
            self._rebuild_node_indexes()

    @staticmethod
    def is_course_dir(path: Path) -> bool:
        """Return True if ``path`` looks like a course directory."""
        return (Path(path) / "index.json").is_file()

    def init_new(self, course_dir: Path, meta: dict[str, Any]) -> None:
        """Create a brand-new sample course directory and load it.

        ``meta`` may contain:
        - display_name (str)
        - language (str, target language code, e.g. "en")
        - source_language (str, e.g. "Chinese", used for sample content only)
        - section_count (int)
        - lessons_per_unit (int)
        """
        course_dir = Path(course_dir)
        start = time.perf_counter()
        if course_dir.exists() and any(course_dir.iterdir()):
            raise FileExistsError(f"目标目录非空，无法初始化：{course_dir}")
        course_dir.mkdir(parents=True, exist_ok=True)
        (course_dir / "sections").mkdir(exist_ok=True)

        language = meta.get("language", "en")
        source_language = meta.get("source_language", "Chinese")
        display_name = meta.get("display_name", "My Chinese-English Course")
        section_count = max(1, min(8, int(meta.get("section_count", 3))))
        lessons_per_unit = max(1, int(meta.get("lessons_per_unit", 3)))

        index = {
            "version": 1,
            "language": language,
            "displayName": display_name,
            "sections": [],
        }
        sections = []
        for i in range(1, section_count + 1):
            sid = f"section{i}"
            section = {
                "id": sid,
                "name": f"Section {i}",
                "description": self._sample_section_description(i, source_language),
                "prerequisiteSectionIds": [f"section{i-1}"] if i > 1 else [],
                "units": [
                    {
                        "id": f"{sid}-u1",
                        "name": "Unit 1",
                        "description": "",
                        "prerequisiteUnitIds": [],
                        "lessons": [],
                    }
                ],
            }
            if i == 1:
                section["units"][0]["lessons"].append(
                    self._build_sample_intro_lesson(source_language, language)
                )
            else:
                for li in range(1, lessons_per_unit + 1):
                    section["units"][0]["lessons"].append(
                        {
                            "id": f"{sid}-u1-l{li}",
                            "name": f"Lesson {li}",
                            "description": "",
                            "type": "normal",
                            "template": "intro",
                            "prerequisiteLessonIds": [],
                            "content": {"subLessons": []},
                        }
                    )
            sections.append(section)
            index["sections"].append(
                {
                    "id": sid,
                    "name": section["name"],
                    "description": section["description"],
                    "level": "A1" if i <= 3 else "A2" if i <= 5 else "B1" if i <= 7 else "B2",
                    "prerequisiteSectionIds": section["prerequisiteSectionIds"],
                    "file": f"sections/{sid}.json",
                }
            )

        api.save_json(course_dir / "index.json", index)
        for section, entry in zip(sections, index["sections"]):
            api.save_json(course_dir / entry["file"], section)
        api.save_json(
            course_dir / "vocab.json",
            {
                "version": 1,
                "language": language,
                "words": self._sample_vocab(language),
            },
        )
        api.save_json(
            course_dir / "expressions.json",
            {
                "version": 1,
                "language": language,
                "expressions": self._sample_expressions(language),
            },
        )
        api.save_json(
            course_dir / "grammar_points.json",
            {"grammarPoints": self._sample_grammar_points(language)},
        )

        self.load(course_dir)
        telemetry.record_duration(
            "repo.init_new",
            (time.perf_counter() - start) * 1000,
            payload={
                "course_dir": str(course_dir),
                "language": language,
                "section_count": meta.get("section_count", 3),
            },
        )

    @staticmethod
    def _sample_section_description(index: int, source_language: str) -> str:
        if source_language.lower() in ("chinese", "zh", "zh-cn", "中文"):
            return "示例单元"
        return "Sample section"

    @staticmethod
    def _sample_vocab(language: str) -> list[dict[str, Any]]:
        """Return a few casual sample words for the target language."""
        if language.lower() in ("en", "english"):
            words = [
                ("你好", "Hello"),
                ("谢谢", "Thank you"),
                ("再见", "Goodbye"),
                ("水", "Water"),
                ("猫", "Cat"),
            ]
        else:
            words = [
                ("hello", "Hello"),
                ("thank you", "Thank you"),
                ("goodbye", "Goodbye"),
                ("water", "Water"),
                ("cat", "Cat"),
            ]
        return [
            {
                "id": f"w-{slugify(en)}",
                "term": en,
                "translation": zh,
                "pronunciation": None,
                "audioAsset": None,
                "tags": ["sample"],
            }
            for zh, en in words
        ]

    @staticmethod
    def _sample_expressions(language: str) -> list[dict[str, Any]]:
        if language.lower() in ("en", "english"):
            items = [
                ("你好，我叫…", "Hello, my name is…"),
                ("谢谢！", "Thank you!"),
                ("再见！", "Goodbye!"),
            ]
        else:
            items = [
                ("Hello, my name is…", "Hello, my name is…"),
                ("Thank you!", "Thank you!"),
                ("Goodbye!", "Goodbye!"),
            ]
        return [
            {
                "id": f"e-{slugify(en)[:20]}",
                "term": en,
                "translation": zh,
                "pronunciation": None,
                "audioAsset": None,
                "tags": ["sample"],
            }
            for zh, en in items
        ]

    @staticmethod
    def _sample_grammar_points(language: str) -> list[dict[str, Any]]:
        if language.lower() in ("en", "english"):
            title = "主谓宾语序"
            explanation = "英语基本语序是主语 + 谓语 + 宾语。"
        else:
            title = "Basic word order"
            explanation = "Basic SVO word order."
        return [
            {
                "id": "g-word-order",
                "title": title,
                "explanation": explanation,
                "exampleExpressionIds": [],
                "exampleSentenceIds": [],
                "practiceItems": [],
            }
        ]

    def _build_sample_intro_lesson(
        self, source_language: str, target_language: str
    ) -> dict[str, Any]:
        """Build a casual intro lesson using Chinese-English direction."""
        if target_language.lower() in ("en", "english"):
            word = ("你好", "Hello", "nǐ hǎo")
            sentence = ("你好吗？", "How are you?")
        else:
            word = ("Hello", "Hello", "")
            sentence = ("How are you?", "How are you?")

        return {
            "id": "section1-u1-l1",
            "name": "Sample Intro",
            "description": "",
            "type": "normal",
            "template": "intro",
            "prerequisiteLessonIds": [],
            "content": {
                "subLessons": [
                    {
                        "id": "section1-u1-l1-sl1",
                        "name": "Sample words",
                        "stages": [
                            {
                                "id": "section1-u1-l1-sl1-st1",
                                "name": "Learn & produce",
                                "items": [
                                    {
                                        "runtimeType": "showWord",
                                        "id": "sw-hello",
                                        "wordId": "w-hello",
                                        "context": f"{word[1]} — {word[0]}",
                                    },
                                    {
                                        "runtimeType": "translateSentence",
                                        "id": "ts-hello",
                                        "source": word[0],
                                        "expected": word[1],
                                        "hints": [word[1].lower()],
                                    },
                                    {
                                        "runtimeType": "fillBlank",
                                        "id": "fb-hello",
                                        "sentence": f"_____, {sentence[1]}?",
                                        "answer": word[1],
                                        "hint": word[0],
                                    },
                                ],
                            }
                        ],
                    }
                ]
            },
        }

    def vocab_options(self) -> list[tuple[str, str]]:
        return [(w["id"], f"{w.get('term', w['id'])} — {w.get('translation', '')}")
                for w in self.vocab]

    def expression_options(self) -> list[tuple[str, str]]:
        return [(e["id"], f"{e.get('term', e['id'])} — {e.get('translation', '')}")
                for e in self.expressions]

    def grammar_options(self) -> list[tuple[str, str]]:
        return [(g["id"], g.get("title", g["id"])) for g in self.grammar_points]

    def section_file(self, section_id: str) -> Path:
        for entry in self.index.get("sections", []):
            if entry["id"] == section_id:
                return self.course_dir / entry["file"]
        raise KeyError(f"unknown section id: {section_id}")

    def find_section(self, section_id: str) -> dict[str, Any]:
        for section in self.sections:
            if section.get("id") == section_id:
                return section
        raise KeyError(f"unknown section: {section_id}")

    def find_unit(self, unit_id: str) -> tuple[dict[str, Any], dict[str, Any]]:
        self._ensure_node_index()
        hit = self._unit_index.get(unit_id)
        if hit is not None:
            section, unit = hit
            # Validate: the cached (section, unit) must still be wired into
            # self.sections. Commands that move lessons/units mutate lists
            # in place, so a stale cache can point at a detached unit dict.
            lessons = unit.get("lessons")
            if any(section is s for s in self.sections) and any(unit is u for u in (section.get("units") or [])):
                return section, unit
            # Stale — drop and fall through to rescan.
            self._unit_index.pop(unit_id, None)
        for section in self.sections:
            for unit in section.get("units") or []:
                if isinstance(unit, dict) and unit.get("id") == unit_id:
                    self._unit_index[unit_id] = (section, unit)
                    return section, unit
        raise KeyError(f"unknown unit: {unit_id}")

    def find_lesson(self, lesson_id: str) -> tuple[dict[str, Any], dict[str, Any], dict[str, Any]]:
        self._ensure_node_index()
        hit = self._lesson_index.get(lesson_id)
        if hit is not None:
            section, unit, lesson = hit
            if (
                any(section is s for s in self.sections)
                and any(unit is u for u in (section.get("units") or []))
                and any(lesson is l for l in (unit.get("lessons") or []))
            ):
                return section, unit, lesson
            self._lesson_index.pop(lesson_id, None)
        for section in self.sections:
            for unit in section.get("units") or []:
                for lesson in unit.get("lessons") or []:
                    if isinstance(lesson, dict) and lesson.get("id") == lesson_id:
                        self._lesson_index[lesson_id] = (section, unit, lesson)
                        return section, unit, lesson
        raise KeyError(f"unknown lesson: {lesson_id}")

    @staticmethod
    def move_within(items: list[Any], from_idx: int, to_idx: int) -> bool:
        """Move an element within a list in place (sibling reorder only).

        Returns True if the move was applied, False if indices were out of
        range or the move was a no-op. Used by the tree-level move commands
        (MoveSection/Unit/Lesson) which only ever reorder within a single
        parent list — hierarchy is preserved by construction.
        """
        if not (0 <= from_idx < len(items) and 0 <= to_idx < len(items)):
            return False
        if from_idx == to_idx:
            return False
        items.insert(to_idx, items.pop(from_idx))
        return True

    def validate_section_json(
        self,
        section_json: dict[str, Any],
        *,
        check_existing_ids: bool = True,
    ) -> list[dict[str, str]]:
        """Validate an AI-generated section dict before importing it.

        Returns a list of problem dicts with keys ``level``, ``message``,
        ``path``.  Empty list means the section can be imported.

        When ``check_existing_ids`` is ``False``, unit/lesson ids are only
        checked for local duplicates *within* ``section_json`` and for empty
        values, not for collisions with the rest of the course. This is what
        AI merge paths need: the AI reuses existing ids on purpose, and the
        importer decides whether to overwrite or append.
        """
        problems: list[dict[str, str]] = []
        if not isinstance(section_json, dict):
            return [
                {"level": "error", "message": "section 必须是 JSON 对象", "path": ""}
            ]

        sid = section_json.get("id", "")
        if not sid:
            problems.append(
                {"level": "error", "message": "section id 不能为空", "path": "id"}
            )
        if check_existing_ids:
            existing_section_ids = {s.get("id") for s in self.sections}
            existing_index_ids = {
                e.get("id") for e in self.index.get("sections", [])
            }
            if sid and (sid in existing_section_ids or sid in existing_index_ids):
                problems.append(
                    {
                        "level": "error",
                        "message": f"section id「{sid}」已存在",
                        "path": "id",
                    }
                )

        if not section_json.get("name"):
            problems.append(
                {"level": "error", "message": "section name 不能为空", "path": "name"}
            )

        units = section_json.get("units")
        if not isinstance(units, list) or not units:
            problems.append(
                {
                    "level": "error",
                    "message": "section 必须包含非空的 units 数组",
                    "path": "units",
                }
            )
            return problems

        if len(units) > api.MAX_UNITS_PER_SECTION:
            problems.append(
                {
                    "level": "error",
                    "message": (
                        f"section 包含 {len(units)} 个单元，"
                        f"超过上限 {api.MAX_UNITS_PER_SECTION}"
                    ),
                    "path": "units",
                }
            )

        vocab_ids = {w.get("id") for w in self.vocab}
        expression_ids = {e.get("id") for e in self.expressions}
        grammar_ids = {g.get("id") for g in self.grammar_points}
        # AI-generated sections may carry their own resources in top-level
        # words/expressions/grammarPoints arrays; merge their ids so that
        # showWord/expressionId/grammarPointId references resolve.
        for w in section_json.get("words") or []:
            if isinstance(w, dict):
                vocab_ids.add(w.get("id"))
        for e in section_json.get("expressions") or []:
            if isinstance(e, dict):
                expression_ids.add(e.get("id"))
        for g in section_json.get("grammarPoints") or []:
            if isinstance(g, dict):
                grammar_ids.add(g.get("id"))
        if check_existing_ids:
            existing_unit_ids = all_unit_ids(self.sections)
            existing_lesson_ids = all_lesson_ids(self.sections)
        else:
            existing_unit_ids: set[str] = set()
            existing_lesson_ids: set[str] = set()

        local_unit_ids: set[str] = set()
        for unit in units:
            uid = unit.get("id", "")
            if not uid:
                problems.append(
                    {
                        "level": "error",
                        "message": "unit id 不能为空",
                        "path": "units",
                    }
                )
            elif uid in local_unit_ids or (
                check_existing_ids and uid in existing_unit_ids
            ):
                problems.append(
                    {
                        "level": "error",
                        "message": f"unit id「{uid}」重复或已存在",
                        "path": f"unit:{uid}",
                    }
                )
            else:
                local_unit_ids.add(uid)

            lessons = unit.get("lessons", [])
            if len(lessons) > api.MAX_LESSONS_PER_UNIT:
                problems.append(
                    {
                        "level": "error",
                        "message": (
                            f"unit {uid} 包含 {len(lessons)} 个课时，"
                            f"超过上限 {api.MAX_LESSONS_PER_UNIT}"
                        ),
                        "path": f"unit:{uid}",
                    }
                )

            local_lesson_ids: set[str] = set()
            for lesson in lessons:
                lid = lesson.get("id", "")
                if not lid:
                    problems.append(
                        {
                            "level": "error",
                            "message": f"unit {uid} 中存在空 lesson id",
                            "path": f"unit:{uid}",
                        }
                    )
                elif lid in local_lesson_ids or (
                    check_existing_ids and lid in existing_lesson_ids
                ):
                    problems.append(
                        {
                            "level": "error",
                            "message": f"lesson id「{lid}」重复或已存在",
                            "path": f"unit:{uid}/lesson:{lid}",
                        }
                    )
                else:
                    local_lesson_ids.add(lid)

                lesson_problems = api.validate_lesson(
                    lesson, vocab_ids, expression_ids, grammar_ids
                )
                for p in lesson_problems:
                    problems.append(
                        {
                            "level": p.level,
                            "message": p.message,
                            "path": p.path or f"unit:{uid}/lesson:{lid}",
                        }
                    )

        return problems

    def plan_section_merge(
        self,
        target_section_id: str | None,
        incoming_section: dict[str, Any],
    ) -> SectionMergePlan:
        """Compute a merge plan for importing an AI-generated section.

        ``target_section_id`` is ``None`` when the section is brand new; in that
        case every unit/lesson is planned as ``add``. When it points to an
        existing section, units/lessons are classified as ``replace`` if their id
        already exists in the target, otherwise ``add``.
        """
        plan = SectionMergePlan(
            target_section_id=target_section_id,
            incoming_section=incoming_section,
        )
        incoming_units = incoming_section.get("units") or []
        if not isinstance(incoming_units, list):
            return plan

        if target_section_id is None:
            for unit in incoming_units:
                if not isinstance(unit, dict):
                    continue
                uid = unit.get("id", "")
                if not uid:
                    continue
                plan.added_units.append(
                    MergeAction(kind="unit", action="add", incoming=unit)
                )
            return plan

        try:
            target_section = self.find_section(target_section_id)
        except KeyError:
            # Fallback to treating everything as new if the target disappeared.
            return self.plan_section_merge(None, incoming_section)

        target_unit_index: dict[str, int] = {
            u.get("id"): i
            for i, u in enumerate(target_section.get("units") or [])
            if isinstance(u, dict) and u.get("id")
        }

        for unit in incoming_units:
            if not isinstance(unit, dict):
                continue
            uid = unit.get("id", "")
            if not uid:
                continue
            if uid in target_unit_index:
                plan.replaced_units.append(
                    MergeAction(
                        kind="unit",
                        action="replace",
                        incoming=unit,
                        target_index=target_unit_index[uid],
                    )
                )
                self._plan_lesson_merge(plan, uid, unit, target_section)
            else:
                plan.added_units.append(
                    MergeAction(kind="unit", action="add", incoming=unit)
                )

        return plan

    @staticmethod
    def _plan_lesson_merge(
        plan: SectionMergePlan,
        unit_id: str,
        incoming_unit: dict[str, Any],
        target_section: dict[str, Any],
    ) -> None:
        """Classify lessons inside a unit that already exists in the target."""
        target_unit = None
        for u in target_section.get("units") or []:
            if isinstance(u, dict) and u.get("id") == unit_id:
                target_unit = u
                break
        if target_unit is None:
            return

        target_lesson_index: dict[str, int] = {
            l.get("id"): i
            for i, l in enumerate(target_unit.get("lessons") or [])
            if isinstance(l, dict) and l.get("id")
        }

        for lesson in incoming_unit.get("lessons") or []:
            if not isinstance(lesson, dict):
                continue
            lid = lesson.get("id", "")
            if not lid:
                continue
            if lid in target_lesson_index:
                plan.replaced_lessons_by_unit.setdefault(unit_id, []).append(
                    MergeAction(
                        kind="lesson",
                        action="replace",
                        incoming=lesson,
                        target_index=target_lesson_index[lid],
                    )
                )
            else:
                plan.added_lessons_by_unit.setdefault(unit_id, []).append(
                    MergeAction(
                        kind="lesson", action="add", incoming=lesson
                    )
                )

    def update_section_meta(self, section_id: str, name: str, description: str) -> None:
        section = self.find_section(section_id)
        section["name"] = name
        section["description"] = description
        for entry in self.index.get("sections", []):
            if entry["id"] == section_id:
                entry["name"] = name
                entry["description"] = description

    def update_lesson_prereqs(self, lesson_id: str, prereq_ids: list[str]) -> None:
        _section, _unit, lesson = self.find_lesson(lesson_id)
        lesson["prerequisiteLessonIds"] = [p for p in prereq_ids if p != lesson_id]

    def section_prereq_options(self, exclude_id: str) -> list[tuple[str, str]]:
        return [(s["id"], f"{s.get('name', s['id'])} ({s['id']})")
                for s in self.sections if s.get("id") != exclude_id]

    def unit_prereq_options(self, section_id: str, exclude_id: str) -> list[tuple[str, str]]:
        section = self.find_section(section_id)
        return [(u["id"], f"{u.get('name', u['id'])} ({u['id']})")
                for u in section.get("units", []) if u.get("id") != exclude_id]

    def lesson_prereq_options(self, unit_id: str, exclude_id: str) -> list[tuple[str, str]]:
        _section, unit = self.find_unit(unit_id)
        return [(l["id"], f"{l.get('name', l['id'])} ({l['id']})")
                for l in unit.get("lessons", []) if l.get("id") != exclude_id]

    def new_lesson(self, unit_id: str, template: str) -> str:
        from src.backend.lesson_content import new_lesson_from_template
        _section, unit = self.find_unit(unit_id)
        lesson = new_lesson_from_template(template, unit)
        return lesson["id"]

    def delete_lesson(self, lesson_id: str) -> None:
        for section in self.sections:
            for unit in section.get("units", []):
                lessons = unit.get("lessons", [])
                for i, lesson in enumerate(lessons):
                    if lesson.get("id") == lesson_id:
                        del lessons[i]
                        return
        raise KeyError(f"unknown lesson: {lesson_id}")

    def duplicate_lesson(self, lesson_id: str) -> str:
        """Deep-copy a lesson with fresh structural ids into the same unit.

        Returns the new lesson id. Reference ids (wordId/expressionId/etc.)
        are preserved so the clone points at the same resources as the
        original (workshop2 P1).
        """
        from src.backend.lesson_content import clone_lesson_with_fresh_ids

        _section, unit, lesson = self.find_lesson(lesson_id)
        clone = clone_lesson_with_fresh_ids(
            lesson, name=f"{lesson.get('name', lesson_id)} 副本"
        )
        unit.setdefault("lessons", []).append(clone)
        return clone["id"]

    def new_unit(self, section_id: str, name: str = "New unit") -> str:
        from src.backend.lesson_content import short_id
        section = self.find_section(section_id)
        unit = {
            "id": short_id("u"),
            "name": name,
            "description": "",
            "prerequisiteUnitIds": [],
            "lessons": [],
        }
        section.setdefault("units", []).append(unit)
        return unit["id"]

    def delete_unit(self, unit_id: str) -> None:
        for section in self.sections:
            units = section.get("units", [])
            for i, unit in enumerate(units):
                if unit.get("id") == unit_id:
                    del units[i]
                    return
        raise KeyError(f"unknown unit: {unit_id}")

    def section_is_referenced(self, section_id: str) -> list[str]:
        """Return ids of other sections whose prerequisiteSectionIds include
        ``section_id``. Used to block deletion of a depended-on section."""
        refs: list[str] = []
        for section in self.sections:
            sid = section.get("id", "")
            if sid == section_id:
                continue
            if section_id in section.get("prerequisiteSectionIds", []):
                refs.append(sid)
        return refs

    def delete_section(self, section_id: str) -> None:
        """Remove a section from ``self.sections`` and from ``index["sections"]``.

        Does NOT clear prerequisiteSectionIds references in other sections; the
        caller should check ``section_is_referenced`` first and block deletion
        when references exist.
        """
        removed = False
        for i, section in enumerate(self.sections):
            if section.get("id") == section_id:
                del self.sections[i]
                removed = True
                break
        entries = self.index.get("sections", [])
        for i, entry in enumerate(entries):
            if entry.get("id") == section_id:
                del entries[i]
                break
        if not removed:
            raise KeyError(f"unknown section: {section_id}")

    def replace_section(self, section_id: str, new_section: dict[str, Any]) -> None:
        """Replace the section with id ``section_id`` by ``new_section`` in both
        ``self.sections`` and ``index["sections"]``. ``new_section["id"]`` must
        equal ``section_id`` (or the index entry keeps the old id)."""
        for i, section in enumerate(self.sections):
            if section.get("id") == section_id:
                self.sections[i] = new_section
                break
        else:
            raise KeyError(f"unknown section: {section_id}")
        for entry in self.index.get("sections", []):
            if entry.get("id") == section_id:
                entry["name"] = new_section.get("name", entry.get("name", ""))
                entry["description"] = new_section.get(
                    "description", entry.get("description", "")
                )
                entry["level"] = new_section.get(
                    "level", entry.get("level", "")
                )
                entry["prerequisiteSectionIds"] = new_section.get(
                    "prerequisiteSectionIds", entry.get("prerequisiteSectionIds", [])
                )
                break

    def replace_unit(
        self, section_id: str, unit_id: str, new_unit: dict[str, Any]
    ) -> None:
        """Replace the unit with id ``unit_id`` within the section ``section_id``."""
        section = self.find_section(section_id)
        units = section.get("units", [])
        for i, unit in enumerate(units):
            if unit.get("id") == unit_id:
                units[i] = new_unit
                return
        raise KeyError(f"unknown unit: {unit_id}")

    def replace_lesson(self, lesson_id: str, new_lesson: dict[str, Any]) -> None:
        """Replace the lesson with id ``lesson_id`` in its containing unit."""
        for section in self.sections:
            for unit in section.get("units", []):
                lessons = unit.get("lessons", [])
                for i, lesson in enumerate(lessons):
                    if lesson.get("id") == lesson_id:
                        lessons[i] = new_lesson
                        return
        raise KeyError(f"unknown lesson: {lesson_id}")

    def _resource_list(self, row_type: str) -> list[dict[str, Any]]:
        if row_type == "vocab":
            return self.vocab
        if row_type == "expressions":
            return self.expressions
        if row_type == "grammar_points":
            return self.grammar_points
        raise ValueError(f"unknown resource type: {row_type}")

    def _set_resource_list(
        self, row_type: str, entries: list[dict[str, Any]]
    ) -> None:
        if row_type == "vocab":
            self.vocab = entries
        elif row_type == "expressions":
            self.expressions = entries
        elif row_type == "grammar_points":
            self.grammar_points = entries
        else:
            raise ValueError(f"unknown resource type: {row_type}")

    def add_resource_entry(self, row_type: str) -> str:
        """Append a blank entry with a fresh id, return the id."""
        from src.backend.lesson_content import short_id
        if row_type in ("vocab", "expressions"):
            prefix = "w" if row_type == "vocab" else "e"
            entry: dict[str, Any] = {
                "id": short_id(prefix),
                "term": "",
                "translation": "",
                "pronunciation": None,
                "audioAsset": None,
                "tags": [],
            }
        elif row_type == "grammar_points":
            entry = {
                "id": short_id("g"),
                "title": "",
                "explanation": "",
                "exampleExpressionIds": [],
                "exampleSentenceIds": [],
                "practiceItems": [],
            }
        else:
            raise ValueError(f"unknown resource type: {row_type}")
        self._resource_list(row_type).append(entry)
        return entry["id"]

    def delete_resource_entry(self, row_type: str, entry_id: str) -> None:
        entries = self._resource_list(row_type)
        for i, e in enumerate(entries):
            if e.get("id") == entry_id:
                del entries[i]
                return
        raise KeyError(f"unknown {row_type} id: {entry_id}")

    def merge_section_resources(self, section: dict[str, Any]) -> dict[str, int]:
        """Merge a section's top-level words/expressions/grammarPoints into the
        course resource lists, skipping ids that already exist.

        Returns a dict with counts: {"vocab": n, "expressions": n, "grammar_points": n}.
        """
        mapping = {
            "words": ("vocab", self.vocab),
            "expressions": ("expressions", self.expressions),
            "grammarPoints": ("grammar_points", self.grammar_points),
        }
        added: dict[str, int] = {"vocab": 0, "expressions": 0, "grammar_points": 0}
        for section_key, (row_type, target) in mapping.items():
            existing_ids = {e.get("id") for e in target}
            for entry in section.get(section_key) or []:
                if not isinstance(entry, dict):
                    continue
                eid = entry.get("id")
                if not eid or eid in existing_ids:
                    continue
                target.append(entry)
                existing_ids.add(eid)
                added[row_type] += 1
        return added

    def import_csv(
        self, row_type: str, csv_path: Path
    ) -> list[dict[str, str]]:
        """Read CSV, merge into memory, return problems. Does not write files.

        On any error the in-memory list is left unchanged (warnings still
        apply). The caller must call save() to persist + validate.
        """
        start = time.perf_counter()
        rows = api.read_csv_file(csv_path)
        existing = self._resource_list(row_type)
        expression_ids = {e["id"] for e in self.expressions}
        merged, problems = api.import_csv_rows(
            row_type, existing, rows, expression_ids
        )
        errors = [p for p in problems if p.level == "error"]
        if not errors:
            self._set_resource_list(row_type, merged)
        telemetry.record_duration(
            "repo.import_csv",
            (time.perf_counter() - start) * 1000,
            payload={
                "row_type": row_type,
                "csv_path": str(csv_path),
                "error_count": len(errors),
                "warning_count": len([p for p in problems if p.level == "warning"]),
            },
        )
        return [p.to_dict() for p in problems]

    def export_csv(self, row_type: str, output_path: Path) -> None:
        """Write current in-memory resources to CSV."""
        headers, rows = api.export_csv_rows(
            row_type, self._resource_list(row_type)
        )
        api.write_csv_file(output_path, headers, rows)

    def sync_resources_with_git(self, git_dir: Path, lang: str) -> str:
        """Bidirectionally merge local resources with a git clone's resource JSON.

        Reads ``vocab.json`` / ``expressions.json`` / ``grammar_points.json``
        from ``git_dir`` (if present), merges by id (skipping duplicates) into
        both the local course and the git clone, then writes both sides.

        The on-disk git resource format is the *wrapped* object form written
        by ``api.save_course_bundle``:

          vocab.json          -> ``{"version":1,"language":..,"words":[..]}``
          expressions.json    -> ``{"version":N,"language":..,"expressions":[..]}``
          grammar_points.json -> ``{"grammarPoints":[..]}``

        Previous versions assumed a bare list on disk and always treated the
        git side as empty, then wrote a bare list back — destroying the
        wrapper, version and language metadata in the collaborator's repo.
        (B10)

        Returns a human-readable summary of what was merged.
        """
        git_dir = Path(git_dir)
        # row_type -> (local_list, filename, wrapper_key, default_wrapper)
        # wrapper_key is the dict key under which the list lives; for
        # grammar_points the wrapper carries no version/language.
        mapping: dict[str, tuple[list[dict[str, Any]], str, str, dict[str, Any]]] = {
            "vocab": (self.vocab, "vocab.json", "words",
                      {"version": 1, "language": lang, "words": []}),
            "expressions": (self.expressions, "expressions.json", "expressions",
                            {"version": self.expressions_version, "language": lang, "expressions": []}),
            "grammar_points": (self.grammar_points, "grammar_points.json", "grammarPoints",
                               {"grammarPoints": []}),
        }
        parts: list[str] = []
        for row_type, (local_list, filename, list_key, default_wrapper) in mapping.items():
            git_file = git_dir / filename
            git_wrapper: dict[str, Any] = dict(default_wrapper)
            if git_file.is_file():
                try:
                    raw = json.loads(git_file.read_text(encoding="utf-8"))
                except Exception:
                    raw = None
                if isinstance(raw, dict):
                    # Preserve any existing version/language but ensure the
                    # list key exists and is a list.
                    git_wrapper.update(raw)
                    existing_list = raw.get(list_key)
                    if not isinstance(existing_list, list):
                        existing_list = []
                elif isinstance(raw, list):
                    # Legacy bare-list format: wrap it, preserve entries.
                    existing_list = raw
                else:
                    existing_list = []
            else:
                existing_list = []
            git_list: list[dict[str, Any]] = existing_list

            # Merge git -> local.
            local_ids = {e.get("id") for e in local_list}
            added_to_local = 0
            for entry in git_list:
                if not isinstance(entry, dict):
                    continue
                eid = entry.get("id")
                if eid and eid not in local_ids:
                    local_list.append(entry)
                    local_ids.add(eid)
                    added_to_local += 1
            # Merge local -> git.
            git_ids = {e.get("id") for e in git_list}
            added_to_git = 0
            for entry in local_list:
                if not isinstance(entry, dict):
                    continue
                eid = entry.get("id")
                if eid and eid not in git_ids:
                    git_list.append(entry)
                    git_ids.add(eid)
                    added_to_git += 1
            # Write back to git preserving the wrapper object.
            git_wrapper[list_key] = git_list
            # Refresh language/version on the wrapper so the git copy stays
            # consistent with the local course after the merge.
            if "language" in git_wrapper:
                git_wrapper["language"] = lang
            if row_type == "expressions":
                git_wrapper["version"] = self.expressions_version
            # Atomic write: tmp + os.replace so a crash mid-write cannot
            # corrupt the collaborator's resource file. (B10/P8)
            tmp_file = git_file.with_suffix(git_file.suffix + ".tmp")
            tmp_file.write_text(
                json.dumps(git_wrapper, ensure_ascii=False, indent=2),
                encoding="utf-8",
            )
            os.replace(tmp_file, git_file)
            parts.append(f"{row_type}: 本地新增 {added_to_local}，Git 新增 {added_to_git}")
        self.notify_resources_changed()
        return "\n".join(parts)

    def detect_duplicates(self) -> list[dict[str, str]]:
        """Detect duplicate terms across vocab and expressions.

        Returns a list of ``{type, id, term, duplicate_in}`` dicts.
        """
        seen: dict[str, str] = {}  # normalized term -> "type:id"
        dupes: list[dict[str, str]] = []
        for entry in self.vocab:
            term = str(entry.get("term") or entry.get("source") or "").strip().lower()
            if not term:
                continue
            if term in seen:
                dupes.append({
                    "type": "vocab",
                    "id": str(entry.get("id", "")),
                    "term": term,
                    "duplicate_in": seen[term],
                })
            else:
                seen[term] = f"vocab:{entry.get('id', '')}"
        for entry in self.expressions:
            term = str(entry.get("source") or entry.get("term") or "").strip().lower()
            if not term:
                continue
            if term in seen:
                dupes.append({
                    "type": "expressions",
                    "id": str(entry.get("id", "")),
                    "term": term,
                    "duplicate_in": seen[term],
                })
            else:
                seen[term] = f"expressions:{entry.get('id', '')}"
        return dupes

    def export_resource_pack(self, output_path: Path) -> Path:
        """Export all resource lists as a single JSON file (resource pack).

        The pack format is ``{"vocab": [...], "expressions": [...],
        "grammar_points": [...]}``.
        """
        output_path = Path(output_path)
        data = {
            "vocab": self.vocab,
            "expressions": self.expressions,
            "grammar_points": self.grammar_points,
        }
        output_path.write_text(
            json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        return output_path

    def import_resource_pack(self, pack_path: Path, *, replace: bool = False) -> dict[str, int]:
        """Import a resource pack JSON file, merging by id.

        If ``replace`` is True, fully replace each list instead of merging.

        Returns counts: ``{"vocab": n, "expressions": n, "grammar_points": n}``.
        """
        pack_path = Path(pack_path)
        data = json.loads(pack_path.read_text(encoding="utf-8"))
        counts = {"vocab": 0, "expressions": 0, "grammar_points": 0}
        mapping = {
            "vocab": self.vocab,
            "expressions": self.expressions,
            "grammar_points": self.grammar_points,
        }
        for key, target in mapping.items():
            incoming = data.get(key, [])
            if replace:
                target.clear()
                target.extend(incoming)
                counts[key] = len(incoming)
            else:
                existing_ids = {e.get("id") for e in target}
                added = 0
                for entry in incoming:
                    eid = entry.get("id")
                    if eid and eid not in existing_ids:
                        target.append(entry)
                        existing_ids.add(eid)
                        added += 1
                counts[key] = added
        self.notify_resources_changed()
        return counts

    def _state_hash(self, data: dict[str, Any]) -> str:
        """Return a stable, salt-independent hash for a state dict.

        Uses sha256 over the canonical JSON so the value is reproducible
        across interpreter runs (Python's builtin ``hash`` is per-process
        salted, which produced false-positive "changed" results whenever
        the cache was rebuilt in a different session). (P5/B14)
        """
        payload = json.dumps(data, ensure_ascii=False, sort_keys=True).encode("utf-8")
        return hashlib.sha256(payload).hexdigest()

    def detect_changes(self) -> dict[str, bool]:
        """Compare current in-memory state vs last-saved snapshot using cached hashes."""
        current = {
            "index": self.index,
            "sections": self.sections,
            "vocab": self.vocab,
            "expressions": self.expressions,
            "grammar_points": self.grammar_points,
        }
        if not self._hash_cache:
            self._refresh_hash_cache()
        return {
            key: self._state_hash({key: current[key]}) != self._hash_cache.get(key, "")
            for key in current
        }

    def version_bump_plan(
        self, changes: dict[str, bool] | None = None
    ) -> dict[str, tuple[int, int]]:
        """Return {file: (current_version, next_version)} for files to bump.

        ``changes`` may be passed to reuse an already-computed
        ``detect_changes()`` result (avoids re-hashing the whole course).
        """
        if changes is None:
            changes = self.detect_changes()
        plan: dict[str, tuple[int, int]] = {}
        if changes["index"] or changes["sections"]:
            cur = int(self.index.get("version", 1))
            plan["index"] = (cur, cur + 1)
        if changes["expressions"]:
            plan["expressions"] = (self.expressions_version, self.expressions_version + 1)
        return plan

    def apply_version_bump(self, plan: dict[str, tuple[int, int]]) -> None:
        """Apply version bumps to in-memory state (caller then save())."""
        if "index" in plan:
            self.index["version"] = plan["index"][1]
        if "expressions" in plan:
            self.expressions_version = plan["expressions"][1]

    def audio_manifest_rows(self) -> list[dict[str, str]]:
        """Return audio manifest rows (delegates to backend API)."""
        assert self.course_dir is not None
        return api.build_audio_manifest_rows(self.course_dir)

    def release_diff(self) -> dict[str, dict[str, Any]]:
        """Compare last-saved snapshot (before) vs current (after) by id sets."""
        snap = self._snapshot or self._deep_snapshot()
        result: dict[str, dict[str, Any]] = {}
        for key, snap_list, cur_list in [
            ("vocab", snap["vocab"], self.vocab),
            ("expressions", snap["expressions"], self.expressions),
            ("grammar_points", snap["grammar_points"], self.grammar_points),
            ("sections", snap["index"].get("sections", []), self.index.get("sections", [])),
        ]:
            before = {e.get("id", "") for e in snap_list if e.get("id")}
            after = {e.get("id", "") for e in cur_list if e.get("id")}
            result[key] = {
                "added": sorted(after - before),
                "removed": sorted(before - after),
                "unchanged_count": len(before & after),
            }
        return result

    def release_report(self) -> dict[str, Any]:
        """Aggregate release checklist data for the publish dialog."""
        changes = self.detect_changes()
        version_bump = self.version_bump_plan(changes)
        audio_manifest = self.audio_manifest_rows()
        diff = self.release_diff()
        validate = api.validate_course_dir(self.course_dir) if self.course_dir else api.ValidationResult(ok=True, error_count=0, problems=[])
        lint = api.lint_course_dir(self.course_dir) if self.course_dir else []
        return {
            "changes": changes,
            "version_bump": version_bump,
            "audio_manifest": audio_manifest,
            "diff": diff,
            "validation": {
                "ok": validate.ok,
                "errors": [p.to_dict() for p in validate.problems if p.level == "error"],
                "warnings": [p.to_dict() for p in lint if p.level == "warning"],
            },
        }

    def _deep_snapshot(self) -> dict[str, Any]:
        return {
            "index": deepcopy(self.index),
            "sections": deepcopy(self.sections),
            "vocab": deepcopy(self.vocab),
            "expressions": deepcopy(self.expressions),
            "grammar_points": deepcopy(self.grammar_points),
        }

    def _restore_from(self, snapshot: dict[str, Any]) -> None:
        self.index = deepcopy(snapshot["index"])
        self.sections = deepcopy(snapshot["sections"])
        self.vocab = deepcopy(snapshot.get("vocab", self.vocab))
        self.expressions = deepcopy(snapshot.get("expressions", self.expressions))
        self.grammar_points = deepcopy(snapshot.get("grammar_points", self.grammar_points))
        self.invalidate_node_index()

    def _write_files_to_dir(self, target_dir: Path) -> None:
        """Write all course files to ``target_dir`` mirroring the course layout."""
        assert self.course_dir is not None
        target_dir.mkdir(parents=True, exist_ok=True)
        (target_dir / "sections").mkdir(exist_ok=True)

        api.save_json(target_dir / "index.json", self.index)
        for section in self.sections:
            path = self.section_file(section["id"])
            rel = path.relative_to(self.course_dir)
            api.save_json(target_dir / rel, section)
        language = self.index.get("language", "")
        api.save_json(
            target_dir / "vocab.json",
            {"version": 1, "language": language, "words": self.vocab},
        )
        api.save_json(
            target_dir / "expressions.json",
            {
                "version": self.expressions_version,
                "language": language,
                "expressions": self.expressions,
            },
        )
        api.save_json(
            target_dir / "grammar_points.json",
            {"grammarPoints": self.grammar_points},
        )

    def _backup_json_files(self, src: Path, dst: Path) -> None:
        """Copy every JSON file under ``src`` to ``dst`` preserving structure.

        Old backup directories are skipped so they do not recurse indefinitely.
        After writing, prune the oldest sibling backups beyond a retention
        cap (default 20) so ``.varnamala-backup`` does not grow without
        bound. (M11)
        """
        for path in src.rglob("*.json"):
            rel = path.relative_to(src)
            if any(part.startswith(".varnamala-backup") for part in rel.parts):
                continue
            target = dst / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, target)
        self._prune_old_backups(dst.parent, keep=20)

    @staticmethod
    def _prune_old_backups(backup_root: Path, keep: int = 20) -> None:
        """Remove the oldest backup dirs under ``backup_root`` beyond ``keep``.

        Backup dirs are named ``YYYYMMDD-HHMMSS-ffffff`` so lexicographic
        sort matches chronological order. Silently no-ops if the dir is
        missing or malformed.
        """
        if not backup_root.is_dir() or keep < 1:
            return
        try:
            children = [
                p for p in backup_root.iterdir()
                if p.is_dir() and not p.name.startswith(".")
            ]
        except OSError:
            return
        if len(children) <= keep:
            return
        children.sort(key=lambda p: p.name)
        for old in children[:-keep]:
            try:
                shutil.rmtree(old, ignore_errors=True)
            except Exception:  # noqa: BLE001 — best-effort prune
                pass

    def _replace_course_files_with(self, tmp_dir: Path, course_dir: Path) -> None:
        """Atomically replace course files with those in ``tmp_dir``.

        Any section file that no longer exists in ``tmp_dir`` (because the
        section was deleted) is removed from ``course_dir`` so no orphan files
        are left behind to confuse the loader/validator.
        """
        new_rel_paths: set[Path] = set()
        for tmp_file in tmp_dir.rglob("*.json"):
            rel = tmp_file.relative_to(tmp_dir)
            new_rel_paths.add(rel)
            target = course_dir / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            os.replace(tmp_file, target)

        sections_dir = course_dir / "sections"
        if sections_dir.is_dir():
            for old_file in sections_dir.glob("*.json"):
                rel = old_file.relative_to(course_dir)
                if rel not in new_rel_paths:
                    old_file.unlink()

    def save(self) -> SaveResult:
        """Persist the in-memory course to disk atomically with backup.

        1. Write a complete copy to a system temp directory.
        2. Run ``course_cli validate`` against the temp copy.
        3. If validation passes, backup the current on-disk JSON files and
           replace them with the temp copy.
        4. If anything fails, restore the in-memory snapshot and return an
           error result; the original files remain untouched.
        """
        if self.course_dir is None:
            return SaveResult(ok=False, message="未加载课程目录")

        rollback = self._snapshot
        if rollback is None:
            rollback = self._deep_snapshot()

        start = time.perf_counter()
        tmp_dir: Path | None = None
        result: SaveResult | None = None
        try:
            tmp_dir = Path(tempfile.mkdtemp(prefix=".varnamala-save-"))
            self._write_files_to_dir(tmp_dir)

            validate = api.validate_course_dir(tmp_dir)
            if not validate.ok:
                self._restore_from(rollback)
                errors = [p.to_dict() for p in validate.problems if p.level == "error"]
                result = SaveResult(
                    ok=False,
                    errors=errors,
                    message=f"校验失败，已回滚（{len(errors)} 个错误）",
                )
                telemetry.record_event(
                    "repo.save.failed",
                    payload={"reason": "validation", "error_count": len(errors)},
                )
                return result

            backup_dir = (
                self.course_dir
                / ".varnamala-backup"
                / datetime.now().strftime("%Y%m%d-%H%M%S-%f")
            )
            self._backup_json_files(self.course_dir, backup_dir)
            self._replace_course_files_with(tmp_dir, self.course_dir)
            # Files are durably replaced at this point: refresh the snapshot
            # immediately so a later failure/rollback can never resurrect
            # pre-save state over the newer on-disk files.
            self._snapshot = self._deep_snapshot()
            self._refresh_hash_cache()
            self.invalidate_node_index()
        except Exception as exc:
            self._restore_from(rollback)
            # Ensure on-disk state matches the restored snapshot so a partial
            # atomic replacement cannot leave the course in a mixed state.
            self._write_files_to_dir(self.course_dir)
            telemetry.record_error(
                exc,
                context={"action": "repo.save", "course_dir": str(self.course_dir)},
            )
            result = SaveResult(ok=False, message=f"保存失败: {exc}")
            return result
        finally:
            if tmp_dir is not None:
                shutil.rmtree(tmp_dir, ignore_errors=True)

        try:
            lint = api.lint_course_dir(self.course_dir)
            warnings = [p.to_dict() for p in lint if p.level == "warning"]
        except Exception as exc:  # noqa: BLE001 — lint is advisory and must
            telemetry.record_error(  # never turn a successful save into a crash
                exc,
                context={"action": "repo.save.lint", "course_dir": str(self.course_dir)},
            )
            warnings = []
        result = SaveResult(
            ok=True,
            warnings=warnings,
            message=f"保存成功，{len(warnings)} 条 lint 警告",
        )
        telemetry.record_duration(
            "repo.save",
            (time.perf_counter() - start) * 1000,
            payload={
                "course_dir": str(self.course_dir),
                "warning_count": len(warnings),
            },
        )
        return result
