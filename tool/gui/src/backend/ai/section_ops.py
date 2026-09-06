"""Section-level ops: fill stubs/gaps, diff, splice, regenerate, transforms.

Extracted from ``ai_generator`` (M1 refactor).
"""
from __future__ import annotations

import copy
import json
from typing import Any, Callable

from src.backend.ai.client import chat_json, resolved_request_chat
from src.backend.ai.config import (
    SYSTEM_AUTHORING,
    SYSTEM_CORRECTION,
    SYSTEM_EDITING,
    AiApiConfig,
    AiCancelled,
    AiCourseSpec,
)
from src.backend.ai.parse import (
    content_text,
    extract_content,
    parse_completion,
    parse_json_obj,
)
from src.backend.ai.prompts import build_prompt, build_response_format
from src.backend.ai.resource_fix import (
    auto_fix_resources,
    iter_items,
    normalize_resources,
)
from src.backend.ai.validate_loop import generate_with_validate_loop
from src.backend.ai_pedagogy import pedagogy_prompt_block

# Local aliases so mechanically-split bodies keep working until fully renamed.
_extract_content = extract_content
_parse_json_obj = parse_json_obj

def needs_review_entries(section: dict[str, Any]) -> list[tuple[str, dict[str, Any]]]:
    """Return (bucket, entry) pairs that need a second-pass fill."""
    out: list[tuple[str, dict[str, Any]]] = []
    for key in ("words", "expressions"):
        for entry in section.get(key) or []:
            if not isinstance(entry, dict):
                continue
            tags = {str(t).lower() for t in (entry.get("tags") or [])}
            trans = (entry.get("translation") or "").strip()
            if "needs-review" in tags or "auto-fix" in tags or trans in ("", "[待补]"):
                out.append((key, entry))
    for entry in section.get("grammarPoints") or []:
        if not isinstance(entry, dict):
            continue
        tags = {str(t).lower() for t in (entry.get("tags") or [])}
        expl = (entry.get("explanation") or "").strip()
        if "needs-review" in tags or "auto-fix" in tags or not expl:
            out.append(("grammarPoints", entry))
    return out


def fill_needs_review_resources(
    config: AiApiConfig,
    section: dict[str, Any],
    *,
    language: str = "Turkish",
    source_language: str = "Chinese",
    timeout: float = 60.0,
    temperature: float = 0.2,
    cancel_check: Callable[[], bool] | None = None,
    usage_callback: Callable[[dict[str, int]], None] | None = None,
) -> dict[str, Any]:
    """Second-pass LLM fill for stub / needs-review resource entries.

    Default callers leave this off (extra tokens). When enabled, only entries
    tagged needs-review/auto-fix or carrying ``[待补]`` / empty glosses are
    sent. On any failure the original section is returned unchanged.
    """
    targets = needs_review_entries(section)
    if not targets:
        return section

    payload = []
    for key, entry in targets:
        payload.append(
            {
                "bucket": key,
                "id": entry.get("id", ""),
                "term": entry.get("term") or entry.get("title") or "",
                "translation": entry.get("translation") or "",
                "explanation": entry.get("explanation") or "",
                "title": entry.get("title") or "",
            }
        )
    prompt = (
        f"你是语言课程词条补全助手。目标语：{language}；释义语：{source_language}。\n"
        "下列条目缺少可靠释义或带有待审标记。请为每一项补全可教的 term/translation"
        "（grammarPoints 用 title/explanation）。\n"
        "只返回 JSON 对象：{\"entries\":[{\"id\":\"...\",\"term\":\"...\","
        "\"translation\":\"...\",\"title\":\"...\",\"explanation\":\"...\"}]}\n"
        "要求：不要改 id；translation/explanation 禁止空或「[待补]」；"
        "不要输出 markdown。\n\n"
        f"{json.dumps({'entries': payload}, ensure_ascii=False)}"
    )
    try:
        body = resolved_request_chat(
            config,
            [
                {
                    "role": "system",
                    "content": (
                        "You complete language-course glossary entries. "
                        "Output ONLY valid JSON, no prose, no markdown fences."
                    ),
                },
                {"role": "user", "content": prompt},
            ],
            temperature=temperature,
            response_format={"type": "json_object"},
            timeout=timeout,
            cancel_check=cancel_check,
            stream=False,
            usage_callback=usage_callback,
            model=config.select_model("json"),
        )
        content = _extract_content(body, strip=True)
        parsed = _parse_json_obj(content)
    except (ValueError, RuntimeError, AiCancelled, TypeError, KeyError):
        return section

    updates = parsed.get("entries") if isinstance(parsed, dict) else None
    if not isinstance(updates, list):
        return section

    by_id: dict[str, dict[str, Any]] = {}
    for item in updates:
        if isinstance(item, dict) and item.get("id"):
            by_id[str(item["id"])] = item

    for key, entry in targets:
        uid = str(entry.get("id") or "")
        patch = by_id.get(uid)
        if not patch:
            continue
        if key == "grammarPoints":
            title = (patch.get("title") or entry.get("title") or uid).strip()
            explanation = (patch.get("explanation") or patch.get("translation") or "").strip()
            if explanation and explanation != "[待补]":
                entry["title"] = title
                entry["explanation"] = explanation
                tags = [t for t in (entry.get("tags") or []) if str(t).lower() not in ("needs-review", "auto-fix")]
                entry["tags"] = tags
        else:
            term = (patch.get("term") or entry.get("term") or uid).strip()
            translation = (patch.get("translation") or "").strip()
            if translation and translation != "[待补]":
                entry["term"] = term
                entry["translation"] = translation
                tags = [t for t in (entry.get("tags") or []) if str(t).lower() not in ("needs-review", "auto-fix")]
                entry["tags"] = tags
    return section


