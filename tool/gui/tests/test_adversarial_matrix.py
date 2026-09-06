"""§13.6 adversarial matrix (v4.54) — pure L1, no Qt widgets.

Coverage map (experienceai §13.6 D1–D20). Rows marked *direct* are asserted
in this file; others are indexed to existing modules so the matrix stays a
single audit surface without duplicating heavy hosts.

| ID  | Scenario                              | Coverage |
|-----|---------------------------------------|----------|
| D1  | Patch 换题改 id                       | ``test_experience_patch`` + ``test_o13``; *direct* field/item force |
| D2  | 无 preview 直接 merge                 | *direct* all tree-write actions need_confirm |
| D3  | mute permanent + 重启                 | *direct* settings round-trip → no Ambient |
| D4  | 双击芯片同 item Guard                 | ``test_conflict_guard`` + ``test_o13`` |
| D5  | Soft 规则试图改 id                    | ``test_soft_autopilot``; *direct* SOFT_RULE_IDS closed |
| D6  | finish 错误 job_id                    | ``test_o13`` + ``test_job_registry`` |
| D7  | 诊断中途换课 stale                    | ``test_experience_shell`` diagnose stale |
| D9  | Soft 非白名单 rule_id                 | G9 + *direct* whitelist closed |
| D10 | Observer 半关                         | ``test_observer_mode`` + G11 |
| D11 | flyout 取消误杀 worker                | *direct* job_tray source: cancel disabled |
| D12 | dangerous 派发闸                      | ``test_experience_actions`` + G10; *direct* empty set |
| D13 | LLM 回包外 id / field                 | *direct* batch_polish + pos parse drops |
| D14 | Timeline/telemetry 泄密               | *direct* closed scopes (OCR/voice/polish/attachments) |
| D15 | Goal 自治写默认 False（immersive P3 可开） | *direct* policy allow_autonomous_write |
| D29 | Immersive 禁区 B 永不 auto            | *direct* auto_apply + can_dispatch |
| D30 | observer 覆盖 immersive               | *direct* policy |
| D31 | 一键降档停 auto                       | *direct* demote + policy |
| D32 | opaque 下 auto 仍入 Undo/apply        | ``test_immersive_p3p6`` PreviewHost |
| D33 | 无 toast 时 Undo 可用                 | *direct* SoftHygiene path / stack |
| D16 | 资源批改字段白名单                    | *direct* POLISH_FIELDS closed + id not in |
| D17 | surface 污染 polish 建议              | *direct* non-resources surface empty |
| D18 | 换课清会话                            | ``test_course_lifecycle``; *direct* clear_experience_session OCR |
| D19 | 日预算闸                              | *direct* budget blocks AI write, soft/app pass |
| D20 | field_patch 拒 id                     | *direct* PatchError |
| D23 | outline_shells 写操作+默认关          | *direct* needs_confirm + is_outline_shell_enabled |
| D24 | 大纲解析注入                          | *direct* parse 永不抛 + id 去重 + 无幻影 unit |
| D26 | A3 ② defer 不 nag                     | *direct* DeferStore 冷却期内不回灌 + dismiss>=3 永久 |
| D27 | A3 ① Ambient 不抢焦                   | *direct* AmbientBanner 源码无 setFocus |
| D28 | A3 ① accept 经 dispatch（不脏盘）     | *direct* _on_ambient_accepted -> _on_experience_suggestion |

Does not construct MainWindow. Prefer pure / duck hosts. Keep free of
heavy widget APIs so the module stays L1-fast (no widget construction).
"""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import MagicMock

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.application.settings import Settings  # noqa: E402
from src.backend.experience.actions import (  # noqa: E402
    ACTIONS,
    APP_BUILTIN_PREFIX,
    DANGEROUS_ACTION_IDS,
    get_action,
)
from src.backend.experience.attachments import build_attachment_snapshot  # noqa: E402
from src.backend.experience.context_bus import ExperienceContext  # noqa: E402
from src.backend.experience.ocr_skill import build_ocr_suggestion  # noqa: E402
from src.backend.experience.patch import PatchError, field_patch, item_patch_from_replace  # noqa: E402
from src.backend.experience.policy import can_dispatch, resolve_policy  # noqa: E402
from src.backend.experience.pos_skill import parse_pos_alignment_reply  # noqa: E402
from src.backend.experience.proactive import (  # noqa: E402
    MUTE_PERMANENT,
    MuteState,
    evaluate_ambient,
    make_mute,
)
from src.backend.experience.resource_batch_skill import (  # noqa: E402
    POLISH_FIELDS,
    parse_batch_polish_reply,
)
from src.backend.experience.soft_autopilot import SOFT_RULE_IDS  # noqa: E402
from src.backend.experience.suggestions import p2_resources  # noqa: E402
from src.backend.experience.voice_skill import build_voice_metrics  # noqa: E402


