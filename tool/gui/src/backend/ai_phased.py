"""Phased (outline → per-lesson) course generation (aiEnhance P2-7..10).

Phase A produces a locked outline (unit/lesson ids + templates + target word
ids). Phase B fills each lesson's content and splices it into a section shell
built from the outline, reusing ``_splice_lesson_in_place`` so ids never drift.

Pure helpers are free of Qt. Network calls go through ``ai_generator``.
"""
from __future__ import annotations

import copy
import json
from typing import Any, Callable

from src.backend.ai_generator import (
    SYSTEM_AUTHORING,
    AiApiConfig,
    AiCancelled,
    AiCourseSpec,
    _splice_lesson_in_place,
    generate_with_validate_loop,
    request_course_with_retry,
    request_lesson_transform,
)
from src.backend.ai_pedagogy import pedagogy_prompt_block


def build_outline_prompt(spec: AiCourseSpec) -> str:
    """User prompt for Phase A: structure only, no full item JSON."""
    pedagogy = pedagogy_prompt_block(
        level=spec.level,
        language=spec.language,
        template=spec.template,
    )
    lines = [
        "请为语言课程生成【大纲 JSON】（只要结构，不要写完整题目 content）。",
        "",
        f"目标语言：{spec.language}",
        f"提示语言：{spec.source_language}",
        f"主题：{spec.topic or '（未指定）'}",
        f"级别：{spec.level}",
        f"单元数：{spec.unit_count}",
        f"每单元课时：{spec.lessons_per_unit}",
        f"默认 template：{spec.template}",
        "",
        pedagogy,
        "",
        "输出 JSON 形状（严格）：",
        "{",
        '  "id": "section-kebab-id",',
        '  "name": "章节中文名",',
        '  "description": "一句话说明",',
        '  "words": [{"id":"w-...","term":"...","translation":"...","tags":[]}],',
        '  "expressions": [],',
        '  "grammarPoints": [],',
        '  "units": [',
        "    {",
        '      "id": "u1", "name": "...",',
        '      "lessons": [',
        '        {"id":"u1-l1","name":"...","template":"intro",',
        '         "targetWordIds":["w-..."], "targetExpressionIds":[]}',
        "      ]",
        "    }",
        "  ]",
        "}",
        "",
        "硬性要求：",
        "1. 先 words/expressions/grammarPoints，再 units。",
        "2. 每个 lesson 必须有唯一 id 与 template（intro/practice/review/listening/reading/mastery）。",
        "3. targetWordIds 只能引用本大纲 words[].id；不要在 lesson 里写 content。",
        f"4. 恰好 {spec.unit_count} 个 unit，每 unit 约 {spec.lessons_per_unit} 课。",
        "5. 只返回 JSON，不要 markdown 代码块或解释。",
    ]
    if spec.design_brief.strip():
        lines.extend(["", "## 设计意图", spec.design_brief.strip()])
    if spec.extra_instructions.strip():
        lines.extend(["", "## 额外要求", spec.extra_instructions.strip()])
    if spec.resource_pool:
        lines.append("")
        lines.append("## Grounded 资源池（优先使用；池外新词必须完整字段 + tags 含 new）")
        # Keep prompt short: only id/term/translation
        slim = []
        for r in spec.resource_pool[:80]:
            if isinstance(r, dict) and r.get("id"):
                slim.append(
                    {
                        "id": r.get("id"),
                        "term": r.get("term"),
                        "translation": r.get("translation"),
                        "_kind": r.get("_kind"),
                    }
                )
        lines.append(json.dumps(slim, ensure_ascii=False))
    return "\n".join(lines)


def validate_outline(outline: dict[str, Any]) -> list[str]:
    """Return human-readable errors; empty list means outline is usable."""
    errors: list[str] = []
    if not isinstance(outline, dict):
        return ["大纲不是 JSON 对象"]
    if not outline.get("id"):
        errors.append("大纲缺少 section id")
    words = outline.get("words") or []
    if not isinstance(words, list):
        errors.append("words 必须是数组")
        word_ids: set[str] = set()
    else:
        word_ids = {
            str(w.get("id"))
            for w in words
            if isinstance(w, dict) and w.get("id")
        }
    units = outline.get("units") or []
    if not isinstance(units, list) or not units:
        errors.append("大纲至少需要一个 unit")
        return errors
    lesson_ids: set[str] = set()
    for ui, unit in enumerate(units):
        if not isinstance(unit, dict):
            errors.append(f"units[{ui}] 不是对象")
            continue
        if not unit.get("id"):
            errors.append(f"units[{ui}] 缺少 id")
        for li, lesson in enumerate(unit.get("lessons") or []):
            if not isinstance(lesson, dict):
                errors.append(f"units[{ui}].lessons[{li}] 不是对象")
                continue
            lid = lesson.get("id")
            if not lid:
                errors.append(f"units[{ui}].lessons[{li}] 缺少 id")
            elif lid in lesson_ids:
                errors.append(f"重复 lesson id：{lid}")
            else:
                lesson_ids.add(str(lid))
            tpl = lesson.get("template")
            if not tpl:
                errors.append(f"lesson {lid or li} 缺少 template")
            for wid in lesson.get("targetWordIds") or []:
                if wid and str(wid) not in word_ids:
                    errors.append(f"lesson {lid}: targetWordIds 引用未知词 {wid}")
    if not lesson_ids:
        errors.append("大纲没有任何 lesson")
    return errors