def listening_gap_items(section: dict[str, Any]) -> list[tuple[dict, dict, str]]:
    """Yield ``(lesson, item, phase_id?)`` for listening items with a gap.

    Mirrors ``content_quality._score_audio_ready``: items whose ``runtimeType``
    is a listening type that lack audioAsset and/or transcript/text. An item
    with audio but no transcript (v4.39 K-17 ``missing_transcript`` kind) is
    also collected so ``fill_listening_gaps`` can fill just the transcript.
    ``phase_id`` is set when the item lives in a listeningPhase, else ``""``.
    """
    out: list[tuple[dict, dict, str]] = []

    def _is_listen(rt: str) -> bool:
        return rt in ("listenAndPick", "typeTheWord") or "listen" in rt.lower()

    for unit in section.get("units") or []:
        if not isinstance(unit, dict):
            continue
        for lesson in unit.get("lessons") or []:
            if not isinstance(lesson, dict):
                continue
            content = lesson.get("content") or {}
            if not isinstance(content, dict):
                continue
            for stage in content.get("stages") or []:
                if not isinstance(stage, dict):
                    continue
                for item in stage.get("items") or []:
                    if not isinstance(item, dict):
                        continue
                    if _is_listen(str(item.get("runtimeType") or "")):
                        if has_listening_gap(item):
                            out.append((lesson, item, ""))
            for phase in content.get("listeningPhases") or []:
                if not isinstance(phase, dict):
                    continue
                pid = str(phase.get("id") or "")
                for item in phase.get("items") or []:
                    if not isinstance(item, dict):
                        continue
                    if _is_listen(str(item.get("runtimeType") or "")) and has_listening_gap(item):
                        out.append((lesson, item, pid))
    return out


def has_audio(item: dict[str, Any]) -> bool:
    audio = item.get("audioAsset")
    transcript = item.get("transcript") or item.get("text")
    return (isinstance(audio, str) and audio.strip()) or (
        isinstance(transcript, str) and transcript.strip()
    )


def has_listening_gap(item: dict[str, Any]) -> bool:
    """v4.39 K-17: True when the listening item lacks audio and/or transcript.

    Strictly broader than the legacy ``not _has_audio`` (which required BOTH
    absent): an item with audio but no transcript is now also a gap so the fill
    path can complete just the transcript without clobbering existing audio.
    """
    audio = item.get("audioAsset")
    transcript = item.get("transcript") or item.get("text")
    has_audio = isinstance(audio, str) and audio.strip()
    has_transcript = isinstance(transcript, str) and transcript.strip()
    return not (has_audio and has_transcript)


