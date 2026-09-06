"""§13.6 adversarial matrix (v4.54) — pure L1, no Qt widgets.

Coverage map (experienceai §13.6 D1–D33). Most rows are *indexed* to their
owning test module (the single source of truth for that invariant); the rows
marked *direct* keep an assertion here because no continuous test covers the
exact invariant (combo paths / closed-set directions / source contracts):

| ID  | Scenario                              | Coverage |
|-----|---------------------------------------|----------|
| D1  | Patch 换题改 id                       | ``test_experience_patch`` |
| D2  | 无 preview 直接 merge                 | ``test_experience_actions`` write need_confirm |
| D3  | mute permanent + 重启                 | *direct* settings round-trip → no Ambient |
| D4  | 双击芯片同 item Guard                 | ``test_conflict_guard`` |
| D5  | Soft 规则试图改 id                    | ``test_soft_autopilot``; *direct* SOFT_RULE_IDS hygiene-only |
| D6  | finish 错误 job_id                    | ``test_job_registry`` |
| D7  | 诊断中途换课 stale                    | ``test_experience_shell`` diagnose stale |
| D9  | Soft 非白名单 rule_id                 | G9 + *direct* whitelist closed |
| D10 | Observer 半关                         | G11 |
| D11 | flyout 取消误杀 worker                | *direct* job_tray source: cancel disabled |
| D12 | dangerous 派发闸                      | ``test_experience_actions`` six-rewrite set + gate |
| D13 | LLM 回包外 id / field                 | ``test_experience_batch_polish`` + ``test_experience_align_pos`` |
| D14 | Timeline/telemetry 泄密               | *direct* closed scopes (OCR/voice/polish/attachments) |
| D15 | Goal 自治写默认 False（immersive P3 可开） | ``test_policy`` + ``test_goal_sandbox`` |
| D16 | 资源批改字段白名单                    | ``test_experience_batch_polish`` drops id/term |
| D17 | surface 污染 polish 建议              | ``test_experience_batch_polish`` surface cases |
| D18 | 换课清会话                            | ``test_course_lifecycle``; *direct* clear_experience_session OCR hint |
| D19 | 日预算闸                              | ``test_policy`` budget matrix |
| D20 | field_patch 拒 id                     | ``test_experience_patch`` |
| D23 | outline_shells 写操作+默认关          | ``test_experience_outline_shells`` |
| D24 | 大纲解析注入                          | ``test_experience_outline_shells`` never-raises + ids unique |
| D26 | A3 ② defer 不 nag                     | ``test_experience_defer_resurface`` + ``test_defer_store`` MAX_DISMISS |
| D27 | A3 ① Ambient 不抢焦                   | *direct* AmbientBanner 源码无 setFocus |
| D28 | A3 ① accept 经 dispatch（不脏盘）     | *direct* _on_ambient_accepted -> _on_experience_suggestion |
| D29 | Immersive 禁区 B 永不 auto            | ``test_immersive_p3p6`` |
| D30 | observer 覆盖 immersive               | ``test_immersive_p3p6`` |
| D31 | 一键降档停 auto                       | ``test_immersive_p3p6`` |
| D32 | opaque 下 auto 仍入 Undo/apply        | ``test_immersive_p3p6`` PreviewHost |
| D33 | 无 toast 时 Undo 可用                 | ``test_save_host`` SoftHygieneCommand |

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
from src.backend.experience.attachments import build_attachment_snapshot  # noqa: E402
from src.backend.experience.context_bus import ExperienceContext  # noqa: E402
from src.backend.experience.ocr_skill import build_ocr_suggestion  # noqa: E402
from src.backend.experience.proactive import (  # noqa: E402
    MUTE_PERMANENT,
    MuteState,
    evaluate_ambient,
    make_mute,
)
from src.backend.experience.soft_autopilot import SOFT_RULE_IDS  # noqa: E402
from src.backend.experience.suggestions import p2_resources  # noqa: E402
from src.backend.experience.voice_skill import build_voice_metrics  # noqa: E402


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
# D26 / D27 / D28 - A3 ①② companion Ambient (v4.66 P4)
# ---------------------------------------------------------------------------


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


if __name__ == "__main__":
    unittest.main()
