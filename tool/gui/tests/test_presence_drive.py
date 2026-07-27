"""F3 silent drive: immersive auto-dispatch of allowlisted ambient/precog skills."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.application.settings import Settings
from src.backend.experience.policy import resolve_policy


def _policy(mode: str = "immersive"):
    s = Settings(experience_mode=mode)
    return resolve_policy(s)


class PresenceDriveTest(unittest.TestCase):
    def test_allowlist(self) -> None:
        from src.application.presence_drive import is_silent_drive_action

        self.assertTrue(is_silent_drive_action("lesson.fill_empty"))
        self.assertTrue(is_silent_drive_action("soft.preview_hygiene"))
        self.assertFalse(is_silent_drive_action("git.push"))
        self.assertFalse(is_silent_drive_action("publish.outbound"))
        self.assertFalse(is_silent_drive_action("section.edit"))

    def test_copilot_no_drive(self) -> None:
        from src.application.presence_drive import maybe_silent_drive_proposals

        host = SimpleNamespace(
            _presence_drive_seen=set(),
            experience_metrics=None,
            statusBar=lambda: None,
        )
        with patch(
            "src.application.experience_dispatch.dispatch_experience_action"
        ) as disp:
            n = maybe_silent_drive_proposals(
                host,
                [
                    SimpleNamespace(
                        action_id="lesson.fill_empty",
                        scope={"first_lesson_id": "L1"},
                        title="fill",
                        id="x",
                    )
                ],
                _policy("copilot"),
            )
            self.assertEqual(n, 0)
            disp.assert_not_called()

    def test_immersive_dispatches_once(self) -> None:
        from src.application.presence_drive import maybe_silent_drive_proposals

        host = SimpleNamespace(
            _presence_drive_seen=set(),
            experience_metrics=MagicMock(),
            statusBar=lambda: MagicMock(showMessage=MagicMock()),
            _immersive_audit_ring=None,
        )
        prop = SimpleNamespace(
            action_id="lesson.fill_empty",
            scope={"first_lesson_id": "L1"},
            title="fill L1",
            id="p1",
        )
        with patch(
            "src.application.experience_dispatch.dispatch_experience_action"
        ) as disp:
            n1 = maybe_silent_drive_proposals(host, [prop], _policy("immersive"))
            n2 = maybe_silent_drive_proposals(host, [prop], _policy("immersive"))
            self.assertEqual(n1, 1)
            self.assertEqual(n2, 0)  # throttled
            self.assertEqual(disp.call_count, 1)

    def test_n3_two_per_tick_and_clear_seen(self) -> None:
        from src.application.presence_drive import (
            clear_drive_seen,
            maybe_silent_drive_proposals,
        )

        host = SimpleNamespace(
            _presence_drive_seen=set(),
            experience_metrics=None,
            statusBar=lambda: None,
        )
        props = [
            SimpleNamespace(
                action_id="lesson.fill_empty",
                scope={"first_lesson_id": "L1"},
                title="f",
                id="a",
            ),
            SimpleNamespace(
                action_id="soft.preview_hygiene",
                scope={},
                title="s",
                id="b",
            ),
            SimpleNamespace(
                action_id="resource.fill_stubs",
                scope={},
                title="r",
                id="c",
            ),
        ]
        with patch(
            "src.application.experience_dispatch.dispatch_experience_action"
        ) as disp:
            n = maybe_silent_drive_proposals(host, props, _policy("immersive"))
            self.assertEqual(n, 2)
            self.assertEqual(disp.call_count, 2)
            clear_drive_seen(host)
            n2 = maybe_silent_drive_proposals(host, props[:1], _policy("immersive"))
            self.assertEqual(n2, 1)

    def test_p0b_demote_clear_drive_allows_again(self) -> None:
        from src.application.presence_drive import (
            clear_drive_seen,
            maybe_silent_drive_proposals,
        )

        host = SimpleNamespace(
            _presence_drive_seen=set(),
            experience_metrics=None,
            statusBar=lambda: MagicMock(showMessage=MagicMock()),
        )
        prop = SimpleNamespace(
            action_id="lesson.fill_empty",
            scope={"first_lesson_id": "L1"},
            title="f",
            id="x",
        )
        with patch(
            "src.application.experience_dispatch.dispatch_experience_action"
        ) as disp:
            self.assertEqual(
                maybe_silent_drive_proposals(host, [prop], _policy("immersive")), 1
            )
            self.assertEqual(
                maybe_silent_drive_proposals(host, [prop], _policy("immersive")), 0
            )
            clear_drive_seen(host)
            self.assertEqual(
                maybe_silent_drive_proposals(host, [prop], _policy("immersive")), 1
            )
            self.assertEqual(disp.call_count, 2)

    def test_precog_builds_fill_prop(self) -> None:
        from src.application.presence_drive import maybe_silent_drive_precog
        from src.backend.experience.precognition import PrecogCache

        cache = PrecogCache()
        cache.empty_lesson_ids = ("empty-1",)
        cache.soft_fix_count = 0
        host = SimpleNamespace(
            _precog_cache=cache,
            _presence_drive_seen=set(),
            experience_metrics=None,
            statusBar=lambda: None,
        )
        with patch(
            "src.application.experience_dispatch.dispatch_experience_action"
        ) as disp:
            n = maybe_silent_drive_precog(host, _policy("immersive"))
            self.assertEqual(n, 1)
            disp.assert_called_once()
            payload = disp.call_args[0][1]
            self.assertEqual(payload["action_id"], "lesson.fill_empty")


if __name__ == "__main__":
    unittest.main()