# Readonly / open-only actions that may set needs_confirm=False (D2 mirror of
# test_experience_actions; keep in sync when adding navigation-only skills).
_OPEN_ONLY = frozenset(
    {
        "resource.open_hygiene",
        "resource.dedupe_suggest",
        "help.fix",
        "course.compare_sections",
        "goal.plan",
        "goal.expand",
        "publish.brief",
        "git.commit_message",
        "git.explain_diff",
        "attachment.open_in_workshop",
        "textbook.ocr_suggest",
        "textbook.open_workshop",
        "memory.clear_author",
    }
)


def _ctx(**kwargs) -> ExperienceContext:
    defaults = dict(
        healthy=False,
        validate_error_count=2,
        empty_lesson_count=1,
        empty_lessons=["l-empty"],
        hygiene={"placeholder_count": 0},
        quality_by_section={},
    )
    defaults.update(kwargs)
    return ExperienceContext(**defaults)


def _make_qsettings(values: dict | None = None) -> MagicMock:
    store = dict(values or {})
    qs = MagicMock()

    def _value(key: str, default=None):
        return store.get(key, default)

    def _set_value(key: str, value) -> None:
        store[key] = value

    qs.value = _value
    qs.setValue = _set_value
    qs.contains = lambda key: key in store
    qs.remove = lambda key: store.pop(key, None)
    qs._store = store
    return qs


def _settings(**kwargs) -> Settings:
    return Settings(**kwargs)


# ---------------------------------------------------------------------------
# D1 / D20 — id integrity
# ---------------------------------------------------------------------------


class D1PatchIdForceTest(unittest.TestCase):
    def test_item_patch_forces_original_id(self) -> None:
        """D1: item_patch_from_replace keeps old id even if new_item rewrites it."""
        old = {"id": "q1", "prompt": "a", "options": ["x", "y"]}
        new = {"id": "HACKED", "prompt": "b", "options": ["x", "y"]}
        patch = item_patch_from_replace(old, new)
        self.assertEqual(patch.item_id, "q1")
        self.assertEqual(patch.new_item.get("id"), "q1")

    def test_field_patch_rejects_id(self) -> None:
        """D20: field_patch on id is forbidden."""
        target = {"id": "w1", "term": "su", "translation": "水"}
        with self.assertRaises(PatchError):
            field_patch(target, "id", "evil", target_kind="vocab")


# ---------------------------------------------------------------------------
# D2 — write actions need confirm
# ---------------------------------------------------------------------------


class D2WriteActionsNeedConfirmTest(unittest.TestCase):
    def test_all_tree_write_actions_need_confirm(self) -> None:
        """D2: no silent tree-write action path via registry."""
        for spec in ACTIONS.values():
            with self.subTest(action_id=spec.action_id):
                if spec.action_id.startswith(APP_BUILTIN_PREFIX):
                    self.assertFalse(spec.needs_confirm, spec.action_id)
                    continue
                if spec.action_id in _OPEN_ONLY:
                    self.assertFalse(spec.needs_confirm, spec.action_id)
                    continue
                self.assertTrue(
                    spec.needs_confirm,
                    f"{spec.action_id} must needs_confirm (D2 silent-merge ban)",
                )

    def test_known_write_skills_confirm(self) -> None:
        # v4.69: lesson.regenerate is now dangerous (set C); the rest are not.
        _dangerous_in_list = {"lesson.regenerate"}
        for aid in (
            "resource.batch_polish",
            "resource.align_pos_tags",
            "resource.resolve_term_conflicts",
            "lesson.regenerate",
            "unit.spiral_vocab",
            "goal.run",
            "soft.preview_hygiene",
        ):
            spec = get_action(aid)
            self.assertIsNotNone(spec, aid)
            assert spec is not None
            self.assertTrue(spec.needs_confirm, aid)
            if aid in _dangerous_in_list:
                self.assertTrue(spec.dangerous, aid)
            else:
                self.assertFalse(spec.dangerous, aid)


