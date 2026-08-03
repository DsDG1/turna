#!/usr/bin/env python3
"""Command-line toolchain for producing and validating Turna course content.

Subcommands:
  validate        Run the Python equivalent of Dart's course_validator.
                  Supports --format text|json (json for GUI/CI). Enforces
                  scale ceilings: max 60 units/section, 40 lessons/unit.
  export-csv      Export vocab / expressions / grammar_points to CSV.
  import-csv      Import vocab / expressions / grammar_points from CSV.
  lint            Find content quality problems (empty fields, missing audio,
                  dangling references, unknown tags).
  audio-manifest  Emit a CSV of all referenced audio assets and their status.
  diff            Compare two course directories and list changed IDs.

All commands default to `assets/courses/turkish` as the course directory and
can be overridden with `--course-dir`.
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import sys
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Any

DEFAULT_COURSE_DIR = Path("assets/courses/turkish")
SOUNDS_DIR = Path("assets/sounds")

# Design-contract limits (must match lib/courses/course_validator.dart).
MAX_UNITS_PER_SECTION = 60
MAX_LESSONS_PER_UNIT = 40

ALLOWED_TAGS = {
    "pronoun",
    "greeting",
    "verb",
    "noun",
    "animal",
    "color",
    "number",
    "emotion",
    "nature",
    "travel",
    "food",
    "family",
    "question",
    "particle",
    "adjective",
    "adverb",
}


# --------------------------------------------------------------------------- #
# Loading and normalisation helpers
# --------------------------------------------------------------------------- #


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def save_json(path: Path, data: Any) -> None:
    """Write JSON to ``path`` atomically.

    Writes to a sibling ``.tmp`` file, fsyncs it, then ``os.replace``s it
    into place. This means a crash (power loss, OOM kill, disk-full) can
    never leave a truncated JSON file at ``path`` — the destination is
    only touched atomically by the rename. Previously a crash mid-write
    could corrupt the file and the loader would then refuse to load the
    whole course. (P7/B24)

    On filesystems where ``os.replace`` is atomic (POSIX, and NTFS since
    Python 3.3), this gives full crash durability for the file content.
    The parent-directory fsync is skipped because it's expensive and the
    worst case is a renamed-in file that survives a journal replay.
    """
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    with tmp.open("w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
        f.flush()
        try:
            os.fsync(f.fileno())
        except OSError:
            # fsync may be unavailable on some platforms / in tests; the
            # atomic rename still protects against the most common
            # truncation case.
            pass
    os.replace(tmp, path)


def load_vocab(course_dir: Path) -> list[dict[str, Any]]:
    data = load_json(course_dir / "vocab.json")
    return list(data.get("words", []))


def load_expressions(course_dir: Path) -> list[dict[str, Any]]:
    data = load_json(course_dir / "expressions.json")
    return list(data.get("expressions", []) or [])


def load_grammar_points(course_dir: Path) -> list[dict[str, Any]]:
    data = load_json(course_dir / "grammar_points.json")
    return list(data.get("grammarPoints", []))


def load_index(course_dir: Path) -> dict[str, Any]:
    return load_json(course_dir / "index.json")


def load_sections(course_dir: Path) -> list[tuple[str, dict[str, Any]]]:
    """Return list of (section_id, section_data) for every section in index.

    Skips entries missing ``id`` or ``file`` (corrupt index) instead of
    raising ``KeyError`` and aborting the whole load. (M17)
    """
    index = load_index(course_dir)
    sections: list[tuple[str, dict[str, Any]]] = []
    for entry in index.get("sections", []):
        if not isinstance(entry, dict):
            continue
        sid = entry.get("id")
        section_file_rel = entry.get("file")
        if not sid or not section_file_rel:
            continue
        section_file = course_dir / section_file_rel
        sections.append((sid, load_json(section_file)))
    return sections


def normalize_flat_lesson(lesson: dict[str, Any]) -> None:
    """Match Dart _normalizeLesson: questions -> single default stage."""
    content = lesson.get("content")
    if not isinstance(content, dict):
        return
    has_stages = "stages" in content
    has_questions = "questions" in content
    if not has_questions:
        return
    if has_stages:
        raise ValueError(
            f'Lesson {lesson.get("id")} declares both "stages" and "questions"'
        )
    questions = content.pop("questions")
    lesson_name = lesson.get("name", "Practice")
    content["stages"] = [
        {
            "id": "stage-default",
            "name": lesson_name,
            "items": questions,
        }
    ]


def normalize_section(section: dict[str, Any]) -> None:
    """Apply flat-lesson normalization to every lesson in the section."""
    for unit in section.get("units", []):
        for lesson in unit.get("lessons", []):
            normalize_flat_lesson(lesson)


# --------------------------------------------------------------------------- #
# Reference collection
# --------------------------------------------------------------------------- #


def collect_word_ids(obj: Any) -> set[str]:
    ids: set[str] = set()
    if isinstance(obj, dict):
        if obj.get("runtimeType") == "showWord" and "wordId" in obj:
            ids.add(obj["wordId"])
        if "linkedWordIds" in obj:
            ids.update(obj["linkedWordIds"])
        for value in obj.values():
            ids.update(collect_word_ids(value))
    elif isinstance(obj, list):
        for item in obj:
            ids.update(collect_word_ids(item))
    return ids


def collect_expression_ids(obj: Any) -> set[str]:
    ids: set[str] = set()
    if isinstance(obj, dict):
        if obj.get("runtimeType") == "showExpression" and "expressionId" in obj:
            ids.add(obj["expressionId"])
        if "exampleExpressionIds" in obj:
            ids.update(obj["exampleExpressionIds"])
        for value in obj.values():
            ids.update(collect_expression_ids(value))
    elif isinstance(obj, list):
        for item in obj:
            ids.update(collect_expression_ids(item))
    return ids


def collect_grammar_point_ids(obj: Any) -> set[str]:
    ids: set[str] = set()
    if isinstance(obj, dict):
        if "grammarPointId" in obj and isinstance(obj["grammarPointId"], str):
            ids.add(obj["grammarPointId"])
        if "linkedGrammarPointIds" in obj:
            ids.update(obj["linkedGrammarPointIds"])
        for value in obj.values():
            ids.update(collect_grammar_point_ids(value))
    elif isinstance(obj, list):
        for item in obj:
            ids.update(collect_grammar_point_ids(item))
    return ids


def collect_audio_assets(obj: Any) -> set[str]:
    assets: set[str] = set()
    if isinstance(obj, dict):
        if "audioAsset" in obj and isinstance(obj["audioAsset"], str):
            assets.add(obj["audioAsset"])
        for value in obj.values():
            assets.update(collect_audio_assets(value))
    elif isinstance(obj, list):
        for item in obj:
            assets.update(collect_audio_assets(item))
    return assets


def is_listening_lesson(lesson: dict[str, Any], content: dict[str, Any]) -> bool:
    """True if this lesson is a listening lesson.

    Listening lessons bundle MP3 assets for their prompts; other lessons rely
    on runtime TTS for word/expression pronunciation. A lesson is listening if
    it is tagged ``template``/``type == "listening"`` or carries
    ``listeningPhases`` (the canonical structural discriminator is ``template``,
    but hand-authored JSON in the wild may set only ``type``).
    """
    return (
        lesson.get("template") == "listening"
        or lesson.get("type") == "listening"
        or bool(content.get("listeningPhases"))
    )


# --------------------------------------------------------------------------- #
# Problem dataclass for lint / validate
# --------------------------------------------------------------------------- #


@dataclass(frozen=True)
class Problem:
    level: str  # 'error' | 'warning'
    message: str
    path: str = ""  # optional machine-readable locator (file / id path)

    def to_dict(self) -> dict[str, str]:
        return {
            "level": self.level,
            "message": self.message,
            "path": self.path,
        }


class CourseValidationError(Exception):
    def __init__(self, problems: list[Problem]) -> None:
        self.problems = problems


# --------------------------------------------------------------------------- #
# Validation
# --------------------------------------------------------------------------- #


def _validate_course(course_dir: Path) -> list[Problem]:
    """Run the Python equivalent of Dart's validateCourse."""
    problems: list[Problem] = []

    vocab = load_vocab(course_dir)
    expressions = load_expressions(course_dir)
    grammar_points = load_grammar_points(course_dir)
    vocab_ids = {w["id"] for w in vocab}
    expression_ids = {e["id"] for e in expressions}
    grammar_ids = {g["id"] for g in grammar_points}

    # Validate vocab/expressions/grammar id uniqueness up front.
    for name, entries in [
        ("vocab", vocab),
        ("expressions", expressions),
        ("grammar_points", grammar_points),
    ]:
        seen: set[str] = set()
        for entry in entries:
            eid = entry.get("id", "")
            if not eid:
                problems.append(Problem("error", f"{name} entry has empty id"))
            elif eid in seen:
                problems.append(Problem("error", f"Duplicate {name} id: {eid}"))
            else:
                seen.add(eid)

    # Grammar point exampleExpressionIds must resolve.
    for gp in grammar_points:
        for eid in gp.get("exampleExpressionIds", []):
            if eid and eid not in expression_ids:
                problems.append(
                    Problem(
                        "error",
                        f"Grammar point {gp.get('id')} references missing "
                        f"expressionId {eid}",
                    )
                )

    sections = load_sections(course_dir)
    section_ids: set[str] = set()
    unit_ids: set[str] = set()
    lesson_ids: set[str] = set()

    for section_id, section in sections:
        try:
            normalize_section(section)
        except ValueError as exc:
            problems.append(Problem("error", str(exc)))
            continue

        sid = section.get("id", "")
        if not sid:
            problems.append(Problem("error", "Section has empty id"))
        elif sid in section_ids:
            problems.append(Problem("error", f"Duplicate section id: {sid}"))
        else:
            section_ids.add(sid)

        if sid != section_id:
            problems.append(
                Problem(
                    "error",
                    f"Section file id mismatch: index says {section_id}, "
                    f"file says {sid}",
                )
            )

        units = section.get("units", [])
        if len(units) > MAX_UNITS_PER_SECTION:
            problems.append(
                Problem(
                    "error",
                    f"Section {sid} has {len(units)} units "
                    f"(max {MAX_UNITS_PER_SECTION}).",
                    path=f"section:{sid}",
                )
            )

        local_unit_ids: set[str] = set()
        for unit in units:
            uid = unit.get("id", "")
            if not uid:
                problems.append(
                    Problem("error", f"Unit in section {sid} has empty id")
                )
            elif uid in unit_ids:
                problems.append(Problem("error", f"Duplicate unit id: {uid}"))
            elif uid in local_unit_ids:
                problems.append(
                    Problem(
                        "error",
                        f"Duplicate unit id: {uid} (within section {sid})",
                    )
                )
            else:
                unit_ids.add(uid)
                local_unit_ids.add(uid)

            lessons = unit.get("lessons", [])
            if len(lessons) > MAX_LESSONS_PER_UNIT:
                problems.append(
                    Problem(
                        "error",
                        f"Unit {uid} has {len(lessons)} lessons "
                        f"(max {MAX_LESSONS_PER_UNIT}).",
                        path=f"section:{sid}/unit:{uid}",
                    )
                )

            local_lesson_ids: set[str] = set()
            for lesson in lessons:
                lid = lesson.get("id", "")
                if not lid:
                    problems.append(
                        Problem(
                            "error",
                            f"Lesson in unit {uid} has empty id",
                        )
                    )
                elif lid in lesson_ids:
                    problems.append(
                        Problem("error", f"Duplicate lesson id: {lid}")
                    )
                elif lid in local_lesson_ids:
                    problems.append(
                        Problem(
                            "error",
                            f"Duplicate lesson id: {lid} (within unit {uid})",
                        )
                    )
                else:
                    lesson_ids.add(lid)
                    local_lesson_ids.add(lid)

                _validate_lesson(
                    lesson, vocab_ids, expression_ids, grammar_ids, problems
                )

    return problems


