"""Caret JSON-path locate + explain for the JsonEditor (T-10 / v4.50).

Pure Python, no Qt, no network, never raises.

- ``json_path_at(text, offset)`` — dotted/`[n]` JSONPath-ish path of the
  token (or innermost container) at character ``offset``. Returns ``None``
  for invalid JSON / out-of-range input.
- ``explain_path(obj, path)`` — closed-set local explanation
  ``{summary, detail, known}`` mirroring ``why.py``'s rule-table style.
  Known fields are described via ``i18n.field_label`` and, when the path
  lands inside an interaction item, the ``INTERACTION_SCHEMA`` FieldSpec
  (required / kind). Unknown paths fall back to 「未识别路径」.
"""
from __future__ import annotations

import json
from typing import Any

_WS = " \t\r\n"


# ---------------------------------------------------------------------------
# json_path_at
# ---------------------------------------------------------------------------


def json_path_at(text: str, offset: int) -> str | None:
    """Return the JSON path at character ``offset`` (``$``-rooted), or None.

    Keys are dot-joined, array indices render as ``[n]``; the document root
    is ``"$"``. Invalid JSON, empty text or a non-integer offset yield
    ``None``. Never raises.
    """
    try:
        return _json_path_at(text, offset)
    except Exception:  # noqa: BLE001 — never-raise contract
        return None


def _fmt_path(segs: list[Any]) -> str:
    out = "$"
    for s in segs:
        if isinstance(s, int):
            out += f"[{s}]"
        else:
            out += f".{s}"
    return out


def _scan_string(text: str, i: int, n: int) -> int:
    """Return the index of the closing quote for a string starting at ``i``."""
    j = i + 1
    while j < n:
        c = text[j]
        if c == "\\" and j + 1 < n:
            j += 2
            continue
        if c == '"':
            return j
        j += 1
    raise ValueError("unterminated string")


def _decode_key(literal: str) -> str:
    try:
        return str(json.loads(literal))
    except Exception:  # noqa: BLE001
        return literal[1:-1]


def _json_path_at(text: str, offset: int) -> str | None:
    if not isinstance(text, str) or not text.strip():
        return None
    offset = int(offset)
    n = len(text)
    if offset < 0 or offset > n:
        return None
    # Gate on a strict parse: the menu disables itself for invalid JSON, so
    # the scanner below only ever walks well-formed documents.
    json.loads(text)

    segs: list[Any] = []  # path segments of the container chain
    # Frames: {"kind": "object"|"array", "key": str|None, "index": int,
    #          "start": int, "seg_count": int}
    frames: list[dict[str, Any]] = []
    best: tuple[int, str] | None = None  # (depth, path) deepest hit so far
    containers = 0  # total containers opened (validates balanced close)

    def _hit(depth: int, path: str) -> None:
        nonlocal best
        if best is None or depth >= best[0]:
            best = (depth, path)

    def _pending_segs() -> list[Any] | None:
        """Segments of the value about to be read inside the current frame."""
        if not frames:
            return list(segs)
        top = frames[-1]
        if top["kind"] == "object":
            if top["key"] is None:
                return None
            return segs + [top["key"]]
        return segs + [top["index"]]

    def _advance_parent() -> None:
        """A value finished inside the current frame; move to the next slot."""
        if not frames:
            return
        top = frames[-1]
        if top["kind"] == "object":
            top["key"] = None
        else:
            top["index"] += 1

    i = 0
    while i < n:
        c = text[i]
        if c in _WS or c in ",:":
            i += 1
            continue
        if c == '"':
            j = _scan_string(text, i, n)
            literal = text[i : j + 1]
            k = j + 1
            while k < n and text[k] in _WS:
                k += 1
            is_key = (
                k < n
                and text[k] == ":"
                and frames
                and frames[-1]["kind"] == "object"
                and frames[-1]["key"] is None
            )
            if is_key:
                key = _decode_key(literal)
                frames[-1]["key"] = key
                token_segs = segs + [key]
            else:
                token_segs = _pending_segs()
                if token_segs is None:
                    return None
                _advance_parent()
            if i <= offset <= j:
                _hit(len(token_segs), _fmt_path(token_segs))
            i = j + 1
            continue
        if c in "[{":
            value_segs = _pending_segs()
            if value_segs is None:
                return None
            kind = "array" if c == "[" else "object"
            frames.append(
                {
                    "kind": kind,
                    "key": None,
                    "index": 0,
                    "start": i,
                    "seg_count": len(segs),
                }
            )
            segs = value_segs
            containers += 1
            i += 1
            continue
        if c in "]}":
            want = "array" if c == "]" else "object"
            if not frames or frames[-1]["kind"] != want:
                return None
            frame = frames.pop()
            if frame["start"] <= offset <= i:
                _hit(len(segs), _fmt_path(segs))
            segs = segs[: frame["seg_count"]]
            _advance_parent()
            i += 1
            continue
        if c in "-0123456789":
            j = i + 1
            while j < n and text[j] in "-+0123456789.eE":
                j += 1
            token_segs = _pending_segs()
            if token_segs is None:
                return None
            _advance_parent()
            if i <= offset <= j - 1:
                _hit(len(token_segs), _fmt_path(token_segs))
            i = j
            continue
        if c.isalpha():
            j = i
            while j < n and text[j].isalpha():
                j += 1
            if text[i:j] not in ("true", "false", "null"):
                return None
            token_segs = _pending_segs()
            if token_segs is None:
                return None
            _advance_parent()
            if i <= offset <= j - 1:
                _hit(len(token_segs), _fmt_path(token_segs))
            i = j
            continue
        return None
    if frames or containers == 0:
        return None
    return best[1] if best is not None else None


