"""Stable backend API for the Turna GUI.

This module is the only part of the GUI that is allowed to import
course_cli. All other GUI code calls the functions and data classes
exposed here. When course_cli internals change, only this file needs
to be updated.
"""
from __future__ import annotations

import argparse
import contextlib
import io
import json
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

_TOOL_DIR = Path(__file__).resolve().parents[3]
if str(_TOOL_DIR) not in sys.path:
    sys.path.insert(0, str(_TOOL_DIR))

import course_cli  # noqa: E402

#: Timeout for the validate/lint subprocess fallbacks (a hung child must not
#: freeze the whole GUI; the in-process fast path needs no such guard).
_CLI_TIMEOUT_SECONDS = 60


MAX_UNITS_PER_SECTION = course_cli.MAX_UNITS_PER_SECTION
MAX_LESSONS_PER_UNIT = course_cli.MAX_LESSONS_PER_UNIT
ALLOWED_TAGS = course_cli.ALLOWED_TAGS


@dataclass(frozen=True)
class Problem:
    level: str  # 'error' | 'warning'
    message: str
    path: str = ""

    def to_dict(self) -> dict[str, str]:
        return {"level": self.level, "message": self.message, "path": self.path}


@dataclass
class ValidationResult:
    ok: bool
    error_count: int
    problems: list[Problem]


@dataclass
class CourseBundle:
    index: dict[str, Any]
    sections: list[dict[str, Any]]
    vocab: list[dict[str, Any]]
    expressions: list[dict[str, Any]]
    grammar_points: list[dict[str, Any]]
    expressions_version: int = 1


def load_json(path: Path) -> Any:
    return course_cli.load_json(path)


def save_json(path: Path, data: Any) -> None:
    course_cli.save_json(path, data)


def load_course(course_dir: Path) -> CourseBundle:
    index = course_cli.load_index(course_dir)
    sections = [section for _sid, section in course_cli.load_sections(course_dir)]
    vocab = course_cli.load_vocab(course_dir)
    expressions = course_cli.load_expressions(course_dir)
    grammar_points = course_cli.load_grammar_points(course_dir)
    expr_data = course_cli.load_json(course_dir / "expressions.json")
    expressions_version = int(expr_data.get("version", 1))
    return CourseBundle(
        index=index,
        sections=sections,
        vocab=vocab,
        expressions=expressions,
        grammar_points=grammar_points,
        expressions_version=expressions_version,
    )


def save_course_bundle(
    bundle: CourseBundle,
    course_dir: Path,
    section_path_for: callable[[str], Path],
) -> None:
    """Write a full course bundle to disk.

    ``section_path_for(section_id)`` must return the on-disk path for the
    given section file (usually ``course_dir / 'sections' / f'{sid}.json'``).
    """
    course_dir.mkdir(parents=True, exist_ok=True)
    course_cli.save_json(course_dir / "index.json", bundle.index)
    for section in bundle.sections:
        path = section_path_for(section["id"])
        path.parent.mkdir(parents=True, exist_ok=True)
        course_cli.save_json(path, section)
    language = bundle.index.get("language", "")
    course_cli.save_json(
        course_dir / "vocab.json",
        {"version": 1, "language": language, "words": bundle.vocab},
    )
    course_cli.save_json(
        course_dir / "expressions.json",
        {
            "version": bundle.expressions_version,
            "language": language,
            "expressions": bundle.expressions,
        },
    )
    course_cli.save_json(
        course_dir / "grammar_points.json",
        {"grammarPoints": bundle.grammar_points},
    )


def _validate_result_from_json(text: str, err_hint: str) -> ValidationResult:
    """Parse the ``validate --format json`` payload into a ValidationResult."""
    try:
        data = json.loads(text)
    except json.JSONDecodeError:
        return ValidationResult(
            ok=False,
            error_count=1,
            problems=[
                Problem(
                    level="error",
                    message=f"validate 无效输出: {err_hint}",
                    path="",
                )
            ],
        )
    problems = [
        Problem(level=p.get("level", "error"), message=p.get("message", ""), path=p.get("path", ""))
        for p in data.get("problems", [])
    ]
    return ValidationResult(
        ok=bool(data.get("ok", False)),
        error_count=int(data.get("errorCount", 0)),
        problems=problems,
    )


def _parse_lint_lines(text: str) -> list[Problem]:
    """Parse ``lint`` stdout lines (``ERROR: ...`` / ``WARNING: ...``)."""
    problems: list[Problem] = []
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("ERROR:"):
            problems.append(
                Problem(level="error", message=line[6:].strip(), path="")
            )
        elif line.startswith("WARNING:"):
            problems.append(
                Problem(level="warning", message=line[8:].strip(), path="")
            )
    return problems


