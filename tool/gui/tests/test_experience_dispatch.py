"""M4: Experience handler registry coverage + dispatch funnel."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest import mock

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.application.experience_dispatch import (  # noqa: E402
    HANDLER_OPTIONAL_ACTIONS,
    HANDLERS,
    dispatch_experience_action,
)
from src.backend.experience.actions import ACTIONS  # noqa: E402


class HandlerRegistryCoverageTest(unittest.TestCase):
    def test_implemented_actions_have_handler_or_optional(self) -> None:
        missing = []
        for action_id, spec in ACTIONS.items():
            if not spec.implemented:
                continue
            if action_id in HANDLER_OPTIONAL_ACTIONS:
                continue
            if action_id not in HANDLERS:
                missing.append(action_id)
        self.assertEqual(
            missing,
            [],
            f"implemented actions missing HANDLERS: {missing}",
        )

    def test_handlers_are_callable(self) -> None:
        for action_id, fn in HANDLERS.items():
            self.assertTrue(callable(fn), action_id)


class _FakeBar:
    def __init__(self) -> None:
        self.messages: list[str] = []

    def showMessage(self, msg: str, timeout: int = 0) -> None:
        self.messages.append(msg)


class _FakeMetrics:
    def __init__(self) -> None:
        self.events: list[tuple[str, str]] = []

    def inc_suggestion(self, action: str, kind: str) -> None:
        self.events.append((action, kind))


class _FakeHost:
    def __init__(self) -> None:
        self._bar = _FakeBar()
        self.experience_metrics = _FakeMetrics()
        self._settings_obj = None
        self.calls: list[str] = []
        self._workshop_opened = False
        self._resources_filter = None

    def statusBar(self) -> _FakeBar:
        return self._bar

    def _resolve_experience_policy(self, *, action_id: str | None = None):
        from src.backend.experience.policy import resolve_policy

        return resolve_policy(None, action_id=action_id)

    def _on_workshop(self) -> None:
        self.calls.append("workshop")
        self._workshop_opened = True

    def _on_resources(self, initial_filter: str = "") -> None:
        self.calls.append(f"resources:{initial_filter}")
        self._resources_filter = initial_filter

    def _experience_fill_empty(self, scope: dict) -> None:
        self.calls.append(f"fill_empty:{scope}")

    def _experience_validate_and_fix(self) -> None:
        self.calls.append("validate_fix")


class DispatchFunnelTest(unittest.TestCase):
    def test_nav_handler_attachment_opens_workshop(self) -> None:
        host = _FakeHost()
        with mock.patch(
            "src.application.experience_dispatch.telemetry.record_event"
        ):
            dispatch_experience_action(
                host,
                {"action_id": "attachment.open_in_workshop", "scope": {}},
            )
        self.assertTrue(host._workshop_opened)
        self.assertIn(("attachment.open_in_workshop", "accepted"), host.experience_metrics.events)

    def test_resource_open_hygiene_passes_filter(self) -> None:
        host = _FakeHost()
        with mock.patch(
            "src.application.experience_dispatch.telemetry.record_event"
        ):
            dispatch_experience_action(
                host,
                {
                    "action_id": "resource.open_hygiene",
                    "scope": {"filter": "重复"},
                },
            )
        self.assertEqual(host._resources_filter, "重复")

    def test_unknown_action_status(self) -> None:
        host = _FakeHost()
        with mock.patch(
            "src.application.experience_dispatch.telemetry.record_event"
        ):
            dispatch_experience_action(
                host, {"action_id": "no.such.action", "scope": {}}
            )
        self.assertTrue(any("建议已记录" in m for m in host._bar.messages))

    def test_item_rewrite_guidance(self) -> None:
        host = _FakeHost()
        with mock.patch(
            "src.application.experience_dispatch.telemetry.record_event"
        ):
            dispatch_experience_action(
                host, {"action_id": "item.rewrite", "scope": {}}
            )
        self.assertTrue(any("教师模式" in m for m in host._bar.messages))

    def test_fill_empty_invokes_handler_module(self) -> None:
        host = _FakeHost()
        with mock.patch(
            "src.application.experience_dispatch.telemetry.record_event"
        ), mock.patch(
            "src.application.experience_handlers.fill.handle_fill_empty"
        ) as m:
            dispatch_experience_action(
                host,
                {
                    "action_id": "lesson.fill_empty",
                    "scope": {"section_id": "s1", "first_lesson_id": "l1"},
                },
            )
        m.assert_called_once()
        args = m.call_args[0]
        self.assertIs(args[0], host)
        self.assertEqual(args[1].get("first_lesson_id"), "l1")


if __name__ == "__main__":
    unittest.main()