def _validate_lesson(
    lesson: dict[str, Any],
    vocab_ids: set[str],
    expression_ids: set[str],
    grammar_ids: set[str],
    problems: list[Problem],
) -> None:
    lid = lesson.get("id", "<unknown>")
    content = lesson.get("content", {})
    template = lesson.get("template", "legacy")

    stages = content.get("stages", [])
    sub_lessons = content.get("subLessons", [])
    listening_phases = content.get("listeningPhases", [])
    reading_passage = content.get("readingPassage") or content.get("passage")
    has_reading = bool(reading_passage) or bool(
        isinstance(reading_passage, list) and reading_passage
    )

    has_stages = bool(stages)
    has_sub_lessons = bool(sub_lessons)
    has_listening = bool(listening_phases)

    # Template / content shape consistency.
    if template in ("intro", "practice"):
        if not has_sub_lessons:
            problems.append(
                Problem(
                    "error",
                    f"Lesson {lid} uses template {template} but has no subLessons",
                )
            )
            return
    elif template == "listening":
        if not has_listening:
            problems.append(
                Problem(
                    "error",
                    f"Lesson {lid} uses template listening but has no listeningPhases",
                )
            )
            return
    elif template == "reading":
        if not has_reading:
            problems.append(
                Problem(
                    "error",
                    f"Lesson {lid} uses template reading but has no readingPassage",
                )
            )
            return
    elif template == "mastery":
        if not has_stages:
            problems.append(
                Problem(
                    "error",
                    f"Lesson {lid} uses template mastery but has no stages",
                )
            )
            return
        if len(stages) > 1:
            problems.append(
                Problem(
                    "error",
                    f"Lesson {lid} uses template mastery and should have a "
                    f"single stage, but has {len(stages)}",
                )
            )
    elif template in ("legacy", "review"):
        if not has_stages and not has_sub_lessons and not has_listening:
            problems.append(
                Problem(
                    "error",
                    f"Lesson {lid} has no stages, subLessons, or listeningPhases",
                )
            )
            return

    if has_stages:
        _validate_stages(lid, stages, vocab_ids, expression_ids, problems)
    if has_sub_lessons:
        _validate_sub_lessons(
            lid, sub_lessons, vocab_ids, expression_ids, problems
        )
    if has_listening:
        _validate_listening_phases(
            lid, listening_phases, vocab_ids, expression_ids, problems
        )

    # Check grammar point links on interactions anywhere in the lesson.
    for gp_id in collect_grammar_point_ids(content):
        if gp_id and gp_id not in grammar_ids:
            problems.append(
                Problem(
                    "error",
                    f"Lesson {lid} references missing grammarPointId {gp_id}",
                )
            )