# ---------------------------------------------------------------------------
# explain_path
# ---------------------------------------------------------------------------


def _split_path(path: str) -> list[Any] | None:
    """Split a ``$.a[0].b`` path into segments (``str`` keys / ``int``)."""
    if not isinstance(path, str) or not path.startswith("$"):
        return None
    segs: list[Any] = []
    i = 1
    n = len(path)
    while i < n:
        c = path[i]
        if c == ".":
            j = i + 1
            while j < n and path[j] not in ".[":
                j += 1
            key = path[i + 1 : j]
            if not key:
                return None
            segs.append(key)
            i = j
        elif c == "[":
            j = path.find("]", i)
            if j < 0:
                return None
            try:
                segs.append(int(path[i + 1 : j]))
            except ValueError:
                return None
            i = j + 1
        else:
            return None
    return segs


# Plural container keys missing from i18n NESTED_LAYER_LABELS (local rule
# table, mirroring why.py's closed-set style).
_LAYER_EXTRA: dict[str, str] = {
    "sections": "章节列表",
    "units": "单元列表",
    "lessons": "课列表",
    "vocab": "词库",
    "expressions": "表达列表",
    "grammarPoints": "语法点列表",
}

_TYPE_NAMES = {
    dict: "对象",
    list: "数组",
    str: "字符串",
    bool: "布尔",
    int: "数字",
    float: "数字",
    type(None): "null",
}

_KIND_NAMES = {
    "string": "文本",
    "int": "整数",
    "bool": "布尔",
    "string_list": "文本列表",
    "int_list": "整数列表",
    "ref_word": "词条引用",
    "ref_expression": "表达引用",
    "ref_grammar": "语法点引用",
}


def _schema_spec(obj: Any, segs: list[Any], field: str):
    """Find the INTERACTION_SCHEMA FieldSpec for ``field`` when the path sits
    inside an interaction item (nearest ancestor dict with a runtimeType)."""
    try:
        from src.backend.lesson_content import INTERACTION_SCHEMA
    except Exception:  # noqa: BLE001
        return None
    node = obj
    ancestors: list[Any] = []
    for seg in segs[:-1]:
        if isinstance(node, dict) and isinstance(seg, str):
            node = node.get(seg)
        elif isinstance(node, list) and isinstance(seg, int) and 0 <= seg < len(node):
            node = node[seg]
        else:
            node = None
        ancestors.append(node)
    for anc in reversed(ancestors):
        if isinstance(anc, dict):
            rt = anc.get("runtimeType")
            if rt in INTERACTION_SCHEMA:
                for spec in INTERACTION_SCHEMA[rt]:
                    if spec.name == field:
                        return spec, rt
                return None
    return None


