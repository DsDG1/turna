"""P3–P6 immersive full-auto, opacity, precog, adversarial D29–D33."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import MagicMock

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))


def _settings(**kw):
    from src.application.settings import Settings

    s = Settings()
    for k, v in kw.items():
        setattr(s, k, v)
    return s


class ImmersivePolicyTest(unittest.TestCase):
    def test_immersive_full_auto_default(self):
        from src.backend.experience.policy import resolve_policy

        p = resolve_policy(_settings(experience_mode="immersive"))
        self.assertTrue(p.allow_full_auto_apply)
        self.assertTrue(p.runtime_opaque)
        self.assertTrue(p.allow_autonomous_write)

    def test_full_auto_off_switch(self):
        from src.backend.experience.policy import resolve_policy

        p = resolve_policy(
            _settings(
                experience_mode="immersive",
                experience_immersive_full_auto=False,
            )
        )
        self.assertFalse(p.allow_full_auto_apply)
        self.assertFalse(p.allow_autonomous_write)
        # opacity can still be on
        self.assertTrue(p.runtime_opaque)

    def test_d31_demote_stops_auto(self):
        from src.application.presence_mode import demote_to_copilot
        from src.backend.experience.policy import resolve_policy

        s = _settings(experience_mode="immersive")
        self.assertTrue(resolve_policy(s).allow_full_auto_apply)
        demote_to_copilot(s)
        self.assertFalse(resolve_policy(s).allow_full_auto_apply)


class AutoApplyDenyTest(unittest.TestCase):
    def test_d29_deny_b(self):
        from src.backend.experience.auto_apply import (
            is_auto_apply_allowed,
            is_denied_immersive,
        )
        from src.backend.experience.policy import resolve_policy

        self.assertTrue(is_denied_immersive("git.push"))
        self.assertTrue(is_denied_immersive("publish.outbound"))
        p = resolve_policy(_settings(experience_mode="immersive"))
        self.assertFalse(is_auto_apply_allowed("git.push", p))
        self.assertTrue(is_auto_apply_allowed("soft.preview_hygiene", p))

    def test_d30_observer_covers(self):
        from src.backend.experience.auto_apply import is_auto_apply_allowed
        from src.backend.experience.policy import resolve_policy

        p = resolve_policy(
            _settings(
                experience_mode="observer",
                experience_immersive_full_auto=True,
            )
        )
        self.assertFalse(p.allow_full_auto_apply)
        self.assertFalse(is_auto_apply_allowed("lesson.fill_empty", p))

    def test_can_dispatch_denies_b(self):
        from src.backend.experience.actions import ActionSpec
        from src.backend.experience.policy import can_dispatch, resolve_policy

        p = resolve_policy(_settings(experience_mode="immersive"))
        spec = ActionSpec("git.push", "push", needs_confirm=True, dangerous=True)
        ok, reason = can_dispatch(spec, p)
        self.assertFalse(ok)
        self.assertIn("禁区", reason)


class AutoConfirmScopeTest(unittest.TestCase):
    def test_g20_safe_question_auto_yes(self):
        from src.application.ui_guard import auto_confirm_scope, safe_question

        with auto_confirm_scope(opaque=True):
            self.assertTrue(safe_question(None, "t", "x", default_yes=False))

    def test_d32_preview_auto_applies(self):
        from src.application.ui_guard import auto_confirm_scope
        from tests._qtapp import _App

        _App.get()
        from src.widgets.preview_host import PreviewHost

        host = PreviewHost()
        applied = []

        def apply_fn():
            applied.append(1)

        with auto_confirm_scope(opaque=True):
            host.offer(title="t", summary="s", apply_fn=apply_fn)
        self.assertEqual(applied, [1])
        self.assertFalse(host.isVisible())

    def test_r2_token_survives_scope_for_async_offer(self):
        """Async path: offer after auto_confirm_scope ends still auto-applies."""
        from src.backend.experience.auto_apply import (
            bind_auto_apply_token,
            issue_auto_apply_token,
        )
        from src.application.ui_guard import auto_confirm_scope
        from tests._qtapp import _App

        _App.get()
        from PySide6.QtWidgets import QMainWindow

        from src.widgets.preview_host import PreviewHost

        win = QMainWindow()
        preview = PreviewHost(win)
        win.setCentralWidget(preview)
        applied = []

        token = issue_auto_apply_token("soft.preview_hygiene", opaque=True)
        bind_auto_apply_token(win, token)
        with auto_confirm_scope(opaque=True, token=token):
            pass  # dispatch frame ends
        # Later async completion:
        preview.offer(title="t", summary="s", apply_fn=lambda: applied.append(1))
        self.assertEqual(applied, [1])
        self.assertFalse(preview.isVisible())

    def test_r2_demote_invalidates_pending_token(self):
        """After demote, host token must not auto-apply."""
        from src.application.presence_mode import demote_to_copilot
        from src.backend.experience.auto_apply import (
            bind_auto_apply_token,
            issue_auto_apply_token,
        )
        from tests._qtapp import _App

        _App.get()
        from PySide6.QtWidgets import QMainWindow

        from src.widgets.preview_host import PreviewHost

        win = QMainWindow()
        preview = PreviewHost(win)
        win.setCentralWidget(preview)
        applied = []

        token = issue_auto_apply_token("lesson.fill_empty", opaque=True)
        bind_auto_apply_token(win, token)
        self.assertTrue(token.still_valid())

        demote_to_copilot(_settings(experience_mode="immersive"), host=win)
        self.assertFalse(token.still_valid())

        preview.offer(title="t", summary="s", apply_fn=lambda: applied.append(1))
        self.assertEqual(applied, [])
        # Not auto-applied: apply_fn retained for human confirm.
        # (has_pending also requires isVisible, which needs a shown ancestor.)
        self.assertIsNotNone(preview._apply_fn)

    def test_r2_auto_apply_failure_not_swallowed_metrics(self):
        from src.backend.experience.auto_apply import (
            bind_auto_apply_token,
            ensure_audit_ring,
            issue_auto_apply_token,
        )
        from src.backend.experience.metrics import ExperienceMetrics
        from tests._qtapp import _App

        _App.get()
        from PySide6.QtWidgets import QMainWindow

        from src.widgets.preview_host import PreviewHost

        win = QMainWindow()
        win.experience_metrics = ExperienceMetrics()
        ensure_audit_ring(win)
        preview = PreviewHost(win)
        win.setCentralWidget(preview)

        token = issue_auto_apply_token("soft.preview_hygiene", opaque=True)
        bind_auto_apply_token(win, token)

        def boom():
            raise RuntimeError("apply failed")

        preview.offer(title="t", summary="s", apply_fn=boom)
        self.assertEqual(win.experience_metrics.snapshot()["auto"]["failed"], 1)


class PrecogTest(unittest.TestCase):
    def test_refresh_hit_miss(self):
        from src.backend.experience.precognition import (
            PrecogCache,
            refresh_local_precog,
        )

        c = PrecogCache()
        r1 = refresh_local_precog(
            c,
            empty_lessons=["a"],
            quality_by_section={"s": 0.2},
            budget_ok=True,
        )
        self.assertEqual(r1, "miss")
        r2 = refresh_local_precog(
            c,
            empty_lessons=["a"],
            quality_by_section={"s": 0.2},
            budget_ok=True,
        )
        self.assertEqual(r2, "hit")
        self.assertGreaterEqual(c.hits, 1)

    def test_budget_skip(self):
        from src.backend.experience.precognition import PrecogCache, refresh_local_precog

        c = PrecogCache()
        self.assertEqual(
            refresh_local_precog(c, budget_ok=False),
            "skip_budget",
        )


class AuditRingTest(unittest.TestCase):
    def test_record_and_format(self):
        from src.backend.experience.auto_apply import (
            format_audit_lines,
            make_audit_ring,
            record_audit,
        )

        ring = make_audit_ring()
        record_audit(ring, "soft.preview_hygiene", count=3)
        lines = format_audit_lines(ring)
        self.assertTrue(any("soft.preview_hygiene" in x for x in lines))


class SetCAutoApplyTest(unittest.TestCase):
    """v4.69: set C tightening — dangerous subset auto-applies under immersive.

    G17' invariants: B∩C=∅, C⊆DANGEROUS_ACTION_IDS, course.outline_shells∉C.
    G18' behavior : C ids auto under immersive; non-C dangerous → confirm.
    """

    _C_IDS = (
        "lesson.regenerate",
        "lesson.batch_regenerate",
        "unit.regenerate",
        "unit.batch_regenerate",
        "lesson.batch_set_template",
    )

    def test_g17_prime_invariants(self):
        from src.backend.experience.auto_apply import (
            AUTO_APPLY_DANGEROUS_WHEN_IMMERSIVE as C,
            IMMERSIVE_ABSOLUTE_DENY_ACTIONS as B,
            deny_and_auto_disjoint,
        )
        from src.backend.experience.actions import DANGEROUS_ACTION_IDS

        # B ∩ C == ∅
        self.assertTrue(B.isdisjoint(C))
        # C ⊆ DANGEROUS_ACTION_IDS
        self.assertTrue(C <= DANGEROUS_ACTION_IDS)
        # course.outline_shells strictly excluded from C (true subset)
        self.assertNotIn("course.outline_shells", C)
        # combined guard helper still truthful
        self.assertTrue(deny_and_auto_disjoint())

    def test_g18_prime_c_auto_under_immersive(self):
        from src.backend.experience.auto_apply import is_auto_apply_allowed
        from src.backend.experience.policy import resolve_policy

        p = resolve_policy(_settings(experience_mode="immersive"))
        for aid in self._C_IDS:
            self.assertTrue(
                is_auto_apply_allowed(aid, p),
                f"{aid} should auto-apply under immersive (C member)",
            )

    def test_g18_prime_non_c_dangerous_confirms_under_immersive(self):
        """course.outline_shells is dangerous but NOT in C → no auto, still dispatches."""
        from src.backend.experience.auto_apply import is_auto_apply_allowed
        from src.backend.experience.actions import get_action
        from src.backend.experience.policy import can_dispatch, resolve_policy

        p = resolve_policy(_settings(experience_mode="immersive"))
        self.assertFalse(is_auto_apply_allowed("course.outline_shells", p))
        spec = get_action("course.outline_shells")
        ok, _ = can_dispatch(spec, p)
        self.assertTrue(ok)  # dispatches but must confirm (not auto)

    def test_observer_denies_all_dangerous(self):
        """Observer mode: zero AI writes — all 6 dangerous dispatches denied."""
        from src.backend.experience.actions import DANGEROUS_ACTION_IDS, get_action
        from src.backend.experience.policy import can_dispatch, resolve_policy

        p = resolve_policy(_settings(experience_mode="observer"))
        for aid in sorted(DANGEROUS_ACTION_IDS):
            spec = get_action(aid)
            ok, _ = can_dispatch(spec, p)
            self.assertFalse(ok, f"observer must deny dangerous {aid}")


if __name__ == "__main__":
    unittest.main()
