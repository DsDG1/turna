"""C-07 policy.py — single source of truth for Experience dispatch gating.

Covers ``resolve_policy`` + ``can_dispatch`` and
``is_dangerous_skill_allowed`` (owned by the policy module).
Default-safe semantics must not change: observer 三零, dangerous/soft
default off.
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))


def _make_settings(**kw):
    from src.application.settings import Settings

    base = Settings()
    for k, v in kw.items():
        setattr(base, k, v)
    return base


class _DangerousSpec:
    """Minimal ActionSpec stand-in with a dangerous flag (registry has none yet)."""

    action_id = "test.dangerous"
    title = "危险测试"
    implemented = True
    needs_confirm = True
    dangerous = True


def _spec(action_id, *, needs_confirm=True, dangerous=False):
    from src.backend.experience.actions import ActionSpec

    return ActionSpec(
        action_id, action_id, implemented=True, needs_confirm=needs_confirm, dangerous=dangerous
    )


class PresenceModeHelpersTests(unittest.TestCase):
    """P1 pure helpers: demote + immersive confirm predicate."""

    def test_demote_to_copilot_changes_and_idempotent(self):
        from src.application.presence_mode import demote_to_copilot

        s = _make_settings(experience_mode="immersive")
        self.assertTrue(demote_to_copilot(s))
        self.assertEqual(s.experience_mode, "copilot")
        self.assertFalse(demote_to_copilot(s))
        s2 = _make_settings(experience_mode="active")
        self.assertTrue(demote_to_copilot(s2))
        self.assertEqual(s2.experience_mode, "copilot")
        s3 = _make_settings(experience_mode="observer")
        self.assertTrue(demote_to_copilot(s3))
        self.assertEqual(s3.experience_mode, "copilot")

    def test_should_confirm_immersive_enter(self):
        from src.application.presence_mode import should_confirm_immersive_enter

        self.assertTrue(should_confirm_immersive_enter("copilot", "immersive"))
        self.assertTrue(should_confirm_immersive_enter("active", "immersive"))
        self.assertTrue(should_confirm_immersive_enter("observer", "immersive"))
        self.assertFalse(should_confirm_immersive_enter("immersive", "immersive"))
        self.assertFalse(should_confirm_immersive_enter("copilot", "active"))
        self.assertFalse(should_confirm_immersive_enter("immersive", "copilot"))


class ResolvePolicyTests(unittest.TestCase):
    def test_defaults_all_off_copilot(self):
        from src.backend.experience.policy import resolve_policy

        p = resolve_policy(_make_settings())
        self.assertEqual(p.mode, "copilot")
        self.assertEqual(p.presence_level, 1)
        self.assertFalse(p.allow_dangerous)
        self.assertFalse(p.allow_soft)
        self.assertFalse(p.allow_autonomous_write)
        self.assertFalse(p.scope_cross_section)
        self.assertFalse(p.is_observer)
        # placeholders checked per-mode in presence_level / bundle tests
        if p.mode in ("copilot", "observer", "active"):
            self.assertFalse(p.allow_full_auto_apply)
            self.assertFalse(p.runtime_opaque)

    def test_observer_zero_side_effects_even_with_flags_on(self):
        from src.backend.experience.policy import resolve_policy

        p = resolve_policy(
            _make_settings(
                experience_mode="observer",
                experience_allow_dangerous_skills=True,
                experience_soft_autopilot=True,
            )
        )
        self.assertTrue(p.is_observer)
        self.assertFalse(p.allow_dangerous)
        self.assertFalse(p.allow_soft)

    def test_copilot_flags_respected(self):
        from src.backend.experience.policy import resolve_policy

        p = resolve_policy(
            _make_settings(
                experience_mode="copilot",
                experience_allow_dangerous_skills=True,
                experience_soft_autopilot=True,
            )
        )
        self.assertTrue(p.allow_dangerous)
        self.assertTrue(p.allow_soft)
        self.assertTrue(p.scope_cross_section)

    def test_copilot_flags_off(self):
        from src.backend.experience.policy import resolve_policy

        p = resolve_policy(_make_settings(experience_mode="copilot"))
        self.assertFalse(p.allow_dangerous)
        self.assertFalse(p.allow_soft)

    def test_invalid_mode_falls_back_to_copilot(self):
        from src.backend.experience.policy import resolve_policy

        p = resolve_policy(_make_settings(experience_mode="nonsense"))
        self.assertEqual(p.mode, "copilot")
        self.assertEqual(p.presence_level, 1)

    def test_presence_level_four_modes(self):
        """P1: observer/copilot/active/immersive map to presence_level 0–3."""
        from src.backend.experience.policy import (
            PRESENCE_LEVEL_BY_MODE,
            normalize_experience_mode,
            resolve_policy,
        )

        for mode, level in PRESENCE_LEVEL_BY_MODE.items():
            with self.subTest(mode=mode):
                self.assertEqual(normalize_experience_mode(mode), mode)
                p = resolve_policy(_make_settings(experience_mode=mode))
                self.assertEqual(p.mode, mode)
                self.assertEqual(p.presence_level, level)
                self.assertEqual(p.is_observer, level == 0)
                if mode in ("immersive",):
                    self.assertTrue(p.allow_full_auto_apply)
                    self.assertTrue(p.runtime_opaque)
                    self.assertTrue(p.allow_autonomous_write)
                else:
                    self.assertFalse(p.allow_full_auto_apply)
                    self.assertFalse(p.runtime_opaque)
                    self.assertFalse(p.allow_autonomous_write)

    def test_active_bundle_ors_presence_flags(self):
        """P2: active/immersive enable Soft/live/defer/campaign without settings."""
        from src.backend.experience.policy import resolve_policy

        for mode in ("active", "immersive"):
            with self.subTest(mode=mode):
                p = resolve_policy(_make_settings(experience_mode=mode))
                self.assertFalse(p.is_observer)
                self.assertTrue(p.is_active_bundle)
                self.assertTrue(p.allow_soft)
                self.assertTrue(p.allow_ambient_live)
                self.assertTrue(p.allow_defer_resurface)
                self.assertTrue(p.allow_campaign_auto)
                if mode == "active":
                    self.assertFalse(p.allow_full_auto_apply)
                    self.assertFalse(p.runtime_opaque)
                    self.assertFalse(p.allow_autonomous_write)
                    self.assertFalse(p.allow_dangerous)
                else:
                    # immersive P3 defaults: full auto + opaque
                    self.assertTrue(p.allow_full_auto_apply)
                    self.assertTrue(p.runtime_opaque)
                    self.assertTrue(p.allow_autonomous_write)
                    self.assertTrue(p.allow_dangerous)

    def test_copilot_bundle_off_unless_flags(self):
        from src.backend.experience.policy import resolve_policy

        p = resolve_policy(_make_settings(experience_mode="copilot"))
        self.assertFalse(p.is_active_bundle)
        self.assertFalse(p.allow_soft)
        self.assertFalse(p.allow_ambient_live)
        self.assertFalse(p.allow_campaign_auto)
        p2 = resolve_policy(
            _make_settings(
                experience_mode="copilot",
                experience_soft_autopilot=True,
                experience_ambient_live=True,
            )
        )
        self.assertTrue(p2.allow_soft)
        self.assertTrue(p2.allow_ambient_live)
        self.assertFalse(p2.allow_campaign_auto)

    def test_observer_covers_immersive_flags(self):
        """Observer still forces 三零 even if flags claim otherwise."""
        from src.backend.experience.policy import resolve_policy

        p = resolve_policy(
            _make_settings(
                experience_mode="observer",
                experience_soft_autopilot=True,
                experience_allow_dangerous_skills=True,
                experience_llm_intent=True,
                experience_goal_enabled=True,
            )
        )
        self.assertEqual(p.presence_level, 0)
        self.assertTrue(p.is_observer)
        self.assertFalse(p.allow_soft)
        self.assertFalse(p.allow_dangerous)
        self.assertFalse(p.allow_llm_intent)
        self.assertFalse(p.allow_goal)

    def test_no_settings_degrades_safely(self):
        from src.backend.experience.policy import resolve_policy

        p = resolve_policy(None)
        self.assertEqual(p.mode, "copilot")
        self.assertEqual(p.presence_level, 1)
        self.assertFalse(p.allow_dangerous)
        self.assertFalse(p.allow_soft)

    def test_missing_attr_does_not_raise(self):
        from src.backend.experience.policy import resolve_policy

        # A bare object with no experience_* attrs must not raise.
        p = resolve_policy(object())
        self.assertEqual(p.mode, "copilot")
        self.assertFalse(p.allow_dangerous)

    def test_budget_matrix(self):
        from src.backend.experience.policy import resolve_policy

        # limit 0 → off even with huge usage
        p = resolve_policy(_make_settings(), usage_today={"requests": 999})
        self.assertEqual(p.budget_limit, 0)
        self.assertFalse(p.budget_exceeded)
        self.assertTrue(p.allow_ai_skill)

        p = resolve_policy(
            _make_settings(experience_daily_ai_budget=5),
            usage_today={"requests": 5},
        )
        self.assertTrue(p.budget_exceeded)
        self.assertFalse(p.allow_ai_skill)
        self.assertEqual(p.budget_used, 5)
        self.assertEqual(p.budget_remaining, 0)

        p = resolve_policy(
            _make_settings(experience_daily_ai_budget=10),
            usage_today={"requests": 3},
        )
        self.assertFalse(p.budget_exceeded)
        self.assertTrue(p.allow_ai_skill)
        self.assertEqual(p.budget_remaining, 7)

        # missing usage → fail-open
        p = resolve_policy(
            _make_settings(experience_daily_ai_budget=1), usage_today=None
        )
        self.assertFalse(p.budget_exceeded)
        self.assertTrue(p.allow_ai_skill)


class CanDispatchTests(unittest.TestCase):
    def test_app_builtins_always_pass_observer(self):
        from src.backend.experience.policy import can_dispatch, resolve_policy

        p = resolve_policy(_make_settings(experience_mode="observer"))
        for aid in ("app.save", "app.undo", "app.why", "app.help", "app.pin"):
            ok, reason = can_dispatch(_spec(aid, needs_confirm=False), p)
            self.assertTrue(ok, aid)
            self.assertEqual(reason, "")

    def test_dangerous_denied_when_locked(self):
        from src.backend.experience.policy import can_dispatch, resolve_policy

        p = resolve_policy(_make_settings(experience_mode="copilot"))
        ok, reason = can_dispatch(_DangerousSpec(), p)
        self.assertFalse(ok)
        self.assertIn("危险技能", reason)

    def test_dangerous_denied_in_observer_even_if_flag_on(self):
        from src.backend.experience.policy import can_dispatch, resolve_policy

        p = resolve_policy(
            _make_settings(experience_mode="observer", experience_allow_dangerous_skills=True)
        )
        ok, reason = can_dispatch(_DangerousSpec(), p)
        self.assertFalse(ok)

    def test_dangerous_allowed_when_unlocked_copilot(self):
        from src.backend.experience.policy import can_dispatch, resolve_policy

        p = resolve_policy(
            _make_settings(experience_mode="copilot", experience_allow_dangerous_skills=True)
        )
        ok, reason = can_dispatch(_DangerousSpec(), p)
        self.assertTrue(ok)
        self.assertEqual(reason, "")

    def test_write_action_denied_in_observer(self):
        from src.backend.experience.policy import can_dispatch, resolve_policy

        p = resolve_policy(_make_settings(experience_mode="observer"))
        ok, reason = can_dispatch(_spec("lesson.fill_empty", needs_confirm=True), p)
        self.assertFalse(ok)
        self.assertIn("观察者", reason)

    def test_readonly_action_passes_in_observer(self):
        from src.backend.experience.policy import can_dispatch, resolve_policy

        p = resolve_policy(_make_settings(experience_mode="observer"))
        ok, _ = can_dispatch(_spec("resource.open_hygiene", needs_confirm=False), p)
        self.assertTrue(ok)

    def test_write_action_passes_in_copilot(self):
        from src.backend.experience.policy import can_dispatch, resolve_policy

        p = resolve_policy(_make_settings(experience_mode="copilot"))
        ok, _ = can_dispatch(_spec("lesson.fill_empty", needs_confirm=True), p)
        self.assertTrue(ok)

    def test_none_spec_denied(self):
        from src.backend.experience.policy import can_dispatch, resolve_policy

        p = resolve_policy(_make_settings())
        ok, _ = can_dispatch(None, p)
        self.assertFalse(ok)

    def test_budget_blocks_ai_write_not_app_or_soft(self):
        from src.backend.experience.policy import can_dispatch, resolve_policy

        p = resolve_policy(
            _make_settings(experience_daily_ai_budget=2),
            usage_today={"requests": 2},
        )
        ok, reason = can_dispatch(_spec("lesson.fill_empty", needs_confirm=True), p)
        self.assertFalse(ok)
        self.assertIn("配额", reason)
        ok_app, _ = can_dispatch(_spec("app.save", needs_confirm=False), p)
        self.assertTrue(ok_app)
        ok_soft, _ = can_dispatch(
            _spec("soft.preview_hygiene", needs_confirm=True), p
        )
        self.assertTrue(ok_soft)
        ok_ro, _ = can_dispatch(
            _spec("resource.open_hygiene", needs_confirm=False), p
        )
        self.assertTrue(ok_ro)


class DelegationTests(unittest.TestCase):
    """policy.is_dangerous_skill_allowed derives from resolve_policy."""

    def test_dangerous_helper_delegates(self):
        from src.backend.experience.policy import is_dangerous_skill_allowed

        self.assertFalse(
            is_dangerous_skill_allowed(
                _make_settings(experience_mode="observer", experience_allow_dangerous_skills=True)
            )
        )
        self.assertFalse(is_dangerous_skill_allowed(_make_settings(experience_mode="copilot")))
        self.assertTrue(
            is_dangerous_skill_allowed(
                _make_settings(experience_mode="copilot", experience_allow_dangerous_skills=True)
            )
        )


if __name__ == "__main__":
    unittest.main()