def _validate_stages(
    lesson_id: str,
    stages: list[Any],
    vocab_ids: set[str],
    expression_ids: set[str],
    problems: list[Problem],
    context_prefix: str = "",
) -> None:
    prefix = f"{context_prefix} / " if context_prefix else ""
    stage_ids: set[str] = set()
    for stage in stages:
        sid = stage.get("id", "")
        if not sid:
            problems.append(
                Problem(
                    "error",
                    f"{prefix}Stage in lesson {lesson_id} has empty id",
                )
            )
        elif sid in stage_ids:
            problems.append(
                Problem(
                    "error",
                    f"{prefix}Duplicate stage id {sid} in lesson {lesson_id}",
                )
            )
        else:
            stage_ids.add(sid)

        items = stage.get("items", [])
        if not items:
            problems.append(
                Problem(
                    "error",
                    f"{prefix}Stage {sid} in lesson {lesson_id} has no items",
                )
            )
            continue

        item_ids: set[str] = set()
        for i, item in enumerate(items):
            item_id = item.get("id", "")
            if not item_id:
                problems.append(
                    Problem(
                        "error",
                        f"{prefix}Item #{i} in stage {sid} (lesson {lesson_id}) "
                        f"has empty id",
                    )
                )
            elif item_id in item_ids:
                problems.append(
                    Problem(
                        "error",
                        f"{prefix}Duplicate item id {item_id} in stage {sid} "
                        f"(lesson {lesson_id})",
                    )
                )
            else:
                item_ids.add(item_id)

            if item.get("runtimeType") == "showWord":
                word_id = item.get("wordId")
                if word_id and word_id not in vocab_ids:
                    problems.append(
                        Problem(
                            "error",
                            f"{prefix}ShowWord {item_id} in stage {sid} "
                            f"(lesson {lesson_id}) references missing wordId "
                            f"{word_id}",
                        )
                    )
                expr_id = item.get("expressionId")
                if expr_id and expr_id not in expression_ids:
                    problems.append(
                        Problem(
                            "error",
                            f"{prefix}ShowWord {item_id} in stage {sid} "
                            f"(lesson {lesson_id}) references missing "
                            f"expressionId {expr_id}",
                        )
                    )


