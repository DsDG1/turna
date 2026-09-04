"""Experience Patch protocol v1.6 (E1.5 / C-08 / P10 / v4.58 SectionPatch).

Pure Python, no Qt. Describes the units of AI/editor change that can be
previewed and pushed through the undo stack (C-09).

Scopes:
* ``FieldPatch`` — single dict field
* ``ItemPatch`` — replace one interaction item (force id)
* ``LessonPatch`` — replace one whole lesson dict (force lesson id)  [P10]
* ``BatchPatch`` — ordered list of the above; transactional apply     [P10]
* ``SectionPatch`` — whole section body replace (force section id) + resource
  merge tracked by ApplySectionPatchCommand  [v4.58]
"""
from __future__ import annotations

from copy import deepcopy
from dataclasses import dataclass
from typing import Any, Sequence, Union
import logging
logger = logging.getLogger(__name__)


class PatchError(ValueError):
    """Raised when a patch cannot be applied safely (e.g. id mutation)."""


@dataclass(frozen=True)
class FieldPatch:
    """Change one field on an in-memory dict target."""

    target_kind: str
    target_id: str
    field: str
    old_value: Any
    new_value: Any

    def summary(self) -> str:
        old = _short(self.old_value)
        new = _short(self.new_value)
        return f"{self.target_kind}:{self.target_id}.{self.field}: {old} → {new}"


@dataclass(frozen=True)
class ItemPatch:
    """Replace one item inside a stage while preserving its id."""

    item_id: str
    old_item: dict[str, Any]
    new_item: dict[str, Any]
    stage_id: str = ""

    def summary(self) -> str:
        before = _item_label(self.old_item)
        after = _item_label(self.new_item)
        return f"题目 {self.item_id}: {before} → {after}"


@dataclass(frozen=True)
class LessonPatch:
    """Replace one whole lesson dict while preserving its id (P10 / C-08).

    Child item ids are **not** force-merged in v1 (empty→filled lessons often
    have no prior items). The lesson id itself is immutable.
    """

    lesson_id: str
    old_lesson: dict[str, Any]
    new_lesson: dict[str, Any]
    section_id: str = ""
    unit_id: str = ""

    def summary(self) -> str:
        old_name = _short(self.old_lesson.get("name") or self.lesson_id, 40)
        new_name = _short(self.new_lesson.get("name") or self.lesson_id, 40)
        return f"课时 {self.lesson_id}: {old_name} → {new_name}"


@dataclass(frozen=True)
class SectionPatch:
    """Replace one whole section dict while preserving its id (C-08 / v4.58).

    Resource table merges (vocab/expressions/grammar from top-level of
    ``new_section``) are applied by ``ApplySectionPatchCommand`` using the
    adapter's ``merge_section_resources`` + rollback tracking — this pure
    type only carries the section bodies.
    """

    section_id: str
    old_section: dict[str, Any]
    new_section: dict[str, Any]

    def summary(self) -> str:
        old_n = _short(self.old_section.get("name") or self.section_id, 40)
        new_n = _short(self.new_section.get("name") or self.section_id, 40)
        return f"节 {self.section_id}: {old_n} → {new_n}"


PatchLike = Union[FieldPatch, ItemPatch, LessonPatch, SectionPatch]


@dataclass(frozen=True)
class BatchPatch:
    """Ordered batch of patches; applied transactionally (P10 / C-08)."""

    patches: tuple[PatchLike, ...]
    label: str = "批量修改"

    def summary(self) -> str:
        n = len(self.patches)
        if n == 0:
            return f"{self.label}（空）"
        first = self.patches[0].summary()
        if n == 1:
            return f"{self.label}: {first}"
        return f"{self.label}（{n} 项）: {first} …"


# ---------------------------------------------------------------------------
# Factories
# ---------------------------------------------------------------------------


def field_patch(
    target: dict[str, Any],
    field: str,
    new_value: Any,
    *,
    target_kind: str = "item",
    target_id: str | None = None,
) -> FieldPatch:
    """Build a FieldPatch from a live target dict (captures old value)."""
    if field == "id":
        raise PatchError("id 字段不可修改")
    tid = target_id if target_id is not None else str(target.get("id") or "")
    return FieldPatch(
        target_kind=target_kind,
        target_id=tid,
        field=field,
        old_value=deepcopy(target.get(field)),
        new_value=deepcopy(new_value),
    )


