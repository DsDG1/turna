"""V-06 resource.resolve_term_conflicts skill (pure Python, no Qt).

Local detector for vocab ↔ expression term conflicts: an entry pair whose
normalized ``term`` matches but whose normalized ``translation`` differs is a
conflict (same term + same translation is a duplicate — owned by K-20
``resource.dedupe_suggest`` and skipped here). The write is performed by the
caller via batch ``FieldPatch`` (one per side, ``translation`` field) +
``ApplyBatchPatchCommand`` (preview + confirm + undo); this module never
touches the adapter or Qt.

红线（experienceai.md §14.5.3）：
* 纯函数检测 / LLM messages 接口预留 / 解析回复；无 Qt、不写树、不写盘。
* 越界 / 缺失 / 异常归一为闭集状态，永不抛（§14.5.2）。
* 返回闭集（count / vocab_id / expression_id / issue）—— term / translation
  不进返回，仅进确认文案（调用方读 live dict）。
* LLM build/parse 为 v1 预留接口；v1 仲裁方向由人二选一，零 LLM。
"""
from __future__ import annotations

import json
from typing import Any

ACTION_ID = "resource.resolve_term_conflicts"

ISSUE_TRANSLATION_MISMATCH = "translation_mismatch"


def _norm(value: Any) -> str:
    return " ".join(str(value or "").split()).lower()


def _term(entry: dict[str, Any]) -> str:
    return _norm(entry.get("term") or entry.get("source"))


def evaluate_term_conflicts(adapter: Any) -> dict[str, Any]:
    """Detect vocab ↔ expression term conflicts; never raises.

    Returns a closed-shape dict::

        {
          "count": int,
          "conflicts": [
            {"vocab_id": str, "expression_id": str, "issue": str}
          ],
        }

    A conflict is a (vocab, expression) pair with equal normalized term and
    different normalized translation. Same term + same translation is skipped
    (K-20 duplicate territory). Empty terms are skipped entirely. ``term`` /
    ``translation`` are intentionally omitted from the return (§14.5.3);
    callers needing them for a confirmation dialog read the live entries.
    """
    out: list[dict[str, Any]] = []
    try:
        vocab = [w for w in (getattr(adapter, "vocab", None) or []) if isinstance(w, dict)]
        exprs = [e for e in (getattr(adapter, "expressions", None) or []) if isinstance(e, dict)]
        expr_by_term: dict[str, list[dict[str, Any]]] = {}
        for e in exprs:
            t = _term(e)
            if t:
                expr_by_term.setdefault(t, []).append(e)
        seen: set[tuple[str, str]] = set()
        for w in vocab:
            try:
                t = _term(w)
                if not t:
                    continue
                wid = str(w.get("id") or "")
                if not wid:
                    continue
                w_trans = _norm(w.get("translation"))
                for e in expr_by_term.get(t, []):
                    eid = str(e.get("id") or "")
                    if not eid or (wid, eid) in seen:
                        continue
                    if _norm(e.get("translation")) == w_trans:
                        continue  # same term + same translation → K-20 duplicate
                    seen.add((wid, eid))
                    out.append(
                        {
                            "vocab_id": wid,
                            "expression_id": eid,
                            "issue": ISSUE_TRANSLATION_MISMATCH,
                        }
                    )
            except Exception:
                continue
    except Exception:
        return {"count": 0, "conflicts": []}
    return {"count": len(out), "conflicts": out}


def build_term_conflict_messages(
    config: Any,
    adapter: Any,
    *,
    language: str = "Turkish",
    source_language: str = "Chinese",
) -> tuple[list[dict[str, Any]], dict[str, str]]:
    """LLM message builder (v1 预留接口，未接入 handler）。

    Returns ``(messages, terms)`` where ``terms`` maps entry id → term for
    client-side confirmation UI only (never telemetry). The LLM would be
    asked to pick one canonical translation per conflict pair; v1 仲裁方向由
    人二选一，零 LLM。
    """
    report = evaluate_term_conflicts(adapter)
    terms: dict[str, str] = {}
    payload: list[dict[str, Any]] = []
    vocab_by_id = {
        str(w.get("id") or ""): w
        for w in (getattr(adapter, "vocab", None) or [])
        if isinstance(w, dict)
    }
    expr_by_id = {
        str(e.get("id") or ""): e
        for e in (getattr(adapter, "expressions", None) or [])
        if isinstance(e, dict)
    }
    for c in report["conflicts"]:
        w = vocab_by_id.get(c["vocab_id"], {})
        e = expr_by_id.get(c["expression_id"], {})
        term = str(w.get("term") or e.get("term") or "")
        terms[c["vocab_id"]] = term
        terms[c["expression_id"]] = term
        payload.append(
            {
                "vocab_id": c["vocab_id"],
                "expression_id": c["expression_id"],
                "term": term,
                "vocab_translation": str(w.get("translation") or ""),
                "expression_translation": str(e.get("translation") or ""),
            }
        )
    prompt = (
        f"你是语言课程词条冲突仲裁助手。目标语：{language}；释义语：{source_language}。\n"
        "下列 vocab 与 expression 词条 term 相同但释义不同，请为每一对给出统一释义。\n"
        "只返回 JSON 对象：{\"entries\":[{\"vocab_id\":\"...\",\"expression_id\":\"...\","
        "\"translation\":\"...\"}]}，不要改 id；不要输出 markdown。\n\n"
        f"{json.dumps({'entries': payload}, ensure_ascii=False)}"
    )
    messages = [
        {
            "role": "system",
            "content": (
                "You resolve translation conflicts between vocabulary and "
                "expression entries. Output ONLY valid JSON, no prose, no "
                "markdown fences."
            ),
        },
        {"role": "user", "content": prompt},
    ]
    return messages, terms


def parse_term_conflict_reply(raw: Any) -> dict[str, str]:
    """Parse the LLM reply into ``{f"{vocab_id}|{expression_id}": translation}``.

    Never raises; invalid / incomplete entries are dropped, ``{}`` on failure.
    v1 预留接口（未接入 handler）。
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
            vid = str(e.get("vocab_id") or "").strip()
            eid = str(e.get("expression_id") or "").strip()
            trans = str(e.get("translation") or "").strip()
            if vid and eid and trans:
                out[f"{vid}|{eid}"] = trans
        return out
    except Exception:
        return {}
