"""Policy resolution for Experience OS dispatch (C-07 + M-08 budget).

Pure Python, no Qt, never raises. This module is the **single source of truth**
for the trust-boundary decisions that gate every Experience dispatch:

* mode (observer / copilot / active / immersive) + **presence_level** (0–3)
* dangerous-skill allowance (删 id / 跨节改写 / Hard import / publish)
* Soft Autopilot allowance (observer short-circuit)
* **C-06 LLM intent** allowance (⌘K NL classify; default off; observer zero)
* autonomous write / Goal allowance (E3, default off)
* cross-section rewrite allowance (default off; dangerous gate)
* **M-08 daily AI budget** (usage_today.requests vs settings limit)

P1–P3 (intrusiveness ladder): four modes + ``presence_level``. When
``presence_level >= 2`` (active/immersive), an **active bundle** ORs Soft /
ambient live / defer resurface / campaign auto without mutating
settings flags. When ``presence_level == 3`` (immersive), ``allow_full_auto_apply``
/ ``runtime_opaque`` / ``allow_autonomous_write`` may open (P3; intentional
divergence from experienceai §6.2 confirm-always). Observer still zeros
everything.

Before C-07 these decisions were scattered across ``actions.is_dangerous_skill_allowed``
and inline reads of ``experience_mode`` / ``experience_soft_autopilot`` in
``experience_skills_mixin`` and ``app``. Those helpers still exist (external
tests depend on their signatures) but now delegate here, so there is one
place to audit and one place to extend when E3 adds the Goal dimension.

红线：
* 默认安全档位不变 —— observer 三零、dangerous/soft 默认关。
* 日预算默认 0 = 关闭熔断；超限只拦 AI 写 skill，不拦手编/保存/app.*/soft.*。
* 本模块永不抛 —— 缺失/损坏 settings 安全降级到最保守决策。
* 不改判 validate、不写树、不记密钥。
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Mapping

from src.backend.experience.actions import ActionSpec, APP_BUILTIN_PREFIX


OBSERVER = "observer"
COPILOT = "copilot"
ACTIVE = "active"
IMMERSIVE = "immersive"
SOVEREIGN = "sovereign"

EXPERIENCE_MODES: frozenset[str] = frozenset(
    {OBSERVER, COPILOT, ACTIVE, IMMERSIVE, SOVEREIGN}
)
PRESENCE_LEVEL_BY_MODE: dict[str, int] = {
    OBSERVER: 0,
    COPILOT: 1,
    ACTIVE: 2,
    IMMERSIVE: 3,
    SOVEREIGN: 4,
}

# M-08: which usage_today key counts toward the daily budget.
BUDGET_USAGE_KEY = "requests"


def normalize_experience_mode(mode: Any) -> str:
    """Map raw mode string to a legal EXPERIENCE_MODES value; never raises."""
    try:
        m = str(mode or COPILOT).strip().lower()
    except Exception:
        return COPILOT
    if m in EXPERIENCE_MODES:
        return m
    return COPILOT


@dataclass(frozen=True)
class PolicyDecision:
    """Resolved trust-boundary decision for one dispatch context.

    Read this rather than the raw settings flags at every dispatch site.
    """

    mode: str  # observer | copilot | active | immersive
    allow_dangerous: bool  # dangerous-skill gate (is_dangerous_skill_allowed 真源)
    allow_soft: bool  # Soft Autopilot gate (observer 强制 False)
    allow_autonomous_write: bool  # E3 Hard auto-import；P1 仍恒 False
    scope_cross_section: bool  # 跨节改写是否允许（默认 False）
    # M-08 daily budget (unit = telemetry usage_today["requests"])
    allow_ai_skill: bool = True  # False when budget_exceeded
    budget_exceeded: bool = False
    budget_limit: int = 0  # 0 = unlimited / circuit open
    budget_used: int = 0
    # C-06 ⌘K NL classify (default off; observer False; budget-aware)
    allow_llm_intent: bool = False
    # E3-A Goal planner/sandbox entry (default off; observer False; not autonomous write)
    allow_goal: bool = False
    # P1 ladder: 0=observer 1=copilot 2=active 3=immersive
    presence_level: int = 1
    # P2 active bundle (also on for immersive; effective flags, not settings)
    allow_ambient_live: bool = False
    allow_defer_resurface: bool = False
    allow_campaign_auto: bool = False
    # P3 immersive full-auto + runtime opacity (settings can turn off)
    allow_full_auto_apply: bool = False
    runtime_opaque: bool = False
    # Sovereign tier: synchronous sovereign takeover mode
    sovereign_mode_enabled: bool = False

    @property
    def is_observer(self) -> bool:
        return int(self.presence_level) == 0

    @property
    def is_active_bundle(self) -> bool:
        """True when presence_level >= 2 and not observer (active or immersive)."""
        return int(self.presence_level) >= 2 and not self.is_observer

    @property
    def budget_remaining(self) -> int | None:
        """Remaining calls when limit > 0; None when unlimited."""
        if self.budget_limit <= 0:
            return None
        return max(0, int(self.budget_limit) - int(self.budget_used))


def _resolve_settings(settings: Any | None) -> Any | None:
    """Return settings as-is. ``None`` means "no settings" -> conservative.

    We deliberately do NOT fall back to the live app's ``current_settings``
    here: that path can return stale, test-mutated state and would make
    ``resolve_policy(None)`` non-deterministic. Callers that want the live
    app settings must pass them explicitly (e.g. ``self._settings_obj``);
    the thin helpers in ``actions`` keep their own
    ``current_settings`` fallback for backward compatibility before delegating.
    """
    return settings


def _budget_used_from_usage(usage_today: Mapping[str, Any] | None) -> int:
    """Extract today's request count; never raises."""
    if not usage_today or not isinstance(usage_today, Mapping):
        return 0
    try:
        return max(0, int(usage_today.get(BUDGET_USAGE_KEY) or 0))
    except Exception:
        return 0