def item_patch_from_replace(
    old_item: dict[str, Any],
    new_item: dict[str, Any],
    *,
    stage_id: str = "",
) -> ItemPatch:
    """Build an ItemPatch; forces new_item id to match old_item (immutable id)."""
    item_id = str(old_item.get("id") or "")
    if not item_id:
        raise PatchError("old_item 缺少 id")
    merged = deepcopy(new_item)
    merged["id"] = item_id  # 红线：默保 id
    return ItemPatch(
        item_id=item_id,
        old_item=deepcopy(old_item),
        new_item=merged,
        stage_id=stage_id,
    )


def lesson_patch_from_replace(
    old_lesson: dict[str, Any],
    new_lesson: dict[str, Any],
    *,
    section_id: str = "",
    unit_id: str = "",
) -> LessonPatch:
    """Build a LessonPatch; forces new_lesson id to match old_lesson."""
    lesson_id = str(old_lesson.get("id") or "")
    if not lesson_id:
        raise PatchError("old_lesson 缺少 id")
    merged = deepcopy(new_lesson)
    if not isinstance(merged, dict):
        raise PatchError("new_lesson 必须是 dict")
    merged["id"] = lesson_id  # 红线：默保 lesson id
    return LessonPatch(
        lesson_id=lesson_id,
        old_lesson=deepcopy(old_lesson),
        new_lesson=merged,
        section_id=section_id,
        unit_id=unit_id,
    )


def batch_patch(
    patches: Sequence[PatchLike],
    *,
    label: str = "批量修改",
) -> BatchPatch:
    """Build a BatchPatch; empty list is rejected."""
    items = tuple(patches)
    if not items:
        raise PatchError("BatchPatch 不能为空")
    for p in items:
        if not isinstance(p, (FieldPatch, ItemPatch, LessonPatch)):
            raise PatchError(f"不支持的 patch 类型: {type(p)!r}")
    return BatchPatch(patches=items, label=label or "批量修改")


def section_patch_from_replace(
    old_section: dict[str, Any],
    new_section: dict[str, Any],
) -> SectionPatch:
    """Build a SectionPatch; forces new_section id to match old_section."""
    if not isinstance(old_section, dict) or not isinstance(new_section, dict):
        raise PatchError("section 必须是 dict")
    sid = str(old_section.get("id") or "").strip()
    if not sid:
        raise PatchError("old_section 缺少 id")
    merged = deepcopy(new_section)
    merged["id"] = sid  # 红线：默保 section id
    return SectionPatch(
        section_id=sid,
        old_section=deepcopy(old_section),
        new_section=merged,
    )


def _index_lessons_by_id(
    section: Any,
) -> dict[str, tuple[str, str, dict[str, Any]]]:
    """Map lesson_id → (section_id, unit_id, lesson_dict). Never raises."""
    out: dict[str, tuple[str, str, dict[str, Any]]] = {}
    try:
        if not isinstance(section, dict):
            return out
        sid = str(section.get("id") or "")
        for unit in section.get("units") or []:
            if not isinstance(unit, dict):
                continue
            uid = str(unit.get("id") or "")
            for les in unit.get("lessons") or []:
                if not isinstance(les, dict):
                    continue
                lid = str(les.get("id") or "").strip()
                if not lid:
                    continue
                out[lid] = (sid, uid, les)
    except Exception:
        return {}
    return out


def lesson_patches_from_section_diff(
    old_section: Any,
    new_section: Any,
    *,
    only_lesson_ids: set[str] | frozenset[str] | None = None,
) -> list[LessonPatch]:
    """C-08 / v4.57: extract LessonPatches for lessons that changed.

    Aligns by lesson id across units. Forces new lesson id to match old.
    Never raises — garbage input → ``[]``. Does **not** cover new units,
    deleted lessons, or section-level resource tables (caller may fall back
    to ``MergeAiSectionCommand``).
    """
    try:
        old_idx = _index_lessons_by_id(old_section)
        new_idx = _index_lessons_by_id(new_section)
        if not old_idx or not new_idx:
            return []
        allow: set[str] | None
        if only_lesson_ids is None:
            allow = None
        else:
            allow = {str(x).strip() for x in only_lesson_ids if str(x).strip()}
            if not allow:
                return []
        patches: list[LessonPatch] = []
        for lid, (sid, uid, old_les) in old_idx.items():
            if allow is not None and lid not in allow:
                continue
            if lid not in new_idx:
                continue
            _nsid, _nuid, new_les = new_idx[lid]
            if old_les == new_les:
                continue
            try:
                patches.append(
                    lesson_patch_from_replace(
                        old_les,
                        new_les,
                        section_id=sid,
                        unit_id=uid,
                    )
                )
            except Exception:
                continue
        return patches
    except Exception:
        return []