# ---------------------------------------------------------------------------
# D3 — mute permanent survives restart
# ---------------------------------------------------------------------------


class D3MutePermanentRestartTest(unittest.TestCase):
    def test_mute_permanent_round_trip_blocks_ambient(self) -> None:
        """D3: permanent mute → QSettings dump/load → still no Ambient."""
        mute = make_mute(MUTE_PERMANENT)
        blob = json.dumps(mute.to_dict(), ensure_ascii=False)
        s = _settings(experience_mute_json=blob)
        qs = _make_qsettings({"recent_repos": "[]"})
        s.save_to_qsettings(qs)
        loaded = Settings.load_from_qsettings(qs)
        self.assertTrue(loaded.experience_mute_json)
        restored = MuteState.from_dict(json.loads(loaded.experience_mute_json))
        self.assertEqual(restored.level, MUTE_PERMANENT)
        self.assertTrue(restored.is_active())
        # Errors present would otherwise yield a P0 Ambient proposal.
        prop = evaluate_ambient(_ctx(), mute=restored)
        self.assertIsNone(prop)


# ---------------------------------------------------------------------------
# D5 / D9 — Soft whitelist closed
# ---------------------------------------------------------------------------


class D5D9SoftWhitelistTest(unittest.TestCase):
    def test_soft_rule_ids_closed_hygiene_only(self) -> None:
        """D5/D9: SOFT_RULE_IDS is a closed hygiene set (no semantic rewrite)."""
        self.assertTrue(SOFT_RULE_IDS)
        for rid in SOFT_RULE_IDS:
            self.assertTrue(
                rid.startswith("hygiene."),
                f"non-hygiene soft rule leaked: {rid}",
            )
        # id-mutating rules must never appear
        for banned in ("rename_id", "change_id", "rewrite_semantics", "ai."):
            self.assertFalse(any(banned in r for r in SOFT_RULE_IDS))
        # v4.62 P5: zero-width strip is hygiene-only
        self.assertIn("hygiene.strip_zero_width", SOFT_RULE_IDS)


class D21MemoryPersistDefaultOffTest(unittest.TestCase):
    """v4.62 P9: project/author memory disk defaults off."""

    def test_persist_flags_default_false(self) -> None:
        from src.application.settings import Settings

        s = Settings()
        self.assertFalse(s.experience_memory_persist_project)
        self.assertFalse(s.experience_memory_persist_author)


class D22ItemSimilarNeedsConfirmTest(unittest.TestCase):
    """v4.62 P9: item.similar is a write skill with confirm."""

    def test_item_similar_needs_confirm(self) -> None:
        from src.backend.experience.actions import get_action

        spec = get_action("item.similar")
        self.assertIsNotNone(spec)
        assert spec is not None
        self.assertTrue(spec.needs_confirm)
        self.assertFalse(spec.dangerous)


class D23OutlineShellGateTest(unittest.TestCase):
    """v4.64 A4: course.outline_shells is a write skill, default-off gated."""

    def test_needs_confirm_and_dangerous(self) -> None:
        from src.backend.experience.actions import get_action

        spec = get_action("course.outline_shells")
        self.assertIsNotNone(spec)
        assert spec is not None
        self.assertTrue(spec.needs_confirm)
        # v4.69: structural shell creation is dangerous; NOT in set C (always confirms,
        # even under immersive) — the largest-blast-radius structural write.
        self.assertTrue(spec.dangerous)

    def test_default_off_conservative(self) -> None:
        from src.backend.experience.outline_skill import is_outline_shell_enabled
        from src.application.settings import Settings

        # Missing/None settings -> False; fresh Settings default False.
        self.assertFalse(is_outline_shell_enabled(None))
        self.assertFalse(is_outline_shell_enabled(Settings()))
        self.assertFalse(Settings().experience_outline_shell)


