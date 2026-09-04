"""V-04 resource reference graph + replacement mapping (pure Python, no Qt).

Wide-scope scan of ``adapter.sections`` for references to a global resource
entry (vocab / expressions / grammar_points). Powers the resource editor's
delete confirmation (ref count + first refs) and the "propose replacement
mapping" flow: local candidates → one ItemPatch per referencing item (item id
preserved) → a single ``ApplyBatchPatchCommand`` on the Undo stack.

红线（experienceai.md §14.5.3）：
* 纯函数检测 / 构造替换 steps；无 Qt、不写树、不写盘；永不抛。
* 只作用全局资源表（adapter.vocab / expressions / grammar_points），不碰
  section 顶层 words 数组。
* 返回闭集 shape（count / section_id / lesson_id / item_id / field）——
  term / translation / 原文不进返回。
"""
from __future__ import annotations

from copy import deepcopy
from typing import Any, Iterator
import logging
logger = logging.getLogger(__name__)

# Reference key whitelist (wide scope, mirrors tool/course_cli.py lint).
_SCALAR_REF_FIELDS: dict[str, tuple[str, ...]] = {
    "vocab": ("wordId",),
    "expressions": ("expressionId",),
    "grammar_points": ("grammarPointId",),
}
_LIST_REF_FIELDS: dict[str, tuple[str, ...]] = {
    "vocab": ("wordIds", "correctWordIds", "linkedWordIds"),
    "expressions": (),
    "grammar_points": (),
}
_POOL_ATTR = {
    "vocab": "vocab",
    "expressions": "expressions",
    "grammar_points": "grammar_points",
}


def _iter_items(adapter: Any) -> Iterator[tuple[str, str, dict, dict]]:
    """Yield ``(section_id, lesson_id, item, container)`` across all sections.

    ``container`` is the stage / listeningPhase dict that owns the ``items``
    list (what ``apply_item_patch`` binds to). Never raises.
    """
    sections = list(getattr(adapter, "sections", None) or [])
    for section in sections:
        if not isinstance(section, dict):
            continue
        sid = str(section.get("id") or "")
        for unit in section.get("units") or []:
            if not isinstance(unit, dict):
                continue
            for lesson in unit.get("lessons") or []:
                if not isinstance(lesson, dict):
                    continue
                lid = str(lesson.get("id") or "")
                content = lesson.get("content") or {}
                if not isinstance(content, dict):
                    continue
                containers: list[dict] = []
                containers.extend(
                    s for s in (content.get("stages") or []) if isinstance(s, dict)
                )
                for sub in content.get("subLessons") or []:
                    if not isinstance(sub, dict):
                        continue
                    containers.extend(
                        s
                        for s in (sub.get("stages") or [])
                        if isinstance(s, dict)
                    )
                containers.extend(
                    p
                    for p in (content.get("listeningPhases") or [])
                    if isinstance(p, dict)
                )
                for container in containers:
                    for item in container.get("items") or []:
                        if isinstance(item, dict):
                            yield sid, lid, item, container


def _hit_fields(item: dict, row_type: str, entry_id: str) -> list[str]:
    """Reference fields of ``item`` that point at ``entry_id`` (order stable)."""
    hits: list[str] = []
    for field in _SCALAR_REF_FIELDS.get(row_type, ()):
        if str(item.get(field) or "") == entry_id:
            hits.append(field)
    for field in _LIST_REF_FIELDS.get(row_type, ()):
        vals = item.get(field)
        if isinstance(vals, list) and any(str(v or "") == entry_id for v in vals):
            hits.append(field)
    return hits


def find_resource_refs(
    adapter: Any, row_type: str, entry_id: str
) -> dict[str, Any]:
    """Find all item references to a global resource entry; never raises.

    Returns a closed-shape dict::

        {"count": int,
         "refs": [{"section_id","lesson_id","item_id","field"}]}

    For ``expressions`` the scan also covers
    ``adapter.grammar_points[*].exampleExpressionIds`` (reported with
    ``item_id`` = grammar point id, empty section/lesson ids).
    """
    empty: dict[str, Any] = {"count": 0, "refs": []}
    try:
        entry_id = str(entry_id or "").strip()
        if not entry_id or row_type not in _POOL_ATTR or adapter is None:
            return empty
        refs: list[dict[str, str]] = []
        for sid, lid, item, _container in _iter_items(adapter):
            try:
                iid = str(item.get("id") or "")
                for field in _hit_fields(item, row_type, entry_id):
                    refs.append(
                        {
                            "section_id": sid,
                            "lesson_id": lid,
                            "item_id": iid,
                            "field": field,
                        }
                    )
            except Exception:
                continue
        if row_type == "expressions":
            try:
                for gp in list(getattr(adapter, "grammar_points", None) or []):
                    if not isinstance(gp, dict):
                        continue
                    vals = gp.get("exampleExpressionIds")
                    if isinstance(vals, list) and any(
                        str(v or "") == entry_id for v in vals
                    ):
                        refs.append(
                            {
                                "section_id": "",
                                "lesson_id": "",
                                "item_id": str(gp.get("id") or ""),
                                "field": "exampleExpressionIds",
                            }
                        )
            except Exception:
                logger.debug("backend/experience/resource_refs.py:find_resource_refs best-effort step failed", exc_info=True)
        return {"count": len(refs), "refs": refs}
    except Exception:
        return empty


