"""C-10 Goal planner — local-first DAG from Context + goal text (E3-A).

Pure Python, no Qt / network. Expands a short author goal (or implicit
health context) into an ordered list of :class:`GoalStep` that reuses the
existing ``ACTIONS`` skill ids. LLM expand is out of scope for E3-A
(source always ``\"local\"``).

红线：只规划，不写树；不删 id；步骤 action_id 优先落在已实现闭集。
"""
from __future__ import annotations

import time
from dataclasses import asdict, dataclass, field
from typing import Any, Mapping, Sequence


@dataclass(frozen=True)
class GoalStep:
    """One node in the goal DAG."""

    step_id: str
    action_id: str
    label: str
    scope: dict[str, Any] = field(default_factory=dict)
    depends_on: tuple[str, ...] = ()
    checkpoint: bool = False

    def to_dict(self) -> dict[str, Any]:
        d = asdict(self)
        d["depends_on"] = list(self.depends_on)
        return d


@dataclass
class GoalPlan:
    """Planned skill sequence for one author goal."""

    goal_text: str
    steps: list[GoalStep] = field(default_factory=list)
    source: str = "local"  # local | llm (E3-B)
    created_ts: float = 0.0
    notes: list[str] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        return {
            "goal_text": self.goal_text,
            "steps": [s.to_dict() for s in self.steps],
            "source": self.source,
            "created_ts": self.created_ts,
            "notes": list(self.notes),
        }

    @property
    def lesson_ids(self) -> list[str]:
        out: list[str] = []
        for s in self.steps:
            lid = str((s.scope or {}).get("lesson_id") or (s.scope or {}).get("first_lesson_id") or "")
            if lid and lid not in out:
                out.append(lid)
        return out

    def __len__(self) -> int:
        return len(self.steps)


# Keyword → preferred primary action (substring match on goal text).
_GOAL_KEYWORDS: tuple[tuple[tuple[str, ...], str], ...] = (
    (("空课", "填充", "fill empty", "填课"), "lesson.fill_empty"),
    (("校验", "修错", "修错误", "validate", "fix error"), "validate.open_and_fix"),
    (("待补", "stubs", "词条"), "resource.fill_stubs"),
    (("听力", "listening"), "listening.fill_gaps"),
    (("战役", "低质", "质量", "campaign"), "quality.campaign_worst_n"),
    (("规范化", "hygiene", "soft"), "soft.preview_hygiene"),
    (("配比", "balance"), "lesson.balance"),
)


def _ctx_get(ctx: Any, name: str, default: Any = None) -> Any:
    if ctx is None:
        return default
    if isinstance(ctx, Mapping):
        return ctx.get(name, default)
    return getattr(ctx, name, default)


def _detect_focus_actions(goal_text: str) -> list[str] | None:
    """Return preferred action ids from NL, or None for full health plan."""
    t = (goal_text or "").strip()
    if not t:
        return None
    hits: list[str] = []
    for words, aid in _GOAL_KEYWORDS:
        if any(w in t for w in words):
            if aid not in hits:
                hits.append(aid)
    return hits or None


def plan_from_context(
    ctx: Any = None,
    *,
    goal_text: str = "",
    max_fill_lessons: int = 5,
    max_steps: int = 12,
) -> GoalPlan:
    """Build a local GoalPlan from ExperienceContext-like *ctx* + goal text.

    Never raises. Empty health + empty goal → plan with notes only.
    """
    try:
        return _plan_from_context_impl(
            ctx,
            goal_text=goal_text,
            max_fill_lessons=max_fill_lessons,
            max_steps=max_steps,
        )
    except Exception as exc:
        return GoalPlan(
            goal_text=str(goal_text or ""),
            steps=[],
            source="local",
            created_ts=time.time(),
            notes=[f"规划失败：{exc.__class__.__name__}"],
        )