class D24OutlineInjectionTest(unittest.TestCase):
    """v4.64 A4: hostile outline text never breaks the parser / ids stay clean."""

    def test_malicious_and_overlong_input_never_raises(self) -> None:
        from src.backend.experience.outline_skill import parse_bullet_outline

        hostile = (
            "\x00\x01\x1f 控制字符\n"
            + "长" * 5000
            + "\n  - "
            + "x" * 5000
            + "\n<script>alert(1)</script>\n  - {json: injection}\n"
            + "删除全部\n  - '; DROP TABLE lessons;--\n"
        )
        o = parse_bullet_outline(hostile, existing_ids=[])
        # produces structure without raising; every id non-empty + unique
        ids = [u["id"] for u in o["units"]] + [
            l["id"] for u in o["units"] for l in u["lessons"]
        ]
        self.assertTrue(all(ids))
        self.assertEqual(len(ids), len(set(ids)))

    def test_empty_result_has_no_phantom_units(self) -> None:
        from src.backend.experience.outline_skill import (
            outline_to_shell_section,
            parse_bullet_outline,
        )

        o = parse_bullet_outline("\n\n# only comments\n# nothing\n")
        self.assertEqual(o["units"], [])
        shell = outline_to_shell_section(o, section_id="s1")
        self.assertEqual(shell["units"], [])


# ---------------------------------------------------------------------------
# D11 — source contracts (keep L1; no widget import)
# ---------------------------------------------------------------------------


class D11SourceContractTest(unittest.TestCase):
    def test_d11_flyout_cancel_disabled_in_source(self) -> None:
        """D11: JobTray cancel action is disabled (no worker kill)."""
        path = _GUI / "src" / "widgets" / "job_tray.py"
        text = path.read_text(encoding="utf-8")
        self.assertIn("setEnabled(False)", text)
        self.assertIn("job_cancel_requested", text)
        self.assertIn("暂不可取消", text)


# ---------------------------------------------------------------------------
# D12 — dangerous set closed (6 structural-rewrite actions, v4.69)
# ---------------------------------------------------------------------------

# The six actions marked dangerous in v4.69 (C-20 retarget). Set C is a strict
# subset (course.outline_shells is dangerous but deliberately NOT in C).
_DANGEROUS_ACTIONS_V469 = frozenset(
    {
        "lesson.regenerate",
        "lesson.batch_regenerate",
        "unit.regenerate",
        "unit.batch_regenerate",
        "lesson.batch_set_template",
        "course.outline_shells",
    }
)


class D12DangerousGateTest(unittest.TestCase):
    def test_dangerous_set_matches_v469(self) -> None:
        self.assertEqual(DANGEROUS_ACTION_IDS, _DANGEROUS_ACTIONS_V469)
        # Only the six structural-rewrite actions are dangerous; everything else isn't.
        for aid, spec in ACTIONS.items():
            if aid in _DANGEROUS_ACTIONS_V469:
                self.assertTrue(spec.dangerous, aid)
            else:
                self.assertFalse(spec.dangerous, aid)

    def test_defaults_deny_dangerous(self) -> None:
        p = resolve_policy(_settings())
        self.assertFalse(p.allow_dangerous)
        # Even with flag on, observer still denies.
        p_obs = resolve_policy(
            _settings(
                experience_mode="observer",
                experience_allow_dangerous_skills=True,
            )
        )
        self.assertFalse(p_obs.allow_dangerous)


# ---------------------------------------------------------------------------
# D13 — LLM closed-set parse drops foreign ids/fields
# ---------------------------------------------------------------------------


class D13LlmClosedParseTest(unittest.TestCase):
    def test_batch_polish_drops_foreign_ids_and_fields(self) -> None:
        out = parse_batch_polish_reply(
            {
                "entries": [
                    {"id": "w9", "field": "translation", "value": "x"},
                    {"id": "w1", "field": "term", "value": "hack"},
                    {"id": "w1", "field": "id", "value": "evil"},
                    {"id": "w1", "field": "translation", "value": "  "},
                    {"id": "w1", "field": "translation", "value": "你好"},
                    {"id": "w1", "field": "pos", "value": "not-a-pos"},
                ]
            },
            allowed_ids={"w1"},
            allowed_fields=POLISH_FIELDS,
        )
        self.assertEqual(out, {("w1", "translation"): "你好"})
        blob = str(out)
        self.assertNotIn("hack", blob)
        self.assertNotIn("evil", blob)

    def test_pos_alignment_drops_invalid_and_empty(self) -> None:
        out = parse_pos_alignment_reply(
            {
                "entries": [
                    {"id": "w1", "pos": "noun"},
                    {"id": "w2", "pos": "banana"},
                    {"id": "", "pos": "verb"},
                    {"id": "w3", "pos": ""},
                    {"id": "w4", "pos": "VERB"},  # normalize ok
                ]
            }
        )
        self.assertEqual(out, {"w1": "noun", "w4": "verb"})
        self.assertNotIn("w2", out)
        self.assertNotIn("banana", json.dumps(out))