# ---------------------------------------------------------------------------
# Apply / revert (single)
# ---------------------------------------------------------------------------


def apply_field_patch(target: dict[str, Any], patch: FieldPatch) -> dict[str, Any]:
    """Apply FieldPatch in-place; returns the target for chaining."""
    if patch.field == "id":
        raise PatchError("id 字段不可修改")
    target[patch.field] = deepcopy(patch.new_value)
    return target


def revert_field_patch(target: dict[str, Any], patch: FieldPatch) -> dict[str, Any]:
    """Undo a FieldPatch in-place."""
    if patch.field == "id":
        raise PatchError("id 字段不可修改")
    target[patch.field] = deepcopy(patch.old_value)
    return target


def apply_item_patch(stage: dict[str, Any], patch: ItemPatch) -> int:
    """Replace the matching item in ``stage['items']``.

    Returns the index that was updated, or raises PatchError.
    """
    items = stage.get("items")
    if not isinstance(items, list):
        raise PatchError("stage 没有 items 列表")
    for i, it in enumerate(items):
        if not isinstance(it, dict):
            continue
        if str(it.get("id") or "") != patch.item_id:
            continue
        # Guard: never let the patch drop or swap the id.
        replacement = deepcopy(patch.new_item)
        replacement["id"] = patch.item_id
        items[i] = replacement
        return i
    raise PatchError(f"找不到题目 id={patch.item_id}")


def revert_item_patch(stage: dict[str, Any], patch: ItemPatch) -> int:
    """Restore old_item for ``patch.item_id``."""
    reverse = ItemPatch(
        item_id=patch.item_id,
        old_item=patch.new_item,
        new_item=patch.old_item,
        stage_id=patch.stage_id,
    )
    return apply_item_patch(stage, reverse)


def apply_lesson_patch(unit: dict[str, Any], patch: LessonPatch) -> int:
    """Replace the matching lesson in ``unit['lessons']``.

    Returns the index that was updated, or raises PatchError.
    """
    lessons = unit.get("lessons")
    if not isinstance(lessons, list):
        raise PatchError("unit 没有 lessons 列表")
    for i, les in enumerate(lessons):
        if not isinstance(les, dict):
            continue
        if str(les.get("id") or "") != patch.lesson_id:
            continue
        replacement = deepcopy(patch.new_lesson)
        replacement["id"] = patch.lesson_id
        lessons[i] = replacement
        return i
    raise PatchError(f"找不到课时 id={patch.lesson_id}")


def revert_lesson_patch(unit: dict[str, Any], patch: LessonPatch) -> int:
    """Restore old_lesson for ``patch.lesson_id``."""
    reverse = LessonPatch(
        lesson_id=patch.lesson_id,
        old_lesson=patch.new_lesson,
        new_lesson=patch.old_lesson,
        section_id=patch.section_id,
        unit_id=patch.unit_id,
    )
    return apply_lesson_patch(unit, reverse)


# ---------------------------------------------------------------------------
# Resolved batch (transactional) — hosts are live dicts bound by the caller
# ---------------------------------------------------------------------------

# step: ("field", target_dict, FieldPatch)
#       ("item", stage_dict, ItemPatch)
#       ("lesson", unit_dict, LessonPatch)
ResolvedStep = tuple[str, dict[str, Any], PatchLike]