def _budget_limit_from_settings(s: Any) -> int:
    try:
        return max(0, int(getattr(s, "experience_daily_ai_budget", 0) or 0))
    except Exception:
        return 0


def resolve_policy(
    settings: Any | None = None,
    *,
    action_id: str | None = None,
    usage_today: Mapping[str, Any] | None = None,
) -> PolicyDecision:
    """Build a ``PolicyDecision`` from settings (+ optional usage); never raises.

    Missing / malformed fields degrade to the safest value (off / observer-safe).
    ``action_id`` is accepted for forward-compat (per-action budget / scope) but
    does not change the base decision today.
    ``usage_today`` should be the int dict from ``usage_today_from_summary``
    (keys include ``requests``). When omitted, budget is treated as not exceeded
    (fail-open on missing usage so local editing is never bricked).
    """
    del action_id  # reserved
    s = _resolve_settings(settings)
    if s is None:
        # No settings at all (headless / very early init) -> most conservative.
        return PolicyDecision(
            mode=COPILOT,
            allow_dangerous=False,
            allow_soft=False,
            allow_llm_intent=False,
            allow_autonomous_write=False,
            allow_goal=False,
            scope_cross_section=False,
            allow_ai_skill=True,
            budget_exceeded=False,
            budget_limit=0,
            budget_used=0,
            presence_level=1,
            allow_ambient_live=False,
            allow_defer_resurface=False,
            allow_campaign_auto=False,
            allow_full_auto_apply=False,
            runtime_opaque=False,
        )
    try:
        mode = normalize_experience_mode(getattr(s, "experience_mode", COPILOT))
    except Exception:
        mode = COPILOT
    presence_level = int(PRESENCE_LEVEL_BY_MODE.get(mode, 1))

    try:
        dangerous_flag = bool(getattr(s, "experience_allow_dangerous_skills", False))
    except Exception:
        dangerous_flag = False
    try:
        soft_flag = bool(getattr(s, "experience_soft_autopilot", False))
    except Exception:
        soft_flag = False
    try:
        llm_intent_flag = bool(getattr(s, "experience_llm_intent", False))
    except Exception:
        llm_intent_flag = False
    try:
        goal_flag = bool(getattr(s, "experience_goal_enabled", False))
    except Exception:
        goal_flag = False
    try:
        ambient_live_flag = bool(getattr(s, "experience_ambient_live", False))
    except Exception:
        ambient_live_flag = False
    try:
        defer_flag = bool(getattr(s, "experience_defer_resurface", False))
    except Exception:
        defer_flag = False
    # P3 sub-switches: default True when immersive so missing attrs still enable.
    try:
        full_auto_flag = getattr(s, "experience_immersive_full_auto", True)
        full_auto_flag = True if full_auto_flag is None else bool(full_auto_flag)
    except Exception:
        full_auto_flag = True
    try:
        opaque_flag = getattr(s, "experience_immersive_opaque", True)
        opaque_flag = True if opaque_flag is None else bool(opaque_flag)
    except Exception:
        opaque_flag = True
    try:
        sovereign_flag = bool(getattr(s, "experience_sovereign_enabled", False))
    except Exception:
        sovereign_flag = False

    is_observer = presence_level == 0
    sovereign = (mode == SOVEREIGN or sovereign_flag) and not is_observer
    if sovereign:
        presence_level = 4
        active_bundle = True
        immersive = True
        sovereign_mode_enabled = True
    else:
        sovereign_mode_enabled = False

    # P2 active bundle: presence >= 2 ORs presence features without mutating settings.
    active_bundle = presence_level >= 2 and not is_observer
    immersive = presence_level >= 3 and not is_observer
    # observer: zero AI side-effects — dangerous / soft / llm_intent forced False.
    allow_dangerous = dangerous_flag and not is_observer
    allow_soft = (soft_flag or active_bundle) and not is_observer
    allow_ambient_live = (ambient_live_flag or active_bundle) and not is_observer
    allow_defer_resurface = (defer_flag or active_bundle) and not is_observer
    allow_campaign_auto = bool(active_bundle)
    # P3: full auto + opacity + autonomous write under immersive / sovereign.
    allow_full_auto_apply = bool(immersive and full_auto_flag)
    runtime_opaque = bool(immersive and opaque_flag)
    # When full auto, dangerous registry actions may dispatch if flag on OR full auto
    # (G18': confirm skipped in UI; B still denied in can_dispatch).
    if allow_full_auto_apply:
        allow_dangerous = True
    # 跨节改写属危险范畴：需 dangerous 开启且非 observer（full auto 亦开）。
    scope_cross_section = allow_dangerous
    allow_autonomous_write = bool(allow_full_auto_apply)

    # M-08: daily budget (0 = off). Fail-open when usage missing.
    budget_limit = _budget_limit_from_settings(s)
    budget_used = _budget_used_from_usage(usage_today)
    budget_exceeded = bool(budget_limit > 0 and budget_used >= budget_limit)
    allow_ai_skill = not budget_exceeded
    allow_llm_intent = (
        llm_intent_flag and not is_observer and allow_ai_skill
    )
    # E3-A: Goal entry (plan/sandbox) — default off; not autonomous write.
    allow_goal = goal_flag and not is_observer and allow_ai_skill

    return PolicyDecision(
        mode=mode,
        allow_dangerous=allow_dangerous,
        allow_soft=allow_soft,
        allow_llm_intent=allow_llm_intent,
        allow_autonomous_write=allow_autonomous_write,
        allow_goal=allow_goal,
        scope_cross_section=scope_cross_section,
        allow_ai_skill=allow_ai_skill,
        budget_exceeded=budget_exceeded,
        budget_limit=budget_limit,
        budget_used=budget_used,
        presence_level=presence_level,
        allow_ambient_live=allow_ambient_live,
        allow_defer_resurface=allow_defer_resurface,
        allow_campaign_auto=allow_campaign_auto,
        allow_full_auto_apply=allow_full_auto_apply,
        runtime_opaque=runtime_opaque,
        sovereign_mode_enabled=sovereign_mode_enabled,
    )