# ---------------------------------------------------------------------------
# D14 — closed scopes / metrics (no term/path/prompt/transcript)
# ---------------------------------------------------------------------------


class D14RedactionClosedScopeTest(unittest.TestCase):
    def test_ocr_suggestion_scope_closed(self) -> None:
        sug = build_ocr_suggestion("att-abc", "image", "ok")
        assert sug is not None
        scope = sug["scope"]
        self.assertEqual(set(scope.keys()), {"ref_id", "kind", "status"})
        blob = json.dumps(scope, ensure_ascii=False)
        self.assertNotIn("path", blob)
        self.assertNotIn("/", blob)  # no filesystem path fragment

    def test_voice_metrics_closed_no_transcript(self) -> None:
        m = build_voice_metrics("ok", ok=True, engine="sphinx")
        self.assertEqual(set(m.keys()), {"status", "ok", "engine"})
        blob = json.dumps(m, ensure_ascii=False)
        self.assertNotIn("transcript", blob)
        self.assertNotIn("secret speech", blob)

    def test_attachment_snapshot_no_body(self) -> None:
        snap = build_attachment_snapshot(
            [
                {
                    "name": "讲义.pdf",
                    "kind": "pdf",
                    "content": "SECRET_BODY_TEXT",
                    "temp_path": "/tmp/secret/path.pdf",
                }
            ]
        )
        blob = json.dumps(snap, ensure_ascii=False)
        self.assertNotIn("SECRET_BODY_TEXT", blob)
        self.assertNotIn("/tmp/secret", blob)
        for row in snap:
            self.assertNotIn("content", row)
            self.assertNotIn("temp_path", row)
            # name is basename-only per M-01 (may appear in Dock, not body)
            self.assertNotIn("SECRET", str(row.get("name", "")))

    def test_polish_scope_shape_has_no_term_key(self) -> None:
        """Collector scope uses count + entry_ids only (§14.5.3)."""
        ctx = SimpleNamespace(
            surface="resources",
            multi_selection=[
                SimpleNamespace(kind="vocab", id="w1"),
                SimpleNamespace(kind="vocab", id="w2"),
            ],
        )
        hits = p2_resources.collect(ctx)
        self.assertEqual(len(hits), 1)
        scope = hits[0]["scope"]
        self.assertEqual(set(scope.keys()), {"count", "entry_ids"})
        self.assertNotIn("term", scope)
        self.assertNotIn("translation", scope)


# ---------------------------------------------------------------------------
# D15 — Goal never autonomous
# ---------------------------------------------------------------------------


class D15GoalNeverAutonomousTest(unittest.TestCase):
    def test_allow_autonomous_write_false_outside_immersive(self) -> None:
        """D15: outside immersive, autonomous write stays False even with goal flags.

        P3 immersive full-auto may set allow_autonomous_write True (design
        divergence); covered by D29–D31 / test_immersive_p3p6.
        """
        for kwargs in (
            {},
            {"experience_goal_enabled": True},
            {"experience_goal_enabled": True, "experience_goal_llm": True},
            {
                "experience_goal_enabled": True,
                "experience_allow_dangerous_skills": True,
                "experience_mode": "copilot",
            },
            {"experience_mode": "active"},
        ):
            with self.subTest(**kwargs):
                p = resolve_policy(_settings(**kwargs))
                self.assertFalse(p.allow_autonomous_write)

    def test_goal_default_off(self) -> None:
        s = Settings()
        self.assertFalse(bool(getattr(s, "experience_goal_enabled", False)))
        p = resolve_policy(s)
        self.assertFalse(p.allow_goal)


# ---------------------------------------------------------------------------
# D16 — polish field whitelist
# ---------------------------------------------------------------------------


class D16PolishWhitelistTest(unittest.TestCase):
    def test_polish_fields_closed(self) -> None:
        self.assertEqual(set(POLISH_FIELDS), {"translation", "pronunciation", "pos"})
        self.assertNotIn("id", POLISH_FIELDS)
        self.assertNotIn("term", POLISH_FIELDS)


# ---------------------------------------------------------------------------
# D17 — surface-aware polish
# ---------------------------------------------------------------------------