def outline_to_section_shell(outline: dict[str, Any]) -> dict[str, Any]:
    """Build a section with empty lesson content shells from a validated outline.

    Lesson content is a minimal valid-ish placeholder; Phase B overwrites each
    lesson via splice. Ids and templates are locked from the outline.
    """
    section: dict[str, Any] = {
        "id": outline.get("id") or "ai-phased",
        "name": outline.get("name") or "Phased section",
        "description": outline.get("description") or "",
        "words": copy.deepcopy(outline.get("words") or []),
        "expressions": copy.deepcopy(outline.get("expressions") or []),
        "grammarPoints": copy.deepcopy(outline.get("grammarPoints") or []),
        "units": [],
    }
    for unit in outline.get("units") or []:
        if not isinstance(unit, dict):
            continue
        new_unit: dict[str, Any] = {
            "id": unit.get("id"),
            "name": unit.get("name") or unit.get("id"),
            "lessons": [],
        }
        for lesson in unit.get("lessons") or []:
            if not isinstance(lesson, dict) or not lesson.get("id"):
                continue
            template = str(lesson.get("template") or "intro")
            shell_lesson = {
                "id": lesson["id"],
                "name": lesson.get("name") or lesson["id"],
                "template": template,
                "description": lesson.get("description") or "",
                "prerequisiteLessonIds": list(lesson.get("prerequisiteLessonIds") or []),
                "content": _empty_content_for_template(template),
            }
            new_unit["lessons"].append(shell_lesson)
        section["units"].append(new_unit)
    return section


def _empty_content_for_template(template: str) -> dict[str, Any]:
    if template == "listening":
        return {
            "listeningPhases": [
                {"id": "lp-placeholder", "name": "TBD", "type": "wordPairing", "items": []}
            ]
        }
    if template == "reading":
        return {
            "readingPassage": {"title": "TBD", "paragraphs": ["…"]},
            "stages": [{"id": "st-placeholder", "name": "Q", "items": []}],
        }
    if template == "mastery":
        return {"stages": [{"id": "st-placeholder", "name": "Quiz", "items": []}]}
    return {
        "subLessons": [
            {
                "id": "sl-placeholder",
                "name": "TBD",
                "stages": [{"id": "st-placeholder", "name": "TBD", "items": []}],
            }
        ]
    }


def iter_outline_lessons(outline: dict[str, Any]) -> list[tuple[str, dict[str, Any]]]:
    """Return (unit_id, lesson_outline) pairs in order."""
    out: list[tuple[str, dict[str, Any]]] = []
    for unit in outline.get("units") or []:
        if not isinstance(unit, dict):
            continue
        uid = str(unit.get("id") or "")
        for lesson in unit.get("lessons") or []:
            if isinstance(lesson, dict) and lesson.get("id"):
                out.append((uid, lesson))
    return out


def build_lesson_fill_instruction(
    outline: dict[str, Any],
    lesson_outline: dict[str, Any],
    *,
    level: str = "A1",
    language: str = "Turkish",
) -> str:
    """Instruction for ``request_lesson_transform`` on a shell lesson."""
    targets = lesson_outline.get("targetWordIds") or []
    word_map = {
        str(w.get("id")): w
        for w in (outline.get("words") or [])
        if isinstance(w, dict) and w.get("id")
    }
    target_lines = []
    for wid in targets:
        w = word_map.get(str(wid))
        if w:
            target_lines.append(
                f"- {wid}: {w.get('term')} = {w.get('translation')}"
            )
        else:
            target_lines.append(f"- {wid}")
    pedagogy = pedagogy_prompt_block(
        level=level,
        language=language,
        template=str(lesson_outline.get("template") or "intro"),
    )
    parts = [
        "根据大纲填充本课完整 content，生成可教的练习题。",
        f"template 必须保持为：{lesson_outline.get('template')}",
        f"lesson id 必须保持为：{lesson_outline.get('id')}",
        pedagogy,
        "本课目标词：",
        *(target_lines or ["（无特定词，用章节主题合理填充）"]),
        "要求：",
        "1. 不要改 id / template / prerequisiteLessonIds。",
        "2. 题型符合 template；intro 先 showWord 再轻量练习。",
        "3. 目标词至少在一道非 showWord 题中复现。",
        "4. 选择题 4 选项不重复；correctIndex 合法。",
        "5. 只返回完整 lesson JSON。",
    ]
    return "\n".join(parts)