def can_dispatch(spec: ActionSpec | None, policy: PolicyDecision) -> tuple[bool, str]:
    """Decide whether ``spec`` may dispatch under ``policy``.

    Returns ``(allowed, deny_reason)``. ``deny_reason`` is empty when allowed;
    otherwise a human-readable reason for the status bar / lock dialog.

    Semantics:
    * ``app.*`` built-ins (save/undo/why/pin/help) always pass — they are
      explicit user window commands, not AI tree-writing actions.
    * ``resource.open_hygiene`` / other ``needs_confirm=False`` read-only
      actions pass even in observer (they do not write the tree).
    * ``soft.*`` local hygiene passes budget gate (zero network).
    * dangerous actions require ``policy.allow_dangerous`` **only outside
      full-auto** (copilot/active); under immersive/sovereign dangerous actions
      dispatch and set C partitions auto-vs-confirm (see
      ``auto_apply.is_auto_apply_allowed``).
    * In observer mode, any tree-writing AI action (``needs_confirm=True`` and
      not ``app.*``) is denied — zero AI writes (S-15).
    * M-08: when ``budget_exceeded``, network AI write skills (``needs_confirm``
      and not soft.*/app.*) are denied.
    * P3: immersive absolute deny set B always blocked.
    """
    if spec is None:
        return False, "未知技能"
    action_id = spec.action_id or ""
    if action_id.startswith(APP_BUILTIN_PREFIX):
        return True, ""
    try:
        from src.backend.experience.auto_apply import is_denied_immersive

        if is_denied_immersive(action_id):
            return False, "该操作在 Immersive 禁区（不可自动执行）"
    except Exception:
        pass
    # E3-A: goal.* requires allow_goal (default off); still needs_confirm for run.
    # P3: full auto also unlocks goal path when allow_autonomous_write.
    if action_id.startswith("goal."):
        if not getattr(policy, "allow_goal", False) and not getattr(
            policy, "allow_autonomous_write", False
        ):
            return False, "Goal 规划已关闭（设置 ▸ 体验 OS 中开启；Observer 下不可用）"
        return True, ""
    # C-20 retarget (v4.69): dangerous lock 仅在非 full-auto（copilot/active）
    # 生效。immersive/sovereign 下 dangerous 派发——C 成员 auto+Undo、非 C
    # dangerous 落 confirm（由 ``is_auto_apply_allowed`` + dispatch else 分流）。
    if (
        spec.dangerous
        and not policy.allow_dangerous
        and not getattr(policy, "allow_full_auto_apply", False)
    ):
        return False, "危险技能已锁定（删 id / 跨节改写 / Hard import），默认关闭"
    # observer: 零 AI 写。非 app.* 且 needs_confirm 的写 action 一律拒。
    if policy.is_observer and spec.needs_confirm:
        return False, "观察者模式不执行 AI 写操作（零侧效应）"
    # M-08 budget: block AI write skills only (soft.* is local rules).
    if (
        policy.budget_exceeded
        and spec.needs_confirm
        and not action_id.startswith("soft.")
    ):
        return (
            False,
            f"今日 AI 配额已用尽（{policy.budget_used}/{policy.budget_limit}）",
        )
    return True, ""
