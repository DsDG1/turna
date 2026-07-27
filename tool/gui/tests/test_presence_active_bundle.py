"""P2 active-bundle: campaign auto-enqueue + policy helpers (headless)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))


class CampaignAutoEnqueueTest(unittest.TestCase):
    def _host(self, *, mode: str = "active", items=None, offered=None):
        host = SimpleNamespace(
            course_dir=Path("/tmp/p2-course"),
            _settings_obj=SimpleNamespace(
                experience_mode=mode,
                experience_soft_autopilot=False,
                experience_ambient_live=False,
                experience_defer_resurface=False,
                experience_allow_dangerous_skills=False,
                experience_llm_intent=False,
                experience_goal_enabled=False,
                experience_daily_ai_budget=0,
            ),
            _campaign_auto_offered_for=offered,
            experience=SimpleNamespace(
                context=SimpleNamespace(
                    quality_by_section={"s1": 0.2},
                    empty_lessons=["l-empty"],
                )
            ),
            adapter=SimpleNamespace(sections=[{"id": "s1", "name": "S1"}]),
            experience_metrics=MagicMock(),
            statusBar=MagicMock(return_value=MagicMock()),
        )
        if items is not None:
            # force campaign_items_for_host via patch in tests
            host._force_items = items
        return host

    def test_skips_when_copilot(self) -> None:
        from src.application.presence_mode import maybe_auto_enqueue_campaign

        host = self._host(mode="copilot")
        with patch(
            "src.application.presence_mode.campaign_items_for_host",
            return_value=[{"kind": "lesson", "id": "x"}],
        ):
            self.assertFalse(maybe_auto_enqueue_campaign(host))

    def test_offers_once_headless(self) -> None:
        from src.application.presence_mode import maybe_auto_enqueue_campaign

        host = self._host(mode="active")
        items = [{"kind": "lesson", "id": "l1", "title": "空课"}]
        with patch(
            "src.application.presence_mode.campaign_items_for_host",
            return_value=items,
        ), patch(
            "src.application.ui_guard.is_headless_ui", return_value=True
        ), patch(
            "src.application.experience_handlers.quality.handle_quality_campaign"
        ) as handle:
            self.assertTrue(maybe_auto_enqueue_campaign(host))
            handle.assert_not_called()
            self.assertEqual(
                host._campaign_auto_offered_for, str(host.course_dir)
            )
            # second call no-op
            self.assertFalse(maybe_auto_enqueue_campaign(host))

    def test_skips_when_no_items(self) -> None:
        from src.application.presence_mode import maybe_auto_enqueue_campaign

        host = self._host(mode="active")
        with patch(
            "src.application.presence_mode.campaign_items_for_host",
            return_value=[],
        ):
            self.assertFalse(maybe_auto_enqueue_campaign(host))
            self.assertIsNone(
                getattr(host, "_campaign_auto_offered_for", None)
            )

    def test_observer_no_campaign_auto(self) -> None:
        from src.backend.experience.policy import resolve_policy

        s = SimpleNamespace(
            experience_mode="observer",
            experience_soft_autopilot=True,
            experience_ambient_live=True,
            experience_defer_resurface=True,
            experience_allow_dangerous_skills=True,
            experience_llm_intent=True,
            experience_goal_enabled=True,
            experience_daily_ai_budget=0,
        )
        p = resolve_policy(s)
        self.assertFalse(p.allow_campaign_auto)
        self.assertFalse(p.allow_soft)
        self.assertFalse(p.allow_ambient_live)


if __name__ == "__main__":
    unittest.main()