def request_outline(
    config: AiApiConfig,
    spec: AiCourseSpec,
    *,
    timeout: float = 120.0,
    temperature: float = 0.3,
    max_retries: int = 1,
    cancel_check: Callable[[], bool] | None = None,
    on_chunk: Callable[[str], None] | None = None,
    usage_callback: Callable[[dict[str, int]], None] | None = None,
) -> dict[str, Any]:
    """Phase A: generate and lightly validate outline JSON."""
    messages = [
        {"role": "system", "content": SYSTEM_AUTHORING},
        {"role": "user", "content": build_outline_prompt(spec)},
    ]

    def _validator(obj: dict) -> list[str]:
        return validate_outline(obj)

    outline = generate_with_validate_loop(
        config,
        messages,
        _validator,
        max_retries=max_retries,
        temperature=temperature,
        timeout=timeout,
        cancel_check=cancel_check,
        on_chunk=on_chunk,
        usage_callback=usage_callback,
        model=config.select_model("json"),
    )
    errs = validate_outline(outline)
    if errs:
        raise ValueError("大纲仍无效：" + "；".join(errs[:8]))
    return outline


def fill_lessons_from_outline(
    config: AiApiConfig,
    spec: AiCourseSpec,
    outline: dict[str, Any],
    *,
    timeout: float = 120.0,
    temperature: float = 0.45,
    cancel_check: Callable[[], bool] | None = None,
    on_chunk: Callable[[str], None] | None = None,
    usage_callback: Callable[[dict[str, int]], None] | None = None,
    on_lesson_done: Callable[[str, int, int], None] | None = None,
    max_parallel: int = 1,
) -> dict[str, Any]:
    """Phase B: shell + per-lesson transform + splice (cancel-aware).

    When ``max_parallel`` > 1, lesson transforms run in a thread pool and are
    spliced on the calling thread in completion order (U4-1). Splice stays
    single-threaded so section dict mutation is race-free. ``on_chunk`` is only
    used in sequential mode (streaming concurrent JSON is noisy).
    """
    errs = validate_outline(outline)
    if errs:
        raise ValueError("大纲无效：" + "；".join(errs[:8]))
    section = outline_to_section_shell(outline)
    lessons = list(iter_outline_lessons(outline))
    total = len(lessons)
    parallel = max(1, min(8, int(max_parallel or 1)))

    def _find_shell(lid: str) -> dict[str, Any] | None:
        for unit in section.get("units") or []:
            for les in unit.get("lessons") or []:
                if isinstance(les, dict) and les.get("id") == lid:
                    return les
        return None

    def _fill_one(lesson_ol: dict[str, Any]) -> tuple[str, dict[str, Any] | None]:
        lid = str(lesson_ol["id"])
        shell = _find_shell(lid)
        if shell is None:
            return lid, None
        instr = build_lesson_fill_instruction(
            outline,
            lesson_ol,
            level=spec.level,
            language=spec.language,
        )
        try:
            new_lesson = request_lesson_transform(
                config,
                shell,
                instr,
                timeout=timeout,
                temperature=temperature,
                cancel_check=cancel_check,
                on_chunk=on_chunk if parallel == 1 else None,
                usage_callback=usage_callback,
                max_retries=1,
            )
        except AiCancelled:
            raise
        except Exception:
            return lid, None
        new_lesson["id"] = lid
        new_lesson["template"] = lesson_ol.get("template") or new_lesson.get("template")
        if lesson_ol.get("name"):
            new_lesson["name"] = lesson_ol["name"]
        return lid, new_lesson

    if parallel == 1:
        for idx, (_uid, lesson_ol) in enumerate(lessons):
            if cancel_check and cancel_check():
                raise AiCancelled("请求已取消。")
            lid, new_lesson = _fill_one(lesson_ol)
            if new_lesson is not None:
                _splice_lesson_in_place(section, lid, new_lesson)
            if on_lesson_done:
                on_lesson_done(lid, idx + 1, total)
        return section

    # Parallel path: workers only produce lesson dicts; splice here.
    import threading
    from concurrent.futures import ThreadPoolExecutor, as_completed

    done_count = 0
    lock = threading.Lock()
    with ThreadPoolExecutor(max_workers=parallel) as pool:
        futures = {
            pool.submit(_fill_one, lesson_ol): lesson_ol
            for _uid, lesson_ol in lessons
        }
        for fut in as_completed(futures):
            if cancel_check and cancel_check():
                for f in futures:
                    f.cancel()
                raise AiCancelled("请求已取消。")
            try:
                lid, new_lesson = fut.result()
            except AiCancelled:
                raise
            except Exception:
                lid = str(futures[fut].get("id") or "")
                new_lesson = None
            if new_lesson is not None:
                _splice_lesson_in_place(section, lid, new_lesson)
            with lock:
                done_count += 1
                cur = done_count
            if on_lesson_done:
                on_lesson_done(lid, cur, total)
    return section


