#!/usr/bin/env python3
"""E1 gate smoke — automated checks for Experience OS L4 readiness.

Maps experienceai.md §8 / §11 gate rows to *logical* regressions that can run
headless (no full human GUI click-through). Exit 0 = all automated checks
passed; human walkthrough items are printed as MANUAL.

Run from repo or tool/gui:

  QT_QPA_PLATFORM=offscreen python3 tool/gui/tests/experience_e1_gate_smoke.py
"""
from __future__ import annotations

import shutil
import sys
import tempfile
import time
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
_ROOT = _GUI.parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from tests._course_fixture import copy_turkish_course  # noqa: E402


def _ok(report: list[str], name: str, passed: bool, detail: str = "") -> bool:
    mark = "✅" if passed else "❌"
    line = f"{mark} {name}" + (f" — {detail}" if detail else "")
    report.append(line)
    print(line)
    return passed


def _manual(report: list[str], name: str) -> None:
    line = f"◻ MANUAL {name}"
    report.append(line)
    print(line)


def main() -> int:
    from tests._qtapp import qt_app

    qt_app()
    report: list[str] = []
    failed = 0

    print("=== Experience E1 Gate Smoke ===\n")

    # --- G1: open course → local context ≤3s + suggestions ---
    tmp = Path(tempfile.mkdtemp(prefix="e1_gate_"))
    try:
        course_dir = tmp / "turkish"
        copy_turkish_course(course_dir)

        from src.backend.course_adapter import CourseAdapter
        from src.backend.experience.context_bus import (
            build_experience_context,
            local_suggestions,
        )
        from src.application.experience_shell import ExperienceShell
        from src.backend.experience.timeline import ExperienceTimeline
        from src.backend.experience.why import why_explain
        from src.backend.experience.patch import item_patch_from_replace, apply_item_patch
        from src.backend.experience.intent_router import route_intent, SLASH_COMMANDS
        from src.widgets.preview_host import PreviewHost
        from src.application.commands import ApplyItemPatchCommand
        from PySide6.QtGui import QUndoStack

        adapter = CourseAdapter()
        adapter.load(course_dir)

        t0 = time.perf_counter()
        ctx = build_experience_context(adapter, include_quality=True, include_hygiene=True)
        elapsed_ms = (time.perf_counter() - t0) * 1000
        sugs = local_suggestions(ctx, limit=3)
        if not _ok(
            report,
            "G1 open→local context <3000ms",
            elapsed_ms < 3000,
            f"{elapsed_ms:.1f}ms lessons={ctx.lesson_count}",
        ):
            failed += 1
        if not _ok(
            report,
            "G1 suggestions non-empty or healthy course",
            bool(sugs) or ctx.healthy,
            f"n_sugs={len(sugs)} healthy={ctx.healthy}",
        ):
            failed += 1

        # --- G2: chip path = ItemPatch + undo, id immutable ---
        stage = {"id": "st", "items": [{"id": "q1", "prompt": "A", "runtimeType": "multipleChoice"}]}
        patch = item_patch_from_replace(
            stage["items"][0],
            {"id": "HACK", "prompt": "B", "runtimeType": "multipleChoice"},
        )
        stack = QUndoStack()
        stack.push(ApplyItemPatchCommand(stage, patch))
        id_ok = stage["items"][0]["id"] == "q1" and stage["items"][0]["prompt"] == "B"
        stack.undo()
        undo_ok = stage["items"][0]["prompt"] == "A"
        if not _ok(report, "G2 ItemPatch preserves id + undo", id_ok and undo_ok):
            failed += 1

        # --- G4: PreviewHost non-modal offer ---
        host_w = PreviewHost()
        applied = []
        host_w.offer(title="t", summary="s", apply_fn=lambda: applied.append(1))
        offer_ok = host_w.has_pending()
        host_w._on_apply()
        if not _ok(report, "G4 PreviewHost offer→apply", offer_ok and applied == [1]):
            failed += 1

        # --- G5: pin survives selection change ---
        shell = ExperienceShell(debounce_ms=0)
        shell.set_adapter(adapter)
        shell.set_selection(("lesson", "s1-l2") if any(
            True for s in adapter.sections for u in s.get("units", []) for l in u.get("lessons", []) if l.get("id") == "s1-l2"
        ) else ("section", adapter.sections[0]["id"]))
        # Use first lesson id from course
        first_lesson = None
        for s in adapter.sections:
            for u in s.get("units", []):
                for l in u.get("lessons", []):
                    first_lesson = l.get("id")
                    break
                if first_lesson:
                    break
            if first_lesson:
                break
        shell.set_selection(("lesson", first_lesson or "x"))
        shell.toggle_pin_selection()
        shell.set_selection(("section", adapter.sections[0]["id"]))
        ctx2 = shell.rebuild_now()
        pin_ok = ctx2 is not None and len(ctx2.pinned_refs) == 1
        shell.set_adapter(None)
        clear_ok = shell.pinned_refs == []
        if not _ok(report, "G5 pin survives selection; clear on adapter None", pin_ok and clear_ok):
            failed += 1

        # --- G6: timeline + why ---
        tl = ExperienceTimeline(maxlen=50)
        tl.record("chip.apply", "改题", action_id="item.rewrite", scope={"item_id": "q1"})
        tl.record("validate.fix", "批修", action_id="validate.open_and_fix")
        if not _ok(report, "G6 timeline recent", len(tl.recent(5)) == 2):
            failed += 1
        why = why_explain({"level": "error", "message": "dangling wordId w-x", "path": ""})
        if not _ok(report, "G6 why_explain dangling", why.rule_id == "dangling_word" and bool(why.summary)):
            failed += 1
        # why must not claim validate passed
        if not _ok(
            report,
            "G6 why does not claim validated",
            "已通过" not in why.detail and "passed" not in why.detail.lower(),
        ):
            failed += 1

        # --- G7: intent routes core slash ---
        for cmd, action in (
            ("/validate", "validate.open_and_fix"),
            ("/why", "app.why"),
            ("/pin", "app.pin"),
        ):
            intent = route_intent(cmd)
            if not _ok(report, f"G7 route {cmd}", intent is not None and intent.action_id == action):
                failed += 1
        if not _ok(report, "G7 slash table size ≥8", len(SLASH_COMMANDS) >= 8, str(len(SLASH_COMMANDS))):
            failed += 1

        # --- G9: Soft Autopilot default off + whitelist closed ---
        from src.application.settings import Settings

        from src.backend.experience.soft_autopilot import (
            SOFT_RULE_IDS,
            evaluate_soft_fixes,
        )

        if not _ok(
            report,
            "G9 soft_autopilot default off",
            Settings().experience_soft_autopilot is False,
        ):
            failed += 1
        # Whitelist closed: every fix produced by evaluate must live in
        # SOFT_RULE_IDS. Build a deliberately dirty adapter to exercise all
        # branches and assert none escape the whitelist.
        _dirty = type(
            "_Dirty",
            (),
            {
                "vocab": [
                    {
                        "id": "d1",
                        "term": "  a   b  ",
                        "translation": '"c"',
                        "pronunciation": "  d  ",
                        "tags": ["", "e"],
                    }
                ],
                "expressions": [
                    {"id": "d2", "term": "「f」", "translation": "g  h", "tags": []}
                ],
                "notify_resources_changed": lambda self: None,
            },
        )()
        dirty_batch = evaluate_soft_fixes(_dirty)
        produced = {f.rule_id for f in dirty_batch.fixes}
        whitelist_ok = produced.issubset(SOFT_RULE_IDS)
        if not _ok(
            report,
            "G9 soft whitelist closed",
            whitelist_ok and bool(produced),
            f"produced={sorted(produced)}",
        ):
            failed += 1

        # --- G10: C-20 dangerous-skill switch default off + closed set ---
        from src.backend.experience import (
            ACTIONS,
            DANGEROUS_ACTION_IDS,
            is_dangerous,
            is_dangerous_skill_allowed,
        )

        if not _ok(
            report,
            "G10 dangerous_skills default off",
            Settings().experience_allow_dangerous_skills is False,
        ):
            failed += 1
        if not _ok(
            report,
            "G10 accessor default off",
            is_dangerous_skill_allowed(Settings()) is False,
        ):
            failed += 1
        if not _ok(
            report,
            "G10 observer overrides flag on",
            is_dangerous_skill_allowed(
                Settings(
                    experience_allow_dangerous_skills=True, experience_mode="observer"
                )
            )
            is False,
        ):
            failed += 1
        if not _ok(
            report,
            "G10 flag on + copilot allowed",
            is_dangerous_skill_allowed(
                Settings(
                    experience_allow_dangerous_skills=True, experience_mode="copilot"
                )
            )
            is True,
        ):
            failed += 1
        # Closed set (v4.69): DANGEROUS_ACTION_IDS must equal the derived flags
        # and match the six structural-rewrite actions; set C is a strict subset.
        derived = frozenset(aid for aid, spec in ACTIONS.items() if spec.dangerous)
        from src.backend.experience.auto_apply import (
            AUTO_APPLY_DANGEROUS_WHEN_IMMERSIVE,
        )
        _dangerous_expected_v469 = frozenset(
            {
                "lesson.regenerate",
                "lesson.batch_regenerate",
                "unit.regenerate",
                "unit.batch_regenerate",
                "lesson.batch_set_template",
                "course.outline_shells",
            }
        )
        if not _ok(
            report,
            "G10 dangerous set closed (v4.69 six structural rewrites)",
            DANGEROUS_ACTION_IDS == derived == _dangerous_expected_v469,
            f"DANGEROUS_ACTION_IDS={sorted(DANGEROUS_ACTION_IDS)}",
        ):
            failed += 1
        if not _ok(
            report,
            "G10 set C strict subset of dangerous",
            (
                AUTO_APPLY_DANGEROUS_WHEN_IMMERSIVE <= DANGEROUS_ACTION_IDS
                and "course.outline_shells" not in AUTO_APPLY_DANGEROUS_WHEN_IMMERSIVE
            ),
            f"C={sorted(AUTO_APPLY_DANGEROUS_WHEN_IMMERSIVE)}",
        ):
            failed += 1

        # --- G11: C-07 policy single source of truth ---
        from src.backend.experience import can_dispatch, resolve_policy
        from src.backend.experience.actions import ActionSpec

        obs_policy = resolve_policy(
            Settings(
                experience_mode="observer",
                experience_allow_dangerous_skills=True,
                experience_soft_autopilot=True,
            )
        )
        if not _ok(
            report,
            "G11 observer policy 三零",
            obs_policy.is_observer
            and not obs_policy.allow_dangerous
            and not obs_policy.allow_soft,
        ):
            failed += 1
        _dangerous_spec = ActionSpec(
            "test.dangerous", "危险测试", needs_confirm=True, dangerous=True
        )
        ok_obs, _ = can_dispatch(_dangerous_spec, obs_policy)
        ok_cop_off, _ = can_dispatch(
            _dangerous_spec, resolve_policy(Settings(experience_mode="copilot"))
        )
        ok_cop_on, _ = can_dispatch(
            _dangerous_spec,
            resolve_policy(
                Settings(experience_mode="copilot", experience_allow_dangerous_skills=True)
            ),
        )
        if not _ok(
            report,
            "G11 can_dispatch dangerous gating",
            not ok_obs and not ok_cop_off and ok_cop_on,
        ):
            failed += 1
        # v4.69: under immersive full-auto, dangerous dispatches even with switch off
        # (C-20 retarget: lock only applies outside full-auto).
        ok_imm_off, _ = can_dispatch(
            _dangerous_spec, resolve_policy(Settings(experience_mode="immersive"))
        )
        if not _ok(
            report,
            "G11 immersive dangerous dispatches (switch off)",
            ok_imm_off,
        ):
            failed += 1
        # observer 零 AI 写：普通写 action 被拒，只读 action 与 app.* 放行。
        _write_spec = ActionSpec("lesson.fill_empty", "填充空课", needs_confirm=True)
        _read_spec = ActionSpec(
            "resource.open_hygiene", "打开资源", needs_confirm=False
        )
        w_ok, _ = can_dispatch(_write_spec, obs_policy)
        r_ok, _ = can_dispatch(_read_spec, obs_policy)
        app_ok, _ = can_dispatch(
            ActionSpec("app.save", "保存", needs_confirm=False), obs_policy
        )
        if not _ok(
            report,
            "G11 observer 零 AI 写 / 只读与 app.* 放行",
            not w_ok and r_ok and app_ok,
        ):
            failed += 1

        # --- G12: M-08 daily AI budget circuit ---
        budget_p = resolve_policy(
            Settings(experience_daily_ai_budget=3),
            usage_today={"requests": 3},
        )
        fill_ok, fill_reason = can_dispatch(_write_spec, budget_p)
        save_ok, _ = can_dispatch(
            ActionSpec("app.save", "保存", needs_confirm=False), budget_p
        )
        soft_ok, _ = can_dispatch(
            ActionSpec("soft.preview_hygiene", "规则规范化", needs_confirm=True),
            budget_p,
        )
        if not _ok(
            report,
            "G12 budget 超限拦 AI 写 / app.save+soft 放行",
            (
                budget_p.budget_exceeded
                and not fill_ok
                and "配额" in fill_reason
                and save_ok
                and soft_ok
            ),
        ):
            failed += 1
        unlimited = resolve_policy(
            Settings(experience_daily_ai_budget=0),
            usage_today={"requests": 999},
        )
        if not _ok(
            report,
            "G12 budget 0=不限制",
            not unlimited.budget_exceeded and unlimited.allow_ai_skill,
        ):
            failed += 1

        # --- G13: E3-A Goal default off + observer zero + sandbox isolation ---
        from src.backend.experience.planner import plan_from_context
        from src.backend.experience.sandbox import CourseSandbox

        goal_off = resolve_policy(Settings())
        goal_spec = ActionSpec("goal.run", "Goal", needs_confirm=True)
        g_ok, g_reason = can_dispatch(goal_spec, goal_off)
        goal_obs = resolve_policy(
            Settings(experience_goal_enabled=True, experience_mode="observer")
        )
        if not _ok(
            report,
            "G13 goal 默认关 + observer 零",
            (
                not goal_off.allow_goal
                and not goal_off.allow_autonomous_write
                and not g_ok
                and "Goal" in g_reason
                and not goal_obs.allow_goal
            ),
        ):
            failed += 1
        # Q-06: sandbox staging does not mutate adapter sections.
        sec = {
            "id": "s1",
            "units": [
                {
                    "id": "u1",
                    "lessons": [
                        {
                            "id": "s1-l1",
                            "name": "L",
                            "template": "intro",
                            "content": {"subLessons": []},
                        }
                    ],
                }
            ],
        }
        from types import SimpleNamespace
        import json as _json

        ad = SimpleNamespace(sections=[sec])
        before = _json.dumps(ad.sections, sort_keys=True)
        box = CourseSandbox.from_adapter(ad, lesson_ids=["s1-l1"])
        box.stage_placeholder_fill("s1-l1")
        after = _json.dumps(ad.sections, sort_keys=True)
        plan = plan_from_context(
            SimpleNamespace(
                empty_lessons=["s1-l1"],
                validate_error_count=0,
                hygiene={},
                listening_gaps=[],
                imbalanced_lessons=[],
            ),
            goal_text="空课",
        )
        if not _ok(
            report,
            "G13 sandbox 不脏主课 + plan 非空",
            before == after and len(plan) >= 1 and box.to_merge_plan().requires_confirm,
        ):
            failed += 1

        # --- G14: E3-B1 filter_merge_plan + publish.brief + goal_llm default off ---
        from src.backend.experience.sandbox import (
            MergeItem,
            MergePlan,
            filter_merge_plan,
            merge_item_key,
        )
        from src.backend.experience.publish_brief import build_publish_brief
        from src.backend.experience.goal_llm import is_goal_llm_enabled

        mp = MergePlan(
            items=[
                MergeItem(
                    kind="lesson",
                    id="a",
                    summary="A",
                    action_id="lesson.fill_empty",
                    scope={"lesson_id": "a"},
                ),
                MergeItem(
                    kind="action",
                    id="b",
                    summary="B",
                    action_id="validate.open_and_fix",
                ),
            ]
        )
        k0 = merge_item_key(mp.items[0])
        filtered = filter_merge_plan(mp, [k0])
        brief = build_publish_brief(
            SimpleNamespace(
                validate_error_count=1,
                validate_warning_count=0,
                empty_lesson_count=0,
                lesson_count=1,
                section_count=1,
                hygiene={},
            )
        )
        if not _ok(
            report,
            "G14 filter + brief blocks + goal_llm off",
            (
                len(filtered) == 1
                and filtered.requires_confirm
                and brief.get("blocks_publish") is True
                and not is_goal_llm_enabled(Settings())
            ),
        ):
            failed += 1

        # --- G15: E3-B2 stub payload mergeable + sandbox isolation ---
        import copy as _copy

        from src.backend.experience.goal_generate import (
            build_stub_lesson,
            is_lesson_payload_mergeable,
        )

        empty_les = {
            "id": "g15-l1",
            "name": "E",
            "template": "intro",
            "content": {"subLessons": []},
        }
        ad2 = SimpleNamespace(
            sections=[
                {
                    "id": "s1",
                    "units": [
                        {"id": "u1", "lessons": [_copy.deepcopy(empty_les)]}
                    ],
                }
            ]
        )
        before2 = _json.dumps(ad2.sections, sort_keys=True)
        box2 = CourseSandbox.from_adapter(ad2, lesson_ids=["g15-l1"])
        ok_stub = box2.stage_stub_fill("g15-l1")
        after2 = _json.dumps(ad2.sections, sort_keys=True)
        mp2 = box2.to_merge_plan()
        payload_ok = bool(
            mp2.items
            and is_lesson_payload_mergeable(mp2.items[0].sandbox_payload)
        )
        stub = build_stub_lesson(empty_les, lesson_id="g15-l1")
        if not _ok(
            report,
            "G15 stub fill 不脏主课 + payload 可 Patch",
            ok_stub and before2 == after2 and payload_ok and stub["id"] == "g15-l1",
        ):
            failed += 1

        # --- G16: E3-B3 real AI payload mergeable + sandbox isolation ---
        def _real_ai(lid: str) -> dict:
            return {
                "id": lid,
                "name": f"AI {lid}",
                "template": "intro",
                "content": {
                    "subLessons": [
                        {
                            "id": f"{lid}-sub1",
                            "stages": [
                                {
                                    "id": f"{lid}-st1",
                                    "items": [
                                        {"id": f"{lid}-i1", "runtimeType": "showWord", "wordId": "w"}
                                    ],
                                }
                            ],
                        }
                    ]
                },
            }

        empty_les3 = {
            "id": "g16-l1",
            "name": "E",
            "template": "intro",
            "content": {"subLessons": []},
        }
        ad3 = SimpleNamespace(
            sections=[
                {
                    "id": "s1",
                    "units": [
                        {"id": "u1", "lessons": [_copy.deepcopy(empty_les3)]}
                    ],
                }
            ]
        )
        before3 = _json.dumps(ad3.sections, sort_keys=True)
        box3 = CourseSandbox.from_adapter(ad3, lesson_ids=["g16-l1"])
        ok_real = bool(
            box3.stage_real_fill("g16-l1", new_lesson=_real_ai("g16-l1"))
        )
        after3 = _json.dumps(ad3.sections, sort_keys=True)
        mp3 = box3.to_merge_plan()
        real_payload_ok = bool(
            mp3.items
            and is_lesson_payload_mergeable(mp3.items[0].sandbox_payload)
            and mp3.items[0].sandbox_payload["id"] == "g16-l1"
            and not bool(
                (mp3.items[0].sandbox_payload.get("meta") or {}).get("sandbox_stub_fill")
            )
        )
        if not _ok(
            report,
            "G16 real fill 不脏主课 + payload 可 Patch + id 默保 + 非 stub",
            ok_real and before3 == after3 and real_payload_ok and mp3.requires_confirm,
        ):
            failed += 1

    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    # --- G17': set B ∩ set C = ∅ and C ⊆ DANGEROUS_ACTION_IDS (real check) ---
    from src.backend.experience.auto_apply import (
        AUTO_APPLY_DANGEROUS_WHEN_IMMERSIVE as _set_c,
        IMMERSIVE_ABSOLUTE_DENY_ACTIONS as _set_b,
        deny_and_auto_disjoint as _g17_disjoint,
        is_auto_apply_allowed as _is_auto,
    )
    if not _ok(
        report,
        "G17' B ∩ C = ∅ and C ⊆ dangerous",
        bool(_g17_disjoint()) and _set_b.isdisjoint(_set_c),
        f"B={sorted(_set_b)} C={sorted(_set_c)}",
    ):
        failed += 1

    # --- G18': C auto under immersive; non-C dangerous (outline_shells) not auto ---
    from src.backend.experience.actions import get_action as _get_action

    _imm_pol = resolve_policy(Settings(experience_mode="immersive"))
    _c_auto = _is_auto("lesson.regenerate", _imm_pol)
    _nonc_auto = _is_auto("course.outline_shells", _imm_pol)
    _nonc_dispatch = can_dispatch(_get_action("course.outline_shells"), _imm_pol)[0]
    if not _ok(
        report,
        "G18' C auto / non-C dangerous confirm under immersive",
        _c_auto and not _nonc_auto and _nonc_dispatch,
        f"c_auto={_c_auto} nonc_auto={_nonc_auto} nonc_dispatch={_nonc_dispatch}",
    ):
        failed += 1

    print("\n--- Human walkthrough still required ---")
    for name in (
        "教师模式芯片：真实 LLM 生成 → PreviewHost Enter（需 API Key）",
        "Dock 批修 / 清待补 端到端确认 Diff",
        "⌘K 历史重放点击",
        "无 API Key 时完整手编一节课并保存",
        "工坊不打开即可完成微观编辑会话（体验指标 ≥80%）",
    ):
        _manual(report, name)

    print("\n=== Summary ===")
    auto = [r for r in report if r.startswith("✅") or r.startswith("❌")]
    print(f"Automated: {sum(1 for r in auto if r.startswith('✅'))}/{len(auto)} passed")
    if failed:
        print(f"FAILED ({failed})")
        return 1
    print("AUTOMATED GATE CHECKS PASSED - E1 manual passed; MANUAL rows above are E1 regression reminders (E2 next)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