def explain_path(obj: Any, path: str | None) -> dict[str, Any]:
    """Explain a JSON path (closed set: ``summary`` / ``detail`` / ``known``).

    Local rules only; unknown paths fall back to 「未识别路径」. Never raises.
    """
    try:
        return _explain_path(obj, path)
    except Exception:  # noqa: BLE001 — never-raise contract
        return {
            "summary": "未识别路径",
            "detail": "路径解析失败，无法解释。",
            "known": False,
        }


def _explain_path(obj: Any, path: str | None) -> dict[str, Any]:
    from src.i18n.labels import field_label, layer_label

    def _known_label(seg: str) -> tuple[str, bool]:
        """Teacher-facing label for a path key; (label, recognized?)."""
        label = field_label(seg)
        if label != seg:
            return label, True
        label = layer_label(seg)
        if label != seg:
            return label, True
        if seg in _LAYER_EXTRA:
            return _LAYER_EXTRA[seg], True
        return seg, False

    if not path:
        return {
            "summary": "未识别路径",
            "detail": "光标处不是合法 JSON，无法定位字段。请先修正语法错误。",
            "known": False,
        }
    segs = _split_path(path)
    if segs is None:
        return {
            "summary": "未识别路径",
            "detail": f"路径格式无法解析：{path}",
            "known": False,
        }
    if not segs:
        return {
            "summary": "文档根",
            "detail": "整个 JSON 文档的根节点。",
            "known": True,
        }

    # Walk the value so we can report its runtime type / existence.
    node = obj
    found = True
    for seg in segs:
        if isinstance(node, dict) and isinstance(seg, str) and seg in node:
            node = node[seg]
        elif isinstance(node, list) and isinstance(seg, int) and 0 <= seg < len(node):
            node = node[seg]
        else:
            found = False
            break

    last = segs[-1]
    if isinstance(last, int):
        label = f"第 {last + 1} 项"
        known = True
    else:
        label, known = _known_label(str(last))
    # Any unrecognized string segment anywhere in the chain makes the whole
    # path unknown unless an interaction-schema rule rescues the last field.
    chain_known = all(
        not isinstance(s, str) or _known_label(str(s))[1] for s in segs
    )

    crumbs: list[str] = []
    for seg in segs[:-1]:
        if isinstance(seg, int):
            crumbs.append(f"[{seg}]")
        else:
            crumbs.append(_known_label(str(seg))[0])
    where = " › ".join(crumbs) if crumbs else "根"

    if not found:
        path_known = known and chain_known
        return {
            "summary": label if path_known else "未识别路径",
            "detail": (
                f"路径：{path}\n位置：{where}\n"
                "该路径在当前 JSON 中不存在（可能已被删除或拼写有误）。"
            ),
            "known": path_known,
        }

    type_name = _TYPE_NAMES.get(type(node), "值")
    detail_lines = [f"路径：{path}", f"位置：{where}", f"类型：{type_name}"]

    known_schema = False
    if isinstance(last, str):
        hit = _schema_spec(obj, segs, last)
        if hit:
            spec, rt = hit
            req = "必填" if spec.required else "可选"
            kind = _KIND_NAMES.get(spec.kind, spec.kind)
            detail_lines.append(f"题型 {rt} 字段：{req} · {kind}")
            known_schema = True

    if not (known and chain_known) and not known_schema:
        return {
            "summary": "未识别路径",
            "detail": "\n".join(detail_lines)
            + "\n未命中已知字段规则，请对照 course-layout 契约检查该字段。",
            "known": False,
        }
    return {"summary": label, "detail": "\n".join(detail_lines), "known": True}
