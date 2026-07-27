"""Resource array normalization and rule-based auto-fix (pure, no network).

Extracted from ``ai_generator`` (M1 refactor). Public names replace former
``_normalize_resources`` / ``_auto_fix_resources`` (M1.d).
"""
from __future__ import annotations

from typing import Any

def normalize_resources(parsed: dict[str, Any]) -> None:
    """Ensure words/expressions/grammarPoints are lists (default empty)."""
    for key in ("words", "expressions", "grammarPoints"):
        val = parsed.get(key)
        if val is None:
            parsed[key] = []
        elif not isinstance(val, list):
            raise ValueError(f"顶层 '{key}' 必须是数组。")


def iter_items(lesson: dict[str, Any]):
    """Yield every interaction item dict inside a lesson's content."""
    content = lesson.get("content") or {}
    stages = content.get("stages") or []
    for stage in stages:
        for item in stage.get("items") or []:
            if isinstance(item, dict):
                yield item
    for sub in content.get("subLessons") or []:
        for stage in sub.get("stages") or []:
            for item in stage.get("items") or []:
                if isinstance(item, dict):
                    yield item
    for phase in content.get("listeningPhases") or []:
        for item in phase.get("items") or []:
            if isinstance(item, dict):
                yield item


def auto_fix_resources(parsed: dict[str, Any]) -> None:
    """Auto-fix dangling resource references by adding stub entries.

    When the AI model forgets to define a word/expression/grammar point in
    the top-level arrays while still referencing it from a lesson item, this
    function synthesizes a minimal stub entry so the section can be imported.
    The stub is populated best-effort from nearby item fields (context,
    expected, source, prompt); the author can refine it later in the editor.
    """
    words = parsed.setdefault("words", [])
    expressions = parsed.setdefault("expressions", [])
    grammar_points = parsed.setdefault("grammarPoints", [])

    word_ids = {w.get("id") for w in words if isinstance(w, dict)}
    expr_ids = {e.get("id") for e in expressions if isinstance(e, dict)}
    grammar_ids = {g.get("id") for g in grammar_points if isinstance(g, dict)}

    for unit in parsed.get("units") or []:
        if not isinstance(unit, dict):
            continue
        for lesson in unit.get("lessons") or []:
            if not isinstance(lesson, dict):
                continue
            for item in iter_items(lesson):
                rt = item.get("runtimeType")
                if rt == "showWord":
                    wid = item.get("wordId")
                    if wid and wid not in word_ids:
                        context = item.get("context") or ""
                        term = ""
                        translation = ""
                        if context:
                            parts = context.split("—", 1)
                            if len(parts) == 2:
                                term = parts[0].strip()
                                translation = parts[1].strip()
                            else:
                                term = context.strip()
                        # Fall back to nearby item fields before giving up,
                        # and never emit an empty translation (B4): a dirty
                        # "[待补]" placeholder flagged needs-review is safer
                        # than an entry the learner sees as a blank.
                        if not term:
                            term = (
                                item.get("expected")
                                or item.get("source")
                                or item.get("prompt")
                                or wid
                            )
                        if not translation:
                            translation = (
                                item.get("expectedAnswer")
                                or item.get("expected")
                                or item.get("source")
                                or "[待补]"
                            )
                        words.append(
                            {
                                "id": wid,
                                "term": term or wid,
                                "translation": translation,
                                "pronunciation": None,
                                "audioAsset": None,
                                "tags": ["auto-fix", "needs-review"],
                            }
                        )
                        word_ids.add(wid)
                eid = item.get("expressionId")
                if eid and eid not in expr_ids:
                    prompt = item.get("prompt") or item.get("source") or ""
                    expected = item.get("expected") or item.get("expectedAnswer") or ""
                    expressions.append(
                        {
                            "id": eid,
                            "term": expected or eid,
                            "translation": prompt or "[待补]",
                            "pronunciation": None,
                            "audioAsset": None,
                            "tags": ["auto-fix", "needs-review"],
                        }
                    )
                    expr_ids.add(eid)
                gid = item.get("grammarPointId")
                if gid and gid not in grammar_ids:
                    grammar_points.append(
                        {
                            "id": gid,
                            "title": gid,
                            "explanation": "",
                            "exampleExpressionIds": [],
                            "exampleSentenceIds": [],
                            "practiceItems": [],
                        }
                    )
                    grammar_ids.add(gid)


def check_resource_self_consistency(parsed: dict[str, Any]) -> None:
    """Verify every wordId/expressionId/grammarPointId is defined in the
    top-level resource arrays. Raises ValueError listing all dangling refs.
    """
    word_ids = {w.get("id") for w in parsed.get("words") or [] if isinstance(w, dict)}
    expr_ids = {e.get("id") for e in parsed.get("expressions") or [] if isinstance(e, dict)}
    grammar_ids = {
        g.get("id") for g in parsed.get("grammarPoints") or [] if isinstance(g, dict)
    }

    missing: list[str] = []
    for unit in parsed.get("units") or []:
        if not isinstance(unit, dict):
            continue
        for lesson in unit.get("lessons") or []:
            if not isinstance(lesson, dict):
                continue
            for item in iter_items(lesson):
                lid = lesson.get("id", "?")
                rt = item.get("runtimeType")
                if rt == "showWord":
                    wid = item.get("wordId")
                    if wid and wid not in word_ids:
                        missing.append(f"lesson {lid}: showWord 引用了未定义的 wordId「{wid}」")
                eid = item.get("expressionId")
                if eid and eid not in expr_ids:
                    missing.append(f"lesson {lid}: 引用了未定义的 expressionId「{eid}」")
                gid = item.get("grammarPointId")
                if gid and gid not in grammar_ids:
                    missing.append(f"lesson {lid}: 引用了未定义的 grammarPointId「{gid}」")
    if missing:
        raise ValueError(
            "资源自洽校验失败（引用的资源 id 未在顶层 words/expressions/grammarPoints 中定义）:\n"
            + "\n".join(missing[:20])
        )


# Back-compat aliases for in-package / transitional imports.
_normalize_resources = normalize_resources
_iter_items = iter_items
_auto_fix_resources = auto_fix_resources
_check_resource_self_consistency = check_resource_self_consistency