def _validate_sub_lessons(
    lesson_id: str,
    sub_lessons: list[Any],
    vocab_ids: set[str],
    expression_ids: set[str],
    problems: list[Problem],
) -> None:
    sub_ids: set[str] = set()
    for sub in sub_lessons:
        sid = sub.get("id", "")
        if not sid:
            problems.append(
                Problem(
                    "error",
                    f"SubLesson in lesson {lesson_id} has empty id",
                )
            )
        elif sid in sub_ids:
            problems.append(
                Problem(
                    "error",
                    f"Duplicate subLesson id {sid} in lesson {lesson_id}",
                )
            )
        else:
            sub_ids.add(sid)

        stages = sub.get("stages", [])
        if not stages:
            problems.append(
                Problem(
                    "error",
                    f"SubLesson {sid} in lesson {lesson_id} has no stages",
                )
            )
            continue

        _validate_stages(
            lesson_id,
            stages,
            vocab_ids,
            expression_ids,
            problems,
            context_prefix=sid,
        )


def _validate_listening_phases(
    lesson_id: str,
    phases: list[Any],
    vocab_ids: set[str],
    expression_ids: set[str],
    problems: list[Problem],
) -> None:
    phase_ids: set[str] = set()
    for phase in phases:
        pid = phase.get("id", "")
        if not pid:
            problems.append(
                Problem(
                    "error",
                    f"ListeningPhase in lesson {lesson_id} has empty id",
                )
            )
        elif pid in phase_ids:
            problems.append(
                Problem(
                    "error",
                    f"Duplicate listeningPhase id {pid} in lesson {lesson_id}",
                )
            )
        else:
            phase_ids.add(pid)

        phase_type = phase.get("type", "dialogue")
        items = phase.get("items", [])
        if phase_type != "summary" and not items:
            problems.append(
                Problem(
                    "error",
                    f"ListeningPhase {pid} in lesson {lesson_id} has no items",
                )
            )
            continue

        item_ids: set[str] = set()
        for i, item in enumerate(items):
            item_id = item.get("id", "")
            if not item_id:
                problems.append(
                    Problem(
                        "error",
                        f"Item #{i} in listeningPhase {pid} (lesson {lesson_id}) "
                        f"has empty id",
                    )
                )
            elif item_id in item_ids:
                problems.append(
                    Problem(
                        "error",
                        f"Duplicate item id {item_id} in listeningPhase {pid} "
                        f"(lesson {lesson_id})",
                    )
                )
            else:
                item_ids.add(item_id)

            if item.get("runtimeType") == "showWord":
                word_id = item.get("wordId")
                if word_id and word_id not in vocab_ids:
                    problems.append(
                        Problem(
                            "error",
                            f"ShowWord {item_id} in listeningPhase {pid} "
                            f"(lesson {lesson_id}) references missing wordId "
                            f"{word_id}",
                        )
                    )
                expr_id = item.get("expressionId")
                if expr_id and expr_id not in expression_ids:
                    problems.append(
                        Problem(
                            "error",
                            f"ShowWord {item_id} in listeningPhase {pid} "
                            f"(lesson {lesson_id}) references missing "
                            f"expressionId {expr_id}",
                        )
                    )


def cmd_validate(args: argparse.Namespace) -> int:
    problems = _validate_course(args.course_dir)
    errors = [p for p in problems if p.level == "error"]
    fmt = getattr(args, "format", "text") or "text"
    if fmt == "json":
        payload = {
            "ok": not errors,
            "errorCount": len(errors),
            "problems": [p.to_dict() for p in problems],
        }
        print(json.dumps(payload, ensure_ascii=False, indent=2))
        return 1 if errors else 0
    for p in problems:
        path_part = f" [{p.path}]" if p.path else ""
        print(f"{p.level.upper()}: {p.message}{path_part}")
    if errors:
        print(f"\nValidation failed with {len(errors)} error(s).")
        return 1
    print("Validation passed.")
    return 0


# --------------------------------------------------------------------------- #
# CSV import / export
# --------------------------------------------------------------------------- #