def fill_listening_gaps(
    config: AiApiConfig,
    section: dict[str, Any],
    *,
    language: str = "Turkish",
    source_language: str = "Chinese",
    timeout: float = 60.0,
    temperature: float = 0.2,
    cancel_check: Callable[[], bool] | None = None,
    usage_callback: Callable[[dict[str, int]], None] | None = None,
) -> dict[str, Any]:
    """Second-pass LLM fill for listening items missing audio/transcript.

    Only items flagged by ``content_quality._score_audio_ready`` (no
    ``audioAsset`` and no ``transcript``/``text``) are sent. The model returns
    ``audioAsset`` (asset path or text-to-speak) + ``transcript`` per item id;
    ids are preserved and the patch is merged back. Empty listening phases are
    left to the lesson-level fill flow (not handled here). On any failure the
    original section is returned unchanged.
    """
    targets = listening_gap_items(section)
    if not targets:
        return section

    payload = [
        {
            "id": str(item.get("id") or ""),
            "runtimeType": str(item.get("runtimeType") or ""),
            "prompt": item.get("prompt") or item.get("sentence") or item.get("word") or "",
            "audioAsset": item.get("audioAsset") or "",
            "transcript": item.get("transcript") or item.get("text") or "",
        }
        for _lesson, item, _pid in targets
    ]
    prompt = (
        f"你是语言课程听力题补全助手。目标语：{language}；释义语：{source_language}。\n"
        "下列听力题缺少 audioAsset 与/或 transcript。请为每一项**补全缺失的字段**：\n"
        "- audioAsset：可朗读的文本（TTS 将读它，用目标语）\n"
        "- transcript：该题的文字内容（目标语）\n"
        "已有值（非空）的字段请原样保留、不要改动；只补缺失（空）的字段。\n"
        "只返回 JSON 对象：{\"entries\":[{\"id\":\"...\",\"audioAsset\":\"...\","
        "\"transcript\":\"...\"}]}\n"
        "要求：不要改 id / runtimeType；audioAsset 与 transcript 禁止空；"
        "不要输出 markdown。\n\n"
        f"{json.dumps({'entries': payload}, ensure_ascii=False)}"
    )
    try:
        body = resolved_request_chat(
            config,
            [
                {
                    "role": "system",
                    "content": (
                        "You complete audio assets for language-course listening "
                        "items. Output ONLY valid JSON, no prose, no markdown "
                        "fences."
                    ),
                },
                {"role": "user", "content": prompt},
            ],
            temperature=temperature,
            response_format={"type": "json_object"},
            timeout=timeout,
            cancel_check=cancel_check,
            stream=False,
            usage_callback=usage_callback,
            model=config.select_model("json"),
        )
        content = _extract_content(body, strip=True)
        parsed = _parse_json_obj(content)
    except (ValueError, RuntimeError, AiCancelled, TypeError, KeyError):
        return section

    updates = parsed.get("entries") if isinstance(parsed, dict) else None
    if not isinstance(updates, list):
        return section

    by_id: dict[str, dict[str, Any]] = {}
    for entry in updates:
        if isinstance(entry, dict) and entry.get("id"):
            by_id[str(entry["id"])] = entry

    for _lesson, item, _pid in targets:
        uid = str(item.get("id") or "")
        patch = by_id.get(uid)
        if not patch:
            continue
        audio = (patch.get("audioAsset") or "").strip()
        transcript = (patch.get("transcript") or "").strip()
        # v4.39 K-17: never overwrite an already-present field with model output —
        # only fill missing ones (audio-present/transcript-absent keeps its audio).
        existing_audio = item.get("audioAsset")
        existing_audio = existing_audio if isinstance(existing_audio, str) else ""
        if audio and not existing_audio.strip():
            item["audioAsset"] = audio
        existing_tr = item.get("transcript") or item.get("text")
        existing_tr = existing_tr if isinstance(existing_tr, str) else ""
        if transcript and not existing_tr.strip():
            item["transcript"] = transcript
    return section