def _plan_from_context_impl(
    ctx: Any,
    *,
    goal_text: str,
    max_fill_lessons: int,
    max_steps: int,
) -> GoalPlan:
    text = (goal_text or "").strip() or "改善课程健康"
    plan = GoalPlan(
        goal_text=text,
        steps=[],
        source="local",
        created_ts=time.time(),
        notes=[],
    )
    focus = _detect_focus_actions(goal_text)
    max_steps = max(1, int(max_steps))
    max_fill = max(0, int(max_fill_lessons))

    empty = list(_ctx_get(ctx, "empty_lessons") or [])
    err_n = int(_ctx_get(ctx, "validate_error_count") or 0)
    hygiene = _ctx_get(ctx, "hygiene") or {}
    if not isinstance(hygiene, Mapping):
        hygiene = {}
    ph = int(hygiene.get("placeholder_count") or 0)
    listening = list(_ctx_get(ctx, "listening_gaps") or [])
    imbalanced = list(_ctx_get(ctx, "imbalanced_lessons") or [])

    def want(aid: str) -> bool:
        return focus is None or aid in focus

    steps: list[GoalStep] = []
    n = 0

    def add(
        action_id: str,
        label: str,
        scope: dict[str, Any] | None = None,
        *,
        depends_on: Sequence[str] = (),
        checkpoint: bool = False,
    ) -> str | None:
        nonlocal n
        if len(steps) >= max_steps:
            return None
        n += 1
        sid = f"s{n}"
        steps.append(
            GoalStep(
                step_id=sid,
                action_id=action_id,
                label=label,
                scope=dict(scope or {}),
                depends_on=tuple(depends_on),
                checkpoint=checkpoint,
            )
        )
        return sid

    # P0 validate
    if want("validate.open_and_fix") and err_n > 0:
        add(
            "validate.open_and_fix",
            f"修复 {err_n} 个校验错误",
            {"error_count": err_n},
            checkpoint=True,
        )

    # P1 empty lessons (one step per lesson, capped)
    if want("lesson.fill_empty") and empty:
        prev: str | None = None
        for i, lid in enumerate(empty[:max_fill]):
            lid_s = str(lid or "").strip()
            if not lid_s:
                continue
            sid = add(
                "lesson.fill_empty",
                f"填充空课 {lid_s}",
                {"lesson_id": lid_s, "first_lesson_id": lid_s},
                depends_on=(prev,) if prev else (),
                checkpoint=(i == min(len(empty), max_fill) - 1),
            )
            if sid:
                prev = sid
        if len(empty) > max_fill:
            plan.notes.append(f"另有 {len(empty) - max_fill} 节空课未列入（上限 {max_fill}）")

    # P2 stubs
    if want("resource.fill_stubs") and ph > 0:
        add(
            "resource.fill_stubs",
            f"清待补词条（{ph}）",
            {"placeholder_count": ph},
            checkpoint=True,
        )

    # Listening gaps
    if want("listening.fill_gaps") and listening:
        add(
            "listening.fill_gaps",
            f"补全听力缺口（{len(listening)}）",
            {"gap_count": len(listening)},
        )

    # Balance / campaign (lower priority unless focused)
    if want("lesson.balance") and imbalanced:
        first = imbalanced[0] if imbalanced else {}
        lid = ""
        if isinstance(first, Mapping):
            lid = str(first.get("lesson_id") or "")
        add(
            "lesson.balance",
            f"调整题型配比（{len(imbalanced)} 课）",
            {"lesson_id": lid, "count": len(imbalanced)},
        )

    if want("quality.campaign_worst_n") and (
        focus is not None or (err_n == 0 and not empty and ph == 0)
    ):
        # Only auto-add campaign when user asked or course looks "healthy but weak"
        weak = _ctx_get(ctx, "quality_by_section") or {}
        if focus is not None or weak:
            add(
                "quality.campaign_worst_n",
                "打开低质战役",
                {},
                checkpoint=True,
            )

    if want("soft.preview_hygiene") and focus is not None:
        add("soft.preview_hygiene", "规则规范化（预览）", {})

    plan.steps = steps
    if not steps:
        plan.notes.append("当前 Context 未发现可自动编排的健康问题；可改写目标关键词（空课/校验/待补）")
    return plan


def _parse_max_fill(goal_text: str, default: int = 5) -> int:
    """Raise fill cap when author asks for all empties."""
    t = (goal_text or "").strip()
    if any(w in t for w in ("全部空课", "所有空课", "填满", "all empty", "全部填充")):
        return 20
    if any(w in t for w in ("多填", "尽量多")):
        return 10
    return max(0, int(default))


def expand_goal_local(
    ctx: Any = None,
    *,
    goal_text: str = "",
    max_steps: int = 16,
) -> GoalPlan:
    """K-09 partial: richer local expansion than bare plan_from_context.

    - Parses fill cap from goal text
    - When goal is broad (「改善」「冲刺」「发布前」), includes multi-skill health plan
    - Annotates notes with expansion source
    Never raises; never calls LLM.
    """
    try:
        text = (goal_text or "").strip()
        broad = (not text) or any(
            w in text
            for w in (
                "改善",
                "冲刺",
                "发布前",
                "健康",
                "一键",
                "全部",
                "整体",
                "全面",
            )
        )
        # Broad goals: no keyword focus filter (pass empty keywords path via
        # plan_from_context with empty-looking generic text when broad).
        plan_text = text if text and not broad else (text or "改善课程健康")
        # When broad and user also said 空课, still let keyword work — use original.
        if broad and text and not any(
            w in text for w in ("空课", "校验", "待补", "听力", "配比", "战役")
        ):
            # Force unfocused health plan
            plan_text = ""
        max_fill = _parse_max_fill(text, default=5)
        plan = plan_from_context(
            ctx,
            goal_text=plan_text if plan_text else "改善课程健康",
            max_fill_lessons=max_fill,
            max_steps=max_steps,
        )
        # Re-label goal_text to original author intent
        if text:
            plan.goal_text = text
        plan.source = "local"
        plan.notes = list(plan.notes or [])
        plan.notes.insert(0, f"expand_goal_local · max_fill={max_fill} · steps={len(plan)}")
        if broad:
            plan.notes.append("宽目标：按课程健康全量编排（校验→空课→待补…）")
        return plan
    except Exception as exc:
        return GoalPlan(
            goal_text=str(goal_text or ""),
            notes=[f"expand 失败：{exc.__class__.__name__}"],
            created_ts=time.time(),
            source="local",
        )


def format_plan_summary(plan: GoalPlan, *, max_lines: int = 20) -> str:
    """Human-readable plan for dialogs / status. Never raises."""
    try:
        lines = [f"目标：{plan.goal_text}", f"来源：{plan.source} · {len(plan)} 步"]
        for s in plan.steps[: max(0, int(max_lines))]:
            dep = f" ←{','.join(s.depends_on)}" if s.depends_on else ""
            ck = " ◆" if s.checkpoint else ""
            lines.append(f"  {s.step_id}. [{s.action_id}] {s.label}{dep}{ck}")
        if len(plan.steps) > max_lines:
            lines.append(f"  …另有 {len(plan.steps) - max_lines} 步")
        for note in plan.notes[:5]:
            lines.append(f"注：{note}")
        return "\n".join(lines)
    except Exception:
        return "（计划摘要不可用）"
