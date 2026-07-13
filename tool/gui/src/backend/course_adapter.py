"""Adapter bridging the GUI to ``tool/course_cli.py``.

Loads course JSON via in-process import of course_cli functions, and runs
validate/lint via subprocess to capture structured output. JSON remains the
single source of truth; this adapter only holds an in-memory working copy.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import uuid
from copy import deepcopy
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

_REPO_ROOT = Path(__file__).resolve().parents[4]
_TOOL_DIR = _REPO_ROOT / "tool"
if str(_TOOL_DIR) not in sys.path:
    sys.path.insert(0, str(_TOOL_DIR))

import course_cli  # noqa: E402
from src.backend.lesson_content import (  # noqa: E402
    all_lesson_ids,
    all_unit_ids,
    slugify,
)


@dataclass
class SaveResult:
    ok: bool
    errors: list[dict[str, str]] = field(default_factory=list)
    warnings: list[dict[str, str]] = field(default_factory=list)
    message: str = ""


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

    def load(self, course_dir: Path) -> None:
        self.course_dir = Path(course_dir)
        self.index = course_cli.load_index(self.course_dir)
        self.sections = [
            section
            for _sid, section in course_cli.load_sections(self.course_dir)
        ]
        self.vocab = course_cli.load_vocab(self.course_dir)
        self.expressions = course_cli.load_expressions(self.course_dir)
        self.grammar_points = course_cli.load_grammar_points(self.course_dir)
        expr_data = course_cli.load_json(self.course_dir / "expressions.json")
        self.expressions_version = int(expr_data.get("version", 1))
        self._snapshot = self._deep_snapshot()
        self._refresh_hash_cache()

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

        course_cli.save_json(course_dir / "index.json", index)
        for section, entry in zip(sections, index["sections"]):
            course_cli.save_json(course_dir / entry["file"], section)
        course_cli.save_json(
            course_dir / "vocab.json",
            {
                "version": 1,
                "language": language,
                "words": self._sample_vocab(language),
            },
        )
        course_cli.save_json(
            course_dir / "expressions.json",
            {
                "version": 1,
                "language": language,
                "expressions": self._sample_expressions(language),
            },
        )
        course_cli.save_json(
            course_dir / "grammar_points.json",
            {"grammarPoints": self._sample_grammar_points(language)},
        )

        self.load(course_dir)

    @staticmethod
    def _sample_section_description(index: int, source_language: str) -> str:
        if source_language.lower() in ("chinese", "zh", "zh-cn", "中文"):
            return "示例单元"
        return "Sample section"

    @staticmethod
    def _sample_vocab(language: str) -> list[dict[str, Any]]:
        """Return a few casual sample words for the target language."""
        # Default Chinese-English direction: target=English, source hints in Chinese.
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
        # Default sample: Chinese source hints, English target answers.
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
        for section in self.sections:
            for unit in section.get("units", []):
                if unit.get("id") == unit_id:
                    return section, unit
        raise KeyError(f"unknown unit: {unit_id}")

    def find_lesson(self, lesson_id: str) -> tuple[dict[str, Any], dict[str, Any], dict[str, Any]]:
        for section in self.sections:
            for unit in section.get("units", []):
                for lesson in unit.get("lessons", []):
                    if lesson.get("id") == lesson_id:
                        return section, unit, lesson
        raise KeyError(f"unknown lesson: {lesson_id}")

    def validate_section_json(self, section_json: dict[str, Any]) -> list[dict[str, str]]:
        """Validate an AI-generated section dict before importing it.

        Returns a list of problem dicts with keys ``level``, ``message``,
        ``path``.  Empty list means the section can be imported.
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

        if len(units) > course_cli.MAX_UNITS_PER_SECTION:
            problems.append(
                {
                    "level": "error",
                    "message": (
                        f"section 包含 {len(units)} 个单元，"
                        f"超过上限 {course_cli.MAX_UNITS_PER_SECTION}"
                    ),
                    "path": "units",
                }
            )

        vocab_ids = {w.get("id") for w in self.vocab}
        expression_ids = {e.get("id") for e in self.expressions}
        grammar_ids = {g.get("id") for g in self.grammar_points}
        existing_unit_ids = all_unit_ids(self.sections)
        existing_lesson_ids = all_lesson_ids(self.sections)

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
            elif uid in local_unit_ids or uid in existing_unit_ids:
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
            if len(lessons) > course_cli.MAX_LESSONS_PER_UNIT:
                problems.append(
                    {
                        "level": "error",
                        "message": (
                            f"unit {uid} 包含 {len(lessons)} 个课时，"
                            f"超过上限 {course_cli.MAX_LESSONS_PER_UNIT}"
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
                elif lid in local_lesson_ids or lid in existing_lesson_ids:
                    problems.append(
                        {
                            "level": "error",
                            "message": f"lesson id「{lid}」重复或已存在",
                            "path": f"unit:{uid}/lesson:{lid}",
                        }
                    )
                else:
                    local_lesson_ids.add(lid)

                lesson_problems: list[course_cli.Problem] = []
                course_cli._validate_lesson(
                    lesson, vocab_ids, expression_ids, grammar_ids, lesson_problems
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

    def update_section_meta(self, section_id: str, name: str, description: str) -> None:
        section = self.find_section(section_id)
        section["name"] = name
        section["description"] = description
        for entry in self.index.get("sections", []):
            if entry["id"] == section_id:
                entry["name"] = name
                entry["description"] = description

    def update_unit_meta(self, unit_id: str, name: str, description: str) -> None:
        _section, unit = self.find_unit(unit_id)
        unit["name"] = name
        unit["description"] = description

    def update_lesson_meta(
        self,
        lesson_id: str,
        name: str,
        description: str,
    ) -> None:
        _section, _unit, lesson = self.find_lesson(lesson_id)
        lesson["name"] = name
        lesson["description"] = description

    def update_section_prereqs(self, section_id: str, prereq_ids: list[str]) -> None:
        section = self.find_section(section_id)
        section["prerequisiteSectionIds"] = [p for p in prereq_ids if p != section_id]

    def update_unit_prereqs(self, unit_id: str, prereq_ids: list[str]) -> None:
        _section, unit = self.find_unit(unit_id)
        unit["prerequisiteUnitIds"] = [p for p in prereq_ids if p != unit_id]

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

    def switch_lesson_template(self, lesson_id: str, new_template: str) -> None:
        from src.backend.lesson_content import switch_template
        _section, _unit, lesson = self.find_lesson(lesson_id)
        switch_template(lesson, new_template)

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

    def import_csv(
        self, row_type: str, csv_path: Path
    ) -> list[dict[str, str]]:
        """Read CSV, merge into memory, return problems. Does not write files.

        On any error the in-memory list is left unchanged (warnings still
        apply). The caller must call save() to persist + validate.
        """
        rows = course_cli._read_csv(csv_path)
        existing = self._resource_list(row_type)
        expression_ids = {e["id"] for e in self.expressions}
        merged, problems = course_cli.merge_csv_rows(
            row_type, existing, rows, expression_ids
        )
        errors = [p for p in problems if p.level == "error"]
        if not errors:
            self._set_resource_list(row_type, merged)
        return [{"level": p.level, "message": p.message} for p in problems]

    def export_csv(self, row_type: str, output_path: Path) -> None:
        """Write current in-memory resources to CSV."""
        headers, rows = course_cli.build_csv_rows(
            row_type, self._resource_list(row_type)
        )
        course_cli._write_csv(output_path, headers, rows)

    def _state_hash(self, data: dict[str, Any]) -> int:
        """Return a stable hash for a state dict without deep-copying."""
        return hash(json.dumps(data, ensure_ascii=False, sort_keys=True))

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
            key: self._state_hash({key: current[key]}) != self._hash_cache.get(key, -1)
            for key in current
        }

    def version_bump_plan(self) -> dict[str, tuple[int, int]]:
        """Return {file: (current_version, next_version)} for files to bump."""
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
        """Return audio manifest rows (delegates to course_cli.build_audio_manifest)."""
        assert self.course_dir is not None
        return course_cli.build_audio_manifest(self.course_dir)

    def release_diff(self) -> dict[str, dict[str, Any]]:
        """Compare last-saved snapshot (before) vs current (after) by id sets."""
        snap = self._snapshot or self._deep_snapshot()
        result: dict[str, dict[str, Any]] = {}
        for key, snap_list, cur_list in [
            ("vocab", snap["vocab"], self.vocab),
            ("expressions", snap["expressions"], self.expressions),
            ("grammar_points", snap["grammar_points"], self.grammar_points),
        ]:
            before = {e.get("id", "") for e in snap_list if e.get("id")}
            after = {e.get("id", "") for e in cur_list if e.get("id")}
            result[key] = {
                "added": sorted(after - before),
                "removed": sorted(before - after),
                "unchanged_count": len(before & after),
            }
        before_sec = {
            s.get("id", "") for s in snap["index"].get("sections", []) if s.get("id")
        }
        after_sec = {
            s.get("id", "") for s in self.index.get("sections", []) if s.get("id")
        }
        result["sections"] = {
            "added": sorted(after_sec - before_sec),
            "removed": sorted(before_sec - after_sec),
            "unchanged_count": len(before_sec & after_sec),
        }
        return result

    def release_report(self) -> dict[str, Any]:
        """Aggregate release checklist data for the publish dialog."""
        changes = self.detect_changes()
        version_bump = self.version_bump_plan()
        audio_manifest = self.audio_manifest_rows()
        diff = self.release_diff()
        validate = self._run_validate()
        lint = self._run_lint()
        return {
            "changes": changes,
            "version_bump": version_bump,
            "audio_manifest": audio_manifest,
            "diff": diff,
            "validation": {
                "ok": validate["ok"],
                "errors": [p for p in validate["problems"] if p["level"] == "error"],
                "warnings": [p for p in lint if p["level"] == "warning"],
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

    def _restore_snapshot(self) -> None:
        snap = self._snapshot
        assert snap is not None
        self.index = deepcopy(snap["index"])
        self.sections = deepcopy(snap["sections"])
        self.vocab = deepcopy(snap["vocab"])
        self.expressions = deepcopy(snap["expressions"])
        self.grammar_points = deepcopy(snap["grammar_points"])

    def save(self) -> SaveResult:
        if self.course_dir is None:
            return SaveResult(ok=False, message="未加载课程目录")
        rollback = self._snapshot
        if rollback is None:
            rollback = self._deep_snapshot()

        tmp_dir: Path | None = None
        try:
            tmp_dir = self._write_files_to_temp_dir()
        except Exception as exc:
            if tmp_dir is not None:
                shutil.rmtree(tmp_dir, ignore_errors=True)
            return SaveResult(ok=False, message=f"写入失败: {exc}")

        validate = self._run_validate_on_dir(tmp_dir)
        if not validate["ok"]:
            self._restore_from(rollback)
            shutil.rmtree(tmp_dir, ignore_errors=True)
            errors = [p for p in validate["problems"] if p["level"] == "error"]
            return SaveResult(
                ok=False,
                errors=errors,
                message=f"校验失败，已回滚（{len(errors)} 个错误）",
            )

        try:
            self._replace_course_files_with(tmp_dir)
        except Exception as exc:
            self._restore_from(rollback)
            shutil.rmtree(tmp_dir, ignore_errors=True)
            return SaveResult(ok=False, message=f"原子替换失败: {exc}")
        finally:
            shutil.rmtree(tmp_dir, ignore_errors=True)

        lint = self._run_lint()
        warnings = [p for p in lint if p["level"] == "warning"]
        self._snapshot = self._deep_snapshot()
        self._refresh_hash_cache()
        return SaveResult(
            ok=True,
            warnings=warnings,
            message=f"保存成功，{len(warnings)} 条 lint 警告",
        )

    def _write_files_to_temp_dir(self) -> Path:
        """Write all course files to a fresh temp directory mirroring the course layout.

        Returns the temp directory path. Caller is responsible for cleanup.
        """
        assert self.course_dir is not None
        tmp_dir = Path(tempfile.mkdtemp(prefix=".varnamala-save-", dir=str(self.course_dir)))
        (tmp_dir / "sections").mkdir(exist_ok=True)

        course_cli.save_json(tmp_dir / "index.json", self.index)
        for section in self.sections:
            path = self.section_file(section["id"])
            rel = path.relative_to(self.course_dir)
            course_cli.save_json(tmp_dir / rel, section)
        course_cli.save_json(
            tmp_dir / "vocab.json",
            {
                "version": 1,
                "language": self.index.get("language", ""),
                "words": self.vocab,
            },
        )
        course_cli.save_json(
            tmp_dir / "expressions.json",
            {
                "version": self.expressions_version,
                "language": self.index.get("language", ""),
                "expressions": self.expressions,
            },
        )
        course_cli.save_json(
            tmp_dir / "grammar_points.json",
            {"grammarPoints": self.grammar_points},
        )
        return tmp_dir

    def _replace_course_files_with(self, tmp_dir: Path) -> None:
        """Atomically replace course files with those in ``tmp_dir``.

        Any section file that no longer exists in ``tmp_dir`` (because the
        section was deleted) is removed from ``course_dir`` so no orphan files
        are left behind to confuse the loader/validator.
        """
        assert self.course_dir is not None
        new_rel_paths: set[Path] = set()
        for tmp_file in tmp_dir.rglob("*.json"):
            rel = tmp_file.relative_to(tmp_dir)
            new_rel_paths.add(rel)
            target = self.course_dir / rel
            if target.exists():
                target.unlink()
            os.replace(tmp_file, target)

        sections_dir = self.course_dir / "sections"
        if sections_dir.is_dir():
            for old_file in sections_dir.glob("*.json"):
                rel = old_file.relative_to(self.course_dir)
                if rel not in new_rel_paths:
                    old_file.unlink()

    def _run_validate_on_dir(self, course_dir: Path) -> dict[str, Any]:
        proc = subprocess.run(
            [
                sys.executable,
                str(_TOOL_DIR / "course_cli.py"),
                "--course-dir",
                str(course_dir),
                "validate",
                "--format",
                "json",
            ],
            capture_output=True,
            text=True,
            encoding="utf-8",
        )
        try:
            return json.loads(proc.stdout)
        except json.JSONDecodeError:
            return {
                "ok": False,
                "problems": [
                    {
                        "level": "error",
                        "message": f"validate 无效输出: {proc.stderr or proc.stdout}",
                        "path": "",
                    }
                ],
            }

    def _write_files(self) -> None:
        """Direct (non-atomic) write; retained for tests and internal use."""
        assert self.course_dir is not None
        course_cli.save_json(self.course_dir / "index.json", self.index)
        for section in self.sections:
            path = self.section_file(section["id"])
            course_cli.save_json(path, section)
        course_cli.save_json(
            self.course_dir / "vocab.json",
            {
                "version": 1,
                "language": self.index.get("language", ""),
                "words": self.vocab,
            },
        )
        course_cli.save_json(
            self.course_dir / "expressions.json",
            {
                "version": self.expressions_version,
                "language": self.index.get("language", ""),
                "expressions": self.expressions,
            },
        )
        course_cli.save_json(
            self.course_dir / "grammar_points.json",
            {"grammarPoints": self.grammar_points},
        )

    def _restore_from(self, snapshot: dict[str, Any]) -> None:
        self.index = deepcopy(snapshot["index"])
        self.sections = deepcopy(snapshot["sections"])
        self.vocab = deepcopy(snapshot.get("vocab", self.vocab))
        self.expressions = deepcopy(snapshot.get("expressions", self.expressions))
        self.grammar_points = deepcopy(snapshot.get("grammar_points", self.grammar_points))

    def _run_validate(self) -> dict[str, Any]:
        assert self.course_dir is not None
        proc = subprocess.run(
            [
                sys.executable,
                str(_TOOL_DIR / "course_cli.py"),
                "--course-dir",
                str(self.course_dir),
                "validate",
                "--format",
                "json",
            ],
            capture_output=True,
            text=True,
            encoding="utf-8",
        )
        try:
            return json.loads(proc.stdout)
        except json.JSONDecodeError:
            return {
                "ok": False,
                "problems": [
                    {
                        "level": "error",
                        "message": f"validate 无效输出: {proc.stderr or proc.stdout}",
                        "path": "",
                    }
                ],
            }

    def _run_lint(self) -> list[dict[str, str]]:
        assert self.course_dir is not None
        proc = subprocess.run(
            [
                sys.executable,
                str(_TOOL_DIR / "course_cli.py"),
                "--course-dir",
                str(self.course_dir),
                "lint",
            ],
            capture_output=True,
            text=True,
            encoding="utf-8",
        )
        problems: list[dict[str, str]] = []
        for line in (proc.stdout or "").splitlines():
            line = line.strip()
            if line.startswith("ERROR:"):
                problems.append({"level": "error", "message": line[6:].strip(), "path": ""})
            elif line.startswith("WARNING:"):
                problems.append({"level": "warning", "message": line[8:].strip(), "path": ""})
        return problems