def _join_list(value: Any) -> str:
    if isinstance(value, list):
        return ", ".join(str(v) for v in value)
    return str(value) if value is not None else ""


def _split_list(value: str) -> list[str]:
    if not value or not value.strip():
        return []
    return [part.strip() for part in value.split(",") if part.strip()]


def _write_csv(path: Path, headers: list[str], rows: list[dict[str, str]]) -> None:
    with path.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=headers)
        writer.writeheader()
        for row in rows:
            writer.writerow({h: row.get(h, "") for h in headers})


def _read_csv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        return list(reader)


def build_csv_rows(
    row_type: str,
    entries: list[dict[str, Any]],
) -> tuple[list[str], list[dict[str, str]]]:
    """Return (headers, rows) for the given resource type. Pure: no I/O."""
    if row_type in ("vocab", "expressions"):
        headers = ["id", "term", "translation", "pronunciation", "audioAsset", "tags"]
        rows = [
            {
                "id": e.get("id", ""),
                "term": e.get("term", ""),
                "translation": e.get("translation", ""),
                "pronunciation": e.get("pronunciation", ""),
                "audioAsset": e.get("audioAsset", ""),
                "tags": _join_list(e.get("tags", [])),
            }
            for e in sorted(entries, key=lambda x: x.get("id", ""))
        ]
    elif row_type == "grammar_points":
        headers = [
            "id",
            "title",
            "explanation",
            "exampleExpressionIds",
            "exampleSentenceIds",
        ]
        rows = [
            {
                "id": e.get("id", ""),
                "title": e.get("title", ""),
                "explanation": e.get("explanation", ""),
                "exampleExpressionIds": _join_list(e.get("exampleExpressionIds", [])),
                "exampleSentenceIds": _join_list(e.get("exampleSentenceIds", [])),
            }
            for e in sorted(entries, key=lambda x: x.get("id", ""))
        ]
    else:
        raise ValueError(f"Unknown export type: {row_type}")
    return headers, rows


def _build_entry(
    row: dict[str, str],
    row_type: str,
    existing_by_id: dict[str, dict[str, Any]],
) -> dict[str, Any]:
    if row_type in ("vocab", "expressions"):
        return {
            "id": row["id"].strip(),
            "term": row["term"].strip(),
            "translation": row["translation"].strip(),
            "pronunciation": row.get("pronunciation", "").strip() or None,
            "audioAsset": row.get("audioAsset", "").strip() or None,
            "tags": _split_list(row.get("tags", "")),
        }
    # grammar_points: preserve practiceItems from existing (CSV omits it)
    return {
        "id": row["id"].strip(),
        "title": row["title"].strip(),
        "explanation": row.get("explanation", "").strip(),
        "exampleExpressionIds": _split_list(row.get("exampleExpressionIds", "")),
        "exampleSentenceIds": _split_list(row.get("exampleSentenceIds", "")),
        "practiceItems": existing_by_id.get(row["id"].strip(), {}).get(
            "practiceItems", []
        ),
    }


def merge_csv_rows(
    row_type: str,
    existing_entries: list[dict[str, Any]],
    rows: list[dict[str, str]],
    expression_ids: set[str],
) -> tuple[list[dict[str, Any]], list[Problem]]:
    """Merge CSV rows into existing entries by id. Pure: no I/O.

    Returns (merged_entries, problems). Upsert semantics: rows update/add by id,
    existing entries absent from CSV are kept. grammar_points practiceItems is
    preserved from existing.
    """
    existing_by_id = {e["id"]: e for e in existing_entries}
    problems: list[Problem] = []
    for row in rows:
        problems.extend(
            _validate_import_row(row, row_type, existing_by_id, expression_ids)
        )
    errors = [p for p in problems if p.level == "error"]
    if errors:
        return list(existing_entries), problems
    merged = dict(existing_by_id)
    for row in rows:
        entry = _build_entry(row, row_type, existing_by_id)
        merged[entry["id"]] = entry
    merged_list = sorted(merged.values(), key=lambda e: e["id"])
    return merged_list, problems


def cmd_export_csv(args: argparse.Namespace) -> int:
    course_dir = args.course_dir
    out_path = Path(args.output)

    if args.type == "vocab":
        entries = load_vocab(course_dir)
    elif args.type == "expressions":
        entries = load_expressions(course_dir)
    elif args.type == "grammar_points":
        entries = load_grammar_points(course_dir)
    else:
        print(f"Unknown export type: {args.type}", file=sys.stderr)
        return 1

    headers, rows = build_csv_rows(args.type, entries)
    _write_csv(out_path, headers, rows)
    print(f"Exported {len(rows)} {args.type} row(s) to {out_path}")
    return 0