def request_course_phased(
    config: AiApiConfig,
    spec: AiCourseSpec,
    validator=None,
    *,
    timeout: float = 120.0,
    max_retries: int = 1,
    temperature: float = 0.4,
    cancel_check: Callable[[], bool] | None = None,
    on_chunk: Callable[[str], None] | None = None,
    usage_callback: Callable[[dict[str, int]], None] | None = None,
    on_progress: Callable[[str], None] | None = None,
    fill_needs_review: bool = False,
) -> dict[str, Any]:
    """Full phased path: outline → fill lessons → optional section validate loop.

    When ``validator`` is provided and reports errors after assembly, a single
    section-level correction pass is *not* re-run here (that would re-expand
    tokens); callers should use Review AI fix. Optional ``fill_needs_review``
    uses the same helper as the fast path.
    """
    def _progress(msg: str) -> None:
        if on_progress:
            on_progress(msg)

    _progress("outline")
    outline = request_outline(
        config,
        spec,
        timeout=timeout,
        temperature=min(temperature, 0.35),
        max_retries=max_retries,
        cancel_check=cancel_check,
        on_chunk=on_chunk,
        usage_callback=usage_callback,
    )
    _progress("fill_lessons")
    section = fill_lessons_from_outline(
        config,
        spec,
        outline,
        timeout=timeout,
        temperature=temperature,
        cancel_check=cancel_check,
        on_chunk=on_chunk,
        usage_callback=usage_callback,
        on_lesson_done=(
            (lambda lid, i, n: _progress(f"lesson:{lid}:{i}/{n}"))
            if on_progress
            else None
        ),
    )
    if fill_needs_review:
        from src.backend.ai_generator import fill_needs_review_resources

        _progress("fill_needs_review")
        section = fill_needs_review_resources(
            config,
            section,
            language=spec.language,
            source_language=spec.source_language,
            timeout=min(timeout, 60.0),
            cancel_check=cancel_check,
            usage_callback=usage_callback,
        )
    if validator is not None:
        problems = list(validator(section) or [])
        # Soft: only annotate via progress; do not auto re-generate whole section.
        err_n = sum(
            1
            for p in problems
            if not isinstance(p, dict) or p.get("level", "error") == "error"
        )
        if err_n:
            _progress(f"validate_errors:{err_n}")
    _progress("done")
    return section


def request_course(
    config: AiApiConfig,
    spec: AiCourseSpec,
    validator=None,
    *,
    mode: str = "fast",
    timeout: float = 120.0,
    max_retries: int = 1,
    temperature: float = 0.4,
    cancel_check: Callable[[], bool] | None = None,
    on_chunk: Callable[[str], None] | None = None,
    usage_callback: Callable[[dict[str, int]], None] | None = None,
    on_progress: Callable[[str], None] | None = None,
    fill_needs_review: bool = False,
) -> dict[str, Any]:
    """Dispatch fast (single-shot) vs phased generation (P2-10)."""
    if mode == "phased" or mode == "refine":
        return request_course_phased(
            config,
            spec,
            validator,
            timeout=timeout,
            max_retries=max_retries,
            temperature=temperature,
            cancel_check=cancel_check,
            on_chunk=on_chunk,
            usage_callback=usage_callback,
            on_progress=on_progress,
            fill_needs_review=fill_needs_review,
        )
    # Fast path requires a validator for retry loop; provide no-op if missing.
    def _noop(_s: dict) -> list:
        return []

    return request_course_with_retry(
        config,
        spec,
        validator if validator is not None else _noop,
        timeout=timeout,
        max_retries=max_retries if validator is not None else 0,
        temperature=temperature,
        cancel_check=cancel_check,
        on_chunk=on_chunk,
        usage_callback=usage_callback,
        fill_needs_review=fill_needs_review,
    )