def apply_resolved_batch(steps: Sequence[ResolvedStep]) -> None:
    """Apply resolved steps transactionally.

    On failure, already-applied steps are reverted in reverse order, then
    the original error is re-raised. Never leaves a half-applied batch.
    """
    if not steps:
        raise PatchError("Batch 步骤不能为空")
    applied: list[ResolvedStep] = []
    try:
        for step in steps:
            kind, host, patch = step
            if kind == "field":
                if not isinstance(patch, FieldPatch):
                    raise PatchError("field 步骤需要 FieldPatch")
                apply_field_patch(host, patch)
            elif kind == "item":
                if not isinstance(patch, ItemPatch):
                    raise PatchError("item 步骤需要 ItemPatch")
                apply_item_patch(host, patch)
            elif kind == "lesson":
                if not isinstance(patch, LessonPatch):
                    raise PatchError("lesson 步骤需要 LessonPatch")
                apply_lesson_patch(host, patch)
            else:
                raise PatchError(f"未知 batch 步骤 kind={kind!r}")
            applied.append(step)
    except Exception:
        for kind, host, patch in reversed(applied):
            try:
                if kind == "field" and isinstance(patch, FieldPatch):
                    revert_field_patch(host, patch)
                elif kind == "item" and isinstance(patch, ItemPatch):
                    revert_item_patch(host, patch)
                elif kind == "lesson" and isinstance(patch, LessonPatch):
                    revert_lesson_patch(host, patch)
            except Exception:
                logger.debug("backend/experience/patch.py:apply_resolved_batch best-effort step failed", exc_info=True)
        raise


def revert_resolved_batch(steps: Sequence[ResolvedStep]) -> None:
    """Revert a previously applied resolved batch (reverse order)."""
    for kind, host, patch in reversed(list(steps)):
        if kind == "field" and isinstance(patch, FieldPatch):
            revert_field_patch(host, patch)
        elif kind == "item" and isinstance(patch, ItemPatch):
            revert_item_patch(host, patch)
        elif kind == "lesson" and isinstance(patch, LessonPatch):
            revert_lesson_patch(host, patch)
        else:
            raise PatchError(f"无法 revert 步骤 kind={kind!r}")


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------


def _short(value: Any, limit: int = 80) -> str:
    if value is None:
        return "∅"
    if isinstance(value, (dict, list)):
        text = str(value)
    else:
        text = str(value)
    text = text.replace("\n", " ").strip()
    if len(text) > limit:
        return text[: limit - 1] + "…"
    return text


def _item_label(item: dict[str, Any]) -> str:
    for key in ("prompt", "sentence", "text", "question"):
        val = item.get(key)
        if val:
            return _short(val, 60)
    return _short(item.get("runtimeType") or item.get("id") or "?", 40)


def field_diff_lines(patches: Any) -> list[str]:
    """Build per-field ``field: old → new`` diff lines for a preview (A2).

    Accepts a single patch or an iterable of patches. ``FieldPatch`` yields one
    line via its own summary format; ``ItemPatch`` yields one line per
    top-level scalar key that changed between ``old_item`` / ``new_item``
    (``id`` and unchanged keys are skipped). Never raises; returns ``[]`` on
    garbage input. Pure / no Qt — used by ``PreviewHost`` to render a
    structured diff for single-entry changes.
    """
    out: list[str] = []
    try:
        if patches is None:
            return []
        if isinstance(patches, (FieldPatch, ItemPatch)):
            seq = [patches]
        else:
            seq = list(patches)
    except Exception:
        return []
    for p in seq:
        try:
            if isinstance(p, FieldPatch):
                out.append(f"{p.field}: {_short(p.old_value)} → {_short(p.new_value)}")
            elif isinstance(p, ItemPatch):
                out.extend(_item_diff_lines(p))
        except Exception:
            continue
    return out


def _item_diff_lines(patch: ItemPatch) -> list[str]:
    """Per-changed-top-level-key diff lines for an ItemPatch (skip id/unchanged)."""
    lines: list[str] = []
    try:
        old = patch.old_item if isinstance(patch.old_item, dict) else {}
        new = patch.new_item if isinstance(patch.new_item, dict) else {}
        keys = list(dict.fromkeys(list(old.keys()) + list(new.keys())))
        for key in keys:
            if key == "id":
                continue
            ov = old.get(key)
            nv = new.get(key)
            if ov == nv:
                continue
            lines.append(f"{key}: {_short(ov)} → {_short(nv)}")
    except Exception:
        return lines
    return lines
