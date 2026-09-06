"""V-02 resource.batch_polish skill (pure Python, no Qt).

Batch polish / completion for *selected* resource entries (vocab /
expressions): an LLM message builder asks the model to improve only a
closed-set whitelist of fields (``translation`` / ``pronunciation`` /
``pos``), and a closed-set reply parser drops anything out of scope. The
write is performed by the caller via batch ``FieldPatch`` (one per
(id, field)) + ``ApplyBatchPatchCommand`` (preview + confirm + undo);
this module never touches the adapter or Qt.

红线（experienceai.md §14.5.3）：
* 纯函数构造 LLM messages / 解析回复；无 Qt、不写树、不写盘、永不抛。
* 字段白名单封闭（``POLISH_FIELDS``）；``pos`` 值再走 POS 闭集归一。
* term / translation 原文只进 LLM prompt 与确认文案，不进 Context /
  Timeline / telemetry scope（§14.5.3）。
* 失败安全：LLM 非 JSON / 越界 id / 越界 field / 空 value -> 丢弃，永不抛。
"""
from __future__ import annotations

import json
from typing import Any, Iterable

from src.backend.experience.pos_constants import POS_TAGS, normalize_pos

ACTION_ID = "resource.batch_polish"

# Closed-set field whitelist the LLM may touch (id / term are immutable).
POLISH_FIELDS: tuple[str, ...] = ("translation", "pronunciation", "pos")

# Cap entries sent to the model (token safety) and per-value length.
MAX_ENTRIES = 40
MAX_VALUE_CHARS = 500


def _clean_fields(fields: Iterable[str] | None) -> list[str]:
    out: list[str] = []
    for f in (fields if fields is not None else POLISH_FIELDS):
        f = str(f).strip()
        if f in POLISH_FIELDS and f not in out:
            out.append(f)
    return out or list(POLISH_FIELDS)


def build_batch_polish_messages(
    entries: Iterable[dict[str, Any]],
    *,
    fields: Iterable[str] | None = None,
    language: str = "Turkish",
    source_language: str = "Chinese",
    max_entries: int = MAX_ENTRIES,
) -> list[dict[str, Any]]:
    """Build LLM messages for batch polish of the selected entries.

    ``entries`` are dicts with ``id`` / ``term`` / ``translation`` /
    ``pronunciation`` / ``pos`` / ``kind`` (kind ``vocab`` | ``expressions``).
    The model is instructed to return
    ``{"entries":[{"id":...,"field":...,"value":...}]}`` touching only the
    whitelisted ``fields``. Never raises.
    """
    try:
        wl = _clean_fields(fields)
    except Exception:
        wl = list(POLISH_FIELDS)
    payload: list[dict[str, Any]] = []
    try:
        cap = max(0, int(max_entries))
    except Exception:
        cap = MAX_ENTRIES
    try:
        for e in list(entries or [])[:cap]:
            if not isinstance(e, dict):
                continue
            rid = str(e.get("id") or "").strip()
            if not rid:
                continue
            payload.append(
                {
                    "id": rid,
                    "kind": str(e.get("kind") or "vocab"),
                    "term": str(e.get("term") or ""),
                    "translation": str(e.get("translation") or ""),
                    "pronunciation": str(e.get("pronunciation") or ""),
                    "pos": str(e.get("pos") or ""),
                }
            )
    except Exception:
        payload = []
    allowed = ", ".join(wl)
    field_clauses: list[str] = []
    if "translation" in wl:
        field_clauses.append("translation 给出准确自然的释义")
    if "pronunciation" in wl:
        field_clauses.append(
            "pronunciation 给出读音提示（音标或拼音式标注，留空则补全，已有明显错误才改）"
        )
    if "pos" in wl:
        field_clauses.append(
            "pos 只允许取 10 类闭集之一：" + ", ".join(POS_TAGS)
            + "（expressions 词条不要给 pos）"
        )
    prompt = (
        f"你是语言课程资源批量润色助手。目标语：{language}；释义语：{source_language}。\n"
        "下列选中词条需要批量补全/润色。只允许修改这些字段："
        f"{allowed}（**不要**改 id / term）。\n"
        "对每条词条：" + "；".join(field_clauses) + "。\n"
        "只返回 JSON 对象：{\"entries\":[{\"id\":\"...\",\"field\":\"...\",\"value\":\"...\"}]}，"
        "一条词条可输出多条（每字段一条）；无需修改的字段不要输出；不要输出 markdown。\n\n"
        f"{json.dumps({'entries': payload}, ensure_ascii=False)}"
    )
    return [
        {
            "role": "system",
            "content": (
                "You polish language-course resource entries. Output ONLY valid "
                "JSON, no prose, no markdown fences."
            ),
        },
        {"role": "user", "content": prompt},
    ]


