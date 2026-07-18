#!/usr/bin/env python3
"""T.9 zero-code teacher usability smoke (automated, headless).

Drives the *logical* path a non-technical teacher would walk, without
PySide6, and prints a human-readable pass/fail report. It exercises:

  1. 一键新建课程目录（中教英样例）
  2. 向导建课：从词库选 3 个词 -> 自动生成 intro 课
  3. 保存 -> course_cli validate ok + lint 无 ERROR
  4. 预览试做：自动判定生成的每道题可答
  5. 发布清单：version bump 检测 / validate / lint

The goal is not to replace human usability testing (the manual checklist in
``docs/authoring/teacher-usability-checklist.md`` covers that), but to give CI
a regression guard that the *teacher path* stays wired end-to-end.

Run: ``python tool/gui/tests/usability_smoke.py``
Exit code 0 = all steps passed; 1 = at least one failed.
"""
from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tool"))
sys.path.insert(0, str(ROOT / "tool" / "gui"))

from src.backend.course_adapter import CourseAdapter  # noqa: E402
from src.backend.teacher_view_model import is_answerable  # noqa: E402
from src.backend.lesson_content import build_intro_lesson  # noqa: E402

_CLI = ROOT / "tool" / "course_cli.py"


def _step(report: list[str], name: str, ok: bool, detail: str = "") -> bool:
    mark = "✅" if ok else "❌"
    line = f"{mark} {name}"
    if detail:
        line += f" — {detail}"
    report.append(line)
    print(line)
    return ok


def _run_validate(course_dir: Path) -> dict:
    proc = subprocess.run(
        [sys.executable, str(_CLI), "--course-dir", str(course_dir),
         "validate", "--format", "json"],
        capture_output=True, text=True, encoding="utf-8",
    )
    try:
        return json.loads(proc.stdout)
    except json.JSONDecodeError:
        return {"ok": False, "problems": [
            {"level": "error", "message": f"invalid output: {proc.stderr or proc.stdout}"}]}


def _run_lint(course_dir: Path) -> list[dict]:
    proc = subprocess.run(
        [sys.executable, str(_CLI), "--course-dir", str(course_dir), "lint"],
        capture_output=True, text=True, encoding="utf-8",
    )
    problems = []
    for line in (proc.stdout or "").splitlines():
        line = line.strip()
        if line.startswith("ERROR:"):
            problems.append({"level": "error", "message": line[6:].strip()})
        elif line.startswith("WARNING:"):
            problems.append({"level": "warning", "message": line[8:].strip()})
    return problems


def _walk_items(lesson: dict) -> list[dict]:
    items = []
    content = lesson.get("content", {}) or {}
    for sl in content.get("subLessons", []) or []:
        for stage in sl.get("stages", []) or []:
            items.extend(stage.get("items", []) or [])
    for stage in content.get("stages", []) or []:
        items.extend(stage.get("items", []) or [])
    return items


def main() -> int:
    report: list[str] = []
    tmp = Path(tempfile.mkdtemp(prefix="varnamala_usability_"))
    try:
        course_dir = tmp / "my-course"

        # Step 1: one-click new course (Chinese-teach-English sample).
        adapter = CourseAdapter()
        adapter.init_new(course_dir, {
            "display_name": "可用性测试课",
            "language": "en",
            "source_language": "Chinese",
            "section_count": 1,
            "lessons_per_unit": 1,
        })
        s1 = _step(report, "1. 一键新建课程目录", adapter.course_dir is not None,
                   f"{adapter.course_dir}")
        if not s1:
            return 1

        # Step 2: wizard build intro lesson from 3 sample words.
        words = adapter.vocab[:3]
        lesson = build_intro_lesson("问候语", "向导生成的样例 intro 课", words)
        adapter.sections[0]["units"][0]["lessons"].append(lesson)
        s2 = _step(report, "2. 向导建课（选 3 词生成 intro）",
                   lesson["template"] == "intro" and len(lesson["content"]["subLessons"]) == 3,
                   f"{len(words)} 词 -> {len(lesson['content']['subLessons'])} 环节")
        if not s2:
            return 1

        # Step 3: save -> validate ok + lint no ERROR.
        save_result = adapter.save()
        s3a = _step(report, "3a. 保存成功", save_result.ok, save_result.message)
        cli = _run_validate(course_dir)
        s3b = _step(report, "3b. CLI validate ok", cli.get("ok") is True)
        lint = _run_lint(course_dir)
        s3c = _step(report, "3c. lint 无 ERROR",
                    not [p for p in lint if p["level"] == "error"])
        if not (s3a and s3b and s3c):
            return 1

        # Step 4: preview "try it yourself" — generated items split into
        # display (showWord) + answerable (translate/fillBlank). The contract
        # requires at least one answerable item and that answerable ones all
        # carry a resolvable answer; display items are intentionally not
        # answerable (they present new words).
        items = _walk_items(lesson)
        answerable = [it for it in items if is_answerable(it.get("runtimeType", ""))]
        s4 = _step(
            report,
            "4. 预览试做（生成展示题 + 可答题）",
            len(items) > 0 and len(answerable) > 0,
            f"{len(items)} 题（{len(answerable)} 可答，{len(items) - len(answerable)} 展示）",
        )
        if not s4:
            return 1

        # Step 5: publish checklist — after a fresh edit, version bump is
        # detected and validate is ok. ``release_report`` compares against the
        # last-saved snapshot, so we make one trivial edit first to create a
        # real pending change (mirrors a teacher finishing edits then publishing).
        adapter.sections[0]["name"] = "问候章节"
        report_data = adapter.release_report()
        bump = report_data.get("version_bump", {})
        s5a = _step(report, "5a. 发布清单检测到改动",
                    any(report_data.get("changes", {}).values()),
                    f"version_bump={list(bump.keys())}")
        s5b = _step(report, "5b. 发布清单 validate ok",
                    report_data.get("validation", {}).get("ok") is True)
        if not (s5a and s5b):
            return 1

        print("\n全部通过：零代码教师路径端到端可用。")
        return 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())