def _validate_import_row(
    row: dict[str, str],
    row_type: str,
    existing_by_id: dict[str, dict[str, Any]],
    expression_ids: set[str],
) -> list[Problem]:
    problems: list[Problem] = []
    eid = row.get("id", "").strip()

    if not eid:
        problems.append(Problem("error", "Row has empty id"))

    if row_type == "grammar_points":
        title = row.get("title", "").strip()
        if not title:
            problems.append(
                Problem("error", f"Row {eid or '?'} has empty title")
            )
    else:
        term = row.get("term", "").strip()
        translation = row.get("translation", "").strip()
        if not term:
            problems.append(
                Problem("error", f"Row {eid or '?'} has empty term")
            )
        if not translation:
            problems.append(
                Problem("error", f"Row {eid or '?'} has empty translation")
            )

    if row_type == "vocab" and eid and not eid.startswith("w-"):
        problems.append(
            Problem("warning", f"Vocab id {eid} does not start with 'w-'")
        )

    if row_type == "grammar_points":
        for expr_id in _split_list(row.get("exampleExpressionIds", "")):
            if expr_id and expr_id not in expression_ids:
                problems.append(
                    Problem(
                        "error",
                        f"Grammar point {eid} references missing expressionId "
                        f"{expr_id}",
                    )
                )

    return problems


def cmd_import_csv(args: argparse.Namespace) -> int:
    course_dir = args.course_dir
    in_path = Path(args.input)
    dry_run = args.dry_run

    if args.type == "vocab":
        json_path = course_dir / "vocab.json"
        data = load_json(json_path)
        existing_entries = list(data.get("words", []))
        key = "words"
        row_type = "vocab"
    elif args.type == "expressions":
        json_path = course_dir / "expressions.json"
        data = load_json(json_path)
        existing_entries = list(data.get("expressions", []) or [])
        key = "expressions"
        row_type = "expressions"
    elif args.type == "grammar_points":
        json_path = course_dir / "grammar_points.json"
        data = load_json(json_path)
        existing_entries = list(data.get("grammarPoints", []))
        key = "grammarPoints"
        row_type = "grammar_points"
    else:
        print(f"Unknown import type: {args.type}", file=sys.stderr)
        return 1

    rows = _read_csv(in_path)
    expression_ids = {e["id"] for e in load_expressions(course_dir)}

    new_entries, problems = merge_csv_rows(
        row_type, existing_entries, rows, expression_ids
    )

    errors = [p for p in problems if p.level == "error"]
    for p in problems:
        print(f"{p.level.upper()}: {p.message}")

    if errors:
        print(f"\nImport aborted: {len(errors)} error(s).", file=sys.stderr)
        return 1

    data[key] = new_entries

    if dry_run:
        print(
            f"Dry run: would write {len(rows)} imported row(s), "
            f"resulting in {len(new_entries)} total {args.type} entry(ies)."
        )
        return 0

    save_json(json_path, data)
    print(
        f"Imported {len(rows)} row(s) into {json_path}; "
        f"total {args.type} entries: {len(new_entries)}"
    )
    return 0


# --------------------------------------------------------------------------- #
# Lint
# --------------------------------------------------------------------------- #


def _lint_entries(
    entries: list[dict[str, Any]],
    kind: str,
    referenced_ids: set[str],
    problems: list[Problem],
) -> None:
    terms: dict[str, list[str]] = defaultdict(list)
    translations: dict[str, list[str]] = defaultdict(list)

    for entry in entries:
        eid = entry.get("id", "")
        term = entry.get("term", "")
        translation = entry.get("translation", "")
        tags = entry.get("tags", []) or []

        if not term:
            problems.append(
                Problem("error", f"{kind} {eid} has empty term")
            )
        if not translation:
            problems.append(
                Problem("error", f"{kind} {eid} has empty translation")
            )

        if term:
            terms[term].append(eid)
        if translation:
            translations[translation].append(eid)

        if not tags:
            problems.append(
                Problem("warning", f"{kind} {eid} has no tags")
            )
        for tag in tags:
            if tag not in ALLOWED_TAGS:
                problems.append(
                    Problem(
                        "warning",
                        f"{kind} {eid} has unknown tag '{tag}'",
                    )
                )

        if eid and eid not in referenced_ids:
            problems.append(
                Problem("warning", f"{kind} {eid} is not referenced by any lesson")
            )

    for term, ids in terms.items():
        if len(ids) > 1:
            problems.append(
                Problem(
                    "warning",
                    f"Duplicate {kind} term '{term}' across ids: {', '.join(ids)}",
                )
            )
    for translation, ids in translations.items():
        if len(ids) > 1:
            problems.append(
                Problem(
                    "warning",
                    f"Duplicate {kind} translation '{translation}' across ids: "
                    f"{', '.join(ids)}",
                )
            )