def parse_batch_polish_reply(
    raw: Any,
    *,
    allowed_ids: Iterable[str],
    allowed_fields: Iterable[str],
) -> dict[tuple[str, str], str]:
    """Parse the LLM reply into a ``{(entry_id, field): value}`` map.

    Closed-set filtering: unknown id dropped, out-of-whitelist field dropped,
    empty value dropped, ``pos`` values normalized to the POS closed set
    (out-of-set dropped). Garbage input returns ``{}``. Never raises.
    """
    try:
        if not raw:
            return {}
        if isinstance(raw, dict):
            data = raw
        else:
            text = str(raw).strip()
            if text.startswith("```"):
                lines = [
                    ln
                    for ln in text.splitlines()
                    if not ln.strip().startswith("```")
                ]
                text = "\n".join(lines).strip()
            data = json.loads(text)
        entries = (data or {}).get("entries") or []
        if not isinstance(entries, list):
            return {}
        ids = {str(i) for i in (allowed_ids or [])}
        fields = {f for f in (str(x).strip() for x in (allowed_fields or [])) if f in POLISH_FIELDS}
        out: dict[tuple[str, str], str] = {}
        for e in entries:
            if not isinstance(e, dict):
                continue
            rid = str(e.get("id") or "").strip()
            field = str(e.get("field") or "").strip()
            value = e.get("value")
            if not isinstance(value, str):
                value = "" if value is None else str(value)
            value = value.strip()
            if not rid or rid not in ids:
                continue
            if field not in fields:
                continue
            if not value:
                continue
            if field == "pos":
                norm = normalize_pos(value)
                if norm is None:
                    continue
                value = norm
            if len(value) > MAX_VALUE_CHARS:
                value = value[:MAX_VALUE_CHARS]
            out[(rid, field)] = value
        return out
    except Exception:
        return {}


def run_batch_polish(
    config: Any,
    entries: Iterable[dict[str, Any]],
    *,
    language: str = "Turkish",
    source_language: str = "Chinese",
    fields: Iterable[str] | None = None,
) -> dict[tuple[str, str], str]:
    """Run the batch-polish LLM call; return ``{(entry_id, field): value}``.

    Never raises here — the ``AiRequestWorker`` surfaces errors via its
    ``error_occurred`` signal, and a network/parse failure degrades to an
    empty map so callers report a non-modal status message. Pure: no Qt,
    no tree writes.
    """
    try:
        from src.backend.ai import content_text, request_chat

        clean = [
            e
            for e in (entries or [])
            if isinstance(e, dict) and str(e.get("id") or "").strip()
        ]
        if not clean:
            return {}
        if fields is None:
            wl: list[str] = ["translation", "pronunciation"]
            if any(str(e.get("kind") or "") == "vocab" for e in clean):
                wl.append("pos")
        else:
            wl = _clean_fields(fields)
        messages = build_batch_polish_messages(
            clean,
            fields=wl,
            language=language,
            source_language=source_language,
        )
        body = request_chat(config, messages, temperature=0.2)
        raw: Any = body
        if isinstance(body, dict) and "entries" not in body:
            choices = (body or {}).get("choices") or []
            if choices:
                raw = content_text((choices[0].get("message") or {}).get("content"))
        allowed_ids = {str(e.get("id") or "").strip() for e in clean}
        return parse_batch_polish_reply(
            raw, allowed_ids=allowed_ids, allowed_fields=wl
        )
    except Exception:
        return {}