class D17SurfacePolishTest(unittest.TestCase):
    def test_tree_surface_no_polish_suggestion(self) -> None:
        ctx = SimpleNamespace(
            surface="tree",
            multi_selection=[
                SimpleNamespace(kind="vocab", id="w1"),
                SimpleNamespace(kind="vocab", id="w2"),
            ],
        )
        self.assertEqual(p2_resources.collect(ctx), [])

    def test_resources_surface_emits_polish(self) -> None:
        ctx = SimpleNamespace(
            surface="resources",
            multi_selection=[SimpleNamespace(kind="vocab", id="w1")],
        )
        hits = p2_resources.collect(ctx)
        self.assertEqual(hits[0]["action_id"], "resource.batch_polish")

    def test_mixed_kinds_no_suggestion(self) -> None:
        ctx = SimpleNamespace(
            surface="resources",
            multi_selection=[
                SimpleNamespace(kind="vocab", id="w1"),
                SimpleNamespace(kind="lesson", id="l1"),
            ],
        )
        self.assertEqual(p2_resources.collect(ctx), [])


# ---------------------------------------------------------------------------
# D18 — clear_experience_session clears OCR hint
# ---------------------------------------------------------------------------


class D18LifecycleClearTest(unittest.TestCase):
    def test_clear_session_disables_ocr_hint(self) -> None:
        from src.application.course_lifecycle import clear_experience_session

        exp = MagicMock()
        host = SimpleNamespace(
            experience=exp,
            experience_memory=MagicMock(),
            experience_metrics=MagicMock(),
            experience_timeline=MagicMock(),
            job_tray=MagicMock(),
            conflict_guard=MagicMock(),
            ambient_banner=MagicMock(),
            experience_dock=MagicMock(),
            _goal_sandbox=object(),
            _focus_pins=set(),
            _ai_scope_keys=set(),
            _shown_suggestion_keys=set(),
            _current_node_ref=None,
            _teacher_focused_item_id=None,
        )
        # Provide optional attrs used by clear_experience_session
        for name in (
            "job_tray",
            "conflict_guard",
            "experience_metrics",
            "experience_timeline",
            "experience_memory",
            "ambient_banner",
            "experience_dock",
        ):
            getattr(host, name)  # ensure present
        clear_experience_session(host)
        exp.set_ocr_enabled.assert_called_with(False)


# ---------------------------------------------------------------------------
# D19 — budget gate
# ---------------------------------------------------------------------------


class D19BudgetGateTest(unittest.TestCase):
    def test_budget_blocks_ai_write_allows_soft_and_app(self) -> None:
        p = resolve_policy(
            _settings(experience_daily_ai_budget=2),
            usage_today={"requests": 2},
        )
        self.assertTrue(p.budget_exceeded)
        write = get_action("resource.batch_polish")
        soft = get_action("soft.preview_hygiene")
        save = get_action("app.save")
        assert write and soft and save
        ok_w, _ = can_dispatch(write, p)
        ok_s, _ = can_dispatch(soft, p)
        ok_a, _ = can_dispatch(save, p)
        self.assertFalse(ok_w)
        self.assertTrue(ok_s)
        self.assertTrue(ok_a)

    def test_budget_zero_unlimited(self) -> None:
        p = resolve_policy(
            _settings(experience_daily_ai_budget=0),
            usage_today={"requests": 999},
        )
        self.assertFalse(p.budget_exceeded)
        write = get_action("resource.batch_polish")
        assert write
        ok, _ = can_dispatch(write, p)
        self.assertTrue(ok)


# ---------------------------------------------------------------------------
# Index integrity — matrix stays honest
# ---------------------------------------------------------------------------


class MatrixIndexIntegrityTest(unittest.TestCase):
    def test_o13_module_cross_references_matrix(self) -> None:
        """Keep dual maps from drifting: o13 docstring should name this file."""
        o13 = (_GUI / "tests" / "test_o13_save_guards.py").read_text(encoding="utf-8")
        self.assertIn("§13.6", o13)
        self.assertIn("test_adversarial_matrix", o13)

    def test_actions_registry_non_empty(self) -> None:
        self.assertGreaterEqual(len(ACTIONS), 20)


# ---------------------------------------------------------------------------
# D26 / D27 / D28 - A3 ①② companion Ambient (v4.66 P4)
# ---------------------------------------------------------------------------