def cmd_lint(args: argparse.Namespace) -> int:
    course_dir = args.course_dir
    strict = args.strict

    vocab = load_vocab(course_dir)
    expressions = load_expressions(course_dir)
    grammar_points = load_grammar_points(course_dir)

    vocab_ids = {w["id"] for w in vocab}
    expression_ids = {e["id"] for e in expressions}
    grammar_ids = {g["id"] for g in grammar_points}

    # Collect references from sections.
    referenced_word_ids: set[str] = set()
    referenced_expression_ids: set[str] = set()
    referenced_grammar_ids: set[str] = set()
    referenced_audio: dict[str, set[tuple[str, bool]]] = defaultdict(set)

    for section_id, section in load_sections(course_dir):
        normalize_section(section)
        for unit in section.get("units", []):
            for lesson in unit.get("lessons", []):
                lid = lesson.get("id", "")
                loc = f"{section_id}/{unit.get('id', '')}/{lid}"
                content = lesson.get("content", {})
                referenced_word_ids.update(collect_word_ids(content))
                referenced_expression_ids.update(collect_expression_ids(content))
                referenced_grammar_ids.update(collect_grammar_point_ids(content))
                is_listening = is_listening_lesson(lesson, content)
                for asset in collect_audio_assets(content):
                    referenced_audio[asset].add((loc, is_listening))

    problems: list[Problem] = []

    _lint_entries(vocab, "word", referenced_word_ids, problems)
    _lint_entries(expressions, "expression", referenced_expression_ids, problems)

    # Grammar points lint.
    for gp in grammar_points:
        gid = gp.get("id", "")
        title = gp.get("title", "")
        if not title:
            problems.append(Problem("error", f"grammar point {gid} has empty title"))
        if gid not in referenced_grammar_ids:
            problems.append(
                Problem("warning", f"grammar point {gid} is not referenced by any lesson")
            )
        for eid in gp.get("exampleExpressionIds", []):
            if eid and eid not in expression_ids:
                problems.append(
                    Problem(
                        "error",
                        f"grammar point {gid} references missing expressionId {eid}",
                    )
                )

    # Dangling references in sections.
    for section_id, section in load_sections(course_dir):
        normalize_section(section)
        for unit in section.get("units", []):
            for lesson in unit.get("lessons", []):
                lid = lesson.get("id", "")
                loc = f"{section_id}/{unit.get('id', '')}/{lid}"
                content = lesson.get("content", {})
                for wid in collect_word_ids(content):
                    if wid and wid not in vocab_ids:
                        problems.append(
                            Problem(
                                "error",
                                f"Dangling wordId {wid} in {loc}",
                            )
                        )
                for eid in collect_expression_ids(content):
                    if eid and eid not in expression_ids:
                        problems.append(
                            Problem(
                                "error",
                                f"Dangling expressionId {eid} in {loc}",
                            )
                        )
                for gid in collect_grammar_point_ids(content):
                    if gid and gid not in grammar_ids:
                        problems.append(
                            Problem(
                                "error",
                                f"Dangling grammarPointId {gid} in {loc}",
                            )
                        )

    # Missing audio files (only required for listening-lesson assets that
    # are not word/expression ids; word/expression audio is TTS at runtime).
    for asset, locations in sorted(referenced_audio.items()):
        if asset in vocab_ids or asset in expression_ids:
            continue

        listening_locs = {loc for loc, is_listening in locations if is_listening}
        non_listening_locs = {
            loc for loc, is_listening in locations if not is_listening
        }

        if non_listening_locs:
            problems.append(
                Problem(
                    "error",
                    f"audioAsset '{asset}' referenced outside a listening "
                    f"lesson: {', '.join(sorted(non_listening_locs))}",
                )
            )
            continue

        if not listening_locs:
            continue

        asset_path = _audio_asset_path(asset, "listening")
        if not asset_path.exists():
            problems.append(
                Problem(
                    "warning",
                    f"Missing audio file for listening asset '{asset}' "
                    f"(referenced in {', '.join(sorted(listening_locs))})",
                )
            )

    for p in problems:
        print(f"{p.level.upper()}: {p.message}")

    errors = [p for p in problems if p.level == "error"]
    if errors:
        print(f"\nLint found {len(errors)} error(s).")
        return 1
    if strict and any(p.level == "warning" for p in problems):
        print("\nLint failed in strict mode due to warnings.")
        return 1
    print("Lint passed.")
    return 0


# --------------------------------------------------------------------------- #
# Audio manifest
# --------------------------------------------------------------------------- #


def _audio_asset_path(asset: str, kind: str) -> Path:
    """Return the canonical filesystem path for a listening audio asset id.

    ``kind`` is retained for call-site compatibility but only listening
    assets are bundled now; word/expression pronunciation is runtime TTS.
    """
    return (SOUNDS_DIR / "listening" / f"{asset}.mp3").resolve()


def build_audio_manifest(course_dir: Path) -> list[dict[str, str]]:
    """Return manifest rows for referenced listening assets. Pure computation.

    Each row: {asset_id, type, referenced_by, status}.
    status = 'present' if the asset file exists else 'missing'.
    """
    vocab = {w["id"]: w for w in load_vocab(course_dir)}
    expressions = {e["id"]: e for e in load_expressions(course_dir)}
    word_and_expr_ids = set(vocab.keys()) | set(expressions.keys())

    referenced: dict[str, set[str]] = {}
    for section_id, section in load_sections(course_dir):
        normalize_section(section)
        for unit in section.get("units", []):
            for lesson in unit.get("lessons", []):
                lid = lesson.get("id", "")
                loc = f"{section_id}/{unit.get('id', '')}/{lid}"
                content = lesson.get("content", {})
                if not is_listening_lesson(lesson, content):
                    continue
                for asset in collect_audio_assets(content):
                    if asset in word_and_expr_ids:
                        continue
                    referenced.setdefault(asset, set()).add(loc)

    rows: list[dict[str, str]] = []
    for asset, locations in sorted(referenced.items()):
        asset_path = _audio_asset_path(asset, "listening")
        status = "present" if asset_path.exists() else "missing"
        rows.append(
            {
                "asset_id": asset,
                "type": "listening",
                "referenced_by": "; ".join(sorted(locations)),
                "status": status,
            }
        )
    return rows


