"""K-21 resource.align_pos_tags skill (pure Python, no Qt).

Local detector for POS (part-of-speech) misalignment across the vocab pool,
plus an LLM message builder + reply parser that propose a single closed-set
POS tag per misaligned word. The write is performed by the caller via batch
``FieldPatch`` (one per word) + ``ApplyBatchPatchCommand`` (preview + confirm
+ undo); this module never touches the adapter or Qt.

红线（experienceai.md §14.5.3）：
* 纯函数检测 / 构造 LLM messages / 解析回复；无 Qt、不写树、不写盘。
* POS 闭集见 :mod:`pos_constants`；越界 / 缺失 / 冲突归一为状态，永不抛。
* Context / Timeline scope 闭集（count / word_id 列表）—— term / translation /
  原文一律不进 scope（§14.5.3）；term 仅用于确认文案，不进遥测。
* 失败安全：LLM 非 JSON / 越界 / 缺字段 -> 丢弃，永不抛（§14.5.2）。
"""
from __future__ import annotations

import json
from typing import Any

from src.backend.experience.pos_constants import POS_TAG_SET, POS_TAGS, normalize_pos

ACTION_ID = "resource.align_pos_tags"


def _word_pos_tags(word: dict[str, Any]) -> list[str]:
    """POS-like tags already present in a word's ``tags`` list (closed-set)."""
    tags = word.get("tags") or []
    if not isinstance(tags, list):
        return []
    out: list[str] = []
    for t in tags:
        p = normalize_pos(t)
        if p is not None and p not in out:
            out.append(p)
    return out


def evaluate_pos_alignment(adapter: Any) -> dict[str, Any]:
    """Detect misaligned POS across the vocab pool; never raises.

    Returns a closed-shape dict::

        {
          "count": int,
          "misaligned": [
            {"word_id": str, "current_pos": str | None, "issue": str,
             "tag_pos": list[str]}
          ],
        }

    ``issue`` ∈ {"missing","invalid","conflict"}:
    * ``missing``  — ``pos`` unset and no POS-like tag in ``tags``.
    * ``invalid``  — ``pos`` set but not a closed-set member.
    * ``conflict`` — ``pos`` set AND ``tags`` carries a different POS-like tag
      (or multiple POS-like tags in ``tags``).

    ``term`` is intentionally omitted from the closed-shape return (§14.5.3);
    callers needing it for a confirmation dialog read the live word dict.
    """
    out: list[dict[str, Any]] = []
    try:
        vocab = list(getattr(adapter, "vocab", []) or [])
        for w in vocab:
            try:
                wid = str(w.get("id") or "")
                if not wid:
                    continue
                current = normalize_pos(w.get("pos"))
                tag_pos = _word_pos_tags(w)
                raw_pos = w.get("pos")
                issue = ""
                # invalid (explicitly set but out-of-set) takes priority over
                # missing so a bogus ``pos`` is reported as invalid, not missing.
                if raw_pos is not None and current is None:
                    issue = "invalid"
                elif current is None and not tag_pos:
                    issue = "missing"
                elif current is not None and tag_pos and (
                    len(tag_pos) > 1 or tag_pos[0] != current
                ):
                    issue = "conflict"
                if issue:
                    out.append(
                        {
                            "word_id": wid,
                            "current_pos": current,
                            "issue": issue,
                            "tag_pos": list(tag_pos),
                        }
                    )
            except Exception:
                continue
    except Exception:
        return {"count": 0, "misaligned": []}
    return {"count": len(out), "misaligned": out}


def build_pos_alignment_messages(
    config: Any,
    adapter: Any,
    *,
    language: str = "Turkish",
    source_language: str = "Chinese",
    temperature: float = 0.2,
) -> tuple[list[dict[str, Any]], dict[str, str]]:
    """Build LLM messages for POS alignment + the {word_id: term} lookup map.

    Returns ``(messages, terms)`` where ``terms`` maps word_id -> term for the
    confirmation dialog (kept client-side; never sent to telemetry). The LLM
    is asked to return ``{"entries":[{"id":...,"pos":...}]}`` with ``pos`` from
    the closed set. Words already healthy are skipped.
    """
    report = evaluate_pos_alignment(adapter)
    misaligned = report["misaligned"]
    terms: dict[str, str] = {}
    payload: list[dict[str, Any]] = []
    for item in misaligned:
        wid = item["word_id"]
        # Re-read the live word for the term (confirmation UI only).
        term = ""
        try:
            for w in getattr(adapter, "vocab", []) or []:
                if str(w.get("id") or "") == wid:
                    term = str(w.get("term") or "")
                    break
        except Exception:
            term = ""
        terms[wid] = term
        payload.append(
            {
                "id": wid,
                "term": term,
                "current_pos": item["current_pos"] or "",
                "tag_pos": item["tag_pos"],
                "issue": item["issue"],
            }
        )
    allowed = ", ".join(POS_TAGS)
    prompt = (
        f"你是语言课程词性（POS）标注助手。目标语：{language}；释义语：{source_language}。\n"
        "下列词条的词性缺失/无效/冲突，请为每一项给出**单一**词性标签。\n"
        f"允许的 POS 闭集：{allowed}。\n"
        "只返回 JSON 对象：{\"entries\":[{\"id\":\"...\",\"pos\":\"...\"}]}，"
        "其中 pos 必须是上述闭集之一；不要改 id；不要输出 markdown。\n\n"
        f"{json.dumps({'entries': payload}, ensure_ascii=False)}"
    )
    messages = [
        {
            "role": "system",
            "content": (
                "You assign a single part-of-speech tag to each given word. "
                "Output ONLY valid JSON, no prose, no markdown fences."
            ),
        },
        {"role": "user", "content": prompt},
    ]
    return messages, terms


def parse_pos_alignment_reply(raw: Any) -> dict[str, str]:
    """Parse the LLM POS reply into a ``{word_id: pos}`` map; never raises.

    Only closed-set POS values are kept; invalid / out-of-set / missing ids
    are dropped. Returns ``{}`` on any failure.
    """
    try:
        if not raw:
            return {}
        data = raw if isinstance(raw, dict) else json.loads(raw)
        entries = (data or {}).get("entries") or []
        if not isinstance(entries, list):
            return {}
        out: dict[str, str] = {}
        for e in entries:
            if not isinstance(e, dict):
                continue
            wid = str(e.get("id") or "").strip()
            pos = normalize_pos(e.get("pos"))
            if wid and pos:
                out[wid] = pos
        return out
    except Exception:
        return {}


def run_pos_alignment(
    config: Any,
    adapter: Any,
    *,
    language: str = "Turkish",
    source_language: str = "Chinese",
) -> dict[str, str]:
    """Run the POS alignment LLM call; return ``{word_id: pos}`` map.

    Never raises here — the ``AiRequestWorker`` surfaces errors via its
    ``error_occurred`` signal, and a network/parse failure degrades to an empty
    map so callers report a non-modal status message. Pure: no Qt, no tree writes.
    """
    try:
        from src.backend.ai_generator import request_chat

        messages, _terms = build_pos_alignment_messages(
            config, adapter, language=language, source_language=source_language
        )
        body = request_chat(config, messages, temperature=0.2)
        return parse_pos_alignment_reply(body)
    except Exception:
        return {}