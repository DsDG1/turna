"""C-11 Course sandbox + merge plan (E3-A).

Pure Python, no Qt. Holds **deep-copied** lesson/section JSON so Goal steps
can stage work without mutating the live CourseAdapter.

红线：
* Sandbox never holds a live write-back reference to the main adapter.
* Merge requires explicit host confirmation (``MergePlan.requires_confirm``).
* Lesson / item ids are preserved when applying staged lesson dicts.
"""
from __future__ import annotations

import copy
import time
from dataclasses import dataclass, field
from typing import Any, Mapping, Sequence

from src.backend.experience.planner import GoalPlan, GoalStep


@dataclass
class MergeItem:
    """One unit the host may merge after human confirm."""

    kind: str  # lesson | action | note
    id: str
    summary: str
    action_id: str = ""
    scope: dict[str, Any] = field(default_factory=dict)
    sandbox_payload: dict[str, Any] | None = None

    def to_dict(self) -> dict[str, Any]:
        return {
            "kind": self.kind,
            "id": self.id,
            "summary": self.summary,
            "action_id": self.action_id,
            "scope": dict(self.scope),
            "sandbox_payload": (
                dict(self.sandbox_payload) if self.sandbox_payload else None
            ),
        }


@dataclass
class MergePlan:
    """Human-gated merge package. ``requires_confirm`` is always True."""

    items: list[MergeItem] = field(default_factory=list)
    lesson_ids: list[str] = field(default_factory=list)
    section_ids: list[str] = field(default_factory=list)
    summary: str = ""
    requires_confirm: bool = True
    created_ts: float = 0.0
    goal_text: str = ""

    def to_dict(self) -> dict[str, Any]:
        return {
            "items": [i.to_dict() for i in self.items],
            "lesson_ids": list(self.lesson_ids),
            "section_ids": list(self.section_ids),
            "summary": self.summary,
            "requires_confirm": True,
            "created_ts": self.created_ts,
            "goal_text": self.goal_text,
        }

    def __len__(self) -> int:
        return len(self.items)


# Max items dispatched in one Goal merge (E3-B1 anti-spam).
MERGE_SELECT_CAP = 8


def merge_item_key(item: MergeItem | Mapping[str, Any]) -> str:
    """Stable key for checklist selection. Never raises."""
    try:
        if isinstance(item, Mapping):
            kind = str(item.get("kind") or "")
            iid = str(item.get("id") or "")
            aid = str(item.get("action_id") or "")
            scope = item.get("scope") or {}
            lid = ""
            if isinstance(scope, Mapping):
                lid = str(
                    scope.get("lesson_id")
                    or scope.get("first_lesson_id")
                    or ""
                )
            return f"{kind}:{aid}:{lid or iid}"
        scope = getattr(item, "scope", None) or {}
        lid = ""
        if isinstance(scope, Mapping):
            lid = str(scope.get("lesson_id") or scope.get("first_lesson_id") or "")
        return (
            f"{getattr(item, 'kind', '')}:"
            f"{getattr(item, 'action_id', '')}:"
            f"{lid or getattr(item, 'id', '')}"
        )
    except Exception:
        return "unknown"


def filter_merge_plan(
    plan: MergePlan | None,
    selected_keys: Sequence[str] | None,
    *,
    max_items: int = MERGE_SELECT_CAP,
) -> MergePlan:
    """Return a new MergePlan with only selected items (order preserved).

    Empty selection → empty items (requires_confirm still True).
    Caps at ``max_items``. Never mutates *plan*. Never raises.
    """
    try:
        if plan is None:
            return MergePlan(requires_confirm=True, created_ts=time.time())
        keys = {str(k) for k in (selected_keys or []) if str(k)}
        cap = max(0, int(max_items))
        picked: list[MergeItem] = []
        for it in plan.items:
            if merge_item_key(it) in keys:
                picked.append(it)
            if len(picked) >= cap:
                break
        lesson_ids: list[str] = []
        section_ids: list[str] = []
        for item in picked:
            if item.kind == "lesson" and item.id and item.id not in lesson_ids:
                lesson_ids.append(item.id)
            sid = str((item.scope or {}).get("section_id") or "")
            if sid and sid not in section_ids:
                section_ids.append(sid)
        n_lesson = sum(1 for i in picked if i.kind == "lesson")
        n_action = sum(1 for i in picked if i.kind == "action")
        summary = (
            f"合并所选：{len(picked)} 项（课 {n_lesson} · 动作 {n_action}）· 须确认"
        )
        if plan.goal_text:
            summary += f" · 目标「{plan.goal_text}」"
        return MergePlan(
            items=picked,
            lesson_ids=lesson_ids,
            section_ids=section_ids,
            summary=summary,
            requires_confirm=True,
            created_ts=time.time(),
            goal_text=plan.goal_text,
        )
    except Exception:
        return MergePlan(requires_confirm=True, created_ts=time.time())