def section_unit_ids(section: dict[str, Any]) -> set[str]:
    return {u.get("id") for u in (section.get("units") or []) if isinstance(u, dict) and u.get("id")}


def section_lesson_ids(section: dict[str, Any]) -> set[str]:
    ids: set[str] = set()
    for unit in section.get("units") or []:
        if not isinstance(unit, dict):
            continue
        for lesson in unit.get("lessons") or []:
            if isinstance(lesson, dict) and lesson.get("id"):
                ids.add(lesson["id"])
    return ids


def top_level_ids(section: dict[str, Any], key: str) -> set[str]:
    return {r.get("id") for r in (section.get(key) or []) if isinstance(r, dict) and r.get("id")}


def structural_diff(existing: dict[str, Any], parsed: dict[str, Any]) -> dict[str, set[str]]:
    """Compare id sets of an existing section vs an AI-edited one (B3).

    Returns a dict of *removed* ids only (before minus after) at the unit,
    lesson, word, expression and grammar-point levels. Additions and renames
    are not reported here — only deletions the dialog must confirm, since a
    silent drop of units/words by the model is the failure mode we guard
    against. An all-empty dict means no structural removals.
    """
    return {
        "removed_units": section_unit_ids(existing) - section_unit_ids(parsed),
        "removed_lessons": section_lesson_ids(existing) - section_lesson_ids(parsed),
        "removed_words": top_level_ids(existing, "words") - top_level_ids(parsed, "words"),
        "removed_expressions": top_level_ids(existing, "expressions")
        - top_level_ids(parsed, "expressions"),
        "removed_grammar": top_level_ids(existing, "grammarPoints")
        - top_level_ids(parsed, "grammarPoints"),
    }


def entries_by_id(section: dict[str, Any], key: str) -> dict[str, dict[str, Any]]:
    """Top-level resource entries keyed by id (e.g. words/expressions/grammarPoints)."""
    out: dict[str, dict[str, Any]] = {}
    for r in section.get(key) or []:
        if isinstance(r, dict) and r.get("id"):
            out[r["id"]] = r
    return out