def _norm(value: Any) -> str:
    return str(value or "").strip().lower()


def find_replacement_candidates(
    adapter: Any, row_type: str, entry_id: str
) -> list[str]:
    """Local replacement candidates: other pool entries sharing the normalized
    term or translation. Returns a list of ids (closed set); never raises."""
    try:
        attr = _POOL_ATTR.get(row_type)
        entry_id = str(entry_id or "").strip()
        if not attr or not entry_id:
            return []
        entries = [
            e
            for e in (getattr(adapter, attr, None) or [])
            if isinstance(e, dict)
        ]
        target = None
        for e in entries:
            if str(e.get("id") or "") == entry_id:
                target = e
                break
        if target is None:
            return []
        term = _norm(target.get("term") or target.get("source"))
        trans = _norm(target.get("translation"))
        out: list[str] = []
        for e in entries:
            eid = str(e.get("id") or "")
            if not eid or eid == entry_id:
                continue
            e_term = _norm(e.get("term") or e.get("source"))
            e_trans = _norm(e.get("translation"))
            if (term and e_term == term) or (trans and e_trans == trans):
                out.append(eid)
        return out
    except Exception:
        return []


def _replace_in_item(item: dict, row_type: str, old_id: str, new_id: str) -> dict:
    """Deep-copy ``item`` with every reference to ``old_id`` swapped to ``new_id``."""
    new_item = deepcopy(item)
    for field in _SCALAR_REF_FIELDS.get(row_type, ()):
        if str(new_item.get(field) or "") == old_id:
            new_item[field] = new_id
    for field in _LIST_REF_FIELDS.get(row_type, ()):
        vals = new_item.get(field)
        if isinstance(vals, list):
            new_item[field] = [
                new_id if str(v or "") == old_id else v for v in vals
            ]
    return new_item


def build_replacement_steps(
    adapter: Any, row_type: str, old_id: str, new_id: str
) -> list[tuple[str, dict, Any]]:
    """Resolved steps replacing all refs ``old_id`` → ``new_id``; never raises.

    One ``ItemPatch`` per referencing item (item id preserved, bound to its
    stage/phase container); for ``expressions`` additionally one
    ``FieldPatch`` per grammar point ``exampleExpressionIds`` list. Feed the
    result to ``ApplyBatchPatchCommand(steps=...)`` for preview + undo.
    Returns ``[]`` on any failure.
    """
    try:
        from src.backend.experience.patch import (
            field_patch,
            item_patch_from_replace,
        )

        old_id = str(old_id or "").strip()
        new_id = str(new_id or "").strip()
        if not old_id or not new_id or old_id == new_id:
            return []
        if row_type not in _POOL_ATTR:
            return []
        steps: list[tuple[str, dict, Any]] = []
        for _sid, _lid, item, container in _iter_items(adapter):
            try:
                if not _hit_fields(item, row_type, old_id):
                    continue
                new_item = _replace_in_item(item, row_type, old_id, new_id)
                patch = item_patch_from_replace(
                    item, new_item, stage_id=str(container.get("id") or "")
                )
                steps.append(("item", container, patch))
            except Exception:
                continue
        if row_type == "expressions":
            try:
                for gp in list(getattr(adapter, "grammar_points", None) or []):
                    if not isinstance(gp, dict):
                        continue
                    vals = gp.get("exampleExpressionIds")
                    if not isinstance(vals, list) or not any(
                        str(v or "") == old_id for v in vals
                    ):
                        continue
                    new_vals = [
                        new_id if str(v or "") == old_id else v for v in vals
                    ]
                    patch = field_patch(
                        gp,
                        "exampleExpressionIds",
                        new_vals,
                        target_kind="grammar_points",
                        target_id=str(gp.get("id") or ""),
                    )
                    steps.append(("field", gp, patch))
            except Exception:
                logger.debug("backend/experience/resource_refs.py:build_replacement_steps best-effort step failed", exc_info=True)
        return steps
    except Exception:
        return []