def _lesson_id(lesson: Mapping[str, Any] | None) -> str:
    if not lesson:
        return ""
    return str(lesson.get("id") or "").strip()


def _walk_lessons(sections: Sequence[Any]) -> list[tuple[str, dict[str, Any]]]:
    """Yield (section_id, lesson_dict) deep copies from adapter sections."""
    out: list[tuple[str, dict[str, Any]]] = []
    for sec in sections or []:
        if not isinstance(sec, Mapping):
            continue
        sid = str(sec.get("id") or "").strip()
        for unit in sec.get("units") or []:
            if not isinstance(unit, Mapping):
                continue
            for les in unit.get("lessons") or []:
                if isinstance(les, Mapping) and _lesson_id(les):
                    out.append((sid, copy.deepcopy(dict(les))))
    return out


class CourseSandbox:
    """In-memory staging area for goal steps (no adapter write-back)."""

    def __init__(self) -> None:
        self._lessons: dict[str, dict[str, Any]] = {}
        self._section_of: dict[str, str] = {}
        self._original_ids: dict[str, str] = {}  # lesson_id -> id (force preserve)
        self._staged: list[MergeItem] = []
        self._applied_steps: list[str] = []
        self._notes: list[str] = []
        self._created_ts = time.time()
        self._goal_text = ""

    @classmethod
    def from_adapter(
        cls,
        adapter: Any,
        *,
        lesson_ids: Sequence[str] | None = None,
    ) -> "CourseSandbox":
        """Deep-copy selected (or all) lessons from *adapter* into a sandbox."""
        box = cls()
        try:
            sections = list(getattr(adapter, "sections", None) or [])
        except Exception:
            sections = []
        want: set[str] | None = None
        if lesson_ids is not None:
            want = {str(x).strip() for x in lesson_ids if str(x).strip()}
        for sid, les in _walk_lessons(sections):
            lid = _lesson_id(les)
            if not lid:
                continue
            if want is not None and lid not in want:
                continue
            box._lessons[lid] = les
            box._section_of[lid] = sid
            box._original_ids[lid] = lid
        return box

    def __len__(self) -> int:
        return len(self._lessons)

    def lesson_ids(self) -> list[str]:
        return list(self._lessons.keys())

    def get_lesson(self, lesson_id: str) -> dict[str, Any] | None:
        les = self._lessons.get(str(lesson_id or "").strip())
        return copy.deepcopy(les) if les is not None else None

    def apply_lesson_dict(self, lesson_id: str, new_lesson: Mapping[str, Any]) -> bool:
        """Stage a full lesson replace **forcing original id**. Never touches adapter."""
        lid = str(lesson_id or "").strip()
        if not lid or lid not in self._lessons:
            return False
        try:
            body = copy.deepcopy(dict(new_lesson))
            # Immutable id hard rule.
            body["id"] = self._original_ids.get(lid, lid)
            self._lessons[lid] = body
            self._staged.append(
                MergeItem(
                    kind="lesson",
                    id=lid,
                    summary=f"沙箱课更新 {lid}",
                    action_id="lesson.fill_empty",
                    scope={"lesson_id": lid, "section_id": self._section_of.get(lid, "")},
                    sandbox_payload=copy.deepcopy(body),
                )
            )
            return True
        except Exception:
            return False

    def mark_action(
        self,
        step: GoalStep,
        *,
        summary: str | None = None,
    ) -> None:
        """Record a non-mutating orchestration step for merge routing."""
        self._applied_steps.append(step.step_id)
        self._staged.append(
            MergeItem(
                kind="action",
                id=step.step_id,
                summary=summary or step.label,
                action_id=step.action_id,
                scope=dict(step.scope or {}),
                sandbox_payload=None,
            )
        )

    def stage_placeholder_fill(self, lesson_id: str) -> bool:
        """E3-B2: stage a **stub-filled** lesson in sandbox (id-preserving).

        Writes minimal content via ``build_stub_lesson`` so merge can apply
        LessonPatch without a second AI round-trip. Does not touch adapter.
        """
        return self.stage_stub_fill(lesson_id)

    def stage_stub_fill(self, lesson_id: str) -> bool:
        """Stage local stub lesson content into sandbox + merge items."""
        from src.backend.experience.goal_generate import build_stub_lesson

        lid = str(lesson_id or "").strip()
        les = self._lessons.get(lid)
        if les is None:
            return False
        try:
            forced_id = self._original_ids.get(lid, lid)
            body = build_stub_lesson(les, lesson_id=forced_id)
            return self._stage_lesson_body(lid, body, summary_hint=f"沙箱 stub {lid}")
        except Exception:
            return False

    def stage_real_fill(self, lesson_id: str, *, new_lesson: Mapping[str, Any]) -> bool:
        """E3-B3: stage a **real AI-generated** lesson into sandbox (id-preserving).

        Mirrors ``stage_stub_fill`` staging but takes *new_lesson* from the AI
        worker (``request_lesson_transform``). Does **not** tag
        ``meta.sandbox_stub_fill`` so ``payload_summary`` shows「生成」and the
        dialog tag distinguishes AI vs stub. Never touches adapter.
        """
        from src.backend.experience.goal_generate import is_lesson_payload_mergeable

        lid = str(lesson_id or "").strip()
        if not lid or lid not in self._lessons:
            return False
        try:
            forced_id = self._original_ids.get(lid, lid)
            body = copy.deepcopy(dict(new_lesson))
            # Immutable id hard rule — overrides any AI-returned id.
            body["id"] = forced_id
            if not is_lesson_payload_mergeable(body):
                return False
            return self._stage_lesson_body(lid, body, summary_hint=f"沙箱生成 {lid}")
        except Exception:
            return False

    def _stage_lesson_body(
        self,
        lid: str,
        body: Mapping[str, Any],
        *,
        summary_hint: str = "",
    ) -> bool:
        """Shared staging for stub + real fill: force id, store, append MergeItem."""
        from src.backend.experience.goal_generate import payload_summary

        try:
            body = dict(body)
            body["id"] = self._original_ids.get(lid, lid)
            self._lessons[lid] = body
            summary = payload_summary(body) or summary_hint or f"沙箱 {lid}"
            self._staged.append(
                MergeItem(
                    kind="lesson",
                    id=lid,
                    summary=summary,
                    action_id="lesson.fill_empty",
                    scope={
                        "lesson_id": lid,
                        "first_lesson_id": lid,
                        "section_id": self._section_of.get(lid, ""),
                        "merge_mode": "lesson_patch",
                    },
                    sandbox_payload=copy.deepcopy(body),
                )
            )
            return True
        except Exception:
            return False

    def run_plan_local(self, plan: GoalPlan) -> list[str]:
        """Apply local staging for each step. Returns list of step_ids applied.

        Does not call LLM. Unknown actions become notes.
        """
        self._goal_text = plan.goal_text
        applied: list[str] = []
        for step in plan.steps:
            aid = step.action_id
            if aid == "lesson.fill_empty":
                lid = str(
                    (step.scope or {}).get("lesson_id")
                    or (step.scope or {}).get("first_lesson_id")
                    or ""
                )
                if lid and self.stage_placeholder_fill(lid):
                    applied.append(step.step_id)
                    self._applied_steps.append(step.step_id)
                else:
                    self.mark_action(step, summary=f"待主路径填充：{step.label}")
                    applied.append(step.step_id)
            elif aid in (
                "validate.open_and_fix",
                "resource.fill_stubs",
                "listening.fill_gaps",
                "quality.campaign_worst_n",
                "soft.preview_hygiene",
                "lesson.balance",
                "resource.open_hygiene",
            ):
                self.mark_action(step)
                applied.append(step.step_id)
            else:
                self._notes.append(f"跳过未知步骤 {step.step_id}:{aid}")
        return applied

    def to_merge_plan(self) -> MergePlan:
        """Build a human-gated merge plan from staged items."""
        lesson_ids: list[str] = []
        section_ids: list[str] = []
        for item in self._staged:
            if item.kind == "lesson" and item.id and item.id not in lesson_ids:
                lesson_ids.append(item.id)
            sid = str((item.scope or {}).get("section_id") or "")
            if sid and sid not in section_ids:
                section_ids.append(sid)
        n_lesson = sum(1 for i in self._staged if i.kind == "lesson")
        n_action = sum(1 for i in self._staged if i.kind == "action")
        summary = (
            f"合并草案：{n_lesson} 课 · {n_action} 动作 · 须确认"
            + (f" · 目标「{self._goal_text}」" if self._goal_text else "")
        )
        return MergePlan(
            items=list(self._staged),
            lesson_ids=lesson_ids,
            section_ids=section_ids,
            summary=summary,
            requires_confirm=True,
            created_ts=time.time(),
            goal_text=self._goal_text,
        )

    def diff_summary(self) -> str:
        mp = self.to_merge_plan()
        lines = [mp.summary or "（空草案）"]
        for it in mp.items[:15]:
            lines.append(f"  · [{it.kind}] {it.summary}")
        if len(mp.items) > 15:
            lines.append(f"  …+{len(mp.items) - 15}")
        for n in self._notes[:5]:
            lines.append(f"注：{n}")
        return "\n".join(lines)

    def clear(self) -> None:
        self._lessons.clear()
        self._section_of.clear()
        self._original_ids.clear()
        self._staged.clear()
        self._applied_steps.clear()
        self._notes.clear()
        self._goal_text = ""


def adapter_lesson_fingerprint(adapter: Any, lesson_id: str) -> str | None:
    """Stable fingerprint of one lesson on the live adapter (for Q-06 tests)."""
    try:
        import json

        lid = str(lesson_id or "").strip()
        for _sid, les in _walk_lessons(list(getattr(adapter, "sections", None) or [])):
            if _lesson_id(les) == lid:
                return json.dumps(les, sort_keys=True, ensure_ascii=False)[:2000]
        return None
    except Exception:
        return None