def cmd_audio_manifest(args: argparse.Namespace) -> int:
    course_dir = args.course_dir
    out_path = Path(args.output)

    rows = build_audio_manifest(course_dir)
    total = len(rows)
    present = sum(1 for r in rows if r["status"] == "present")

    headers = ["asset_id", "type", "referenced_by", "status"]
    _write_csv(out_path, headers, rows)

    print(f"Wrote audio manifest ({len(rows)} listening assets) to {out_path}")
    pct = f"{present / total * 100:.1f}%" if total else "n/a"
    print(f"\nCoverage: {present}/{total} ({pct})")
    return 0


# --------------------------------------------------------------------------- #
# Diff
# --------------------------------------------------------------------------- #


def _id_set(course_dir: Path, loader: Any, key: str) -> set[str]:
    data = load_json(course_dir / f"{key}.json")
    if key == "vocab":
        entries = data.get("words", [])
    elif key == "expressions":
        entries = data.get("expressions", []) or []
    elif key == "grammar_points":
        entries = data.get("grammarPoints", [])
    else:
        entries = []
    return {e.get("id", "") for e in entries if e.get("id")}


def _section_ids(course_dir: Path) -> set[str]:
    index = load_index(course_dir)
    return {s.get("id", "") for s in index.get("sections", []) if s.get("id")}


def _diff_sets(
    before: set[str],
    after: set[str],
    label: str,
) -> list[str]:
    added = after - before
    removed = before - after
    changed = before & after
    lines: list[str] = []
    if added:
        lines.append(f"  added ({label}): {', '.join(sorted(added))}")
    if removed:
        lines.append(f"  removed ({label}): {', '.join(sorted(removed))}")
    if changed:
        lines.append(f"  unchanged ({label}): {len(changed)} id(s)")
    return lines


def cmd_diff(args: argparse.Namespace) -> int:
    before_dir = Path(args.before)
    after_dir = Path(args.after)

    print(f"Diff: {before_dir} -> {after_dir}")
    for label, key in [
        ("vocab", "vocab"),
        ("expressions", "expressions"),
        ("grammar_points", "grammar_points"),
    ]:
        before_ids = _id_set(before_dir, load_json, key)
        after_ids = _id_set(after_dir, load_json, key)
        lines = _diff_sets(before_ids, after_ids, label)
        if lines:
            print(f"\n{label}:")
            for line in lines:
                print(line)

    before_sections = _section_ids(before_dir)
    after_sections = _section_ids(after_dir)
    lines = _diff_sets(before_sections, after_sections, "sections")
    if lines:
        print("\nsections:")
        for line in lines:
            print(line)

    return 0


# --------------------------------------------------------------------------- #
# CLI entry point
# --------------------------------------------------------------------------- #


def _course_dir(value: str) -> Path:
    path = Path(value)
    if not path.is_dir():
        raise argparse.ArgumentTypeError(f"Not a directory: {value}")
    return path


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Turna course content toolchain",
    )
    parser.add_argument(
        "--course-dir",
        type=_course_dir,
        default=DEFAULT_COURSE_DIR,
        help="Course directory to operate on (default: assets/courses/turkish)",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    # validate
    p_validate = subparsers.add_parser(
        "validate", help="Validate course JSON against invariants"
    )
    p_validate.add_argument(
        "--format",
        choices=["text", "json"],
        default="text",
        help="Output format (json is for GUI / CI machine consumption)",
    )
    p_validate.set_defaults(func=cmd_validate)

    # export-csv
    p_export = subparsers.add_parser(
        "export-csv", help="Export vocab/expressions/grammar_points to CSV"
    )
    p_export.add_argument(
        "--type",
        required=True,
        choices=["vocab", "expressions", "grammar_points"],
        help="Which table to export",
    )
    p_export.add_argument(
        "--output", required=True, help="Output CSV file path"
    )
    p_export.set_defaults(func=cmd_export_csv)

    # import-csv
    p_import = subparsers.add_parser(
        "import-csv", help="Import vocab/expressions/grammar_points from CSV"
    )
    p_import.add_argument(
        "--type",
        required=True,
        choices=["vocab", "expressions", "grammar_points"],
        help="Which table to import",
    )
    p_import.add_argument("--input", required=True, help="Input CSV file path")
    p_import.add_argument(
        "--dry-run",
        action="store_true",
        help="Validate without writing files",
    )
    p_import.set_defaults(func=cmd_import_csv)

    # lint
    p_lint = subparsers.add_parser(
        "lint", help="Check content quality (warnings and errors)"
    )
    p_lint.add_argument(
        "--strict",
        action="store_true",
        help="Treat warnings as errors",
    )
    p_lint.set_defaults(func=cmd_lint)

    # audio-manifest
    p_audio = subparsers.add_parser(
        "audio-manifest", help="Generate CSV of referenced audio assets"
    )
    p_audio.add_argument(
        "--output", required=True, help="Output CSV file path"
    )
    p_audio.set_defaults(func=cmd_audio_manifest)

    # diff
    p_diff = subparsers.add_parser(
        "diff", help="Compare two course directories by id sets"
    )
    p_diff.add_argument("--before", required=True, help="Before course directory")
    p_diff.add_argument("--after", required=True, help="After course directory")
    p_diff.set_defaults(func=cmd_diff)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