def units_by_id(section: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {u.get("id"): u for u in (section.get("units") or []) if isinstance(u, dict) and u.get("id")}


def lessons_by_id(section: dict[str, Any]) -> dict[str, dict[str, Any]]:
    out: dict[str, dict[str, Any]] = {}
    for unit in section.get("units") or []:
        if not isinstance(unit, dict):
            continue
        for lesson in unit.get("lessons") or []:
            if isinstance(lesson, dict) and lesson.get("id"):
                out[lesson["id"]] = lesson
    return out


def entry_fingerprint(entry: dict[str, Any]) -> str:
    """Stable serialized form for deep-equality comparison (changed detection)."""
    return json.dumps(entry, sort_keys=True, ensure_ascii=False)


def full_section_diff(
    existing: dict[str, Any], generated: dict[str, Any]
) -> dict[str, dict[str, list[str]]]:
    """Full add/remove/change diff between two sections (P3.4).

    Returns ``{category: {"added": [...], "removed": [...], "changed": [...]}}``
    for categories ``units``/``lessons``/``words``/``expressions``/``grammar``.
    ``added`` = ids in generated but not existing; ``removed`` = ids in existing
    but not generated; ``changed`` = ids present in both whose serialized
    content differs. Lists are sorted for stable display.
    """
    spec: list[tuple[str, dict[str, dict], dict[str, dict]]] = [
        ("units", units_by_id(existing), units_by_id(generated)),
        ("lessons", lessons_by_id(existing), lessons_by_id(generated)),
        ("words", entries_by_id(existing, "words"), entries_by_id(generated, "words")),
        ("expressions", entries_by_id(existing, "expressions"), entries_by_id(generated, "expressions")),
        ("grammar", entries_by_id(existing, "grammarPoints"), entries_by_id(generated, "grammarPoints")),
    ]
    result: dict[str, dict[str, list[str]]] = {}
    for category, before, after in spec:
        before_ids = set(before)
        after_ids = set(after)
        added = sorted(after_ids - before_ids)
        removed = sorted(before_ids - after_ids)
        changed = sorted(
            bid
            for bid in (before_ids & after_ids)
            if entry_fingerprint(before[bid]) != entry_fingerprint(after[bid])
        )
        result[category] = {"added": added, "removed": removed, "changed": changed}
    return result


def build_local_regen_instruction(spec: AiCourseSpec, scope_label: str) -> str:
    """Pure helper: build a local-regeneration instruction from the spec.

    The teacher's edit intent is derived from ``spec.topic`` and
    ``spec.extra_instructions`` (the same prompt material used for full
    generation), scoped to the selected lesson/unit. Extracted as a pure
    function so it can be unit-tested without PySide6.
    """
    parts = [f"请在此课程主题下{scope_label}：保持 id 与题型不变，改进内容质量。"]
    if spec.topic:
        parts.append(f"课程主题：{spec.topic}")
    if spec.extra_instructions:
        parts.append(f"额外要求：{spec.extra_instructions}")
    return "\n".join(parts)


def find_lesson(section: dict[str, Any], lesson_id: str) -> tuple[dict | None, dict | None]:
    """Return (unit, lesson) for ``lesson_id`` in ``section``, or (None, None)."""
    for unit in section.get("units") or []:
        if not isinstance(unit, dict):
            continue
        for lesson in unit.get("lessons") or []:
            if isinstance(lesson, dict) and lesson.get("id") == lesson_id:
                return unit, lesson
    return None, None


def splice_lesson(
    existing_section: dict[str, Any], lesson_id: str, new_lesson: dict[str, Any]
) -> dict[str, Any]:
    """Return a deep-ish copy of ``existing_section`` with ``lesson_id``
    replaced by ``new_lesson`` (matched by id). If the id is not found, the
    new lesson is appended to the first unit. Other lessons/units are
    preserved verbatim.
    """
    import copy

    section = copy.deepcopy(existing_section)
    splice_lesson_in_place(section, lesson_id, new_lesson)
    return section


def splice_lesson_in_place(
    section: dict[str, Any], lesson_id: str, new_lesson: dict[str, Any]
) -> bool:
    """Replace the lesson with ``lesson_id`` inside ``section`` in place.

    Mutates ``section`` directly (no copy). Returns True if an existing
    lesson with that id was found and replaced, False if the new lesson was
    appended to the first unit instead. The caller is responsible for
    deep-copying ``section`` first if it needs to preserve the original.
    """
    new_lesson = dict(new_lesson)
    new_lesson["id"] = lesson_id
    units = section.get("units") or []
    for unit in units:
        lessons = unit.get("lessons") or []
        for i, lesson in enumerate(lessons):
            if isinstance(lesson, dict) and lesson.get("id") == lesson_id:
                lessons[i] = new_lesson
                return True
    first_unit = next((u for u in units if isinstance(u, dict)), None)
    if first_unit is None:
        first_unit = {"id": "u-ai", "lessons": []}
        section.setdefault("units", []).append(first_unit)
    first_unit.setdefault("lessons", []).append(new_lesson)
    return False


def regenerate_lesson_in_section(
    config: AiApiConfig,
    spec: AiCourseSpec,
    existing_section: dict[str, Any],
    lesson_id: str,
    instruction: str | None = None,
    timeout: float = 120.0,
    temperature: float = 0.5,
    cancel_check: Callable[[], bool] | None = None,
    on_chunk: Callable[[str], None] | None = None,
    usage_callback: Callable[[dict[str, int]], None] | None = None,
) -> dict[str, Any]:
    """Regenerate a single lesson in place and splice it back (C5).

    Only the targeted lesson is sent to the model via
    ``request_lesson_transform`` (which validates and preserves identity
    fields), so unchanged units/lessons cost no tokens. Returns the
    reassembled full section JSON.
    """
    import sys
    ai_gen = sys.modules.get("src.backend.ai_generator")
    if ai_gen is not None:
        patched = getattr(ai_gen, "regenerate_lesson_in_section", None)
        if patched is not None and patched is not regenerate_lesson_in_section:
            return patched(
                config,
                spec,
                existing_section,
                lesson_id,
                instruction=instruction,
                timeout=timeout,
                temperature=temperature,
                cancel_check=cancel_check,
                on_chunk=on_chunk,
                usage_callback=usage_callback,
            )

    _, lesson = find_lesson(existing_section, lesson_id)
    if lesson is None:
        raise ValueError(f"未找到课时「{lesson_id}」。")
    instr = instruction or build_local_regen_instruction(spec, "重写该课时")
    new_lesson = request_lesson_transform(
        config,
        lesson,
        instr,
        timeout=timeout,
        temperature=temperature,
        cancel_check=cancel_check,
        on_chunk=on_chunk,
        usage_callback=usage_callback,
    )
    return splice_lesson(existing_section, lesson_id, new_lesson)


def regenerate_unit_in_section(
    config: AiApiConfig,
    spec: AiCourseSpec,
    existing_section: dict[str, Any],
    unit_id: str,
    instruction: str | None = None,
    timeout: float = 120.0,
    temperature: float = 0.5,
    cancel_check: Callable[[], bool] | None = None,
    on_chunk: Callable[[str], None] | None = None,
    usage_callback: Callable[[dict[str, int]], None] | None = None,
) -> dict[str, Any]:
    """Regenerate every lesson in a unit in place and splice them back (C5).

    Iterates the unit's lessons, calling ``request_lesson_transform`` on each
    (reusing the already-validated single-lesson path and fine-grained token
    usage), then splices each result back. The section id and other units are
    untouched. ``cancel_check`` is honoured between lessons.
    """
    import sys
    ai_gen = sys.modules.get("src.backend.ai_generator")
    if ai_gen is not None:
        patched = getattr(ai_gen, "regenerate_unit_in_section", None)
        if patched is not None and patched is not regenerate_unit_in_section:
            return patched(
                config,
                spec,
                existing_section,
                unit_id,
                instruction=instruction,
                timeout=timeout,
                temperature=temperature,
                cancel_check=cancel_check,
                on_chunk=on_chunk,
                usage_callback=usage_callback,
            )

    unit = next(
        (u for u in (existing_section.get("units") or []) if isinstance(u, dict) and u.get("id") == unit_id),
        None,
    )
    if unit is None:
        raise ValueError(f"未找到单元「{unit_id}」。")
    instr = instruction or build_local_regen_instruction(spec, "重写该单元内的课时")
    # Deep-copy once and mutate in place: the old loop called _splice_lesson
    # (which deep-copies the whole section) per lesson, making unit regen
    # O(L * len(section)) in memory/time. (P1)
    import copy as _copy

    section = _copy.deepcopy(existing_section)
    target_unit = next(
        (u for u in (section.get("units") or []) if isinstance(u, dict) and u.get("id") == unit_id),
        None,
    )
    if target_unit is None:
        # Defensive: unit vanished during copy (shouldn't happen) — fall back.
        target_unit = next(
            (u for u in (existing_section.get("units") or [])
             if isinstance(u, dict) and u.get("id") == unit_id),
            None,
        )
        if target_unit is None:
            raise ValueError(f"未找到单元「{unit_id}」。")
    for lesson in list(target_unit.get("lessons") or []):
        if not isinstance(lesson, dict) or not lesson.get("id"):
            continue
        if cancel_check and cancel_check():
            raise AiCancelled("请求已取消。")
        new_lesson = request_lesson_transform(
            config,
            lesson,
            instr,
            timeout=timeout,
            temperature=temperature,
            cancel_check=cancel_check,
            on_chunk=on_chunk,
            usage_callback=usage_callback,
        )
        splice_lesson_in_place(section, lesson["id"], new_lesson)
    return section


# --- Teacher-view inline AI helpers ----------------------------------------


def allowed_interactions_block() -> str:
    from src.backend.lesson_content import ALLOWED_RUNTIME_TYPES, INTERACTION_LABELS

    lines = ["- 可用 interaction runtimeType："]
    for rt in ALLOWED_RUNTIME_TYPES:
        lines.append(f"  • {rt}（{INTERACTION_LABELS.get(rt, rt)}）")
    return "\n".join(lines)


def request_lesson_transform(
    config: AiApiConfig,
    lesson: dict[str, Any],
    instruction: str,
    timeout: float = 120.0,
    temperature: float = 0.5,
    cancel_check: Callable[[], bool] | None = None,
    on_chunk: Callable[[str], None] | None = None,
    usage_callback: Callable[[dict[str, int]], None] | None = None,
    max_retries: int = 1,
) -> dict[str, Any]:
    """Transform a single lesson in-place according to a teacher instruction.

    The returned lesson keeps the same ``id`` and ``template`` as the input
    unless the instruction explicitly asks to change the template. Content
    shape (subLessons / stages / listeningPhases / readingPassage) must remain
    valid for the template.

    Uses the shared validate loop: structural lesson errors are re-fed to the
    model up to ``max_retries`` times before raising.
    """
    from src.backend import api

    template = lesson.get("template", "legacy")
    pedagogy = pedagogy_prompt_block(level="A1", language="Turkish", template=template)
    prompt = (
        "你是一位语言课程编辑助手。请根据教师的指令改写下面这门课。\n\n"
        f"课程模板：{template}\n"
        f"课程 id（必须保留）：{lesson.get('id', '')}\n"
        f"课程名称：{lesson.get('name', '')}\n"
        f"课程描述：{lesson.get('description', '')}\n\n"
        f"{pedagogy}\n\n"
        "当前课程完整 JSON：\n"
        f"```json\n{json.dumps(lesson, ensure_ascii=False, indent=2)}\n```\n\n"
        "教师指令：\n"
        f"{instruction}\n\n"
        "要求：\n"
        "1. 只返回完整的课程 JSON，不要任何解释、markdown 代码块标记或额外文字。\n"
        "2. 必须保留顶层 id、name、template、prerequisiteLessonIds 字段。\n"
        "3. content 结构必须符合该模板的规范（intro/practice/review 用 subLessons；"
        "listening 用 listeningPhases；reading 用 readingPassage + stages；mastery 用 stages）。\n"
        f"{allowed_interactions_block()}\n"
        "5. 引用的 wordId / expressionId / grammarPointId 必须在课程现有资源中存在；"
        "如果没有合适资源，宁可留空也不要编造。\n"
    )

    messages = [
        {
            "role": "system",
            "content": SYSTEM_EDITING,
        },
        {"role": "user", "content": prompt},
    ]

    def _parse_lesson_body(body: Any) -> dict:
        if isinstance(body, str):
            body = json.loads(body)
        content = _extract_content(body)
        parsed = _parse_json_obj(content)
        if "content" not in parsed:
            raise ValueError("模型输出不是合法的课程 JSON（缺少 content）。")
        for key in ("id", "name", "template", "prerequisiteLessonIds"):
            if key in lesson:
                parsed[key] = lesson[key]
        return parsed

    def _lesson_validator(parsed: dict) -> list[dict]:
        problems = api.validate_lesson(parsed, set(), set(), set())
        return [p.to_dict() for p in problems if p.level == "error"]

    try:
        parsed = generate_with_validate_loop(
            config,
            messages,
            _lesson_validator,
            max_retries=max_retries,
            temperature=temperature,
            timeout=timeout,
            cancel_check=cancel_check,
            on_chunk=on_chunk,
            usage_callback=usage_callback,
            parse=_parse_lesson_body,
            model=config.select_model("json"),
        )
    except ValueError:
        raise

    errors = _lesson_validator(parsed)
    if errors:
        raise ValueError(
            "AI 返回的课程校验失败：\n"
            + "\n".join(e.get("message", str(e)) for e in errors[:5])
        )
    return parsed


def request_item_transform(
    config: AiApiConfig,
    item: dict[str, Any],
    instruction: str,
    vocab_ids: set[str] | None = None,
    expression_ids: set[str] | None = None,
    grammar_ids: set[str] | None = None,
    timeout: float = 120.0,
    temperature: float = 0.5,
    cancel_check: Callable[[], bool] | None = None,
    on_chunk: Callable[[str], None] | None = None,
    usage_callback: Callable[[dict[str, int]], None] | None = None,
) -> dict[str, Any]:
    """Transform a single interaction item in-place.

    Preserves the item ``id`` and ``runtimeType`` unless the instruction asks
    to switch type.
    """
    from src.backend.lesson_content import normalize_item

    rt = item.get("runtimeType", "")
    prompt = (
        "你是一位语言课程编辑助手。请根据教师的指令改写下面这道题目。\n\n"
        f"题目 id（必须保留）：{item.get('id', '')}\n"
        f"当前 runtimeType：{rt}\n"
        "当前题目 JSON：\n"
        f"```json\n{json.dumps(item, ensure_ascii=False, indent=2)}\n```\n\n"
        "教师指令：\n"
        f"{instruction}\n\n"
        "要求：\n"
        "1. 只返回完整的题目 JSON，不要任何解释、markdown 代码块标记或额外文字。\n"
        "2. 必须保留 id 字段；如未要求改题型，请保留 runtimeType。\n"
        f"{allowed_interactions_block()}\n"
        "4. 引用的 wordId / expressionId / grammarPointId 必须在可用资源中存在；"
        "没有则留空。\n"
    )

    messages = [
        {
            "role": "system",
            "content": SYSTEM_EDITING,
        },
        {"role": "user", "content": prompt},
    ]
    body = chat_json(
        config, messages, temperature=temperature, timeout=timeout,
        cancel_check=cancel_check, on_chunk=on_chunk,
        usage_callback=usage_callback,
        model=config.select_model("json"),
    )
    content = _extract_content(body)
    parsed = _parse_json_obj(content)

    # Preserve id and default runtimeType if missing.
    parsed["id"] = item.get("id", parsed.get("id", ""))
    if "runtimeType" not in parsed:
        parsed["runtimeType"] = rt

    # Normalize against the schema to fill missing fields and catch unknown types.
    try:
        parsed = normalize_item(parsed)
    except ValueError as exc:
        raise ValueError(f"AI 返回的题目格式不正确: {exc}") from exc

    # Reference check.
    wid = parsed.get("wordId")
    if wid and vocab_ids and wid not in vocab_ids:
        parsed["wordId"] = ""
    eid = parsed.get("expressionId")
    if eid and expression_ids and eid not in expression_ids:
        parsed["expressionId"] = ""
    gid = parsed.get("grammarPointId")
    if gid and grammar_ids and gid not in grammar_ids:
        parsed["grammarPointId"] = ""
    return parsed


def request_correction(
    config: AiApiConfig,
    prompt: str,
    timeout: float = 120.0,
    temperature: float = 0.2,
    cancel_check: Callable[[], bool] | None = None,
    on_chunk: Callable[[str], None] | None = None,
    usage_callback: Callable[[dict[str, int]], None] | None = None,
) -> dict[str, Any]:
    """Ask the model to correct a JSON node and return the parsed dict.

    The prompt is expected to contain the problematic JSON node and a list of
    validation problems. The model must return only a JSON object.
    """
    from src.backend.ai_fixer import extract_json_object

    messages = [
        {
            "role": "system",
            "content": SYSTEM_CORRECTION,
        },
        {"role": "user", "content": prompt},
    ]
    body = chat_json(
        config, messages, temperature=temperature, timeout=timeout,
        cancel_check=cancel_check, on_chunk=on_chunk,
        usage_callback=usage_callback,
        model=config.select_model("json"),
    )
    content = _extract_content(body)
    return extract_json_object(content)


# Back-compat aliases for external transitional imports
_needs_review_entries = needs_review_entries
_listening_gap_items = listening_gap_items
_has_audio = has_audio
_has_listening_gap = has_listening_gap
_splice_lesson_in_place = splice_lesson_in_place
_splice_lesson = splice_lesson
_find_lesson = find_lesson
_content_text = content_text