def _validate_in_process(course_dir: Path) -> ValidationResult:
    """Run the CLI validator in-process, capturing its JSON stdout."""
    buf = io.StringIO()
    args = argparse.Namespace(course_dir=Path(course_dir), format="json")
    with contextlib.redirect_stdout(buf):
        course_cli.cmd_validate(args)
    return _validate_result_from_json(buf.getvalue(), buf.getvalue()[:200])


def _validate_via_subprocess(course_dir: Path) -> ValidationResult:
    """Run the CLI validator as a subprocess (isolation fallback)."""
    try:
        proc = subprocess.run(
            [
                sys.executable,
                str(Path(course_cli.__file__).resolve()),
                "--course-dir",
                str(course_dir),
                "validate",
                "--format",
                "json",
            ],
            capture_output=True,
            text=True,
            encoding="utf-8",
            timeout=_CLI_TIMEOUT_SECONDS,
        )
    except subprocess.TimeoutExpired:
        return ValidationResult(
            ok=False,
            error_count=1,
            problems=[
                Problem(
                    level="error",
                    message=f"validate 子进程超时（>{_CLI_TIMEOUT_SECONDS}s）",
                    path="",
                )
            ],
        )
    return _validate_result_from_json(proc.stdout, proc.stderr or proc.stdout)


def validate_course_dir(course_dir: Path) -> ValidationResult:
    """Validate a course directory and return structured problems.

    Fast path runs the same ``course_cli.cmd_validate`` code in-process
    (skipping interpreter startup on every save); any failure falls back to
    the subprocess, preserving the old isolation behaviour.
    """
    try:
        return _validate_in_process(course_dir)
    except Exception:  # noqa: BLE001 — fall back to the subprocess path
        return _validate_via_subprocess(course_dir)


def _lint_in_process(course_dir: Path) -> list[Problem]:
    """Run the CLI linter in-process, capturing its stdout."""
    buf = io.StringIO()
    args = argparse.Namespace(course_dir=Path(course_dir), strict=False)
    with contextlib.redirect_stdout(buf):
        course_cli.cmd_lint(args)
    return _parse_lint_lines(buf.getvalue())


def _lint_via_subprocess(course_dir: Path) -> list[Problem]:
    """Run the CLI linter as a subprocess (isolation fallback)."""
    try:
        proc = subprocess.run(
            [
                sys.executable,
                str(Path(course_cli.__file__).resolve()),
                "--course-dir",
                str(course_dir),
                "lint",
            ],
            capture_output=True,
            text=True,
            encoding="utf-8",
            timeout=_CLI_TIMEOUT_SECONDS,
        )
    except subprocess.TimeoutExpired:
        return [
            Problem(
                level="error",
                message=f"lint 子进程超时（>{_CLI_TIMEOUT_SECONDS}s）",
                path="",
            )
        ]
    return _parse_lint_lines(proc.stdout or "")


def lint_course_dir(course_dir: Path) -> list[Problem]:
    """Lint a course directory (in-process fast path, subprocess fallback)."""
    try:
        return _lint_in_process(course_dir)
    except Exception:  # noqa: BLE001 — fall back to the subprocess path
        return _lint_via_subprocess(course_dir)


def validate_lesson(
    lesson: dict[str, Any],
    vocab_ids: set[str],
    expression_ids: set[str],
    grammar_ids: set[str],
) -> list[Problem]:
    """Validate a single lesson dict in-process (used for AI-generated previews)."""
    raw: list[course_cli.Problem] = []
    course_cli._validate_lesson(lesson, vocab_ids, expression_ids, grammar_ids, raw)
    return [
        Problem(level=p.level, message=p.message, path=p.path or "")
        for p in raw
    ]


def _normalize_csv_row(row: dict[str, Any]) -> dict[str, str]:
    """Replace None values with empty strings for CSV round-trips."""
    return {k: "" if v is None else str(v) for k, v in row.items()}


def export_csv_rows(
    row_type: str, entries: list[dict[str, Any]]
) -> tuple[list[str], list[dict[str, str]]]:
    headers, rows = course_cli.build_csv_rows(row_type, entries)
    return headers, [_normalize_csv_row(r) for r in rows]


def import_csv_rows(
    row_type: str,
    existing_entries: list[dict[str, Any]],
    rows: list[dict[str, Any]],
    expression_ids: set[str],
) -> tuple[list[dict[str, Any]], list[Problem]]:
    normalized = [_normalize_csv_row(r) for r in rows]
    merged, raw_problems = course_cli.merge_csv_rows(
        row_type, existing_entries, normalized, expression_ids
    )
    problems = [
        Problem(level=p.level, message=p.message, path=p.path or "")
        for p in raw_problems
    ]
    return merged, problems


def read_csv_file(path: Path) -> list[dict[str, str]]:
    return course_cli._read_csv(path)


def write_csv_file(path: Path, headers: list[str], rows: list[dict[str, str]]) -> None:
    course_cli._write_csv(path, headers, rows)


def build_audio_manifest_rows(course_dir: Path) -> list[dict[str, str]]:
    return course_cli.build_audio_manifest(course_dir)