class D26DeferNoNagTest(unittest.TestCase):
    def test_cooldown_hides_and_escalation_permanent(self) -> None:
        """D26: a deferred proposal is hidden during cooldown (no nag) and
        escalates to permanent after MAX_DISMISS (no resurface)."""
        from datetime import datetime, timedelta, timezone

        from src.backend.experience.defer_store import MAX_DISMISS, DeferStore
        from src.backend.experience.proactive import (
            evaluate_ambient_batch,
            proposal_id_for,
        )

        now = datetime(2026, 7, 24, 12, 0, tzinfo=timezone.utc)
        ctx = ExperienceContext()
        pid = proposal_id_for("validate.open_and_fix", {"error_count": 2})
        sug = [{
            "priority": 0,
            "title": "x",
            "action_id": "validate.open_and_fix",
            "scope": {"error_count": 2},
        }]
        store = DeferStore()
        store.add(pid, "validate.open_and_fix", now=now)
        # D26a: during cooldown the proposal is hidden (no nag).
        self.assertEqual(
            evaluate_ambient_batch(ctx, suggestions=sug, defer_store=store, now=now),
            [],
        )
        # D26b: after MAX_DISMISS defers -> permanent marker, dropped from store.
        store.add(pid, now=now)
        r3 = store.add(pid, now=now)
        self.assertEqual(r3.dismiss_count, MAX_DISMISS)
        self.assertEqual(r3.re_surface_after_iso, "")
        self.assertIsNone(store.get(pid))


class D27AmbientNoFocusStealTest(unittest.TestCase):
    def test_banner_source_has_no_setfocus(self) -> None:
        """D27: AmbientBanner must never steal focus (source contract)."""
        import inspect

        from src.widgets.ambient_banner import AmbientBanner

        self.assertNotIn("setFocus", inspect.getsource(AmbientBanner))


class D28AmbientAcceptDispatchTest(unittest.TestCase):
    def test_accept_routes_through_dispatch_funnel(self) -> None:
        """D28: accept does not write directly - it routes via
        ``_on_experience_suggestion`` (the dispatch funnel enforcing
        needs_confirm + Undo), never pushing a merge command itself."""
        import inspect

        from src.application.ambient_controller import on_ambient_accepted

        src = inspect.getsource(on_ambient_accepted)
        self.assertIn("_on_experience_suggestion", src)
        self.assertNotIn("MergeAiSectionCommand", src)
        self.assertNotIn("undo_stack.push", src)


# ---------------------------------------------------------------------------
# D29–D33 — immersive ladder (P3–P6)
# ---------------------------------------------------------------------------


class D29ImmersiveDenyBTest(unittest.TestCase):
    def test_deny_b_never_auto(self) -> None:
        from src.backend.experience.auto_apply import is_auto_apply_allowed
        from src.backend.experience.actions import ActionSpec
        from src.backend.experience.policy import can_dispatch, resolve_policy

        p = resolve_policy(_settings(experience_mode="immersive"))
        self.assertFalse(is_auto_apply_allowed("git.push", p))
        ok, _ = can_dispatch(
            ActionSpec("git.push", "push", dangerous=True), p
        )
        self.assertFalse(ok)


class D30ObserverCoversImmersiveTest(unittest.TestCase):
    def test_observer_zeros_immersive_flags(self) -> None:
        p = resolve_policy(
            _settings(
                experience_mode="observer",
                experience_immersive_full_auto=True,
                experience_soft_autopilot=True,
            )
        )
        self.assertFalse(p.allow_full_auto_apply)
        self.assertFalse(p.allow_soft)
        self.assertFalse(p.allow_autonomous_write)


class D31DemoteStopsAutoTest(unittest.TestCase):
    def test_demote_to_copilot(self) -> None:
        from src.application.presence_mode import demote_to_copilot

        s = _settings(experience_mode="immersive")
        self.assertTrue(resolve_policy(s).allow_full_auto_apply)
        demote_to_copilot(s)
        self.assertEqual(s.experience_mode, "copilot")
        self.assertFalse(resolve_policy(s).allow_full_auto_apply)


class D33UndoWithoutToastTest(unittest.TestCase):
    def test_soft_command_still_undoable_concept(self) -> None:
        """D33: Soft hygiene still uses Undo command (source contract)."""
        import inspect

        from src.application.save_host import apply_soft_before_save

        src = inspect.getsource(apply_soft_before_save)
        self.assertIn("SoftHygieneCommand", src)
        self.assertIn("undo_stack", src)


if __name__ == "__main__":
    unittest.main()
